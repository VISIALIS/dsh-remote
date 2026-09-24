import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Client du plugin hôte `dsh-remote`.
///
/// Il ne connaît QUE le protocole documenté dans le README du plugin : aucune
/// API interne du harness n'est devinée ici. C'est la contrepartie du choix
/// d'architecture — le serveur porte la connaissance du harness, le client porte
/// celle du protocole, et la frontière entre les deux est un JSON versionné.
public actor RemoteClient {
  private let base: URL
  private let jeton: String
  private let session: URLSession

  /// LA DERNIÈRE LISTE DES SESSIONS, ET L'EMPREINTE QUI LA DÉCRIT.
  ///
  /// POURQUOI CE CLIENT EN GARDE UNE COPIE. L'application relit la liste toutes
  /// les trois secondes ; l'hôte, lui, retransmettait 172 sessions × ~685 octets,
  /// soit environ **115 Kio par appel** — mesuré sur cette installation. Rien ne
  /// justifie de faire voyager dix fois par minute un contenu qui n'a pas bougé,
  /// surtout sur un iPhone en radio.
  ///
  /// COMMENT ÇA MARCHE, ET POURQUOI LA GARDE EST ICI. Le client envoie
  /// `If-None-Match` avec l'empreinte de sa copie ; si l'hôte répond `304`, il
  /// rend la copie **sans rien redécoder**. La mémoire est IN-MEMORY et par
  /// client : rien n'est écrit sur disque (un journal de session n'a rien à y
  /// faire), et un client neuf — donc une machine ou un jeton différents — ne
  /// peut pas hériter de la liste d'un autre.
  ///
  /// À QUOI SERT `sessionsInchangees`, ALORS QUE LA LISTE SUFFIRAIT : à rendre
  /// l'économie VISIBLE et éprouvable. Sans lui, un `304` et un `200` identique
  /// seraient indiscernables depuis le modèle, et aucun test ne pourrait dire si
  /// l'hôte a réellement répondu « rien n'a changé ».
  private var sessionsConnues: ListeSessions?
  private var empreinteSessions: String?
  /// Nombre de réponses `304` reçues pour la liste — un compteur d'observation,
  /// pas un état de l'application.
  public private(set) var sessionsInchangees = 0

  /// - Parameters:
  ///   - adresse: racine du serveur, par exemple `http://127.0.0.1:3080` ou le
  ///     nom MagicDNS du tailnet. Le schéma et l'hôte sont validés.
  ///   - jeton: le jeton d'appareil, lu une fois dans le coffre du Mac.
  ///   - delai: délai d'une requête, en secondes. Vingt secondes par défaut —
  ///     assez pour un tailnet lent. La SONDER de découverte passe un délai
  ///     court : elle interroge des machines dont on ne sait rien, et une
  ///     machine éteinte ne doit pas figer la liste pendant vingt secondes.
  ///   - configuration: réservé aux TESTS, qui ont besoin d'un protocole
  ///     d'URL bouchonné pour observer ce qui part réellement sur le fil —
  ///     l'en-tête conditionnel, et ce qu'un `304` devient côté appelant. Le
  ///     laisser `nil` en production, où la configuration est construite ici.
  public init(adresse: String, jeton: String, delai: TimeInterval = 20, configuration: URLSessionConfiguration? = nil)
    throws
  {
    let normalisee = RemoteClient.normaliser(adresse)
    guard let url = URL(string: normalisee), let schema = url.scheme, let hote = url.host else {
      throw ErreurRemote.adresseInvalide(adresse)
    }
    guard schema == "http" || schema == "https" else {
      throw ErreurRemote.adresseInvalide("schéma « \(schema) » non supporté")
    }
    guard !hote.isEmpty else { throw ErreurRemote.adresseInvalide("hôte vide") }
    // Un jeton sur du HTTP clair vers une IP publique quitte le tailnet. La
    // sonde, elle, n'a pas de jeton : elle peut encore interroger l'adresse.
    if schema == "http", !jeton.isEmpty, ExceptionATS.hoteEnClairExpose(hote) {
      throw ErreurRemote.adresseInvalide(
        "HTTP clair vers une adresse publique : le jeton d'appareil partirait en clair. Utilisez https, ou une adresse de tailnet, de réseau privé, ou de boucle locale."
      )
    }
    self.base = url
    self.jeton = jeton

    // LA CONFIGURATION VIENT DU PARAMÈTRE QUAND ELLE EST FOURNIE (tests), sinon
    // de la fabrique PARTAGÉE avec le flux (`ConfigurationReseau`) : le client
    // HTTP et la socket temps réel doivent porter les mêmes règles de cache, de
    // cookie et d'attente du réseau — elles ont divergé une fois, et le flux n'y
    // avait pas gagné.
    let config = configuration ?? ConfigurationReseau.pourRequetes(delai: delai)
    self.session = URLSession(configuration: config)
  }

  /// Complète une adresse saisie sans protocole.
  ///
  /// POURQUOI. Personne n'écrit `http://` en recopiant un nom d'hôte : le
  /// propriétaire a saisi un nom d'hôte sans schéma, et le client l'a refusé
  /// faute de protocole. Exiger une syntaxe que personne
  /// n'emploie naturellement, c'est rejeter une saisie correcte. On suppose
  /// donc `http`, qui est le seul schéma que `tailscale serve` publie.
  ///
  /// `https://` reste honoré tel quel, et un `://` déjà présent n'est jamais
  /// réécrit.
  public static func normaliser(_ adresse: String) -> String {
    let propre = adresse.trimmingCharacters(in: .whitespacesAndNewlines)
    if propre.isEmpty { return propre }
    if propre.contains("://") { return propre }
    return "http://" + propre
  }

  private func url(_ chemin: String) -> URL {
    var composants = URLComponents(url: base, resolvingAgainstBaseURL: false)
    composants?.path = chemin
    return composants?.url ?? base.appendingPathComponent(chemin)
  }

  private func requete(_ chemin: String, methode: String, corps: Data?) throws -> URLRequest {
    var requete = URLRequest(url: url(chemin))
    requete.httpMethod = methode
    // UN PORTEUR VIDE N'EST PAS POSÉ, ET CE N'EST PAS UN DÉTAIL. La sonde de
    // découverte interroge des machines qui ne sont PAS la cible : leur envoyer
    // le jeton de la cible ferait voyager un secret vers des hôtes qui n'en ont
    // aucun besoin — alors qu'un `401` prouve déjà que DSH y répond (voir
    // `Sonde`). Un en-tête `Bearer ` vide, lui, serait un porteur MAL FORMÉ : on
    // n'en pose donc aucun, et la route répond son `401` fixe sans rien lire.
    if !jeton.isEmpty {
      requete.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")
    }
    requete.setValue("application/json", forHTTPHeaderField: "Accept")
    // Délibérément AUCUN en-tête `Origin` : le serveur refuse en 403 toute
    // requête qui en porte un, et c'est cette barrière qui bloque les
    // navigateurs. En ajouter un ici casserait l'accès.
    if let corps {
      requete.httpBody = corps
      requete.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    return requete
  }

  /// - Parameter echange: `true` UNIQUEMENT pour la route d'échange d'un code
  ///   d'appairage. Là, et là seulement, un `404` veut dire « ce plugin ne
  ///   connaît pas la route ». Ailleurs, un `404` veut dire « cette session
  ///   n'existe pas » : les confondre affichait « votre plugin est trop ancien »
  ///   à quelqu'un qui avait demandé un journal supprimé — un remède faux, qui
  ///   envoie mettre à jour un plugin alors qu'il n'y a rien à mettre à jour.
  ///
  /// Rend AUSSI la réponse HTTP, et pas seulement son corps : c'est elle qui
  /// porte l'`ETag` dont la liste des sessions a besoin pour ne plus voyager
  /// entière à chaque tour.
  private func executerAvecReponse(_ requete: URLRequest, echange: Bool = false) async throws -> (Data, HTTPURLResponse) {
    let donnees: Data
    let reponse: URLResponse
    do {
      (donnees, reponse) = try await session.data(for: requete)
    } catch {
      // On remonte le CODE et le domaine de l'erreur, pas seulement son texte.
      // Un « connexion au serveur impossible » générique ne permet pas de
      // distinguer un refus App Transport Security d'un DNS injoignable ou
      // d'un délai dépassé — et ces trois causes demandent des corrections
      // opposées. C'est ce qui a rendu la première panne si longue à situer.
      let ns = error as NSError
      var detail = "\(ns.domain) \(ns.code)"
      if let url = ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
        detail += " vers \(url.host ?? "?")"
      }
      let sous = ns.userInfo[NSUnderlyingErrorKey] as? NSError
      if let sous { detail += " | sous-jacent: \(sous.domain) \(sous.code) \(sous.localizedDescription)" }
      else { detail += " | \(ns.localizedDescription)" }
      if ns.code == NSURLErrorAppTransportSecurityRequiresSecureConnection {
        detail += " | CAUSE: App Transport Security refuse le clair vers cet hote"
        // DEUX CAUSES POSSIBLES, ET UNE SEULE SE REPARE.
        //
        // Mesure : un `xcodebuild` sur un DerivedData REUTILISE produit un paquet
        // SANS exception ATS — la phase du projet se declare pourtant executee.
        // Tous les serveurs passent alors en « pas de DSH », chaque sonde vers un
        // nom du tailnet etant refusee ici. Le paquet lui-meme ne peut pas le
        // deviner, mais il peut le DIRE : sans cette ligne, l'utilisateur cherche
        // une panne reseau, ou soupconne son jeton.
        detail +=
          " | VERIFIER: domaine absent de Config/DomaineTailnet, ou paquet construit sans l'exception"
          + " (utiliser Scripts/construire-app-ios.sh, qui la pose ET la verifie)"
      }
      if ns.code == NSURLErrorCannotFindHost { detail += " | CAUSE: nom d'hote non resolu" }
      if ns.code == NSURLErrorCannotConnectToHost { detail += " | CAUSE: rien n'ecoute sur cet hote et ce port" }
      if ns.code == NSURLErrorTimedOut {
        detail += " | CAUSE: delai depasse, hote injoignable"
        // Le meme code a DEUX causes que l'on confondait : un Mac eteint, et un
        // iPhone dont la radio s'est rendormie. La seconde se voit dans les
        // traces (`ping` qui saute de 6 ms a 400 ms) et se distingue ici par le
        // fait que le service, lui, repond.
        detail += " | SI le service repond par ailleurs: veille Wi-Fi de l'appareil, reessayer"
      }
      throw ErreurRemote.transport(detail)
    }
    guard let http = reponse as? HTTPURLResponse else {
      throw ErreurRemote.transport("réponse sans statut HTTP")
    }
    // `304` EST UN SUCCÈS, ET PAS UN STATUT INATTENDU. Il n'est pas dans
    // `200...299`, donc le laisser tomber dans le `throw` ci-dessous rendait la
    // réponse conditionnelle inexploitable : la liste était bien marquée
    // inchangée par l'hôte, et le client la refusait comme une panne. C'est
    // l'appelant qui sait s'il a une copie à ressortir — pas cette fonction, qui
    // ne fait que rendre ce que le serveur a dit.
    if (200...299).contains(http.statusCode) || http.statusCode == 304 { return (donnees, http) }
    throw RemoteClient.erreur(pour: http.statusCode, donnees: donnees, echange: echange)
  }

  /// Le corps seul, quand la réponse n'a rien à dire de plus.
  private func executer(_ requete: URLRequest, echange: Bool = false) async throws -> Data {
    try await executerAvecReponse(requete, echange: echange).0
  }

  /// UN STATUT ET UN CORPS DEVIENNENT UNE ERREUR TYPÉE.
  ///
  /// POURQUOI CETTE FONCTION EST PURE, ET POURQUOI ELLE EXISTE. Le choix du type
  /// d'erreur décide du MESSAGE, et le message décide du REMÈDE. Il était noyé
  /// dans une méthode qui parle au réseau : on ne pouvait donc l'éprouver qu'en
  /// montant un serveur. Ici, deux `Data` suffisent — et c'est ce qui permet de
  /// tenir le contrat avec le plugin, qui écrit la raison dans le corps.
  ///
  /// LE CAS QUI L'A RENDUE NÉCESSAIRE : l'hôte refuse en **403** aussi bien une
  /// requête portant `Origin` (anti-CSRF) qu'une écriture demandée avec un jeton
  /// en **LECTURE SEULE**. Les confondre affichait « un client natif ne doit
  /// jamais envoyer d'en-tête Origin » à quelqu'un dont le jeton lit simplement
  /// sans écrire : un message faux, donc un remède faux.
  nonisolated static func erreur(pour statut: Int, donnees: Data, echange: Bool = false) -> ErreurRemote {
    switch statut {
    case 401:
      return .jetonRefuse
    case 403:
      if let refus = try? JSONDecoder().decode(RefusEcriture.self, from: donnees),
        refus.erreur == ErreurRemote.raisonLectureSeule
      {
        return .ecritureRefusee
      }
      // LE TROISIÈME `403` DU PROTOCOLE : celui de l'échange d'un code. Deux
      // motifs, et ils se réparent de la même façon (redemander un code) — mais
      // pas comme un refus d'origine, qui est une erreur de CLIENT.
      // LE MOTIF EST GARDÉ TEL QUEL, ET LE DÉTAIL À PART : c'est le motif qui
      // identifie la cause (donc le remède traduit), le détail qui l'explique.
      // Les confondre rendrait la traduction impossible.
      if let refus = try? JSONDecoder().decode(RefusEcriture.self, from: donnees),
        let motif = refus.erreur, motif.hasPrefix("code ")
      {
        return .appairageRefuse(motif: motif, detail: refus.detail)
      }
      return .origineRefusee
    case 404 where echange:
      // Une route d'échange INCONNUE : le plugin d'en face est plus ancien que
      // cette application. Le `where` n'est pas une coquetterie : sur les AUTRES
      // routes, un `404` veut dire « session inconnue », et le corps le dit
      // (`{"erreur":"session inconnue"}`) — il tombe donc dans le cas par défaut,
      // qui décode le motif. Sans cette condition, un journal supprimé affichait
      // « mettez le plugin à jour ».
      return .appairageNonSupporte
    default:
      // L'hôte joint un motif STRUCTURÉ à ses refus (`erreur`, `code`, `detail`).
      // Le perdre ici transformerait « aucun modèle n'est choisi pour cette
      // session » en « HTTP 409 », c'est-à-dire en message que l'utilisateur ne
      // peut pas suivre. On décode donc le corps avant de renoncer.
      if let refus = try? JSONDecoder().decode(RefusEcriture.self, from: donnees) {
        let motif = refus.detail?.isEmpty == false ? refus.detail! : (refus.erreur ?? "refus sans motif")
        return .refusServeur(statut: statut, motif: motif, code: refus.code)
      }
      return .reponseInattendue(code: statut)
    }
  }

  private func decoder<T: Decodable>(_ type: T.Type, depuis donnees: Data) throws -> T {
    do {
      return try JSONDecoder().decode(type, from: donnees)
    } catch {
      throw ErreurRemote.decodage(String(describing: error))
    }
  }

  /// ÉCHANGE UN CODE D'APPAIRAGE contre un jeton propre à cet appareil.
  ///
  /// LE CODE EST LE PORTEUR : c'est la seule requête de ce client qui s'exécute
  /// avant qu'un jeton existe. Le corps porte le NOM de l'appareil, borné par
  /// l'hôte (il finit dans une liste que l'humain lit pour décider quoi révoquer).
  public func echangerAppairage(nom: String) async throws -> AppareilAppaire {
    let corps = try JSONSerialization.data(withJSONObject: ["nom": nom])
    let donnees = try await executer(
      try requete("/dsh-remote/v1/appairage/echange", methode: "POST", corps: corps), echange: true)
    let appareil = try decoder(AppareilAppaire.self, depuis: donnees)
    guard appareil.protocole == versionProtocoleSupportee else {
      throw ErreurRemote.versionIncompatible(recue: appareil.protocole, supportee: versionProtocoleSupportee)
    }
    return appareil
  }

  /// Vérifie que le serveur parle une version que ce client sait lire.
  @discardableResult
  public func verifierSante() async throws -> Sante {
    let donnees = try await executer(try requete("/dsh-remote/v1/sante", methode: "GET", corps: nil))
    let sante = try decoder(Sante.self, depuis: donnees)
    guard sante.protocole == versionProtocoleSupportee else {
      throw ErreurRemote.versionIncompatible(recue: sante.protocole, supportee: versionProtocoleSupportee)
    }
    return sante
  }

  /// Liste les sessions présentes sur disque, de la plus récente à la plus ancienne.
  ///
  /// CONDITIONNELLE QUAND ELLE PEUT L'ÊTRE. La seconde lecture — celle du suivi,
  /// toutes les trois secondes — porte l'empreinte de la liste déjà reçue. Si
  /// l'hôte répond `304`, sa copie est rendue telle quelle : rien n'a voyagé, et
  /// rien n'a été redécodé. Un hôte plus ancien, qui ne pose pas d'`ETag`, répond
  /// `200` comme avant — cette méthode ne l'exige pas, elle en profite.
  ///
  /// LA COPIE EST CONSERVÉE MÊME SI L'APPELANT LA JETTE. Un `304` ne dit pas
  /// « voici la liste », il dit « celle que tu as envoyée est encore bonne » :
  /// sans la copie, le client n'aurait rien à rendre. Elle ne vit qu'en mémoire,
  /// et meurt avec le client — donc avec le changement de cible.
  public func listerSessions(limite: Int? = nil) async throws -> ListeSessions {
    let corps: Data?
    if let limite {
      corps = try? JSONSerialization.data(withJSONObject: ["limite": limite])
    } else {
      corps = nil
    }
    var demande = try requete("/dsh-remote/v1/sessions", methode: corps == nil ? "GET" : "POST", corps: corps)
    // La comparaison se fait EXACTEMENT sur l'empreinte reçue : c'est un `ETag`
    // fort, donc deux empreintes égales désignent le même contenu.
    if let empreinteSessions {
      demande.setValue(empreinteSessions, forHTTPHeaderField: "If-None-Match")
    }
    let (donnees, http) = try await executerAvecReponse(demande)
    if http.statusCode == 304 {
      guard let connue = sessionsConnues else {
        // Un `304` sans copie locale : le client ne PEUT pas répondre. Le dire
        // vaut mieux que rendre une liste vide — qui se lirait « aucune session »
        // — et mieux qu'un `200` rejoué avec un corps qui n'existe pas.
        throw ErreurRemote.nonModifie
      }
      sessionsInchangees += 1
      return connue
    }
    let liste = try decoder(ListeSessions.self, depuis: donnees)
    sessionsConnues = liste
    // Un hôte antérieur à l'empreinte n'en pose aucune : on oublie la précédente
    // plutôt que de garder une copie que plus rien ne valide.
    empreinteSessions = http.value(forHTTPHeaderField: "ETag")
    return liste
  }

  /// Demande à l'hôte la liste des Macs qu'il voit sur son tailnet.
  ///
  /// POURQUOI CE N'EST PAS LE CLIENT QUI DÉCOUVRE. Une application iOS ne peut
  /// pas exécuter de processus, et le socket LocalAPI de l'application Tailscale
  /// n'est pas lisible depuis un autre bac à sable : l'iPhone ne PEUT PAS
  /// découvrir le tailnet. L'hôte, lui, tourne sur un Mac qui a Tailscale. Le
  /// Mac découvre donc, et l'application lit le résultat.
  ///
  /// Une liste vide est une réponse NORMALE, pas une erreur : `diagnostic` dit
  /// alors pourquoi, et la saisie manuelle reste disponible.
  public func listerServeurs() async throws -> ListeServeurs {
    let donnees = try await executer(try requete("/dsh-remote/v1/serveurs", methode: "GET", corps: nil))
    return try decoder(ListeServeurs.self, depuis: donnees)
  }

  /// Demande à l'hôte ses espaces de travail, **y compris ceux sans session**.
  ///
  /// L'application déduisait ses espaces des sessions : un dossier enregistré
  /// mais encore vide n'apparaissait donc pas, alors que l'interface web
  /// l'affiche. L'ordre rendu est celui du registre de l'hôte — par date de
  /// création décroissante — et le client le conserve tel quel.
  public func listerEspaces() async throws -> ListeEspaces {
    let donnees = try await executer(try requete("/dsh-remote/v1/espaces", methode: "GET", corps: nil))
    return try decoder(ListeEspaces.self, depuis: donnees)
  }

  /// Lit une page du journal d'une session.
  public func lireSession(_ identifiant: String, demande: DemandeJournal = DemandeJournal()) async throws
    -> JournalSession
  {
    let encodeur = JSONEncoder()
    let corps = try encodeur.encode(demande)
    let chemin = "/dsh-remote/v1/session/" + identifiant
    let donnees = try await executer(try requete(chemin, methode: "POST", corps: corps))
    return try decoder(JournalSession.self, depuis: donnees)
  }

  /// Adresse un prompt à une session — la SEULE opération de ce client qui écrit.
  ///
  /// REPRENDRE UNE SESSION FROIDE EST NORMAL. L'hôte résout la session ou la
  /// reprend lui-même (même politique que l'interface web) : appeler cette
  /// méthode sur une session fermée depuis hier fonctionne. La réponse porte
  /// `reprise` pour que l'interface puisse l'annoncer, car une reprise prend
  /// quelques secondes.
  ///
  /// IDEMPOTENCE. `demande.requestId` est l'identité de l'envoi : rejouer la
  /// MÊME demande après une coupure réseau rend l'acceptation d'origine sans
  /// insérer un second message. Le client doit donc conserver l'identifiant
  /// jusqu'à l'acquittement, et ne pas en tirer un nouveau à chaque tentative.
  public func envoyerPrompt(_ identifiant: String, demande: DemandePrompt) async throws -> ReponsePrompt {
    let corps = try JSONEncoder().encode(demande)
    let chemin = "/dsh-remote/v1/session/" + identifiant + "/prompt"
    let donnees = try await executer(try requete(chemin, methode: "POST", corps: corps))
    return try decoder(ReponsePrompt.self, depuis: donnees)
  }

  /// Interrompt le tour en cours d'une session.
  ///
  /// La file d'attente est CONSERVÉE : ce qui n'a pas encore été traité reste
  /// en attente. Une session froide est refusée en `session/not-found` — il n'y
  /// a rien à interrompre.
  public func annuler(_ identifiant: String) async throws -> ReponseAnnulation {
    let chemin = "/dsh-remote/v1/session/" + identifiant + "/annuler"
    let donnees = try await executer(try requete(chemin, methode: "POST", corps: nil))
    return try decoder(ReponseAnnulation.self, depuis: donnees)
  }
}
