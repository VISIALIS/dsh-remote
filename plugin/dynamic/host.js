// Moitié HÔTE du plugin dsh-remote.
//
// Ce fichier n'est PAS un module « corps de fonction » : c'est un module ES
// ordinaire, chargé par le loader d'un PROFIL DSH (`~/.dsh/profiles/<profil>/`),
// donc durable — il survit à un redémarrage, contrairement à un plugin dynamique
// posé par `cordis_define`.
//
// OBJET
// Donner à l'application Swift native « DSH Remote » (macOS + iOS) une surface
// JSON versionnée, lisible par une machine, pour observer et piloter l'instance
// DSH qui tourne sur le Mac. Il ne remplace pas l'interface web : il expose à un
// client natif ce que l'interface web ne sait dire qu'à un navigateur.
//
// POURQUOI CE PLUGIN EXISTE (constats mesurés, pas déduits — voir README)
//   1. DSH ne se lie qu'à la boucle locale ; `--host 0.0.0.0` est refusé.
//   2. `tailscale serve` publie déjà l'instance sur le tailnet en relayant vers
//      127.0.0.1:3080. Aucun port supplémentaire n'est donc nécessaire.
//   3. Une route NOMMÉE (`webServer.register`) est dispatchée avant le repli de
//      l'interface : elle n'est pas soumise à l'authentification navigateur.
//      C'est à ce plugin d'apporter la sienne.
//   4. `tailscale serve` termine la connexion et re-proxifie en boucle locale :
//      `socket.remoteAddress` vaut TOUJOURS 127.0.0.1, et l'en-tête
//      `Tailscale-User-Login` est FALSIFIABLE par tout processus local. Ni l'un
//      ni l'autre ne peut servir de contrôle d'accès. Seul un secret partagé le
//      peut — d'où le jeton porteur ci-dessous.
//
// SÉCURITÉ (RÈGLE #0 d'AGENTS.md)
//   - Aucune surface réseau nouvelle : on enregistre des routes sur le serveur
//     DSH existant, on n'ouvre aucun port, on ne crée aucun serveur annexe.
//   - Toute route vérifie le jeton AVANT de lire quoi que ce soit. Une requête
//     non authentifiée ne reçoit qu'une réponse fixe et ne déclenche aucune E/S.
//   - Comparaison du jeton à temps constant (`timingSafeEqual`), longueurs
//     égalisées au préalable.
//   - Aucun `Origin` n'est toléré : un client natif n'en envoie pas, un
//     navigateur en envoie toujours. C'est la barrière anti-DNS-rebinding et
//     anti-CSRF, et elle est refusée AVANT le test du jeton.
//   - Aucune donnée de session n'est journalisée : les lignes de journal ne
//     portent qu'une méthode, une route, un code et un identifiant de session.
//   - Le jeton n'est jamais réécrit dans un journal. Il est affiché UNE fois, à
//     sa création, dans le terminal de l'utilisateur — exception assumée et
//     documentée dans le README.
//
// API INTERNES DE DSH UTILISÉES (aucune garantie de stabilité)
//   `ctx.webServer.register` / `.registerUpgrade` — routes nommées
//   `ctx.credentials.readRecord` / `.modifyRecord` — coffre du harness
//   `ctx.get('sessionController')`, `ctx.get('agents')` — état vivant
// Chacune est lue par `ctx.get(...)` puis testée ; le plugin se dégrade au lieu
// de lever une exception au chargement.

import { createHash, randomBytes, timingSafeEqual } from 'node:crypto'
import { open, readFile, readdir, stat } from 'node:fs/promises'
import { join } from 'node:path'
import zlib from 'node:zlib'

export const name = 'dsh-remote'

// Services requis par le plugin pour enregistrer ses routes et gérer son jeton.
export const inject = ['webServer', 'credentials']

const PREFIX = '/dsh-remote'
const VERSION_PROTOCOLE = 1

// Bornes de lecture. Un journal de session peut être énorme ; on refuse de
// décompresser sans limite plutôt que de faire enfler la mémoire du harness.
const PLAFOND_DECOMPRESSION = 64 * 1024 * 1024
const PLAFOND_FICHIER = 512 * 1024 * 1024
const TAILLE_PAGE_DEFAUT = 200
const TAILLE_PAGE_MAX = 2000
const TTL_CACHE_MS = 2000

// Types d'enregistrements porteurs de contenu de modèle ou de requête : jamais
// renvoyés par défaut. Le client doit les demander explicitement (`inclure`).
const TYPES_VOLUMINEUX = new Set([
  'request/header',
  'request/context',
  'system/message',
  'session/title-llm-request',
])

const CLE_JETON = 'dsh-remote/device-token'

// ─────────────────────────────────────────────────────────────────────────────
// Lecture d'un journal de session
// ─────────────────────────────────────────────────────────────────────────────

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

