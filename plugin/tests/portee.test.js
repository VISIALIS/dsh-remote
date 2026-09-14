/**
 * LA PORTÉE DU JETON, ÉPROUVÉE PAR LES ROUTES.
 *
 * POURQUOI CE FICHIER EXISTE. Le jeton d'appareil ouvrait la lecture ET
 * l'écriture : un jeton qui fuit donnait à son porteur le pouvoir d'écrire dans
 * l'agent de quelqu'un d'autre. La portée (`lecture` / `ecriture`) répond à
 * cette question, et un test qui ne vérifierait que la fonction de lecture de
 * l'enregistrement ne prouverait RIEN de ce qui compte : que la route refuse.
 *
 * On appelle donc les routes pour de vrai, avec un `ctx` minimal — et
 * l'assertion centrale n'est pas le code HTTP, c'est que le contrôleur n'a
 * JAMAIS été appelé : un refus qui laisse passer l'écriture n'est pas un refus.
 *
 * LANCEMENT : `node --test plugins/dsh-remote/tests/`.
 */

import assert from 'node:assert/strict'
import { EventEmitter } from 'node:events'
import { test } from 'node:test'

import {
  apply,
  PORTEE_ECRITURE,
  PORTEE_LECTURE,
  porteeDemandee,
  porteeEnregistree,
} from '../dynamic/host.js'

const JETON = 'jeton-d-essai-de-plus-de-trente-deux-caracteres'
const SESSION = '2026-09-14T10-00-00-essai'

/**
 * Un `ctx` minimal : les services que le plugin résout, et rien de plus.
 *
 * `portee` est ce que portera l'ENREGISTREMENT du jeton — `undefined` simule un
 * enregistrement écrit avant que la portée existe.
 */
async function monter({ portee } = {}) {
  const routes = []
  const ecrit = []
  const enregistrement = { kind: 'grant', payload: { token: JETON, creeLe: 1, portee } }
  const controleur = {
    prompt: async (demande) => {
      ecrit.push(demande)
      return { accepted: true }
    },
    cancel: async (demande) => {
      ecrit.push({ annulation: demande })
      return { accepted: true }
    },
  }
  const services = {
    webServer: {
      register: (route) => {
        routes.push(route)
        return { retirer() {} }
      },
      registerUpgrade: (route) => {
        routes.push(route)
        return { retirer() {} }
      },
    },
    credentials: {
      readRecord: async () => enregistrement,
      modifyRecord: async () => enregistrement,
    },
    sessionController: controleur,
  }
  const ctx = {
    get: (nom) => services[nom],
    // `ctx.effect` rattache le nettoyage au cycle de vie du plugin (cordis) :
    // on l'accepte et on l'ignore, les routes n'ayant pas à être retirées dans
    // un test qui se termine.
    effect: () => {},
    ...services,
  }
  apply(ctx, {})
  // `chargerJeton()` est lancé À LA FIN de `apply`, sans être attendu : on lui
  // laisse un tour de boucle, sinon toutes les routes répondraient 401.
  await new Promise((suite) => setImmediate(suite))
  return { routes, ecrit }
}

/** Appelle une route et rend le code, le corps décodé, et rien d'autre. */
async function appeler(routes, chemin, { methode = 'GET', jeton = JETON, corps = null, entetes = {} } = {}) {
  // La route des sessions est enregistrée en PRÉFIXE (`/v1/session` sert le
  // journal, l'envoi et l'annulation) : on cherche donc aussi par préfixe, sinon
  // le test dirait « route absente » alors que le plugin l'a bien posée.
  const route = routes.find(
    (candidate) => candidate.path === chemin || (candidate.kind === 'prefix' && chemin.startsWith(candidate.path)),
  )
  assert.ok(route, 'route absente : ' + chemin)

  const req = new EventEmitter()
  req.method = methode
  req.url = chemin
  req.headers = { ...(jeton === null ? {} : { authorization: 'Bearer ' + jeton }), ...entetes }

  const res = {
    code: null,
    corps: null,
    writeHead(code) {
      this.code = code
    },
    end(texte) {
      this.corps = typeof texte === 'string' && texte.length > 0 ? JSON.parse(texte) : null
    },
  }

  route.handler(req, res)
  // `lireCorps` attache ses écouteurs DANS le gestionnaire : le corps ne peut
  // être émis qu'après, sinon la promesse ne se résoudrait jamais.
  setImmediate(() => {
    if (corps !== null) req.emit('data', Buffer.from(JSON.stringify(corps)))
    req.emit('end')
  })
  await new Promise((suite) => setImmediate(suite))
  return { code: res.code, corps: res.corps }
}

const CHEMIN_PROMPT = '/dsh-remote/v1/session/' + SESSION + '/prompt'
const CHEMIN_ANNULER = '/dsh-remote/v1/session/' + SESSION + '/annuler'
const CHEMIN_SANTE = '/dsh-remote/v1/sante'

test('un jeton en LECTURE SEULE lit : la santé répond, et annonce sa portée', async () => {
  const { routes } = await monter({ portee: PORTEE_LECTURE })
  const { code, corps } = await appeler(routes, CHEMIN_SANTE)

  assert.equal(code, 200)
  // LA PORTÉE EST DITE : c'est ce qui permet à l'application d'expliquer
  // « ce jeton lit sans écrire » au lieu de laisser croire à une panne.
  assert.equal(corps.portee, PORTEE_LECTURE)
})

