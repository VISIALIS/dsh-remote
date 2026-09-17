// UN FAUX HÔTE DSH REMOTE — HTTP *ET* WebSocket — POUR ÉPROUVER LA RECONNEXION
// DU MODÈLE. Essai seulement.
//
// POURQUOI UN SECOND SERVEUR D'ESSAI, ALORS QU'IL Y EN A DÉJÀ UN. Le premier
// (`serveur-flux-essai.mjs`) ne parle QUE WebSocket : il suffit à éprouver le
// transport (`FluxSession`), mais pas la BOUCLE DE RECONNEXION, qui vit dans le
// modèle — et le modèle refuse d'ouvrir un flux s'il n'a pas d'abord joint l'hôte
// par HTTP (`guard client != nil`). Sans les routes HTTP, le test mesurerait
// « le modèle ne démarre rien », pas « le modèle se reconnecte ».
//
// CE QU'IL FAIT :
//   1. répond en JSON à `GET /dsh-remote/v1/sante` et `POST /dsh-remote/v1/sessions`
//      — juste assez pour que `joindre` réussisse ;
//   2. accepte les connexions WebSocket sur `/dsh-remote/v1/flux`, envoie `base`
//      puis un `evenement`, et COUPE brutalement les `nb-coupures` premières ;
//   3. note dans un fichier chaque connexion et le `depuisSeq` qu'elle a porté :
//      c'est LA mesure — la reprise doit avancer, pas repartir de zéro.
//
// Aucune dépendance : HTTP et RFC 6455 sont écrits à la main. Le dépôt a ce
// savoir-faire côté plugin, et le refaire ici est délibéré — un test qui
// partagerait le code de ce qu'il éprouve ne prouverait rien.
//
// Usage : node serveur-modele-essai.mjs <port> <fichier-journal> [nb-coupures]

import { createHash } from 'node:crypto'
import { appendFileSync, writeFileSync } from 'node:fs'
import { createServer } from 'node:net'

const port = Number(process.argv[2])
const journal = process.argv[3]
const coupures = Number(process.argv[4] ?? '1')
writeFileSync(journal, '')

const noter = (texte) => appendFileSync(journal, texte + '\n')

const IDENTIFIANT = 'session-essai'

/** Un enregistrement de journal, tel que le plugin les publie. */
const enregistrement = (seq) => ({ type: 'assistant/message', seq, time: 1_700_000_000_000 + seq })

const CORPS_SANTE = JSON.stringify({
  protocole: 1,
  nom: 'dsh-remote',
  hote: 'hote-essai',
  capacites: {
    sessions: true, journal: true, flux: true, ecriture: false, approbations: false,
    decouverte: true, espaces: false,
  },
})

const CORPS_SESSIONS = JSON.stringify({
  protocole: 1,
  racine: '/tmp/sessions-essai',
  total: 1,
  sessions: [
    {
      projet: '--tmp-essai--',
      cwdIndicatif: '/tmp/essai',
      octets: 1_234,
      modifieLe: 1_700_000_000_002,
      vivante: true,
      statut: 'en_cours',
      attendReponse: false,
      id: IDENTIFIANT,
      titre: 'Essai de reconnexion',
      cwd: '/tmp/essai',
      dernierSeq: 2,
      nbEnregistrements: 2,
    },
  ],
})

