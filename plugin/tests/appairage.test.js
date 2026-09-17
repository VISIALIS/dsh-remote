// Tests du CONTRAT D'APPAIRAGE.
//
// POURQUOI CES TESTS EXISTENT. La charge utile traverse deux langages : elle est
// CONSTRUITE en JavaScript (l'hôte) et ANALYSÉE en Swift (l'application). Une
// divergence entre les deux ne se verrait qu'au moment de l'appairage, chez
// l'utilisateur, sous la forme d'un refus qui n'explique rien. Ces tests
// rejouent le fixture PARTAGÉ (`vecteurs-appairage.json`) que la suite Swift
// rejoue de son côté : c'est le même fichier, donc la même vérité.
//
// CE QUI EST ÉPROUVÉ ICI, ET POURQUOI CHAQUE POINT COMPTE :
//
//   - les vecteurs valides : le découpage, l'adresse déduite, le genre et la
//     version — ce que l'application doit retrouver à l'identique ;
//   - les vecteurs refusés : CHAQUE refus a un motif distinct, parce que trois
//     causes (« le QR vise à côté », « c'est l'adresse de la boucle locale »,
//     « mon application est trop ancienne ») ne se réparent pas pareil ;
//   - la boucle construction → analyse : ce que l'hôte émet, l'appareil doit le
//     lire. C'est le seul test qui relie vraiment les deux fonctions ;
//   - le refus de la boucle locale À LA CONSTRUCTION : l'hôte ne doit JAMAIS
//     pouvoir émettre un appairage qui ne mène nulle part. Le refus à l'analyse
//     protège l'appareil ; celui-ci protège de l'émetteur.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

import {
  analyser,
  construire,
  hoteJoignable,
  messageRefus,
  MOTIFS,
  SCHEMA,
  GENRE_CODE,
  GENRE_JETON,
  SECRETS_MINIMUMS,
} from '../dynamic/appairage.js'

// LE FIXTURE VIT À CÔTÉ DU TEST SWIFT QUI LE CONSOMME, et le JavaScript vient
// le lire ici : c'est la convention du dépôt pour un contrat entre deux
// langages (voir `tests/contrat.test.js` et `Fixtures/sessions-hote.json`). Le
// poser côté Swift, c'est le poser du côté qui ne peut pas le déplacer sans
// casser sa construction.
const vecteurs = JSON.parse(
  readFileSync(
    new URL('../../../packages/dsh-remote-swift/Tests/DSHRemoteKitTests/Fixtures/vecteurs-appairage.json', import.meta.url),
    'utf8',
  ),
)

test('les vecteurs valides sont analyses a l identique', () => {
  assert.ok(vecteurs.valides.length >= 3, 'le fixture doit couvrir les deux genres')
  for (const attendu of vecteurs.valides) {
    const lu = analyser(attendu.charge)
    assert.equal(lu.ok, true, 'refuse a tort : ' + attendu.charge)
    assert.equal(lu.hote, attendu.hote)
    assert.equal(lu.genre, attendu.genre)
    assert.equal(lu.version, attendu.version)
    assert.equal(lu.secret, attendu.secret)
    assert.equal(lu.adresse, attendu.adresse)
    // LE TRANSPORT ANNONCÉ EST RENDU, ET `http` QUAND LE SEGMENT EST OMIS : c'est
    // ce que le client Swift confronte ensuite à ce que SON paquet autorise.
    assert.equal(lu.schema, attendu.transport ?? 'http', 'transport inattendu : ' + attendu.charge)
  }
})

test('les vecteurs refuses rendent le motif attendu, et un message lisible', () => {
  assert.ok(vecteurs.refuses.length >= 10, 'le fixture doit couvrir les refus')
  for (const attendu of vecteurs.refuses) {
    const lu = analyser(attendu.charge)
    assert.equal(lu.ok, false, 'accepte a tort : ' + attendu.charge)
    assert.equal(lu.motif, attendu.motif, 'motif inattendu pour « ' + attendu.charge + ' »')
    assert.equal(typeof lu.message, 'string')
    assert.ok(lu.message.length > 10, 'un refus doit dire pourquoi')
    assert.ok(lu.secret === undefined, 'un refus ne rend jamais un secret')
  }
})

test('le fixture couvre tous les motifs declares', () => {
  // POURQUOI CE TEST. Un motif ajouté au module sans vecteur serait un refus
  // jamais éprouvé — et c'est exactement le genre de trou qui ne se voit pas.
  const couverts = new Set(vecteurs.refuses.map((vecteur) => vecteur.motif))
  for (const motif of Object.values(MOTIFS)) {
    assert.ok(couverts.has(motif), 'aucun vecteur ne refuse pour le motif ' + motif)
    assert.ok(messageRefus(motif).length > 10, 'le motif ' + motif + ' n a pas de message')
  }
})

test('ce que l hote construit, l appareil le relit', () => {
  for (const vecteur of vecteurs.valides) {
    const construit = construire({
      hote: vecteur.hote,
      genre: vecteur.genre,
      secret: vecteur.secret,
      schema: vecteur.transport ?? undefined,
    })
    assert.equal(construit.ok, true)
    assert.equal(construit.charge, vecteur.charge, 'la boucle construction/analyse a derive')
    const relu = analyser(construit.charge)
    assert.equal(relu.ok, true)
    assert.equal(relu.secret, vecteur.secret)
    assert.equal(relu.schema, vecteur.transport ?? 'http')
  }
})

