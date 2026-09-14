/**
 * LA LECTURE D'UN JOURNAL DE SESSION.
 *
 * POURQUOI CE FICHIER EXISTE. Ces règles vivaient au milieu d'un fichier de
 * 1 637 lignes. Elles sont PURES (hors la lecture du fichier lui-même) et
 * portent des décisions mesurées — la concaténation des trames zstd, la lecture
 * structurelle de la fin d'une trame, le résumé d'un en-tête — donc elles
 * s'éprouvent avec des charges utiles réelles.
 *
 * Un journal de session DSH (`session.v3.jsonl.zstd`) est une CONCATENATION de
 * trames zstd indépendantes, une par écriture. `zlib.zstdDecompressSync` n'en
 * décode qu'UNE et s'arrête silencieusement : l'utiliser seul ne rendrait que la
 * première écriture du journal. Il faut donc avancer trame par trame.
 *
 * LA FIN D'UNE TRAME SE LIT DANS SA STRUCTURE, PAS EN LA DÉCOMPRESSANT. Le
 * décodeur de Node ne signale pas qu'une trame est incomplète : sur Node 22.19 —
 * celui sous lequel tourne le harnais ici — une tranche tronquée rend ce qu'elle
 * a, sans lever (1 octet → chaîne vide ; 90 % d'une trame de 200 Kio → 131 072
 * octets rendus, aucune erreur). Chercher la fin par essais (« la plus petite
 * tranche qui décode ») ne peut donc pas marcher là où le harnais tourne :
 * mesuré, `decoderJournal` rendait ZÉRO ligne sur un journal de trois trames,
 * tandis que le même code passait sur Node 26.8.2, où la tranche tronquée lève
 * `Z_BUF_ERROR`. La structure, elle, ne dépend d'aucune version : en-tête
 * (magie, descripteur, fenêtre, dictionnaire, taille de contenu) puis blocs
 * (en-tête de 3 octets, charge du bloc). C'est l'approche du harnais pour ses
 * propres journaux (`scanZstdFrames`, `@deepseek-ai/dsh-session-persistence-jsonl`).
 */

import { open, stat } from 'node:fs/promises'
import { join } from 'node:path'
import zlib from 'node:zlib'

// Borne de lecture : un journal de session peut être énorme ; on refuse de
// décompresser sans limite plutôt que de faire enfler la mémoire du harness.
//
// ELLE VIT ICI, ET PAS DANS `host.js` : elle n'était utilisée QUE par le
// décodage du journal, et l'oublier lors de l'extraction a fait lever
// `decoderJournal` — attrapé par le test de concaténation des trames, qui est
// exactement le genre d'erreur qu'on ne voit qu'en lisant un vrai journal.
export const PLAFOND_DECOMPRESSION = 64 * 1024 * 1024

// La magie sert DEUX FOIS : en Buffer pour `indexOf` (repérer un départ de trame
// candidat dans une fenêtre), et en entier pour la lecture structurelle.
const MAGIE_ZSTD = Buffer.from([0x28, 0xb5, 0x2f, 0xfd])
const MAGIE_ZSTD_ENTIER = MAGIE_ZSTD.readUInt32LE(0)
// Trames « à ignorer » : la spécification en réserve la plage 0x184D2A50-5F.
const MAGIE_IGNORABLE_MIN = 0x184d2a50
const MAGIE_IGNORABLE_MAX = 0x184d2a5f

/**
 * Longueur totale de la trame qui commence à `depart`, LUE DANS SA STRUCTURE.
 *
 * Aucune décompression n'est faite ici : on lit l'en-tête de trame, puis on
 * saute les blocs d'après leurs en-têtes. C'est la seule façon de connaître la
 * fin d'une trame sans dépendre du comportement — variable selon la version de
 * Node — du décodeur face à une entrée tronquée.
 *
 * @param {Buffer} tampon
 * @param {number} depart
 * @returns {number | null} la longueur en octets, ou `null` si les octets
 *   présents ne suffisent pas à lire une trame complète (trame en cours
 *   d'écriture, ou début qui n'est pas une trame).
 */
export function longueurDeTrame(tampon, depart) {
  if (tampon.length - depart < 4) return null
  const magie = tampon.readUInt32LE(depart)

  // Trame à ignorer : magie, taille de charge sur 4 octets, puis la charge.
  if (magie >= MAGIE_IGNORABLE_MIN && magie <= MAGIE_IGNORABLE_MAX) {
    if (tampon.length - depart < 8) return null
    const fin = depart + 8 + tampon.readUInt32LE(depart + 4)
    return fin <= tampon.length ? fin - depart : null
  }
  if (magie !== MAGIE_ZSTD_ENTIER) return null

  let curseur = depart + 4
  // Journal coupé juste après la magie : rien à lire, et rien à lever.
  if (curseur >= tampon.length) return null
  const descripteur = tampon.readUInt8(curseur)
  curseur += 1
  // Bits réservés : une trame qui les porte n'est pas du zstd valide.
  if ((descripteur & 0x18) !== 0) return null
  const drapeauTaille = descripteur >>> 6
  const segmentUnique = (descripteur & 0x20) !== 0
  const somme = (descripteur & 0x04) !== 0
  const drapeauDictionnaire = descripteur & 0x03
  const octetsDictionnaire = drapeauDictionnaire === 3 ? 4 : drapeauDictionnaire
  // `Frame_Content_Size` : absent, ou 1 octet quand la trame est un segment unique.
  const octetsTaille = drapeauTaille === 0 ? (segmentUnique ? 1 : 0) : 1 << drapeauTaille
  const resteEnTete = (segmentUnique ? 0 : 1) + octetsDictionnaire + octetsTaille
  if (tampon.length - curseur < resteEnTete) return null
  curseur += resteEnTete

  for (;;) {
    if (tampon.length - curseur < 3) return null
    const enteteBloc = tampon.readUIntLE(curseur, 3)
    curseur += 3
    const dernierBloc = (enteteBloc & 1) !== 0
    const typeBloc = (enteteBloc >>> 1) & 3
    const tailleBloc = enteteBloc >>> 3
    if (typeBloc === 3) return null // type réservé
    // Un bloc RLE n'occupe qu'un octet : `tailleBloc` est sa taille DÉCOMPRESSÉE.
    const charge = typeBloc === 1 ? 1 : tailleBloc
    if (tampon.length - curseur < charge) return null
    curseur += charge
    if (dernierBloc) break
  }

  if (somme) {
    if (tampon.length - curseur < 4) return null
    curseur += 4
  }
  return curseur - depart
}

