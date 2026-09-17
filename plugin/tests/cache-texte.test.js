/**
 * LE CACHE DE TEXTE DES JOURNAUX, éprouvé SEUL.
 *
 * POURQUOI CE FICHIER DE TEST EXISTE, ET CE QU'IL A COÛTÉ DE NE PAS L'AVOIR. Ce
 * cache vivait en ligne dans `host.js`, à l'intérieur de `apply`, donc invisible
 * depuis un test : la seule façon de vérifier qu'une lecture disque était évitée
 * aurait été de monter un harness entier. Deux tentatives ont échoué avant
 * l'extraction — `mock.method` ne peut pas redéfinir `readFile` d'un module natif
 * (« Cannot redefine property »), et `mock.module` exige un drapeau Node que le
 * lanceur de tests n'accepte pas. Un test impossible à écrire est un signal : la
 * pièce était mal découpée.
 *
 * CE QU'ON VÉRIFIE ICI : qu'une lecture disque est ÉVITÉE — la seule mesure qui ne
 * puisse pas passer pour ce qu'elle n'est pas. Un compteur, pas un chronomètre.
 *
 * LANCEMENT : `node --test plugins/dsh-remote/tests/*.test.js`.
 */

import assert from 'node:assert/strict'
import { test } from 'node:test'

import { creerCacheTexte, ENTREES_MAX, OCTETS_MAX } from '../dynamic/cache-texte.js'

/** Un décodeur factice : le « journal » est un texte, une ligne par écriture. */
const decoderFactice = (tampon) => ({
  lignes: tampon.toString('utf8').split('\n').filter((ligne) => ligne.length > 0),
  tronque: false,
})

/** Une source de journal qui COMPTE ses lectures — c'est la mesure du test. */
function sourceFactice(contenu = 'a\nb\nc\n') {
  const source = { lectures: 0, contenu, taille: contenu.length, mtime: 1000 }
  source.lecture = async () => {
    source.lectures += 1
    return Buffer.from(source.contenu, 'utf8')
  }
  source.information = () => ({ size: source.taille, mtimeMs: source.mtime })
  /** Une écriture de journal : le contenu grandit, et la date change. */
  source.ecrire = (ligne) => {
    source.contenu += ligne + '\n'
    source.taille = source.contenu.length
    source.mtime += 1
  }
  return source
}

test('deux lectures du meme fichier ne lisent le disque QU UNE fois', async () => {
  const source = sourceFactice()
  const cache = creerCacheTexte({ lire: source.lecture, decoder: decoderFactice })

  const premier = await cache.lignes('/tmp/journal', source.information())
  const second = await cache.lignes('/tmp/journal', source.information())

  assert.equal(source.lectures, 1, 'la seconde lecture doit venir du cache')
  assert.deepEqual(second.lignes, premier.lignes)
  assert.equal(premier.cache, false, 'la premiere lecture decode')
  assert.equal(second.cache, true, 'la seconde est servie par le cache')
})

test('une ECRITURE invalide le cache : taille ou date differente', async () => {
  const source = sourceFactice()
  const cache = creerCacheTexte({ lire: source.lecture, decoder: decoderFactice })
  await cache.lignes('/tmp/journal', source.information())
  assert.equal(source.lectures, 1)

  source.ecrire('d')

  const apres = await cache.lignes('/tmp/journal', source.information())
  assert.equal(source.lectures, 2, 'le journal a change : il doit etre relu')
  assert.equal(apres.cache, false)
  assert.deepEqual(apres.lignes, ['a', 'b', 'c', 'd'], 'et la nouvelle ecriture doit y etre')

  // Et la relecture SUIVANTE est de nouveau servie par le cache : on n'a pas
  // seulement invalide, on a remplace.
  await cache.lignes('/tmp/journal', source.information())
  assert.equal(source.lectures, 2)
})

test('une taille identique mais une DATE differente suffit a invalider', async () => {
  // LE CAS QUI COMPTE : un journal peut grandir ET sa taille revenir identique
  // apres une rotation, ou une ecriture remplacer une autre. La date seule
  // distingue alors les deux contenus — et se fier a la taille servirait un
  // journal qui n'existe plus.
  const source = sourceFactice()
  const cache = creerCacheTexte({ lire: source.lecture, decoder: decoderFactice })
  await cache.lignes('/tmp/journal', source.information())

  source.mtime += 5

  await cache.lignes('/tmp/journal', source.information())
  assert.equal(source.lectures, 2, 'meme taille, autre date : relire')
})

