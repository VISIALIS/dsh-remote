/**
 * LE REGISTRE DES APPAREILS — qui a le droit de parler au harness, et avec quelle portée.
 *
 * POURQUOI CE FICHIER EXISTE. C'est la dernière grosse pièce d'état qui vivait dans
 * `host.js` : le jeton historique, sa portée, et la liste des appareils appairés —
 * lus par la route de santé, la liste, la révocation et l'échange d'un code. Cet
 * état était manipulé par quatorze fonctions noyées dans 2 268 lignes, et une
 * relecture de sécurité devait reconstituer à la main QUI pouvait écrire quoi.
 * Ici, la question a une seule réponse : ce module est le seul dépositaire.
 *
 * CE QU'IL GARANTIT, ET QUI EST MESURÉ :
 *
 *   1. **Un jeton n'est jamais rendu par une route.** Il est affiché UNE fois, au
 *      terminal, à sa création — c'est `console.log` du tirage, et rien d'autre ne
 *      le fait sortir. Ce qui circule pour désigner un appareil est son EMPREINTE
 *      (SHA-256 tronqué à 12 caractères hexadécimaux).
 *   2. **La comparaison est à temps constant, et SANS SORTIE ANTICIPÉE.** La
 *      boucle compare contre CHAQUE entrée même après avoir trouvé : la durée ne
 *      doit pas dire à quelle position le jeton a été trouvé.
 *   3. **Une entrée mal formée est ignorée, pas fatale.** Le registre vit dans un
 *      fichier que l'utilisateur peut éditer : une faute de frappe dans un nom ne
 *      doit pas déconnecter tous les appareils.
 *   4. **L'écriture RELIT le registre sous verrou** (`modifyRecord`), au lieu de
 *      réécrire la liste qu'on avait en mémoire — deux appairages rapprochés
 *      s'écraseraient sinon, et un appareil disparaîtrait sans que rien ne le dise.
 *      La liste en mémoire sert à AUTHENTIFIER, pas à écrire.
 *   5. **Le jeton historique ne s'efface qu'en SUPPRIMANT son enregistrement** —
 *      jamais en le retirant d'une liste. S'il n'y a pas de `deleteRecord`, la
 *      révocation est REFUSÉE (503) au lieu d'être silencieusement inopérante.
 *
 * CE QU'IL NE FAIT PAS : aucune réponse HTTP, aucun `req`/`res`. Il rend des
 * décisions et des résultats ; la route les traduit en statuts. C'est ce qui rend
 * ses règles éprouvables sans monter un serveur.
 */

import { createHash, randomBytes, timingSafeEqual } from 'node:crypto'

import { PORTEE_ECRITURE, PORTEE_LECTURE } from './auth.js'
import { nomDAppareil } from './appairage.js'

/** La longueur minimale acceptée pour un jeton — un secret tronqué n'en est pas un. */
const LONGUEUR_JETON_MINIMALE = 32

/**
 * @param {object} dependances
 * @param {() => object | null} dependances.coffre le service `credentials`, ou `null`.
 * @param {{jeton: string, jetons: string}} dependances.cles noms des deux enregistrements.
 * @param {(valeur: unknown) => string} dependances.porteeDemandee portée d'une variable d'environnement.
 * @param {(payload: unknown) => string} dependances.porteeEnregistree portée lue dans un enregistrement.
 * @param {(texte: string) => void} [dependances.journal] où va l'affichage unique du jeton.
 * @param {() => string} [dependances.tirerJeton] tirage d'un jeton neuf (injecté par les tests).
 * @param {() => number} [dependances.maintenant]
 */
