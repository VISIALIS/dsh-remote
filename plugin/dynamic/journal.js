/**
 * LA LECTURE D'UN JOURNAL DE SESSION.
 *
 * POURQUOI CE FICHIER EXISTE. Ces règles vivaient au milieu d'un fichier de
 * 1 637 lignes. Elles sont PURES (hors la lecture du fichier lui-même) et
 * portent des décisions mesurées — la concaténation des trames zstd, la
 * recherche binaire de la fin d'une trame, le résumé d'un en-tête — donc elles
 * s'éprouvent avec des charges utiles réelles.
 *
 * Un journal de session DSH (`session.v3.jsonl.zstd`) est une CONCATENATION de
 * trames zstd indépendantes, une par écriture. `zlib.zstdDecompressSync` n'en
 * décode qu'UNE et s'arrête silencieusement : l'utiliser seul ne rendrait que la
 * première écriture du journal. Il faut donc avancer trame par trame.
 *
 * La fin d'une trame est trouvée par recherche binaire : une tranche qui décode
 * n'est pas forcément exactement une trame (zstd ignore ce qui suit), on cherche
 * donc la plus petite longueur qui décode encore.
 */

import { open, stat } from 'node:fs/promises'
import zlib from 'node:zlib'

// Borne de lecture : un journal de session peut être énorme ; on refuse de
// décompresser sans limite plutôt que de faire enfler la mémoire du harness.
//
// ELLE VIT ICI, ET PAS DANS `host.js` : elle n'était utilisée QUE par le
// décodage du journal, et l'oublier lors de l'extraction a fait lever
// `decoderJournal` — attrapé par le test de concaténation des trames, qui est
// exactement le genre d'erreur qu'on ne voit qu'en lisant un vrai journal.
export const PLAFOND_DECOMPRESSION = 64 * 1024 * 1024

// Un journal de session DSH (`session.v3.jsonl.zstd`) est une CONCATENATION de
// trames zstd indépendantes, une par écriture. `zlib.zstdDecompressSync` n'en
// décode qu'UNE et s'arrête silencieusement : l'utiliser seul ne rendrait que la
// première écriture du journal. Il faut donc avancer trame par trame.
//
// La fin d'une trame est trouvée par recherche binaire : une tranche qui décode
// n'est pas forcément exactement une trame (zstd ignore ce qui suit), on cherche
// donc la plus petite longueur qui décode encore.
const MAGIE_ZSTD = Buffer.from([0x28, 0xb5, 0x2f, 0xfd])
const MAGIE_ZSTD_SKIPPABLE = Buffer.from([0x50, 0x2a, 0x4d, 0x18])

export function decoderUneTrame(tampon, depart, maximum) {
  const fin = Math.min(tampon.length, depart + maximum)
  let bas = 1
  let haut = fin - depart
  let meilleur = -1
  while (bas <= haut) {
    const milieu = (bas + haut) >> 1
    try {
      zlib.zstdDecompressSync(tampon.subarray(depart, depart + milieu))
      meilleur = milieu
      haut = milieu - 1
    } catch {
      bas = milieu + 1
    }
  }
  if (meilleur === -1) return null
  return { sortie: zlib.zstdDecompressSync(tampon.subarray(depart, depart + meilleur)), consomme: meilleur }
}

/**
 * Décode un journal complet et rend ses lignes JSON.
 * @param {Buffer} tampon - contenu brut du fichier.
 * @param {number} depart - décalage de la première trame à décoder.
 * @returns {{lignes: string[], offset: number, tronque: boolean}}
 */
export function decoderJournal(tampon, depart = 0) {
  const lignes = []
  let offset = depart
  let rendus = 0
  let tronque = false
  while (offset < tampon.length) {
    const magie = tampon.subarray(offset, offset + 4)
    if (!magie.equals(MAGIE_ZSTD) && !magie.equals(MAGIE_ZSTD_SKIPPABLE)) {
      // Trame interrompue par une écriture en cours : on s'arrête proprement.
      tronque = true
      break
    }
    if (rendus > PLAFOND_DECOMPRESSION) {
      tronque = true
      break
    }
    let resultat
    try {
      resultat = decoderUneTrame(tampon, offset, PLAFOND_DECOMPRESSION)
    } catch {
      resultat = null
    }
    if (resultat === null) {
      tronque = true
      break
    }
    rendus += resultat.sortie.length
    offset += resultat.consomme
    const texte = resultat.sortie.toString('utf8')
    for (const ligne of texte.split('\n')) if (ligne.length > 0) lignes.push(ligne)
  }
  return { lignes, offset, tronque }
}

/** Analyse une ligne JSONL sans jamais lever : une ligne illisible est ignorée. */
export function analyserLigne(ligne) {
  try {
    const valeur = JSON.parse(ligne)
    if (valeur === null || typeof valeur !== 'object') return null
    return valeur
  } catch {
    return null
  }
}

