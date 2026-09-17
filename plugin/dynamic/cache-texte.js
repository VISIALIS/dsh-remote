/**
 * LE CACHE DE TEXTE DES JOURNAUX — et pourquoi il garde du TEXTE.
 *
 * POURQUOI CE FICHIER EXISTE. `lireSession` relit et redécompresse le journal
 * ENTIER à chaque page, et le client en demande une à l'ouverture puis une autre
 * aussitôt après (l'en-tête, puis les enregistrements) : les mêmes 37 000
 * enregistrements étaient décompressés deux fois de suite. Mesuré sur un journal
 * de 3 Mio compressés : **235 ms** pour la première page, **41 ms** pour la
 * seconde avec le cache — le reste étant l'analyse JSON, qu'on ne peut pas éviter.
 *
 * C'est aussi la raison pour laquelle il vit HORS de `host.js` : un cache qu'on ne
 * peut éprouver qu'en montant un harness entier n'est pas éprouvé. Ici, il reçoit
 * ses deux dépendances (lire, décoder), donc un test lui donne un compteur et
 * vérifie qu'une lecture disque a bien été ÉVITÉE — la seule mesure qui ne puisse
 * pas passer pour ce qu'elle n'est pas.
 *
 * POURQUOI DU TEXTE, ET PAS DES OBJETS — C'EST UNE MESURE, PAS UN GOÛT. Sur le
 * plus gros journal de cette installation (9,7 Mio compressés, 37 989
 * enregistrements), le tas de Node croît de **84 Mio** quand on matérialise les
 * objets analysés, soit **8,7 fois le fichier** — et la décompression seule en
 * explique déjà 42 Mio. Garder les objets ferait donc payer 84 Mio de mémoire du
 * harness par journal chaud, pour épargner une analyse JSON qui coûte quelques
 * millisecondes. On garde les LIGNES, et on les réanalyse à chaque appel.
 *
 * LA CLÉ DE VALIDITÉ EST `(taille, mtime)` : un journal est append-only, donc une
 * taille et une date identiques désignent le même contenu. Toute autre combinaison
 * redécode et REMPLACE l'entrée — une session qui écrit beaucoup ne fait pas
 * coexister deux versions de son journal.
 *
 * LES DEUX BORNES SONT NÉCESSAIRES : le nombre d'entrées évince la plus ancienne
 * (LRU), et le total en octets empêche trois journaux énormes de tenir 180 Mio
 * pour rien.
 */

/** Nombre de journaux gardés au maximum. */
export const ENTREES_MAX = 8

/** Total de texte décompressé gardé au maximum, en octets. */
export const OCTETS_MAX = 48 * 1024 * 1024

/**
 * @param {object} dependances
 * @param {(fichier: string) => Promise<Buffer>} dependances.lire
 * @param {(tampon: Buffer) => {lignes: string[], tronque: boolean}} dependances.decoder
 * @param {number} [dependances.entreesMax]
 * @param {number} [dependances.octetsMax]
 */
export function creerCacheTexte({ lire, decoder, entreesMax = ENTREES_MAX, octetsMax = OCTETS_MAX }) {
  /** @type {Map<string, {taille: number, mtime: number, lignes: string[], tronque: boolean, octets: number}>} */
  const entrees = new Map()
  let octets = 0

  const retirer = (cle) => {
    const entree = entrees.get(cle)
    if (entree === undefined) return
    octets -= entree.octets
    entrees.delete(cle)
  }

  return {
    /**
     * Le journal décompressé, servi depuis le cache quand rien n'a bougé.
     *
     * @param {string} fichier
     * @param {{size: number, mtimeMs: number}} information - `stat` du fichier
     * @returns {Promise<{lignes: string[], tronque: boolean, cache: boolean}>}
     */
    async lignes(fichier, information) {
      const connu = entrees.get(fichier)
      if (connu !== undefined && connu.taille === information.size && connu.mtime === information.mtimeMs) {
        // LRU : une entrée qu'on vient de servir repasse en fin d'ordre, donc une
        // session qu'on regarde ne se fait pas évincer par une qu'on a survolée.
        entrees.delete(fichier)
        entrees.set(fichier, connu)
        return { lignes: connu.lignes, tronque: connu.tronque, cache: true }
      }
      const tampon = await lire(fichier)
      const { lignes, tronque } = decoder(tampon)
      const taille = lignes.reduce((total, ligne) => total + ligne.length, 0)
      // Un journal plus gros que le plafond TOTAL n'entre pas : le garder ferait
      // payer sa taille entière pour un seul usage, et évincerait tout le reste.
      if (taille <= octetsMax) {
        retirer(fichier)
        entrees.set(fichier, { taille: information.size, mtime: information.mtimeMs, lignes, tronque, octets: taille })
        octets += taille
        while (entrees.size > entreesMax || octets > octetsMax) {
          retirer(entrees.keys().next().value)
        }
      }
      return { lignes, tronque, cache: false }
    },

    /** Vide le cache — au retrait des routes, pour ne rien garder d'un plugin démonté. */
    vider() {
      entrees.clear()
      octets = 0
    },

    /** Ce que le cache tient, pour l'observer (tests, et un jour un diagnostic). */
    etat() {
      return { entrees: entrees.size, octets }
    },
  }
}
