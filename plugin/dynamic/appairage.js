// CONTRAT D'APPAIRAGE — la charge utile qui fait traverser un secret du Mac
// vers un appareil, une seule fois.
//
// POURQUOI CE FICHIER EXISTE SÉPARÉMENT. La charge utile est un CONTRAT ENTRE
// DEUX MOITIÉS QUI NE PARTAGENT PAS DE LANGAGE : l'hôte et le panneau sont en
// JavaScript, l'application est en Swift. Une divergence ne se verrait qu'à
// l'usage, chez l'utilisateur, sous la forme d'un « jeton invalide » qui
// n'explique rien. Le format vit donc ici, en fonctions PURES, éprouvées par
// `tests/appairage.test.js` — et les mêmes vecteurs sont rejoués côté Swift
// (`Tests/DSHRemoteKitTests/AppairageTests.swift`, fixture partagé).
//
// FORME (une seule ligne, ASCII, aucune transformation) :
//
//     dshremote://<hote>/<genre>/v1/<secret>[/<schema>]
//
//   - `<hote>`   : le nom MagicDNS SANS point final — jamais une adresse de
//                  boucle locale, jamais un port (le port est implicite : 80 pour
//                  `http`, 443 pour `https`, la convention que `tailscale serve`
//                  publie) ;
//   - `<genre>`  : `jeton` (le secret EST le jeton d'appareil) ou `code` (le
//                  secret est un code d'appairage à usage unique) ;
//   - `v1`       : la version du contrat, PAR GENRE. Un client qui ne connaît
//                  pas le genre ou la version REFUSE en le disant : envoyer un
//                  code comme jeton porteur rendrait un `401` qui n'explique
//                  rien, alors que le vrai problème est une version d'accord
//                  différente entre les deux moitiés ;
//   - `<secret>` : base64url, donc sans `/` — le découpage du chemin n'est pas
//                  ambigu ;
//   - `<schema>` : FACULTATIF, `http` ou `https`, et OMIS quand il vaut `http`.
//                  Il dit sous quel transport la machine se publie, ce que
//                  l'application ne peut pas deviner (`tailscale serve --https`
//                  change le port ET le transport). Voir `SCHEMAS`.
//
// CE QUI N'EST PAS FAIT ICI, ET POURQUOI :
//   - aucun pourcent-encodage : les quatre champs sont déjà sans caractère
//     réservé, et encoder l'adresse coûterait 15 octets sur une charge utile
//     qui doit tenir dans un QR de version 6 ;
//   - aucune écriture, aucun journal, aucune E/S : ce module ne fait que
//     transformer du texte. C'est ce qui permet de l'éprouver sans harness.

/** Le schéma de la charge utile. Un seul, jamais négocié. */
export const SCHEMA = 'dshremote'

/** Les genres connus, et ce que leur secret est. */
export const GENRE_JETON = 'jeton'
export const GENRE_CODE = 'code'

/** La version du contrat, par genre. Écrite dans la charge utile, lue par l'appareil. */
export const VERSIONS = { [GENRE_JETON]: 'v1', [GENRE_CODE]: 'v1' }

/**
 * LES TRANSPORTS QUI PEUVENT ÊTRE ANNONCÉS — et rien d'autre.
 *
 * POURQUOI UNE LISTE BLANCHE, ET PAS UNE CHAÎNE LIBRE. Le cinquième segment d'une
 * charge utile est une entrée d'un carnet d'adresses ÉCRIT PAR UNE AUTRE MACHINE :
 * `ftp://`, `file://` ou `javascript:` n'ont rien à y faire, et un client qui
 * ferait confiance à ce segment construirait une adresse qu'il n'a pas choisie.
 */
export const SCHEMAS = ['http', 'https']

/**
 * Longueur minimale d'un secret, PAR GENRE.
 *
 * POURQUOI DEUX SEUILS, ET POURQUOI AUSSI BAS. Un jeton d'appareil fait 43
 * caractères (32 octets en base64url) ; un code d'appairage en fera 22 (16
 * octets, soit 128 bits). Le seuil n'a pas à décrire le tirage — il est là pour
 * refuser une TRONCATURE : un presse-papiers qui coupe, un scan partiel, une
 * ligne recopiée à moitié. Un secret amputé d'un caractère reste donc « formé »
 * et c'est l'authentification, qui compare la valeur exacte à temps constant,
 * qui le refuse ; exiger ici la longueur exacte du tirage casserait toute
 * application le jour où le tirage grandit.
 */
