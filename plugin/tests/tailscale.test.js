/**
 * Les règles de la DÉCOUVERTE, éprouvées sans lancer Tailscale.
 *
 * POURQUOI CE FICHIER EXISTE. Le plugin n'avait AUCUN test : 1 637 lignes de code
 * qui s'exécutent dans le processus du harness, chez l'utilisateur, et dont la
 * seule vérification automatique était… aucune. Ces deux fonctions d'analyse sont
 * pures — elles ne dépendent ni du réseau ni du disque — donc elles s'éprouvent
 * avec des charges utiles réelles, decodées telles quelles.
 *
 * POURQUOI `node:test`, ET PAS UNE DÉPENDANCE. La RÈGLE #0 fait de chaque
 * dépendance une surface d'attaque de plus dans un processus sans bac à sable.
 * Le runner est intégré à Node depuis la version 18 ; il n'y a rien à installer.
 *
 * LANCEMENT : `node --test plugins/dsh-remote/tests/` (ou `scripts/verifier.sh`).
 */

import assert from 'node:assert/strict'
import { test } from 'node:test'

import { analyserTailnet, raisonCourte } from '../dynamic/tailscale.js'

/** Une sortie de `tailscale status --json`, réduite à ce qui est lu. */
function sortie(contenu) {
  return JSON.stringify(contenu)
}

test('la machine locale est toujours en ligne, et marquée locale', () => {
  const macs = analyserTailnet(
    sortie({
      Self: { OS: 'macOS', DNSName: 'portable-un.exemple.ts.net.', HostName: 'portable-un', Online: false },
      Peer: {},
    }),
  )

  // `Self` est la machine qui exécute l'instance : elle répond par définition,
  // même si Tailscale la dit « Online: false » (un état transitoire au réveil).
  assert.equal(macs.length, 1)
  assert.deepEqual(macs[0], {
    nom: 'portable-un',
    nomDNS: 'portable-un.exemple.ts.net',
    enLigne: true,
    local: true,
  })
})

test('le point final du DNS est retiré — le nom doit servir d’adresse', () => {
  const macs = analyserTailnet(
    sortie({
      Self: { OS: 'macOS', DNSName: 'portable-un.exemple.ts.net.', HostName: 'portable-un' },
      Peer: {},
    }),
  )
  assert.equal(macs[0].nomDNS, 'portable-un.exemple.ts.net')
})

test('seuls les Macs sont proposés — un PC ou un téléphone ne peut pas héberger DSH', () => {
  const macs = analyserTailnet(
    sortie({
      Self: { OS: 'macOS', DNSName: 'portable-un.exemple.ts.net.', HostName: 'portable-un' },
      Peer: {
        cle1: { OS: 'windows', DNSName: 'pc.exemple.ts.net.', HostName: 'pc', Online: true },
        cle2: { OS: 'iOS', DNSName: 'iphone.exemple.ts.net.', HostName: 'iphone', Online: true },
        cle3: { OS: 'macOS', DNSName: 'portable-deux.exemple.ts.net.', HostName: 'portable-deux', Online: true },
      },
    }),
  )

  // L'ORDRE SUIT LA RÈGLE, PAS L'INTUITION : « en ligne d'abord, puis par nom ».
  // La machine LOCALE n'a aucune priorité — elle est en ligne comme une autre, et
  // `portable-deux` passe donc devant `portable-un` par ordre alphabétique.
  assert.deepEqual(
    macs.map((mac) => mac.nom),
    ['portable-deux', 'portable-un'],
  )
})

test('en ligne d’abord, puis par nom — l’ordre ne doit pas sauter d’un appel à l’autre', () => {
  const macs = analyserTailnet(
    sortie({
      Self: { OS: 'macOS', DNSName: 'zebre.exemple.ts.net.', HostName: 'zebre' },
      Peer: {
        a: { OS: 'macOS', DNSName: 'alpha.exemple.ts.net.', HostName: 'alpha', Online: false },
        b: { OS: 'macOS', DNSName: 'bravo.exemple.ts.net.', HostName: 'bravo', Online: true },
      },
    }),
  )

  // `zebre` est locale, donc en ligne ; `bravo` est en ligne ; `alpha` est hors
  // ligne et passe en dernier. Une liste qui changerait d'ordre ferait sauter les
  // vignettes sous les yeux de l'utilisateur.
  assert.deepEqual(
    macs.map((mac) => mac.nom),
    ['bravo', 'zebre', 'alpha'],
  )
})

test('JSON invalide : l’analyse LÈVE, et l’appelant en fait « sortie illisible »', () => {
  // DEUX DIAGNOSTICS DISTINCTS, ET C'EST VOULU. `lancerTailscale` attrape ce
  // lever et rend « sortie illisible » ; il ne dit « sortie inattendue » que si
  // l'analyse a rendu `null`. Confondre les deux priverait l'utilisateur de la
  // distinction entre « le CLI a rendu du charabia » et « le CLI a rendu du JSON
  // qui n'est pas un état de tailnet » — deux causes différentes.
  assert.throws(() => analyserTailnet('pas du json'), SyntaxError)
})

test('JSON valide mais forme inattendue : `null`, donc « sortie inattendue »', () => {
  assert.equal(analyserTailnet('null'), null)
  assert.equal(analyserTailnet('42'), null)
  assert.equal(analyserTailnet('"du texte"'), null)
})

test('`Self` absent et `Peer` vide : une liste vide, pas une erreur', () => {
  const macs = analyserTailnet(sortie({ Peer: {} }))
  assert.deepEqual(macs, [])
})

test('un nom DNS vide écarte la machine — elle ne serait pas joignable', () => {
  const macs = analyserTailnet(
    sortie({
      Self: { OS: 'macOS', DNSName: '', HostName: 'sans-nom' },
      Peer: { a: { OS: 'macOS', DNSName: 'ok.exemple.ts.net.', HostName: 'ok', Online: true } },
    }),
  )
  assert.deepEqual(
    macs.map((mac) => mac.nom),
    ['ok'],
  )
})

test('un nom d’hôte absent retombe sur le nom DNS', () => {
  const macs = analyserTailnet(
    sortie({ Self: { OS: 'macOS', DNSName: 'sans-nom-hote.exemple.ts.net.' }, Peer: {} }),
  )
  assert.equal(macs[0].nom, 'sans-nom-hote.exemple.ts.net')
})

test('le diagnostic tient sur UNE ligne, sans saut ni débordement', () => {
  // Il part dans une réponse HTTP : il doit rester un champ de texte. Mesuré,
  // le CLI de Tailscale rend des messages sur plusieurs lignes.
  const long = 'a'.repeat(200)
  assert.equal(raisonCourte('\n\n  premiere ligne  \nseconde ligne'), 'premiere ligne')
  assert.equal(raisonCourte('deux   espaces\tet\tune tabulation'), 'deux espaces et une tabulation')
  assert.equal(raisonCourte(long).length, 120, 'tronqué à 120 caractères')
  assert.equal(raisonCourte(null), '')
  assert.equal(raisonCourte(undefined), '')
})
