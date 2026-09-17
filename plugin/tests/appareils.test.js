/**
 * LE REGISTRE DES APPAREILS, ÉPROUVÉ SANS COFFRE NI HARNESS.
 *
 * POURQUOI CES TESTS. Ce module est le dépositaire de l'état qui décide qui peut
 * parler au harness : le jeton historique, sa portée, et la liste des appareils
 * appairés. Ses règles n'étaient vérifiables qu'à travers les routes — donc en
 * montant un faux `ctx`, un faux coffre, un faux serveur et un arbre de sessions,
 * et seulement pour les cas qu'un test de route avait eu l'idée d'exercer. Ici,
 * chaque règle est nommée, et les cas limites (registre cassé, entrée mal formée,
 * `deleteRecord` absent) s'écrivent en trois lignes.
 *
 * LE FAUX COFFRE EST EN MÉMOIRE ET NE CONTIENT QUE DES VALEURS FICTIVES : aucun
 * test ne touche un secret réel (RÈGLE #0, interdit #8).
 */

import assert from 'node:assert/strict'
import { test } from 'node:test'

import { creerRegistreDAppareils } from '../dynamic/appareils.js'
import { PORTEE_ECRITURE, PORTEE_LECTURE } from '../dynamic/auth.js'

const CLE_JETON = 'dsh-remote/device-token'
const CLE_JETONS = 'dsh-remote/device-tokens'
const JETON_HISTORIQUE = 'JETONFICTIF-historique-000000000000000000000'
const JETON_APPAREIL = 'JETONFICTIF-appareil-00000000000000000000000'

/**
 * Un coffre en mémoire, avec les deux enregistrements du vrai.
 *
 * `avecSuppression: false` rejoue le coffre incomplet que le vrai service peut
 * être — c'est le cas « la révocation de l'historique est REFUSÉE, pas
 * silencieuse », et il n'était éprouvable qu'en montant tout le plugin.
 */
function coffreFactice({ jeton = JETON_HISTORIQUE, portee = PORTEE_ECRITURE, jetons = [], avecSuppression = true, illisibleRegistre = false } = {}) {
  const enregistrements = new Map()
  if (jeton !== null) enregistrements.set(CLE_JETON, { kind: 'grant', payload: { token: jeton, creeLe: 0, portee } })
  if (jetons.length > 0) enregistrements.set(CLE_JETONS, { kind: 'grant', payload: { jetons } })
  const service = {
    ecritures: 0,
    supprimes: [],
    readRecord: async (cle) => {
      // `illisibleRegistre` ne casse QUE l'enregistrement des appareils : le jeton
      // du terminal reste lisible, ce qui est le cas reel a eprouver — un registre
      // casse ne doit pas faire perdre la connexion qui permet de le reprendre.
      if (illisibleRegistre && cle === CLE_JETONS) throw new Error('registre illisible')
      return enregistrements.get(cle)
    },
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
      service.supprimes.push(cle)
    }
  }
  return service
}

const porteeDemandee = (valeur) => (String(valeur ?? '').trim().toLowerCase() === PORTEE_ECRITURE ? PORTEE_ECRITURE : PORTEE_LECTURE)
const porteeEnregistree = (payload) =>
  payload?.portee === PORTEE_LECTURE ? PORTEE_LECTURE : PORTEE_ECRITURE

function registre(coffre, options = {}) {
  return creerRegistreDAppareils({
    coffre: () => coffre,
    cles: { jeton: CLE_JETON, jetons: CLE_JETONS },
    porteeDemandee,
    porteeEnregistree,
    journal: options.journal ?? (() => {}),
    tirerJeton: options.tirerJeton ?? (() => 'JETONFICTIF-tire-000000000000000000000000000'),
  })
}

// ── Le chargement, et le jeton historique ─────────────────────────────────────

test('le jeton historique est LU, jamais réécrit, et sa portée vient de l’enregistrement', async () => {
  const coffre = coffreFactice({ portee: PORTEE_LECTURE })
  const r = registre(coffre)
  const { jeton } = await r.charger()
  assert.equal(jeton, JETON_HISTORIQUE)
  assert.equal(r.porteeHistorique(), PORTEE_LECTURE, 'la portée est celle qui a été tirée avec le jeton')
  assert.equal(coffre.ecritures, 0, 'un jeton existant ne doit pas être réécrit')
  // L'HISTORIQUE EST EN TÊTE de la liste, et il est NOMMÉ : « Jeton du terminal »,
  // parce que « historique » faisait lire un vestige là où c'est la connexion du
  // terminal sur ce Mac.
  assert.equal(r.liste().length, 1)
  assert.equal(r.liste()[0].historique, true)
  assert.ok(r.liste()[0].nom.includes('terminal'))
})

