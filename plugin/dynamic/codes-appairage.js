/**
 * LA MÉMOIRE DES CODES D'APPAIRAGE — la moitié CÔTÉ HÔTE du contrat d'appairage.
 *
 * POURQUOI CE FICHIER EXISTE. Les codes vivaient dans trois variables de `host.js`
 * (`codes`, `frappes`, `echanges`) que six lignes de route manipulaient à la main,
 * chacune avec sa subtilité : les codes périmés sont retirés AVANT le plafond, la
 * consommation d'un code est IMMÉDIATE (avant toute écriture dans le coffre), et un
 * code expiré reste BRÛLÉ. Ces règles décident si un code à usage unique peut
 * servir deux fois — donc elles méritent d'être écrites à un seul endroit, et
 * éprouvées sans monter un serveur.
 *
 * CE QU'UN CODE EST, ET CE QU'IL N'EST PAS. Seize octets tirés au hasard (128 bits),
 * donc indevinables : **les plafonds ci-dessous ne protègent PAS du devinage**, et
 * prétendre le contraire serait un mensonge écrit dans le code. Ils bornent autre
 * chose — un script qui martèle la route, ou un panneau qui boucle. ET ILS SONT
 * GLOBAUX, PAS PAR ADRESSE : derrière `tailscale serve`, `socket.remoteAddress` vaut
 * toujours `127.0.0.1` et l'en-tête d'identité tailnet est falsifiable — un plafond
 * « par IP » serait un plafond par personne, c'est-à-dire une illusion de contrôle.
 *
 * LES CODES VIVENT EN MÉMOIRE SEULEMENT, ET C'EST DÉLIBÉRÉ : un code qui survit à un
 * redémarrage serait un code qu'on aurait oublié, alors qu'il donne un jeton.
 */

import { randomBytes } from 'node:crypto'

/** Durée de vie par défaut d'un code : deux minutes, le temps d'un scan. */
export const TTL_CODE_MS = 2 * 60 * 1000

/**
 * Nombre de codes VIVANTS gardés.
 *
 * POURQUOI HUIT. Un code se consomme en quelques secondes ; en garder davantage
 * n'élargirait pas la fenêtre d'attaque (elle est bornée par le TTL) mais ferait
 * vivre en mémoire des codes oubliés. Huit couvrent le cas réel — plusieurs
 * appareils appairés d'affilée — sans accumulation.
 */
export const CODES_VIVANTS_MAX = 8

/** Bornes de la durée de vie, réglable par le profil. */
export const TTL_CODE_MIN_MS = 1000
export const TTL_CODE_MAX_MS = 15 * 60 * 1000

/** Fenêtre des plafonds glissants : une minute. */
export const FENETRE_MS = 60 * 1000

/** Frappes de code tolérées par fenêtre. */
export const FRAPPES_MAX = 30

/** Échanges tolérés par fenêtre. */
export const ECHANGES_MAX = 30

// LES DEUX PLAFONDS SONT COUPLÉS, ET LE SECOND NE PROTÈGE RIEN DE PLUS. Un échange
// exige un code frappé, et les deux compteurs valent 30 sur la même fenêtre : la 31e
// frappe est donc refusée avant que la 31e dépense ne puisse avoir lieu. C'est une
// SECONDE SERRURE SUR LA MÊME PORTE, écrit ici pour que personne ne la lise comme un
// contrôle indépendant — pour qu'elle en soit un, il faudrait `FRAPPES_MAX` plus
// grand que `ECHANGES_MAX`.

/**
 * Borne la durée de vie demandée par le profil.
 *
 * POURQUOI ELLE EST ICI, ET EXPORTÉE. La valeur vient d'un fichier que l'exploitant
 * édite à la main : une valeur absurde ne doit ni rendre l'appairage impossible
 * (trop court) ni rouvrir la fenêtre de l'étape A (trop long) — et c'est une règle,
 * donc elle s'éprouve seule.
 */
