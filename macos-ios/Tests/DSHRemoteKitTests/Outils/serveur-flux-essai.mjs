// UN SERVEUR WEBSOCKET MINIMAL, POUR ÉPROUVER LA REPRISE DU FLUX. Essai seulement.
//
// POURQUOI CE FICHIER EXISTE, ET POURQUOI IL N'EST PAS DANS `dynamic/`. La reprise
// du flux est la propriété la plus difficile à vérifier d'un client temps réel :
// il faut une socket qui TOMBE, un client qui se reconnecte, et la preuve que le
// second `demarrer` porte bien le `seq` déjà connu. Un test de politique ne voit
// rien de tout cela, et un simulacre de tâche WebSocket ne dirait que ce qu'on a
// décidé de lui faire dire.
//
// Il vit donc DU COTÉ SWIFT (`Tests/DSHRemoteKitTests/Outils/`), hors de la moitié
// hôte du plugin : la cible de test du paquet ne peut pas dépendre de `dynamic/`.
//
// CE QU'IL FAIT, ET RIEN DE PLUS :
//   1. accepte DEUX connexions, et envoie à chacune `base` (avec `dernierSeq`)
//      puis un `evenement` — c'est ce qui fait démarrer la reprise au client ;
//   2. FERME la première socket brutalement, après ces messages : c'est la coupure
//      de réseau qu'on veut rejouer, pas une fermeture propre que le client
//      pourrait interpréter comme un « au revoir » ;
//   3. note dans un fichier ce que le SECOND `demarrer` a porté (`depuisSeq`) —
//      c'est LA mesure du test ;
//   4. laisse la seconde socket ouverte, pour que le client reste en direct.
//
// Aucune dépendance : le protocole est écrit à la main (RFC 6455, texte, non
// masqué côté serveur). Le dépôt a déjà ce savoir-faire côté plugin
// (`dynamic/trames.js`), et le refaire ici est délibéré — un test qui partagerait
// le code de ce qu'il éprouve ne prouverait rien.
//
// Usage : node serveur-flux-essai.mjs <port> <fichier-journal> [nb-coupures] [sourd]
//
// LE CINQUIEME ARGUMENT, `sourd`, SERT AU BATTEMENT DE COEUR : le serveur repond
// alors au `demarrer` mais JAMAIS aux pings. C'est la seule facon d'eprouver ce
// que le battement existe pour attraper — une socket qui reste ouverte sans que
// rien ne revienne — sans dependre d'un vrai reseau qu'on coupe.

import { createHash } from 'node:crypto'
import { appendFileSync, writeFileSync } from 'node:fs'
import { createServer } from 'node:net'

const port = Number(process.argv[2])
const journal = process.argv[3]
// COMBIEN DE CONNEXIONS COUPER AVANT D'EN LAISSER UNE VIVRE.
//
// Pourquoi un parametre, et pas « on coupe toujours la premiere » : deux
// proprietes differentes se mesurent. Le TRANSPORT (`FluxSession`) se prouve avec
// une seule coupure ; la BOUCLE DE RECONNEXION du modele se prouve en en voyant
// plusieurs — c'est ce qui montre qu'on REESSAIE, et pas seulement qu'on sait
// reprendre.
const coupures = Number(process.argv[4] ?? '1')
const sourd = process.argv[5] === 'sourd'
writeFileSync(journal, '')

const noter = (texte) => appendFileSync(journal, texte + '\n')