test('sans jeton rangé, il en est TIRÉ un — affiché UNE fois — et rangé', async () => {
  const coffre = coffreFactice({ jeton: null })
  const lignes = []
  const r = registre(coffre, { journal: (texte) => lignes.push(texte), tirerJeton: () => 'JETONFICTIF-neuf-00000000000000000000000000' })
  const { jeton } = await r.charger()
  assert.equal(jeton, 'JETONFICTIF-neuf-00000000000000000000000000')
  assert.equal(coffre.ecritures, 1, 'le jeton neuf est rangé')
  // RÈGLE #0, interdit #3 : l'affichage unique est le SEUL endroit qui montre un
  // jeton, et il est au terminal de l'utilisateur — pas dans une route.
  assert.equal(lignes.filter((ligne) => ligne.includes('JETONFICTIF-neuf')).length, 1)
  // LA PORTÉE EST DITE À LA CRÉATION, et c'est le seul endroit où l'utilisateur
  // l'apprend : `DSH_REMOTE_PORTEE` n'étant pas posée, le défaut est `lecture`.
  assert.ok(lignes.some((ligne) => ligne.includes('PORTEE LECTURE')))
  assert.ok(
    lignes.some((ligne) => ligne.includes('LIT sans pouvoir ecrire')),
    'un jeton de lecture doit dire ce qu il ne permet pas')
})

test('un registre ILLISIBLE ne fait pas perdre le jeton du terminal', async () => {
  // Le perdre déconnecterait la seule connexion qui permette de réparer : on
  // signale, et on continue avec le jeton historique seul.
  const coffre = coffreFactice({ illisibleRegistre: true })
  const r = registre(coffre)
  const { jeton, appareils, illisible } = await r.charger()
  assert.equal(jeton, JETON_HISTORIQUE)
  assert.notEqual(illisible, null, 'la raison est rendue, pour que l appelant la journalise')
  assert.equal(appareils.length, 1)
  assert.equal(appareils[0].historique, true)
})

// ── L'authentification ───────────────────────────────────────────────────────

test('un appareil est reconnu par son jeton, et une entrée MAL FORMÉE est ignorée', async () => {
  const coffre = coffreFactice({
    jetons: [
      { token: JETON_APPAREIL, portee: PORTEE_LECTURE, creeLe: 1, nom: 'iPhone' },
      { token: 'court', portee: PORTEE_ECRITURE, nom: 'tronqué' },
      null,
      { nom: 'sans jeton' },
    ],
  })
  const r = registre(coffre)
  await r.charger()
  // UNE ENTRÉE CASSÉE NE DOIT PAS RENDRE LES AUTRES INUTILISABLES : le registre vit
  // dans un fichier que l'utilisateur peut éditer.
  assert.equal(r.liste().length, 2, 'un historique + un appareil valide')
  assert.equal(r.appareilDe(JETON_APPAREIL)?.nom, 'iPhone')
  assert.equal(r.jetonValide(JETON_APPAREIL), true)
  assert.equal(r.appareilDe(JETON_HISTORIQUE)?.historique, true)
  for (const mauvais of [null, undefined, '', 'inconnu', 42]) {
    assert.equal(r.appareilDe(mauvais), null, 'accepté à tort : ' + String(mauvais))
    assert.equal(r.jetonValide(mauvais), false)
  }
})

test('l’empreinte DÉSIGNE un appareil sans jamais révéler son jeton', async () => {
  const r = registre(coffreFactice())
  await r.charger()
  const empreinte = r.empreinteDe(JETON_HISTORIQUE)
  assert.match(empreinte, /^[0-9a-f]{12}$/)
  assert.equal(empreinte.includes(JETON_HISTORIQUE.slice(0, 8)), false, 'aucun fragment du jeton ne doit apparaître')
  assert.equal(r.empreinteDe(JETON_HISTORIQUE), empreinte, 'la même valeur rend la même empreinte')
  assert.notEqual(r.empreinteDe(JETON_APPAREIL), empreinte)
})

// ── L'écriture ────────────────────────────────────────────────────────────────

