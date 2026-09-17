/**
 * LA BARRIÈRE D'ACCÈS DU PLUGIN — la RÈGLE #0, écrite une fois et éprouvée seule.
 *
 * POURQUOI CE FICHIER EXISTE. L'authentification vivait au milieu de `host.js`,
 * entre la lecture des journaux et les routes. C'est la partie du dépôt dont une
 * erreur coûte le plus cher — elle décide si une requête lit des données de session
 * —, et elle était noyée dans 2 300 lignes. Sortie ici, elle tient en une page, ses
 * quatre règles se lisent d'affilée, et `tests/auth.test.js` les éprouve **sans
 * harness**, donc sans monter un serveur pour vérifier qu'un `Origin` est refusé.
 *
 * LES QUATRE RÈGLES, DANS L'ORDRE OÙ ELLES S'APPLIQUENT — l'ordre est une règle de
 * sécurité, pas une commodité :
 *
 *   1. **Aucun `Origin`.** Un client natif n'en envoie jamais ; un navigateur en
 *      envoie toujours, y compris depuis une page hostile. On refuse AVANT de
 *      regarder le jeton, donc une page web n'apprend rien — pas même si un jeton
 *      valide circule.
 *   2. **Un porteur valide, comparé à temps constant contre CHAQUE appareil.**
 *      La comparaison appartient au registre (`appareilDe`), qui ne sort jamais
 *      d'une boucle plus tôt que nécessaire.
 *   3. **La portée est lue SUR LA RÉPONSE**, jamais dans une variable de module :
 *      elle dépend de QUI appelle, et une variable partagée deviendrait fausse le
 *      jour où une route attend entre l'authentification et la lecture.
 *   4. **Le silence de l'écriture.** Un jeton de lecture seule ne mute rien : la
 *      route répond `403` avec une raison DISTINCTE de `origine refusee` — deux
 *      causes, deux messages — et le contrôleur n'est jamais appelé.
 *
 * CE QUE CE MODULE NE FAIT PAS : il ne lit aucun secret, ne connaît ni coffre ni
 * fichier, et ne décide pas de ce qu'un appareil a le droit de voir. Il reçoit
 * `appareilDe` (une fonction) et rend des décisions. C'est ce qui le rend éprouvable
 * en trente lignes de test.
 */

import { envoyer } from './reponse.js'

/** La portée qui autorise l'écriture. L'autre, `lecture`, lit sans écrire. */
export const PORTEE_ECRITURE = 'ecriture'

/**
 * La portée qui LIT sans écrire.
 *
 * ELLE EST DÉFINIE ICI, À CÔTÉ DE L'AUTRE, ET PAS AILLEURS : ce sont les deux
 * valeurs d'une même décision, et les séparer ferait diverger le jour où l'une
 * changerait de nom. `host.js` les réexporte — c'est sa surface publique —, mais
 * il n'en est plus la source.
 */
export const PORTEE_LECTURE = 'lecture'

/**
 * La marque de l'appareil authentifié SUR LA RÉPONSE, et pourquoi pas une variable
 * de module.
 *
 * POURQUOI. La portée était UNE variable globale : il n'y avait qu'un jeton, donc
 * une seule portée. Avec un jeton par appareil, elle dépend de QUI appelle. Une
 * variable de module écrasée à chaque requête serait juste « en pratique » (Node
 * est mono-thread, et le gestionnaire lit la portée dans le même tour) — mais elle
 * deviendrait fausse le jour où une route attend entre l'authentification et la
 * lecture. La réponse, elle, appartient à SA requête par construction.
 */
export const APPAREIL = Symbol('dsh-remote/appareil')

/**
 * Construit la barrière d'accès.
 *
 * @param {object} dependances
 * @param {(jeton: string | null) => object | null} dependances.appareilDe
 *   l'appareil dont le jeton est celui présenté, ou `null`. C'est la SEULE source
 *   d'authentification, et elle appartient au registre.
 * @param {(req: object, code: number, complement?: string) => void} dependances.tracer
 *   le journal d'accès — il n'écrit jamais un jeton, seulement méthode, chemin, code.
 * @param {(mot: string) => string} dependances.nomDeLaCle
 *   rend le nom d'une clé du coffre (`device-tokens`, `device-token`) pour le texte
 *   du refus : le remède doit dire OÙ aller, pas seulement que c'est refusé.
 */
