/**
 * LES QUATRE GESTES DU PANNEAU — frapper un code, l'echanger, lister, revoquer.
 *
 * POURQUOI CE FICHIER EXISTE. Ces quatre fonctions sont les SEULES du plugin qui ne
 * soient pas gardees par le jeton d'appareil : trois le sont par la SESSION
 * NAVIGATEUR (l'utilisateur, devant son Mac), et l'echange par le CODE lui-meme. Une
 * relecture de securite doit donc pouvoir les lire d'affilee, sans traverser les
 * 2 000 lignes de `host.js` — c'est exactement ce que ce decoupage rend possible.
 *
 * CE QU'ELLES DECIDENT, ET QUI EST MAINTENANT A UN SEUL ENDROIT :
 *
 *   - **l'echange REND un jeton** — la seule route du plugin qui en rend un. Il est
 *     range dans le registre pour l'appareil qui a presente le code, avec la portee
 *     annoncee, et le nom de l'appareil est trace (jamais le jeton, jamais le code) ;
 *   - **le code sert UNE fois** : la consommation appartient a `codes-appairage.js` et
 *     elle est IMMEDIATE — un echec d'ecriture ensuite ne rouvre pas la porte ;
 *   - **la liste ne rend que des EMPREINTES** : l'utilisateur doit pouvoir designer un
 *     appareil sans qu'on lui reaffiche un secret ;
 *   - **la revocation passe par la session navigateur** : un porteur de jeton
 *     d'appareil ne peut pas expulser les autres. C'est une derogation assumee a la
 *     REGLE #0 (elle est ecrite dans le README), et elle vit donc ici, lisible.
 *
 * CE QU'ELLE RECOIT, ET RIEN DE PLUS : les fonctions qui repondent et qui lisent, le
 * registre, la memoire des codes, le resolveur d'hote, et le contrat d'appairage
 * (`construire`). Aucune dependance n'est devinee : toutes viennent de
 * `host.js`, qui les a deja construites.
 */

import { randomBytes } from 'node:crypto'

