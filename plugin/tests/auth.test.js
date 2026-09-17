/**
 * LA BARRIÈRE D'ACCÈS, ÉPROUVÉE SANS HARNESS NI SERVEUR.
 *
 * POURQUOI CES TESTS, ET POURQUOI ILS SONT AUSSI COURTS. C'est la partie du dépôt
 * dont une erreur coûte le plus cher : elle décide si une requête lit des données
 * de session. Elle était noyée dans `host.js`, où l'éprouver demandait de monter un
 * faux `ctx`, un faux coffre, un faux serveur web et un arbre de sessions — c'est
 * pourquoi ses règles n'étaient vérifiées qu'INDIRECTEMENT, à travers les routes.
 * Ici, quatre fonctions et un faux `res` suffisent, et chaque règle est nommée.
 *
 * CE QUI EST ÉPROUVÉ, ET QUI COMPTE AUTANT QUE LE RESTE : ce que la barrière
 * N'ÉCRIT PAS. Aucun corps de réponse ne contient le jeton présenté, et le refus
 * d'une requête non authentifiée est IDENTIQUE quel que soit le jeton essayé.
 */

import assert from 'node:assert/strict'
import { test } from 'node:test'

import { APPAREIL, creerAuthentification, PORTEE_ECRITURE } from '../dynamic/auth.js'

const JETON_ECRITURE = 'JETONFICTIF-ecriture-000000000000000000000'
const JETON_LECTURE = 'JETONFICTIF-lecture-0000000000000000000000'

const nomDeLaCle = (genre) => (genre === 'jetons' ? 'dsh-remote/device-tokens' : 'dsh-remote/device-token')

/** Une barrière dont le registre est donné par le test. */
function barriere(appareils = { [JETON_ECRITURE]: PORTEE_ECRITURE, [JETON_LECTURE]: 'lecture' }) {
  const traces = []
  const outil = creerAuthentification({
    appareilDe: (presente) =>
      typeof presente === 'string' && Object.hasOwn(appareils, presente)
        ? { token: presente, portee: appareils[presente] }
        : null,
    tracer: (req, code, complement) => traces.push({ code, complement }),
    nomDeLaCle,
  })
  return { ...outil, traces }
}

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
  }
  return reponse
}

const requete = ({ authorization, origin } = {}) => ({
  method: 'POST',
  url: '/dsh-remote/v1/session/abc/prompt',
  headers: {
    ...(authorization === undefined ? {} : { authorization }),
    ...(origin === undefined ? {} : { origin }),
  },
})

// ── La règle 1 : aucun Origin ─────────────────────────────────────────────────

test('un Origin est refusé AVANT le jeton — même avec un jeton valide', () => {
  // L'ORDRE EST LA RÈGLE. Refuser après avoir validé le jeton laisserait une page
  // web apprendre qu'un jeton valide circule : elle ne doit rien apprendre du tout.
  const { autoriser } = barriere()
  const res = reponseFactice()
  assert.equal(autoriser(requete({ authorization: 'Bearer ' + JETON_ECRITURE, origin: 'https://hostile.test' }), res), false)
  assert.equal(res.code, 403)
  assert.equal(JSON.parse(res.corps).erreur, 'origine refusee')
  assert.equal(res[APPAREIL], undefined, 'aucun appareil ne doit être marqué')
})

test('un Origin vide compte comme un Origin : le client natif n’en envoie aucun', () => {
  const { autoriser } = barriere()
  const res = reponseFactice()
  assert.equal(autoriser(requete({ authorization: 'Bearer ' + JETON_ECRITURE, origin: '' }), res), false)
  assert.equal(res.code, 403)
})

// ── La règle 2 : un porteur valide ────────────────────────────────────────────

test('sans porteur, ou avec un porteur inconnu : 401 et une réponse FIXE', () => {
  const { autoriser } = barriere()
  for (const entete of [undefined, 'Bearer ', 'Bearer inconnu', JETON_ECRITURE, 'Basic ' + JETON_ECRITURE]) {
    const res = reponseFactice()
    // `Bearer ` sans valeur, schéma en minuscules, jeton nu : quatre formes qui ne
    // sont PAS un porteur, et qui doivent toutes rendre la même réponse.
    assert.equal(autoriser(requete({ authorization: entete }), res), false, 'accepté à tort : ' + String(entete))
    assert.equal(res.code, 401)
    assert.equal(res.entetes['www-authenticate'], 'Bearer')
    assert.equal(res.corps, '{"erreur":"jeton requis"}', 'la réponse ne doit pas distinguer les causes')
  }
})

