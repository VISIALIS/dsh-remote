/**
 * LA MÉMOIRE DES CODES D'APPAIRAGE, ÉPROUVÉE SANS SERVEUR NI HORLOGE RÉELLE.
 *
 * POURQUOI CES TESTS. Ces règles décident si un code à usage unique peut servir
 * DEUX FOIS — c'est-à-dire si un secret qui traverse un QR code peut être rejoué.
 * Elles vivaient dans trois variables de `host.js` manipulées à la main par six
 * lignes de route, et n'étaient vérifiables qu'en montant le plugin entier, avec
 * une horloge réelle : « le code expire au bout de deux minutes » se testait donc
 * en attendant… ou pas du tout. Ici, l'horloge est une variable.
 *
 * AUCUN CODE RÉEL : `tirerCode` est injecté, et les valeurs sont fictives et
 * reconnaissables (RÈGLE #0, interdit #8).
 */

import assert from 'node:assert/strict'
import { test } from 'node:test'

import {
  CODES_VIVANTS_MAX,
  configurerTtlCode,
  creerMemoireDesCodes,
  ECHANGES_MAX,
  FRAPPES_MAX,
  TTL_CODE_MAX_MS,
  TTL_CODE_MIN_MS,
} from '../dynamic/codes-appairage.js'

/** Une mémoire à horloge réglable et à codes prévisibles. */
function memoire({ ttlMs = 120000 } = {}) {
  let instant = 0
  let compteur = 0
  const m = creerMemoireDesCodes({
    ttlMs,
    maintenant: () => instant,
    tirerCode: () => 'CODEFICTIF-' + String(++compteur).padStart(4, '0'),
  })
  return { ...m, avancer: (ms) => (instant += ms), instant: () => instant }
}

test('un code frappé se consomme UNE fois, et une seule', () => {
  const m = memoire()
  const { code } = m.frapper()
  assert.equal(m.echanger(code).etat, 'valide')
  // LE SECOND ÉCHANGE DU MÊME CODE EST « INCONNU » — et non « déjà utilisé » :
  // distinguer les deux dirait à un porteur de code deviné si son texte a existé.
  assert.equal(m.echanger(code).etat, 'inconnu')
  assert.equal(m.vivants(), 0)
})

test('un code EXPIRÉ est refusé, et il reste BRÛLÉ', () => {
  const m = memoire({ ttlMs: 2000 })
  const { code } = m.frapper()
  m.avancer(2001)
  assert.equal(m.echanger(code).etat, 'expire')
  // Un code expiré ne redevient pas valide, et ne peut pas resservir : c'est la
  // même consommation immédiate qui s'applique.
  m.avancer(-2001)
  assert.equal(m.echanger(code).etat, 'inconnu', 'un code expiré ne doit jamais revivre')
})

test('la consommation est IMMÉDIATE, même si l’échange échoue ensuite', () => {
  // POURQUOI C'EST UNE RÈGLE, ET PAS UN DÉTAIL D'IMPLÉMENTATION. Rendre le code au
  // client après un échec (coffre indisponible, registre refusé) rouvrirait une
  // fenêtre de réemploi exactement là où le système vient de montrer qu'il est en
  // difficulté — donc au pire moment.
  const m = memoire()
  const { code } = m.frapper()
  assert.equal(m.echanger(code).etat, 'valide')
  // L'appelant échouerait ici. Le code, lui, est déjà consommé :
  assert.equal(m.echanger(code).etat, 'inconnu')
})

test('les codes PÉRIMÉS ne bloquent pas la frappe d’un neuvième', () => {
  // LE DÉFAUT QUE CE TEST FIXE, ET IL ÉTAIT ÉCRIT DANS LE CODE : les codes périmés
  // sont retirés AVANT que le plafond des vivants ne s'applique. Sans cet ordre,
  // un panneau laissé ouvert une heure refuserait de servir, sans dire pourquoi.
  const m = memoire({ ttlMs: 1000 })
  const frappes = []
  for (let index = 0; index < CODES_VIVANTS_MAX; index++) frappes.push(m.frapper().code)
  assert.equal(m.vivants(), CODES_VIVANTS_MAX)
  // Tous périmés, mais toujours dans la table :
  m.avancer(1001)
  assert.equal(m.vivants(), CODES_VIVANTS_MAX, 'rien n’est retiré avant la frappe suivante')
  const neuvieme = m.frapper()
  assert.notEqual(neuvieme, null, 'un code neuf doit pouvoir être frappé')
  assert.equal(m.vivants(), 1, 'seul le neuf vit encore')
  // Et les anciens ne valent plus rien.
  for (const ancien of frappes) assert.equal(m.echanger(ancien).etat, 'inconnu')
})

test('le plafond des frappes est GLOBAL et se réarme avec la fenêtre', () => {
  const m = memoire()
  for (let index = 0; index < FRAPPES_MAX; index++) assert.notEqual(m.frapper(), null)
  assert.equal(m.frapper(), null, 'au-delà du plafond, la frappe est refusée')
  // Une minute plus tard, la fenêtre est vide : on peut refrapper.
  m.avancer(60001)
  assert.notEqual(m.frapper(), null)
})

test('les DEUX plafonds sont couplés — et le second ne protège pas autre chose', () => {
  // CE QUE CE TEST MESURE, ET CE QU'IL INTERDIT DE CROIRE. Un échange exige un code
  // frappé : `FRAPPES_MAX` et `ECHANGES_MAX` valent tous deux 30 sur la même
  // fenêtre d'une minute, et le plafond des codes VIVANTS (8) empêche d'en
  // accumuler. Conséquence : la 31e frappe est refusée AVANT que la 31e dépense ne
  // puisse avoir lieu, et le plafond des échanges est une SECONDE SERRURE SUR LA
  // MÊME PORTE — pas une protection supplémentaire.
  //
  // C'est écrit ici parce que le contraire se lirait facilement dans le code : deux
  // plafonds nommés différemment laissent croire à deux contrôles indépendants. Pour
  // que le second protège quelque chose, il faudrait `FRAPPES_MAX > ECHANGES_MAX`.
  const m = memoire()
  let echanges = 0
  for (;;) {
    const frappe = m.frapper()
    if (frappe === null) break
    assert.equal(m.echanger(frappe.code).etat, 'valide')
    echanges += 1
    assert.ok(echanges <= FRAPPES_MAX, 'on ne doit pas échanger plus qu’on ne frappe')
  }
  assert.equal(echanges, FRAPPES_MAX, 'les deux plafonds se vident en même temps')
  // ET LA FENÊTRE SE RÉARME : les deux compteurs retombent ensemble.
  m.avancer(60001)
  assert.notEqual(m.frapper(), null)
})

test('la durée de vie du profil est BORNÉE dans les deux sens', () => {
  // La valeur vient d'un fichier que l'exploitant édite : elle ne doit ni rendre
  // l'appairage impossible (trop court) ni rouvrir la fenêtre de l'étape A.
  assert.equal(configurerTtlCode(undefined), 120000, 'défaut : deux minutes')
  assert.equal(configurerTtlCode('bizarre'), 120000)
  assert.equal(configurerTtlCode(60000), 60000)
  assert.equal(configurerTtlCode(50), TTL_CODE_MIN_MS, 'plancher d’une seconde')
  assert.equal(configurerTtlCode(60 * 60 * 1000), TTL_CODE_MAX_MS, 'plafond d’un quart d’heure')
})
