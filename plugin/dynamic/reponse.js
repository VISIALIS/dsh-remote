/**
 * LES RÉPONSES HTTP DU PLUGIN — lire un corps, écrire une réponse.
 *
 * POURQUOI CE FICHIER EXISTE. Ces trois fonctions vivaient au milieu de 2 368
 * lignes, entre l'authentification et les routes. Elles ne décident RIEN de la
 * sécurité — elles ne lisent ni jeton, ni portée —, et c'est précisément ce qui
 * les rendait difficiles à relire : un auditeur qui cherche « où une requête est
 * refusée » traverse d'abord la plomberie. Sorties ici, avec leurs tests, elles
 * se lisent en une fois, et `host.js` ne garde que ce qui décide.
 *
 * ELLES PORTENT DES RÈGLES MESURÉES, ET PAS SEULEMENT DU FORMATAGE :
 *
 *   - `cache-control: no-store` sur TOUTE réponse. Un journal de session n'a rien
 *     à faire dans un cache, et le navigateur n'est pas le seul à en avoir un ;
 *   - `content-length` TOUJOURS posé : une réponse sans longueur est servie en
 *     `chunked`, ce qui interdit au client de distinguer « fin de corps » de
 *     « connexion coupée » — et un client mobile qui ne peut pas distinguer les
 *     deux affiche une erreur là où il n'a reçu qu'un corps tronqué ;
 *   - le corps lu est BORNÉ (1 Mio) et détruit au-delà : une route qui accepte un
 *     corps sans limite laisse un inconnu faire enfler la mémoire du harness, qui
 *     n'a pas de bac à sable (RÈGLE #0) ;
 *   - un corps illisible rend `null`, JAMAIS `{}` : confondre « vide » et
 *     « invalide » ferait passer une requête malformée pour une requête sans
 *     paramètres, et la route répondrait à côté au lieu de refuser.
 */

/** La borne d'un corps de requête, en octets. */
export const PLAFOND_CORPS = 1024 * 1024

/**
 * Écrit une réponse JSON.
 *
 * @param {object} res
 * @param {number} code statut HTTP.
 * @param {unknown} charge valeur sérialisée en JSON.
 * @param {string | null} [etag] empreinte optionnelle — voir la note ci-dessous.
 */
export function envoyer(res, code, charge, etag = null) {
  const corps = JSON.stringify(charge)
  const entetes = {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'content-length': Buffer.byteLength(corps),
  }
  // L'`ETag` est OPTIONNEL : seules les réponses dont l'empreinte est connue (la
  // liste des sessions) en portent un. En poser un partout promettrait une
  // validité qu'aucune autre route ne sait calculer.
  if (typeof etag === 'string') entetes.etag = etag
  res.writeHead(code, entetes)
  res.end(corps)
}

/**
 * Écrit une réponse `304` — « rien n'a changé », sans corps.
 *
 * L'EMPREINTE EST RENDUE TELLE QUELLE : c'est ce que le client compare, et une
 * valeur réécrite ici (guillemets, casse) ferait échouer la comparaison suivante
 * pour une raison invisible.
 */
export function envoyerNonModifie(res, empreinte) {
  res.writeHead(304, {
    etag: empreinte,
    'cache-control': 'no-store',
    'content-length': '0',
  })
  res.end()
}

/**
 * Lit le corps JSON d'une requête.
 *
 * @param {object} req
 * @returns {Promise<object | null>} `null` quand le corps est illisible, trop
 *   volumineux, ou que la requête a échoué. Ne lève jamais : une exception ici
 *   deviendrait un `400` vide, indiscernable d'une requête malformée.
 */
export function lireCorps(req) {
  return new Promise((resolve) => {
    const morceaux = []
    let taille = 0
    let conclu = false
    const conclure = (valeur) => {
      if (conclu) return
      conclu = true
      resolve(valeur)
    }
    req.on('data', (morceau) => {
      taille += morceau.length
      if (taille > PLAFOND_CORPS) {
        req.destroy()
        conclure(null)
        return
      }
      morceaux.push(morceau)
    })
    req.on('end', () => {
      if (morceaux.length === 0) return conclure({})
      try {
        const valeur = JSON.parse(Buffer.concat(morceaux).toString('utf8'))
        // Un corps JSON qui n'est pas un OBJET (`null`, `42`, `"texte"`) n'est pas
        // un corps de requête : le rendre tel quel ferait lire des propriétés sur
        // un nombre, et la route lèverait au lieu de refuser.
        conclure(valeur !== null && typeof valeur === 'object' ? valeur : {})
      } catch {
        conclure(null)
      }
    })
    req.on('error', () => conclure(null))
  })
}