/**
 * Décode les trames qui COMMENCENT dans les `tailleMax` derniers octets.
 *
 * POURQUOI PAR LA FIN. Un journal de session grossit sans fin : le relire en
 * entier toutes les 750 ms pour un flux temps réel coûterait de plus en plus
 * cher, jusqu'à épuiser la mémoire du harness sur une session longue. Comme un
 * journal est append-only, tout ce qui précède la fin est déjà connu du client :
 * seuls les derniers octets peuvent porter du nouveau.
 *
 * Les écritures font au plus quelques kilo-octets ; 64 Kio offrent une marge
 * confortable, et la fonction dit `borneAtteinte` quand elle n'a pas pu
 * remonter assez loin — le client peut alors redemander une page complète
 * plutôt que de subir une lacune silencieuse.
 *
 * @param {string} fichier
 * @param {number} taille
 * @param {number} tailleMax
 * @returns {Promise<{enregistrements: object[], debut: number, borneAtteinte: boolean}>}
 */
export async function decoderFinDeJournal(fichier, taille, tailleMax) {
  const debutFenetre = Math.max(0, taille - tailleMax)
  const poignee = await open(fichier, 'r')
  let tampon
  try {
    const longueur = taille - debutFenetre
    tampon = Buffer.allocUnsafe(longueur)
    let lu = 0
    while (lu < longueur) {
      const morceau = await poignee.read(tampon, lu, longueur - lu, debutFenetre + lu)
      if (morceau.bytesRead === 0) break
      lu += morceau.bytesRead
    }
    if (lu < longueur) tampon = tampon.subarray(0, lu)
  } finally {
    await poignee.close()
  }

  const minimum = Math.max(0, taille - tampon.length)
  const marques = []
  let curseur = 0
  for (;;) {
    const trouve = tampon.indexOf(MAGIE_ZSTD, curseur)
    if (trouve === -1) break
    marques.push(trouve)
    curseur = trouve + 1
    if (marques.length > 20000) break
  }
  if (marques.length === 0) {
    // Aucune trame atteignable dans la fenêtre : l'appelant doit élargir.
    return { enregistrements: [], debut: taille, borneAtteinte: true }
  }

  // La dernière marque peut être un faux positif à l'intérieur d'une charge
  // compressée. On retient la plus GRANDE marque qui décode réellement : tout ce
  // qui la suit n'est alors qu'une queue tronquée, pas une lacune.
  for (let index = marques.length - 1; index >= 0; index--) {
    const depart = marques[index]
    const { lignes, offset, tronque } = decoderJournal(tampon, depart)
    if (lignes.length === 0) continue
    const enregistrements = []
    for (const ligne of lignes) {
      const analyse = analyserLigne(ligne)
      if (analyse !== null) enregistrements.push(analyse)
    }
    if (enregistrements.length === 0) continue
    const debut = minimum + depart
    // `tronque` signale une trame interrompue en cours d'écriture : c'est normal
    // sur un journal vivant, et ce n'est PAS une lacune. On ne le remonte donc pas
    // comme telle — seule une fenêtre trop courte empêche de servir le client.
    return { enregistrements, debut: minimum + offset, borneAtteinte: false }
  }
  return { enregistrements: [], debut: taille, borneAtteinte: true }
}

// ─────────────────────────────────────────────────────────────────────────────
// Découverte des sessions
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Reconstruit, pour l'AFFICHAGE SEULEMENT, un chemin depuis un nom de dossier.
 *
 * DSH encode `/chemin/projet-externe` en `--chemin-projet-externe--`
 * en remplaçant chaque `/` par `-`. Cette transformation n'est PAS inversible :
 * le tiret de `dsh-plugins` est indiscernable du séparateur de `Projets/`. On ne
 * s'en sert donc jamais pour lire quoi que ce soit — c'est `cwd`, conservé en
 * clair par DSH dans l'enregistrement d'en-tête, qui fait foi. Ce champ n'existe
 * que pour donner un libellé lisible à un client qui n'a pas encore lu le journal.
 * @param {string} nom - nom du dossier de projet.
 * @returns {string}
 */
export function cheminIndicatif(nom) {
  const nu = nom.startsWith('--') ? nom.slice(2) : nom
  const sansFin = nu.endsWith('--') ? nu.slice(0, -2) : nu
  return '/' + sansFin.replace(/-/g, '/')
}

/** Extrait les faits d'un en-tête et d'un journal déjà analysés. */
export function resumer(enregistrements) {
  let entete = null
  let titre = null
  let dernier = null
  let dernierSeq = -1
  for (const enregistrement of enregistrements) {
    const type = enregistrement.type
    if (type === 'session' && entete === null) entete = enregistrement
    else if (type === 'session/title') {
      const valeur = enregistrement.data?.title
      if (typeof valeur === 'string' && valeur.length > 0) titre = valeur
    }
    if (typeof enregistrement.seq === 'number' && enregistrement.seq > dernierSeq) dernierSeq = enregistrement.seq
    if (typeof enregistrement.time === 'number') dernier = enregistrement.time
  }
  return {
    id: typeof entete?.id === 'string' ? entete.id : null,
    cwd: typeof entete?.cwd === 'string' ? entete.cwd : null,
    creeLe: typeof entete?.createdAt === 'number' ? entete.createdAt : null,
    preset: typeof entete?.agentPreset === 'string' ? entete.agentPreset : null,
    profondeurDelegation: typeof entete?.delegationDepth === 'number' ? entete.delegationDepth : null,
    seme: entete?.isSeeded === true,
    titre,
    dernierEvenementLe: dernier,
    dernierSeq,
    nbEnregistrements: enregistrements.length,
  }
}
