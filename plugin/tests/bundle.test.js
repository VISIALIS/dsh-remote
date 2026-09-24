// Tests du BUNDLE CLIENT — le fichier que le navigateur reçoit réellement.
//
// POURQUOI CE FICHIER EXISTE, ET CE QU'IL PROUVE. Le panneau d'appairage est un
// `client.js` ÉCRIT À LA MAIN, sans étape de compilation : c'est une forme que
// ce dépôt n'avait jamais produite, et une forme qui peut échouer de trois
// façons SILENCIEUSES — un `id` qui ne correspond pas au nom du paquet (le
// chargeur refuse alors d'enregistrer le bundle), une copie d'encodeur qui a
// dérivé, un enregistrement de slot mal formé. Aucune de ces trois pannes ne
// casse quoi que ce soit au chargement du harness : le panneau est simplement
// absent, sans erreur visible.
//
// CE QUI EST ÉPROUVÉ ICI :
//
//   1. le bundle s'exécute et s'annonce avec le nom du paquet (`id`) ;
//   2. l'encodeur qu'il embarque est IDENTIQUE, caractère pour caractère, à la
//      référence figée sous `encodeur-reference.js` — la copie est assumée
//      (RÈGLE #2), sa dérive ne l'est pas ;
//   3. les invariants de la matrice (taille, motifs de repérage) tiennent ;
//   4. la charge utile RÉELLE est décodée par une implémentation INDÉPENDANTE
//      (Vision/macOS, via `tests/outils/decoder-qr.swift`) ;
//   5. `apply` enregistre le panneau dans le bon slot, et se dégrade — sans
//      lever — quand le service `slots` est absent.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, mkdtempSync, existsSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { tmpdir } from 'node:os'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { dirname, join } from 'node:path'

import { ecrireBmp } from './outils/qr-vers-bmp.js'

const ICI = dirname(fileURLToPath(import.meta.url))
const PAQUET = join(ICI, '..', 'package.json')
const BUNDLE = join(ICI, '..', 'dynamic', 'client.js')
const ENCODEUR_ORIGINE = join(ICI, 'encodeur-reference.js')

// ── Chargement du bundle hors navigateur ─────────────────────────────────────
//
// `window.__ModuleLoader__.load` est la seule porte d'entrée du bundle. On la
// remplace par une prise qui garde l'enregistrement, exactement comme le fait
// le shell — c'est ce qui permet d'éprouver le fichier RÉEL, et non une copie
// de laboratoire.
const enregistrement = { id: null, factory: null }
globalThis.window = {
  __ModuleLoader__: {
    load: (valeur) => {
      enregistrement.id = valeur.id
      enregistrement.factory = valeur.factory
    },
  },
}

await import(pathToFileURL(BUNDLE).href)

// React n'est pas nécessaire pour éprouver l'encodeur : le panneau n'appelle
// `React.createElement` qu'au rendu, jamais au chargement. On en fournit donc
// une version minimale — assez pour que `apply` aille jusqu'à l'enregistrement
// du slot, et pas assez pour rendre quoi que ce soit (ce que seul un navigateur
// peut faire, et c'est le rôle de l'épreuve manuelle décrite au README).
const reactMinimal = {
  createElement: () => null,
  useState: () => [null, () => {}],
  useEffect: () => {},
}
const charger = (fournir) => enregistrement.factory(fournir)
const moduleClient = charger((specifieur) => {
  if (specifieur === 'react') return reactMinimal
  throw new Error('module inattendu au chargement : ' + specifieur)
})

test('le bundle s annonce avec le nom du paquet', () => {
  const paquet = JSON.parse(readFileSync(PAQUET, 'utf8'))
  // MESURÉ : le chargeur construit la ligne du graphe avec le nom du paquet et
  // REFUSE un bundle qui enregistre un autre identifiant (« bundle loaded
  // without registering <id> »). Un `id` divergent ne casserait donc rien au
  // chargement du harness : il rendrait le panneau invisible.
  assert.equal(enregistrement.id, paquet.name)
  assert.equal(paquet.dsh.client.platform, 'web')
  assert.equal(paquet.exports['./client'], './dynamic/client.js')
  assert.equal(paquet.type, 'module', 'sans type: module, Node re-parse le module hote')
})

