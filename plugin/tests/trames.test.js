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

import {
  accepterWebSocket,
  creerAssembleur,
  lireTrames,
  trameFermeture,
  tramePong,
  trameTexte,
} from '../dynamic/trames.js'

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

// ── Le réassemblage des trames fragmentées (RFC 6455, § 5.4) ──────────────────
//
// POURQUOI CES TESTS. `host.js` ignorait tout ce qui n'était pas `0x1` : un client
// qui fragmentait un message n'obtenait AUCUNE réponse, sans erreur — le flux se
// taisait. Ces quatre règles sont celles qui décident entre servir, refuser, et
// laisser la mémoire enfler.

/** Une trame de données, avec le bit FIN qu'on veut, et sa charge. */
const donnees = (opcode, charge, fin = true) => ({
  fin,
  opcode,
  charge: Buffer.from(charge),
})

test('un message fragmenté est réassemblé, et rendu UNE fois', () => {
  const assembleur = creerAssembleur()
  const debut = assembleur.ajouter(donnees(0x1, 'demar', false))
  assert.deepEqual(debut.messages, [], 'un début sans FIN ne rend rien')
  assert.equal(debut.erreur, null)
  const milieu = assembleur.ajouter(donnees(0x0, 'er', false))
  assert.deepEqual(milieu.messages, [])
  const fin = assembleur.ajouter(donnees(0x0, '{"a":1}'))
  assert.equal(fin.erreur, null)
  assert.equal(fin.messages.length, 1)
  assert.equal(fin.messages[0].opcode, 0x1)
  assert.equal(fin.messages[0].charge.toString('utf8'), 'demarer{"a":1}')
})

test('une trame de contrôle s’intercale SANS participer au message', () => {
  // Un proxy peut glisser un ping au milieu d'une fragmentation : le message doit
  // survivre, et le ping doit être rendu à part — sinon on perdrait le pong.
  const assembleur = creerAssembleur()
  assembleur.ajouter(donnees(0x1, 'debut', false))
  const ping = assembleur.ajouter(donnees(0x9, 'x'))
  assert.equal(ping.controle.length, 1)
  assert.equal(ping.controle[0].opcode, 0x9)
  assert.deepEqual(ping.messages, [])
  const fin = assembleur.ajouter(donnees(0x0, 'fin'))
  assert.equal(fin.messages[0].charge.toString('utf8'), 'debutfin')
})

test('une continuation sans début, ou un message pendant un autre, est une FAUTE', () => {
  // 1002 : « protocol error ». Refuser est le seul choix honnête — ignorer
  // laisserait le client attendre une réponse qui ne viendrait jamais.
  const sansDebut = creerAssembleur()
  assert.equal(sansDebut.ajouter(donnees(0x0, 'orphelin')).erreur, 1002)

  const pendant = creerAssembleur()
  pendant.ajouter(donnees(0x1, 'debut', false))
  assert.equal(pendant.ajouter(donnees(0x1, 'un autre')).erreur, 1002)

  const inconnu = creerAssembleur()
  assert.equal(inconnu.ajouter(donnees(0x3, 'réservé')).erreur, 1002)
})

test('un message fragmenté qui dépasse le plafond est REFUSÉ, pas accumulé', () => {
  // POURQUOI CE PLAFOND EXISTE : sans lui, un client enverrait des fragments pour
  // toujours et ferait enfler la mémoire du harness, qui n'a pas de bac à sable.
  const assembleur = creerAssembleur(16)
  assert.equal(assembleur.ajouter(donnees(0x1, 'x'.repeat(16), false)).erreur, null)
  assert.equal(assembleur.ajouter(donnees(0x0, 'y')).erreur, 1009)

  const enorme = creerAssembleur(4)
  assert.equal(enorme.ajouter(donnees(0x1, 'xxxxx', false)).erreur, 1009)
})

test('un message NON fragmenté traverse l’assembleur tel quel', () => {
  const assembleur = creerAssembleur()
  const rendu = assembleur.ajouter(donnees(0x1, '{"type":"demarrer"}'))
  assert.equal(rendu.erreur, null)
  assert.equal(rendu.messages.length, 1)
  assert.equal(rendu.messages[0].charge.toString('utf8'), '{"type":"demarrer"}')
})
