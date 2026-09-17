// Tests de CHARGEMENT et de ROUTES du module hôte — ce que les autres tests ne voient pas.
//
// POURQUOI CE FICHIER EXISTE. Le dépôt a déjà payé cette panne deux fois : un
// symbole resté dans un fichier après une extraction (`PLAFOND_DECOMPRESSION`,
// vu par un test) et surtout un import manquant (`cheminIndicatif`) qui ne s'est
// vu qu'en INSTANCE NEUVE, sous la forme d'un `500 listage impossible` — c'est-à-
// dire chez l'utilisateur, après un redémarrage, sans trace utile. `node --check`
// ne voit rien : le fichier est syntaxiquement parfait, c'est la RÉSOLUTION des
// imports et l'ENREGISTREMENT des routes qui cassent.
//
// CE QUI EST ÉPROUVÉ ICI, sans harness et sans réseau :
//
//   1. le module s'importe (tous ses imports relatifs résolvent) ;
//   2. `apply` enregistre les routes attendues, chacune avec un gestionnaire ;
//   3. `apply` se dégrade proprement quand `webServer` manque (RÈGLE #3) ;
//   4. la frappe d'un code est gatée par la session NAVIGATEUR, et elle ne publie
//      JAMAIS le jeton d'appareil ;
//   5. un code ne sert QU'UNE FOIS, et il expire ;
//   6. l'échange rend un jeton PROPRE À L'APPAREIL, qui authentifie les routes
//      natives avec SA portée ;
//   7. la révocation par empreinte coupe UN appareil, sans toucher aux autres ;
//   8. le flux REFUSE un second `demarrer` au lieu de melanger deux sessions.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { EventEmitter } from 'node:events'
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import zlib from 'node:zlib'

import { analyser } from '../dynamic/appairage.js'
import { apply, configurerTtlCode, inject, name, VERSION_PROTOCOLE } from '../dynamic/host.js'
import { lireTrames } from '../dynamic/trames.js'

/**
 * LE JETON HISTORIQUE DU FAUX COFFRE, ET POURQUOI IL EXISTE DÉJÀ.
 *
 * Un `readRecord` qui rend `undefined` ferait TIRER UN JETON NEUF au plugin — et
 * il l'imprimerait dans la sortie des tests. C'est exactement ce que la RÈGLE #0
 * interdit (interdit #8 : aucun secret réel dans les tests) : la valeur serait
 * tirée par le vrai générateur, et elle sortirait dans un journal de test. Le
 * faux coffre rend donc un enregistrement DÉJÀ LÀ, avec un secret qui dit qu'il
 * est faux.
 */
const JETON_HISTORIQUE = 'JETONFICTIF-historique-000000000000000000000'

/** Un coffre en mémoire : les deux enregistrements du vrai, et rien de plus. */
function coffreFactice({ historique = JETON_HISTORIQUE, registre = null, avecSuppression = true } = {}) {
  const enregistrements = new Map()
  if (historique !== null) {
    enregistrements.set('dsh-remote/device-token', {
      kind: 'grant',
      payload: { token: historique, creeLe: 0, portee: 'lecture' },
    })
  }
  if (registre !== null) {
    enregistrements.set('dsh-remote/device-tokens', { kind: 'grant', payload: { jetons: registre } })
  }
  const service = {
    ecritures: 0,
    suppressions: [],
    readRecord: async (cle) => enregistrements.get(cle),
    modifyRecord: async (cle, fabrique) => {
      const suivant = await fabrique(enregistrements.get(cle))
      if (suivant === undefined) return enregistrements.get(cle)
      enregistrements.set(cle, suivant)
      service.ecritures += 1
      return suivant
    },
    lire: (cle) => enregistrements.get(cle),
  }
  if (avecSuppression) {
    service.deleteRecord = async (cle) => {
      enregistrements.delete(cle)
      service.suppressions.push(cle)
    }
  }
  return service
}

/** Un `ctx` minimal : juste ce qu'`apply` exige pour enregistrer ses routes. */
function contexteFactice({ coffre = coffreFactice(), avecNavigateur = true, authentifie = true, agents = null } = {}) {
  const routes = []
  // LES ECOUTEURS SONT GARDES, ET C'EST LE POINT : le plugin s'abonne au bus du
  // harness (`session/event`, `agent/status`) pour pousser les evenements sans
  // attendre sa minuterie. Un `on` muet rendrait ce chemin INEPROUVABLE — on
  // croirait le tester alors qu'on ne ferait que constater que rien ne leve.
  const ecouteurs = new Map()
  const ctx = {
    routes,
    coffre,
    ecouteurs,
    /** Emet un evenement comme le ferait le harness, et rend le nombre d'ecouteurs. */
    emettre(nom, ...arguments_) {
      const pour = ecouteurs.get(nom) ?? []
      for (const ecouteur of pour) ecouteur(...arguments_)
      return pour.length
    },
    get(service) {
      if (service === 'webServer') {
        return {
          register: (candidat) => {
            routes.push(candidat)
            return () => {}
          },
          registerUpgrade: (candidat) => {
            routes.push({ ...candidat, upgrade: true })
            return () => {}
          },
        }
      }
      if (service === 'credentials') return coffre
      // LES AGENTS NE SONT PAS TOUJOURS FOURNIS, et c'est le cas nominal de ce
      // test : `statut` vaut alors `null` (« état inconnu »). Le test d'empreinte
      // les injecte pour rejouer ce qu'un VRAI harness fait — un agent qui passe
      // de `idle` à `running` sans qu'aucun fichier ne bouge.
      if (service === 'agents') return agents ?? undefined
      if (service === 'connection') {
        if (!avecNavigateur) return undefined
        return {
          browserAuth: { isAuthenticated: () => authentifie },
          trustedHosts: ['mac-mini-essai.exemple.test'],
        }
      }
      return undefined
    },
    on(nom, ecouteur) {
      ecouteurs.set(nom, [...(ecouteurs.get(nom) ?? []), ecouteur])
    },
    effect: () => {},
  }
  return ctx
}

/** Une réponse HTTP minimale, qui garde ce qui a été écrit. */
function reponseFactice() {
  const reponse = {
    code: null,
    entetes: null,
    corps: '',
    writeHead(code, entetes) {
      reponse.code = code
      reponse.entetes = entetes ?? {}
    },
    end(corps) {
      reponse.corps = corps ?? ''
    },
    json() {
      try {
        return JSON.parse(reponse.corps)
      } catch {
        return null
      }
    },
  }
  return reponse
}

/** Une requête, avec un corps JSON optionnel — `lireCorps` écoute des évènements. */
function requete({ method = 'GET', url = '/dsh-remote/v1/appairage', headers = {}, corps = null } = {}) {
  const ecouteurs = new Map()
  const req = {
    method,
    url,
    headers,
    on(evenement, rappel) {
      ecouteurs.set(evenement, rappel)
      return req
    },
    destroy() {},
  }
  // Le corps est livré au tour suivant : c'est ce que fait un vrai flux.
  setImmediate(() => {
    const donnee = ecouteurs.get('data')
    const fin = ecouteurs.get('end')
    if (corps !== null && donnee !== undefined) donnee(Buffer.from(JSON.stringify(corps), 'utf8'))
    if (fin !== undefined) fin()
  })
  return req
}

/** Le gérant d'une route, par son chemin. */
const route = (ctx, chemin) => ctx.routes.find((candidat) => candidat.path === chemin)

