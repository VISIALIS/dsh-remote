/**
 * LE PROTOCOLE WEBSOCKET, ÉPROUVÉ OCTET PAR OCTET.
 *
 * POURQUOI CES TESTS. C'est du code BINAIRE écrit à la main : une longueur mal
 * encodée, un masque mal appliqué, et le flux se tait sans rien dire — le client
 * attend, le serveur croit avoir envoyé. Rien ne l'éprouvait jusqu'ici.
 *
 * Les charges utiles des clients sont MASQUÉES (RFC 6455 §5.3 : un client DOIT
 * masquer) ; celles du serveur ne le sont jamais. Un décodeur qui oublie le
 * masque rend du charabia, et un encodeur qui le pose fait fermer la connexion.
 */

import assert from 'node:assert/strict'
import { test } from 'node:test'

import { accepterWebSocket, lireTrames, trameFermeture, tramePong, trameTexte } from '../dynamic/trames.js'

/** Une trame de CLIENT, masquée, comme le navigateur ou l'application l'envoie. */
function trameClient(opcode, charge) {
  const donnees = Buffer.from(charge)
  const cle = Buffer.from([0x01, 0x02, 0x03, 0x04])
  const masque = Buffer.from(donnees.map((octet, index) => octet ^ cle[index & 3]))
  const entete = Buffer.from([0x80 | opcode, 0x80 | donnees.length])
  return Buffer.concat([entete, cle, masque])
}

test('une trame de texte courte est encodée en deux octets, sans masque', () => {
  const trame = trameTexte('bonjour')
  // FIN + opcode texte, puis la longueur : le serveur ne masque JAMAIS.
  assert.equal(trame[0], 0x81)
  assert.equal(trame[1], 7)
  assert.equal(trame.subarray(2).toString('utf8'), 'bonjour')
})

test('au-delà de 125 octets, la longueur passe sur deux octets, puis huit', () => {
  const moyen = trameTexte('a'.repeat(200))
  assert.equal(moyen[1], 126)
  assert.equal(moyen.readUInt16BE(2), 200)
  assert.equal(moyen.length, 4 + 200)

  const grand = trameTexte('a'.repeat(70000))
  assert.equal(grand[1], 127)
  assert.equal(Number(grand.readBigUInt64BE(2)), 70000)
  assert.equal(grand.length, 10 + 70000)
})

test('la fermeture porte son code, et le pong sa charge', () => {
  const fermeture = trameFermeture(1000)
  assert.equal(fermeture[0], 0x88)
  assert.equal(fermeture.readUInt16BE(2), 1000)

  const pong = tramePong(Buffer.from('ok'))
  assert.equal(pong[0], 0x8a)
  assert.equal(pong.subarray(2).toString('utf8'), 'ok')

  // Une charge de pong trop longue n'est pas permise par la RFC : on rend un
  // pong VIDE plutôt qu'une trame invalide que le client refuserait.
  assert.deepEqual(tramePong(Buffer.alloc(200)), Buffer.from([0x8a, 0x00]))
})

test('une trame de client est DÉMASQUÉE, et plusieurs trames se suivent', () => {
  const tampon = Buffer.concat([trameClient(0x1, '{"type":"demarrer"}'), trameClient(0x9, 'ping')])

  const { trames, restant } = lireTrames(tampon)

  assert.equal(trames.length, 2)
  assert.equal(trames[0].opcode, 0x1)
  assert.equal(trames[0].charge.toString('utf8'), '{"type":"demarrer"}')
  assert.equal(trames[1].opcode, 0x9)
  assert.equal(trames[1].charge.toString('utf8'), 'ping')
  assert.equal(restant.length, 0)
})

test('une trame INCOMPLÈTE est conservée pour le morceau suivant', () => {
  // Le réseau découpe où il veut : un message peut arriver en deux morceaux. Le
  // décodeur doit rendre ce qu'il n'a pas pu lire, sans le perdre.
  const complete = trameClient(0x1, 'message entier')
  const coupee = complete.subarray(0, complete.length - 4)

  const premier = lireTrames(coupee)
  assert.equal(premier.trames.length, 0)
  assert.equal(premier.restant.length, coupee.length)

  // Le morceau suivant complète la trame.
  const second = lireTrames(Buffer.concat([premier.restant, complete.subarray(complete.length - 4)]))
  assert.equal(second.trames.length, 1)
  assert.equal(second.trames[0].charge.toString('utf8'), 'message entier')
})

test('une longueur démesurée est REFUSÉE au lieu d’allouer', () => {
  // Le champ de longueur sur huit octets peut annoncer des gigaoctets : on refuse
  // AVANT d'allouer, sinon un client malveillant fait enfler la mémoire du
  // harness — qui n'a pas de bac à sable.
  const entete = Buffer.alloc(10)
  entete[0] = 0x81
  entete[1] = 127
  entete.writeBigUInt64BE(BigInt(8 * 1024 * 1024 * 1024), 2)

  const lecture = lireTrames(entete)
  assert.equal(lecture.trop, true)
  assert.equal(lecture.trames.length, 0)
})

test('l’acceptation du handshake est celle que la RFC impose', () => {
  // Valeur de l'exemple de la RFC 6455 §1.3 : un client ne l'accepte pas si elle
  // diffère, et il ferme sans rien dire.
  assert.equal(
    accepterWebSocket('dGhlIHNhbXBsZSBub25jZQ=='),
    's3pPLMBiTxaQ9kYGzzhZRbK+xOo=',
  )
})
