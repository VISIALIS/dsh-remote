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

  /// - Parameters:
  ///   - adresse: racine du serveur, par exemple `http://127.0.0.1:3080` ou le
  ///     nom MagicDNS du tailnet. Le schéma et l'hôte sont validés.
  ///   - jeton: le jeton d'appareil, lu une fois dans le coffre du Mac.
  public init(adresse: String, jeton: String) throws {
    let normalisee = RemoteClient.normaliser(adresse)
    guard let url = URL(string: normalisee), let schema = url.scheme, let hote = url.host else {
      throw ErreurRemote.adresseInvalide(adresse)
    }
    guard schema == "http" || schema == "https" else {
      throw ErreurRemote.adresseInvalide("schéma « \(schema) » non supporté")
    }
    guard !hote.isEmpty else { throw ErreurRemote.adresseInvalide("hôte vide") }
    self.base = url
    self.jeton = jeton

    let configuration = URLSessionConfiguration.ephemeral
    // Aucun cache : un journal de session n'a rien à faire sur disque, et une
    // réponse périmée induirait l'utilisateur en erreur.
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.urlCache = nil
    configuration.httpShouldSetCookies = false
    configuration.httpCookieAcceptPolicy = .never
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 120
    self.session = URLSession(configuration: configuration)
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
    requete.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")
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

  private func executer(_ requete: URLRequest) async throws -> Data {
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
      }
      if ns.code == NSURLErrorCannotFindHost { detail += " | CAUSE: nom d'hote non resolu" }
      if ns.code == NSURLErrorCannotConnectToHost { detail += " | CAUSE: rien n'ecoute sur cet hote et ce port" }
      if ns.code == NSURLErrorTimedOut { detail += " | CAUSE: delai depasse, hote injoignable" }
      throw ErreurRemote.transport(detail)
    }
    guard let http = reponse as? HTTPURLResponse else {
      throw ErreurRemote.transport("réponse sans statut HTTP")
    }
    switch http.statusCode {
    case 200...299:
      return donnees
    case 401:
      throw ErreurRemote.jetonRefuse
    case 403:
      throw ErreurRemote.origineRefusee
    default:
      throw ErreurRemote.reponseInattendue(code: http.statusCode)
    }
  }

  private func decoder<T: Decodable>(_ type: T.Type, depuis donnees: Data) throws -> T {
    do {
      return try JSONDecoder().decode(type, from: donnees)
    } catch {
      throw ErreurRemote.decodage(String(describing: error))
    }
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
  public func listerSessions(limite: Int? = nil) async throws -> ListeSessions {
    let corps: Data?
    if let limite {
      corps = try? JSONSerialization.data(withJSONObject: ["limite": limite])
    } else {
      corps = nil
    }
    let donnees = try await executer(
      try requete("/dsh-remote/v1/sessions", methode: corps == nil ? "GET" : "POST", corps: corps))
    return try decoder(ListeSessions.self, depuis: donnees)
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
}
