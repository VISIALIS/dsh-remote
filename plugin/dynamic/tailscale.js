/**
 * LA DÉCOUVERTE DU TAILNET : quelles machines sont en ligne, et lesquelles
 * peuvent héberger DSH.
 *
 * POURQUOI CE FICHIER EXISTE. Ce bloc vivait au milieu d'un fichier de 1 637
 * lignes, mêlé aux routes et au cache. Il ne dépend pourtant que d'une chose :
 * le binaire LOCAL de Tailscale. Le sortir rend ses deux fonctions d'analyse
 * éprouvables — `analyserTailnet` et `raisonCourte` sont PURES, et elles portent
 * des règles mesurées (voir plus bas).
 *
 * HORS DSH : la découverte lance le binaire local (`node:child_process`, argv
 * fixe, sans shell). Ce n'est ni une API DSH ni une API distante : c'est un état
 * déjà présent sur la machine. Si le binaire manque ou refuse de répondre, la
 * route rend une liste vide AVEC sa raison, et le reste du plugin fonctionne.
 */

import { execFile } from 'node:child_process'
import { constants as constantesFS } from 'node:fs'
import { access } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join } from 'node:path'

// Candidats, essayés DANS CET ORDRE JUSQU'À UN SUCCÈS — et non jusqu'au premier
// fichier exécutable. La distinction est mesurée : sur cette machine,
// `/usr/local/bin/tailscale` est un lien symbolique vers le binaire de
// l'application, et le lancer par ce lien échoue (« The current bundleIdentifier
// is unknown to the registry ») alors que le binaire direct réussit. Un lien
// perd l'identité de bundle dont le CLI a besoin pour joindre l'application.
//
// ET SUR WINDOWS ? Le CLI y vit dans `…\Tailscale\tailscale.exe`. Ce chemin est
// écrit d'après l'emplacement d'installation standard, et **il n'a pas été
// mesuré** : cette installation-ci est un Mac. Le dernier candidat est le NOM NU,
// que `execFile` résout par le PATH — c'est lui qui sauvera le cas si
// l'emplacement diffère, et c'est pourquoi un nom nu n'est pas soumis au test
// d'existence ci-dessous (`access` résout relativement au dossier courant, pas
// dans le PATH).
const CHEMINS_TAILSCALE =
  process.platform === 'win32'
    ? [
        join(process.env.ProgramFiles ?? 'C:\\Program Files', 'Tailscale', 'tailscale.exe'),
        ...(typeof process.env.LOCALAPPDATA === 'string' && process.env.LOCALAPPDATA.length > 0
          ? [join(process.env.LOCALAPPDATA, 'Tailscale', 'tailscale.exe')]
          : []),
        'tailscale.exe',
      ]
    : [
        '/Applications/Tailscale.app/Contents/MacOS/Tailscale',
        '/opt/homebrew/bin/tailscale',
        '/usr/local/bin/tailscale',
        // Linux : la distribution décide de l'emplacement, et un paquet peut
        // l'installer ailleurs. Le nom nu laisse le PATH trancher.
        'tailscale',
      ]

// LES SYSTÈMES QUI PEUVENT HÉBERGER DSH — ET CEUX QUI NE LE PEUVENT PAS.
//
// POURQUOI CETTE RÈGLE A CHANGÉ. Elle ne retenait que `macOS` : « proposer un PC
// Windows ou un iPhone comme serveur DSH serait une promesse que l'installation
// ne peut pas tenir ». La prémisse était fausse, et le propriétaire l'a relevée :
// « il y a un serveur windows qui n'est pas listé, or le serveur DSH est
// universel non ? c'est juste le remote qui est macOS ou iOS ». Mesuré : le
// harness DSH tourne aussi sur Windows (il publie un bac à sable Windows ACL) et
// sur Linux. C'est l'APPLICATION CLIENT qui est macOS et iOS — pas l'hôte.
//
// Ce qui reste écarté, ce sont les systèmes qui ne peuvent pas exécuter de
// processus : iOS, iPadOS, Android, tvOS. Un iPhone ne peut pas héberger DSH, et
// le proposer serait la promesse intenable qu'on voulait éviter. La liste est
// donc une LISTE BLANCHE : un système inconnu n'est pas proposé.
//
// CE QUE LA LISTE NE PROMET PAS : qu'une machine donnée serve DSH. Elle dit
// qu'elle POURRAIT l'héberger ; c'est la sonde du client qui tranche, et une
// machine qui ne répond pas s'affiche « pas de DSH » — sans mensonge.
const SYSTEMES_QUI_HEBERGENT = new Set(['macOS', 'windows', 'linux'])

