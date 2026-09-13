/**
 * LA MOITIÉ PLUGIN DU CONTRAT APP ↔ PLUGIN.
 *
 * POURQUOI CE FICHIER EXISTE. Les formes JSON sont déclarées DEUX FOIS : le
 * plugin les produit, l'application Swift les décode. Rien ne vérifiait qu'elles
 * s'accordent — et elles ont divergé : le résumé d'une session est ÉTALÉ dans
 * l'objet (pas imbriqué sous `resume`), ce qu'un test Swift avait supposé de
 * travers en lisant « (inconnu) » là où il attendait un identifiant.
 *
 * Le contrat tient donc en DEUX MOITIÉS, et il faut les deux :
 *
 *   - ici : le plugin PRODUIT exactement les clés du fixture versionné ;
 *   - `packages/dsh-remote-swift/…/ContratHoteTests.swift` : l'application les
 *     DÉCODE.
 *
 * Une dérive d'un côté casse un test de l'autre, sans qu'il faille faire tourner
 * les deux langages en même temps.
 *
 * LANCEMENT : `node --test plugins/dsh-remote/tests/`.
 */

import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'

import { VERSION_PROTOCOLE } from '../dynamic/host.js'
import { entreeDeSession, resumer } from '../dynamic/journal.js'

const fixture = JSON.parse(
  readFileSync(
    new URL('../../../packages/dsh-remote-swift/Tests/DSHRemoteKitTests/Fixtures/sessions-hote.json', import.meta.url),
    'utf8',
  ),
)

/** Le même genre de faits que ceux lus dans un journal, pour l'entrée produite. */
function faits() {
  // LA ROUTE AJOUTE `tronque` APRÈS `resumer` : le résumé ne le connaît pas, et
  // c'est le décodage du journal qui le rend. L'oublier ici faisait diverger le
  // test du plugin — ce qui est exactement son travail.
  const resume = resumer([
    {
      type: 'session',
      id: '2026-09-13T08-12-44-abc',
      cwd: '/srv/projets/dsh-plugins',
      createdAt: 1789000000000,
      agentPreset: 'danger-full-access',
      delegationDepth: 0,
      isSeeded: false,
    },
    { type: 'session/title', data: { title: 'Reprise de la découverte des serveurs' } },
    { type: 'message', seq: 412, time: 1789000300000 },
  ])
  resume.tronque = false
  return resume
}

test('la version du protocole du plugin est celle du fixture', () => {
  // Si le plugin change de protocole, le client doit le savoir : c'est le
  // premier champ que la route envoie, et le premier que le client lit.
  assert.equal(VERSION_PROTOCOLE, fixture.protocole)
})

test('la réponse de liste porte EXACTEMENT ces trois clés', () => {
  assert.deepEqual(Object.keys(fixture).sort(), ['protocole', 'sessions', 'total'])
})

test('le plugin produit EXACTEMENT les clés que le client décode', () => {
  const entree = entreeDeSession({
    projet: '--srv-projets-dsh-plugins--',
    dossier: '/srv/projets/dsh-plugins/--srv-projets-dsh-plugins--/2026-09-13T08-12-44-abc',
    fichier:
      '/srv/projets/dsh-plugins/--srv-projets-dsh-plugins--/2026-09-13T08-12-44-abc/session.v3.jsonl.zstd',
    octets: 40960,
    modifieLe: 1789000000000,
    vivante: true,
    statut: 'running',
    attendReponse: false,
    faits: faits(),
  })

  const produites = Object.keys(entree).sort()
  const attendues = Object.keys(fixture.sessions[0]).sort()

  assert.deepEqual(
    produites,
    attendues,
    'le plugin et le fixture divergent — le client Swift lit ces clés-là',
  )
  // Et les VALEURS du fixture correspondent à ce que la mise en forme produit :
  // un fixture périmé ne protégerait rien.
  assert.equal(entree.id, fixture.sessions[0].id)
  assert.equal(entree.titre, fixture.sessions[0].titre)
  assert.equal(entree.cwdIndicatif, fixture.sessions[0].cwdIndicatif)
  assert.equal(entree.dernierSeq, fixture.sessions[0].dernierSeq)
})

test('une session ILLISIBLE ajoute sa raison, sans changer le reste', () => {
  // Le chemin d'erreur du listage remplace les faits du journal par une raison.
  // Le client doit pouvoir compter sur les mêmes clés, PLUS cette raison — sinon
  // une session illisible ferait disparaître la ligne au lieu de l'expliquer.
  const entree = entreeDeSession({
    projet: '--srv-projets-phoenix-0--',
    dossier: '/srv/projets/phoenix-0/--srv-projets-phoenix-0--/2026-09-12T21-04-02-def',
    fichier:
      '/srv/projets/phoenix-0/--srv-projets-phoenix-0--/2026-09-12T21-04-02-def/session.v3.jsonl.zstd',
    octets: 8192,
    modifieLe: 1788900000000,
    vivante: false,
    statut: null,
    attendReponse: true,
    faits: { illisible: 'journal trop volumineux (536870912 octets)' },
  })

  const attendues = Object.keys(fixture.sessions[1]).sort()
  assert.deepEqual(Object.keys(entree).sort(), attendues)
  assert.equal(entree.illisible, fixture.sessions[1].illisible)
})
