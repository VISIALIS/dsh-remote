/**
 * LE PROTOCOLE WEBSOCKET, ÉCRIT À LA MAIN (RFC 6455).
 *
 * POURQUOI CE FICHIER, ET POURQUOI PAS UNE DÉPENDANCE. La RÈGLE #0 fait de chaque
 * dépendance une surface d'attaque supplémentaire dans un processus sans bac à
 * sable : une centaine de lignes suffisent ici pour un flux d'événements serveur
 * vers client, et seuls le texte, le ping, le pong et la fermeture sont
 * implémentés.
 *
 * POURQUOI IL A DES TESTS. C'est du code BINAIRE : une longueur mal encodée, un
 * masque mal appliqué, et le flux se tait sans rien dire. Rien ne l'éprouvait —
 * ces fonctions vivaient au milieu de 1 311 lignes de routes.
 */

import { createHash } from 'node:crypto'

// ─────────────────────────────────────────────────────────────────────────────
// WebSocket minimal (RFC 6455)
//
// Écrire une centaine de lignes ici plutôt qu'ajouter une dépendance : la
// RÈGLE #0 fait de chaque dépendance une surface d'attaque supplémentaire dans
// un processus sans bac à sable. Seuls le texte, le ping, le pong et la
// fermeture sont implémentés, ce qui suffit à un flux d'événements serveur vers
// client.
// ─────────────────────────────────────────────────────────────────────────────

// PLAFOND D'UNE TRAME ANNONCÉE PAR LE CLIENT. Le champ de longueur sur huit
// octets peut annoncer des gigaoctets : on refuse AVANT d'allouer, sinon un
// client malveillant fait enfler la mémoire du harness — qui n'a pas de bac à
// sable. (Cette borne était empruntée à la décompression du journal, restée dans
// `host.js` : le test de trame trop longue l'a signalé.)
const PLAFOND_TRAME = 64 * 1024 * 1024

export const CLE_MAGIQUE_WS = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'

export function trameTexte(texte) {
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

export function trameFermeture(code = 1000) {
  const charge = Buffer.alloc(2)
  charge.writeUInt16BE(code, 0)
  return Buffer.concat([Buffer.from([0x88, 0x02]), charge])
}

export function tramePong(charge) {
  if (charge.length >= 126) return Buffer.from([0x8a, 0x00])
  return Buffer.concat([Buffer.from([0x8a, charge.length]), charge])
}

/**
 * Décode les trames reçues d'un client. Le client DOIT masquer ses trames.
 * @returns {{restant: Buffer, trames: Array<{fin: boolean, opcode: number, charge: Buffer}>}}
 */
export function lireTrames(restant) {
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
      if (grand > BigInt(PLAFOND_TRAME)) return { restant: Buffer.alloc(0), trames, trop: true }
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


/**
 * LE RÉASSEMBLAGE DES TRAMES FRAGMENTÉES — RFC 6455, § 5.4.
 *
 * POURQUOI CE FICHIER EN A BESOIN, ALORS QUE LE CLIENT ACTUEL N'EN ENVOIE PAS.
 * Un message peut arriver en plusieurs trames : la première porte le texte (ou le
 * binaire) sans le bit FIN, les suivantes ont l'opcode `0x0` (continuation) et
 * reconstituent la charge. Notre client envoie un `demarrer` de soixante octets
 * d'un seul tenant — mais la RFC n'oblige personne à faire comme lui, et un proxy
 * intermédiaire peut fragmenter. Jusqu'ici, `host.js` ignorait tout ce qui n'était
 * pas `0x1` : un client qui fragmentait n'obtenait AUCUNE réponse, sans erreur —
 * le flux se taisait, ce qui est la pire des pannes.
 *
 * LES RÈGLES QUI COMPTENT, ET CELLES QU'ON REFUSE :
 *   - une continuation SANS début est une faute de protocole (fermeture `1002`) ;
 *   - un nouveau message de données PENDANT une fragmentation aussi ;
 *   - les trames de CONTRÔLE (ping, pong, fermeture) peuvent s'intercaler : elles
 *     ne participent pas au message et sont rendues à part, dans l'ordre ;
 *   - l'accumulation est BORNÉE, comme une trame seule : sans cela, un client
 *     pourrait envoyer des fragments pour toujours et faire enfler la mémoire du
 *     harness, qui n'a pas de bac à sable (`1009`).
 *
 * @param {number} [plafond] taille maximale d'un message réassemblé, en octets.
 */
export function creerAssembleur(plafond = PLAFOND_TRAME) {
  /** Les morceaux du message EN COURS, et son opcode d'origine. */
  let morceaux = []
  let opcode = null
  let octets = 0

  return {
    /**
     * @param {{fin: boolean, opcode: number, charge: Buffer}} trame
     * @returns {{messages: Array<{opcode: number, charge: Buffer}>, controle: Array<{opcode: number, charge: Buffer}>, erreur: number | null}}
     */
    ajouter(trame) {
      const messages = []
      const controle = []
      // Les trois opcodes de contrôle : ils traversent la fragmentation sans y
      // participer, et l'ordre doit être conservé (un ping reçoit son pong).
      if (trame.opcode === 0x8 || trame.opcode === 0x9 || trame.opcode === 0xa) {
        controle.push({ opcode: trame.opcode, charge: trame.charge })
        return { messages, controle, erreur: null }
      }
      if (trame.opcode === 0x0) {
        if (opcode === null) return { messages, controle, erreur: 1002 }
        octets += trame.charge.length
        if (octets > plafond) return { messages, controle, erreur: 1009 }
        morceaux.push(trame.charge)
        if (!trame.fin) return { messages, controle, erreur: null }
        messages.push({ opcode, charge: Buffer.concat(morceaux, octets) })
        morceaux = []
        opcode = null
        octets = 0
        return { messages, controle, erreur: null }
      }
      if (trame.opcode !== 0x1 && trame.opcode !== 0x2) {
        // Un opcode de données inconnu (réservé) : on refuse au lieu d'ignorer,
        // sinon la trame disparaît en silence.
        return { messages, controle, erreur: 1002 }
      }
      if (opcode !== null) return { messages, controle, erreur: 1002 }
      if (trame.fin) {
        messages.push({ opcode: trame.opcode, charge: trame.charge })
        return { messages, controle, erreur: null }
      }
      octets = trame.charge.length
      if (octets > plafond) return { messages, controle, erreur: 1009 }
      opcode = trame.opcode
      morceaux = [trame.charge]
      return { messages, controle, erreur: null }
    },
  }
}

/**
 * L'ACCEPTATION D'UN HANDSHAKE — RFC 6455, §4.2.2.
 *
 * `Sec-WebSocket-Accept` est le SHA-1, en base 64, de la clé du client suivie de
 * la clé magique du protocole. Une valeur fausse fait échouer le client sans
 * explication : il ferme, et le serveur ne voit rien.
 *
 * @param {string} cle la valeur de `Sec-WebSocket-Key`
 * @returns {string}
 */
export function accepterWebSocket(cle) {
  return createHash('sha1').update(cle + CLE_MAGIQUE_WS).digest('base64')
}