export function configurerTtlCode(valeur) {
  if (!Number.isFinite(valeur)) return TTL_CODE_MS
  return Math.min(Math.max(Math.trunc(valeur), TTL_CODE_MIN_MS), TTL_CODE_MAX_MS)
}

/**
 * La mémoire des codes, et les deux plafonds glissants.
 *
 * @param {{ttlMs?: number, maintenant?: () => number, tirerCode?: () => string}} [reglages]
 */
export function creerMemoireDesCodes({ ttlMs = TTL_CODE_MS, maintenant = Date.now, tirerCode } = {}) {
  /** `code -> { creeLe, expireLe }`. */
  const codes = new Map()
  let frappes = []
  let echanges = []

  const tirer = tirerCode ?? (() => randomBytes(16).toString('base64url'))

  /**
   * Frappe un code neuf, ou rend `null` si le plafond de frappes est atteint.
   *
   * L'ORDRE DES DEUX NETTOYAGES EST UNE RÈGLE, et elle a coûté un défaut : les
   * codes PÉRIMÉS sont retirés avant que le plafond des vivants ne s'applique. Sans
   * cela, huit codes expirés bloqueraient la frappe d'un neuvième — un panneau
   * qu'on laisse ouvert une heure refuserait de servir, et le refus ne dirait pas
   * pourquoi.
   */
  const frapper = () => {
    const instant = maintenant()
    frappes = frappes.filter((marque) => instant - marque < FENETRE_MS)
    if (frappes.length >= FRAPPES_MAX) return null
    for (const [valeur, fiche] of codes) if (fiche.expireLe <= instant) codes.delete(valeur)
    while (codes.size >= CODES_VIVANTS_MAX) codes.delete(codes.keys().next().value)
    const code = tirer()
    const expireLe = instant + ttlMs
    codes.set(code, { creeLe: instant, expireLe })
    frappes.push(instant)
    return { code, expireLe }
  }

  /**
   * Consomme un code et dit ce qu'il vaut.
   *
   * LA CONSOMMATION EST IMMÉDIATE, AVANT TOUTE ÉCRITURE : un code ne sert qu'une
   * fois, même si l'échange qui suit échoue ensuite (coffre indisponible, registre
   * refusé). Le rendre au client après un échec rouvrirait une fenêtre de réemploi
   * exactement là où le système vient de montrer qu'il est en difficulté.
   *
   * Rend un VERDICT, jamais une réponse HTTP : la route traduit.
   *
   * @returns {{etat: 'inconnu'} | {etat: 'expire'} | {etat: 'valide'}}
   */
  const echanger = (code) => {
    const instant = maintenant()
    echanges = echanges.filter((marque) => instant - marque < FENETRE_MS)
    if (echanges.length >= ECHANGES_MAX) return { etat: 'plafond' }
    const fiche = codes.get(code)
    if (fiche === undefined) {
      // DEUX CAUSES, UN SEUL VERDICT — et c'est assumé : distinguer « jamais émis »
      // de « déjà utilisé » dirait à un porteur de code deviné si son texte a
      // existé. Le message donne les deux possibilités, l'utilisateur tranche par
      // le geste : il redemande un code.
      return { etat: 'inconnu' }
    }
    // Consommation IMMÉDIATE, avant toute écriture — voir la note ci-dessus.
    codes.delete(code)
    echanges.push(instant)
    if (fiche.expireLe <= instant) return { etat: 'expire' }
    return { etat: 'valide' }
  }

  return {
    frapper,
    echanger,
    /**
     * Retire un code qui n'a pas pu être PUBLIÉ (adresse injoignable, composition
     * refusée). Sans cela, une frappe qui échoue consommerait un crédit du plafond
     * et une place parmi les vivants — le panneau deviendrait inutilisable sur une
     * machine dont le nom n'est pas joignable, ce qui est exactement le cas où
     * l'utilisateur insiste.
     */
    retirer: (code) => codes.delete(code),
    /** Combien de codes vivent encore — pour les tests et une trace de diagnostic. */
    vivants: () => codes.size,
  }
}