const DELAI_TAILSCALE_MS = 8000
const PLAFOND_SORTIE_TAILSCALE = 4 * 1024 * 1024

/** Un candidat est-il un CHEMIN, plutôt qu'un nom à chercher dans le PATH ? */
const estUnChemin = (candidat) => candidat.includes('/') || candidat.includes('\\')

/**
 * Une machine du tailnet telle que la découverte la propose. `local` marque
 * l'hôte qui répond — c'est-à-dire celui qui exécute cette instance, information
 * que seul l'hôte connaît.
 * @typedef {{nom: string, nomDNS: string, enLigne: boolean, local: boolean}} MachineTrouvee
 */

/**
 * Analyse la sortie de `tailscale status --json`.
 *
 * Séparée de l'exécution pour être éprouvable sans lancer de processus, comme
 * côté Swift. Ne retient que `Self` et `Peer`, et seulement les systèmes qui
 * PEUVENT héberger DSH (voir `SYSTEMES_QUI_HEBERGENT`) : un iPhone ne le peut
 * pas, un PC Windows si.
 *
 * @param {string} sortie
 * @returns {MachineTrouvee[] | null} `null` si la sortie n'a pas la forme attendue.
 */
export function analyserTailnet(sortie) {
  const racine = JSON.parse(sortie)
  if (racine === null || typeof racine !== 'object') return null

  const trouves = []
  const retenir = (objet, local) => {
    if (objet === null || typeof objet !== 'object') return
    if (!SYSTEMES_QUI_HEBERGENT.has(objet.OS)) return
    const dns = typeof objet.DNSName === 'string' ? objet.DNSName : ''
    if (dns.length === 0) return
    // Le point final est la forme absolue du DNS : on le retire pour que le nom
    // soit directement utilisable comme adresse.
    const nomDNS = dns.endsWith('.') ? dns.slice(0, -1) : dns
    const nom = typeof objet.HostName === 'string' && objet.HostName.length > 0 ? objet.HostName : nomDNS
    trouves.push({ nom, nomDNS, enLigne: local ? true : objet.Online === true, local })
  }

  retenir(racine.Self, true)
  if (racine.Peer !== null && typeof racine.Peer === 'object') {
    for (const valeur of Object.values(racine.Peer)) retenir(valeur, false)
  }

  // En ligne d'abord, puis par nom : l'ordre doit être stable d'un appel à
  // l'autre, sinon la liste semble sauter sous les yeux de l'utilisateur.
  return trouves.sort((gauche, droite) => {
    if (gauche.enLigne !== droite.enLigne) return gauche.enLigne ? -1 : 1
    return gauche.nom.localeCompare(droite.nom, 'fr')
  })
}

/**
 * Réduit un message d'erreur à une ligne courte, sans retour à la ligne.
 *
 * Le diagnostic est utile — il distingue « binaire absent » de « Tailscale
 * refuse de répondre » — mais il part dans une réponse HTTP : il est tronqué et
 * débarrassé de ses sauts de ligne pour rester un champ de texte, pas un journal.
 */
export function raisonCourte(texte) {
  const ligne = String(texte ?? '').split('\n').find((element) => element.trim().length > 0) ?? ''
  const propre = ligne.replace(/\s+/g, ' ').trim()
  return propre.length > 120 ? propre.slice(0, 120) : propre
}

