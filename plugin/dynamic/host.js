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
//   `ctx.get('sessionController')` — adresser un prompt, annuler un tour
//   `ctx.get('agents')`, `ctx.get('sessions')` — état vivant
// Chacune est lue par `ctx.get(...)` puis testée ; le plugin se dégrade au lieu
// de lever une exception au chargement. `sessionController` est en outre relu à
// CHAQUE requête : la composition web le fournit une dizaine de secondes après
// le démarrage, donc une lecture unique au chargement le manquerait à jamais.
//
// HORS DSH : la découverte lance le binaire LOCAL de Tailscale
// (`node:child_process`, argv fixe, sans shell) pour lire l'état du tailnet. Ce
// n'est ni une API DSH ni une API distante : c'est un état déjà présent sur la
// machine. Si le binaire manque ou refuse de répondre, la route rend une liste
// vide AVEC sa raison, et le reste du plugin fonctionne.

import { execFile } from 'node:child_process'
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto'
import { readFile, readdir, stat } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join } from 'node:path'

// LA DÉCOUVERTE DU TAILNET vit dans son propre fichier : elle ne dépend que du
// binaire local de Tailscale, et ses deux fonctions d'analyse sont PURES — donc
// éprouvables sans lancer de processus (voir `tests/tailscale.test.js`).
import { decouvrirMachines, lirePublication } from './tailscale.js'
// LA PLOMBERIE DES RÉPONSES vit dans son propre fichier : elle ne décide rien de la
// sécurité, et c'est ce qui la rendait pénible à traverser quand on cherchait où une
// requête est REFUSÉE. Elle porte pourtant des règles (corps borné, longueur posée,
// corps illisible qui rend `null`), et ses tests sont à côté d'elle.
import { envoyer, envoyerNonModifie, lireCorps } from './reponse.js'

// LE CACHE DE TEXTE DES JOURNAUX vit dans son propre fichier : il ne depend que
// d'une fonction de lecture et d'une fonction de decodage, donc il s'eprouve seul
// — un cache qu'on ne peut verifier qu'en montant un harness entier n'est pas
// verifie. Le POURQUOI du texte plutot que des objets est mesure, et documente la.
import { creerCacheDeFaits } from './cache-faits.js'
import { creerCacheTexte } from './cache-texte.js'

// LA LECTURE DU JOURNAL vit dans son propre fichier : décodage des trames zstd,
// analyse des lignes JSONL, et résumé d'une session. Ce sont des règles pures —
// donc éprouvables sans harness (voir `tests/journal.test.js`).
// TOUS les symboles encore utilisés ici sont importés — la liste a été VÉRIFIÉE
// par grep après extraction, et pas de mémoire : un `cheminIndicatif` oublié a
// fait répondre `500 listage impossible` à `/v1/sessions` sur une instance
// neuve.
// LE PROTOCOLE WEBSOCKET vit dans son propre fichier, avec ses tests : c'est du
// code BINAIRE (RFC 6455), écrit à la main pour ne pas ajouter de dépendance, et
// rien ne l'éprouvait.
import {
  accepterWebSocket,
  creerAssembleur,
  lireTrames,
  trameFermeture,
  tramePong,
  trameTexte,
} from './trames.js'

import {
  analyserLigne,
  cheminIndicatif,
  entreeDeSession,
  trouverJournal,
  decoderFinDeJournal,
  decoderJournal,
  resumer,
} from './journal.js'

import { codePlausible, construire, GENRE_CODE, GENRE_JETON, nomDAppareil, VERSIONS } from './appairage.js'

export const name = 'dsh-remote'

// Services requis par le plugin pour enregistrer ses routes et gérer son jeton.
export const inject = ['webServer', 'credentials']

const PREFIX = '/dsh-remote'
// LA VERSION DU PROTOCOLE EST EXPORTÉE : c'est un terme du CONTRAT avec le
// client, et le test de contrat la compare au fixture que le client décode.
export const VERSION_PROTOCOLE = 1

// Bornes de lecture. Un journal de session peut être énorme ; on refuse de
// décompresser sans limite plutôt que de faire enfler la mémoire du harness.
const PLAFOND_FICHIER = 512 * 1024 * 1024
const TAILLE_PAGE_DEFAUT = 200
const TAILLE_PAGE_MAX = 2000
// PAS DE CACHE DE LISTE ICI, ET C'EST UNE MESURE, PAS UN OUBLI. Un
// `TTL_CACHE_MS = 2000` a vécu à cette place sans jamais être lu — du code mort,
// retiré ici. Le brancher n'aurait d'ailleurs rien rendu : la cadence du client
// (3 s) DÉPASSE déjà ce TTL, donc chaque tour aurait redemandé un calcul déjà
// périmé. Le coût chaud d'un listage complet est de 15 à 27 ms (mesure du README
// du plugin, 200 sessions), et ce qui le réduit vraiment est la cadence du
// client — pas une mémorisation plus courte que l'intervalle qui l'interroge.

// Types d'enregistrements porteurs de contenu de modèle ou de requête : jamais
// renvoyés par défaut. Le client doit les demander explicitement (`inclure`).
const TYPES_VOLUMINEUX = new Set([
  'request/header',
  'request/context',
  'system/message',
  'session/title-llm-request',
])

const CLE_JETON = 'dsh-remote/device-token'

// ── Le registre des jetons PAR APPAREIL ───────────────────────────────────────
//
// POURQUOI UN SECOND ENREGISTREMENT, ET PAS UNE RÉÉCRITURE DU PREMIER. Le jeton
// historique (`dsh-remote/device-token`) reste lu TEL QUEL : une mise à jour du
// plugin ne doit pas retirer un droit acquis, et un retour en arrière du plugin
// doit continuer de fonctionner. Le registre s'AJOUTE donc, et les deux sources
// sont valides en même temps — l'historique étant simplement la première entrée.
const CLE_JETONS = 'dsh-remote/device-tokens'

// ── Les codes d'appairage ─────────────────────────────────────────────────────
//
// DURÉE DE VIE. Deux minutes : assez pour lire un QR code, le temps d'un geste —
// et assez court pour qu'une PHOTO de l'écran, prise pendant ce temps, ne vaille
// plus rien après. C'est ce que l'étape A ne savait pas faire : elle publiait le
// jeton lui-même, qui n'expirait jamais.
const TTL_CODE_MS = 2 * 60 * 1000
// Nombre de codes VIVANTS simultanément. Un plafond, pas un compteur d'usage :
// sans lui, un panneau laissé ouvert (ou une page qui se reconnecte en boucle)
// ferait croître une carte en mémoire sans fin.
const CODES_VIVANTS_MAX = 8
// Bornes de la durée de vie réglable (`config.ttlCodeMs`). POURQUOI UNE BORNE
// BASSÉ : en dessous d'une seconde, un code expirerait avant que l'utilisateur
// ait fini de lever son téléphone — la borne protège d'une valeur absurde, pas
// d'un attaquant (le profil est le fichier de l'exploitant). POURQUOI UNE BORNE
// HAUTE : au-delà d'un quart d'heure, la fenêtre pendant laquelle une photo de
// l'écran vaut un jeton redevient celle de l'étape A, et le code perd sa raison
// d'être.
const TTL_CODE_MIN_MS = 1000
const TTL_CODE_MAX_MS = 15 * 60 * 1000
// Plafonds par fenêtre glissante, pour la frappe et pour l'échange.
//
// POURQUOI ILS NE PROTÈGENT PAS DU DEVINAGE, ET POURQUOI ILS EXISTENT QUAND MÊME.
// Un code fait 128 bits : on ne le devine pas, aucun plafond n'y changerait rien.
// Ces compteurs bornent autre chose — un ENCORE qui martèle la route, ou une page
// qui boucle. ET ILS SONT GLOBAUX, PAS PAR ADRESSE : mesuré et documenté ailleurs
// dans ce dépôt, `socket.remoteAddress` vaut TOUJOURS `127.0.0.1` derrière
// `tailscale serve`, et l'en-tête d'identité tailnet est falsifiable. Un plafond
// « par IP » serait donc un plafond par personne… sauf qu'il n'y a qu'une IP :
// ce serait une illusion de contrôle, écrite ici pour ne pas laisser croire
// qu'elle existe.
const FENETRE_MS = 60 * 1000
const FRAPPES_MAX = 30
const ECHANGES_MAX = 30

// ── Portée du jeton ──────────────────────────────────────────────────────────
//
// POURQUOI ELLE EXISTE. Le jeton était tout-puissant : il ouvrait la lecture ET
// l'écriture (`/prompt`, `/annuler`). Un jeton qui fuit donnait donc à son
// porteur le pouvoir d'ÉCRIRE dans l'agent de quelqu'un d'autre — la première
// question qu'on pose à un client publié. La portée y répond par construction :
// un jeton `lecture` lit tout et n'écrit rien.
//
// CE QUI EST PROTÉGÉ, ET CE QUI NE L'EST PAS. La portée borne ce que le JETON
// autorise. Elle ne remplace pas le jeton : sans portée valide, on n'accède à
// rien. Elle ne chiffre rien non plus — le transport est celui de Tailscale.
//
// ELLES SONT EXPORTÉES pour que les tests les emploient plutôt que de recopier
// des chaînes : une faute de frappe dans un test ne prouverait plus rien.
export const PORTEE_LECTURE = 'lecture'
export const PORTEE_ECRITURE = 'ecriture'

/**
 * La portée d'un enregistrement de jeton.
 *
 * UN ENREGISTREMENT SANS PORTÉE EST D'AVANT LA PORTÉE : il vaut `ecriture`.
 * Le traiter en lecture seule retirerait silencieusement un droit à son
 * propriétaire — une mise à jour du plugin ne doit pas casser ce qui marchait.
 */
export function porteeEnregistree(payload) {
  return payload?.portee === PORTEE_LECTURE ? PORTEE_LECTURE : PORTEE_ECRITURE
}

/**
 * La portée d'un jeton NOUVEAU.
 *
 * `lecture` PAR DÉFAUT, et c'est un choix : une installation neuve n'a aucune
 * raison d'accorder l'écriture, et le dépôt public doit pouvoir répondre « un
 * jeton fuité n'écrit rien » sans condition. Qui veut écrire le demande :
 *
 *     DSH_REMOTE_PORTEE=ecriture
 */
export function porteeDemandee(valeur) {
  return String(valeur ?? '').trim().toLowerCase() === PORTEE_ECRITURE
    ? PORTEE_ECRITURE
    : PORTEE_LECTURE
}

// ─────────────────────────────────────────────────────────────────────────────
// Lecture d'un journal de session
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Découverte des serveurs — « le Mac découvre, l'iPhone consomme »
// ─────────────────────────────────────────────────────────────────────────────
//
// POURQUOI ICI ET PAS DANS L'APPLICATION. Une application iOS ne peut pas
// exécuter de processus, et le socket LocalAPI de l'application Tailscale n'est
// pas lisible depuis un autre bac à sable : l'iPhone ne peut donc PAS découvrir
// le tailnet par lui-même. L'instance DSH, elle, tourne sur un Mac qui a
// Tailscale et son binaire. C'est donc le Mac qui découvre, et l'application qui
// LIT le résultat par une route authentifiée.
//
// CE QUE CETTE DÉCOUVERTE N'EST PAS : un scan de réseau, une requête sortante,
// ou une écoute. On interroge l'état LOCAL de Tailscale, déjà présent sur la
// machine, en lançant son binaire avec un argv FIXE (aucune entrée utilisateur
// n'entre dans la ligne de commande, et `execFile` ne passe jamais par un
// shell). Aucun paquet n'est émis par le plugin : Tailscale fait son travail,
// on lit son état.

