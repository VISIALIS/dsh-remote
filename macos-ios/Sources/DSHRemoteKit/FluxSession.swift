import Foundation

/// Un message du flux temps réel.
///
/// Le flux est repris-safe : `dernierSeq` permet de se reconnecter sans recevoir
/// deux fois ce que le client possède déjà. C'est la raison d'être du champ, et
/// non un ornement.
public enum MessageFlux: Sendable {
  case base(session: ResumeSession, enregistrements: [EnregistrementJournal], dernierSeq: Int?)
  case evenement(EnregistrementJournal)
  case delta(dernierSeq: Int?)
  case tronque(message: String)
  case erreur(message: String)
}

/// Structure d'un message sur le fil, décodée avec `convertFromSnakeCase` pour
/// rester indifférente à la casse des clés.
private struct MessageFluxBrut: Decodable {
  let type: String
  let message: String?
  let dernierSeq: Int?
  let session: ResumeSession?
  let enregistrements: [EnregistrementJournal]?
  let enregistrement: EnregistrementJournal?
}

/// Suit le journal d'une session en direct.
///
/// S'appuie sur `URLSessionWebSocketTask`, fourni par la plateforme : ajouter une
/// bibliothèque WebSocket tierce à une application qui détient un jeton d'accès
/// au harness serait une surface d'attaque gratuite.
public actor FluxSession {
  private let tache: URLSessionWebSocketTask
  private let session: URLSession
  private let identifiant: String
  private var dernierSeq: Int?

  /// - Parameters:
  ///   - adresse: racine du serveur (schéma `http` ou `https`).
  ///   - jeton: jeton d'appareil.
  ///   - identifiant: session à suivre.
  ///   - depuisSeq: dernier `seq` déjà connu du client, pour une reprise sans doublon.
  public init?(adresse: String, jeton: String, identifiant: String, depuisSeq: Int? = nil) {
    guard var composants = URLComponents(string: adresse) else { return nil }
    composants.scheme = composants.scheme == "https" ? "wss" : "ws"
    composants.path = "/dsh-remote/v1/flux"
    guard let url = composants.url else { return nil }

    var requete = URLRequest(url: url)
    requete.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")
    // Aucun `Origin` : le serveur refuse en 403 toute requête qui en porte un.

    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    configuration.httpCookieAcceptPolicy = .never
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    let session = URLSession(configuration: configuration)
    self.session = session
    self.tache = session.webSocketTask(with: requete)
    self.dernierSeq = depuisSeq
    self.identifiant = identifiant
  }

  /// Dernier `seq` observé, à conserver pour une reprise.
  public var sequenceConnue: Int? { dernierSeq }

  /// Ouvre le flux et rend les messages au fil de l'eau.
  ///
  /// La séquence se termine quand le socket se ferme ; l'appelant décide s'il
  /// rouvre avec `depuisSeq: flux.sequenceConnue` pour rattraper sans doublon.
  public func messages() -> AsyncStream<MessageFlux> {
    let tache = self.tache
    let identifiant = self.identifiant
    let depuisSeq = self.dernierSeq

    return AsyncStream { continuation in
      tache.resume()
      // `depuisSeq` est ce qui rend la reprise non destructive : sans lui, une
      // reconnexion renverrait au client des evenements qu'il possede deja.
      let demande: String
      if let depuisSeq {
        demande = #"{"type":"demarrer","session":"\#(identifiant)","depuisSeq":\#(depuisSeq)}"#
      } else {
        demande = #"{"type":"demarrer","session":"\#(identifiant)"}"#
      }
      tache.send(.string(demande)) { _ in }

      let lecture = Task { [weak self, tache] in
        while !Task.isCancelled {
          do {
            let message = try await tache.receive()
            guard let self else { break }
            switch message {
            case let .string(texte):
              if let decode = await self.decoder(texte) {
                await self.noterSiBesoin(decode)
                continuation.yield(decode)
              }
            case let .data(donnees):
              if let texte = String(data: donnees, encoding: .utf8),
                let decode = await self.decoder(texte)
              {
                await self.noterSiBesoin(decode)
                continuation.yield(decode)
              }
            @unknown default:
              break
            }
          } catch {
            continuation.yield(.erreur(message: error.localizedDescription))
            break
          }
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        lecture.cancel()
        tache.cancel(with: .normalClosure, reason: nil)
      }
    }
  }

  /// Ferme le flux proprement.
  public func fermer() {
    tache.cancel(with: .normalClosure, reason: nil)
    session.invalidateAndCancel()
  }

  /// Avance le curseur de reprise sur le plus grand `seq` observe.
  private func noterSiBesoin(_ message: MessageFlux) {
    switch message {
    case let .base(_, enregistrements, seq):
      let plusGrand = enregistrements.compactMap(\.seq).max()
      noter(seq ?? plusGrand)
    case let .evenement(enregistrement):
      noter(enregistrement.seq)
    case let .delta(seq):
      noter(seq)
    case .tronque, .erreur:
      break
    }
  }

  private func noter(_ seq: Int?) {
    guard let seq else { return }
    if let dernierSeq, seq <= dernierSeq { return }
    dernierSeq = seq
  }

  private func decoder(_ texte: String) -> MessageFlux? {
    guard let donnees = texte.data(using: .utf8) else { return nil }
    let decodeur = JSONDecoder()
    decodeur.keyDecodingStrategy = .convertFromSnakeCase
    guard let brut = try? decodeur.decode(MessageFluxBrut.self, from: donnees) else { return nil }
    switch brut.type {
    case "base":
      return .base(
        session: brut.session ?? ResumeSession(),
        enregistrements: brut.enregistrements ?? [],
        dernierSeq: brut.dernierSeq)
    case "evenement":
      guard let enregistrement = brut.enregistrement else { return nil }
      return .evenement(enregistrement)
    case "delta":
      return .delta(dernierSeq: brut.dernierSeq)
    case "tronque":
      return .tronque(message: brut.message ?? "fenêtre de lecture insuffisante")
    case "erreur":
      return .erreur(message: brut.message ?? "erreur du serveur")
    default:
      return nil
    }
  }
}
