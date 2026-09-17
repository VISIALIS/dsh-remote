/**
 * LE CACHE DES FAITS D'UNE SESSION — ce qu'un journal déjà lu a appris.
 *
 * POURQUOI CE FICHIER EXISTE. `listerSessions` relit l'arbre des journaux à chaque
 * appel — c'est ce qui rend la liste des sessions vivante, et c'est aussi ce qui la
 * rendrait intenable : 172 sessions, un `readdir` et un `stat` par session, toutes
 * les trois secondes. Un journal est APPEND-ONLY, donc `(taille, mtime)` identiques
 * désignent le même contenu, et les faits résolus sont réutilisables tels quels.
 *
 * POURQUOI PAS UN SIMPLE `Map` SANS BORNE. Deux raisons, et la seconde est une
 * mesure : le nombre d'entrées est borné par éviction, et une entrée non revue
 * depuis longtemps est OUBLIÉE. Sans cela, un harness qui vit des jours garderait
 * les faits d'un millier de sessions oubliées, et la mémoire du processus — qui
 * n'a pas de bac à sable, donc pas de plafond — croîtrait sans fin.
 *
 * LA VALIDITÉ SE LIT SUR LE FICHIER, JAMAIS SUR L'HORLOGE. Une entrée est bonne si
 * `taille` ET `mtime` n'ont pas bougé — pas si elle est « récente ». Une session
 * qu'on n'a pas touchée depuis une heure est parfaitement valide ; une session qui
 * vient d'écrire deux fois dans la même milliseconde ne l'est plus, et c'est
 * `mtime` (avec la taille) qui le dit.
 */

/** Durée au-delà de laquelle une entrée non revue est oubliée. */
export const PEREMPTION_MS = 5 * 60 * 1000

/** Intervalle minimal entre deux balayages — un balayage par `get` coûterait plus cher que le cache. */
export const INTERVALLE_BALAYAGE_MS = 60 * 1000

/** Nombre maximal d'entrées gardées. */
export const ENTREES_MAX = 400

/**
 * @param {{maintenant?: () => number, peremptionMs?: number, intervalleBalayageMs?: number, entreesMax?: number}} [reglages]
 * @returns {{lire: (cle: string, marqueurs: {taille: number, mtime: number}) => object | undefined, poser: (cle: string, marqueurs: {taille: number, mtime: number}, faits: object) => void, vider: () => void, taille: () => number}}
 */
export function creerCacheDeFaits({
  maintenant = Date.now,
  peremptionMs = PEREMPTION_MS,
  intervalleBalayageMs = INTERVALLE_BALAYAGE_MS,
  entreesMax = ENTREES_MAX,
} = {}) {
  const entrees = new Map()
  let dernierBalayage = 0

  const balayer = (instant) => {
    if (instant - dernierBalayage < intervalleBalayageMs) return
    dernierBalayage = instant
    for (const [cle, entree] of entrees) {
      if (instant - entree.vuLe > peremptionMs) entrees.delete(cle)
    }
  }

  return {
    /**
     * Les faits d'une session, si le fichier n'a pas bougé depuis la dernière lecture.
     *
     * Rend `undefined` — et non `null` — pour que l'appelant distingue « rien en
     * cache » de « faits vides mis en cache » avec un simple `!== undefined`.
     */
    lire(cle, { taille, mtime }) {
      const instant = maintenant()
      // ON BALAIE AVANT DE SERVIR, et non après : une entrée périmée ne doit pas
      // être rendue une dernière fois « puisqu'elle est là ». Le balayage respecte
      // son propre intervalle, donc il ne coûte rien à chaque lecture.
      balayer(instant)
      const entree = entrees.get(cle)
      if (entree === undefined) return undefined
      if (entree.taille !== taille || entree.mtime !== mtime) return undefined
      // UNE ENTRÉE RELUE REMONTE EN TÊTE : c'est ce qui fait de l'éviction un LRU,
      // et non un « premier entré, premier sorti ». Sans ce déplacement, la session
      // la plus ACTIVE serait évincée avant une session oubliée.
      entrees.delete(cle)
      entree.vuLe = instant
      entrees.set(cle, entree)
      return entree.faits
    },

    poser(cle, { taille, mtime }, faits) {
      const instant = maintenant()
      // ON RETIRE PUIS ON REPOSE : une `Map` conserve l'ordre d'insertion, et une
      // entrée RELUE doit redevenir la plus récente — sinon l'éviction emporterait
      // celle qu'on vient d'utiliser, et le cache oublierait la session la plus
      // active au lieu de la plus ancienne.
      entrees.delete(cle)
      entrees.set(cle, { taille, mtime, faits, vuLe: instant })
      while (entrees.size > entreesMax) {
        entrees.delete(entrees.keys().next().value)
      }
      balayer(instant)
    },

    vider() {
      entrees.clear()
      dernierBalayage = 0
    },

    /** Le nombre d'entrées gardées — pour les tests, et pour une trace de diagnostic. */
    taille() {
      return entrees.size
    },
  }
}