export function creerRegistreDAppareils({
  coffre,
  cles,
  porteeDemandee,
  porteeEnregistree,
  journal = (texte) => console.log('[dsh-remote] ' + texte),
  tirerJeton = () => randomBytes(32).toString('base64url'),
  maintenant = Date.now,
}) {
  /** Le jeton HISTORIQUE — celui du terminal, tiré par le harness lui-même. */
  let jeton = null
  /** Sa portée. La valeur de départ est celle d'un jeton d'avant la portée. */
  let portee = PORTEE_ECRITURE
  /**
   * LES APPAREILS, dans l'ordre de lecture : l'historique d'abord (s'il existe),
   * puis le registre. Chaque entrée porte SON jeton et SA portée — c'est ce qui
   * permet de révoquer un appareil sans toucher aux autres.
   */
  let appareils = []

  /**
   * Charge (ou tire) le jeton historique, puis le registre.
   *
   * UN REGISTRE ILLISIBLE NE REND PAS LE JETON HISTORIQUE INUTILISABLE : on rend
   * ce qu'on a, et l'appelant journalise. Le jeton du terminal reste valide même
   * si le fichier des appareils est cassé — le perdre déconnecterait la seule
   * connexion qui permette de réparer.
   */
  const charger = async () => {
    jeton = await chargerJeton()
    try {
      appareils = await chargerAppareils()
      return { jeton, appareils, illisible: null }
    } catch (erreur) {
      appareils =
        jeton === null
          ? []
          : [
              {
                token: jeton,
                portee,
                creeLe: null,
                nom: 'Jeton du terminal (ce Mac, dsh-remote-ctl)',
                historique: true,
              },
            ]
      return { jeton, appareils, illisible: String(erreur?.message ?? erreur) }
    }
  }

  const chargerJeton = async () => {
    const credentials = coffre()
    if (credentials === null) {
      journal("coffre d identifiants indisponible: le plugin ne peut pas gerer de jeton")
      return null
    }
    const existant = await credentials.readRecord(cles.jeton)
    if (existant !== undefined && existant !== null && existant.kind === 'grant') {
      const valeur = existant.payload?.token
      if (typeof valeur === 'string' && valeur.length >= LONGUEUR_JETON_MINIMALE) {
        const lue = porteeEnregistree(existant.payload)
        // Une portée inconnue n'authentifie pas. La laisser passer ferait de
        // n'importe quelle chaîne autre que `lecture` un droit d'écriture.
        if (lue !== PORTEE_LECTURE && lue !== PORTEE_ECRITURE) {
          journal(
            'portee inconnue sur le jeton du terminal : il est ignore. Valeurs admises : lecture, ecriture, ou aucun champ.',
          )
          return null
        }
        portee = lue
        return valeur
      }
    }
    const nouveau = tirerJeton()
    portee = porteeDemandee(process.env.DSH_REMOTE_PORTEE)
    await credentials.modifyRecord(cles.jeton, async () => ({
      kind: 'grant',
      payload: { token: nouveau, creeLe: maintenant(), portee },
    }))
    // Affichage UNIQUE, dans le terminal de l'utilisateur, a la creation.
    // Jamais reecrit ensuite, jamais journalise, JAMAIS RENVOYE PAR UNE ROUTE —
    // c'est la regle que l'appairage par code a permis de retablir (l'etape A la
    // transgressait en publiant ce jeton dans un QR).
    journal('NOUVEAU JETON D APPAREIL, PORTEE ' + portee.toUpperCase() + ' (a saisir une fois dans l application, puis oublier) :')
    journal(nouveau)
    if (portee === PORTEE_LECTURE) {
      journal(
        'ce jeton LIT sans pouvoir ecrire. Pour autoriser l ecriture, relancer avec DSH_REMOTE_PORTEE=ecriture et un jeton neuf (supprimer l enregistrement ' +
          cles.jeton +
          ' du coffre).',
      )
    }
    return nouveau
  }

  /** L'entrée du registre correspondant à un enregistrement de coffre, ou `null`. */
  const entreeDeRegistre = (brut) => {
    if (brut === null || typeof brut !== 'object') return null
    const valeur = brut.token
    if (typeof valeur !== 'string' || valeur.length < LONGUEUR_JETON_MINIMALE) return null
    const lue = porteeEnregistree(brut)
    if (lue !== PORTEE_LECTURE && lue !== PORTEE_ECRITURE) return null
    return {
      token: valeur,
      portee: lue,
      creeLe: Number.isFinite(brut.creeLe) ? brut.creeLe : null,
      nom: nomDAppareil(brut.nom),
      historique: false,
    }
  }

  const chargerAppareils = async () => {
    const credentials = coffre()
    const entrees = []
    if (jeton !== null) {
      // LE NOM DIT CE QUE C'EST, ET À QUI ÇA SERT. « jeton historique » faisait
      // lire un vestige là où il y a la connexion de l'application SUR CE MAC à
      // elle-même (et celle de dsh-remote-ctl) : le propriétaire a demandé à quoi
      // il correspondait, ce qui est exactement le défaut d'un nom qui n'explique
      // rien. Il n'est pas appairé, il n'a pas de date, et le révoquer le remplace
      // au prochain démarrage — le panneau le dit à côté.
      entrees.push({
        token: jeton,
        portee,
        creeLe: null,
        nom: 'Jeton du terminal (ce Mac, dsh-remote-ctl)',
        historique: true,
      })
    }
    if (credentials === null) return entrees
    const registre = await credentials.readRecord(cles.jetons)
    const liste =
      registre?.kind === 'grant' && Array.isArray(registre.payload?.jetons) ? registre.payload.jetons : []
    for (const brut of liste) {
      const entree = entreeDeRegistre(brut)
      if (entree !== null) entrees.push(entree)
    }
    return entrees
  }

  /**
   * Comparaison à temps constant, longueurs égalisées.
   *
   * POURQUOI ELLE RESTE ICI, alors qu'il n'y a plus UN secret mais N. Le nombre
   * d'appareils est public (il est affiché), la taille d'un jeton aussi : ce qui
   * ne doit pas fuiter, c'est la VALEUR. Chaque comparaison est donc à temps
   * constant, et la boucle les fait TOUTES — sans sortie anticipée, pour que la
   * durée ne dise pas à quelle position le jeton a été trouvé.
   */
  const egalConstant = (attendu, recu) => {
    const gauche = Buffer.from(attendu, 'utf8')
    const droite = Buffer.from(recu, 'utf8')
    const taille = Math.max(gauche.length, droite.length, 1)
    const tamponGauche = Buffer.alloc(taille)
    const tamponDroite = Buffer.alloc(taille)
    gauche.copy(tamponGauche)
    droite.copy(tamponDroite)
    const egaux = timingSafeEqual(tamponGauche, tamponDroite)
    return egaux && gauche.length === droite.length
  }

  /** L'appareil dont le jeton est celui présenté, ou `null`. */
  const appareilDe = (presente) => {
    if (typeof presente !== 'string' || presente.length === 0) return null
    let trouve = null
    for (const entree of appareils) {
      if (egalConstant(entree.token, presente)) trouve = trouve === null ? entree : trouve
    }
    return trouve
  }

  /**
   * L'EMPREINTE d'un jeton — ce qu'on montre pour désigner un appareil.
   *
   * POURQUOI UNE EMPREINTE ET JAMAIS LE JETON. La liste des appareils sert à en
   * révoquer un : l'utilisateur doit pouvoir le DÉSIGNER sans qu'on lui réaffiche
   * un secret. Douze caractères hexadécimaux suffisent à distinguer deux appareils
   * et ne permettent pas de remonter au jeton (c'est un SHA-256 tronqué d'une
   * valeur de 256 bits d'aléa).
   */
  const empreinteDe = (valeur) => createHash('sha256').update(String(valeur)).digest('hex').slice(0, 12)

  /**
   * Écrire dans le registre À PARTIR DE LA LISTE RELUE, jamais de la mémoire.
   *
   * POURQUOI LA LISTE EST RELUE ICI, ET PAS REPRISE DE `appareils`. Deux écritures
   * rapprochées — deux appareils qui s'appairent dans la même minute, une
   * révocation pendant un échange — écriraient chacune la liste qu'elles avaient
   * en mémoire, et la seconde EFFACERAIT l'entrée de la première. Le service de
   * coffre sérialise et relit sous verrou : `modifyRecord` reçoit l'enregistrement
   * COURANT, et c'est ce qu'on modifie.
   *
   * (La conséquence d'un écrasement ne serait pas une faille mais une perte : un
   * appareil appairé disparaîtrait du registre, et son jeton cesserait de valoir au
   * redémarrage suivant — sans que rien ne le dise.)
   */
  const modifierRegistre = async (transformer) => {
    const credentials = coffre()
    if (credentials === null) return false
    await credentials.modifyRecord(cles.jetons, async (courant) => {
      const brut = Array.isArray(courant?.payload?.jetons) ? courant.payload.jetons : []
      return { kind: 'grant', payload: { jetons: transformer(brut) } }
    })
    return true
  }

  /**
   * Ajoute un appareil au registre, PUIS à la liste en mémoire.
   *
   * L'ÉCRITURE PASSE D'ABORD : si le coffre refuse, on ne garde pas en mémoire un
   * appareil qui ne survivrait pas au redémarrage — le panneau afficherait un
   * appareil appairé qui n'existe pas.
   */
  const ajouter = async (entree) => {
    const ecrit = await modifierRegistre((liste) => [
      ...liste,
      { token: entree.token, portee: entree.portee, creeLe: entree.creeLe, nom: entree.nom },
    ])
    // LE COFFRE D'ABORD, LA MÉMOIRE ENSUITE — ET ON VÉRIFIE QU'IL A ÉCRIT.
    // Ignorer ce retour laissait en mémoire un appareil absent du coffre : il
    // disparaissait au redémarrage suivant, et le panneau avait affiché un
    // appareil appairé qui n'existait pas. Trouvé par le test « sans coffre,
    // ajouter ÉCHOUE au lieu de garder un appareil fantôme ».
    if (!ecrit) throw new Error('coffre indisponible : le registre ne peut pas etre ecrit')
    appareils = [...appareils, { ...entree, historique: false }]
    return entree
  }

  /**
   * Révoque l'appareil désigné par son empreinte.
   *
   * Rend un RÉSULTAT, jamais une réponse HTTP : la route traduit. Le cas du jeton
   * HISTORIQUE est distinct, et c'est le cœur de cette fonction — il vit dans son
   * propre enregistrement, donc il se SUPPRIME au lieu de se filtrer, et un jeton
   * neuf sera tiré au prochain démarrage. Sans `deleteRecord`, on REFUSE : une
   * révocation qui n'efface rien serait un mensonge affiché à l'utilisateur.
   */
  const retirer = async (empreinte) => {
    if (typeof empreinte !== 'string' || !/^[0-9a-f]{12}$/.test(empreinte)) {
      return { ok: false, code: 400, corps: { erreur: 'empreinte absente ou malformee' } }
    }
    const cible = appareils.find((entree) => empreinteDe(entree.token) === empreinte)
    if (cible === undefined) {
      return {
        ok: false,
        code: 404,
        corps: {
          erreur: 'appareil inconnu',
          detail: 'cet appareil n est plus dans la liste : rechargez le panneau',
        },
      }
    }
    const credentials = coffre()
    try {
      if (cible.historique === true) {
        if (credentials === null || typeof credentials.deleteRecord !== 'function') {
          return {
            ok: false,
            code: 503,
            corps: {
              erreur: 'coffre incapable de supprimer',
              detail: 'le service credentials n expose pas deleteRecord',
            },
          }
        }
        await credentials.deleteRecord(cles.jeton)
        jeton = null
      } else {
        if (credentials === null) {
          return { ok: false, code: 503, corps: { erreur: 'coffre indisponible' } }
        }
        await modifierRegistre((liste) => liste.filter((entree) => entree?.token !== cible.token))
      }
    } catch (erreur) {
      return {
        ok: false,
        code: 500,
        corps: { erreur: 'revocation impossible', detail: String(erreur?.message ?? erreur) },
      }
    }
    appareils = appareils.filter((entree) => entree !== cible)
    return { ok: true, nom: cible.nom, restants: appareils.length, historique: cible.historique === true }
  }

  return {
    charger,
    appareilDe,
    jetonValide: (presente) => appareilDe(presente) !== null,
    empreinteDe,
    liste: () => appareils,
    nombre: () => appareils.length,
    porteeHistorique: () => portee,
    jetonHistorique: () => jeton,
    ajouter,
    retirer,
    /** Exposé pour les tests : la comparaison constante, éprouvée telle quelle. */
    egalConstant,
  }
}