/** Attend qu'une réponse asynchrone soit écrite. */
async function attendre(reponse, essais = 200) {
  for (let essai = 0; essai < essais; essai++) {
    if (reponse.code !== null) return reponse
    await new Promise((resoudre) => setTimeout(resoudre, 10))
  }
  return reponse
}

/** Applique le plugin et attend que le jeton historique soit chargé. */
async function demarrer(options = {}, config = { journaliser: false }) {
  const ctx = contexteFactice(options)
  apply(ctx, config)
  const sante = route(ctx, '/dsh-remote/v1/sante')
  for (let essai = 0; essai < 100; essai++) {
    const reponse = reponseFactice()
    sante.handler(requete({ url: '/dsh-remote/v1/sante', headers: { authorization: 'Bearer ' + JETON_HISTORIQUE } }), reponse)
    await attendre(reponse, 20)
    if (reponse.code === 200) return ctx
    await new Promise((resoudre) => setTimeout(resoudre, 25))
  }
  throw new Error('le plugin n a jamais repondu 200 : le jeton historique n a pas ete charge')
}

const entete = (valeur) => ({ authorization: 'Bearer ' + valeur })

/**
 * UNE RACINE DE SESSIONS FICTIVE, DANS UN DOSSIER TEMPORAIRE.
 *
 * POURQUOI ELLE EST ECRITE EN VRAI, ET PAS SIMULEE. La liste des sessions lit un
 * ARBRE DE DOSSIERS : deux noms de journal possibles par session, un `stat` pour
 * chacun, une mise en cache par `(taille, mtime)`. Simuler `readdir` prouverait
 * que le code appelle ce qu'on a simule — pas qu'il trouve un journal reel, ni
 * qu'une ECRITURE change l'empreinte. Ici, une seule ligne est ajoutee au
 * fichier, et c'est bien le `stat` du plugin qui doit s'en apercevoir.
 *
 * `DSH_HOME` est pose sur ce dossier : c'est exactement la variable que `apply`
 * lit pour resoudre `<DSH_HOME>/sessions` — donc aucun test ne touche a la vraie
 * installation, et aucun journal reel n'est lu ni ecrit.
 *
 * Le dossier de projet imite la forme reelle (`--tmp-essai--`), et l'horodatage
 * est FICTIF et fixe : un test qui depend de l'heure de la machine finit par
 * echouer un jour sans que personne n'ait rien change.
 */
async function arbreDeSessions({ sessions = ['session-aaa', 'session-bbb'] } = {}) {
  const racine = await mkdtemp(join(tmpdir(), 'dsh-remote-test-'))
  const ancien = process.env.DSH_HOME
  process.env.DSH_HOME = racine
  const projet = '--tmp-essai--'
  const dossier = (identifiant) => join(racine, 'sessions', projet, identifiant)
  /** Une ecriture de journal est UNE TRAME ZSTD, comme le vrai format. */
  const trame = (objet) => zlib.zstdCompressSync(Buffer.from(JSON.stringify(objet) + '\n', 'utf8'))
  // LE JOURNAL EST RECONSTRUIT EN ENTIER A CHAQUE ECRITURE, depuis ce registre.
  // Ecrire la seule trame nouvelle ECRASERAIT l'en-tete : la session perdrait son
  // identifiant, et le test mesurerait tout autre chose que ce qu'il annonce.
  const ecritures = new Map()
  const ecrire = async (identifiant, ...objets) => {
    ecritures.set(identifiant, [...(ecritures.get(identifiant) ?? []), ...objets])
    await mkdir(dossier(identifiant), { recursive: true })
    await writeFile(join(dossier(identifiant), 'session.v3.jsonl.zstd'), Buffer.concat(ecritures.get(identifiant).map(trame)))
  }
  let horodatage = 1_700_000_000_000
  for (const identifiant of sessions) {
    horodatage += 1000
    await ecrire(identifiant, {
      type: 'session',
      id: identifiant,
      cwd: '/tmp/essai',
      createdAt: horodatage,
      agentPreset: 'standard',
    })
  }
  return {
    racine,
    /** Ajoute une ecriture a une session — et fait donc bouger sa taille. */
    ajouter: (identifiant, seq) => ecrire(identifiant, { type: 'assistant/message', seq, time: horodatage + seq }),
    /** Restaure `DSH_HOME` : sans ca, un test suivant lirait un dossier efface. */
    nettoyer: async () => {
      if (ancien === undefined) delete process.env.DSH_HOME
      else process.env.DSH_HOME = ancien
      await rm(racine, { recursive: true, force: true })
    },
  }
}

/** Demande UNE PAGE d'un journal, comme le fait le client a l'ouverture. */
async function demanderUnePage(ctx, identifiant, depuis) {
  const reponse = reponseFactice()
  const chemin = '/dsh-remote/v1/session'
  route(ctx, chemin).handler(
    requete({
      method: 'POST',
      url: chemin + '/' + identifiant,
      headers: entete(JETON_HISTORIQUE),
      corps: { depuis, limite: 200 },
    }),
    reponse,
  )
  return attendre(reponse)
}

/** Interroge la liste des sessions, avec l'en-tete conditionnel demande. */
async function demanderLaListe(ctx, entetesSupplementaires = {}, corps = { limite: 2 }) {
  const reponse = reponseFactice()
  route(ctx, '/dsh-remote/v1/sessions').handler(
    requete({
      method: 'POST',
      url: '/dsh-remote/v1/sessions',
      headers: { ...entete(JETON_HISTORIQUE), ...entetesSupplementaires },
      corps,
    }),
    reponse,
  )
  return attendre(reponse)
}

/** Frappe un code, rend son secret. */
async function frapperUnCode(ctx) {
  const reponse = reponseFactice()
  route(ctx, '/dsh-remote/v1/appairage').handler(requete({ method: 'POST', url: '/dsh-remote/v1/appairage', corps: {} }), reponse)
  await attendre(reponse)
  assert.equal(reponse.code, 200, 'frappe refusee : ' + reponse.corps)
  return { code: analyser(reponse.json().charge).secret, reponse }
}

/** Échange un code, rend la réponse. */
async function echanger(ctx, code, corps = {}) {
  const reponse = reponseFactice()
  route(ctx, '/dsh-remote/v1/appairage/echange').handler(
    requete({ method: 'POST', url: '/dsh-remote/v1/appairage/echange', headers: entete(code), corps }),
    reponse,
  )
  await attendre(reponse)
  return reponse
}

test('le module hote s importe et declare son contrat', () => {
  assert.equal(name, 'dsh-remote')
  assert.equal(VERSION_PROTOCOLE, 1)
  assert.deepEqual(inject, ['webServer', 'credentials'])
})

test('les bornes de la duree de vie d un code sont tenues', () => {
  // POURQUOI CE TEST EST ICI, ET PAS AILLEURS : la valeur vient du profil, donc
  // d'un fichier que l'exploitant edite a la main. Une valeur absurde ne doit pas
  // rendre l'appairage impossible (trop court) ni rouvrir la fenetre de l'etape A
  // (trop long).
  assert.equal(configurerTtlCode(undefined), 2 * 60 * 1000, 'defaut : deux minutes')
  assert.equal(configurerTtlCode('bizarre'), 2 * 60 * 1000)
  assert.equal(configurerTtlCode(60000), 60000)
  assert.equal(configurerTtlCode(50), 1000, 'plancher d une seconde')
  assert.equal(configurerTtlCode(60 * 60 * 1000), 15 * 60 * 1000, 'plafond d un quart d heure')
})