test('ajouter écrit DANS LE COFFRE avant de garder en mémoire', async () => {
  const coffre = coffreFactice()
  const r = registre(coffre)
  await r.charger()
  await r.ajouter({ token: JETON_APPAREIL, portee: PORTEE_LECTURE, creeLe: 42, nom: 'iPad' })
  assert.equal(coffre.ecritures, 1)
  const range = coffre.lire(CLE_JETONS).payload.jetons
  assert.equal(range.length, 1)
  assert.equal(range[0].token, JETON_APPAREIL)
  assert.equal(r.nombre(), 2, 'l’appareil est aussi dans la liste en mémoire')
  assert.equal(r.appareilDe(JETON_APPAREIL)?.nom, 'iPad')
})

test('sans coffre, ajouter ÉCHOUE au lieu de garder un appareil fantôme', async () => {
  // Un appareil gardé en mémoire mais absent du coffre disparaîtrait au
  // redémarrage : le panneau afficherait un appareil appairé qui n'existe pas.
  const r = creerRegistreDAppareils({
    coffre: () => null,
    cles: { jeton: CLE_JETON, jetons: CLE_JETONS },
    porteeDemandee,
    porteeEnregistree,
    journal: () => {},
  })
  await r.charger()
  await assert.rejects(
    () => r.ajouter({ token: JETON_APPAREIL, portee: PORTEE_LECTURE, creeLe: 1, nom: 'iPad' }),
    /coffre indisponible/)
  assert.equal(r.appareilDe(JETON_APPAREIL), null)
})

// ── La révocation ─────────────────────────────────────────────────────────────

test('révoquer un appareil appairé le retire du coffre ET de la liste', async () => {
  const coffre = coffreFactice({ jetons: [{ token: JETON_APPAREIL, portee: PORTEE_LECTURE, creeLe: 1, nom: 'iPhone' }] })
  const r = registre(coffre)
  await r.charger()
  const resultat = await r.retirer(r.empreinteDe(JETON_APPAREIL))
  assert.equal(resultat.ok, true)
  assert.equal(resultat.nom, 'iPhone')
  assert.equal(resultat.restants, 1, 'il reste le jeton du terminal')
  assert.equal(r.appareilDe(JETON_APPAREIL), null)
  assert.equal(coffre.lire(CLE_JETONS).payload.jetons.length, 0)
  // LE JETON HISTORIQUE N'EST PAS TOUCHÉ : révoquer un appareil ne déconnecte pas
  // le terminal.
  assert.equal(r.appareilDe(JETON_HISTORIQUE)?.historique, true)
})

test('révoquer le jeton HISTORIQUE le SUPPRIME — il ne se filtre pas', async () => {
  const coffre = coffreFactice()
  const r = registre(coffre)
  await r.charger()
  const resultat = await r.retirer(r.empreinteDe(JETON_HISTORIQUE))
  assert.equal(resultat.ok, true)
  assert.equal(resultat.historique, true)
  // Il vit dans son propre enregistrement : « tourner le jeton » veut dire
  // l'effacer, et un jeton neuf sera tiré au prochain démarrage.
  assert.deepEqual(coffre.supprimes, [CLE_JETON])
  assert.equal(r.jetonHistorique(), null)
  assert.equal(r.nombre(), 0)
})

test('sans `deleteRecord`, la révocation de l’historique est REFUSÉE, pas silencieuse', async () => {
  const coffre = coffreFactice({ avecSuppression: false })
  const r = registre(coffre)
  await r.charger()
  const resultat = await r.retirer(r.empreinteDe(JETON_HISTORIQUE))
  assert.equal(resultat.ok, false)
  assert.equal(resultat.code, 503)
  assert.equal(resultat.corps.erreur, 'coffre incapable de supprimer')
  // ET RIEN N'A BOUGÉ : une révocation qui n'efface rien serait un mensonge.
  assert.equal(r.jetonHistorique(), JETON_HISTORIQUE)
  assert.equal(r.nombre(), 1)
})

test('révoquer une empreinte inconnue ou mal formée est refusé, et dit pourquoi', async () => {
  const r = registre(coffreFactice())
  await r.charger()
  for (const mauvaise of ['', 'ZZZ', 'pas-hexadecimal', null, undefined, '0123456789abc']) {
    const resultat = await r.retirer(mauvaise)
    assert.equal(resultat.ok, false, 'accepté à tort : ' + String(mauvaise))
    assert.equal(resultat.code, 400)
  }
  // Une empreinte BIEN FORMÉE mais inconnue : 404, avec le remède (recharger).
  const inconnue = await r.retirer('0123456789ab')
  assert.equal(inconnue.code, 404)
  assert.ok(inconnue.corps.detail.includes('rechargez'))
})