const TTL_DECOUVERTE_MS = 15000

// ─────────────────────────────────────────────────────────────────────────────
// Plugin
// ─────────────────────────────────────────────────────────────────────────────

export function configurerTtlCode(valeur) {
  if (!Number.isFinite(valeur)) return TTL_CODE_MS
  return Math.min(Math.max(Math.trunc(valeur), TTL_CODE_MIN_MS), TTL_CODE_MAX_MS)
}

export function apply(ctx, config) {
  const options = config ?? {}
  const journaliser = options.journaliser !== false
  /** La duree de vie d'un code, bornee. Voir TTL_CODE_MIN_MS / TTL_CODE_MAX_MS. */
  const ttlCode = configurerTtlCode(options.ttlCodeMs)

  const webServer = ctx.get('webServer') ?? ctx.webServer
  if (webServer === undefined || webServer === null || typeof webServer.register !== 'function') {
    console.log('[dsh-remote] ECHEC: service webServer indisponible, aucune route enregistree')
    return
  }

  const sessions = ctx.get('sessions')
  const agents = ctx.get('agents')

  // Seul service qui sache ADRESSER un prompt a une session par son identifiant.
  //
  // Il est lu A CHAQUE REQUETE, jamais au chargement. Mesure a l'appui : la
  // composition web fournit `sessionController` une dizaine de secondes APRES
  // le demarrage, alors que ce plugin s'applique dans les premieres. Une lecture
  // unique au chargement figeait donc `undefined` pour toute la vie du
  // processus — ce qui a fait conclure, a tort, que le service etait absent de
  // la composition et que l'ecriture y etait impossible.
  const controleurEcriture = () => {
    try {
      const service = ctx.get('sessionController')
      return service !== undefined && service !== null && typeof service.prompt === 'function' ? service : null
    } catch {
      return null
    }
  }

  // Le harness ne publie pas de service de chemins : `dsh-home-paths` est une
  // bibliotheque de fonctions, pas un service Cordis. On refait donc la
  // resolution documentee (variable `DSH_HOME`, sinon `~/.dsh`). Les chemins ne
  // sont jamais journalises ni renvoyes : seule la liste des sessions l'est.
  //
  // `homedir()` ET NON `process.env.HOME` : la variable n'existe pas sur
  // Windows, ou le profil est dans `USERPROFILE`. Le repli `/tmp` d'avant y
  // aurait resolu `C:\tmp\.dsh` — un dossier vide, donc une liste de sessions
  // vide sans erreur. Le defaut n'a pas ete observe (aucun hote Windows n'a
  // encore charge ce plugin) : il est corrige par lecture du code.
  const racineSessions = () => {
    const configure =
      typeof process.env.DSH_HOME === 'string' && process.env.DSH_HOME.length > 0
        ? process.env.DSH_HOME
        : join(homedir() || '/tmp', '.dsh')
    return join(configure, 'sessions')
  }

  // Aucune API publique n'expose la version du harness au contexte d'un plugin.
  // On prefere `null` a une valeur inventee.
  const versionHarness = () => {
    const declaree = process.env.DSH_VERSION
    return typeof declaree === 'string' && declaree.length > 0 ? declaree : null
  }

  // ── Jetons, appareils, codes ───────────────────────────────────────────────
  let jeton = null
  // Ce que le jeton HISTORIQUE autorise. Voir `PORTEE_LECTURE` / `PORTEE_ECRITURE` :
  // la valeur de départ est celle d'un jeton d'avant la portée.
  let portee = PORTEE_ECRITURE
  // LES APPAREILS APPAIRÉS, dans l'ordre de lecture : l'historique d'abord (s'il
  // existe), puis le registre. Chaque entrée porte SON jeton et SA portée — c'est
  // ce qui permet de révoquer un appareil sans toucher aux autres.
  let appareils = []
  // LES CODES VIVANTS : `code -> { creeLe, expireLe }`. En mémoire SEULEMENT, et
  // c'est délibéré : un code qui survit à un redémarrage serait un code qu'on
  // aurait oublié, alors qu'il donne un jeton.
  const codes = new Map()
  // Horodatages des frappes et des échanges, pour les plafonds glissants.
  let frappes = []
  let echanges = []

  /**
   * La marque de l'appareil authentifié SUR LA RÉPONSE, et pourquoi pas une
   * variable de module.
   *
   * POURQUOI. La portée était UNE variable globale : il n'y avait qu'un jeton,
   * donc une seule portée. Avec un jeton par appareil, elle dépend de QUI appelle.
   * Une variable de module écrasée à chaque requête serait juste « en pratique »
   * (Node est mono-thread, et le gestionnaire lit la portée dans le même tour) —
   * mais elle deviendrait fausse le jour où une route attend entre l'authentification
   * et la lecture. La réponse, elle, appartient à SA requête par construction.
   */
  const APPAREIL = Symbol('dsh-remote/appareil')

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
      if (typeof valeur === 'string' && valeur.length >= 32) {
        portee = porteeEnregistree(existant.payload)
        return valeur
      }
    }
    const nouveau = randomBytes(32).toString('base64url')
    portee = porteeDemandee(process.env.DSH_REMOTE_PORTEE)
    await credentials.modifyRecord(CLE_JETON, async () => ({ kind: 'grant', payload: { token: nouveau, creeLe: Date.now(), portee } }))
    // Affichage UNIQUE, dans le terminal de l'utilisateur, a la creation.
    // Jamais reecrit ensuite, jamais journalise, JAMAIS RENVOYE PAR UNE ROUTE —
    // c'est la regle que l'appairage par code a permis de retablir (l'etape A la
    // transgressait en publiant ce jeton dans un QR).
    // LA PORTEE EST DITE ICI, et c'est le seul endroit ou l'utilisateur apprend
    // ce que ce jeton autorise — sans quoi il decouvrirait en lisant le code
    // pourquoi son application n'ecrit pas.
    console.log('[dsh-remote] NOUVEAU JETON D APPAREIL, PORTEE ' + portee.toUpperCase() + ' (a saisir une fois dans l application, puis oublier) :')
    console.log('[dsh-remote] ' + nouveau)
    if (portee === PORTEE_LECTURE) {
      console.log('[dsh-remote] ce jeton LIT sans pouvoir ecrire. Pour autoriser l ecriture, relancer avec DSH_REMOTE_PORTEE=ecriture et un jeton neuf (supprimer l enregistrement ' + CLE_JETON + ' du coffre).')
    }
    return nouveau
  }

  /** L'entrée du registre correspondant à un enregistrement de coffre, ou `null`. */
  const entreeDeRegistre = (brut) => {
    if (brut === null || typeof brut !== 'object') return null
    const valeur = brut.token
    if (typeof valeur !== 'string' || valeur.length < 32) return null
    return {
      token: valeur,
      portee: porteeEnregistree(brut),
      creeLe: Number.isFinite(brut.creeLe) ? brut.creeLe : null,
      nom: nomDAppareil(brut.nom),
      historique: false,
    }
  }

  /**
   * Charge le registre des jetons par appareil.
   *
   * UNE ENTRÉE MAL FORMÉE EST IGNORÉE, PAS FATALE : le registre est écrit par ce
   * plugin, mais il vit dans un fichier que l'utilisateur peut éditer. Une entrée
   * cassée ne doit pas rendre les AUTRES inutilisables — sinon une faute de frappe
   * dans un nom déconnecterait tous les appareils.
   */
  const chargerAppareils = async () => {
    const credentials = coffre()
    const entrees = []
    if (jeton !== null) {
      // LE NOM DIT CE QUE C'EST, ET À QUI ÇA SERT. « jeton historique » faisait
      // lire un vestige là où il y a la connexion de l'application SUR CE MAC à
      // elle-même (et celle de dsh-remote-ctl) : le propriétaire a demandé à quoi
      // il correspondait, ce qui est exactement le défaut d'un nom qui n'explique
      // rien. Il n'est pas appairé, il n'a pas de date, et le révoquer le remplace
      // au prochain démarrage — le panneau le dit à côté.
      entrees.push({
        token: jeton,
        portee,
        creeLe: null,
        nom: 'Jeton du terminal (ce Mac, dsh-remote-ctl)',
        historique: true,
      })
    }
    if (credentials === null) return entrees
    const registre = await credentials.readRecord(CLE_JETONS)
    const liste = registre?.kind === 'grant' && Array.isArray(registre.payload?.jetons) ? registre.payload.jetons : []
    for (const brut of liste) {
      const entree = entreeDeRegistre(brut)
      if (entree !== null) entrees.push(entree)
    }
    return entrees
  }

  /**
   * Comparaison à temps constant, longueurs égalisées.
   *
   * POURQUOI ELLE RESTE ÉCRITE ICI, alors qu'il n'y a plus UN secret mais N. Le
   * nombre d'appareils est public (il est affiché), la taille d'un jeton aussi :
   * ce qui ne doit pas fuiter, c'est la VALEUR. Chaque comparaison est donc à
   * temps constant, et la boucle les fait TOUTES — sans sortie anticipée, pour que
   * la durée ne dise pas à quelle position le jeton a été trouvé.
   */
  const egalConstant = (attendu, recu) => {
    const gauche = Buffer.from(attendu, 'utf8')
    const droite = Buffer.from(recu, 'utf8')
    const taille = Math.max(gauche.length, droite.length, 1)
    const tamponGauche = Buffer.alloc(taille)
    const tamponDroite = Buffer.alloc(taille)
    gauche.copy(tamponGauche)
    droite.copy(tamponDroite)
    const egaux = timingSafeEqual(tamponGauche, tamponDroite)
    return egaux && gauche.length === droite.length
  }

  /** L'appareil dont le jeton est celui présenté, ou `null`. */
  const appareilDe = (presente) => {
    if (typeof presente !== 'string' || presente.length === 0) return null
    let trouve = null
    for (const entree of appareils) {
      if (egalConstant(entree.token, presente)) trouve = trouve === null ? entree : trouve
    }
    return trouve
  }

  /**
   * L'EMPREINTE d'un jeton — ce qu'on montre pour désigner un appareil.
   *
   * POURQUOI UNE EMPREINTE ET JAMAIS LE JETON. La liste des appareils sert à en
   * révoquer un : l'utilisateur doit pouvoir le DÉSIGNER sans qu'on lui réaffiche
   * un secret. Douze caractères hexadécimaux suffisent à distinguer deux appareils
   * et ne permettent pas de remonter au jeton (c'est un SHA-256 tronqué d'une
   * valeur de 256 bits d'aléa).
   */
  const empreinteDe = (valeur) => createHash('sha256').update(String(valeur)).digest('hex').slice(0, 12)

  /**
   * Écrire dans le registre À PARTIR DE LA LISTE RELUE, jamais de la mémoire.
   *
   * POURQUOI LA LISTE EST RELUE ICI, ET PAS REPRISE DE `appareils`. Deux écritures
   * rapprochées — deux appareils qui s'appairent dans la même minute, une
   * révocation pendant un échange — écriraient chacune la liste qu'elles avaient
   * en mémoire, et la seconde EFFACERAIT l'entrée de la première. Le service de
   * coffre sérialise et relit sous verrou : `modifyRecord` reçoit l'enregistrement
   * COURANT, et c'est ce qu'on modifie. La liste en mémoire, elle, sert à
   * AUTHENTIFIER, pas à écrire.
   *
   * (La conséquence d'un écrasement ne serait pas une faille mais une perte : un
   * appareil appairé disparaîtrait du registre, et son jeton cesserait de valoir au
   * redémarrage suivant — sans que rien ne le dise.)
   */
  const modifierRegistre = async (transformer) => {
    const credentials = coffre()
    if (credentials === null) return false
    await credentials.modifyRecord(CLE_JETONS, async (courant) => {
      const brut = Array.isArray(courant?.payload?.jetons) ? courant.payload.jetons : []
      return { kind: 'grant', payload: { jetons: transformer(brut) } }
    })
    return true
  }

  const ajouterAuRegistre = (entree) =>
    modifierRegistre((liste) => [
      ...liste,
      { token: entree.token, portee: entree.portee, creeLe: entree.creeLe, nom: entree.nom },
    ])

  const retirerDuRegistre = (jeton) => modifierRegistre((liste) => liste.filter((entree) => entree?.token !== jeton))

  const jetonValide = (presente) => appareilDe(presente) !== null

  // ── Cache des journaux ─────────────────────────────────────────────────────
  // LA POLITIQUE VIT DANS `cache-faits.js` (validité par les marqueurs du fichier,
  // péremption, éviction LRU) : elle y est éprouvée seule. Ici, on ne fait que lui
  // donner son horloge.
  const cache = creerCacheDeFaits()

  // ── Le cache du TEXTE des journaux lus en entier ───────────────────────────
  // La regle (bornes, cle de validite, LRU) vit dans `cache-texte.js`, ou elle est
  // eprouvee seule. Ici, on ne fait que lui donner ses deux dependances.
  const cacheTexte = creerCacheTexte({ lire: readFile, decoder: decoderJournal })

  /** Le journal d'un fichier, decompresse — servi par le cache quand rien n'a bouge. */
  const decoderFichier = (fichier, information) => cacheTexte.lignes(fichier, information)

  const viderLesCaches = () => {
    cache.vider()
    cacheTexte.vider()
  }

  /**
   * Liste les sessions presentes sur disque, de la plus recente a la plus ancienne.
   * @param {{limite?: number}} [demande]
   */
  const listerSessions = async (demande = {}) => {
    // PLUS DE BALAYAGE ICI : il appartient au cache, qui le fait a ses propres
    // lectures et a son propre rythme (voir `cache-faits.js`). L'appeler d'ici
    // faisait dependre la memoire du harness de la cadence du CLIENT.
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
        // DEUX NOMS DE JOURNAL EXISTENT, et n'en lire qu'un faisait disparaître
        // 39 sessions sur 148 (mesuré). Voir `trouverJournal`.
        const fichier = await trouverJournal(dossier)
        if (fichier === null) continue
        let information
        try {
          information = await stat(fichier)
        } catch {
          continue
        }
        const cle = fichier
        // LA VALIDITÉ EST CELLE DU FICHIER, et c'est le cache qui la juge (taille
        // ET mtime) : voir `cache-faits.js`, ou cette règle est éprouvée seule.
        const marqueurs = { taille: information.size, mtime: information.mtimeMs }
        let faits = cache.lire(cle, marqueurs)
        if (faits !== undefined) {
          // rien a refaire : le journal n'a pas bouge depuis la derniere lecture
        } else if (information.size > PLAFOND_FICHIER) {
          faits = { illisible: 'journal trop volumineux (' + information.size + ' octets)' }
        } else {
          try {
            const { lignes, tronque } = await decoderFichier(fichier, information)
            const enregistrements = []
            for (const ligne of lignes) {
              const analyse = analyserLigne(ligne)
              if (analyse !== null) enregistrements.push(analyse)
            }
            faits = resumer(enregistrements)
            faits.tronque = tronque
            cache.poser(cle, marqueurs, faits)
          } catch (erreur) {
            faits = { illisible: 'lecture impossible: ' + (erreur.code ?? erreur.message) }
          }
        }
        // LA MISE EN FORME VIT DANS `journal.js`, ET C'EST LE CONTRAT : c'est
        // cette fonction que le test de contrat compare au fixture que le client
        // Swift décode. Construite ici en ligne, elle ne pouvait être éprouvée
        // que par un vrai client branché sur un vrai harness.
        resultats.push(
          entreeDeSession({
            projet: projet.name,
            dossier,
            fichier,
            octets: information.size,
            modifieLe: information.mtimeMs,
            vivante: estVivante(faits?.id),
            statut: statutDe(faits?.id),
            // Le harness attend-il une DECISION de l'utilisateur pour cette
            // session ? C'est l'information la plus actionnable de la liste : une
            // session bloquee sur une question ne repartira pas toute seule.
            attendReponse: attendUneReponse(faits?.id),
            faits,
          }),
        )
      }
    }
    resultats.sort((a, b) => (b.dernierEvenementLe ?? b.modifieLe) - (a.dernierEvenementLe ?? a.modifieLe))
    // L'empreinte est calculée AVANT la troncature : elle décrit la liste
    // complète, donc elle ne dépend pas de la page demandée — la `limite` est
    // dans l'empreinte, justement pour que deux pages ne se confondent pas.
    return {
      racine,
      total: resultats.length,
      empreinte: empreinteDeListe(resultats, limite),
      sessions: resultats.slice(0, limite),
    }
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

  /**
   * L'EMPREINTE DE LA LISTE PUBLIÉE — ce qui remplace 115 Kio par une chaîne.
   *
   * POURQUOI ELLE EXISTE. La liste était retransmise EN ENTIER toutes les trois
   * secondes par l'application, alors qu'un tailnet ne change pas d'une seconde à
   * l'autre : mesuré sur cette installation, 172 sessions × 685 octets ≈ **115
   * Kio par appel**, vingt fois par minute, soit ~135 Mio par heure d'usage actif
   * pour un contenu presque toujours identique. L'application envoie désormais
   * `If-None-Match`, et un `304` sans corps répond « rien n'a changé ».
   *
   * POURQUOI PAS SEULEMENT `taille` ET `mtime`. C'est le piège de cette
   * optimisation, et il est silencieux : `statut` (`en_cours`), `vivante` et
   * `attendReponse` viennent du PROCESSUS, pas du fichier. Une empreinte fondée
   * sur les seuls états de fichier rendrait `304` pendant qu'un tour démarre ou
   * qu'une question attend une réponse — l'écran gèlerait ses pastilles, et
   * l'information la plus actionnable de la liste (« une décision humaine est
   * attendue ») ne remonterait plus.
   *
   * CE QUI ENTRE DANS L'EMPREINTE, ET RIEN DE PLUS : pour chaque session, les
   * marqueurs de FICHIER (`modifieLe`, `octets`, `dernierSeq`) et les marqueurs de
   * PROCESSUS (`vivante`, `statut`, `attendReponse`) — plus la `limite`, car deux
   * listes tronquées différemment ne sont pas la même représentation, et un client
   * qui réutiliserait son empreinte en changeant de limite recevrait un `304`
   * au-dessus d'une liste d'une autre longueur.
   *
   * LE COÛT EST CELUI DU BALAYAGE, PAS DE LA SÉRIALISATION : l'empreinte est
   * calculée sur ce que `listerSessions` a DÉJÀ en mémoire. L'ancien chemin
   * sérialisait ces 115 Kio (avec `content-length`, donc un second passage sur le
   * tampon) avant de les écrire : un `304` évite les deux.
   *
   * @param {object[]} resultats - les entrées DÉJÀ mises en forme, liste complète
   * @param {number} limite
   * @returns {string} une empreinte stable pour un contenu identique
   */
  const empreinteDeListe = (resultats, limite) => {
    const condensat = createHash('sha256')
    condensat.update('dsh-remote/liste/v1\u0000' + limite + '\u0000' + resultats.length + '\u0000')
    for (const entree of resultats) {
      condensat.update(
        [
          entree.id ?? '',
          entree.modifieLe ?? '',
          entree.octets ?? '',
          entree.dernierSeq ?? '',
          entree.vivante === true ? 1 : 0,
          entree.statut ?? '',
          entree.attendReponse === true ? 1 : 0,
        ].join('\u0001') + '\u0000',
      )
    }
    // Guillemets : la forme d'un `ETag` fort (RFC 9110, § 8.8.3). L'empreinte
    // porte sur le CONTENU de la représentation, pas sur ses octets : deux corps
    // identiques la partagent, ce qui est exactement ce qu'on compare.
    return '"' + condensat.digest('base64url') + '"'
  }

  /**
   * Identifiant de session porte par un agent d'evenement.
   *
   * Les deux waterfalls qui demandent une decision passent l'agent vivant pour
   * portee ; son identifiant EST celui de la session.
   */
  const identifiantDeLagent = (agent) => {
    if (agent === undefined || agent === null) return null
    if (typeof agent.id === 'string' && agent.id.length > 0) return agent.id
    const parSession = agent.session?.id
    return typeof parSession === 'string' && parSession.length > 0 ? parSession : null
  }

  // ── Attente d'une decision de l'utilisateur ────────────────────────────────
  //
  // Deux waterfalls du harness suspendent un tour en attendant un HUMAIN : une
  // question d'un tool (`user-questions/request`) et une autorisation
  // (`approval/request`). Toutes deux sont diffusees avec l'agent pour portee,
  // donc un listener pose ici, a la racine, les recoit — c'est le meme seam que
  // l'interface web consomme.
  //
  // CE PLUGIN N'Y REPOND PAS. Il rend la main au repondeur suivant et se
  // contente de compter : repondre depuis cette surface reste impossible (un
  // seul repondeur terminal par deploiement, occupe par l'interface web). Ce qui
  // est nouveau, c'est de pouvoir DIRE qu'une decision est attendue — une
  // session bloquee sur une question ne repartira pas toute seule, et c'est
  // exactement ce qu'un telephone doit signaler.
  //
  // La duree de l'attente n'est pas devinee : c'est celle de la promesse du
  // waterfall. Le listener la traverse (`next()`), donc il voit le moment exact
  // ou la question est resolue — repondue, refusee ou abandonnee. Un compteur
  // par session, parce que deux demandes peuvent se superposer.
  const attentes = new Map()

  const suivreAttente = (evenement) => {
    try {
      // `{ prepend: true }` EST INDISPENSABLE, et c'est une MESURE.
      //
      // Un waterfall s'arrete au premier ecouteur qui ne rappelle pas `next()`
      // (`waterfall()` : `cbs.shift()`) — et le repondeur, lui, repond : il ne
      // rappelle pas `next`. Un ecouteur inscrit APRES lui n'est donc JAMAIS
      // appele. Mesure : 4 ecouteurs inscrits sur l'evenement, dont le notre,
      // et le notre jamais atteint — jusqu'a ce qu'il passe en tete.
      //
      // `global` n'est PAS necessaire : un ecouteur non etiquete est admis par
      // le filtre de portee. Seule la place dans la chaine comptait.
      //
      // Le desabonnement reste solidaire du cycle de vie du plugin : `ctx.on`
      // enregistre l'ecouteur comme effet de sa fibre.
      ctx.on(
        evenement,
        (requete, next) => {
          const identifiant = identifiantDeLagent(requete?.agent)
          if (identifiant !== null) attentes.set(identifiant, (attentes.get(identifiant) ?? 0) + 1)
          // Passer la main, jamais repondre : le repondeur reste celui du harness.
          const suite = typeof next === 'function' ? next() : undefined
          return Promise.resolve(suite).finally(() => {
            try {
              if (identifiant === null) return
              const restant = (attentes.get(identifiant) ?? 1) - 1
              if (restant > 0) attentes.set(identifiant, restant)
              else attentes.delete(identifiant)
            } catch {
              // Un compteur ne doit jamais faire echouer une question en cours.
            }
          })
        },
        { prepend: true },
      )
    } catch {
      // Le harness a change de forme : on perd l'indicateur, pas la lecture.
    }
  }
  suivreAttente('user-questions/request')
  suivreAttente('approval/request')

  /** Le harness attend-il une decision de l'utilisateur pour cette session ? */
  const attendUneReponse = (identifiant) =>
    typeof identifiant === 'string' && identifiant.length > 0 && attentes.has(identifiant)

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
      const fichier = await trouverJournal(join(racine, projet.name, identifiant))
      // Aucun des deux noms n'existe : ce projet ne porte pas cette session.
      if (fichier === null) continue
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
    // LA LECTURE PASSE PAR LE CACHE : le client demande une page a l'ouverture,
    // puis une autre aussitot apres (l'en-tete, puis les enregistrements) — et
    // c'est le MEME journal, donc le meme decodage. Le cache est valide par
    // `(taille, mtime)`, donc une session en train d'ecrire est relue.
    const { lignes, tronque } = await decoderFichier(trouve.fichier, trouve.information)
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
  //
  // `envoyer`, `envoyerNonModifie` et `lireCorps` viennent de `reponse.js` : voir
  // l'en-tête de ce fichier pour ce qu'elles garantissent (pas de cache, longueur
  // toujours posée, corps borné à 1 Mio, corps illisible qui rend `null`).

  const autoriser = (req, res) => {
    // 1. Un client natif n'envoie jamais `Origin`. Un navigateur en envoie
    //    toujours, y compris depuis une page hostile. On refuse donc tout
    //    `Origin`, avant même de regarder le jeton.
    if (req.headers.origin !== undefined) {
      envoyer(res, 403, { erreur: 'origine refusee' })
      return false
    }
    // 2. Secret partage, comparaison a temps constant — contre CHAQUE appareil.
    const entete = req.headers.authorization
    const presente = typeof entete === 'string' && entete.startsWith('Bearer ') ? entete.slice(7) : null
    const appareil = appareilDe(presente)
    if (appareil === null) {
      res.writeHead(401, { 'content-type': 'application/json; charset=utf-8', 'www-authenticate': 'Bearer', 'cache-control': 'no-store' })
      res.end('{"erreur":"jeton requis"}')
      return false
    }
    // QUEL APPAREIL A PARLÉ, ET DONC QUELLE PORTÉE S'APPLIQUE. Marqué sur la
    // réponse : voir `APPAREIL` pour pourquoi ce n'est pas une variable de module.
    res[APPAREIL] = appareil
    return true
  }

  /**
   * La portée de l'appareil qui a parlé — lue SUR LA RÉPONSE, jamais devinée.
   *
   * Rend `null` quand la requête n'a pas été authentifiée : aucune route ne doit
   * alors décider quoi que ce soit. Une valeur par défaut, ici, serait un droit
   * accordé par omission.
   */
  const porteeDe = (res) => (res[APPAREIL] === undefined ? null : res[APPAREIL].portee)

  /**
   * La portée refuse-t-elle cette écriture ? Rend `true` si la requête est
   * REFUSÉE (et la réponse envoyée).
   *
   * POURQUOI ELLE EST SÉPARÉE DE `autoriser`. Les routes d'écriture vivent dans
   * le même gestionnaire que celles de lecture (`/v1/session/<id>/<action>`) :
   * le jeton y est déjà vérifié une fois pour toutes, et le contrôle de portée
   * doit donc pouvoir s'appliquer SEUL, dans la branche qui écrit.
   *
   * LE CORPS PORTE UNE RAISON DISTINCTE de `origine refusee` (même code 403) :
   * le client lit ce champ, et deux causes différentes ne doivent pas produire
   * le même message.
   */
  const refuserSiLectureSeule = (req, res) => {
    const porteeRequete = porteeDe(res)
    if (porteeRequete === PORTEE_ECRITURE) return false
    envoyer(res, 403, {
      erreur: 'jeton en lecture seule',
      portee: porteeRequete,
      detail:
        "cet appareil a recu un jeton qui LIT sans ecrire. Pour lui donner l ecriture : supprimer son enregistrement dans " +
        CLE_JETONS +
        ' (ou le jeton historique ' +
        CLE_JETON +
        "), puis refaire l appairage avec DSH_REMOTE_PORTEE=ecriture.",
    })
    tracer(req, 403, 'portee ' + String(porteeRequete))
    return true
  }

  /** Barrière complète d'une route qui écrit : jeton, puis portée. */
  const autoriserEcriture = (req, res) => {
    if (!autoriser(req, res)) return false
    return !refuserSiLectureSeule(req, res)
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
        // La portée de CET APPAREIL, dite TELLE QUELLE : c'est ce qui permet à
        // l'application d'expliquer « ce jeton lit sans écrire » plutôt que de
        // laisser croire à une panne. Elle n'est plus globale : deux appareils
        // appairés peuvent avoir deux portées différentes.
        portee: porteeDe(res),
        // COMBIEN D'APPAREILS SONT APPAIRÉS — un compte, jamais une liste.
        //
        // POURQUOI UN COMPTE ICI, ET PAS UNE ROUTE NATIVE DE PLUS. Gérer les
        // appareils (les voir, en révoquer un) se fait dans le PANNEAU, sous
        // session navigateur, et c'est délibéré : un porteur de jeton ne doit pas
        // pouvoir expulser les autres, et `dsh-remote-ctl` n'a pas à devenir un
        // SECOND LECTEUR du coffre — un lecteur qui se trompe afficherait un
        // jeton. Ce champ donne au terminal ce qu'il peut honnêtement savoir :
        // combien. Le nom du champ est au pluriel, comme celui des appareils.
        appareils: appareils.length,
        capacites: {
          sessions: true,
          journal: true,
          flux: true,
          // L'hote sait-il publier la liste des Macs du tailnet ? Un client plus
          // ancien que cette route lira `false` et gardera la saisie manuelle
          // plutot que d'attendre une liste qui ne viendra jamais.
          decouverte: true,
          // L'hote sait-il publier ses espaces de travail — y compris ceux qui
          // n'ont AUCUNE session ? Sans cette capacite, le client deduit ses
          // espaces des sessions, ce qui est le comportement d'avant.
          espaces: registreEspaces() !== null,
          // L'ÉCRITURE DÉPEND DE DEUX CHOSES : que le service soit monté, ET que
          // le jeton de CET APPAREIL porte la portée. Un client qui lit `false` ne
          // propose pas de composeur — la règle du dépôt : un bouton sans effet
          // est un mensonge.
          ecriture: porteeDe(res) === PORTEE_ECRITURE && controleurEcriture() !== null,
          // Annuler le tour en cours. Meme service que l'ecriture : un client qui
          // lit `false` ne propose pas de bouton « Arreter » qui ne ferait rien.
          annulation: porteeDe(res) === PORTEE_ECRITURE && controleurEcriture() !== null,
          // L'hote sait-il ECHANGER un code d'appairage contre un jeton propre a
          // l'appareil ? C'est ce que lit une application qui vient de scanner un
          // code : un hote plus ancien ne le sait pas, et le lui dire evite de
          // chercher une panne d'authentification.
          appairage: true,
          // L'hote sait-il dire qu'une session ATTEND une decision humaine ?
          // Annonce a part de `approbations` : ici on ne fait que SIGNALER
          // l'attente, jamais y repondre.
          questions: true,
          // Les approbations ne sont PAS exposees : le seam d'approbation de DSH
          // n'admet qu'un repondeur terminal par deploiement, et l'interface web
          // l'occupe deja. Repondre depuis l'iPhone exigerait de le remplacer.
          approbations: false,
        },
      })
      tracer(req, 200)
    },
  })

  // ── GET /dsh-remote/v1/espaces — les espaces de travail de l'hote ─────────
  //
  // POURQUOI CETTE ROUTE EXISTE. L'application deduisait ses espaces de travail
  // des SESSIONS : un espace sans session lui etait donc invisible, alors que
  // l'interface web les affiche tous (un espace s'enregistre des qu'on choisit
  // un dossier, avant meme d'y ouvrir une session). Résultat : deux arbres qui
  // ne se ressemblaient plus.
  //
  // L'ORDRE VIENT DE L'HOTE, et il est deja le bon : `workspaceRegistry.list()`
  // rend les espaces dans l'ordre durable du registre, qui classe par date de
  // creation decroissante (`newestAt`). On ne retrie donc PAS ici — retrier
  // ferait diverger l'application du web a la premiere evolution de la regle.
  //
  // `sessionIds` est publie tel quel : c'est l'APPARTENANCE, qui est un fait du
  // registre. Le client n'a pas a la recalculer en comparant des chemins — ce
  // que faisait l'application, avec les erreurs que cela suppose (un dossier
  // deplace, un sous-agent, deux projets homonymes).
  const registreEspaces = () => {
    try {
      const service = ctx.get('workspaceRegistry')
      return service !== undefined && service !== null && typeof service.list === 'function' ? service : null
    } catch {
      return null
    }
  }

  enregistrer({
    kind: 'exact',
    path: PREFIX + '/v1/espaces',
    handler: (req, res) => {
      if (!autoriser(req, res)) return tracer(req, 401)
      if (req.method !== 'GET') {
        envoyer(res, 405, { erreur: 'methode non autorisee' })
        return tracer(req, 405)
      }
      // Le service est resolu A LA REQUETE : la composition web publie ses
      // services par vagues, et une lecture au chargement du plugin rendrait
      // `undefined` pour toujours (meme piege que `sessionController`).
      const registre = registreEspaces()
      if (registre === null) {
        envoyer(res, 503, {
          erreur: 'espaces indisponibles',
          detail: "le service workspaceRegistry n'est pas monte dans cette composition",
        })
        return tracer(req, 503)
      }
      try {
        const espaces = registre.list().map((espace) => {
          const cree = Date.parse(espace.createdAt)
          return {
            id: String(espace.id),
            titre: typeof espace.title === 'string' ? espace.title : '',
            chemin: String(espace.path),
            // Millisecondes epoch, comme partout ailleurs dans ce protocole.
            creeLe: Number.isFinite(cree) ? cree : null,
            sessions: Array.isArray(espace.sessionIds) ? espace.sessionIds.map(String) : [],
          }
        })
        envoyer(res, 200, { protocole: VERSION_PROTOCOLE, espaces })
        tracer(req, 200, espaces.length + ' espaces')
      } catch (erreur) {
        envoyer(res, 500, { erreur: 'lecture des espaces impossible', detail: String(erreur?.message ?? erreur) })
        tracer(req, 500)
      }
    },
  })

  // ── GET /dsh-remote/v1/serveurs — decouverte du tailnet ───────────────────
  //
  // L'iPhone ne peut pas decouvrir le tailnet (iOS interdit d'executer un
  // processus) : il demande donc la liste a un hote qui le peut. C'est la voie
  // retenue — le Mac decouvre, l'application consomme.
  //
  // Le resultat est mis en cache quelques secondes : lancer un processus a
  // chaque requete serait un cout sans contrepartie, un tailnet ne changeant pas
  // d'une seconde a l'autre.
  let cacheDecouverte = { vuLe: 0, valeur: null }
  // LA PUBLICATION DE CETTE MACHINE (`tailscale serve status --json`), mise en
  // cache pour la meme duree : elle coute un processus, et elle ne change pas
  // d'une seconde a l'autre. `null` EST UN RESULTAT : « rien de publie, ou
  // binaire muet » ne doit pas relancer le CLI a chaque frappe de code.
  let cachePublication = { vuLe: 0, valeur: null }

  const repondreServeurs = async (req, res) => {
    try {
      const maintenant = Date.now()
      if (cacheDecouverte.valeur === null || maintenant - cacheDecouverte.vuLe > TTL_DECOUVERTE_MS) {
        const { machines, diagnostic } = await decouvrirMachines()
        cacheDecouverte = { vuLe: maintenant, valeur: { machines, diagnostic } }
      }
      const { machines, diagnostic } = cacheDecouverte.valeur
      envoyer(res, 200, { protocole: VERSION_PROTOCOLE, serveurs: machines, diagnostic })
      tracer(req, 200, machines.length + ' machines')
    } catch (erreur) {
      envoyer(res, 500, { erreur: 'decouverte impossible', detail: String(erreur?.message ?? erreur) })
      tracer(req, 500)
    }
  }

  enregistrer({
    kind: 'exact',
    path: PREFIX + '/v1/serveurs',
    handler: (req, res) => {
      if (!autoriser(req, res)) return tracer(req, 401)
      if (req.method !== 'GET') {
        envoyer(res, 405, { erreur: 'methode non autorisee' })
        return tracer(req, 405)
      }
      repondreServeurs(req, res).catch((erreur) => {
        envoyer(res, 500, { erreur: 'decouverte impossible', detail: String(erreur?.message ?? erreur) })
      })
    },
  })

  // ── GET /dsh-remote/v1/appairage — de quoi appairer un appareil ────────────
  //
  // POURQUOI CETTE ROUTE EXISTE. Le secret ne traversait qu'un seul canal :
  // l'affichage unique au terminal, a la creation du jeton. Le recopier a la
  // main, sur un AUTRE appareil, est la seule etape du parcours qui echoue
  // vraiment — et elle echoue salement, puisque le jeton n'est plus jamais
  // reaffiche ensuite.
  //
  // CE QU'ELLE DEROGE, ET IL FAUT LE DIRE. Le README de ce plugin pose : « le
  // jeton n'est jamais renvoye par une route HTTP, pas meme a un client
  // authentifie : une route qui rendrait le jeton serait un oracle ». Cette
  // route rend le jeton. Ce qui la separe d'un oracle, c'est ce qui l'autorise :
  // NON PAS le jeton d'appareil, mais la SESSION NAVIGATEUR — c'est la page de
  // l'utilisateur, sur sa propre machine, qui l'appelle pour afficher un QR.
  //
  // LA BORNE, ECRITE AUSSI AU README. Tant que `share-qr` vivait dans ce depot,
  // il affichait un QR de l'URL navigateur AUTHENTIFIEE : une photo de ce
  // panneau donnait un cookie valide, qui ouvrait cette route-ci, et deux
  // plugins actifs composaient donc un chemin qu'aucun des deux ne decrivait
  // seul. Ce plugin a ete supprime le 14 septembre 2026 ; la composition n'est
  // plus atteignable DEPUIS CE DEPOT, et la borne qui la rendait supportable
  // reste vraie pour cette route : le jeton rendu est en portee `lecture` par
  // defaut, il ne repond a aucune approbation, et il se revoque en supprimant un
  // enregistrement du coffre.
  //
  // CE QU'ELLE NE FAIT PAS : aucune surface reseau nouvelle (le serveur existe),
  // aucun ecoute, et AUCUNE E/S AVANT L'AUTHENTIFICATION — une requete refusee
  // ne lit ni le coffre ni Tailscale, et repart avec une reponse fixe.
  const serviceNavigateur = () => {
    try {
      const connexion = ctx.get('connection')
      if (connexion === undefined || connexion === null) return null
      const auth = connexion.browserAuth
      if (auth === undefined || auth === null || typeof auth.isAuthenticated !== 'function') return null
      return { auth, connexion }
    } catch {
      // Un service qui leve n'est pas un service present : on degrade.
      return null
    }
  }

  /**
   * Le nom MagicDNS de CETTE machine — celui qu'un AUTRE appareil peut joindre.
   *
   * Deux sources, dans cet ordre : ce que Tailscale dit de la machine locale
   * (`Self`), puis l'hote declare au profil. Jamais la boucle locale : publier
   * `127.0.0.1` dans un QR produirait un appairage qui ne peut aboutir nulle
   * part, et l'utilisateur n'aurait aucun moyen de comprendre pourquoi.
   */
  const nomDeLHote = async () => {
    // LE SCHEMA DE PUBLICATION SE LIT, IL NE SE DEVINE PAS. `tailscale serve
    // status --json` dit sous quel transport CETTE machine est publiee ; il est
    // mis en cache avec la meme duree que la decouverte, parce qu'il coute un
    // processus et qu'une publication ne change pas d'une seconde a l'autre.
    // Sans binaire, sans publication, ou devant une sortie inattendue, on
    // retombe sur le clair : le comportement d'avant, jamais une adresse inventee.
    const schema = await schemaDePublication()
    try {
      const maintenant = Date.now()
      if (cacheDecouverte.valeur === null || maintenant - cacheDecouverte.vuLe > TTL_DECOUVERTE_MS) {
        const { machines, diagnostic } = await decouvrirMachines()
        cacheDecouverte = { vuLe: maintenant, valeur: { machines, diagnostic } }
      }
      const machines = cacheDecouverte.valeur.machines ?? []
      const locale = machines.find((machine) => machine.local === true)
      if (locale !== undefined && typeof locale.nomDNS === 'string' && locale.nomDNS.length > 0) {
        return { hote: locale.nomDNS, via: 'tailscale', schema }
      }
    } catch {
      // Tailscale absent ou muet : l'hote declare reste une source valable.
    }
    const navigateur = serviceNavigateur()
    const declares = navigateur === null ? [] : navigateur.connexion.trustedHosts
    const premier = Array.isArray(declares) && declares.length > 0 ? String(declares[0]) : ''
    // Le profil peut declarer un hote AVEC son port : on ne garde que le nom.
    const nom = premier.split(':')[0]
    return nom.length > 0 ? { hote: nom, via: 'hote declare', schema } : { hote: '', via: 'aucun', schema }
  }

  /**
   * Le schéma sous lequel cette machine est publiée : `http` par défaut.
   *
   * LE DÉFAUT EST LE CLAIR, ET C'EST DÉLIBÉRÉ : c'est ce que le plugin publiait
   * avant, et un `null` (binaire absent, aucune publication, sortie inattendue) ne
   * doit pas transformer une installation qui marchait en installation qui ne
   * répond plus. Le passage à HTTPS est un FAIT que la machine annonce.
   */
  const schemaDePublication = async () => {
    const maintenant = Date.now()
    if (maintenant - cachePublication.vuLe > TTL_DECOUVERTE_MS) {
      let valeur = null
      try {
        valeur = await lirePublication()
      } catch {
        valeur = null
      }
      cachePublication = { vuLe: maintenant, valeur }
    }
    return cachePublication.valeur?.schema === 'https' ? 'https' : 'http'
  }

  /**
   * FRAPPER UN CODE D'APPAIRAGE — la seule chose que le panneau fait désormais.
   *
   * POURQUOI CE N'EST PLUS LE JETON QUI EST PUBLIÉ. À l'étape A, cette route
   * rendait le jeton d'appareil lui-même. C'était une dérogation assumée, et elle
   * avait une conséquence écrite noir sur blanc : une photo de l'écran valait le
   * jeton POUR TOUJOURS, et cette photo pouvait venir d'un autre panneau (celui
   * de `share-qr`, qui publiait l'URL navigateur authentifiée — ce plugin a
   * quitté le dépôt le 14 septembre 2026). Un code change cela : il expire en
   * deux minutes, ne sert qu'une fois, et ne vit qu'en mémoire.
   *
   * LA PORTÉE EST ANNONCÉE, PAS ACCORDÉE ICI : le code ne donne aucun droit, il
   * donne un JETON dont la portée est celle que le harness applique à un appareil
   * neuf (`DSH_REMOTE_PORTEE`, donc `lecture` par défaut). Le panneau l'affiche
   * pour que l'utilisateur sache ce qu'il donne avant de scanner.
   */
  const repondreFrappe = async (req, res) => {
    const maintenant = Date.now()
    frappes = frappes.filter((instant) => maintenant - instant < FENETRE_MS)
    if (frappes.length >= FRAPPES_MAX) {
      envoyer(res, 429, { erreur: 'trop de codes demandes', detail: 'patientez une minute avant de recommencer' })
      return tracer(req, 429)
    }
    const { hote, via, schema } = await nomDeLHote()
    const code = randomBytes(16).toString('base64url')
    const resultat = construire({ hote, genre: GENRE_CODE, secret: code, schema })
    if (resultat.ok !== true) {
      envoyer(res, 503, { erreur: 'adresse injoignable', motif: resultat.motif, detail: resultat.message })
      return tracer(req, 503, resultat.motif)
    }
    // Les codes perimes sont retires AVANT le plafond : sans cela, huit codes
    // expires bloqueraient la frappe d'un neuvieme.
    for (const [valeur, fiche] of codes) if (fiche.expireLe <= maintenant) codes.delete(valeur)
    while (codes.size >= CODES_VIVANTS_MAX) codes.delete(codes.keys().next().value)
    const expireLe = maintenant + ttlCode
    codes.set(code, { creeLe: maintenant, expireLe })
    frappes.push(maintenant)

    envoyer(res, 200, {
      protocole: VERSION_PROTOCOLE,
      genre: GENRE_CODE,
      version: VERSIONS[GENRE_CODE],
      // L'ADRESSE QUE LE PANNEAU AFFICHE SUIT LE SCHEMA PUBLIE : annoncer
      // `http://…` a cote d'un QR qui porte `https` ferait douter de la seule
      // ligne que l'utilisateur peut verifier a la main.
      adresse: schema + '://' + hote,
      charge: resultat.charge,
      // La portee qu'aura le jeton issu de ce code : dite ICI, avant le scan.
      porteeFuture: porteeDemandee(process.env.DSH_REMOTE_PORTEE),
      expireLe,
      via,
    })
    // LE CODE N'EST PAS TRACE : `tracer` n'ecrit que la methode, le chemin sans
    // parametre, le code HTTP et ce complement.
    tracer(req, 200, 'code ' + via)
  }

  /**
   * ÉCHANGER UN CODE CONTRE UN JETON PROPRE À L'APPAREIL.
   *
   * C'EST LA SEULE ROUTE QUI REND UN JETON, et elle le rend à qui présente un
   * code — c'est-à-dire à qui a vu l'écran pendant les deux minutes de vie du
   * code, ou a scanné le QR. La dérogation à l'interdit #3 se réduit donc à cela,
   * au lieu de « une route rend le jeton à toute session navigateur ».
   *
   * ORDRE DES OPÉRATIONS, ET IL EST DÉLIBÉRÉ : forme, puis provenance, puis
   * consommation du code, puis écriture. LE CODE EST CONSOMMÉ AVANT L'ÉCRITURE :
   * un échec du coffre brûle le code au lieu de le laisser rejouable — l'appareil
   * redemande un code, ce qui est un désagrément ; un code rejouable serait une
   * faille.
   */
  const repondreEchange = async (req, res, corps) => {
    const entete = req.headers.authorization
    const code = typeof entete === 'string' && entete.startsWith('Bearer ') ? entete.slice(7) : null
    if (!codePlausible(code)) {
      envoyer(res, 400, { erreur: 'code absent ou malforme' })
      return tracer(req, 400)
    }
    const maintenant = Date.now()
    echanges = echanges.filter((instant) => maintenant - instant < FENETRE_MS)
    if (echanges.length >= ECHANGES_MAX) {
      envoyer(res, 429, { erreur: 'trop d echanges', detail: 'patientez une minute avant de recommencer' })
      return tracer(req, 429)
    }
    const fiche = codes.get(code)
    if (fiche === undefined) {
      // DEUX CAUSES, UN SEUL REFUS — et c'est assumé : distinguer « jamais emis »
      // de « deja utilise » dirait a un porteur de code devine si son texte a
      // existe. Le message donne les deux possibilites, l'utilisateur tranche par
      // le geste : il redemande un code.
      envoyer(res, 403, { erreur: 'code inconnu ou deja utilise', detail: 'les codes ne servent qu une fois et expirent en deux minutes' })
      return tracer(req, 403)
    }
    // Consommation IMMEDIATE, avant toute écriture.
    codes.delete(code)
    echanges.push(maintenant)
    if (fiche.expireLe <= maintenant) {
      envoyer(res, 403, { erreur: 'code expire', detail: 'redemandez un code dans le panneau « Appairer un appareil »' })
      return tracer(req, 403, 'expire')
    }
    const credentials = coffre()
    if (credentials === null) {
      envoyer(res, 503, { erreur: 'coffre indisponible', detail: "sans coffre, aucun jeton ne peut etre range" })
      return tracer(req, 503)
    }
    const nouveau = randomBytes(32).toString('base64url')
    const porteeNouvelle = porteeDemandee(process.env.DSH_REMOTE_PORTEE)
    const entree = {
      token: nouveau,
      portee: porteeNouvelle,
      creeLe: maintenant,
      nom: nomDAppareil(corps?.nom),
    }
    try {
      await ajouterAuRegistre(entree)
    } catch (erreur) {
      envoyer(res, 500, { erreur: 'ecriture du registre impossible', detail: String(erreur?.message ?? erreur) })
      return tracer(req, 500)
    }
    appareils = [...appareils, { ...entree, historique: false }]
    // Le nom de l'appareil est TRACE (il sert a designer l'appareil qu'on vient
    // d'appairer) ; le jeton ne l'est jamais, et le code non plus.
    tracer(req, 200, 'echange ' + entree.nom)
    res.writeHead(200, {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    })
    res.end(
      JSON.stringify({
        protocole: VERSION_PROTOCOLE,
        jeton: nouveau,
        portee: porteeNouvelle,
        nom: entree.nom,
        creeLe: entree.creeLe,
      }),
    )
  }

  /** LES APPAREILS APPAIRÉS — des empreintes, jamais des jetons. */
  const repondreAppareils = (req, res) => {
    envoyer(res, 200, {
      protocole: VERSION_PROTOCOLE,
      appareils: appareils.map((entree) => ({
        nom: entree.nom,
        portee: entree.portee,
        creeLe: entree.creeLe,
        empreinte: empreinteDe(entree.token),
        historique: entree.historique === true,
      })),
    })
    tracer(req, 200, appareils.length + ' appareils')
  }

  /**
   * RÉVOQUER UN APPAREIL — par sa seule EMPREINTE.
   *
   * POURQUOI ON DÉSIGNE PAR EMPREINTE, ET PAS PAR NOM. Deux appareils peuvent
   * porter le même nom (« iPhone »), et révoquer « le premier qui ressemble »
   * révoquerait le mauvais. L'empreinte est unique, elle est affichée dans la
   * liste, et elle ne permet pas de reconstruire le jeton.
   *
   * POURQUOI LA RÉVOCATION PASSE PAR LA SESSION NAVIGATEUR, et non par un jeton
   * d'appareil : un porteur de jeton ne doit pas pouvoir expulser les autres. Le
   * humain devant l'interface, lui, le peut — c'est le même geste que frapper un
   * code. Ce que cela coûte est écrit au README : qui obtient la session
   * navigateur (donc, aujourd'hui, qui obtient le cookie) peut révoquer des
   * appareils — un déni de service sur ses propres appareils, jamais une fuite.
   */
  const repondreRevocation = async (req, res, corps) => {
    const empreinte = typeof corps?.empreinte === 'string' ? corps.empreinte.trim().toLowerCase() : ''
    if (!/^[0-9a-f]{12}$/.test(empreinte)) {
      envoyer(res, 400, { erreur: 'empreinte absente ou malformee' })
      return tracer(req, 400)
    }
    const cible = appareils.find((entree) => empreinteDe(entree.token) === empreinte)
    if (cible === undefined) {
      envoyer(res, 404, { erreur: 'appareil inconnu', detail: 'cet appareil n est plus dans la liste : rechargez le panneau' })
      return tracer(req, 404)
    }
    const credentials = coffre()
    try {
      if (cible.historique === true) {
        // LE JETON HISTORIQUE SE SUPPRIME, IL NE SE FILTRE PAS : il vit dans son
        // propre enregistrement. Un jeton neuf sera tire au prochain demarrage —
        // c'est ce que « tourner le jeton » veut dire, et le README le dit.
        if (credentials === null || typeof credentials.deleteRecord !== 'function') {
          envoyer(res, 503, { erreur: 'coffre incapable de supprimer', detail: 'le service credentials n expose pas deleteRecord' })
          return tracer(req, 503)
        }
        await credentials.deleteRecord(CLE_JETON)
        jeton = null
        appareils = appareils.filter((entree) => entree !== cible)
      } else {
        if (credentials === null) {
          envoyer(res, 503, { erreur: 'coffre indisponible' })
          return tracer(req, 503)
        }
        await retirerDuRegistre(cible.token)
        appareils = appareils.filter((entree) => entree !== cible)
      }
    } catch (erreur) {
      envoyer(res, 500, { erreur: 'revocation impossible', detail: String(erreur?.message ?? erreur) })
      return tracer(req, 500)
    }
    envoyer(res, 200, { protocole: VERSION_PROTOCOLE, revoque: true, nom: cible.nom, restants: appareils.length })
    tracer(req, 200, 'revoque ' + cible.nom)
  }

  enregistrer({
    kind: 'exact',
    path: PREFIX + '/v1/appairage',
    handler: (req, res) => {
      const navigateur = serviceNavigateur()
      if (navigateur === null) {
        envoyer(res, 503, { erreur: 'authentification navigateur indisponible' })
        return tracer(req, 503)
      }
      // LE COOKIE D'ABORD : une requete refusee ne lit ni le coffre ni Tailscale.
      if (navigateur.auth.isAuthenticated(req) !== true) {
        envoyer(res, 401, { erreur: 'session navigateur requise' })
        return tracer(req, 401)
      }
      if (req.method !== 'POST') {
        envoyer(res, 405, { erreur: 'methode non autorisee' })
        return tracer(req, 405)
      }
      repondreFrappe(req, res).catch((erreur) => {
        envoyer(res, 500, { erreur: 'frappe impossible', detail: String(erreur?.message ?? erreur) })
        tracer(req, 500)
      })
    },
  })

  enregistrer({
    kind: 'exact',
    path: PREFIX + '/v1/appareils',
    handler: (req, res) => {
      const navigateur = serviceNavigateur()
      if (navigateur === null) {
        envoyer(res, 503, { erreur: 'authentification navigateur indisponible' })
        return tracer(req, 503)
      }
      if (navigateur.auth.isAuthenticated(req) !== true) {
        envoyer(res, 401, { erreur: 'session navigateur requise' })
        return tracer(req, 401)
      }
      if (req.method !== 'GET') {
        envoyer(res, 405, { erreur: 'methode non autorisee' })
        return tracer(req, 405)
      }
      repondreAppareils(req, res)
    },
  })

  enregistrer({
    kind: 'exact',
    path: PREFIX + '/v1/appareils/revoquer',
    handler: (req, res) => {
      const navigateur = serviceNavigateur()
      if (navigateur === null) {
        envoyer(res, 503, { erreur: 'authentification navigateur indisponible' })
        return tracer(req, 503)
      }
      if (navigateur.auth.isAuthenticated(req) !== true) {
        envoyer(res, 401, { erreur: 'session navigateur requise' })
        return tracer(req, 401)
      }
      if (req.method !== 'POST') {
        envoyer(res, 405, { erreur: 'methode non autorisee' })
        return tracer(req, 405)
      }
      lireCorps(req)
        .then((corps) => {
          if (corps === null) {
            envoyer(res, 400, { erreur: 'corps illisible' })
            return tracer(req, 400)
          }
          return repondreRevocation(req, res, corps)
        })
        .catch((erreur) => {
          envoyer(res, 500, { erreur: 'revocation impossible', detail: String(erreur?.message ?? erreur) })
          tracer(req, 500)
        })
    },
  })

  // ── POST /dsh-remote/v1/appairage/echange — route NATIVE (aucun Origin) ─────
  enregistrer({
    kind: 'exact',
    path: PREFIX + '/v1/appairage/echange',
    handler: (req, res) => {
      // Elle n'est PAS gatée par le cookie : c'est un appareil qui n'en a pas
      // encore. Ce qui la garde, c'est le code lui-même — mais la discipline
      // commune reste : aucun `Origin`, donc aucun navigateur.
      if (req.headers.origin !== undefined) {
        envoyer(res, 403, { erreur: 'origine refusee' })
        return tracer(req, 403)
      }
      if (req.method !== 'POST') {
        envoyer(res, 405, { erreur: 'methode non autorisee' })
        return tracer(req, 405)
      }
      lireCorps(req)
        .then((corps) => {
          if (corps === null) {
            envoyer(res, 400, { erreur: 'corps illisible' })
            return tracer(req, 400)
          }
          return repondreEchange(req, res, corps)
        })
        .catch((erreur) => {
          envoyer(res, 500, { erreur: 'echange impossible', detail: String(erreur?.message ?? erreur) })
          tracer(req, 500)
        })
    },
  })

  /**
   * Répond `304 Not Modified` : la liste n'a pas bougé depuis la dernière fois.
   *
   * POURQUOI UNE RÉPONSE À PART, ET POURQUOI ELLE PORTE L'EN-TÊTE. Un `304` est
   * la seule réponse de ce plugin qui n'a pas de corps : elle ne peut donc pas
   * passer par `envoyer`, qui sérialise une charge. Les règles de cache valent
   * aussi pour elle (`no-store`), sans quoi un intermédiaire pourrait la garder.
   */
  /**
   * La requête porte-t-elle DÉJÀ l'empreinte de la liste courante ?
   *
   * L'en-tête `If-None-Match` peut arriver sous trois formes — chaîne, tableau
   * (en-tête répété), ou liste séparée par des virgules — et un client qui
   * n'envoie rien reçoit simplement la liste, comme avant. La comparaison est
   * exacte, et non un « contient » approximatif : deux `ETag` forts ne sont égaux
   * que s'ils sont identiques.
   */
  const listeInchangee = (req, empreinte) => {
    const brut = req.headers['if-none-match']
    const presented = Array.isArray(brut) ? brut.join(',') : typeof brut === 'string' ? brut : ''
    if (presented.length === 0) return false
    if (presented.trim() === '*') return true
    return presented.split(',').some((element) => element.trim() === empreinte)
  }

  const repondreListe = async (req, res, demande) => {
    // Toute erreur est convertie en reponse JSON explicite. Une exception non
    // rattrapee ici deviendrait un 400 vide, indiscernable d'une requete
    // malformee — et donc indebogable depuis le client.
    try {
      const resultat = await listerSessions(demande)
      // RIEN N'A CHANGÉ : on répond AVANT de sérialiser quoi que ce soit. C'est
      // tout le gain — l'ancien chemin construisait les 115 Kio (et les comptait
      // pour `content-length`) pour les envoyer à un client qui les avait déjà.
      if (typeof resultat.empreinte === 'string' && listeInchangee(req, resultat.empreinte)) {
        envoyerNonModifie(res, resultat.empreinte)
        tracer(req, 304, 'liste inchangee')
        return
      }
      // L'EMPREINTE EST UN EN-TÊTE, PAS UN CHAMP DU CONTRAT. Elle ne doit donc
      // PAS entrer dans le corps : un client qui l'y lirait en ferait une donnée
      // de protocole, et le fixture partagé avec le Swift ne la connaît pas.
      const { empreinte, ...publie } = resultat
      envoyer(res, 200, { protocole: VERSION_PROTOCOLE, ...publie }, empreinte)
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
        // LA PORTÉE SE VÉRIFIE AVANT TOUTE ACTION, et après la méthode : une
        // requête mal formée se refuse sans révéler l'état du droit d'écriture.
        if (refuserSiLectureSeule(req, res)) return
        // Le service est resolu ICI, a la requete. Voir `controleurEcriture` :
        // fourni tardivement, il serait `undefined` pour toujours si on le
        // lisait au chargement du plugin.
        const controleur = controleurEcriture()
        if (controleur === null) {
          // `controleur?.` et non `controleur.` : `ctx.get` rend `undefined` quand le
          // service est absent, et lire une propriete de `undefined` LEVE. L'exception
          // remontait au serveur web, qui la convertissait en `400` vide — ni corps,
          // ni trace, ni cause. C'est ce qui a rendu cette panne si longue a voir.
          envoyer(res, 503, {
            erreur: 'ecriture indisponible',
            detail: "le service sessionController n'est pas monte dans cette composition",
          })
          return tracer(req, 503)
        }
        // Une session froide n'est PAS un refus : le controleur la reprend
        // (resolution ou reprise) avant d'adresser le prompt, exactement comme
        // l'interface web. On le dit dans la reponse plutot que de l'interdire.
        const reprise = !estVivante(identifiant)
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
            if (texte.length > 200000) {
              envoyer(res, 413, { erreur: 'texte trop long', limite: 200000 })
              return tracer(req, 413)
            }
            const mode = corps.mode === 'steer' ? 'steer' : 'queue'
            // Idempotence : un client mobile qui rejoue apres une coupure reseau
            // renvoie le MEME identifiant, et le harness rend alors l'acceptation
            // d'origine sans inserer un second message. Sans cela, une reponse
            // perdue se paie par un doublon dans la conversation.
            const requestId =
              typeof corps.requestId === 'string' && /^[A-Za-z0-9_-]{8,64}$/.test(corps.requestId)
                ? corps.requestId
                : randomBytes(16).toString('hex')
            const demande = {
              requestId,
              sessionId: identifiant,
              mode,
              content: [{ type: 'text', text: texte }],
            }
            if (typeof corps.fuseau === 'string' && corps.fuseau.length > 0) demande.clientTimeZone = corps.fuseau
            try {
              const valeur = await controleur.prompt(demande, new AbortController().signal)
              envoyer(res, 202, {
                protocole: VERSION_PROTOCOLE,
                accepte: valeur?.accepted === true,
                mode,
                requestId,
                reprise,
              })
              // Jamais le TEXTE du prompt dans le journal : il peut contenir
              // n'importe quoi, y compris ce que l'utilisateur ne veut pas voir
              // recopie dans un terminal. Seule sa longueur est tracee.
              tracer(req, 202, 'prompt ' + mode + ', ' + texte.length + ' caracteres')
            } catch (erreur) {
              // Les codes viennent du controleur ; on les traduit en statuts
              // plutot que de tout rendre en `500`, sinon le client ne peut pas
              // distinguer « reessayez » de « ca ne marchera jamais ».
              const code = typeof erreur?.code === 'string' ? erreur.code : ''
              const statuts = {
                'gateway/bad-request': 400,
                'session/attachment-invalid': 400,
                'session/invalid-time-zone': 400,
                'session/not-found': 404,
                'session/agent-busy': 409,
                'session/model-unavailable': 409,
                'session/steer-unavailable': 409,
              }
              const statut = statuts[code] ?? 502
              envoyer(res, statut, {
                erreur: 'envoi refuse',
                code: code.length > 0 ? code : null,
                detail: String(erreur?.message ?? erreur),
              })
              tracer(req, statut, 'prompt refuse ' + (code.length > 0 ? code : 'sans code'))
            }
          })
          .catch((erreur) => {
            envoyer(res, 500, { erreur: 'envoi impossible', detail: String(erreur?.message ?? erreur) })
            tracer(req, 500)
          })
        return
      }

      // ── Annuler le tour en cours : la contrepartie de l'ecriture ───────────
      //
      // Depuis un telephone, on ecrit souvent pour ARRETER ce qu'on a lance. Un
      // envoi sans annulation oblige a revenir au Mac, ce qui vide la fonction
      // de son interet. L'annulation conserve la file : `cancel` est appele avec
      // `keepInbox: true` par le controleur, donc ce qui attend son tour attend
      // toujours.
      if (action === 'annuler') {
        // Même barrière que l'écriture : annuler un tour MODIFIE l'état du
        // harness, et un jeton en lecture seule ne le fait pas.
        if (refuserSiLectureSeule(req, res)) return
        if (req.method !== 'POST') {
          envoyer(res, 405, { erreur: 'methode non autorisee' })
          return tracer(req, 405)
        }
        const controleur = controleurEcriture()
        if (controleur === null || typeof controleur.cancel !== 'function') {
          envoyer(res, 503, {
            erreur: 'annulation indisponible',
            detail: "le service sessionController n'est pas monte dans cette composition",
          })
          return tracer(req, 503)
        }
        // `Promise.resolve().then(...)` et NON `Promise.resolve(cancel(...))` :
        // `cancel` LEVE de facon synchrone quand la session n'est pas vivante.
        // L'appeler en argument l'executait HORS de la chaine, l'exception
        // remontait au serveur web et ressortait en `400` vide — sans corps, ni
        // trace, ni cause. Meme piege que `undefined.prompt`, meme remede :
        // toute lecture ou tout appel susceptible de lever va DANS la chaine.
        Promise.resolve()
          .then(() => controleur.cancel({ sessionId: identifiant }))
          .then((valeur) => {
            envoyer(res, 202, { protocole: VERSION_PROTOCOLE, annule: valeur?.accepted === true })
            tracer(req, 202, 'annulation')
          })
          .catch((erreur) => {
            const code = typeof erreur?.code === 'string' ? erreur.code : ''
            const statut = code === 'session/not-found' ? 404 : code === 'gateway/bad-request' ? 400 : 502
            envoyer(res, statut, {
              erreur: 'annulation refusee',
              code: code.length > 0 ? code : null,
              detail: String(erreur?.message ?? erreur),
            })
            tracer(req, statut, 'annulation refusee ' + (code.length > 0 ? code : 'sans code'))
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
  // PROTOCOLE. Le client ouvre, puis envoie UN message JSON :
  //   { "type": "demarrer", "session": "<id>", "depuisSeq": <n|null> }
  // Le serveur repond :
  //   { "type": "base",  "session": {...}, "enregistrements": [...], "dernierSeq": n }
  //   { "type": "evenement", "enregistrement": {...} }
  //   { "type": "delta", "dernierSeq": n }
  //   { "type": "tronque", "message": "..." }  quand la fenetre de lecture n'a pas suffi
  //   { "type": "erreur", "message": "..." }
  //
  // UN FLUX SUIT UNE SEULE SESSION. Un second `demarrer` sur la meme socket est
  // REFUSE, et la connexion reste ouverte : deux `demarrer` qui se croisent
  // reecriraient `chemin`, `offset` et `seuilReprise` dans un ordre non
  // deterministe, et le journal afficherait un melange de deux sessions. Fermer
  // la socket punirait le direct en cours pour une faute du client, alors qu'un
  // refus explicite se lit et se corrige.
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
  // DEUX PINGS SANS PONG, ET LA SOCKET EST DECLAREE MORTE.
  //
  // POURQUOI CE DELAI EXISTE, ALORS QUE LE SERVEUR ENVOYAIT DEJA UN PING. Un ping
  // sans lecteur ne prouve rien : la reponse arrivait — la plateforme du client y
  // repond toute seule — et PERSONNE ne la regardait. Un telephone dont la radio
  // s'eteint sans fermer la connexion laissait donc son minuteur vivant, et le
  // serveur continuait de `stat` et de relire 64 Kio de journal toutes les 750 ms
  // pour un appareil qui n'etait plus la. Le controle qui manquait n'est pas
  // l'envoi, c'est L'ECHEANCE.
  //
  // DEUX PINGS, ET PAS UN : un ping peut se perdre, ou son pong arriver apres
  // l'echeance sur un reseau mobile. Deux manques d'affilee, c'est une minute
  // sans aucune reponse — un appareil qui n'est plus joignable, pas un a-coup.
  // C'est une FILET DE SECURITE, pas le mecanisme principal : un client qui bat
  // la mesure (l'application le fait toutes les 15 s) voit la coupure bien avant.
  const DELAI_PONG_MS = 2 * PING_FLUX_MS
  const MAX_TAMPON_EN_ATTENTE = 4 * 1024 * 1024
  // L'INTERVALLE DE SCRUTATION QUAND LE BUS REPOND : cinq secondes au lieu de
  // 750 ms. Ce n'est PAS une suppression — le disque reste la seule source pour
  // une session ecrite par un AUTRE processus —, c'est un filet qu'on espace
  // puisque les evenements de CE processus arrivent par le bus.
  const INTERVALLE_FLUX_RELAIS_MS = 5000

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

  // ── LE BUS DU HARNESS, QUAND IL EST LÀ ──────────────────────────────────────
  //
  // POURQUOI UNE SEULE TABLE POUR TOUTES LES SESSIONS. `session/event` est emis a
  // la RACINE, avec la session pour portee : un seul ecouteur suffit donc, et la
  // diffusion se fait par identifiant. Poser un ecouteur par connexion ferait
  // autant d'ecouteurs que de flux ouverts, pour le meme resultat.
  //
  // CE QU'ON LIT D'UN OBJET VIVANT : `session.id`, et rien d'autre. L'evenement,
  // lui, est gele et deja JSON (`dsh-session` le valide et le fige a l'append) —
  // c'est la seule forme sous laquelle il est transmis.
  const abonnes = new Map()
  let busDisponible = false
  try {
    ctx.on('session/event', (session, evenement) => {
      const identifiant = typeof session?.id === 'string' ? session.id : null
      if (identifiant === null) return
      const pour = abonnes.get(identifiant)
      if (pour === undefined) return
      for (const abonne of pour) abonne.diffuser(evenement)
    })
    ctx.on('agent/status', (charge) => {
      const identifiant = identifiantDeLagent(charge?.agent)
      if (identifiant === null) return
      const pour = abonnes.get(identifiant)
      if (pour === undefined) return
      const statut = charge?.status === 'running' ? 'en_cours' : 'inactif'
      for (const abonne of pour) abonne.statut(statut)
    })
    busDisponible = true
  } catch {
    // Le harness a change de forme : on garde la scrutation disque, et rien
    // d'autre ne change. C'est la meme degradation que pour les autres API.
    busDisponible = false
  }

  /** L'inscription des connexions au bus — `null` quand il n'y a pas de bus. */
  const diffusion = busDisponible
    ? {
        abonner(identifiant, diffuser, statut) {
          const pour = abonnes.get(identifiant) ?? new Set()
          pour.add({ diffuser, statut })
          abonnes.set(identifiant, pour)
        },
        retirer(identifiant, diffuser, statut) {
          const pour = abonnes.get(identifiant)
          if (pour === undefined) return
          for (const abonne of pour) {
            if (abonne.diffuser === diffuser && abonne.statut === statut) pour.delete(abonne)
          }
          if (pour.size === 0) abonnes.delete(identifiant)
        },
      }
    : null

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
        const accept = accepterWebSocket(cle)
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
        // Pose SYNCHRONEMENT a l'acceptation du premier `demarrer`, et jamais
        // remis a zero : c'est ce qui rend le refus du second possible avant que
        // le premier ait fini sa lecture disque (qui est asynchrone).
        let demarre = false
        // L'INSTANT DU DERNIER PONG. Initialise a l'ouverture de la connexion :
        // une socket qui vient de naitre n'est pas en retard, elle n'a simplement
        // pas encore eu de ping a honorer.
        let dernierPong = Date.now()
        // L'IDENTIFIANT SUIVI, pour pouvoir SE DESABONNER du bus a la fermeture.
        // Pose des que le premier `demarrer` est accepte, comme `demarre`.
        let suivie = null
        // L'ASSEMBLEUR DE TRAMES, PAR CONNEXION : une fragmentation est un etat de
        // la CONNEXION, pas de la trame. Le partager entre connexions melangerait
        // les morceaux de deux clients.
        const assembleur = creerAssembleur()

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

        /**
         * Diffuse un evenement ARRIVE PAR LE BUS, sans attendre le tour de minuterie.
         *
         * POURQUOI CE CHEMIN EXISTE. La scrutation disque coute ce qu'elle coute —
         * un `stat` par tour, et une relecture de 64 Kio des que la taille bouge —
         * et elle ajoute jusqu'a son intervalle de latence a ce que l'agent vient
         * d'ecrire. Le harness EMET chaque enregistrement en memoire au moment ou
         * il est valide (`session/event`, emis synchronement a l'append), donc le
         * plugin peut le pousser tout de suite.
         *
         * CE QU'IL NE FAIT PAS : remplacer le disque. Le journal reste la source de
         * la `base` et de la reprise, et la scrutation continue — ralentie — pour
         * une session ecrite par un AUTRE processus, que le bus de celui-ci ne voit
         * pas. On ajoute une source rapide, on ne retire pas la source sure.
         *
         * CE QU'IL NE FAIT PAS NON PLUS : serialiser un objet vivant du harness. Il
         * ne lit QUE `seq` (un nombre) et transmet l'enregistrement, qui est gele et
         * deja JSON par construction (`dsh-session` le valide et le fige a l'append).
         *
         * @param {object} enregistrement
         */
        const diffuser = (enregistrement) => {
          if (ferme) return
          const seq = enregistrement?.seq
          if (typeof seq !== 'number' || seq <= seuilReprise) return
          envoyer({ type: 'evenement', enregistrement })
          seuilReprise = seq
          envoyer({ type: 'delta', dernierSeq: seq })
        }

        /**
         * Diffuse un CHANGEMENT DE STATUT — `en_cours` / `inactif`.
         *
         * POURQUOI CE MESSAGE EXISTE. Les pastilles de la liste sont ce que
         * l'utilisateur regarde pour savoir si quelque chose travaille, et elles
         * n'etaient rafraichies que par la boucle HTTP de trois secondes. Le
         * harness, lui, emet `agent/status` a chaque transition : le pousser divise
         * la latence percue, et evite a l'application de reveiller sa radio pour
         * l'apprendre.
         */
        const diffuserStatut = (statut) => {
          if (ferme || statut === null) return
          envoyer({ type: 'statut', statut })
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

          // LE BUS PREND LE RELAIS QUAND IL EXISTE, ET LA SCRUTATION DEVIENT UN
          // FILET. Tant que le harness emet ses evenements en memoire, les pousser
          // est immediat ; le disque reste lu, mais cinq fois moins souvent, pour
          // une session ecrite par un AUTRE processus. Sans bus (composition
          // differente, API disparue), on garde exactement le comportement d'avant.
          // LA CONNEXION A-T-ELLE ETE FERMEE PENDANT LA LECTURE DISQUE ? C'est un
          // cas REEL, et il etait un vrai defaut : `demarrer` lit un journal (donc
          // attend), et pendant cette attente le client peut fermer, ou une faute
          // de protocole fermer a sa place. Les minuteurs crees ici l'etaient ALORS
          // QUE PLUS RIEN NE LES ARRETERAIT — le gestionnaire de fermeture avait
          // deja tourne —, et le serveur scrutait le disque pour une socket morte,
          // pour toujours. Trouve par le test du reassemblage : une continuation
          // orpheline ferme en 1002 pendant que le `demarrer` est encore en vol.
          if (ferme) return
          if (diffusion !== null) {
            diffusion.abonner(identifiant, diffuser, diffuserStatut)
            suivie = identifiant
          }
          const intervalle = diffusion === null ? INTERVALLE_FLUX_MS : INTERVALLE_FLUX_RELAIS_MS
          if (minuteur !== null) clearInterval(minuteur)
          minuteur = setInterval(() => {
            interroger()
          }, intervalle)
          if (minuteurPing === null) {
            minuteurPing = setInterval(() => {
              if (ferme) return
              // L'ECHEANCE EST VERIFIEE AVANT D'ENVOYER : un client qui n'a plus
              // repondu depuis deux pings est mort, et continuer a lui ecrire ne
              // ferait que garder son minuteur de lecture en vie — donc le `stat`
              // et la decompression toutes les 750 ms pour personne.
              if (Date.now() - dernierPong >= DELAI_PONG_MS) return arreter(1008)
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
            // LE RÉASSEMBLAGE EST ICI, ET PAS DANS LA BOUCLE DE LECTURE : un
            // message peut arriver en plusieurs trames (RFC 6455 § 5.4), et un
            // client qui fragmente doit être SERVI, pas ignoré en silence.
            const assemble = assembleur.ajouter(trame)
            if (assemble.erreur !== null) return arreter(assemble.erreur)
            for (const controle of assemble.controle) {
              if (controle.opcode === 0x8) return arreter(1000)
              if (controle.opcode === 0x9) {
                socket.write(tramePong(controle.charge))
                continue
              }
              // PONG : la reponse qui prouve que le client est vivant. Elle etait
              // ignoree — `!== 0x1` — donc l'echeance ci-dessus n'aurait jamais
              // pu avoir de sens.
              dernierPong = Date.now()
            }
            for (const message of assemble.messages) {
              // Seul le TEXTE porte une commande : du binaire n'a rien a faire
              // ici, et l'ignorer vaut mieux que de le lire comme du JSON.
              if (message.opcode !== 0x1) continue
              let commande = null
              try {
                commande = JSON.parse(message.charge.toString('utf8'))
              } catch {
                commande = null
              }
              if (commande === null || commande.type !== 'demarrer') {
                envoyer({ type: 'erreur', message: 'premier message attendu: demarrer' })
                continue
              }
              if (demarre) {
                // Le refus ne porte AUCUN identifiant de session : le client connait
                // deja celui de son flux, et le repeter n'apprendrait rien.
                envoyer({ type: 'erreur', message: 'un flux suit deja une session' })
                continue
              }
              demarre = true
              const identifiant = typeof commande.session === 'string' ? commande.session : ''
              const depuisSeq = typeof commande.depuisSeq === 'number' ? commande.depuisSeq : null
              demarrer(identifiant, depuisSeq).catch((erreur) => {
                envoyer({ type: 'erreur', message: String(erreur?.message ?? erreur) })
                arreter(1011)
              })
            }
          }
        })
        socket.on('error', () => arreter(1011))
        socket.on('close', () => {
          ferme = true
          if (minuteur !== null) clearInterval(minuteur)
          if (minuteurPing !== null) clearInterval(minuteurPing)
          // SE DESABONNER EST AUSSI IMPORTANT QUE S'ABONNER : sans cela, une
          // connexion morte resterait dans la table du bus, et chaque evenement
          // d'une session regardee une fois serait diffuse a une socket fermee —
          // pour toujours, sur un serveur qui vit des jours.
          if (diffusion !== null && suivie !== null) diffusion.retirer(suivie, diffuser, diffuserStatut)
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
    // LES DEUX CACHES SONT VIDES ICI, ET PAS SEULEMENT CELUI DES FAITS : le cache
    // de texte tiendrait sinon des journaux entiers apres le retrait des routes —
    // de la memoire du harness gardee pour un plugin qui n'est plus monte.
    viderLesCaches()
    console.log('[dsh-remote] routes retirees')
  }

  chargerJeton()
    .then(async (valeur) => {
      jeton = valeur
      // LE REGISTRE EST CHARGE APRES LE JETON, dans le meme enchainenement : la
      // liste des appareils contient l'historique EN PREMIER, donc `jeton` doit
      // deja etre connu. Un registre illisible ne doit pas rendre le jeton
      // historique inutilisable : on journalise, et on continue avec lui seul.
      try {
        appareils = await chargerAppareils()
      } catch (erreur) {
        appareils = jeton === null ? [] : [{ token: jeton, portee, creeLe: null, nom: 'jeton historique (terminal)', historique: true }]
        console.log('[dsh-remote] registre des appareils illisible: ' + String(erreur?.message ?? erreur))
      }
      if (valeur === null) {
        console.log('[dsh-remote] aucune authentification possible: routes inutilisables (401)')
        return
      }
      console.log(
        '[dsh-remote] pret: ' +
          PREFIX +
          '/v1/sante, /v1/sessions, /v1/espaces, /v1/serveurs, /v1/session/<id>, /v1/session/<id>/prompt, /v1/session/<id>/annuler, ws /v1/flux',
      )
      console.log('[dsh-remote] appairage (navigateur): POST ' + PREFIX + '/v1/appairage, GET ' + PREFIX + '/v1/appareils, POST ' + PREFIX + '/v1/appareils/revoquer')
      console.log('[dsh-remote] appairage (appareil): POST ' + PREFIX + '/v1/appairage/echange — ' + appareils.length + ' appareil(s) connu(s)')
    })
    .catch((erreur) => {
      console.log('[dsh-remote] ECHEC du chargement du jeton: ' + String(erreur?.message ?? erreur))
    })
}