export function creerRoutesAppairage({
  envoyer,
  lireCorps,
  tracer,
  coffre,
  registre,
  codes,
  resolveur,
  construire,
  codePlausible,
  ajouter,
  retirer,
  empreinteDe,
  nomDeLHote,
  GENRE_CODE,
  VERSIONS,
  porteeDemandee,
  nomDAppareil,
  VERSION_PROTOCOLE,
}) {

  /**
   * FRAPPER UN CODE D'APPAIRAGE — la seule chose que le panneau fait désormais.
   *
   * POURQUOI CE N'EST PLUS LE JETON QUI EST PUBLIÉ. À l'étape A, cette route
   * rendait le jeton d'appareil lui-même. C'était une dérogation assumée, et elle
   * avait une conséquence écrite noir sur blanc : une photo de l'écran valait le
   * jeton POUR TOUJOURS, et cette photo pouvait venir d'un autre panneau (celui
   * de `share-qr`, qui publiait l'URL navigateur authentifiée — ce plugin a
   * quitté le dépôt le 14 septembre 2026). Un code change cela : il expire en
   * deux minutes, ne sert qu'une fois, et ne vit qu'en mémoire.
   *
   * LA PORTÉE EST ANNONCÉE, PAS ACCORDÉE ICI : le code ne donne aucun droit, il
   * donne un JETON dont la portée est celle que le harness applique à un appareil
   * neuf (`DSH_REMOTE_PORTEE`, donc `lecture` par défaut). Le panneau l'affiche
   * pour que l'utilisateur sache ce qu'il donne avant de scanner.
   */
  const repondreFrappe = async (req, res) => {
    // L'ORDRE COMPTE, ET IL EST CELUI D'AVANT : le nom de l'hôte d'abord, le code
    // ensuite. Tirer un code avant de savoir si l'adresse est joignable brûlerait un
    // crédit du plafond pour une frappe qui ne peut pas aboutir — sur une machine
    // dont le nom n'est pas joignable, c'est-à-dire précisément le cas où
    // l'utilisateur insiste.
    const { hote, via, schema } = await nomDeLHote()
    // LA FRAPPE APPARTIENT À LA MÉMOIRE DES CODES : plafond glissant, retrait des
    // périmés AVANT de faire de la place, tirage du secret.
    const tire = codes.frapper()
    if (tire === null) {
      envoyer(res, 429, { erreur: 'trop de codes demandes', detail: 'patientez une minute avant de recommencer' })
      return tracer(req, 429)
    }
    const { code, expireLe } = tire
    const resultat = construire({ hote, genre: GENRE_CODE, secret: code, schema })
    if (resultat.ok !== true) {
      // UN CODE QUI N'A PAS PU ÊTRE PUBLIÉ NE VIT PAS : sans ce retrait, une adresse
      // injoignable laisserait des codes fantômes occuper les places.
      codes.retirer(code)
      envoyer(res, 503, { erreur: 'adresse injoignable', motif: resultat.motif, detail: resultat.message })
      return tracer(req, 503, resultat.motif)
    }

    envoyer(res, 200, {
      protocole: VERSION_PROTOCOLE,
      genre: GENRE_CODE,
      version: VERSIONS[GENRE_CODE],
      // L'ADRESSE QUE LE PANNEAU AFFICHE SUIT LE SCHEMA PUBLIE : annoncer
      // `http://…` a cote d'un QR qui porte `https` ferait douter de la seule
      // ligne que l'utilisateur peut verifier a la main.
      adresse: schema + '://' + hote,
      charge: resultat.charge,
      // La portee qu'aura le jeton issu de ce code : dite ICI, avant le scan.
      porteeFuture: porteeDemandee(process.env.DSH_REMOTE_PORTEE),
      expireLe,
      via,
    })
    // LE CODE N'EST PAS TRACE : `tracer` n'ecrit que la methode, le chemin sans
    // parametre, le code HTTP et ce complement.
    tracer(req, 200, 'code ' + via)
  }

  /**
   * ÉCHANGER UN CODE CONTRE UN JETON PROPRE À L'APPAREIL.
   *
   * C'EST LA SEULE ROUTE QUI REND UN JETON, et elle le rend à qui présente un
   * code — c'est-à-dire à qui a vu l'écran pendant les deux minutes de vie du
   * code, ou a scanné le QR. La dérogation à l'interdit #3 se réduit donc à cela,
   * au lieu de « une route rend le jeton à toute session navigateur ».
   *
   * ORDRE DES OPÉRATIONS, ET IL EST DÉLIBÉRÉ : forme, puis provenance, puis
   * consommation du code, puis écriture. LE CODE EST CONSOMMÉ AVANT L'ÉCRITURE :
   * un échec du coffre brûle le code au lieu de le laisser rejouable — l'appareil
   * redemande un code, ce qui est un désagrément ; un code rejouable serait une
   * faille.
   */
  const repondreEchange = async (req, res, corps) => {
    const entete = req.headers.authorization
    const code = typeof entete === 'string' && entete.startsWith('Bearer ') ? entete.slice(7) : null
    if (!codePlausible(code)) {
      envoyer(res, 400, { erreur: 'code absent ou malforme' })
      return tracer(req, 400)
    }
    // LA CONSOMMATION APPARTIENT A LA MEMOIRE DES CODES, et elle est IMMEDIATE : un
    // code ne sert qu'une fois, meme si l'echange qui suit echoue. La route traduit
    // le verdict, elle ne decide plus.
    const verdict = codes.echanger(code)
    if (verdict.etat === 'plafond') {
      envoyer(res, 429, { erreur: 'trop d echanges', detail: 'patientez une minute avant de recommencer' })
      return tracer(req, 429)
    }
    if (verdict.etat === 'inconnu') {
      // DEUX CAUSES, UN SEUL REFUS — et c'est assumé : distinguer « jamais emis »
      // de « deja utilise » dirait a un porteur de code devine si son texte a
      // existe. Le message donne les deux possibilites, l'utilisateur tranche par
      // le geste : il redemande un code.
      envoyer(res, 403, { erreur: 'code inconnu ou deja utilise', detail: 'les codes ne servent qu une fois et expirent en deux minutes' })
      return tracer(req, 403)
    }
    if (verdict.etat === 'expire') {
      envoyer(res, 403, { erreur: 'code expire', detail: 'redemandez un code dans le panneau « Appairer un appareil »' })
      return tracer(req, 403, 'expire')
    }
    const maintenant = Date.now()
    const credentials = coffre()
    if (credentials === null) {
      envoyer(res, 503, { erreur: 'coffre indisponible', detail: "sans coffre, aucun jeton ne peut etre range" })
      return tracer(req, 503)
    }
    const nouveau = randomBytes(32).toString('base64url')
    const porteeNouvelle = porteeDemandee(process.env.DSH_REMOTE_PORTEE)
    const entree = {
      token: nouveau,
      portee: porteeNouvelle,
      creeLe: maintenant,
      nom: nomDAppareil(corps?.nom),
    }
    try {
      // L'ECRITURE DANS LE COFFRE PUIS LA MEMOIRE : c'est le registre qui fait les
      // deux, dans cet ordre, et qui refuse si le coffre n'a pas ecrit (un appareil
      // garde en memoire mais absent du coffre disparaitrait au redemarrage).
      await ajouter(entree)
    } catch (erreur) {
      envoyer(res, 500, { erreur: 'ecriture du registre impossible', detail: String(erreur?.message ?? erreur) })
      return tracer(req, 500)
    }
    // Le nom de l'appareil est TRACE (il sert a designer l'appareil qu'on vient
    // d'appairer) ; le jeton ne l'est jamais, et le code non plus.
    tracer(req, 200, 'echange ' + entree.nom)
    res.writeHead(200, {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    })
    res.end(
      JSON.stringify({
        protocole: VERSION_PROTOCOLE,
        jeton: nouveau,
        portee: porteeNouvelle,
        nom: entree.nom,
        creeLe: entree.creeLe,
      }),
    )
  }

  /** LES APPAREILS APPAIRÉS — des empreintes, jamais des jetons. */
  const repondreAppareils = (req, res) => {
    envoyer(res, 200, {
      protocole: VERSION_PROTOCOLE,
      appareils: registre.liste().map((entree) => ({
        nom: entree.nom,
        portee: entree.portee,
        creeLe: entree.creeLe,
        empreinte: empreinteDe(entree.token),
        historique: entree.historique === true,
      })),
    })
    tracer(req, 200, registre.nombre() + ' appareils')
  }

  /**
   * RÉVOQUER UN APPAREIL — par sa seule EMPREINTE.
   *
   * POURQUOI ON DÉSIGNE PAR EMPREINTE, ET PAS PAR NOM. Deux appareils peuvent
   * porter le même nom (« iPhone »), et révoquer « le premier qui ressemble »
   * révoquerait le mauvais. L'empreinte est unique, elle est affichée dans la
   * liste, et elle ne permet pas de reconstruire le jeton.
   *
   * POURQUOI LA RÉVOCATION PASSE PAR LA SESSION NAVIGATEUR, et non par un jeton
   * d'appareil : un porteur de jeton ne doit pas pouvoir expulser les autres. Le
   * humain devant l'interface, lui, le peut — c'est le même geste que frapper un
   * code. Ce que cela coûte est écrit au README : qui obtient la session
   * navigateur (donc, aujourd'hui, qui obtient le cookie) peut révoquer des
   * appareils — un déni de service sur ses propres appareils, jamais une fuite.
   */
  const repondreRevocation = async (req, res, corps) => {
    const empreinte = typeof corps?.empreinte === 'string' ? corps.empreinte.trim().toLowerCase() : ''
    // TOUTE LA DÉCISION — empreinte mal formée, appareil inconnu, jeton historique
    // qui se SUPPRIME au lieu de se filtrer, coffre sans `deleteRecord` — vit dans
    // le registre, où elle est éprouvée seule. La route ne fait que traduire un
    // résultat en statut HTTP : c'est ce qui garantit que les deux moitiés de
    // cette règle ne peuvent pas diverger.
    const resultat = await retirer(empreinte)
    if (resultat.ok !== true) {
      envoyer(res, resultat.code, resultat.corps)
      return tracer(req, resultat.code)
    }
    envoyer(res, 200, {
      protocole: VERSION_PROTOCOLE,
      revoque: true,
      nom: resultat.nom,
      restants: resultat.restants,
    })
    // Le nom de l'appareil est trace — il sert a designer ce qu'on vient de
    // revoquer ; le jeton ne l'est jamais.
    tracer(req, 200, 'revoque ' + resultat.nom)
  }

  return {
    frappe: repondreFrappe,
    echange: repondreEchange,
    appareils: repondreAppareils,
    revocation: repondreRevocation,
  }
}