/**
 * Liste les machines du tailnet qui POURRAIENT héberger DSH, vues depuis celle-ci.
 *
 * Ne lève jamais : une découverte impossible rend une liste vide AVEC sa raison,
 * parce qu'une liste vide sans explication est indébogable — on ne sait pas si
 * le binaire manque, si Tailscale est arrêté ou si la sortie est illisible, et
 * ces trois causes ne se corrigent pas de la même façon.
 *
 * @returns {Promise<{machines: MachineTrouvee[], diagnostic: string | null}>}
 */
export async function decouvrirMachines() {
  const raisons = []
  for (const binaire of await candidatsTailscale()) {
    const { sortie, raison } = await lancerBinaire(binaire, ['status', '--json'])
    if (sortie === null) {
      raisons.push(raison)
      continue
    }
    let machines = null
    try {
      machines = analyserTailnet(sortie)
    } catch {
      raisons.push('sortie illisible')
      continue
    }
    if (machines === null) {
      raisons.push('sortie inattendue')
      continue
    }
    return {
      machines,
      diagnostic: machines.length === 0 ? 'aucune machine du tailnet' : null,
    }
  }

  if (raisons.length === 0) return { machines: [], diagnostic: 'binaire tailscale introuvable' }
  return { machines: [], diagnostic: 'tailscale muet: ' + raisons[0] }
}

// ── SOUS QUEL SCHÉMA CETTE MACHINE SE PUBLIE-T-ELLE ? ─────────────────────────
//
// POURQUOI CETTE SECONDE LECTURE, ET POURQUOI ELLE EST INDISPENSABLE. Le contrat
// d'appairage écrivait `http://<hote>` en dur, et l'application visait donc le
// port 80 — même quand le Mac est publié en HTTPS sur 443 par
// `tailscale serve --https`. Passer le serveur en HTTPS ne suffisait alors à
// rien : le QR continuait de donner l'adresse en clair, et ATS refusait la
// connexion (`-1022`) ou le port ne répondait plus. Le schéma est un FAIT de
// publication : il se LIT, il ne se devine pas.
//
// `tailscale serve status --json` le dit, et sa forme est MESURÉE sur cette
// installation (publication en clair sur le port 80) :
//
//   { "TCP": { "80": { "HTTP": true } },
//     "Web": { "macmini.<tailnet>.ts.net:80": { "Handlers": { "/": { "Proxy": "http://127.0.0.1:3080" } } } } }
//
// La branche HTTPS (`"443": { "HTTPS": true }` et une clé `…:443`) suit la même
// forme — c'est la documentation de Tailscale — mais elle n'a PAS été mesurée
// ici : cette installation publie en clair. Elle est donc écrite pour être
// TOLÉRANTE (on lit le drapeau du port, on ne le suppose pas) plutôt que pour
// décrire une sortie qu'on n'a pas vue.
/**
 * Analyse la sortie de `tailscale serve status --json`.
 *
 * @param {string} texte
 * @returns {{schema: 'http'|'https', port: number, hote: string} | null} `null`
 *   quand rien n'est publié, ou quand la sortie n'est pas celle attendue.
 */
export function publicationDepuisServe(texte) {
  let racine = null
  try {
    racine = JSON.parse(texte)
  } catch {
    return null
  }
  if (racine === null || typeof racine !== 'object' || Array.isArray(racine)) return null
  const web = racine.Web
  if (web === null || typeof web !== 'object' || Array.isArray(web)) return null
  const tcp = racine.TCP !== null && typeof racine.TCP === 'object' ? racine.TCP : {}

  let enClair = null
  for (const [cle, valeur] of Object.entries(web)) {
    const correspondance = /^([^:]+):(\d{1,5})$/.exec(cle)
    if (correspondance === null) continue
    // ON NE RETIENT QUE CE QUI SERT DSH : une publication vers une AUTRE machine
    // (ou vers un dossier statique) ne dit rien du schéma à donner au téléphone.
    if (!proxifieVersLaBoucleLocale(valeur)) continue
    const port = Number(correspondance[2])
    const drapeaux = tcp[String(port)]
    const schema =
      drapeaux !== null && typeof drapeaux === 'object' && drapeaux.HTTPS === true
        ? 'https'
        : drapeaux !== null && typeof drapeaux === 'object' && drapeaux.HTTP === true
          ? 'http'
          : null
    if (schema === null) continue
    // HTTPS GAGNE, MÊME SI LE CLAIR EST AUSSI PUBLIÉ : c'est le schéma que le
    // client doit préférer, et celui qui ne demande aucune exception ATS.
    if (schema === 'https') return { schema, port, hote: correspondance[1] }
    enClair = enClair ?? { schema, port, hote: correspondance[1] }
  }
  return enClair
}

