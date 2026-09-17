/**
 * LA PLOMBERIE HTTP ET LE CACHE DES FAITS, ÉPROUVÉS SANS HARNESS.
 *
 * POURQUOI CES TESTS. Les deux modules sont sortis de `host.js`, où ils étaient
 * noyés dans 2 368 lignes : la plomberie de réponse ne décide rien mais porte des
 * règles (corps borné, `content-length` toujours posé, corps illisible qui rend
 * `null` et non `{}`), et le cache porte une POLITIQUE (validité par les marqueurs
 * du fichier, péremption, éviction). Une politique qu'on ne peut éprouver qu'en
 * montant un harness entier n'est pas éprouvée.
 *
 * Les faux `req`/`res` sont ceux de `hote.test.js`, réduits à ce que ces fonctions
 * touchent : c'est le même contrat, sans le plugin autour.
 */

import assert from 'node:assert/strict'
import { test } from 'node:test'

import {
  creerCacheDeFaits,
  ENTREES_MAX,
  INTERVALLE_BALAYAGE_MS,
  PEREMPTION_MS,
} from '../dynamic/cache-faits.js'
import { envoyer, envoyerNonModifie, lireCorps, PLAFOND_CORPS } from '../dynamic/reponse.js'

/** Une réponse HTTP minimale, qui garde ce qui a été écrit. */
function reponseFactice() {
  const reponse = {
    code: null,
    entetes: {},
    corps: '',
    writeHead(code, entetes) {
      reponse.code = code
      reponse.entetes = entetes ?? {}
    },
    end(corps) {
      reponse.corps = corps ?? ''
    },
    json() {
      return JSON.parse(reponse.corps)
    },
  }
  return reponse
}

/** Une requête dont le corps arrive au tour suivant, comme un vrai flux. */
function requeteFactice({ corps = null, brut = null, erreur = false } = {}) {
  const ecouteurs = new Map()
  const req = {
    detruit: false,
    on(evenement, rappel) {
      ecouteurs.set(evenement, rappel)
      return req
    },
    destroy() {
      req.detruit = true
    },
  }
  setImmediate(() => {
    const donnee = ecouteurs.get('data')
    const fin = ecouteurs.get('end')
    if (erreur) {
      ecouteurs.get('error')?.()
      return
    }
    if (brut !== null) donnee?.(Buffer.from(brut, 'utf8'))
    else if (corps !== null) donnee?.(Buffer.from(JSON.stringify(corps), 'utf8'))
    fin?.()
  })
  return req
}

// ── Les réponses ──────────────────────────────────────────────────────────────

test('une réponse JSON est écrite avec sa longueur, et sans cache', () => {
  const res = reponseFactice()
  envoyer(res, 200, { protocole: 1 })
  assert.equal(res.code, 200)
  assert.equal(res.entetes['content-type'], 'application/json; charset=utf-8')
  assert.equal(res.entetes['cache-control'], 'no-store')
  // LA LONGUEUR EST CELLE DES OCTETS, pas des caractères : un titre accentué fait
  // deux octets de plus que sa longueur en caractères, et un `content-length` faux
  // fait échouer le client au milieu du corps.
  assert.equal(res.entetes['content-length'], Buffer.byteLength(res.corps))
  const accentue = reponseFactice()
  envoyer(accentue, 200, { titre: 'réunion — suite' })
  assert.equal(accentue.entetes['content-length'], Buffer.byteLength(accentue.corps))
  assert.deepEqual(accentue.json(), { titre: 'réunion — suite' })
})

test('un ETag n’est posé que quand il est connu', () => {
  const sans = reponseFactice()
  envoyer(sans, 200, {})
  assert.equal(sans.entetes.etag, undefined, 'promettre une validité qu’on ne sait pas calculer')

  const avec = reponseFactice()
  envoyer(avec, 200, {}, '"abc"')
  assert.equal(avec.entetes.etag, '"abc"')

  // LE 304 REND L'EMPREINTE TELLE QUELLE : la réécrire ferait échouer la
  // comparaison suivante du client, pour une raison invisible.
  const nonModifie = reponseFactice()
  envoyerNonModifie(nonModifie, '"abc"')
  assert.equal(nonModifie.code, 304)
  assert.equal(nonModifie.entetes.etag, '"abc"')
  assert.equal(nonModifie.entetes['content-length'], '0')
  assert.equal(nonModifie.corps, '')
})

// ── La lecture du corps ───────────────────────────────────────────────────────

test('un corps JSON valide est lu, et un corps vide rend un objet vide', async () => {
  assert.deepEqual(await lireCorps(requeteFactice({ corps: { texte: 'bonjour' } })), { texte: 'bonjour' })
  assert.deepEqual(await lireCorps(requeteFactice()), {}, 'aucun corps : requête sans paramètres')
})

test('un corps ILLISIBLE rend `null`, jamais `{}`', async () => {
  // CONFONDRE LES DEUX est le défaut que ce test empêche : une requête malformée
  // passerait pour une requête sans paramètres, et la route répondrait à côté au
  // lieu de refuser — un `200` sur un corps qu'on n'a pas compris.
  assert.equal(await lireCorps(requeteFactice({ brut: '{ pas du json' })), null)
  // Un JSON valide qui n'est pas un OBJET n'est pas un corps de requête non plus :
  // le rendre ferait lire des propriétés sur un nombre, et la route lèverait.
  assert.deepEqual(await lireCorps(requeteFactice({ brut: '42' })), {})
  assert.deepEqual(await lireCorps(requeteFactice({ brut: 'null' })), {})
})

