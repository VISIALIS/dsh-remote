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
import { decouvrirMachines } from './tailscale.js'

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
          // L'hote sait-il publier la liste des Macs du tailnet ? Un client plus
          // ancien que cette route lira `false` et gardera la saisie manuelle
          // plutot que d'attendre une liste qui ne viendra jamais.
          decouverte: true,
          // L'hote sait-il publier ses espaces de travail — y compris ceux qui
          // n'ont AUCUNE session ? Sans cette capacite, le client deduit ses
          // espaces des sessions, ce qui est le comportement d'avant.
          espaces: registreEspaces() !== null,
          ecriture: controleurEcriture() !== null,
          // Annuler le tour en cours. Meme service que l'ecriture : un client qui
          // lit `false` ne propose pas de bouton « Arreter » qui ne ferait rien.
          annulation: controleurEcriture() !== null,
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
      else console.log('[dsh-remote] pret: ' + PREFIX + '/v1/sante, /v1/sessions, /v1/espaces, /v1/serveurs, /v1/session/<id>, /v1/session/<id>/prompt, /v1/session/<id>/annuler, ws /v1/flux')
    })
    .catch((erreur) => {
      console.log('[dsh-remote] ECHEC du chargement du jeton: ' + String(erreur?.message ?? erreur))
    })
}