test('un porteur valide passe, et l’appareil est marqué SUR LA RÉPONSE', () => {
  const { autoriser, porteeDe } = barriere()
  const res = reponseFactice()
  assert.equal(autoriser(requete({ authorization: 'Bearer ' + JETON_LECTURE }), res), true)
  assert.equal(porteeDe(res), 'lecture')
  // SUR LA RÉPONSE, et pas dans une variable de module : deux requêtes
  // concurrentes portant deux jetons différents ne peuvent pas se mélanger.
  const autre = reponseFactice()
  autoriser(requete({ authorization: 'Bearer ' + JETON_ECRITURE }), autre)
  assert.equal(porteeDe(res), 'lecture', 'la première réponse garde SA portée')
  assert.equal(porteeDe(autre), PORTEE_ECRITURE)
})

test('le corps d’un refus ne contient JAMAIS le porteur présenté', () => {
  // RÈGLE #0, interdit #3 : un identifiant porteur n'est ni journalisé, ni
  // renvoyé. Un refus qui le recopierait le ferait atterrir dans un journal de
  // client, une capture d'écran, un rapport de bug.
  const { autoriser } = barriere()
  const res = reponseFactice()
  autoriser(requete({ authorization: 'Bearer ' + JETON_LECTURE, origin: 'https://hostile.test' }), res)
  assert.equal(res.corps.includes(JETON_LECTURE), false)
  const res2 = reponseFactice()
  barriere({}).autoriser(requete({ authorization: 'Bearer ' + JETON_LECTURE }), res2)
  assert.equal(res2.corps.includes(JETON_LECTURE), false)
})

// ── Les règles 3 et 4 : la portée ─────────────────────────────────────────────

test('la portée n’est jamais DEVINÉE : sans authentification, elle vaut null', () => {
  // Une valeur par défaut ici serait un droit accordé par omission — et c'est
  // exactement la ligne qui décide si `refuserSiLectureSeule` refuse.
  const { porteeDe, refuserSiLectureSeule } = barriere()
  const vierge = reponseFactice()
  assert.equal(porteeDe(vierge), null)
  assert.equal(refuserSiLectureSeule(requete(), vierge), true, 'rien d’authentifié ne peut pas écrire')
  assert.equal(vierge.code, 403)
})

test('un jeton de LECTURE ne peut pas écrire, et le refus dit comment réparer', () => {
  const { autoriser, refuserSiLectureSeule, traces } = barriere()
  const res = reponseFactice()
  autoriser(requete({ authorization: 'Bearer ' + JETON_LECTURE }), res)

  assert.equal(refuserSiLectureSeule(requete(), res), true)
  assert.equal(res.code, 403)
  const corps = JSON.parse(res.corps)
  assert.equal(corps.erreur, 'jeton en lecture seule')
  assert.equal(corps.portee, 'lecture')
  // LE REMÈDE EST NOMMÉ : la clé du coffre à supprimer, et la variable à poser
  // pour refaire l'appairage. Un refus sans remède envoie chercher au hasard.
  assert.ok(corps.detail.includes('dsh-remote/device-tokens'))
  assert.ok(corps.detail.includes('DSH_REMOTE_PORTEE=ecriture'))
  // ET LE REFUS EST TRACÉ, avec sa cause — pas avec le jeton.
  assert.deepEqual(traces, [{ code: 403, complement: 'portee lecture' }])
})

test('un jeton d’ÉCRITURE passe la barrière de portée', () => {
  const { autoriser, refuserSiLectureSeule } = barriere()
  const res = reponseFactice()
  autoriser(requete({ authorization: 'Bearer ' + JETON_ECRITURE }), res)
  assert.equal(refuserSiLectureSeule(requete(), res), false, 'un jeton d’écriture doit passer')
  assert.equal(res.code, null, 'aucune réponse ne doit avoir été écrite')
})

test('la barrière d’écriture enchaîne les deux : jeton PUIS portée', () => {
  const { autoriserEcriture, traces } = barriere()
  // Sans jeton : refus au premier étage, et RIEN n'est tracé par le second.
  const sansJeton = reponseFactice()
  assert.equal(autoriserEcriture(requete(), sansJeton), false)
  assert.equal(sansJeton.code, 401)
  assert.deepEqual(traces, [], 'la portée ne se contrôle pas avant l’authentification')
  // Avec un jeton de lecture : refus au second étage.
  const lecture = reponseFactice()
  assert.equal(autoriserEcriture(requete({ authorization: 'Bearer ' + JETON_LECTURE }), lecture), false)
  assert.equal(lecture.code, 403)
  // Avec un jeton d'écriture : passe.
  const ecriture = reponseFactice()
  assert.equal(autoriserEcriture(requete({ authorization: 'Bearer ' + JETON_ECRITURE }), ecriture), true)
})
