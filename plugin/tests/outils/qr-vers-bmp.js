// RENDRE UNE MATRICE DE QR EN IMAGE — outil de TEST, pas de production.
//
// POURQUOI DU BMP, ET POURQUOI ÉCRIT À LA MAIN. La preuve de conformité de
// l'encodeur est un DÉCODAGE PAR UNE IMPLÉMENTATION INDÉPENDANTE : la matrice
// produite ici est donnée à Vision (macOS), qui ne partage aucun code avec
// elle. Il faut donc une image que `CGImageSource` sache lire — et le BMP
// 24 bits NON COMPRESSÉ est le seul format qu'on puisse écrire sans dépendance
// et sans compresseur : `node:zlib` ferait un PNG, mais il faudrait alors
// écrire les morceaux, les CRC et les filtres de ligne, pour aucun gain.
//
// CE FICHIER N'EST PAS CHARGÉ PAR LE PLUGIN : il vit sous `tests/`, il n'entre
// ni dans le harness ni dans le bundle du navigateur.

import { writeFileSync } from 'node:fs'

/**
 * Convertir une matrice de modules en BMP 24 bits.
 *
 * @param {number[][]} matrice - lignes de 0/1 (1 = module noir)
 * @param {{echelle?: number, marge?: number}} options - `marge` en MODULES
 *   (4 est la zone de silence exigée par la norme : sans elle, un décodeur peut
 *   refuser un code parfaitement valide)
 * @returns {Buffer}
 */
export function matriceVersBmp(matrice, options = {}) {
  const echelle = Number.isInteger(options.echelle) && options.echelle > 0 ? options.echelle : 6
  const marge = Number.isInteger(options.marge) && options.marge >= 0 ? options.marge : 4
  const modules = matrice.length
  const cote = (modules + 2 * marge) * echelle
  // Chaque ligne d'un BMP est alignée sur 4 octets, et les lignes vont du BAS
  // vers le HAUT : deux pièges qui ne se voient qu'à l'image.
  const ligne = Math.ceil((cote * 3) / 4) * 4
  const pixels = Buffer.alloc(ligne * cote, 0xff)

  for (let my = 0; my < modules; my++) {
    for (let mx = 0; mx < modules; mx++) {
      if (matrice[my][mx] !== 1) continue
      for (let dy = 0; dy < echelle; dy++) {
        for (let dx = 0; dx < echelle; dx++) {
          const x = (mx + marge) * echelle + dx
          const y = (my + marge) * echelle + dy
          const decalage = (cote - 1 - y) * ligne + x * 3
          pixels[decalage] = 0
          pixels[decalage + 1] = 0
          pixels[decalage + 2] = 0
        }
      }
    }
  }

  const entete = Buffer.alloc(54)
  entete.write('BM', 0, 'ascii')
  entete.writeUInt32LE(54 + pixels.length, 2)
  entete.writeUInt32LE(54, 10)
  entete.writeUInt32LE(40, 14) // en-tête DIB BITMAPINFOHEADER
  entete.writeInt32LE(cote, 18)
  entete.writeInt32LE(cote, 22)
  entete.writeUInt16LE(1, 26) // plans
  entete.writeUInt16LE(24, 28) // bits par pixel
  entete.writeUInt32LE(pixels.length, 34)
  return Buffer.concat([entete, pixels])
}

/** Écrire une matrice dans un fichier BMP. */
export function ecrireBmp(matrice, chemin, options = {}) {
  writeFileSync(chemin, matriceVersBmp(matrice, options))
  return chemin
}