export function creerAuthentification({ appareilDe, tracer, nomDeLaCle }) {
  const autoriser = (req, res) => {
    // 1. Un client natif n'envoie jamais `Origin`. Un navigateur en envoie
    //    toujours, y compris depuis une page hostile. On refuse donc tout
    //    `Origin`, avant même de regarder le jeton.
    if (req.headers.origin !== undefined) {
      envoyer(res, 403, { erreur: 'origine refusee' })
      return false
    }
    // 2. Secret partage, comparaison a temps constant — contre CHAQUE appareil.
    const entete = req.headers.authorization
    const presente = typeof entete === 'string' && entete.startsWith('Bearer ') ? entete.slice(7) : null
    const appareil = appareilDe(presente)
    if (appareil === null) {
      // RÉPONSE FIXE, ET SANS RIEN LIRE : une requête non authentifiée ne doit
      // déclencher aucune E/S, et ne doit pas distinguer « jeton inconnu » de
      // « jeton absent » — deux messages différents indiqueraient à un inconnu
      // qu'il a trouvé un jeton valide quelque part.
      res.writeHead(401, {
        'content-type': 'application/json; charset=utf-8',
        'www-authenticate': 'Bearer',
        'cache-control': 'no-store',
      })
      res.end('{"erreur":"jeton requis"}')
      return false
    }
    // QUEL APPAREIL A PARLÉ, ET DONC QUELLE PORTÉE S'APPLIQUE.
    res[APPAREIL] = appareil
    return true
  }

  /**
   * La portée de l'appareil qui a parlé — lue SUR LA RÉPONSE, jamais devinée.
   *
   * Rend `null` quand la requête n'a pas été authentifiée : aucune route ne doit
   * alors décider quoi que ce soit. Une valeur par défaut, ici, serait un droit
   * accordé par omission.
   */
  const porteeDe = (res) => (res[APPAREIL] === undefined ? null : res[APPAREIL].portee)

  /**
   * La portée refuse-t-elle cette écriture ? Rend `true` si la requête est
   * REFUSÉE (et la réponse envoyée).
   *
   * POURQUOI ELLE EST SÉPARÉE DE `autoriser`. Les routes d'écriture vivent dans
   * le même gestionnaire que celles de lecture (`/v1/session/<id>/<action>`) :
   * le jeton y est déjà vérifié une fois pour toutes, et le contrôle de portée
   * doit donc pouvoir s'appliquer SEUL, dans la branche qui écrit.
   *
   * ELLE REFUSE AUSSI QUAND RIEN N'A ÉTÉ AUTHENTIFIÉ (`porteeDe` rend `null`) :
   * la seule façon de passer est une portée qui vaut explicitement `ecriture`.
   */
  const refuserSiLectureSeule = (req, res) => {
    const porteeRequete = porteeDe(res)
    if (porteeRequete === PORTEE_ECRITURE) return false
    envoyer(res, 403, {
      erreur: 'jeton en lecture seule',
      portee: porteeRequete,
      detail:
        "cet appareil a recu un jeton qui LIT sans ecrire. Pour lui donner l ecriture : supprimer son enregistrement dans " +
        nomDeLaCle('jetons') +
        ' (ou le jeton historique ' +
        nomDeLaCle('jeton') +
        "), puis refaire l appairage avec DSH_REMOTE_PORTEE=ecriture.",
    })
    tracer(req, 403, 'portee ' + String(porteeRequete))
    return true
  }

  /** Barrière complète d'une route qui écrit : jeton, puis portée. */
  const autoriserEcriture = (req, res) => {
    if (!autoriser(req, res)) return false
    return !refuserSiLectureSeule(req, res)
  }

  return { autoriser, porteeDe, refuserSiLectureSeule, autoriserEcriture }
}
