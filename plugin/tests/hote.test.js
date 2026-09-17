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
//   7. la révocation par empreinte coupe UN appareil, sans toucher aux autres.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import zlib from 'node:zlib'

import { analyser } from '../dynamic/appairage.js'
import { apply, configurerTtlCode, inject, name, VERSION_PROTOCOLE } from '../dynamic/host.js'

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
  const ctx = {
    routes,
    coffre,
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
    on: () => {},
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