test('le cache est BORNE par le nombre d entrees, et evince la plus ancienne', async () => {
  const source = sourceFactice()
  const cache = creerCacheTexte({ lire: source.lecture, decoder: decoderFactice })

  // On remplit au-dela du plafond : la premiere entree doit avoir disparu.
  for (let index = 0; index <= ENTREES_MAX; index++) {
    await cache.lignes('/tmp/journal-' + index, source.information())
  }
  assert.equal(cache.etat().entrees, ENTREES_MAX, 'le nombre d entrees est borne')

  const avant = source.lectures
  await cache.lignes('/tmp/journal-0', source.information())
  assert.equal(source.lectures, avant + 1, 'la plus ancienne a ete evincee, donc relue')
  await cache.lignes('/tmp/journal-' + ENTREES_MAX, source.information())
  assert.equal(source.lectures, avant + 1, 'la plus recente est toujours en cache')
})

test('le cache est BORNE par les octets, et n entre pas au-dela du plafond', async () => {
  // Un journal plus gros que le plafond TOTAL ne doit pas entrer du tout : le
  // garder ferait payer sa taille entiere pour un seul usage.
  const enorme = 'x'.repeat(64)
  const source = sourceFactice(enorme + '\n')
  const cache = creerCacheTexte({
    lire: source.lecture,
    decoder: decoderFactice,
    entreesMax: 8,
    octetsMax: 32,
  })

  await cache.lignes('/tmp/journal', source.information())
  assert.equal(cache.etat().entrees, 0, 'trop gros pour le plafond : rien n est garde')
  assert.equal(cache.etat().octets, 0)

  await cache.lignes('/tmp/journal', source.information())
  assert.equal(source.lectures, 2, 'et il est donc relu a chaque fois — sans erreur')
})

test('le total d octets evince jusqu a rentrer dans le plafond', async () => {
  // Chaque journal pese 8 octets de texte ; le plafond en admet quatre.
  const source = sourceFactice('aa\nbb\ncc\ndd\n')
  const cache = creerCacheTexte({ lire: source.lecture, decoder: decoderFactice, entreesMax: 8, octetsMax: 20 })

  for (let index = 0; index < 4; index++) await cache.lignes('/tmp/journal-' + index, source.information())

  assert.ok(cache.etat().octets <= 20, 'le total doit rester sous le plafond : ' + cache.etat().octets)
  assert.ok(cache.etat().entrees < 4, 'et donc des entrees ont ete evincees')
})

test('la plus ancienne est evincee AVANT celle qu on vient de servir', async () => {
  // LE LRU, ET POURQUOI IL COMPTE ICI : l'application survole la liste (chaque
  // journal est lu une fois) puis OUVRE une session. Sans LRU, l'ouverture
  // evincerait precisement le journal qu'on est en train de lire.
  const source = sourceFactice()
  const cache = creerCacheTexte({ lire: source.lecture, decoder: decoderFactice, entreesMax: 2, octetsMax: OCTETS_MAX })

  await cache.lignes('/tmp/journal-a', source.information())
  await cache.lignes('/tmp/journal-b', source.information())
  // On re-sert A : il redevient le plus RECENT.
  await cache.lignes('/tmp/journal-a', source.information())
  // Puis on ajoute C : c'est B qui doit partir, pas A.
  await cache.lignes('/tmp/journal-c', source.information())

  const avant = source.lectures
  await cache.lignes('/tmp/journal-a', source.information())
  assert.equal(source.lectures, avant, 'A vient d etre servi : il doit etre encore la')
  await cache.lignes('/tmp/journal-b', source.information())
  assert.equal(source.lectures, avant + 1, 'B etait le plus ancien : il est parti')
})

test('vider ne laisse RIEN derriere soi', async () => {
  const source = sourceFactice()
  const cache = creerCacheTexte({ lire: source.lecture, decoder: decoderFactice })
  await cache.lignes('/tmp/journal', source.information())

  cache.vider()

  assert.deepEqual(cache.etat(), { entrees: 0, octets: 0 })
  await cache.lignes('/tmp/journal', source.information())
  assert.equal(source.lectures, 2, 'apres un vidage, on relit')
})
