/**
 * LA RÉSOLUTION DU NOM D'HÔTE ET DU TRANSPORT, ÉPROUVÉE SANS TAILSCALE.
 *
 * POURQUOI CES TESTS. Ce que cette pièce produit finit dans un QR code, donc c'est
 * définitif pour l'appareil qui le scanne : un nom injoignable, ou un transport
 * faux, donne un appairage qui ne peut aboutir nulle part. Ses deux règles — jamais
 * la boucle locale, le schéma se LIT au lieu de se deviner — ne se voyaient qu'à la
 * lecture du code de `host.js`, et les deux caches qui les entourent n'étaient pas
 * éprouvables du tout.
 *
 * LA DÉCOUVERTE ET LA PUBLICATION SONT INJECTÉES : aucun test ne lance `tailscale`,
 * donc aucun ne dépend de l'état du tailnet de la machine qui exécute la suite.
 */

import assert from 'node:assert/strict'
import { test } from 'node:test'

import { creerResolveurDHote, TTL_DECOUVERTE_MS } from '../dynamic/resolution-hote.js'

/** Une découverte factice, qui compte ses appels. */
function decouverteFactice(machines, { diagnostic = null } = {}) {
  const outil = { appels: 0 }
  outil.fonction = async () => {
    outil.appels += 1
    return { machines, diagnostic }
  }
  return outil
}

function publicationFactice(valeur) {
  const outil = { appels: 0 }
  outil.fonction = async () => {
    outil.appels += 1
    return valeur
  }
  return outil
}

const machineLocale = { local: true, nomDNS: 'macmini.exemple.ts.net' }
const machineDistante = { local: false, nomDNS: 'portable.exemple.ts.net' }

test('la machine LOCALE de Tailscale est préférée, et le transport vient de la publication', async () => {
  const d = decouverteFactice([machineDistante, machineLocale])
  const p = publicationFactice({ schema: 'https', port: 443, hote: 'macmini.exemple.ts.net' })
  const resolveur = creerResolveurDHote({ hotesDeclares: () => ['declare.exemple.ts.net'], decouvrir: d.fonction, lireLaPublication: p.fonction })

  assert.deepEqual(await resolveur.resoudre(), {
    hote: 'macmini.exemple.ts.net',
    via: 'tailscale',
    schema: 'https',
  })
  // UNE MACHINE DISTANTE N'EST PAS CETTE MACHINE : prendre la première de la liste
  // publierait le nom d'un autre Mac, et l'appareil appairerait ailleurs.
  assert.equal((await resolveur.resoudre()).hote !== machineDistante.nomDNS, true)
})

test('sans publication, le schéma retombe sur le CLAIR — jamais sur une adresse inventée', async () => {
  // C'est le comportement d'avant : un binaire muet ne doit pas transformer une
  // installation qui marchait en installation qui ne répond plus.
  const d = decouverteFactice([machineLocale])
  for (const valeur of [null, { schema: 'ftp' }, { schema: 'http' }]) {
    const resolveur = creerResolveurDHote({
      hotesDeclares: () => [],
      decouvrir: d.fonction,
      lireLaPublication: publicationFactice(valeur).fonction,
    })
    assert.equal((await resolveur.resoudre()).schema, 'http', 'valeur : ' + JSON.stringify(valeur))
  }
})

test('une publication qui LÈVE est traitée comme une absence de publication', async () => {
  const resolveur = creerResolveurDHote({
    hotesDeclares: () => [],
    decouvrir: decouverteFactice([machineLocale]).fonction,
    lireLaPublication: async () => {
      throw new Error('binaire introuvable')
    },
  })
  assert.equal((await resolveur.resoudre()).schema, 'http')
})

test('Tailscale muet : l’hôte DÉCLARÉ prend le relais, sans son port', async () => {
  // La seconde source existe pour qu'un Tailscale muet ne rende pas l'appairage
  // impossible. Le profil peut déclarer un hôte AVEC son port : le QR, lui, n'en
  // porte jamais (le port est implicite, 80 ou 443 selon le transport).
  const resolveur = creerResolveurDHote({
    hotesDeclares: () => ['portable.exemple.ts.net:3080'],
    decouvrir: async () => ({ machines: null, diagnostic: 'tailscale muet' }),
    lireLaPublication: async () => null,
  })
  assert.deepEqual(await resolveur.resoudre(), {
    hote: 'portable.exemple.ts.net',
    via: 'hote declare',
    schema: 'http',
  })
})

test('sans aucune source, l’hôte est VIDE — la frappe refusera, elle ne mentira pas', async () => {
  const resolveur = creerResolveurDHote({
    hotesDeclares: () => [],
    decouvrir: async () => ({ machines: [], diagnostic: null }),
    lireLaPublication: async () => null,
  })
  assert.equal((await resolveur.resoudre()).hote, '')
  assert.equal((await resolveur.resoudre()).via, 'aucun')
})

test('les deux lectures sont MISES EN CACHE, et le cache expire', async () => {
  // Deux processus lancés à chaque frappe de code seraient un coût sans
  // contrepartie : un tailnet ne change pas d'une seconde à l'autre.
  let instant = 0
  const d = decouverteFactice([machineLocale])
  const p = publicationFactice({ schema: 'https', port: 443, hote: machineLocale.nomDNS })
  const resolveur = creerResolveurDHote({
    hotesDeclares: () => [],
    decouvrir: d.fonction,
    lireLaPublication: p.fonction,
    maintenant: () => instant,
  })
  await resolveur.resoudre()
  await resolveur.resoudre()
  await resolveur.resoudre()
  assert.equal(d.appels, 1, 'une seule découverte pour trois résolutions')
  assert.equal(p.appels, 1, 'une seule lecture de publication')

  // Après la durée de vie, on relit — c'est ce qui fait qu'un passage à HTTPS est
  // vu sans redémarrer le harness.
  instant = TTL_DECOUVERTE_MS + 1
  await resolveur.resoudre()
  assert.equal(d.appels, 2)
  assert.equal(p.appels, 2)
})

test('un `null` de publication EST un résultat mis en cache', async () => {
  // Sinon un binaire muet relancerait le CLI à chaque demande, indéfiniment.
  const p = publicationFactice(null)
  const resolveur = creerResolveurDHote({
    hotesDeclares: () => [],
    decouvrir: decouverteFactice([machineLocale]).fonction,
    lireLaPublication: p.fonction,
  })
  await resolveur.resoudre()
  await resolveur.resoudre()
  assert.equal(p.appels, 1)
})

test('la route des serveurs se sert du MÊME cache que la résolution', async () => {
  // POURQUOI C'EST ÉPROUVÉ : les deux étaient deux blocs séparés dans `host.js`, et
  // deux caches pour la même lecture auraient lancé `tailscale status` deux fois par
  // cycle — la route toutes les quinze secondes, la frappe à chaque code.
  const d = decouverteFactice([machineLocale], { diagnostic: 'aucune machine du tailnet' })
  const resolveur = creerResolveurDHote({ hotesDeclares: () => [], decouvrir: d.fonction, lireLaPublication: async () => null })
  const liste = await resolveur.machines()
  assert.deepEqual(liste, { machines: [machineLocale], diagnostic: 'aucune machine du tailnet' })
  await resolveur.resoudre()
  assert.equal(d.appels, 1, 'une seule lecture pour les deux usages')
})