/** La publication vise-t-elle la boucle locale — donc le harness de CETTE machine ? */
function proxifieVersLaBoucleLocale(entree) {
  const handlers = entree?.Handlers
  if (handlers === null || typeof handlers !== 'object') return false
  for (const handler of Object.values(handlers)) {
    const cible = handler?.Proxy
    if (typeof cible !== 'string') continue
    if (/^https?:\/\/(127\.0\.0\.1|localhost|\[::1\])(:\d+)?(\/|$)/.test(cible)) return true
  }
  return false
}

/**
 * Lit la publication de CETTE machine, ou rend `null`.
 *
 * Ne lève jamais : sans binaire, sans publication, ou devant une sortie
 * inattendue, l'appelant retombe sur le clair — c'est-à-dire sur le
 * comportement d'avant, jamais sur une adresse inventée.
 *
 * @returns {Promise<{schema: 'http'|'https', port: number, hote: string} | null>}
 */
export async function lirePublication() {
  for (const binaire of await candidatsTailscale()) {
    const { sortie } = await lancerBinaire(binaire, ['serve', 'status', '--json'])
    if (sortie === null) continue
    const publication = publicationDepuisServe(sortie)
    if (publication !== null) return publication
  }
  return null
}

/** Les candidats au lancement, dans l'ordre — le profil utilisateur compris. */
async function candidatsTailscale() {
  // `HOME` n'existe pas sur Windows : le lanceur de l'application y vit sous le
  // profil utilisateur, que `homedir()` sait trouver sur les trois systèmes.
  const maison =
    typeof process.env.HOME === 'string' && process.env.HOME.length > 0 ? process.env.HOME : homedir()
  const candidats = CHEMINS_TAILSCALE.slice()
  if (typeof maison === 'string' && maison.length > 0) {
    candidats.splice(1, 0, join(maison, '.local', 'bin', 'tailscale'))
  }
  // UN NOM NU EST RÉSOLU PAR LE PATH, et `access()` ne saurait pas le faire : il
  // résout relativement au dossier courant. On l'écarte donc du test d'existence,
  // et `execFile` cherchera dans le PATH comme le ferait un terminal.
  const retenus = []
  for (const binaire of candidats) {
    if (!estUnChemin(binaire)) {
      retenus.push(binaire)
      continue
    }
    try {
      await access(binaire, constantesFS.X_OK)
      retenus.push(binaire)
    } catch {
      // absent : candidat suivant
    }
  }
  return retenus
}

/**
 * Lance un binaire avec des arguments DONNÉS, et rend sa sortie ou `null`.
 *
 * @param {string} binaire
 * @param {string[]} arguments_
 * @returns {Promise<{sortie: string | null, raison: string | null}>}
 */
function lancerBinaire(binaire, arguments_) {
  return new Promise((resolve) => {
    execFile(
      binaire,
      arguments_,
      { timeout: DELAI_TAILSCALE_MS, maxBuffer: PLAFOND_SORTIE_TAILSCALE, windowsHide: true, encoding: 'utf8' },
      (erreur, sortie, erreurs) => {
        if (erreur !== null && erreur !== undefined) {
          if (erreur.killed === true) return resolve({ sortie: null, raison: 'delai depasse' })
          if (erreur.code === 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER') {
            return resolve({ sortie: null, raison: 'sortie trop volumineuse' })
          }
          return resolve({ sortie: null, raison: raisonCourte(erreurs) || raisonCourte(erreur.message) })
        }
        resolve({ sortie: typeof sortie === 'string' ? sortie : '', raison: null })
      },
    )
  })
}