/** Le `Sec-WebSocket-Accept` de la RFC 6455, § 4.2.2. */
const acceptation = (cle) => createHash('sha1').update(cle + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64')

/** Une trame texte non masquée. Au-delà de 125 octets, la longueur passe sur 2 octets. */
function trame(texte) {
  const charge = Buffer.from(texte, 'utf8')
  const entete = charge.length < 126 ? Buffer.from([0x81, charge.length]) : Buffer.concat([Buffer.from([0x81, 126]), (() => { const t = Buffer.alloc(2); t.writeUInt16BE(charge.length); return t })()])
  return Buffer.concat([entete, charge])
}

/** Un pong non masque (0x8A), qui renvoie la charge du ping. */
function pong(charge) {
  return Buffer.concat([Buffer.from([0x8a, charge.length]), charge])
}

/**
 * La premiere trame cliente COMPLETE du tampon, ou `null` s'il en manque encore.
 *
 * Elle est MASQUEE (la RFC l'impose au client) : sans demasquage, le `demarrer`
 * se lirait en charabia — et le test croirait que le client n'a rien demande.
 */
function trameCliente(tampon) {
  if (tampon.length < 2) return null
  const opcode = tampon[0] & 0x0f
  let longueur = tampon[1] & 0x7f
  let debut = 2
  if (longueur === 126) {
    if (tampon.length < 4) return null
    longueur = tampon.readUInt16BE(2)
    debut = 4
  } else if (longueur === 127) {
    if (tampon.length < 10) return null
    longueur = Number(tampon.readBigUInt64BE(2))
    debut = 10
  }
  if ((tampon[1] & 0x80) === 0) return null
  if (tampon.length < debut + 4 + longueur) return null
  const cle = tampon.subarray(debut, debut + 4)
  const charge = Buffer.from(tampon.subarray(debut + 4, debut + 4 + longueur))
  for (let i = 0; i < charge.length; i++) charge[i] ^= cle[i % 4]
  return { opcode, charge, reste: tampon.subarray(debut + 4 + longueur) }
}

const enregistrement = (seq) => JSON.stringify({ type: 'assistant/message', seq, time: 1_700_000_000_000 + seq })

let connexions = 0

const serveur = createServer((socket) => {
  let tampon = Buffer.alloc(0)
  let enteteLue = false
  // Chaque socket a SON numero de connexion : deux sockets peuvent arriver dans
  // le meme tour, et un compteur global lu plus tard attribuerait le mauvais rang
  // au mauvais journal.
  const rang = ++connexions
  let aRepondu = false
  let pings = 0

  socket.on('data', (morceau) => {
    tampon = Buffer.concat([tampon, morceau])

    if (!enteteLue) {
      const fin = tampon.indexOf('\r\n\r\n')
      if (fin === -1) return
      const entete = tampon.subarray(0, fin).toString('latin1')
      const cle = /sec-websocket-key:\s*(\S+)/i.exec(entete)?.[1]
      if (cle === undefined) {
        socket.end('HTTP/1.1 400 Bad Request\r\n\r\n')
        return
      }
      socket.write(
        'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' +
          acceptation(cle) +
          '\r\n\r\n',
      )
      enteteLue = true
      tampon = tampon.subarray(fin + 4)
      noter('connexion=' + rang + ' upgrade=ok')
    }

    // LE CLIENT ENVOIE DEUX SORTES DE TRAMES : le « demarrer » (une fois), puis
    // les pings de son battement de coeur. On les traite EN BOUCLE, parce qu'une
    // seule lecture de socket peut en porter plusieurs — et parce qu'un serveur
    // qui ne lirait que la premiere ne verrait jamais le battement, donc ne
    // pourrait pas l'eprouver.
    for (;;) {
      const lue = trameCliente(tampon)
      if (lue === null) return
      tampon = lue.reste

      if (lue.opcode === 0x9) {
        pings += 1
        noter('connexion=' + rang + ' ping=' + pings)
        // `sourd` : on ne repond PAS. C'est la panne qu'on veut rejouer — une
        // socket ouverte sur laquelle plus rien ne revient.
        if (!sourd) socket.write(pong(lue.charge))
        continue
      }
      if (lue.opcode !== 0x1 || aRepondu) continue
      aRepondu = true

      let demande = {}
      try {
        demande = JSON.parse(lue.charge.toString('utf8'))
      } catch {
        noter('connexion=' + rang + ' demarrer=illisible')
      }
      noter('connexion=' + rang + ' depuisSeq=' + (demande.depuisSeq === undefined ? 'absent' : demande.depuisSeq))

      // La base : le resume de la session, et le dernier enregistrement connu.
      socket.write(
        trame(
          JSON.stringify({
            type: 'base',
            protocole: 1,
            session: { id: 'session-essai', titre: 'Essai de reprise', dernierSeq: 1 },
            enregistrements: [JSON.parse(enregistrement(1))],
            dernierSeq: 1,
          }),
        ),
      )
      // Puis un evenement : c'est LUI qui prouve au client que le flux vit, donc
      // celui qui remet le compteur de reconnexion a zero.
      socket.write(trame(JSON.stringify({ type: 'evenement', enregistrement: JSON.parse(enregistrement(2)) })))
      socket.write(trame(JSON.stringify({ type: 'delta', dernierSeq: 2 })))
      // UN STATUT, COMME L'HOTE EN POUSSE : ce n'est pas un enregistrement du
      // journal, donc il ne porte aucun `seq` — et le client ne doit PAS le
      // compter comme un evenement ni faire avancer son curseur de reprise.
      socket.write(trame(JSON.stringify({ type: 'statut', statut: 'en_cours' })))

      // LES PREMIERES CONNEXIONS SONT COUPÉES, LA SUIVANTE VIT.
      if (rang <= coupures) {
        // LA COUPURE, BRUTALE : pas de trame de fermeture, pas de `FIN`. C'est ce
        // que fait un Wi-Fi qui s'endort, et c'est ce que le client doit savoir
        // rattraper.
        noter('connexion=' + rang + ' coupure=brutale')
        setTimeout(() => socket.destroy(), 60)
        return
      }
      noter('connexion=' + rang + ' maintenue=oui')
    }
  })

  socket.on('error', () => {})
})

serveur.listen(port, '127.0.0.1', () => noter('ecoute=' + port))