test('apply enregistre les routes, appairage compris', async () => {
  const ctx = await demarrer()
  const chemins = ctx.routes.map((candidat) => candidat.path)
  for (const attendu of [
    '/dsh-remote/v1/sante',
    '/dsh-remote/v1/sessions',
    '/dsh-remote/v1/espaces',
    '/dsh-remote/v1/serveurs',
    '/dsh-remote/v1/appairage',
    '/dsh-remote/v1/appairage/echange',
    '/dsh-remote/v1/appareils',
    '/dsh-remote/v1/appareils/revoquer',
    '/dsh-remote/v1/session',
  ]) {
    assert.ok(chemins.includes(attendu), 'route absente : ' + attendu)
  }
  // Le flux est un Upgrade, pas une route ordinaire : il a son propre point
  // d'entree, et le confondre avec `register` le rendrait muet.
  const flux = ctx.routes.find((candidat) => candidat.path === '/dsh-remote/v1/flux')
  assert.ok(flux !== undefined && flux.upgrade === true, 'le flux doit passer par registerUpgrade')
  for (const candidat of ctx.routes) {
    assert.equal(typeof candidat.handler, 'function', 'gestionnaire absent sur ' + candidat.path)
  }
})

test('sans webServer, apply se degrade au lieu de lever', () => {
  // RÈGLE #3 : une API interne absente ne doit pas produire d'exception non
  // rattrapée dans le processus du harness.
  assert.doesNotThrow(() => apply({ get: () => undefined, on: () => {}, effect: () => {} }, {}))
  assert.doesNotThrow(() => apply({ get: () => null }, {}))
})

test('la frappe d un code exige le cookie, et ne publie JAMAIS le jeton', async () => {
  const ctx = await demarrer()
  const frappe = route(ctx, '/dsh-remote/v1/appairage')

  // Sans service navigateur : 503, et rien n'est emis.
  const sansNavigateur = contexteFactice({ avecNavigateur: false })
  apply(sansNavigateur, { journaliser: false })
  const reponse503 = reponseFactice()
  route(sansNavigateur, '/dsh-remote/v1/appairage').handler(requete({ method: 'POST', corps: {} }), reponse503)
  assert.equal(reponse503.code, 503)

  // Cookie refuse : 401.
  const refus = contexteFactice({ authentifie: false })
  apply(refus, { journaliser: false })
  const reponse401 = reponseFactice()
  route(refus, '/dsh-remote/v1/appairage').handler(requete({ method: 'POST', corps: {} }), reponse401)
  assert.equal(reponse401.code, 401)

  // Methode de lecture : 405 (la frappe ECRIT un code en memoire).
  const reponse405 = reponseFactice()
  frappe.handler(requete({ method: 'GET' }), reponse405)
  assert.equal(reponse405.code, 405)

  // Chemin nominal.
  const { reponse } = await frapperUnCode(ctx)
  assert.equal(reponse.entetes['cache-control'], 'no-store')
  const corps = reponse.json()
  assert.equal(corps.genre, 'code')
  assert.equal(corps.porteeFuture, 'lecture', 'un appareil neuf lit sans ecrire')
  assert.ok(Number.isFinite(corps.expireLe) && corps.expireLe > Date.now())
  // LA CHARGE UTILE EST UN CODE, ET LE JETON D APPAREIL N EST NULLE PART.
  assert.equal(reponse.corps.includes(JETON_HISTORIQUE), false, 'le jeton ne doit jamais sortir')
  const relu = analyser(corps.charge)
  assert.equal(relu.ok, true, 'charge illisible : ' + corps.charge)
  assert.equal(relu.genre, 'code')
  assert.equal(relu.adresse, corps.adresse)
  assert.equal(corps.adresse.includes('127.0.0.1'), false)
})

test('un code ne sert QU UNE FOIS et donne un jeton propre a l appareil', async () => {
  const ctx = await demarrer()
  const { code } = await frapperUnCode(ctx)

  // Un navigateur n'echange rien : aucun `Origin` tolere sur cette route native.
  const avecOrigine = reponseFactice()
  route(ctx, '/dsh-remote/v1/appairage/echange').handler(
    requete({
      method: 'POST',
      url: '/dsh-remote/v1/appairage/echange',
      headers: { ...entete(code), origin: 'http://attaquant.exemple.test' },
      corps: {},
    }),
    avecOrigine,
  )
  assert.equal(avecOrigine.code, 403)

  const premier = await echanger(ctx, code, { nom: 'iPhone de test' })
  assert.equal(premier.code, 200, 'corps : ' + premier.corps)
  const appareil = premier.json()
  assert.equal(appareil.portee, 'lecture')
  assert.equal(appareil.nom, 'iPhone de test')
  assert.notEqual(appareil.jeton, JETON_HISTORIQUE, 'le jeton rendu doit etre NEUF')
  assert.equal(appareil.jeton.length, 43)
  assert.equal(premier.entetes['cache-control'], 'no-store')

  // Second echange du MEME code : refuse.
  const second = await echanger(ctx, code)
  assert.equal(second.code, 403)
  assert.equal(second.json().erreur, 'code inconnu ou deja utilise')

  // Le jeton rendu AUTHENTIFIE les routes natives, avec SA portee.
  const sante = reponseFactice()
  route(ctx, '/dsh-remote/v1/sante').handler(requete({ url: '/dsh-remote/v1/sante', headers: entete(appareil.jeton) }), sante)
  assert.equal(sante.code, 200)
  assert.equal(sante.json().portee, 'lecture')
  assert.equal(sante.json().capacites.ecriture, false, 'en lecture, pas de composeur')
  assert.equal(sante.json().capacites.appairage, true, 'la capacite d echange est annoncee')
  // Le compte des appareils est publie ; la LISTE, elle, ne l'est jamais par une
  // route native — elle vit dans le panneau, sous session navigateur.
  assert.equal(sante.json().appareils, 2, 'l historique + l appareil qui vient d echanger')
  assert.equal(sante.corps.includes('empreinte'), false)

  // ET LA PORTEE EST PAR APPAREIL : ce jeton-la ne doit pas ecrire.
  const ecriture = reponseFactice()
  route(ctx, '/dsh-remote/v1/session').handler(
    requete({
      method: 'POST',
      url: '/dsh-remote/v1/session/session-essai/prompt',
      headers: entete(appareil.jeton),
      corps: { texte: 'bonjour' },
    }),
    ecriture,
  )
  await attendre(ecriture)
  assert.equal(ecriture.code, 403, 'un jeton en lecture ne doit pas ecrire')
  assert.equal(ecriture.json().erreur, 'jeton en lecture seule')
  assert.equal(ecriture.json().portee, 'lecture')
})

test('un code EXPIRE est refuse, et il reste brule', async () => {
  // Duree de vie d'une seconde : le plancher de `configurerTtlCode`. On attend
  // donc un peu plus d'une seconde — c'est le seul test lent de ce fichier, et il
  // eprouve le seul chemin qu'aucune lecture de code ne peut remplacer.
  const ctx = await demarrer({}, { journaliser: false, ttlCodeMs: 1000 })
  const { code, reponse } = await frapperUnCode(ctx)
  assert.ok(reponse.json().expireLe - Date.now() <= 1000, 'l echeance annoncee doit suivre la duree de vie')

  await new Promise((resoudre) => setTimeout(resoudre, 1200))

  const expire = await echanger(ctx, code)
  assert.equal(expire.code, 403)
  assert.equal(expire.json().erreur, 'code expire')

  // Brule : le meme code ne redevient pas valide.
  const rejoue = await echanger(ctx, code)
  assert.equal(rejoue.json().erreur, 'code inconnu ou deja utilise')
})