test('le bundle expose un plugin client complet', () => {
  assert.equal(typeof moduleClient.apply, 'function')
  assert.deepEqual(moduleClient.inject, ['slots'])
  assert.equal(typeof moduleClient.essai?.encodeQr, 'function', 'surface de test absente')
  assert.equal(typeof moduleClient.essai?.dureeLisible, 'function')
})

test('l encodeur embarque est identique a la reference figee', () => {
  // LA COPIE EST ASSUMÉE (RÈGLE #2 : un plugin est autonome), SA DÉRIVE NON.
  // On compare les deux blocs par leur TEXTE, pas par une empreinte figée.
  //
  // LA RÉFÉRENCE ÉTAIT LE FICHIER DE `share-qr`, ELLE EST MAINTENANT UNE COPIE
  // FIGÉE (`encodeur-reference.js`) : le plugin d'origine a quitté le dépôt le
  // 14 septembre 2026, et le test ne pouvait pas partir avec lui sans que plus
  // rien ne dise qu'une correction d'encodage reste d'un seul côté. La
  // comparaison garde donc son objet, et perd seulement le lien vivant : si
  // l'encodeur embarque change, ce test le dit, et la re-copie de référence
  // devient un geste délibéré au lieu d'un oubli.
  const bloc = (chemin) => {
    const lignes = readFileSync(chemin, 'utf8').split('\n')
    const debut = lignes.findIndex((ligne) => ligne.startsWith('const SPEC = {'))
    const marque = lignes.findIndex((ligne) => ligne.includes('matrix: best }'))
    assert.ok(debut > 0 && marque > debut, 'bloc encodeur introuvable dans ' + chemin)
    let fin = marque
    while (fin < lignes.length && lignes[fin] !== '}') fin++
    return lignes.slice(debut, fin + 1).join('\n')
  }
  const origine = bloc(ENCODEUR_ORIGINE)
  const copie = bloc(BUNDLE)
  assert.ok(origine.length > 2000, 'bloc de reference suspicieusement court')
  assert.equal(copie, origine, 'la copie de l encodeur a derive de la reference figee')
})

test('la matrice respecte les invariants de la norme', () => {
  const { encodeQr } = moduleClient.essai
  for (const texte of ['court', 'dshremote://mac-mini-essai.exemple.test/jeton/v1/' + 'A'.repeat(43)]) {
    const { version, mask, matrix } = encodeQr(texte)
    assert.equal(matrix.length, 4 * version + 17, 'cote = 4 x version + 17')
    assert.ok(matrix.every((rangee) => rangee.length === matrix.length), 'matrice carree')
    assert.ok(mask >= 0 && mask <= 7, 'masque hors bornes')
    // LES TROIS MOTIFS DE REPÉRAGE, aux trois coins. Ce sont eux qu'un décodeur
    // cherche en premier : sans eux, aucune image n'est un QR, quelle que soit
    // la qualité du reste.
    const motif = [
      [1, 1, 1, 1, 1, 1, 1],
      [1, 0, 0, 0, 0, 0, 1],
      [1, 0, 1, 1, 1, 0, 1],
      [1, 0, 1, 1, 1, 0, 1],
      [1, 0, 1, 1, 1, 0, 1],
      [1, 0, 0, 0, 0, 0, 1],
      [1, 1, 1, 1, 1, 1, 1],
    ]
    for (const [oy, ox] of [[0, 0], [0, matrix.length - 7], [matrix.length - 7, 0]]) {
      for (let y = 0; y < 7; y++) {
        for (let x = 0; x < 7; x++) {
          assert.equal(matrix[oy + y][ox + x], motif[y][x], 'motif de reperage altere en ' + ox + ',' + oy)
        }
      }
    }
  }
})

test('le panneau s enregistre dans le slot du pied de la barre laterale', () => {
  const enregistres = []
  const ctx = {
    slots: {
      inject: (nom, rappel) => {
        enregistres.push({ nom, fait: rappel() })
      },
      register: (options, composant) => ({ options, composant }),
    },
  }
  moduleClient.apply(ctx)
  assert.equal(enregistres.length, 1)
  assert.equal(enregistres[0].nom, 'sidebar.footer.action')
  const { options, composant } = enregistres[0].fait
  assert.equal(options.name, 'sidebar.footer.action')
  assert.equal(options.id, 'dsh-remote-appairage', 'un slot de liste exige un id')
  assert.equal(typeof composant, 'function')
})