function decoderUneTrame(tampon, depart, maximum) {
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
function decoderJournal(tampon, depart = 0) {
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
function analyserLigne(ligne) {
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
async function decoderFinDeJournal(fichier, taille, tailleMax) {
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
function cheminIndicatif(nom) {
  const nu = nom.startsWith('--') ? nom.slice(2) : nom
  const sansFin = nu.endsWith('--') ? nu.slice(0, -2) : nu
  return '/' + sansFin.replace(/-/g, '/')
}

/** Extrait les faits d'un en-tête et d'un journal déjà analysés. */
function resumer(enregistrements) {
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

// ─────────────────────────────────────────────────────────────────────────────
// WebSocket minimal (RFC 6455)
//
// Écrire une centaine de lignes ici plutôt qu'ajouter une dépendance : la
// RÈGLE #0 fait de chaque dépendance une surface d'attaque supplémentaire dans
// un processus sans bac à sable. Seuls le texte, le ping, le pong et la
// fermeture sont implémentés, ce qui suffit à un flux d'événements serveur vers
// client.
// ─────────────────────────────────────────────────────────────────────────────

const CLE_MAGIQUE_WS = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'

function trameTexte(texte) {
  const charge = Buffer.from(texte, 'utf8')
  const longueur = charge.length
  let entete
  if (longueur < 126) {
    entete = Buffer.alloc(2)
    entete[1] = longueur
  } else if (longueur < 65536) {
    entete = Buffer.alloc(4)
    entete[1] = 126
    entete.writeUInt16BE(longueur, 2)
  } else {
    entete = Buffer.alloc(10)
    entete[1] = 127
    entete.writeBigUInt64BE(BigInt(longueur), 2)
  }
  entete[0] = 0x81
  return Buffer.concat([entete, charge])
}

function trameFermeture(code = 1000) {
  const charge = Buffer.alloc(2)
  charge.writeUInt16BE(code, 0)
  return Buffer.concat([Buffer.from([0x88, 0x02]), charge])
}

function tramePong(charge) {
  if (charge.length >= 126) return Buffer.from([0x8a, 0x00])
  return Buffer.concat([Buffer.from([0x8a, charge.length]), charge])
}

/**
 * Décode les trames reçues d'un client. Le client DOIT masquer ses trames.
 * @returns {{restant: Buffer, trames: Array<{fin: boolean, opcode: number, charge: Buffer}>}}
 */
function lireTrames(restant) {
  const trames = []
  let tampon = restant
  for (;;) {
    if (tampon.length < 2) break
    const fin = (tampon[0] & 0x80) !== 0
    const opcode = tampon[0] & 0x0f
    const masque = (tampon[1] & 0x80) !== 0
    let longueur = tampon[1] & 0x7f
    let curseur = 2
    if (longueur === 126) {
      if (tampon.length < 4) break
      longueur = tampon.readUInt16BE(2)
      curseur = 4
    } else if (longueur === 127) {
      if (tampon.length < 10) break
      const grand = tampon.readBigUInt64BE(2)
      if (grand > BigInt(PLAFOND_DECOMPRESSION)) return { restant: Buffer.alloc(0), trames, trop: true }
      longueur = Number(grand)
      curseur = 10
    }
    const debutMasque = curseur
    if (masque) curseur += 4
    if (tampon.length < curseur + longueur) break
    let charge = tampon.subarray(curseur, curseur + longueur)
    if (masque) {
      const cle = tampon.subarray(debutMasque, debutMasque + 4)
      const clair = Buffer.allocUnsafe(longueur)
      for (let i = 0; i < longueur; i++) clair[i] = charge[i] ^ cle[i & 3]
      charge = clair
    }
    trames.push({ fin, opcode, charge: Buffer.from(charge) })
    tampon = tampon.subarray(curseur + longueur)
  }
  return { restant: Buffer.from(tampon), trames, trop: false }
}

// ─────────────────────────────────────────────────────────────────────────────
// Plugin
// ─────────────────────────────────────────────────────────────────────────────

export function apply(ctx, config) {
  const options = config ?? {}
  const journaliser = options.journaliser !== false

  const webServer = ctx.get('webServer') ?? ctx.webServer
  if (webServer === undefined || webServer === null || typeof webServer.register !== 'function') {
    console.log('[dsh-remote] ECHEC: service webServer indisponible, aucune route enregistree')
    return
  }

  const sessions = ctx.get('sessions')
  const agents = ctx.get('agents')
  // Seul service qui sache ADRESSER un prompt a une session par son identifiant.
  // Lu par `ctx.get` puis teste : sans lui, la lecture continue de fonctionner et
  // seule l'ecriture se declare indisponible.
  const controller = ctx.get('sessionController')

  // Le harness ne publie pas de service de chemins : `dsh-home-paths` est une
  // bibliotheque de fonctions, pas un service Cordis. On refait donc la
  // resolution documentee (variable `DSH_HOME`, sinon `~/.dsh`). Les chemins ne
  // sont jamais journalises ni renvoyes : seule la liste des sessions l'est.
  const racineSessions = () => {
    const configure =
      typeof process.env.DSH_HOME === 'string' && process.env.DSH_HOME.length > 0
        ? process.env.DSH_HOME
        : join(process.env.HOME ?? '/tmp', '.dsh')
    return join(configure, 'sessions')
  }

  // Aucune API publique n'expose la version du harness au contexte d'un plugin.
  // On prefere `null` a une valeur inventee.
  const versionHarness = () => {
    const declaree = process.env.DSH_VERSION
    return typeof declaree === 'string' && declaree.length > 0 ? declaree : null
  }

  // ── Jeton ──────────────────────────────────────────────────────────────────
  let jeton = null

  const coffre = () => {
    const credentials = ctx.get('credentials') ?? ctx.credentials
    if (credentials === undefined || credentials === null) return null
    if (typeof credentials.readRecord !== 'function' || typeof credentials.modifyRecord !== 'function') return null
    return credentials
  }

  const chargerJeton = async () => {
    const credentials = coffre()
    if (credentials === null) {
      console.log('[dsh-remote] coffre d identifiants indisponible: le plugin ne peut pas gerer de jeton')
      return null
    }
    const existant = await credentials.readRecord(CLE_JETON)
    if (existant !== undefined && existant !== null && existant.kind === 'grant') {
      const valeur = existant.payload?.token
      if (typeof valeur === 'string' && valeur.length >= 32) return valeur
    }
    const nouveau = randomBytes(32).toString('base64url')
    await credentials.modifyRecord(CLE_JETON, async () => ({ kind: 'grant', payload: { token: nouveau, creeLe: Date.now() } }))
    // Affichage UNIQUE, dans le terminal de l'utilisateur, a la creation.
    // Jamais reecrit ensuite, jamais journalise, jamais renvoye par une route.
    console.log('[dsh-remote] NOUVEAU JETON D APPAREIL (a saisir une fois dans l application, puis oublier) :')
    console.log('[dsh-remote] ' + nouveau)
    return nouveau
  }

  const jetonValide = (presente) => {
    if (jeton === null) return false
    if (typeof presente !== 'string' || presente.length === 0) return false
    const attendu = Buffer.from(jeton, 'utf8')
    const recu = Buffer.from(presente, 'utf8')
    if (attendu.length !== recu.length) {
      // Comparaison a longueur egale malgre tout, pour ne pas fuiter la taille.
      timingSafeEqual(attendu, attendu)
      return false
    }
    return timingSafeEqual(attendu, recu)
  }

  // ── Cache des journaux ─────────────────────────────────────────────────────
  // Cle : chemin absolu. Valeur : faits resolus + etat du fichier au moment de
  // la lecture. Un journal est append-only : tant que taille et mtime n'ont pas
  // bouge, le resulat est reutilisable.
  const cache = new Map()
  let dernierNettoyage = 0

  const nettoyerCache = () => {
    const maintenant = Date.now()
    if (maintenant - dernierNettoyage < 60000) return
    dernierNettoyage = maintenant
    for (const [cle, entree] of cache) if (maintenant - entree.vuLe > 300000) cache.delete(cle)
  }

  /**
   * Liste les sessions presentes sur disque, de la plus recente a la plus ancienne.
   * @param {{limite?: number}} [demande]
   */
  const listerSessions = async (demande = {}) => {
    nettoyerCache()
    const racine = racineSessions()
    const limite = Number.isInteger(demande.limite) && demande.limite > 0 ? Math.min(demande.limite, 500) : 200
    let projets
    try {
      projets = await readdir(racine, { withFileTypes: true })
    } catch (erreur) {
      return { racine, sessions: [], erreur: 'repertoire de sessions illisible: ' + (erreur.code ?? erreur.message) }
    }
    const resultats = []
    for (const projet of projets) {
      if (!projet.isDirectory()) continue
      const dossierProjet = join(racine, projet.name)
      let sousDossiers
      try {
        sousDossiers = await readdir(dossierProjet, { withFileTypes: true })
      } catch {
        continue
      }
      for (const sous of sousDossiers) {
        if (!sous.isDirectory()) continue
        const dossier = join(dossierProjet, sous.name)
        const fichier = join(dossier, 'session.v3.jsonl.zstd')
        let information
        try {
          information = await stat(fichier)
        } catch {
          continue
        }
        const cle = fichier
        const connu = cache.get(cle)
        let faits
        if (connu !== undefined && connu.taille === information.size && connu.mtime === information.mtimeMs) {
          faits = connu.faits
          connu.vuLe = Date.now()
        } else if (information.size > PLAFOND_FICHIER) {
          faits = { illisible: 'journal trop volumineux (' + information.size + ' octets)' }
        } else {
          try {
            const tampon = await readFile(fichier)
            const { lignes, tronque } = decoderJournal(tampon)
            const enregistrements = []
            for (const ligne of lignes) {
              const analyse = analyserLigne(ligne)
              if (analyse !== null) enregistrements.push(analyse)
            }
            faits = resumer(enregistrements)
            faits.tronque = tronque
            cache.set(cle, { taille: information.size, mtime: information.mtimeMs, faits, vuLe: Date.now() })
          } catch (erreur) {
            faits = { illisible: 'lecture impossible: ' + (erreur.code ?? erreur.message) }
          }
        }
        resultats.push({
          projet: projet.name,
          cwdIndicatif: cheminIndicatif(projet.name),
          dossier,
          fichier,
          octets: information.size,
          modifieLe: information.mtimeMs,
          vivante: estVivante(faits?.id),
          statut: statutDe(faits?.id),
          ...faits,
        })
      }
    }
    resultats.sort((a, b) => (b.dernierEvenementLe ?? b.modifieLe) - (a.dernierEvenementLe ?? a.modifieLe))
    return { racine, total: resultats.length, sessions: resultats.slice(0, limite) }
  }

  /**
   * Statut d'une session : `en_cours` si un tour s'execute, `inactif` sinon.
   *
   * `agents.get(id).status` vaut `idle` ou `running` — c'est l'etat de cycle de
   * vie de l'agent, emis a chaque transition. On le TRANSPORTE plutot que de le
   * deduire du journal : deviner « ca travaille » en regardant si les
   * enregistrements defilent donnerait un voyant qui s'allume en retard et
   * s'eteint a tort entre deux etapes.
   *
   * Rend `null` quand la session n'est pas ouverte dans ce processus : l'etat
   * est alors INCONNU, et un client ne doit pas le confondre avec « inactif ».
   */
  const statutDe = (identifiant) => {
    if (typeof identifiant !== 'string' || identifiant.length === 0) return null
    try {
      if (agents === undefined || agents === null || typeof agents.get !== 'function') return null
      const agent = agents.get(identifiant)
      if (agent === undefined || agent === null) return null
      return agent.status === 'running' ? 'en_cours' : 'inactif'
    } catch {
      return null
    }
  }

  /** Une session est vivante si le harness la connait encore dans ce processus. */
  const estVivante = (identifiant) => {
    if (typeof identifiant !== 'string' || identifiant.length === 0) return false
    try {
      if (sessions !== undefined && sessions !== null && typeof sessions.get === 'function') {
        if (sessions.get(identifiant) !== undefined) return true
      }
    } catch {
      // le service a change de forme : on repond « inconnue » plutot que d echouer
    }
    try {
      if (agents !== undefined && agents !== null && typeof agents.roots === 'function') {
        for (const racine of agents.roots()) {
          if (racine?.session?.id === identifiant || racine?.id === identifiant) return true
        }
      }
    } catch {
      // idem
    }
    return false
  }

  /** Résout l'identifiant demandé en un chemin de journal, sans sortir de la racine. */
  const resoudreJournal = async (identifiant) => {
    if (typeof identifiant !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(identifiant)) return null
    const racine = racineSessions()
    let projets
    try {
      projets = await readdir(racine, { withFileTypes: true })
    } catch {
      return null
    }
    for (const projet of projets) {
      if (!projet.isDirectory()) continue
      const fichier = join(racine, projet.name, identifiant, 'session.v3.jsonl.zstd')
      try {
        const information = await stat(fichier)
        if (information.isFile()) return { fichier, information, projet: projet.name }
      } catch {
        continue
      }
    }
    return null
  }

  /**
   * Lit un journal et rend une page d'enregistrements.
   * @param {string} identifiant
   * @param {{depuis?: number, limite?: number, types?: string[], inclureVolumineux?: boolean}} demande
   */
  const lireSession = async (identifiant, demande = {}) => {
    const trouve = await resoudreJournal(identifiant)
    if (trouve === null) return { erreur: 'session inconnue', code: 404 }
    if (trouve.information.size > PLAFOND_FICHIER) return { erreur: 'journal trop volumineux', code: 413 }
    const tampon = await readFile(trouve.fichier)
    const { lignes, tronque } = decoderJournal(tampon)
    const tous = []
    for (const ligne of lignes) {
      const analyse = analyserLigne(ligne)
      if (analyse !== null) tous.push(analyse)
    }
    const faits = resumer(tous)
    const depuis = Number.isInteger(demande.depuis) && demande.depuis >= 0 ? demande.depuis : 0
    const limite = Number.isInteger(demande.limite) && demande.limite > 0 ? Math.min(demande.limite, TAILLE_PAGE_MAX) : TAILLE_PAGE_DEFAUT
    const veutTout = Array.isArray(demande.types) && demande.types.length > 0
    const filtre = veutTout ? new Set(demande.types) : null
    const retenus = []
    for (let index = 0; index < tous.length; index++) {
      const enregistrement = tous[index]
      if (!veutTout && TYPES_VOLUMINEUX.has(enregistrement.type)) continue
      if (filtre !== null && !filtre.has(enregistrement.type)) continue
      retenus.push({ index, enregistrement })
    }
    const page = retenus.slice(depuis, depuis + limite)
    return {
      session: {
        ...faits,
        projet: trouve.projet,
        octets: trouve.information.size,
        modifieLe: trouve.information.mtimeMs,
        vivante: estVivante(faits.id),
        statut: statutDe(faits.id),
      },
      depuis,
      limite,
      total: retenus.length,
      tronque,
      enregistrements: page.map((element) => element.enregistrement),
    }
  }

  // ── Réponses HTTP ──────────────────────────────────────────────────────────

  const envoyer = (res, code, charge) => {
    const corps = JSON.stringify(charge)
    res.writeHead(code, {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'content-length': Buffer.byteLength(corps),
    })
    res.end(corps)
  }

  const lireCorps = (req) =>
    new Promise((resolve) => {
      const morceaux = []
      let taille = 0
      req.on('data', (morceau) => {
        taille += morceau.length
        if (taille > 1024 * 1024) {
          req.destroy()
          resolve(null)
          return
        }
        morceaux.push(morceau)
      })
      req.on('end', () => {
        if (morceaux.length === 0) return resolve({})
        try {
          const valeur = JSON.parse(Buffer.concat(morceaux).toString('utf8'))
          resolve(valeur !== null && typeof valeur === 'object' ? valeur : {})
        } catch {
          resolve(null)
        }
      })
      req.on('error', () => resolve(null))
    })

  /**
   * Barrière d'accès. Rend `true` si la requête peut continuer.
   * L'ordre est délibéré : provenance, puis jeton. Aucune E/S avant.
   */
  const autoriser = (req, res) => {
    // 1. Un client natif n'envoie jamais `Origin`. Un navigateur en envoie
    //    toujours, y compris depuis une page hostile. On refuse donc tout
    //    `Origin`, avant même de regarder le jeton.
    if (req.headers.origin !== undefined) {
      envoyer(res, 403, { erreur: 'origine refusee' })
      return false
    }
    // 2. Secret partage, comparaison a temps constant.
    const entete = req.headers.authorization
    const presente = typeof entete === 'string' && entete.startsWith('Bearer ') ? entete.slice(7) : null
    if (!jetonValide(presente)) {
      res.writeHead(401, { 'content-type': 'application/json; charset=utf-8', 'www-authenticate': 'Bearer', 'cache-control': 'no-store' })
      res.end('{"erreur":"jeton requis"}')
      return false
    }
    return true
  }

  const tracer = (req, code, complement = '') => {
    if (options.journaliser === false) return
    console.log('[dsh-remote] ' + req.method + ' ' + String(req.url).split('?')[0] + ' -> ' + code + (complement.length > 0 ? ' ' + complement : ''))
  }

  const identite = (req) => {
    const valeur = req.headers['tailscale-user-login']
    return typeof valeur === 'string' && valeur.length > 0 ? valeur : null
  }

  const routes = []

  const enregistrer = (route) => {
    routes.push(webServer.register(route))
  }

  // ── GET /dsh-remote/v1/sante — poignée de main, sans donnee ────────────────
  enregistrer({
    kind: 'exact',
    path: PREFIX + '/v1/sante',
    handler: (req, res) => {
      if (!autoriser(req, res)) return tracer(req, 401)
      envoyer(res, 200, {
        protocole: VERSION_PROTOCOLE,
        nom: 'dsh-remote',
        hote: process.env.HOSTNAME ?? null,
        acces: identite(req),
        versionDsh: versionHarness(),
        capacites: {
          sessions: true,
          journal: true,
          flux: true,
          ecriture: controller !== null && typeof controller?.prompt === 'function',
          // Les approbations ne sont PAS exposees : le seam d'approbation de DSH
          // n'admet qu'un repondeur terminal par deploiement, et l'interface web
          // l'occupe deja. Repondre depuis l'iPhone exigerait de le remplacer.
          approbations: false,
        },
      })
      tracer(req, 200)
    },
  })

  const repondreListe = async (req, res, demande) => {
    // Toute erreur est convertie en reponse JSON explicite. Une exception non
    // rattrapee ici deviendrait un 400 vide, indiscernable d'une requete
    // malformee — et donc indebogable depuis le client.
    try {
      const resultat = await listerSessions(demande)
      envoyer(res, 200, { protocole: VERSION_PROTOCOLE, ...resultat })
      tracer(req, 200, resultat.total === undefined ? '' : resultat.total + ' sessions')
    } catch (erreur) {
      envoyer(res, 500, { erreur: 'listage impossible', detail: String(erreur?.message ?? erreur) })
      tracer(req, 500)
    }
  }

  enregistrer({
    kind: 'exact',
    path: PREFIX + '/v1/sessions',
    handler: (req, res) => {
      if (!autoriser(req, res)) return tracer(req, 401)
      if (req.method === 'GET') {
        repondreListe(req, res, {}).catch((erreur) => {
          envoyer(res, 500, { erreur: 'echec de listage', detail: String(erreur?.message ?? erreur) })
        })
        return
      }
      if (req.method === 'POST') {
        lireCorps(req).then((corps) => {
          if (corps === null) return envoyer(res, 400, { erreur: 'corps JSON invalide' })
          return repondreListe(req, res, corps)
        })
        return
      }
      envoyer(res, 405, { erreur: 'methode non autorisee' })
    },
  })

  enregistrer({
    kind: 'prefix',
    path: PREFIX + '/v1/session',
    handler: (req, res) => {
      if (!autoriser(req, res)) return tracer(req, 401)
      const reste = String(req.url).slice((PREFIX + '/v1/session').length)
      const segments = reste.split('/').filter((segment) => segment.length > 0)
      const identifiant = segments[0] === undefined ? '' : decodeURIComponent(segments[0])
      if (identifiant.length === 0) {
        envoyer(res, 400, { erreur: 'identifiant de session manquant' })
        return tracer(req, 400)
      }
      const action = segments[1] === undefined ? 'journal' : segments[1]

      // ── Envoyer un prompt : la SEULE route qui ecrit dans le harness ───────
      if (action === 'prompt') {
        if (req.method !== 'POST') {
          envoyer(res, 405, { erreur: 'methode non autorisee' })
          return tracer(req, 405)
        }
        // `controller?.` et non `controller.` : `ctx.get` rend `undefined` quand le
        // service est absent, et lire une propriete de `undefined` LEVE. L'exception
        // remontait au serveur web, qui la convertissait en `400` vide — ni corps,
        // ni trace, ni cause. C'est ce qui a rendu cette panne si longue a voir.
        if (typeof controller?.prompt !== 'function') {
          envoyer(res, 503, {
            erreur: 'ecriture indisponible',
            detail: 'le service sessionController n est pas monte dans cette composition',
          })
          return tracer(req, 503)
        }
        if (!estVivante(identifiant)) {
          // Un agent froid ne peut pas recevoir de prompt : le harness le dit
          // lui-meme. On le dit AVANT d'ecrire, avec la marche a suivre.
          envoyer(res, 409, {
            erreur: 'session non vivante',
            detail: "cette session n'est pas ouverte dans ce processus: ouvrez-la d'abord dans l'interface du Mac",
          })
          return tracer(req, 409)
        }
        lireCorps(req)
          .then(async (corps) => {
            if (corps === null) {
              envoyer(res, 400, { erreur: 'corps JSON invalide' })
              return
            }
            const texte = typeof corps.texte === 'string' ? corps.texte : ''
            if (texte.trim().length === 0) {
              envoyer(res, 400, { erreur: 'texte vide' })
              return
            }
            const mode = corps.mode === 'steer' ? 'steer' : 'queue'
            const valeur = await controller.prompt(
              {
                requestId: randomBytes(16).toString('hex'),
                sessionId: identifiant,
                mode,
                content: [{ type: 'text', text: texte }],
              },
              new AbortController().signal,
            )
            envoyer(res, 202, { protocole: VERSION_PROTOCOLE, accepte: valeur?.accepted === true, mode })
            // Jamais le TEXTE du prompt dans le journal : il peut contenir
            // n'importe quoi, y compris ce que l'utilisateur ne veut pas voir
            // recopie dans un terminal. Seule sa longueur est tracee.
            tracer(req, 202, 'prompt ' + mode + ', ' + texte.length + ' caracteres')
          })
          .catch((erreur) => {
            envoyer(res, 500, { erreur: 'envoi impossible', detail: String(erreur?.message ?? erreur) })
            tracer(req, 500)
          })
        return
      }

      if (req.method !== 'POST' && req.method !== 'GET') {
        envoyer(res, 405, { erreur: 'methode non autorisee' })
        return tracer(req, 405)
      }

      lireCorps(req)
        .then((corps) => {
          if (corps === null) return envoyer(res, 400, { erreur: 'corps JSON invalide' })
          return lireSession(identifiant, corps)
        })
        .then((resultat) => {
          if (resultat === undefined) return
          if (resultat.erreur !== undefined) {
            envoyer(res, resultat.code ?? 400, { erreur: resultat.erreur })
            return tracer(req, resultat.code ?? 400)
          }
          envoyer(res, 200, { protocole: VERSION_PROTOCOLE, ...resultat })
          tracer(req, 200, resultat.total + ' enregistrements')
        })
        .catch((erreur) => {
          envoyer(res, 500, { erreur: 'echec de lecture', detail: String(erreur?.message ?? erreur) })
          tracer(req, 500)
        })
    },
  })

  // ── WebSocket /dsh-remote/v1/flux — evenements d'une session, en direct ────
  //
  // PROTOCOLE. Le client ouvre, puis envoie un message JSON :
  //   { "type": "demarrer", "session": "<id>", "depuisSeq": <n|null> }
  // Le serveur repond :
  //   { "type": "base",  "session": {...}, "enregistrements": [...], "dernierSeq": n }
  //   { "type": "delta", "enregistrements": [...], "dernierSeq": n }
  //   { "type": "tronque" }   quand la fenetre de lecture n'a pas suffi
  //   { "type": "erreur", "message": "..." }
  //
  // REPRISE. `depuisSeq` evite de renvoyer ce que le client a deja : le serveur ne
  // transmet que les enregistrements dont `seq` depasse cette valeur. C'est ce qui
  // rend une reconnexion apres coupure reseau non destructive.
  //
  // Le jeton est exige en en-tete `Authorization`, jamais en parametre d'URL :
  // un parametre finit dans un journal d'acces.
  const FENETRE_FLUX_MIN = 64 * 1024
  const FENETRE_FLUX_MAX = 8 * 1024 * 1024
  const INTERVALLE_FLUX_MS = 750
  const PING_FLUX_MS = 30000
  const MAX_TAMPON_EN_ATTENTE = 4 * 1024 * 1024

  /**
   * Lit ce qui a ete ecrit apres `offset`, en elargissant la fenetre si besoin.
   *
   * La fenetre part de 64 Kio et double jusqu'a 8 Mio tant que la fin du fichier
   * ne contient aucune trame atteignable. Un journal qui n'a rien ecrit depuis
   * longtemps peut en effet avoir sa derniere ecriture loin de la fin ; sans
   * elargissement on annoncerait une lacune qui n'existe pas.
   */
  const lireDepuis = async (fichier, taille, offset) => {
    let fenetre = FENETRE_FLUX_MIN
    for (;;) {
      const lecture = await decoderFinDeJournal(fichier, taille, fenetre)
      if (!lecture.borneAtteinte) return lecture
      if (fenetre >= FENETRE_FLUX_MAX || fenetre >= taille) return lecture
      fenetre *= 2
    }
  }

  routes.push(
    webServer.registerUpgrade({
      path: PREFIX + '/v1/flux',
      handler: (req, socket) => {
        if (req.headers.origin !== undefined) {
          socket.end('HTTP/1.1 403 Forbidden\r\n\r\n')
          return tracer(req, 403)
        }
        const entete = req.headers.authorization
        const presente = typeof entete === 'string' && entete.startsWith('Bearer ') ? entete.slice(7) : null
        if (!jetonValide(presente)) {
          socket.end('HTTP/1.1 401 Unauthorized\r\n\r\n')
          return tracer(req, 401)
        }
        const cle = req.headers['sec-websocket-key']
        if (typeof cle !== 'string') {
          socket.end('HTTP/1.1 400 Bad Request\r\n\r\n')
          return tracer(req, 400)
        }
        const accept = createHash('sha1').update(cle + CLE_MAGIQUE_WS).digest('base64')
        socket.write(
          'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' +
            accept +
            '\r\n\r\n',
        )
        tracer(req, 101, 'flux ouvert')

        let restant = Buffer.alloc(0)
        let ferme = false
        let minuteur = null
        let minuteurPing = null

        const arreter = (code) => {
          if (ferme) return
          ferme = true
          if (minuteur !== null) clearInterval(minuteur)
          if (minuteurPing !== null) clearInterval(minuteurPing)
          minuteur = null
          minuteurPing = null
          try {
            socket.write(trameFermeture(code))
          } catch {
            // deja ferme
          }
          socket.end()
        }

        const envoyer = (charge) => {
          if (ferme) return
          // Client trop lent : on coupe plutot que de laisser le tampon du noyau
          // enfler jusqu'a faire enfler la memoire du harness. Le client se
          // reconnectera avec `depuisSeq` et rattrapera sans perte.
          if (socket.writableLength > MAX_TAMPON_EN_ATTENTE) return arreter(1008)
          try {
            socket.write(trameTexte(JSON.stringify(charge)))
          } catch {
            arreter(1011)
          }
        }

        // Etat du suivi, tenu par la connexion et non par une fabrique : le
        // seuil de reprise et l'offset de lecture doivent survivre a chaque tour.
        let chemin = null
        let offset = 0
        let seuilReprise = -1
        let enCours = false

        const interroger = async () => {
          if (ferme || enCours || chemin === null) return
          enCours = true
          try {
            let information
            try {
              information = await stat(chemin)
            } catch {
              return
            }
            if (information.size <= offset) return
            const lecture = await lireDepuis(chemin, information.size, offset)
            if (lecture.borneAtteinte) {
              envoyer({ type: 'tronque', message: 'fenetre de lecture insuffisante' })
              return
            }
            offset = lecture.debut
            const nouveaux = lecture.enregistrements.filter(
              (enregistrement) => typeof enregistrement.seq === 'number' && enregistrement.seq > seuilReprise,
            )
            if (nouveaux.length === 0) return
            for (const enregistrement of nouveaux) envoyer({ type: 'evenement', enregistrement })
            const dernier = nouveaux[nouveaux.length - 1].seq
            seuilReprise = dernier
            envoyer({ type: 'delta', dernierSeq: dernier })
          } catch (erreur) {
            envoyer({ type: 'erreur', message: String(erreur?.message ?? erreur) })
          } finally {
            enCours = false
          }
        }

        const demarrer = async (identifiant, depuisSeq) => {
          const trouve = await resoudreJournal(identifiant)
          if (trouve === null) {
            envoyer({ type: 'erreur', message: 'session inconnue' })
            return arreter(1008)
          }
          chemin = trouve.fichier
          seuilReprise = depuisSeq === null ? -1 : depuisSeq

          // Base : l'en-tete, le titre et les derniers enregistrements. Une session
          // peut porter des milliers d'evenements ; le client en demande davantage
          // par pages via /v1/session/<id> s'il en a besoin.
          const base = await lireDepuis(trouve.fichier, trouve.information.size, 0)
          let faits = resumer(base.enregistrements)
          if (faits.id === null) {
            // La fenetre n'a pas atteint l'en-tete : on lit le debut du fichier.
            const tampon = await readFile(trouve.fichier)
            const complet = decoderJournal(tampon)
            const tous = []
            for (const ligne of complet.lignes) {
              const analyse = analyserLigne(ligne)
              if (analyse !== null) tous.push(analyse)
            }
            faits = resumer(tous)
          }
          offset = base.debut
          const enregistrements = base.enregistrements.filter(
            (enregistrement) => typeof enregistrement.seq === 'number' && enregistrement.seq > seuilReprise,
          )
          if (enregistrements.length > 0) seuilReprise = enregistrements[enregistrements.length - 1].seq

          envoyer({
            type: 'base',
            protocole: VERSION_PROTOCOLE,
            session: faits,
            enregistrements,
            dernierSeq: seuilReprise,
          })

          if (minuteur !== null) clearInterval(minuteur)
          minuteur = setInterval(() => {
            interroger()
          }, INTERVALLE_FLUX_MS)
          if (minuteurPing === null) {
            minuteurPing = setInterval(() => {
              if (ferme) return
              try {
                socket.write(Buffer.from([0x89, 0x00]))
              } catch {
                arreter(1011)
              }
            }, PING_FLUX_MS)
          }
        }

        socket.on('data', (morceau) => {
          const lecture = lireTrames(Buffer.concat([restant, morceau]))
          restant = lecture.restant
          if (lecture.trop) return arreter(1009)
          for (const trame of lecture.trames) {
            if (trame.opcode === 0x8) return arreter(1000)
            if (trame.opcode === 0x9) {
              socket.write(tramePong(trame.charge))
              continue
            }
            if (trame.opcode !== 0x1) continue
            let message = null
            try {
              message = JSON.parse(trame.charge.toString('utf8'))
            } catch {
              message = null
            }
            if (message === null || message.type !== 'demarrer') {
              envoyer({ type: 'erreur', message: 'premier message attendu: demarrer' })
              continue
            }
            const identifiant = typeof message.session === 'string' ? message.session : ''
            const depuisSeq = typeof message.depuisSeq === 'number' ? message.depuisSeq : null
            demarrer(identifiant, depuisSeq).catch((erreur) => {
              envoyer({ type: 'erreur', message: String(erreur?.message ?? erreur) })
              arreter(1011)
            })
          }
        })
        socket.on('error', () => arreter(1011))
        socket.on('close', () => {
          ferme = true
          if (minuteur !== null) clearInterval(minuteur)
          if (minuteurPing !== null) clearInterval(minuteurPing)
        })
      },
    }),
  )

  // ── Cycle de vie ───────────────────────────────────────────────────────────
  // `ctx.effect` rattache le nettoyage au cycle de vie du plugin : un
  // rechargement live du patch retire les routes au lieu de les laisser fuir.
  // `retirer()` est idempotent, donc l'appel par effet et par intervalle de
  // securite peut se superposer sans dommage.
  ctx.effect(() => () => retirerTout())

  const retirerTout = () => {
    for (const retirer of routes) {
      try {
        retirer()
      } catch {
        // deja retiree
      }
    }
    cache.clear()
    console.log('[dsh-remote] routes retirees')
  }

  chargerJeton()
    .then((valeur) => {
      jeton = valeur
      if (valeur === null) console.log('[dsh-remote] aucune authentification possible: routes inutilisables (401)')
      else console.log('[dsh-remote] pret: ' + PREFIX + '/v1/sante, /v1/sessions, /v1/session/<id>, ws /v1/flux')
    })
    .catch((erreur) => {
      console.log('[dsh-remote] ECHEC du chargement du jeton: ' + String(erreur?.message ?? erreur))
    })
}