test('un code absent ou malforme est refuse avant toute recherche', async () => {
  const ctx = await demarrer()
  for (const valeur of [null, '', 'court', 'a'.repeat(200), 'code avec espaces 0000000000']) {
    const reponse = reponseFactice()
    route(ctx, '/dsh-remote/v1/appairage/echange').handler(
      requete({
        method: 'POST',
        url: '/dsh-remote/v1/appairage/echange',
        headers: valeur === null ? {} : entete(valeur),
        corps: {},
      }),
      reponse,
    )
    await attendre(reponse)
    assert.equal(reponse.code, 400, 'texte accepte a tort : ' + String(valeur))
  }
})

test('la liste des appareils rend des EMPREINTES, jamais des jetons', async () => {
  const ctx = await demarrer()
  const liste = reponseFactice()
  route(ctx, '/dsh-remote/v1/appareils').handler(requete({ url: '/dsh-remote/v1/appareils' }), liste)
  assert.equal(liste.code, 200)
  const corps = liste.json()
  assert.equal(corps.appareils.length, 1, 'le jeton du terminal est le premier appareil')
  assert.equal(corps.appareils[0].historique, true)
  assert.equal(corps.appareils[0].portee, 'lecture')
  // SON NOM DIT CE QUE C'EST, ET À QUI ÇA SERT. « jeton historique (terminal) »
  // faisait lire un vestige là où il y a la connexion de l'application SUR CE MAC
  // à elle-même : le propriétaire a demandé à quoi il correspondait, ce qui est
  // le défaut exact d'un nom qui n'explique rien.
  assert.match(corps.appareils[0].nom, /terminal/i, 'le nom doit dire d\'où il vient')
  assert.match(corps.appareils[0].nom, /dsh-remote-ctl/, 'et à quoi il sert encore')
  // PAS DE DATE : il n'est pas appairé, et le panneau ne doit pas laisser croire
  // à un appareil dont on aurait perdu la trace.
  assert.equal(corps.appareils[0].creeLe, null)
  assert.match(corps.appareils[0].empreinte, /^[0-9a-f]{12}$/)
  assert.equal(liste.corps.includes(JETON_HISTORIQUE), false, 'la liste ne doit JAMAIS porter un jeton')
})

test('un nom d appareil hostile est nettoye, pas refuse', async () => {
  // Le nom vient du client : il finit dans une liste que l'humain lit pour
  // decider quoi revoquer. Un retour a la ligne y fabriquerait une fausse ligne,
  // et une commande bidi inverserait l'affichage.
  const ctx = await demarrer()
  const { code } = await frapperUnCode(ctx)
  const reponse = await echanger(ctx, code, { nom: 'iPhone\nMacMini de Camille\u202e' + 'x'.repeat(200) })
  assert.equal(reponse.code, 200, 'corps : ' + reponse.corps)
  const nom = reponse.json().nom
  assert.equal(nom.includes('\n'), false)
  assert.equal(nom.includes('\u202e'), false)
  assert.ok(nom.length <= 40, 'nom trop long : ' + nom.length)
})

test('la revocation coupe UN appareil et laisse les autres', async () => {
  const ctx = await demarrer()
  const sante = route(ctx, '/dsh-remote/v1/sante')

  // Deux appareils appaires.
  const jetons = []
  for (const nom of ['premier', 'second']) {
    const { code } = await frapperUnCode(ctx)
    const reponse = await echanger(ctx, code, { nom })
    assert.equal(reponse.code, 200, 'corps : ' + reponse.corps)
    jetons.push(reponse.json().jeton)
  }

  const liste = reponseFactice()
  route(ctx, '/dsh-remote/v1/appareils').handler(requete({ url: '/dsh-remote/v1/appareils' }), liste)
  assert.equal(liste.json().appareils.length, 3, 'historique + deux appareils')
  const cible = liste.json().appareils.find((entree) => entree.nom === 'premier')
  assert.ok(cible !== undefined)

  const revocation = reponseFactice()
  route(ctx, '/dsh-remote/v1/appareils/revoquer').handler(
    requete({ method: 'POST', url: '/dsh-remote/v1/appareils/revoquer', corps: { empreinte: cible.empreinte } }),
    revocation,
  )
  await attendre(revocation)
  assert.equal(revocation.code, 200, 'corps : ' + revocation.corps)
  assert.equal(revocation.json().revoque, true)
  assert.equal(revocation.json().restants, 2)

  // Le revoque ne passe plus.
  const coupe = reponseFactice()
  sante.handler(requete({ url: '/dsh-remote/v1/sante', headers: entete(jetons[0]) }), coupe)
  assert.equal(coupe.code, 401)
  // L'autre passe toujours.
  const intact = reponseFactice()
  sante.handler(requete({ url: '/dsh-remote/v1/sante', headers: entete(jetons[1]) }), intact)
  assert.equal(intact.code, 200)
  // Et l'historique aussi.
  const historique = reponseFactice()
  sante.handler(requete({ url: '/dsh-remote/v1/sante', headers: entete(JETON_HISTORIQUE) }), historique)
  assert.equal(historique.code, 200)

  // Le registre ecrit ne contient plus que l'autre appareil — et jamais le jeton
  // historique, qui vit dans SON enregistrement.
  const registre = ctx.coffre.lire('dsh-remote/device-tokens')
  assert.equal(registre.payload.jetons.length, 1)
  assert.equal(registre.payload.jetons[0].nom, 'second')

  // Une empreinte inconnue : 404, pas une revocation silencieuse.
  const inconnue = reponseFactice()
  route(ctx, '/dsh-remote/v1/appareils/revoquer').handler(
    requete({ method: 'POST', url: '/dsh-remote/v1/appareils/revoquer', corps: { empreinte: 'abcdefabcdef' } }),
    inconnue,
  )
  await attendre(inconnue)
  assert.equal(inconnue.code, 404)
})

test('revoquer le jeton HISTORIQUE supprime son enregistrement', async () => {
  const ctx = await demarrer()
  const liste = reponseFactice()
  route(ctx, '/dsh-remote/v1/appareils').handler(requete({ url: '/dsh-remote/v1/appareils' }), liste)
  const historique = liste.json().appareils[0]
  assert.equal(historique.historique, true)

  const revocation = reponseFactice()
  route(ctx, '/dsh-remote/v1/appareils/revoquer').handler(
    requete({ method: 'POST', url: '/dsh-remote/v1/appareils/revoquer', corps: { empreinte: historique.empreinte } }),
    revocation,
  )
  await attendre(revocation)
  assert.equal(revocation.code, 200)
  assert.deepEqual(ctx.coffre.suppressions, ['dsh-remote/device-token'])
  assert.equal(ctx.coffre.lire('dsh-remote/device-token'), undefined)

  const coupe = reponseFactice()
  route(ctx, '/dsh-remote/v1/sante').handler(requete({ url: '/dsh-remote/v1/sante', headers: entete(JETON_HISTORIQUE) }), coupe)
  assert.equal(coupe.code, 401)
})