test('l hote refuse d EMETTRE un appairage vers la boucle locale', () => {
  // CE TEST PROTEGE L'EMETTEUR, PAS L'APPAREIL. Le refus a l'analyse empeche un
  // appareil de viser sa propre boucle locale ; celui-ci empeche le Mac de
  // publier une adresse qui ne mene nulle part pour les autres.
  for (const hote of ['127.0.0.1', 'localhost', '0.0.0.0', '::1', 'mac-mini-essai.exemple.test:3080', '']) {
    const resultat = construire({ hote, genre: GENRE_JETON, secret: vecteurs.valides[0].secret })
    assert.equal(resultat.ok, false, 'emis a tort vers ' + hote)
    assert.ok([MOTIFS.HOTE, MOTIFS.HOTE_LOCAL].includes(resultat.motif), 'motif inattendu : ' + resultat.motif)
  }
  assert.equal(hoteJoignable('127.0.0.1'), false)
  assert.equal(hoteJoignable('mac-mini-essai.exemple.test'), true)
})

test('les seuils de secret sont ceux des tirages reels', () => {
  // LES SEUILS SONT UNE PART DU CONTRAT PARTAGÉ : les deux moitiés les
  // affirment contre le même fichier, au lieu de deux constantes jumelles qui
  // divergeraient au premier ajustement.
  assert.equal(SECRETS_MINIMUMS[GENRE_JETON], vecteurs.seuils.jeton)
  assert.equal(SECRETS_MINIMUMS[GENRE_CODE], vecteurs.seuils.code)
  assert.equal(vecteurs.seuils.jeton, 32)
  assert.equal(vecteurs.seuils.code, 22)
  const jeton = vecteurs.valides.find((vecteur) => vecteur.genre === GENRE_JETON)
  const code = vecteurs.valides.find((vecteur) => vecteur.genre === GENRE_CODE)
  assert.equal(jeton.secret.length, 43)
  assert.equal(code.secret.length, 22)
  // LE PLANCHER N'EST PAS LA LONGUEUR DU TIRAGE, et c'est deliberé : c'est un
  // FILET CONTRE LA TRONCATURE (presse-papiers qui coupe, scan partiel), pas une
  // description du secret. Un jeton ampute de 43 a 42 caracteres passe donc le
  // contrat — et c'est l'authentification, qui compare a temps constant sur la
  // valeur exacte, qui le refuse. L'inverse (exiger 43) casserait toute
  // application le jour ou le tirage grandit.
  const ampute = construire({ hote: jeton.hote, genre: GENRE_JETON, secret: jeton.secret.slice(0, 42) })
  assert.equal(ampute.ok, true, 'un jeton ampute d un caractere reste forme : l auth tranche')
  // SOUS LE PLANCHER, en revanche, le contrat refuse : c'est le filet.
  const sousLePlancher = construire({ hote: jeton.hote, genre: GENRE_JETON, secret: jeton.secret.slice(0, 31) })
  assert.equal(sousLePlancher.ok, false)
  assert.equal(sousLePlancher.motif, MOTIFS.SECRET)
  const codeAmpute = construire({ hote: code.hote, genre: GENRE_CODE, secret: code.secret.slice(0, 21) })
  assert.equal(codeAmpute.ok, false)
  assert.equal(codeAmpute.motif, MOTIFS.SECRET)
})

test('l analyse ne leve jamais, quelle que soit l entree', () => {
  // ELLE EST APPELÉE DANS UNE BOUCLE DE SCAN ET DANS UN CHAMP DE SAISIE, ou le
  // texte est incomplet a chaque frappe. Lever y serait un defaut d'ergonomie,
  // pas une securite.
  const entrees = [
    null,
    undefined,
    42,
    {},
    [],
    'dshremote',
    'dshremote:',
    SCHEMA + '://',
    SCHEMA + '://' + 'a'.repeat(600),
    SCHEMA + '://hote.exemple.test/jeton/v1/' + 'a'.repeat(43) + '?x=1',
    '   ',
  ]
  for (const entree of entrees) {
    const resultat = analyser(entree)
    assert.equal(resultat.ok, false, 'entree acceptee a tort : ' + String(entree))
    assert.equal(typeof resultat.motif, 'string')
  }
})

test('les limites du nom d hote sont les memes des deux cotes', () => {
  // POURQUOI CE TEST EXISTE. La règle du nom d'hôte n'est pas une règle DNS par
  // étiquette : elle exige un premier et un dernier caractère alphanumériques, et
  // rien de plus. Un tiret avant un point passe donc — et c'est acceptable, le
  // nom venant de Tailscale. Ce qui ne serait PAS acceptable, c'est que le Swift
  // et le JavaScript n'acceptent pas la même chose : les vecteurs ci-dessous
  // sont donc partagés, et figent la LAXITÉ autant que la sévérité.
  assert.ok(vecteurs.limites.length >= 3, 'le fixture doit figer les bornes')
  for (const limite of vecteurs.limites) {
    const lu = analyser(limite.charge)
    assert.equal(lu.ok, limite.accepte, 'desaccord sur « ' + limite.charge + ' » : ' + limite.pourquoi)
  }
})

test('un texte entoure d espaces est accepte — un collage en ajoute', () => {
  const charge = vecteurs.valides[0].charge
  const lu = analyser('  ' + charge + '\n')
  assert.equal(lu.ok, true)
  assert.equal(lu.secret, vecteurs.valides[0].secret)
})
