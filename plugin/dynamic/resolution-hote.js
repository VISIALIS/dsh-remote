/**
 * QUEL NOM — ET QUEL TRANSPORT — CETTE MACHINE DOIT-ELLE ANNONCER ?
 *
 * POURQUOI CE FICHIER EXISTE. La réponse vit dans un QR code, donc elle est
 * définitive pour l'appareil qui le scanne : un nom injoignable ou un transport
 * faux produit un appairage qui ne peut aboutir nulle part, et l'utilisateur n'a
 * aucun moyen de comprendre pourquoi. Elle était calculée au milieu de `host.js`,
 * entre deux caches et trois routes, et deux de ses règles ne se voyaient qu'à la
 * lecture :
 *
 *   1. **jamais la boucle locale.** `127.0.0.1` dans un QR ne mène nulle part depuis
 *      un téléphone ;
 *   2. **le schéma se LIT, il ne se devine pas.** `tailscale serve status --json`
 *      dit sous quel transport la machine est publiée ; sans binaire, sans
 *      publication, ou devant une sortie inattendue, on retombe sur le CLAIR —
 *      c'est-à-dire sur le comportement d'avant, jamais sur une adresse inventée.
 *
 * DEUX SOURCES POUR LE NOM, DANS CET ORDRE : ce que Tailscale dit de la machine
 * locale (`Self`, via la découverte), puis l'hôte déclaré au profil. La seconde
 * existe parce qu'un Tailscale muet ne doit pas rendre l'appairage impossible.
 *
 * LES DEUX CACHES SONT ICI, ET PAS AILLEURS. Ils couvrent deux processus (`tailscale
 * status`, `tailscale serve status`) qu'on ne relance pas à chaque frappe de code :
 * un tailnet ne change pas d'une seconde à l'autre. `null` EST UN RÉSULTAT mis en
 * cache — « rien de publié, ou binaire muet » ne doit pas relancer le CLI à chaque
 * demande.
 */

import { decouvrirMachines, lirePublication } from './tailscale.js'

/** Durée de validité des deux lectures : quinze secondes. */
export const TTL_DECOUVERTE_MS = 15000

/**
 * @param {object} dependances
 * @param {() => string[]} dependances.hotesDeclares les hôtes de confiance du profil.
 * @param {() => Promise<{machines: object[] | null, diagnostic: string | null}>} [dependances.decouvrir]
 * @param {() => Promise<{schema: string, port: number, hote: string} | null>} [dependances.lireLaPublication]
 * @param {() => number} [dependances.maintenant]
 * @param {number} [dependances.ttlMs]
 */
export function creerResolveurDHote({
  hotesDeclares,
  decouvrir = decouvrirMachines,
  lireLaPublication = lirePublication,
  maintenant = Date.now,
  ttlMs = TTL_DECOUVERTE_MS,
}) {
  // `vuLe: null` VEUT DIRE « JAMAIS LU », et c'est une correction : avec `vuLe: 0`,
  // une horloge injectée qui commence à zéro faisait croire à une lecture fraîche,
  // et la PREMIÈRE lecture était sautée — le cache rendait `null` jusqu'à ce que
  // l'horloge dépasse la durée de vie. Avec une horloge réelle, la différence ne se
  // voyait pas (l'époque est loin) ; c'est le test à horloge réglable qui l'a
  // montrée, et c'est exactement pour cela qu'il existe.
  let cacheDecouverte = { vuLe: null, valeur: null }
  let cachePublication = { vuLe: null, valeur: null }

  /**
   * Le schéma sous lequel cette machine est publiée : `http` par défaut.
   *
   * LE DÉFAUT EST LE CLAIR, ET C'EST DÉLIBÉRÉ : c'est ce que le plugin publiait
   * avant, et un `null` (binaire absent, aucune publication, sortie inattendue) ne
   * doit pas transformer une installation qui marchait en installation qui ne
   * répond plus. Le passage à HTTPS est un FAIT que la machine annonce.
   */
  const schema = async () => {
    const instant = maintenant()
    if (cachePublication.vuLe === null || instant - cachePublication.vuLe > ttlMs) {
      let valeur = null
      try {
        valeur = await lireLaPublication()
      } catch {
        valeur = null
      }
      cachePublication = { vuLe: instant, valeur }
    }
    return cachePublication.valeur?.schema === 'https' ? 'https' : 'http'
  }

  /** Les machines du tailnet, servies par le cache — la route `/v1/serveurs` s'en sert. */
  const machines = async () => {
    const instant = maintenant()
    if (cacheDecouverte.vuLe === null || instant - cacheDecouverte.vuLe > ttlMs) {
      const { machines: trouvees, diagnostic } = await decouvrir()
      cacheDecouverte = { vuLe: instant, valeur: { machines: trouvees, diagnostic } }
    }
    return cacheDecouverte.valeur
  }

  /**
   * Le nom à publier, la source qui l'a fourni, et le transport.
   *
   * @returns {Promise<{hote: string, via: 'tailscale'|'hote declare'|'aucun', schema: 'http'|'https'}>}
   */
  const resoudre = async () => {
    const transport = await schema()
    try {
      const trouvees = (await machines()).machines ?? []
      const locale = trouvees.find((machine) => machine.local === true)
      if (locale !== undefined && typeof locale.nomDNS === 'string' && locale.nomDNS.length > 0) {
        return { hote: locale.nomDNS, via: 'tailscale', schema: transport }
      }
    } catch {
      // Tailscale absent ou muet : l'hote declare reste une source valable.
    }
    const declares = hotesDeclares()
    const premier = Array.isArray(declares) && declares.length > 0 ? String(declares[0]) : ''
    // Le profil peut declarer un hote AVEC son port : on ne garde que le nom.
    const nom = premier.split(':')[0]
    return nom.length > 0
      ? { hote: nom, via: 'hote declare', schema: transport }
      : { hote: '', via: 'aucun', schema: transport }
  }

  return { resoudre, machines, schema }
}