test('sans deleteRecord, la revocation de l historique est REFUSEE, pas silencieuse', async () => {
  // RÈGLE #3 : une capacite absente se dit. Une revocation qui rendrait « ok »
  // sans rien supprimer laisserait croire un appareil coupe alors qu'il ne l'est pas.
  const ctx = await demarrer({ coffre: coffreFactice({ avecSuppression: false }) })
  const liste = reponseFactice()
  route(ctx, '/dsh-remote/v1/appareils').handler(requete({ url: '/dsh-remote/v1/appareils' }), liste)
  const historique = liste.json().appareils[0]

  const revocation = reponseFactice()
  route(ctx, '/dsh-remote/v1/appareils/revoquer').handler(
    requete({ method: 'POST', url: '/dsh-remote/v1/appareils/revoquer', corps: { empreinte: historique.empreinte } }),
    revocation,
  )
  await attendre(revocation)
  assert.equal(revocation.code, 503)
  assert.equal(revocation.json().erreur, 'coffre incapable de supprimer')

  const encore = reponseFactice()
  route(ctx, '/dsh-remote/v1/sante').handler(requete({ url: '/dsh-remote/v1/sante', headers: entete(JETON_HISTORIQUE) }), encore)
  assert.equal(encore.code, 200, 'le jeton doit rester valide')
})

test('la frappe est plafonnee par fenetre', async () => {
  const ctx = await demarrer()
  let derniere = null
  for (let index = 0; index < 31; index++) {
    derniere = reponseFactice()
    route(ctx, '/dsh-remote/v1/appairage').handler(requete({ method: 'POST', url: '/dsh-remote/v1/appairage', corps: {} }), derniere)
    await attendre(derniere)
  }
  assert.equal(derniere.code, 429, 'le 31e code doit etre refuse')
  assert.equal(derniere.json().erreur, 'trop de codes demandes')
  // Les codes vivants ne s'accumulent pas pour autant : la carte est plafonnee,
  // et les codes perimes sont retires AVANT le plafond (sinon huit codes expires
  // bloqueraient la frappe d'un neuvieme).
  const liste = reponseFactice()
  route(ctx, '/dsh-remote/v1/appareils').handler(requete({ url: '/dsh-remote/v1/appareils' }), liste)
  assert.equal(liste.code, 200)
})

test('les routes natives refusent toujours Origin, les routes navigateur non', () => {
  // LA DISTINCTION EST LE CŒUR DE LA DÉROGATION : les routes natives sont gardées
  // par le jeton et refusent `Origin` ; les routes d'appairage sont des routes de
  // NAVIGATEUR, gardées par le cookie — et un navigateur, lui, envoie toujours
  // `Origin`. Le refuser là serait refuser l'usage prévu.
  const ctx = contexteFactice()
  apply(ctx, { journaliser: false })

  const sante = reponseFactice()
  route(ctx, '/dsh-remote/v1/sante').handler(
    requete({ url: '/dsh-remote/v1/sante', headers: { origin: 'http://attaquant.exemple.test' } }),
    sante,
  )
  assert.equal(sante.code, 403)
  assert.equal(sante.json().erreur, 'origine refusee')

  const echange = reponseFactice()
  route(ctx, '/dsh-remote/v1/appairage/echange').handler(
    requete({
      method: 'POST',
      url: '/dsh-remote/v1/appairage/echange',
      headers: { origin: 'http://attaquant.exemple.test' },
      corps: {},
    }),
    echange,
  )
  assert.equal(echange.code, 403, 'l echange reste une route NATIVE')

  const appairage = reponseFactice()
  route(ctx, '/dsh-remote/v1/appairage').handler(
    requete({ method: 'POST', url: '/dsh-remote/v1/appairage', headers: { origin: 'http://127.0.0.1:3080' }, corps: {} }),
    appairage,
  )
  assert.notEqual(appairage.code, 403, 'la route du panneau ne refuse pas Origin')
})

// ─────────────────────────────────────────────────────────────────────────────
// L'EMPREINTE DE LA LISTE — 115 Kio remplaces par une chaine
// ─────────────────────────────────────────────────────────────────────────────
//
// POURQUOI CES TROIS TESTS, ET PAS UN SEUL. Le gain de cette optimisation est
// invisible : un `304` qui remplace 115 Kio ne se voit pas a l'ecran. Ce qui se
// verrait, en revanche, c'est un `304` servi a tort — une liste qui ne bouge plus
// alors que quelque chose a change. Les trois cas ou l'empreinte DOIT changer
// sont donc eprouves separement, et le troisieme (l'etat d'un agent) est celui
// qu'une empreinte fondee sur les seuls fichiers aurait rate.

test('la liste des sessions porte une empreinte, et un 304 sans corps la rejoue', async () => {
  const arbre = await arbreDeSessions()
  try {
    const ctx = await demarrer()
    const premier = await demanderLaListe(ctx)

    assert.equal(premier.code, 200, 'corps : ' + premier.corps)
    const empreinte = premier.entetes.etag
    assert.equal(typeof empreinte, 'string', 'un ETag doit etre pose sur la liste')
    assert.ok(premier.corps.length > 0)
    assert.equal(premier.json().sessions.length, 2, 'les deux sessions de l arbre')
    // L'EMPREINTE N'EST PAS PUBLIEE DANS LE CORPS : c'est un en-tete, pas un
    // champ de contrat. Un client plus ancien ne doit rien voir de nouveau.
    assert.equal('empreinte' in premier.json(), false)

    const second = await demanderLaListe(ctx, { 'if-none-match': empreinte })
    assert.equal(second.code, 304, 'la meme empreinte doit rendre 304')
    assert.equal(second.corps, '', 'un 304 ne porte AUCUN corps')
    assert.equal(second.entetes.etag, empreinte)
    assert.equal(second.entetes['cache-control'], 'no-store')

    // Une empreinte perimee rend la liste entiere : le 304 n'est pas un piege.
    const perime = await demanderLaListe(ctx, { 'if-none-match': '"empreinte-perimee"' })
    assert.equal(perime.code, 200)
    assert.equal(perime.json().sessions.length, 2)
  } finally {
    await arbre.nettoyer()
  }
})

test('une ECRITURE de journal change l empreinte, meme sans nouvelle session', async () => {
  const arbre = await arbreDeSessions()
  try {
    const ctx = await demarrer()
    const avant = await demanderLaListe(ctx)
    assert.equal(avant.code, 200)

    // Une SEULE ligne de plus dans un journal : ni session nouvelle, ni nom de
    // fichier change. C'est le cas qu'un client ne doit pas manquer.
    await arbre.ajouter('session-bbb', 7)

    const apres = await demanderLaListe(ctx, { 'if-none-match': avant.entetes.etag })
    assert.equal(apres.code, 200, 'la liste a bouge : pas de 304')
    assert.notEqual(apres.entetes.etag, avant.entetes.etag)
    const bbb = apres.json().sessions.find((session) => session.id === 'session-bbb')
    assert.equal(bbb.dernierSeq, 7, 'le nouveau seq est bien publie')
  } finally {
    await arbre.nettoyer()
  }
})