/** Le `Sec-WebSocket-Accept` de la RFC 6455, § 4.2.2. */
const acceptation = (cle) => createHash('sha1').update(cle + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64')

/** Une trame texte non masquée. Au-delà de 125 octets, la longueur passe sur 2 octets. */
function trame(texte) {
  const charge = Buffer.from(texte, 'utf8')
  if (charge.length < 126) return Buffer.concat([Buffer.from([0x81, charge.length]), charge])
  const longueur = Buffer.alloc(2)
  longueur.writeUInt16BE(charge.length)
  return Buffer.concat([Buffer.from([0x81, 126]), longueur, charge])
}

const reponseHttp = (socket, code, corps) => {
  const texte = Buffer.from(corps, 'utf8')
  socket.write(
    'HTTP/1.1 ' + code + '\r\nContent-Type: application/json\r\nContent-Length: ' + texte.length + '\r\n\r\n',
  )
  socket.end(texte)
}

let connexions = 0

const serveur = createServer((socket) => {
  let tampon = Buffer.alloc(0)
  let enteteLue = false
  let rang = 0
  let aRepondu = false

  socket.on('data', (morceau) => {
    tampon = Buffer.concat([tampon, morceau])

    if (!enteteLue) {
      const fin = tampon.indexOf('\r\n\r\n')
      if (fin === -1) return
      const entete = tampon.subarray(0, fin).toString('latin1')
      const chemin = (entete.split('\r\n')[0] ?? '').split(' ')[1] ?? ''
      const estUpgrade = /upgrade:\s*websocket/i.test(entete)

      if (!estUpgrade) {
        // ── HTTP : juste ce qu'il faut pour que `joindre` réussisse ──────────
        const corps = chemin.includes('/v1/sante')
          ? CORPS_SANTE
          : chemin.includes('/v1/sessions')
            ? CORPS_SESSIONS
            : null
        noter('http ' + chemin + ' -> ' + (corps === null ? 404 : 200))
        if (corps === null) return reponseHttp(socket, '404 Not Found', '{"erreur":"route inconnue"}')
        return reponseHttp(socket, '200 OK', corps)
      }

      const cle = /sec-websocket-key:\s*(\S+)/i.exec(entete)?.[1]
      if (cle === undefined) {
        socket.end('HTTP/1.1 400 Bad Request\r\n\r\n')
        return
      }
      rang = ++connexions
      socket.write(
        'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' +
          acceptation(cle) +
          '\r\n\r\n',
      )
      enteteLue = true
      tampon = tampon.subarray(fin + 4)
      noter('connexion=' + rang + ' upgrade=ok')
    }

    // Le client n'envoie qu'un message : « demarrer ». Trame cliente, donc
    // MASQUÉE (la RFC l'impose), et de longueur variable.
    if (aRepondu || !enteteLue || tampon.length < 6) return
    const masque = (tampon.readUInt8(1) & 0x80) !== 0
    let longueur = tampon.readUInt8(1) & 0x7f
    let debut = 2
    if (longueur === 126) {
      if (tampon.length < 8) return
      longueur = tampon.readUInt16BE(2)
      debut = 4
    }
    if (!masque || tampon.length < debut + 4 + longueur) return
    const cle = tampon.subarray(debut, debut + 4)
    const charge = Buffer.from(tampon.subarray(debut + 4, debut + 4 + longueur))
    for (let i = 0; i < charge.length; i++) charge[i] ^= cle[i % 4]
    aRepondu = true

    let demande = {}
    try {
      demande = JSON.parse(charge.toString('utf8'))
    } catch {
      noter('connexion=' + rang + ' demarrer=illisible')
    }
    noter('connexion=' + rang + ' depuisSeq=' + (demande.depuisSeq === undefined ? 'absent' : demande.depuisSeq))

    // Ce que l'hôte enverrait : la base (avec les derniers enregistrements), puis
    // un évènement. Le seq 1 est TOUJOURS renvoyé, même en reprise — c'est ce qui
    // permet de vérifier que le client ne l'affiche pas deux fois.
    const depuis = typeof demande.depuisSeq === 'number' ? demande.depuisSeq : 0
    const aEnvoyer = [1, 2].filter((seq) => seq > depuis)
    socket.write(
      trame(
        JSON.stringify({
          type: 'base',
          protocole: 1,
          session: { id: IDENTIFIANT, titre: 'Essai de reconnexion', cwd: '/tmp/essai', dernierSeq: 2 },
          enregistrements: aEnvoyer.map(enregistrement),
          dernierSeq: 2,
        }),
      ),
    )
    // L'évènement qui suit la base : c'est lui qui prouve au client que le flux
    // vit, donc qui remet le compteur de reconnexion à zéro.
    socket.write(trame(JSON.stringify({ type: 'evenement', enregistrement: enregistrement(3) })))
    noter('connexion=' + rang + ' envoi=' + JSON.stringify(aEnvoyer.concat([3])))

    if (rang <= coupures) {
      // LA COUPURE, BRUTALE : pas de trame de fermeture, pas de `FIN`. C'est ce
      // que fait un Wi-Fi qui s'endort.
      noter('connexion=' + rang + ' coupure=brutale')
      setTimeout(() => socket.destroy(), 60)
    } else {
      noter('connexion=' + rang + ' maintenue=oui')
    }
  })

  socket.on('error', () => {})
})

serveur.listen(port, '127.0.0.1', () => noter('ecoute=' + port))
