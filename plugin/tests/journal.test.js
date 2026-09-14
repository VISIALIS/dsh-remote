/**
 * Les règles de LECTURE DU JOURNAL, éprouvées avec de vraies charges utiles.
 *
 * POURQUOI ELLES MÉRITENT DES TESTS. Le journal est la donnée centrale de
 * l'application : c'est lui qui porte les événements d'une session, et son
 * décodage est tout sauf évident — les écritures sont CONCATÉNÉES, chacune dans
 * sa propre trame zstd, et `zstdDecompressSync` n'en décode qu'une en s'arrêtant
 * silencieusement. Une erreur ici ne lève pas : elle rend un journal TRONQUÉ, et
 * l'utilisateur croit avoir tout lu.
 *
 * LANCEMENT : `node --test plugins/dsh-remote/tests/*.test.js`.
 *
 * PAS DE DOSSIER EN ARGUMENT : `node --test <dossier>` est REFUSÉ par Node
 * 22.19 (`Cannot find module …/tests`) alors qu'il est accepté par 20.19 et
 * 26.8.2 — et 22.19 est le Node sous lequel tourne le harnais ici. Des fichiers
 * explicites marchent sur les trois.
 */

import assert from 'node:assert/strict'
import { mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import zlib from 'node:zlib'

import {
  analyserLigne,
  cheminIndicatif,
  decoderJournal,
  longueurDeTrame,
  resumer,
  trouverJournal,
} from '../dynamic/journal.js'

/** Ce que DSH écrit : une trame zstd par écriture, concaténées. */
function journal(...ecritures) {
  return Buffer.concat(ecritures.map((texte) => zlib.zstdCompressSync(Buffer.from(texte, 'utf8'))))
}

test('un journal est une CONCATÉNATION de trames : toutes doivent être lues', () => {
  const tampon = journal(
    '{"type":"session","id":"abc"}\n',
    '{"type":"message","seq":1}\n',
    '{"type":"message","seq":2}\n',
  )

  const { lignes, tronque } = decoderJournal(tampon)

  // C'est LE piège mesuré : `zstdDecompressSync` seul n'aurait rendu que la
  // première écriture, sans rien dire. Un journal tronqué en silence est pire
  // qu'une erreur.
  assert.deepEqual(lignes, [
    '{"type":"session","id":"abc"}',
    '{"type":"message","seq":1}',
    '{"type":"message","seq":2}',
  ])
  assert.equal(tronque, false)
})

test('la fin d’une trame se lit dans sa STRUCTURE, pas en la décompressant', () => {
  const trame = zlib.zstdCompressSync(Buffer.from('{"type":"a"}\n', 'utf8'))
  assert.equal(longueurDeTrame(trame, 0), trame.length)

  // 300 Kio ne tiennent pas dans un bloc zstd (128 Kio au plus) : la lecture
  // doit avancer de bloc en bloc, pas s'arrêter au premier.
  const grosse = zlib.zstdCompressSync(Buffer.alloc(300 * 1024, 0x61))
  assert.equal(longueurDeTrame(grosse, 0), grosse.length)

  // Un octet de moins : ce n'est plus une trame complète. C'est LE cas qui
  // décidait de tout — sur Node 22.19, `zstdDecompressSync` rend une tranche
  // tronquée SANS LEVER (mesuré : 1 octet → chaîne vide, 90 % d'une trame de
  // 200 Kio → 131 072 octets rendus). La structure, elle, ne se laisse pas
  // convaincre : la taille annoncée dépasse ce qui est présent.
  assert.equal(longueurDeTrame(trame.subarray(0, trame.length - 1), 0), null)
  // Coupée juste après la magie : rien à lire, et rien à lever.
  assert.equal(longueurDeTrame(trame.subarray(0, 4), 0), null)
})

test('une trame TRONQUÉE en fin de journal n’efface pas ce qui précède', () => {
  const complet = journal('{"type":"a"}\n', '{"type":"b"}\n')
  const entiere = zlib.zstdCompressSync(Buffer.from('{"type":"c"}\n', 'utf8'))
  const tampon = Buffer.concat([complet, entiere.subarray(0, entiere.length - 2)])

  const { lignes, offset, tronque } = decoderJournal(tampon)

  // C'est la panne mesurée : la recherche par essais rendait ZÉRO ligne pour
  // tout le journal, y compris les trames complètes qui le précédaient.
  assert.deepEqual(lignes, ['{"type":"a"}', '{"type":"b"}'])
  assert.equal(tronque, true)
  // `offset` dit où reprendre : au DÉBUT de la trame incomplète, pour que rien
  // ne soit sauté quand l'écriture en cours sera terminée.
  assert.equal(offset, complet.length)
})

test('une trame « à ignorer » est SAUTÉE, pas prise pour du contenu', () => {
  // La spécification zstd réserve la plage 0x184D2A50-5F à des trames dont la
  // charge ne veut rien dire pour le décodeur. DSH n'en écrit pas aujourd'hui ;
  // les fabriquer à la main est la seule façon d'éprouver qu'on les saute
  // (magie de 4 octets, taille de charge sur 4 octets, puis la charge).
  const charge = Buffer.from('a ignorer', 'utf8')
  const taille = Buffer.alloc(4)
  taille.writeUInt32LE(charge.length, 0)
  const ignorable = Buffer.concat([Buffer.from([0x50, 0x2a, 0x4d, 0x18]), taille, charge])

  const tampon = Buffer.concat([journal('{"type":"avant"}\n'), ignorable, journal('{"type":"apres"}\n')])
  const { lignes, offset, tronque } = decoderJournal(tampon)

  assert.deepEqual(lignes, ['{"type":"avant"}', '{"type":"apres"}'])
  assert.equal(tronque, false)
  assert.equal(offset, tampon.length)
})

test('un en-tête de trame ABÎMÉ arrête la lecture sans lever', () => {
  // Bits réservés du descripteur : du zstd invalide. Le journal rend ce qu'il a
  // lu avant, et dit qu'il s'est arrêté — il ne lève jamais dans le processus du
  // harnais, où une exception non rattrapée coûte la route entière.
  const abime = Buffer.from([0x28, 0xb5, 0x2f, 0xfd, 0xff, 0x00, 0x00])
  const tampon = Buffer.concat([journal('{"type":"lisible"}\n'), abime])

  const { lignes, offset, tronque } = decoderJournal(tampon)

  assert.deepEqual(lignes, ['{"type":"lisible"}'])
  assert.equal(tronque, true)
  assert.equal(offset, tampon.length - abime.length)
})

test('une ligne illisible est IGNORÉE, pas fatale', () => {
  // Une écriture interrompue (le harness tué en plein vol) laisse une ligne
  // incomplète à la fin d'une trame. Refuser tout le journal pour autant
  // priverait l'utilisateur de ce qui est lisible.
  assert.equal(analyserLigne('{"type":"message"}')?.type, 'message')
  assert.equal(analyserLigne('{"incomplet":'), null)
  assert.equal(analyserLigne(''), null)
  assert.equal(analyserLigne('42'), null, 'un nombre n’est pas un enregistrement')
  assert.equal(analyserLigne('null'), null)
})

test('le résumé prend le PREMIER en-tête, le DERNIER titre, et le plus grand `seq`', () => {
  const enregistrements = [
    { type: 'session', id: 'abc', cwd: '/tmp/projet', createdAt: 1000, agentPreset: 'defaut' },
    { type: 'session/title', data: { title: 'Premier titre' } },
    { type: 'message', seq: 3, time: 2000 },
    { type: 'session/title', data: { title: 'Titre courant' } },
    { type: 'message', seq: 7, time: 3000 },
  ]

  const resume = resumer(enregistrements)

  assert.equal(resume.id, 'abc')
  assert.equal(resume.cwd, '/tmp/projet')
  assert.equal(resume.creeLe, 1000)
  assert.equal(resume.preset, 'defaut')
  // Le DERNIER titre gagne : c'est celui que l'utilisateur voit dans l'interface
  // web, et un titre change en cours de session.
  assert.equal(resume.titre, 'Titre courant')
  assert.equal(resume.dernierSeq, 7)
  assert.equal(resume.dernierEvenementLe, 3000)
  assert.equal(resume.nbEnregistrements, 5)
})

test('un en-tête absent ne fait pas lever le résumé — il rend des champs nuls', () => {
  const resume = resumer([{ type: 'message', seq: 1 }])
  assert.equal(resume.id, null)
  assert.equal(resume.cwd, null)
  assert.equal(resume.creeLe, null)
  assert.equal(resume.titre, null)
  // Un journal sans en-tête (tronqué, ou écrit par une version antérieure) doit
  // rester lisible : l'application affiche « (inconnu) », elle ne plante pas.
  assert.equal(resume.dernierSeq, 1)
})

test('le chemin indicatif est INDICATIF : il ne distingue pas un tiret d’un séparateur', () => {
  // DSH nomme les dossiers de projet en remplaçant `/` par `-`, encadrés de `--`.
  assert.equal(cheminIndicatif('--tmp--'), '/tmp')
  // Sans les tirets d'encadrement, on ne les invente pas.
  assert.equal(cheminIndicatif('tmp'), '/tmp')

  // LE PIÈGE, ÉPINGLÉ ICI POUR QU'ON NE LE « RÉPARE » PAS À TORT : un tiret DANS
  // un nom de dossier devient un séparateur, et c'est irréversible —
  // `dsh-plugins` se relit `dsh/plugins`. C'est la raison pour laquelle ce champ
  // ne sert JAMAIS à lire quoi que ce soit : `cwd`, conservé en clair par DSH
  // dans l'enregistrement d'en-tête, fait foi. Le champ n'existe que pour donner
  // un libellé à un client qui n'a pas encore lu le journal.
  // LA RACINE EST NEUTRE, ET CE N'EST PAS UN HASARD : `check-secrets.sh` refuse
  // tout chemin absolu `/Users/…`, même fictif (RÈGLE #0 — un chemin réel fuit un
  // nom de compte). La règle éprouvée est la même sous `/srv`.
  assert.equal(cheminIndicatif('--srv-projets-dsh-plugins--'), '/srv/projets/dsh/plugins')
})

test('les DEUX noms de journal sont essayés — 39 sessions en dépendaient', async () => {
  // MESURÉ : sur cette machine, 118 sessions ont un journal `session.v3.jsonl.zstd`
  // et 39 un journal `session.jsonl.zstd`. Le plugin ne cherchait QUE le premier
  // nom : les 39 autres n'existaient pas pour l'application, alors que leur
  // journal se décode parfaitement.
  const dossier = await mkdtemp(join(tmpdir(), 'essai-journal-'))
  try {
    // Aucun des deux : rien, et surtout pas une exception.
    assert.equal(await trouverJournal(dossier), null)

    // Le nom historique seul est trouvé.
    await writeFile(join(dossier, 'session.jsonl.zstd'), 'peu importe')
    assert.equal(await trouverJournal(dossier), join(dossier, 'session.jsonl.zstd'))

    // Et quand LES DEUX existent, c'est le v3 qui fait foi — c'est le nom
    // courant, celui que DSH écrit aujourd'hui.
    await writeFile(join(dossier, 'session.v3.jsonl.zstd'), 'peu importe')
    assert.equal(await trouverJournal(dossier), join(dossier, 'session.v3.jsonl.zstd'))
  } finally {
    await rm(dossier, { recursive: true, force: true })
  }
})