test('un agent qui passe EN COURS change l empreinte sans qu aucun fichier ne bouge', async () => {
  const arbre = await arbreDeSessions()
  try {
    // L'ETAT VIVANT VIENT DU PROCESSUS, PAS DU DISQUE : c'est le piege de cette
    // optimisation. `statut` valait `idle` a l'instant d'avant, et l'agent passe
    // a `running` — aucune ecriture, donc aucune date de fichier ne change. Une
    // empreinte fondee sur `taille` et `mtime` repondrait ici `304`, et la
    // pastille d'activite de l'application resterait figee.
    let etat = 'idle'
    const agents = {
      get: () => ({ id: 'session-bbb', status: etat }),
      // `estVivante` interroge AUSSI les racines d'agents : c'est la forme que le
      // vrai harness publie, et un faux qui ne l'aurait pas rendrait le test faux
      // pour une raison qui n'a rien a voir avec l'empreinte.
      roots: () => [{ id: 'session-bbb', session: { id: 'session-bbb' } }],
    }
    const ctx = await demarrer({ agents })

    const avant = await demanderLaListe(ctx)
    assert.equal(avant.code, 200)
    const bbbAvant = avant.json().sessions.find((session) => session.id === 'session-bbb')
    assert.equal(bbbAvant.statut, 'inactif')
    assert.equal(bbbAvant.vivante, true, 'l agent connait la session : elle est vivante')

    etat = 'running'

    const apres = await demanderLaListe(ctx, { 'if-none-match': avant.entetes.etag })
    assert.equal(apres.code, 200, 'un tour vient de demarrer : pas de 304')
    assert.notEqual(apres.entetes.etag, avant.entetes.etag)
    assert.equal(apres.json().sessions.find((session) => session.id === 'session-bbb').statut, 'en_cours')
  } finally {
    await arbre.nettoyer()
  }
})

// ── Le flux : un seul `demarrer` par connexion ────────────────────────────────
//
// POURQUOI CE TEST EXISTE. Le flux n'etait eprouve que par `trames.test.js`, qui
// verifie l'ENCODAGE des octets, et par les tests Swift, qui verifient le CLIENT.
// Personne ne tenait la regle du milieu : ce que le serveur accepte comme
// suite de messages. Un second `demarrer` reecrivait `chemin`, `offset` et
// `seuilReprise` — dans un ordre non deterministe, puisque la lecture disque qui
// les precede est asynchrone — et le journal pouvait afficher un melange de deux
// sessions sans qu'aucune erreur ne soit levee.

/** Un socket d'Upgrade : ce qui lui est ecrit, et ses evenements. */
function socketFactice() {
  const socket = new EventEmitter()
  socket.ecrit = []
  socket.writableLength = 0
  socket.write = (morceau) => {
    socket.ecrit.push(Buffer.from(morceau))
    return true
  }
  socket.end = () => {
    socket.termine = true
  }
  return socket
}

/** Une trame de CLIENT, MASQUEE : la RFC 6455 l'exige, et `lireTrames` la lit. */
function trameClient(opcode, texte) {
  const donnees = Buffer.from(texte, 'utf8')
  const cle = Buffer.from([0x11, 0x22, 0x33, 0x44])
  const masque = Buffer.from(donnees.map((octet, index) => octet ^ cle[index & 3]))
  return Buffer.concat([Buffer.from([0x80 | opcode, 0x80 | donnees.length]), cle, masque])
}

/**
 * Une trame de client FRAGMENTÉE : le bit FIN est celui qu'on demande.
 *
 * Sert à rejouer ce qu'un proxy — ou un client qui découpe ses écritures — peut
 * produire, et qui laissait le flux MUET avant le réassemblage.
 */
function trameClientFragment(opcode, texte, fin) {
  const donnees = Buffer.from(texte, 'utf8')
  const cle = Buffer.from([0x55, 0x66, 0x77, 0x88])
  const masque = Buffer.from(donnees.map((octet, index) => octet ^ cle[index & 3]))
  return Buffer.concat([Buffer.from([(fin ? 0x80 : 0x00) | opcode, 0x80 | donnees.length]), cle, masque])}

/** Les messages JSON ecrits sur la socket, l'en-tete 101 mis a part. */
function messagesDuFlux(socket) {
  const { trames } = lireTrames(Buffer.concat(socket.ecrit.slice(1)))
  return trames
    .filter((trame) => trame.opcode === 0x1)
    .map((trame) => JSON.parse(trame.charge.toString('utf8')))
}

/**
 * Attend qu'un message du flux apparaisse — le serveur repond en ASYNCHRONE,
 * parce qu'il lit un journal avant d'ecrire sa `base`.
 *
 * Rend `null` au bout des essais : un test qui attendrait indefiniment masquerait
 * une regression derriere un blocage de la suite.
 */
async function attendreMessage(socket, predicat, essais = 200) {
  for (let essai = 0; essai < essais; essai++) {
    const trouve = messagesDuFlux(socket).find(predicat)
    if (trouve !== undefined) return trouve
    await new Promise((resoudre) => setTimeout(resoudre, 10))
  }
  return null
}

test('un flux REFUSE un second demarrer au lieu de melanger deux sessions', async () => {
  const arbre = await arbreDeSessions({ sessions: ['session-aaa', 'session-bbb'] })
  try {
    const ctx = await demarrer()
    const flux = route(ctx, '/dsh-remote/v1/flux')
    const socket = socketFactice()
    // LE FLUX EST FERME DANS TOUS LES CAS, y compris quand une assertion tombe :
    // sans cela, le minuteur du flux survit a l'echec, garde la boucle d'evenements
    // en vie, et le test se termine en BLOCAGE au lieu de dire ce qui a casse.
    try {
      flux.handler(
        requete({
          url: '/dsh-remote/v1/flux',
          headers: { ...entete(JETON_HISTORIQUE), 'sec-websocket-key': 'Y2xlLWRlLXRlc3QtaXhpY2k=' },
        }),
        socket,
      )
      assert.match(socket.ecrit[0].toString('utf8'), /^HTTP\/1\.1 101 /, 'l upgrade doit etre accepte')

      socket.emit('data', trameClient(0x1, JSON.stringify({ type: 'demarrer', session: 'session-aaa' })))
      const base = await attendreMessage(socket, (message) => message.type === 'base')
      assert.notEqual(base, null, 'le premier demarrer doit rendre une base')
      assert.equal(base.session.id, 'session-aaa')

      // LE SECOND `demarrer` VISE UNE AUTRE SESSION : c'est le cas qui melangerait
      // les deux journaux, pas un cas d'ecole.
      socket.emit('data', trameClient(0x1, JSON.stringify({ type: 'demarrer', session: 'session-bbb' })))
      const refus = await attendreMessage(socket, (message) => message.type === 'erreur')
      assert.notEqual(refus, null, 'un second demarrer doit etre REFUSE, pas ignore')
      assert.match(refus.message, /deja/)
      assert.equal(
        messagesDuFlux(socket).filter((message) => message.type === 'base').length,
        1,
        'aucune base ne doit partir pour la seconde session',
      )
      // LA CONNEXION SURVIT AU REFUS : le direct en cours ne doit pas mourir pour
      // une faute du client, et un refus explicite se lit.
      assert.notEqual(socket.termine, true)
    } finally {
      socket.emit('data', trameClient(0x8, ''))
    }
    assert.equal(socket.termine, true, 'la trame de fermeture doit arreter le flux')
  } finally {
    await arbre.nettoyer()
  }
})

/** La trame de fermeture ecrite sur la socket, s'il y en a une. */
function fermetureDuFlux(socket) {
  const { trames } = lireTrames(Buffer.concat(socket.ecrit.slice(1)))
  return trames.find((trame) => trame.opcode === 0x8)
}