export const SECRETS_MINIMUMS = { [GENRE_JETON]: 32, [GENRE_CODE]: 22 }

/** Les hôtes qui ne sont PAS une adresse de réseau : les publier ne mènerait nulle part. */
const HOTES_LOCAUX = new Set(['127.0.0.1', 'localhost', '0.0.0.0', '::1', '[::1]', '::'])

/** Un nom d'hôte acceptable : lettres, chiffres, points, tirets. Rien d'autre. */
const FORME_HOTE = /^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$/

/** Un secret acceptable : base64url, longueur bornée par le bas selon son genre. */
const FORME_SECRET = /^[A-Za-z0-9_-]+$/

/** Un code d'appairage présenté à l'échange : la forme que l'hôte SAIT avoir émise. */
const FORME_CODE = /^[A-Za-z0-9_-]{20,64}$/

/**
 * La longueur maximale d'un nom d'appareil, et son nom par défaut.
 *
 * POURQUOI UNE BORNE, ET POURQUOI ELLE EST DANS CE FICHIER. Le nom vient du
 * CLIENT — c'est-à-dire, du point de vue de l'hôte, d'une donnée NON FIABLE : il
 * finit dans la liste des appareils appairés, que l'humain lit pour décider quoi
 * révoquer. Un nom de 10 000 caractères, ou qui contient un retour à la ligne,
 * rendrait cette liste illisible — et une liste illisible est une liste où l'on
 * révoque le mauvais appareil.
 */
export const NOM_MAX = 40
export const NOM_PAR_DEFAUT = 'appareil sans nom'

/**
 * Les caractères qu'un nom ne peut PAS porter, et pourquoi chacun est nommé.
 *
 * POURQUOI UNE LISTE PLUTÔT QU'UN `trim`. Trois familles, trois dégâts distincts :
 *
 *   - les caractères de COMMANDE (C0/C1) cassent la mise en page d'une liste — un
 *     `\n` fabrique une ligne qui n'existe pas ;
 *   - les commandes BIDI (`U+202A`–`U+202E`, `U+2066`–`U+2069`) INVERSENT l'ordre
 *     d'affichage : un nom peut faire apparaître « MacMini de Camille » là où le
 *     stockage dit autre chose. C'est une usurpation d'affichage, pas une coquetterie ;
 *   - les caractères de LARGEUR NULLE (`U+200B`–`U+200D`, `U+FEFF`) rendent deux
 *     noms visuellement identiques alors qu'ils diffèrent — donc « révoquer celui
 *     que je vois » ne révoque pas celui qu'on croit.
 */
const CARACTERES_INTERDITS = /[\u0000-\u001f\u007f-\u009f\u200b-\u200d\ufeff\u202a-\u202e\u2066-\u2069]/g

/**
 * Un nom d'appareil utilisable dans une liste, borné et nettoyé.
 *
 * REFUSER N'EST PAS UNE OPTION ICI : un appareil sans nom reste un appareil
 * appairé, et le rendre inappairable pour un champ d'affichage serait disproportionné.
 * On nettoie donc, et on nomme ce qui reste.
 *
 * @param {unknown} brut
 * @returns {string}
 */
export function nomDAppareil(brut) {
  if (typeof brut !== 'string') return NOM_PAR_DEFAUT
  const nettoye = brut.replace(CARACTERES_INTERDITS, ' ').replace(/\s+/g, ' ').trim()
  if (nettoye.length === 0) return NOM_PAR_DEFAUT
  return nettoye.slice(0, NOM_MAX)
}