test('un jeton en LECTURE SEULE n’écrit PAS, et le contrôleur n’est jamais appelé', async () => {
  const { routes, ecrit } = await monter({ portee: PORTEE_LECTURE })
  const { code, corps } = await appeler(routes, CHEMIN_PROMPT, {
    methode: 'POST',
    corps: { texte: 'ce message ne doit pas partir', mode: 'queue' },
  })

  assert.equal(code, 403)
  assert.equal(corps.erreur, 'jeton en lecture seule')
  assert.equal(corps.portee, PORTEE_LECTURE)
  // L'ASSERTION QUI COMPTE : un refus qui laisse passer l'écriture n'en est pas
  // un. Le contrôleur est le seul chemin vers le harness.
  assert.deepEqual(ecrit, [], 'aucun prompt ne doit atteindre le contrôleur')
})

test('un jeton en LECTURE SEULE n’annule PAS un tour', async () => {
  const { routes, ecrit } = await monter({ portee: PORTEE_LECTURE })
  const { code, corps } = await appeler(routes, CHEMIN_ANNULER, { methode: 'POST' })

  assert.equal(code, 403)
  assert.equal(corps.erreur, 'jeton en lecture seule')
  assert.deepEqual(ecrit, [], 'aucune annulation ne doit atteindre le contrôleur')
})

test('la capacité d’écriture SUIT la portée : elle est fausse en lecture seule', async () => {
  const lecture = await monter({ portee: PORTEE_LECTURE })
  const santeLecture = await appeler(lecture.routes, CHEMIN_SANTE)
  // L'application cache son composeur sur ce booléen : l'annoncer faux est ce
  // qui évite de proposer un bouton qui recevrait un 403.
  assert.equal(santeLecture.corps.capacites.ecriture, false)
  assert.equal(santeLecture.corps.capacites.annulation, false)

  const ecriture = await monter({ portee: PORTEE_ECRITURE })
  const santeEcriture = await appeler(ecriture.routes, CHEMIN_SANTE)
  assert.equal(santeEcriture.corps.capacites.ecriture, true)
  assert.equal(santeEcriture.corps.capacites.annulation, true)
})

test('un jeton d’ÉCRITURE écrit, et le contrôleur reçoit le prompt', async () => {
  const { routes, ecrit } = await monter({ portee: PORTEE_ECRITURE })
  const { code } = await appeler(routes, CHEMIN_PROMPT, {
    methode: 'POST',
    corps: { texte: 'bonjour', mode: 'queue' },
  })

  assert.equal(code, 202)
  assert.equal(ecrit.length, 1)
  assert.equal(ecrit[0].content[0].text, 'bonjour')
})

test('un enregistrement SANS PORTÉE vaut écriture : une mise à jour ne retire pas un droit', async () => {
  // C'est le cas des jetons tirés avant que la portée existe : les traiter en
  // lecture seule casserait, sans le dire, une installation qui marchait.
  const { routes, ecrit } = await monter({ portee: undefined })
  const { code } = await appeler(routes, CHEMIN_PROMPT, {
    methode: 'POST',
    corps: { texte: 'toujours autorisé', mode: 'queue' },
  })

  assert.equal(code, 202)
  assert.equal(ecrit.length, 1)
})

test('les DEUX refus en 403 se distinguent par leur raison', async () => {
  // Même code, deux causes : un client qui lit `erreur` doit pouvoir dire
  // laquelle. Sans cela, un jeton en lecture seule s'afficherait comme une
  // « origine refusée » — un message faux, donc un remède faux.
  const { routes } = await monter({ portee: PORTEE_LECTURE })

  const origine = await appeler(routes, CHEMIN_PROMPT, {
    methode: 'POST',
    entetes: { origin: 'https://exemple.invalid' },
    corps: { texte: 'x', mode: 'queue' },
  })
  assert.equal(origine.code, 403)
  assert.equal(origine.corps.erreur, 'origine refusee')

  const portee = await appeler(routes, CHEMIN_PROMPT, {
    methode: 'POST',
    corps: { texte: 'x', mode: 'queue' },
  })
  assert.equal(portee.code, 403)
  assert.equal(portee.corps.erreur, 'jeton en lecture seule')
})

test('sans jeton, rien ne passe — la portée ne remplace pas le jeton', async () => {
  const { routes, ecrit } = await monter({ portee: PORTEE_ECRITURE })
  const { code } = await appeler(routes, CHEMIN_PROMPT, {
    methode: 'POST',
    jeton: null,
    corps: { texte: 'x', mode: 'queue' },
  })

  assert.equal(code, 401)
  assert.deepEqual(ecrit, [])
})

test('les fonctions de portée : le défaut d’un jeton neuf est la LECTURE', () => {
  // Le défaut est le cœur de la décision : une installation neuve n'a aucune
  // raison d'accorder l'écriture.
  assert.equal(porteeDemandee(undefined), PORTEE_LECTURE)
  assert.equal(porteeDemandee(''), PORTEE_LECTURE)
  assert.equal(porteeDemandee('lecture'), PORTEE_LECTURE)
  // Ce qui n'est pas reconnu retombe sur la lecture, jamais sur l'écriture.
  assert.equal(porteeDemandee('ECRITURE '), PORTEE_ECRITURE)
  assert.equal(porteeDemandee('tout'), PORTEE_LECTURE)

  // Et un enregistrement d'avant la portée reste en écriture.
  assert.equal(porteeEnregistree({ token: JETON }), PORTEE_ECRITURE)
  assert.equal(porteeEnregistree({ token: JETON, portee: PORTEE_LECTURE }), PORTEE_LECTURE)
  assert.equal(porteeEnregistree({ token: JETON, portee: 'autre chose' }), PORTEE_ECRITURE)
})