/**
 * Décode un journal complet et rend ses lignes JSON.
 * @param {Buffer} tampon - contenu brut du fichier.
 * @param {number} depart - décalage de la première trame à décoder.
 * @returns {{lignes: string[], offset: number, tronque: boolean}} `offset` est
 *   l'endroit où reprendre : le début de la trame incomplète, ou la fin du
 *   tampon. `tronque` dit qu'il reste des octets non lus à cet endroit.
 */
export function decoderJournal(tampon, depart = 0) {
  const lignes = []
  let offset = depart
  let rendus = 0
  let tronque = false
  while (offset < tampon.length) {
    const longueur = longueurDeTrame(tampon, offset)
    if (longueur === null) {
      // Trame interrompue par une écriture en cours, ou octets qui ne sont pas
      // une trame : on s'arrête proprement, sans rien inventer.
      tronque = true
      break
    }
    if (rendus >= PLAFOND_DECOMPRESSION) {
      tronque = true
      break
    }
    let sortie
    try {
      // `maxOutputLength` borne la mémoire d'une SEULE trame : le plafond
      // ci-dessus ne compte que ce qui a déjà été rendu. Une trame complète mais
      // illisible (somme de contrôle fausse, corruption) lève ici.
      sortie = zlib.zstdDecompressSync(tampon.subarray(offset, offset + longueur), {
        maxOutputLength: PLAFOND_DECOMPRESSION,
      })
    } catch {
      tronque = true
      break
    }
    rendus += sortie.length
    offset += longueur
    // Une trame à ignorer rend zéro octet : elle est sautée, et sa place dans le
    // compte des octets est tenue par `longueur`.
    const texte = sortie.toString('utf8')
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

/**
 * LA MISE EN FORME D'UNE ENTRÉE DE SESSION — le contrat avec le client.
 *
 * POURQUOI ELLE EST ICI, ET POURQUOI ELLE EST PURE. Elle était construite en
 * ligne dans la route : sa forme n'était donc vérifiable qu'avec un vrai harness
 * et un vrai client. Elle l'est maintenant par un test, et c'est ce qui permet
 * de tenir le CONTRAT — le client Swift décode exactement ces clés, et un
 * fixture versionné est éprouvé des deux côtés.
 *
 * DEUX ORIGINES, UN SEUL OBJET. Les champs de gauche viennent du SYSTÈME DE
 * FICHIERS (taille, date, chemins), ceux de droite du JOURNAL (identifiant,
 * titre, date du dernier événement). Le résumé est ÉTALÉ (`...faits`) et non
 * imbriqué sous une clé `resume` : c'est la forme que le client attend, et
 * l'imbriquer a déjà été une erreur — un test Swift a lu « (inconnu) » là où il
 * attendait un identifiant.
 *
 * @param {{projet: string, dossier: string, fichier: string, octets: number,
 *          modifieLe: number, vivante: boolean, statut: string | null,
 *          attendReponse: boolean, faits: object}} partie
 * @returns {object}
 */
export function entreeDeSession(partie) {
  return {
    projet: partie.projet,
    cwdIndicatif: cheminIndicatif(partie.projet),
    dossier: partie.dossier,
    fichier: partie.fichier,
    octets: partie.octets,
    modifieLe: partie.modifieLe,
    vivante: partie.vivante,
    statut: partie.statut,
    attendReponse: partie.attendReponse,
    ...partie.faits,
  }
}

/**
 * LES NOMS DE JOURNAL, DANS L'ORDRE OÙ ON LES ESSAIE.
 *
 * POURQUOI DEUX NOMS. DSH a écrit ses journaux sous `session.jsonl.zstd`, puis
 * sous `session.v3.jsonl.zstd`. Mesuré sur cette machine : **118 sessions au nom
 * v3, 39 au nom historique** — et le plugin ne cherchait QUE le v3. Les 39
 * autres n'existaient donc pas pour l'application, alors que leur journal se
 * décode parfaitement (6 356 enregistrements lus sur la première essayée, en-tête
 * complet, cwd et titre présents).
 *
 * Le v3 d'abord : c'est le nom courant, et s'il est là c'est lui qui fait foi.
 */
export const NOMS_DE_JOURNAL = ['session.v3.jsonl.zstd', 'session.jsonl.zstd']

/**
 * Le journal d'une session, ou `null` si aucun nom n'existe.
 *
 * @param {string} dossier
 * @returns {Promise<string | null>}
 */
export async function trouverJournal(dossier) {
  for (const nom of NOMS_DE_JOURNAL) {
    const fichier = join(dossier, nom)
    try {
      await stat(fichier)
      return fichier
    } catch {
      // Nom absent : on essaie le suivant. Un dossier sans aucun journal est
      // simplement ignoré par l'appelant.
    }
  }
  return null
}