/**
 * Ce texte a-t-il la FORME d'un code d'appairage ?
 *
 * POURQUOI CETTE FONCTION EXISTE, ALORS QUE `analyser` SAIT DÉJÀ LIRE UNE CHARGE
 * UTILE. L'échange reçoit le code SEUL, dans un en-tête — pas la charge utile
 * entière. La forme est donc vérifiée ici AVANT toute recherche : refuser un texte
 * qui ne peut pas être un code évite de faire travailler la comparaison, et évite
 * surtout de confondre « ce code n'existe pas » avec « ce texte n'est pas un code ».
 *
 * @param {unknown} valeur
 * @returns {boolean}
 */
export function codePlausible(valeur) {
  return typeof valeur === 'string' && FORME_CODE.test(valeur)
}

const secretAcceptable = (genre, secret) =>
  typeof secret === 'string' && secret.length >= SECRETS_MINIMUMS[genre] && FORME_SECRET.test(secret)

/**
 * Pourquoi une charge utile a été refusée.
 *
 * Un refus qui ne dit pas POURQUOI oblige l'utilisateur à deviner entre « le QR
 * est abîmé », « l'adresse est celle de la boucle locale » et « mon application
 * est trop ancienne ». Trois causes, trois remèdes.
 */
export const MOTIFS = {
  FORME: 'forme',
  SCHEMA: 'schema',
  HOTE: 'hote',
  HOTE_LOCAL: 'hote-local',
  GENRE: 'genre',
  VERSION: 'version',
  SECRET: 'secret',
}

const MOTIFS_LISIBLES = {
  [MOTIFS.FORME]: "ce texte n'est pas une charge utile d'appairage",
  [MOTIFS.SCHEMA]: "le schéma n'est pas celui d'un appairage DSH",
  [MOTIFS.HOTE]: "le nom de machine est vide ou mal formé",
  [MOTIFS.HOTE_LOCAL]: "l'adresse est celle de la boucle locale : un autre appareil ne peut pas la joindre",
  [MOTIFS.GENRE]: "ce genre d'appairage n'existe pas",
  [MOTIFS.VERSION]: "cette version d'appairage n'est pas connue de cette moitié",
  [MOTIFS.SECRET]: 'le secret est absent, tronqué ou mal formé',
}

/** Le message lisible d'un motif de refus. Jamais une trace technique. */
export function messageRefus(motif) {
  return MOTIFS_LISIBLES[motif] ?? MOTIFS_LISIBLES[MOTIFS.FORME]
}

/**
 * L'hôte est-il publiables à un AUTRE appareil ?
 *
 * @param {string} hote
 * @returns {boolean}
 */
export function hoteJoignable(hote) {
  if (typeof hote !== 'string' || hote.length === 0) return false
  if (hote.includes(':')) return false // un port, ou une adresse IPv6 : hors contrat
  if (HOTES_LOCAUX.has(hote.toLowerCase())) return false
  return FORME_HOTE.test(hote)
}

/**
 * Construire la charge utile.
 *
 * LE SCHÉMA DE PUBLICATION EST FACULTATIF, ET OMIS QUAND IL VAUT `http` : c'est
 * le cas de très loin le plus courant, et un segment de plus coûterait des octets
 * sur une charge utile qui doit tenir dans un QR de version 6. Un client plus
 * ancien REFUSE une charge utile à cinq segments (« forme inattendue ») — ce qui
 * est le bon comportement : il ne saurait pas viser HTTPS, et lui donner une
 * adresse en clair vers un hôte publié en HTTPS ne le mènerait nulle part.
 *
 * @param {{ hote: string, genre: string, secret: string, schema?: string }} champs
 * @returns {{ ok: true, charge: string } | { ok: false, motif: string, message: string }}
 */
export function construire({ hote, genre, secret, schema }) {
  if (!hoteJoignable(hote)) {
    const motif = HOTES_LOCAUX.has(String(hote).toLowerCase()) ? MOTIFS.HOTE_LOCAL : MOTIFS.HOTE
    return { ok: false, motif, message: messageRefus(motif) }
  }
  const version = VERSIONS[genre]
  if (version === undefined) return { ok: false, motif: MOTIFS.GENRE, message: messageRefus(MOTIFS.GENRE) }
  if (!secretAcceptable(genre, secret)) {
    return { ok: false, motif: MOTIFS.SECRET, message: messageRefus(MOTIFS.SECRET) }
  }
  // Un schéma INCONNU n'est pas deviné : il est ignoré, et la charge utile reste
  // celle du clair. Inventer `https://` sur une valeur douteuse ferait échouer un
  // appairage qui marchait, ce qui serait un remède pire que le mal.
  const transport = SCHEMAS.includes(String(schema).toLowerCase()) ? String(schema).toLowerCase() : 'http'
  const suffixe = transport === 'https' ? '/' + transport : ''
  return { ok: true, charge: SCHEMA + '://' + hote + '/' + genre + '/' + version + '/' + secret + suffixe }
}