test('un corps trop volumineux est REFUSÉ avant d’avoir tout lu', async () => {
  // RÈGLE #0 : une route qui accepte un corps sans limite laisse un inconnu faire
  // enfler la mémoire du harness, qui n'a pas de bac à sable.
  const enorme = reponseFactice()
  void enorme
  const req = requeteFactice()
  const promesse = lireCorps(req)
  // Un morceau au-delà du plafond, livré directement.
  const auDela = Buffer.alloc(PLAFOND_CORPS + 1)
  const ecouteurs = new Map()
  const req2 = {
    detruit: false,
    on(evenement, rappel) {
      ecouteurs.set(evenement, rappel)
      return req2
    },
    destroy() {
      req2.detruit = true
    },
  }
  const promesse2 = lireCorps(req2)
  setImmediate(() => ecouteurs.get('data')?.(auDela))
  assert.equal(await promesse2, null)
  assert.equal(req2.detruit, true, 'la requête doit être détruite, pas seulement ignorée')
  await promesse
})

// ── Le cache des faits ────────────────────────────────────────────────────────

test('les faits sont rendus tant que les marqueurs du fichier n’ont pas bougé', () => {
  const cache = creerCacheDeFaits()
  cache.poser('s1', { taille: 10, mtime: 1000 }, { id: 's1' })
  assert.deepEqual(cache.lire('s1', { taille: 10, mtime: 1000 }), { id: 's1' })
  // UNE TAILLE QUI CHANGE INVALIDE, même à mtime égal : un journal append-only qui
  // grandit sans que l'horloge du système bouge est un cas réel (deux écritures dans
  // la même milliseconde).
  assert.equal(cache.lire('s1', { taille: 11, mtime: 1000 }), undefined)
  assert.equal(cache.lire('s1', { taille: 10, mtime: 1001 }), undefined)
  // Une clé inconnue rend `undefined` — et non `null`, pour que l'appelant
  // distingue « rien en cache » de « faits vides mis en cache ».
  assert.equal(cache.lire('inconnue', { taille: 0, mtime: 0 }), undefined)
})

test('une entrée non revue est OUBLIÉE, et le balayage ne se fait pas à chaque lecture', () => {
  let instant = 0
  const cache = creerCacheDeFaits({ maintenant: () => instant })
  cache.poser('s1', { taille: 1, mtime: 1 }, { id: 's1' })
  // Juste après : toujours là.
  instant = PEREMPTION_MS - 1
  assert.notEqual(cache.lire('s1', { taille: 1, mtime: 1 }), undefined)
  // POURQUOI CETTE DATE, ET PAS `PEREMPTION_MS + 1` : la lecture ci-dessus a
  // RAFRAÎCHI l'entrée (c'est un LRU, voir le test suivant), donc la péremption
  // court à partir de là. Cinq minutes SANS être relue, plus un intervalle de
  // balayage pour que le balayage ait le droit de tourner :
  instant = PEREMPTION_MS - 1 + PEREMPTION_MS + INTERVALLE_BALAYAGE_MS + 1
  assert.equal(cache.lire('s1', { taille: 1, mtime: 1 }), undefined)
  assert.equal(cache.taille(), 0)
})

test('le cache est BORNÉ : la plus ancienne entrée cède la place', () => {
  // Sans borne, un harness qui vit des jours garderait les faits d'un millier de
  // sessions oubliées, dans un processus sans plafond de mémoire.
  const cache = creerCacheDeFaits({ entreesMax: 3 })
  for (const cle of ['a', 'b', 'c']) cache.poser(cle, { taille: 1, mtime: 1 }, { id: cle })
  cache.poser('d', { taille: 1, mtime: 1 }, { id: 'd' })
  assert.equal(cache.taille(), 3)
  assert.equal(cache.lire('a', { taille: 1, mtime: 1 }), undefined, 'la plus ancienne est évincée')
  assert.notEqual(cache.lire('d', { taille: 1, mtime: 1 }), undefined)

  // UNE ENTRÉE RELUE REDEVIENT RÉCENTE : sinon l'éviction emporterait la session
  // la plus ACTIVE au lieu de la plus ancienne.
  const autre = creerCacheDeFaits({ entreesMax: 2 })
  autre.poser('x', { taille: 1, mtime: 1 }, { id: 'x' })
  autre.poser('y', { taille: 1, mtime: 1 }, { id: 'y' })
  autre.lire('x', { taille: 1, mtime: 1 })
  autre.poser('z', { taille: 1, mtime: 1 }, { id: 'z' })
  assert.notEqual(autre.lire('x', { taille: 1, mtime: 1 }), undefined, 'x vient d’être relu')
  assert.equal(autre.lire('y', { taille: 1, mtime: 1 }), undefined, 'c’est y, la plus ancienne')
})

test('vider le cache efface tout, et la borne reste celle du module', () => {
  const cache = creerCacheDeFaits()
  cache.poser('s1', { taille: 1, mtime: 1 }, {})
  cache.vider()
  assert.equal(cache.taille(), 0)
  assert.equal(cache.lire('s1', { taille: 1, mtime: 1 }), undefined)
  assert.ok(ENTREES_MAX >= 100, 'la borne par défaut doit couvrir un usage réel')
})