/** Ouvre un flux sur la session demandee, et rend la socket. */
function ouvrirLeFlux(ctx, session) {
  const socket = socketFactice()
  route(ctx, '/dsh-remote/v1/flux').handler(
    requete({
      url: '/dsh-remote/v1/flux',
      headers: { ...entete(JETON_HISTORIQUE), 'sec-websocket-key': 'Y2xlLWRlLXRlc3QtaXhpY2k=' },
    }),
    socket,
  )
  socket.emit('data', trameClient(0x1, JSON.stringify({ type: 'demarrer', session })))
  return socket
}

test('un client qui ne repond PLUS est ferme, au lieu de scruter le disque pour lui', async (t) => {
  const arbre = await arbreDeSessions({ sessions: ['session-aaa'] })
  try {
    // HORLOGE SIMULEE, ET C'EST INDISPENSABLE ICI : le vrai delai se compte en
    // minutes, et un test qui attendrait une minute ne serait pas lance. Seuls
    // `setInterval` et `Date` sont simules — `setTimeout` reste reel, donc
    // l'attente de la reponse ci-dessous fonctionne normalement.
    t.mock.timers.enable({ apis: ['setInterval', 'Date'] })
    const ctx = await demarrer()
    const socket = ouvrirLeFlux(ctx, 'session-aaa')
    try {
      const base = await attendreMessage(socket, (message) => message.type === 'base')
      assert.notEqual(base, null, 'la base doit arriver avant tout controle de vie')

      // UN PING SANS PONG N'EST PAS ENCORE UNE PREUVE DE MORT : il peut se perdre,
      // ou revenir apres l'echeance sur un reseau mobile.
      t.mock.timers.tick(30000)
      assert.notEqual(socket.termine, true, 'un seul ping sans pong ne doit pas fermer')
      const premierPing = lireTrames(Buffer.concat(socket.ecrit.slice(1))).trames.some(
        (trame) => trame.opcode === 0x9,
      )
      assert.equal(premierPing, true, 'le serveur doit avoir envoye son ping')

      // DEUX PINGS SANS AUCUN PONG, SI : c'est une minute sans reponse.
      t.mock.timers.tick(30000)
      assert.equal(socket.termine, true, 'deux pings sans pong doivent fermer la socket')
      const fermeture = fermetureDuFlux(socket)
      assert.notEqual(fermeture, undefined, 'la fermeture doit porter une trame, pas un `end` muet')
      assert.equal(fermeture.charge.readUInt16BE(0), 1008)
    } finally {
      socket.emit('data', trameClient(0x8, ''))
    }
  } finally {
    await arbre.nettoyer()
  }
})

test('un client qui repond a ses pings garde son flux ouvert', async (t) => {
  const arbre = await arbreDeSessions({ sessions: ['session-aaa'] })
  try {
    t.mock.timers.enable({ apis: ['setInterval', 'Date'] })
    const ctx = await demarrer()
    const socket = ouvrirLeFlux(ctx, 'session-aaa')
    try {
      const base = await attendreMessage(socket, (message) => message.type === 'base')
      assert.notEqual(base, null, 'la base doit arriver')

      // LA CONTREPARTIE, SANS LAQUELLE LE CONTROLE DE VIE SERAIT UN DEFAUT : trois
      // pings, trois pongs, et le flux doit vivre. Un client qui repond ne doit
      // JAMAIS etre ferme pour avoir « trop attendu ».
      for (let tour = 0; tour < 3; tour++) {
        t.mock.timers.tick(30000)
        socket.emit('data', trameClient(0xa, ''))
      }
      assert.notEqual(socket.termine, true, 'un client qui repond garde son flux')
      assert.equal(fermetureDuFlux(socket), undefined, 'aucune fermeture ne doit avoir ete ecrite')
    } finally {
      socket.emit('data', trameClient(0x8, ''))
    }
  } finally {
    await arbre.nettoyer()
  }
})

// ── Le bus du harness : pousser au lieu d'attendre la minuterie ───────────────
//
// POURQUOI CES TESTS EXISTENT. Le flux n'etait alimente que par une scrutation
// disque de 750 ms : chaque evenement payait jusqu'a trois quarts de seconde de
// latence, plus un `stat` et une relecture de 64 Kio. Le harness emet pourtant
// chaque enregistrement EN MEMOIRE au moment ou il le valide
// (`session/event`). Ce chemin se prouve en EMETTANT l'evenement soi-meme : sans
// cela, on ne verifierait que l'absence d'exception.

test('un evenement du bus est pousse TOUT DE SUITE, sans attendre la scrutation', async () => {
  const arbre = await arbreDeSessions({ sessions: ['session-aaa'] })
  try {
    const ctx = await demarrer()
    const socket = ouvrirLeFlux(ctx, 'session-aaa')
    try {
      const base = await attendreMessage(socket, (message) => message.type === 'base')
      assert.notEqual(base, null, 'la base doit arriver avant tout evenement')
      const avant = messagesDuFlux(socket).filter((message) => message.type === 'evenement').length

      // L'EVENEMENT EST EMIS COMME LE FAIT LE HARNESS : la session pour portee, et
      // l'enregistrement gele. Aucune ecriture disque n'a lieu — c'est le point :
      // le fichier ne bouge pas, et pourtant le client doit recevoir le `seq`.
      const diffuses = ctx.emettre('session/event', { id: 'session-aaa' }, {
        type: 'assistant/message',
        seq: 4096,
        time: 1_700_000_000_000,
        data: { texte: 'pousse par le bus' },
      })
      assert.ok(diffuses >= 1, 'le plugin doit etre abonne au bus des sessions')

      const pousse = await attendreMessage(
        socket,
        (message) => message.type === 'evenement' && message.enregistrement?.seq === 4096,
      )
      assert.notEqual(pousse, null, 'un evenement du bus doit partir immediatement')
      const delta = messagesDuFlux(socket).find(
        (message) => message.type === 'delta' && message.dernierSeq === 4096,
      )
      assert.notEqual(delta, undefined, 'le delta doit suivre l evenement')
      assert.equal(
        messagesDuFlux(socket).filter((message) => message.type === 'evenement').length,
        avant + 1,
        'un seul evenement pousse, sans doublon',
      )
    } finally {
      socket.emit('data', trameClient(0x8, ''))
    }
  } finally {
    await arbre.nettoyer()
  }
})

test('un evenement DEJA CONNU du client n est pas renvoye', async () => {
  const arbre = await arbreDeSessions({ sessions: ['session-aaa'] })
  try {
    const ctx = await demarrer()
    // LE CLIENT REPREND AU SEQ 7 : tout ce qui est <= 7 est deja chez lui. Un bus
    // qui repousserait sans filtre ferait reapparaitre des doublons a l'ecran — le
    // defaut exact que `depuisSeq` corrige, reintroduit par une seconde source.
    const socket = socketFactice()
    route(ctx, '/dsh-remote/v1/flux').handler(
      requete({
        url: '/dsh-remote/v1/flux',
        headers: { ...entete(JETON_HISTORIQUE), 'sec-websocket-key': 'Y2xlLWRlLXRlc3QtaXhpY2k=' },
      }),
      socket,
    )
    socket.emit(
      'data',
      trameClient(0x1, JSON.stringify({ type: 'demarrer', session: 'session-aaa', depuisSeq: 7 })),
    )
    assert.notEqual(await attendreMessage(socket, (message) => message.type === 'base'), null)

    ctx.emettre('session/event', { id: 'session-aaa' }, { type: 'assistant/message', seq: 7, time: 1, data: {} })
    ctx.emettre('session/event', { id: 'session-aaa' }, { type: 'assistant/message', seq: 8, time: 1, data: {} })

    const pousse = await attendreMessage(
      socket,
      (message) => message.type === 'evenement' && message.enregistrement?.seq === 8,
    )
    assert.notEqual(pousse, null, 'le seq 8 doit passer : il est nouveau')
    const sept = messagesDuFlux(socket).filter(
      (message) => message.type === 'evenement' && message.enregistrement?.seq === 7,
    )
    assert.equal(sept.length, 0, 'le seq 7 est deja chez le client : il ne doit pas repartir')
    socket.emit('data', trameClient(0x8, ''))
  } finally {
    await arbre.nettoyer()
  }
})