/**
 * Analyser une charge utile — le chemin de l'appareil qui scanne ou qui colle.
 *
 * REFUSER EST UN RÉSULTAT, PAS UNE EXCEPTION : cette fonction ne lève jamais.
 * Elle est appelée dans une boucle de scan et dans un champ de saisie, où lever
 * pour un texte encore incomplet serait un défaut d'ergonomie, pas une sécurité.
 *
 * @param {string} texte
 * @returns {{ ok: true, hote: string, genre: string, version: string, secret: string, schema: string, adresse: string }
 *          | { ok: false, motif: string, message: string }}
 */
export function analyser(texte) {
  if (typeof texte !== 'string') return refus(MOTIFS.FORME)
  const valeur = texte.trim()
  if (valeur.length === 0 || valeur.length > 512) return refus(MOTIFS.FORME)

  const prefixe = SCHEMA + '://'
  if (!valeur.startsWith(prefixe)) {
    // Deux causes distinctes, et l'utilisateur ne les corrige pas pareil :
    // un autre schéma, ou un texte qui n'est pas une adresse du tout.
    const avant = valeur.slice(0, valeur.indexOf('://') + 3)
    return refus(valeur.includes('://') ? MOTIFS.SCHEMA : MOTIFS.FORME, avant)
  }

  const reste = valeur.slice(prefixe.length)
  const morceaux = reste.split('/')
  // QUATRE SEGMENTS — hôte, genre, version, secret — OU CINQ avec le schéma de
  // publication en dernier. Aucun autre compte : un secret ne contient pas de
  // `/`, donc un segment de plus est une charge utile mal formée, jamais un cas
  // particulier à deviner.
  if (morceaux.length !== 4 && morceaux.length !== 5) return refus(MOTIFS.FORME)
  const [hote, genre, version, secret] = morceaux
  if (hote.includes('?') || hote.includes('#')) return refus(MOTIFS.FORME)

  if (!hoteJoignable(hote)) {
    return refus(HOTES_LOCAUX.has(hote.toLowerCase()) ? MOTIFS.HOTE_LOCAL : MOTIFS.HOTE)
  }
  if (VERSIONS[genre] === undefined) return refus(MOTIFS.GENRE, genre)
  if (VERSIONS[genre] !== version) return refus(MOTIFS.VERSION, genre + '/' + version)
  if (!secretAcceptable(genre, secret)) return refus(MOTIFS.SECRET)
  // Le schéma annoncé est vérifié CONTRE LA LISTE BLANCHE, et le détail du refus
  // le nomme : « forme inattendue » sans plus ne dirait pas quel segment corriger.
  const schema = morceaux.length === 5 ? morceaux[4].toLowerCase() : 'http'
  if (!SCHEMAS.includes(schema)) return refus(MOTIFS.FORME, morceaux[4])

  return {
    ok: true,
    hote,
    genre,
    version,
    secret,
    schema,
    // L'adresse que l'appareil doit viser. Sans cinquième segment, le port
    // implicite est 80 — la convention que `tailscale serve` publie. Le client
    // Swift ne fait pas confiance à ce segment pour autant : il le confronte à ce
    // que SON paquet autorise (`AdresseMachine`), donc un paquet qui refuse le
    // clair ne suit jamais un `http` annoncé.
    adresse: schema + '://' + hote,
  }
}

function refus(motif, detail) {
  const message = messageRefus(motif)
  return detail === undefined || detail === ''
    ? { ok: false, motif, message }
    : { ok: false, motif, message, detail: String(detail) }
}