test('sans service slots, apply se degrade au lieu de lever', () => {
  // RÈGLE #3 : une API interne qui disparaît ne doit pas produire d'exception
  // non rattrapée dans le processus du harness — ni dans la page de
  // l'utilisateur, où elle emporterait le rendu entier.
  assert.doesNotThrow(() => moduleClient.apply({}))
  assert.doesNotThrow(() => moduleClient.apply({ slots: null }))
  assert.doesNotThrow(() => moduleClient.apply({ slots: {} }))
})

test('sans React, apply se degrade au lieu de lever', () => {
  // La table de modules du shell pourrait ne pas porter React (une version qui
  // change ses graines). Le panneau est alors absent — et c'est tout : la page
  // de l'utilisateur, elle, doit continuer de fonctionner.
  const sansReact = charger(() => {
    throw new Error('react absent')
  })
  assert.equal(sansReact.essai.encodeQr !== undefined, true, 'l encodeur ne depend pas de react')
  const enregistres = []
  assert.doesNotThrow(() =>
    sansReact.apply({ slots: { inject: () => enregistres.push(1) } }),
  )
  assert.equal(enregistres.length, 0, 'sans react, rien ne doit etre enregistre')
})

test('la charge utile reelle est decodee par une implementation independante', (t) => {
  // POURQUOI CE TEST EST LE SEUL QUI COMPTE VRAIMENT ICI. Les invariants
  // ci-dessus vérifient que la matrice RESSEMBLE à un QR ; celui-ci vérifie
  // qu'un décodeur qui ne partage aucune ligne avec l'encodeur la LIT, et qu'il
  // y lit exactement la charge utile attendue.
  if (process.platform !== 'darwin') {
    t.skip('Vision est propre a macOS : decodage independant non verifie ici')
    return
  }
  const sonde = spawnSync('swift', ['--version'], { encoding: 'utf8', timeout: 60000 })
  if (sonde.error !== undefined || sonde.status !== 0) {
    t.skip('swift indisponible : decodage independant NON VERIFIE (le champ « preuve » du README doit le dire)')
    return
  }

  const charge = 'dshremote://mac-mini-essai.exemple.test/jeton/v1/' + 'JETONFICTIF-a-remplacer-0000000000000000000'
  const { matrix } = moduleClient.essai.encodeQr(charge)
  const dossier = mkdtempSync(join(tmpdir(), 'dsh-remote-qr-'))
  const image = join(dossier, 'qr.bmp')
  ecrireBmp(matrix, image)

  const decodeur = join(ICI, 'outils', 'decoder-qr.swift')
  assert.ok(existsSync(decodeur), 'decodeur independant introuvable : ' + decodeur)
  const lecture = spawnSync('swift', [decodeur, image], { encoding: 'utf8', timeout: 120000 })
  assert.equal(lecture.status, 0, 'le decodeur independant a echoue : ' + String(lecture.stderr))
  assert.equal(lecture.stdout.trim(), charge, 'la charge utile lue differe de celle encodee')
})

test('le compte a rebours du panneau se lit en clair', () => {
  // POURQUOI CE TEST. Le panneau affiche « Ce code expire dans X » : c'est la
  // phrase qui dit à l'utilisateur combien de temps son écran vaut quelque chose.
  // Une durée illisible (« 107 s ») ou un zéro affiché comme une durée
  // (« expire dans 0 s ») transformeraient un avertissement en décoration.
  const { dureeLisible } = moduleClient.essai
  assert.equal(typeof dureeLisible, 'function')
  const expire =
    typeof navigator !== 'undefined' && String(navigator.language || '').toLowerCase().startsWith('fr')
      ? 'expiré'
      : 'expired'
  assert.equal(dureeLisible(0), expire)
  assert.equal(dureeLisible(-3), expire)
  assert.equal(dureeLisible(12), '12 s')
  assert.equal(dureeLisible(59), '59 s')
  assert.equal(dureeLisible(60), '1 min 0 s')
  assert.equal(dureeLisible(107), '1 min 47 s')
  assert.equal(dureeLisible(600), '10 min 0 s')
})