test('un changement de statut d agent est pousse sur le flux de SA session', async () => {
  const arbre = await arbreDeSessions({ sessions: ['session-aaa', 'session-bbb'] })
  try {
    const ctx = await demarrer()
    const socket = ouvrirLeFlux(ctx, 'session-aaa')
    try {
      assert.notEqual(await attendreMessage(socket, (message) => message.type === 'base'), null)

      // L'AUTRE SESSION D'ABORD : son statut ne doit PAS arriver ici. C'est la
      // regle de portee — `agent/status` est emis avec l'agent pour portee, et un
      // flux ne parle que d'UNE session.
      ctx.emettre('agent/status', { agent: { id: 'session-bbb' }, status: 'running' })
      // Puis la sienne.
      const abonnes = ctx.emettre('agent/status', { agent: { id: 'session-aaa' }, status: 'running' })

      assert.ok(abonnes >= 1, 'le plugin doit etre abonne au bus des agents')
      const statut = await attendreMessage(socket, (message) => message.type === 'statut')
      assert.notEqual(statut, null, 'le changement de statut doit etre pousse')
      assert.equal(statut.statut, 'en_cours')
      assert.equal(
        messagesDuFlux(socket).filter((message) => message.type === 'statut').length,
        1,
        'un seul statut pousse : celui de la session suivie',
      )

      ctx.emettre('agent/status', { agent: { id: 'session-aaa' }, status: 'idle' })
      const repos = await attendreMessage(
        socket,
        (message) => message.type === 'statut' && message.statut === 'inactif',
      )
      assert.notEqual(repos, null, 'le retour au repos doit etre pousse aussi')
    } finally {
      socket.emit('data', trameClient(0x8, ''))
    }
  } finally {
    await arbre.nettoyer()
  }
})

test('un flux FERME ne recoit plus rien du bus', async () => {
  const arbre = await arbreDeSessions({ sessions: ['session-aaa'] })
  try {
    const ctx = await demarrer()
    const socket = ouvrirLeFlux(ctx, 'session-aaa')
    assert.notEqual(await attendreMessage(socket, (message) => message.type === 'base'), null)
    socket.emit('data', trameClient(0x8, ''))
    assert.equal(socket.termine, true, 'la fermeture doit etre traitee')

    const avant = messagesDuFlux(socket).length
    ctx.emettre('session/event', { id: 'session-aaa' }, { type: 'assistant/message', seq: 99, time: 1, data: {} })
    ctx.emettre('agent/status', { agent: { id: 'session-aaa' }, status: 'running' })
    // RIEN NE PART, ET SURTOUT RIEN NE LEVE : une connexion morte doit etre
    // RETIREE de la table du bus. Sans ce desabonnement, un serveur qui vit des
    // jours accumulerait des sockets fermees et ecrirait dedans pour toujours.
    assert.equal(messagesDuFlux(socket).length, avant, 'aucun message apres la fermeture')

    // ET LA TABLE EST VIDE : un nouvel abonne sur la meme session ne recoit que
    // ce qui le concerne.
    const seconde = ouvrirLeFlux(ctx, 'session-aaa')
    assert.notEqual(await attendreMessage(seconde, (message) => message.type === 'base'), null)
    const avantSeconde = messagesDuFlux(seconde).length
    ctx.emettre('session/event', { id: 'session-bbb' }, { type: 'assistant/message', seq: 5, time: 1, data: {} })
    await new Promise((resoudre) => setTimeout(resoudre, 60))
    assert.equal(messagesDuFlux(seconde).length, avantSeconde, 'une autre session ne parle pas ici')
    seconde.emit('data', trameClient(0x8, ''))
  } finally {
    await arbre.nettoyer()
  }
})

test('un `demarrer` FRAGMENTÉ est servi, au lieu de laisser le flux muet', async () => {
  const arbre = await arbreDeSessions({ sessions: ['session-aaa'] })
  try {
    const ctx = await demarrer()
    const socket = socketFactice()
    route(ctx, '/dsh-remote/v1/flux').handler(
      requete({
        url: '/dsh-remote/v1/flux',
        headers: { ...entete(JETON_HISTORIQUE), 'sec-websocket-key': 'Y2xlLWRlLXRlc3QtaXhpY2k=' },
      }),
      socket,
    )
    try {
      // LE MESSAGE EST COUPÉ EN DEUX, avec un PING INTERCALÉ — ce que la RFC 6455
      // autorise et ce qu'un proxy peut faire. Avant le réassemblage, `host.js`
      // ignorait tout ce qui n'était pas `0x1` : le client n'obtenait aucune
      // réponse, sans erreur ni trace. C'est la panne qu'on rend impossible.
      const texte = JSON.stringify({ type: 'demarrer', session: 'session-aaa' })
      const coupe = Math.floor(texte.length / 2)
      socket.emit('data', trameClientFragment(0x1, texte.slice(0, coupe), false))
      socket.emit('data', trameClient(0x9, ''))
      socket.emit('data', trameClientFragment(0x0, texte.slice(coupe), true))

      const base = await attendreMessage(socket, (message) => message.type === 'base')
      assert.notEqual(base, null, 'un demarrer fragmente doit etre reassemble et servi')
      assert.equal(base.session.id, 'session-aaa')
      // ET LE PING A RECU SON PONG, malgre la fragmentation en cours.
      const pong = lireTrames(Buffer.concat(socket.ecrit.slice(1))).trames.some(
        (trame) => trame.opcode === 0xa,
      )
      assert.equal(pong, true, 'le ping intercale doit recevoir son pong')
    } finally {
      socket.emit('data', trameClient(0x8, ''))
    }
  } finally {
    await arbre.nettoyer()
  }
})

test('une continuation SANS début ferme la connexion en 1002', async () => {
  const arbre = await arbreDeSessions({ sessions: ['session-aaa'] })
  try {
    const ctx = await demarrer()
    const socket = ouvrirLeFlux(ctx, 'session-aaa')
    // Une faute de protocole se DIT (1002) : l'ignorer laisserait le client
    // attendre une reponse qui ne viendrait jamais.
    socket.emit('data', trameClientFragment(0x0, 'orphelin', true))
    assert.equal(socket.termine, true, 'la faute doit fermer la connexion')
    const fermeture = fermetureDuFlux(socket)
    assert.notEqual(fermeture, undefined)
    assert.equal(fermeture.charge.readUInt16BE(0), 1002)
  } finally {
    await arbre.nettoyer()
  }
})
