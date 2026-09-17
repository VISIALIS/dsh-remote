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
  /// Un changement de statut d'agent poussé par l'hôte : `en_cours` / `inactif`.
  ///
  /// POURQUOI CE MESSAGE EXISTE. Les pastilles de la liste n'étaient rafraîchies
  /// que par la boucle HTTP de trois secondes ; le harness émet pourtant
  /// `agent/status` à chaque transition, et l'hôte le pousse désormais sur le flux
  /// de la session concernée. La pastille suit donc en quelques millisecondes, sans
  /// que l'application réveille sa radio pour l'apprendre.
  case statut(String)
  case tronque(message: String)
  case erreur(message: String)
}

/// Structure d'un message sur le fil, décodée avec `convertFromSnakeCase` pour
/// rester indifférente à la casse des clés.
private struct MessageFluxBrut: Decodable {
  let type: String
  let message: String?
  let statut: String?
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
///
/// POURQUOI UN BATTEMENT DE CŒUR APPLICATIF. Une connexion TCP peut mourir SANS
/// LE DIRE : la radio d'un téléphone perd les paquets, et ni la fermeture ni
/// l'erreur n'arrivent. Dans ce cas `receive()` reste suspendu — des minutes,
/// mesurées sur iOS — et l'écran affiche « En direct » sur un journal qui ne
/// recevra plus rien. Le serveur, lui, envoie un ping toutes les trente secondes
/// et la plateforme y répond toute seule ; mais RIEN ne vérifie que la réponse
/// revient, ni d'un côté ni de l'autre. Le client envoie donc le sien et EXIGE
/// son pong dans un délai court : c'est la seule preuve de vie qui ne dépende pas
/// du hasard du réseau.
public actor FluxSession {

  /// La cadence du battement de cœur, et la patience accordée au pong.
  ///
  /// POURQUOI CES VALEURS-LÀ. Quinze secondes : deux fois moins que le ping du
  /// serveur, donc une socket morte est vue en vingt secondes au pire — le temps
  /// d'un aller-retour, pas d'une minute devant un journal figé. Cinq secondes
  /// pour le pong : une radio qui se rendort met quelques centaines de
  /// millisecondes à revenir (mesuré : 412 ms), donc cinq secondes laissent
  /// largement la place à un réveil normal sans laisser passer une vraie coupure.
  ///
  /// C'EST UN TYPE, ET PAS DEUX CONSTANTES, pour une seule raison : un test qui
  /// devrait attendre quinze secondes pour éprouver une coupure ne serait pas
  /// lancé. Les valeurs de production sont le défaut ; le test passe les siennes.
  public struct Battement: Sendable, Equatable {
    public let intervalle: TimeInterval
    public let delaiPong: TimeInterval

    public init(intervalle: TimeInterval, delaiPong: TimeInterval) {
      self.intervalle = intervalle
      self.delaiPong = delaiPong
    }

    public static let parDefaut = Battement(intervalle: 15, delaiPong: 5)
  }

  private let tache: URLSessionWebSocketTask
  private let session: URLSession
  private let identifiant: String
  private let battement: Battement
  private var dernierSeq: Int?

  /// - Parameters:
  ///   - adresse: racine du serveur (schéma `http` ou `https`).
  ///   - jeton: jeton d'appareil.
  ///   - identifiant: session à suivre.
  ///   - depuisSeq: dernier `seq` déjà connu du client, pour une reprise sans doublon.
  ///   - battement: cadence du contrôle de vie (voir `Battement`).
  ///   - configuration: réservé aux TESTS, comme pour `RemoteClient`. Le laisser
  ///     `nil` en production, où la configuration vient de `ConfigurationReseau`.
  public init?(
    adresse: String, jeton: String, identifiant: String, depuisSeq: Int? = nil,
    battement: Battement = .parDefaut, configuration: URLSessionConfiguration? = nil
  ) {
    guard var composants = URLComponents(string: adresse) else { return nil }
    composants.scheme = composants.scheme == "https" ? "wss" : "ws"
    composants.path = "/dsh-remote/v1/flux"
    guard let url = composants.url else { return nil }

    var requete = URLRequest(url: url)
    requete.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")
    // Aucun `Origin` : le serveur refuse en 403 toute requête qui en porte un.

    // LA MÊME CONFIGURATION QUE LE CLIENT HTTP, À LA PATIENCE PRÈS — et cette
    // patience-là est celle de la POIGNÉE DE MAIN, pas celle du direct. Voir
    // `ConfigurationReseau.pourFlux()` : y recopier les délais d'une requête
    // couperait la socket toutes les deux minutes.
    let configuration = configuration ?? ConfigurationReseau.pourFlux()
    let session = URLSession(configuration: configuration)
    self.session = session
    self.tache = session.webSocketTask(with: requete)
    self.dernierSeq = depuisSeq
    self.identifiant = identifiant
    self.battement = battement
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
    let battement = self.battement

    return AsyncStream { continuation in
      tache.resume()
      // `depuisSeq` est ce qui rend la reprise non destructive : sans lui, une
      // reconnexion renverrait au client des evenements qu'il possede deja.
      let demande: String
      if let depuisSeq {
        demande = Self.demande(identifiant: identifiant, depuisSeq: depuisSeq)
      } else {
        demande = Self.demande(identifiant: identifiant, depuisSeq: nil)
      }

      // L'ÉCHEC DE L'ENVOI EST TRAITÉ, ET CE N'ÉTAIT PAS LE CAS. `send` était
      // appelé avec un bloc vide : quand le `demarrer` ne partait pas — socket
      // acceptée puis rompue, tampon refusé —, le serveur n'envoyait jamais rien,
      // `receive()` attendait, et l'écran affichait « En direct » sur un flux
      // muet. Un envoi qui échoue est une erreur de flux, donc une reconnexion.
      let envoi = Task { [weak self] in
        do {
          try await tache.send(.string(demande))
        } catch {
          guard let self else { return }
          await self.signaler(error.localizedDescription, a: continuation)
        }
      }

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

      // LE BATTEMENT DÉMARRE TOUT DE SUITE, ET PAS APRÈS L'ENVOI. Le faire
      // dépendre de `send` avait un défaut mesuré : sur une socket qui ne se
      // connecte pas, `send` ne rend jamais la main, donc le battement — le seul
      // mécanisme qui puisse conclure — n'aurait jamais commencé. Ici, l'échéance
      // du premier ping est la borne qui garantit qu'un flux ne reste pas muet.
      let battementTache = Task { [weak self] in
        guard let self else { return }
        await self.battre(battement, vers: continuation)
      }

      continuation.onTermination = { _ in
        envoi.cancel()
        lecture.cancel()
        battementTache.cancel()
        tache.cancel(with: .normalClosure, reason: nil)
      }
    }
  }

  /// La demande d'ouverture, ENCODÉE PAR `JSONEncoder`.
  ///
  /// POURQUOI PAS UNE INTERPOLATION DE CHAÎNE, CE QUI ÉTAIT LE CAS. Un
  /// identifiant de session est aujourd'hui un `session-<uuid>`, donc l'ancienne
  /// forme marchait par chance. Un identifiant qui contiendrait un guillemet, une
  /// barre oblique inverse ou un saut de ligne produirait un JSON invalide, ou un
  /// JSON valide décrivant AUTRE CHOSE — et la panne se lirait « session
  /// inconnue », c'est-à-dire nulle part. Le reste du client encode déjà ses
  /// corps de requête ; celui-ci le fait maintenant aussi.
  static func demande(identifiant: String, depuisSeq: Int?) -> String {
    struct Demande: Encodable {
      let type = "demarrer"
      let session: String
      let depuisSeq: Int?
    }
    let encodeur = JSONEncoder()
    // L'ordre des clés n'est pas garanti par `JSONEncoder` — et il n'a pas à
    // l'être : le serveur lit un OBJET JSON, pas une chaîne. Un test qui
    // comparerait le texte exact serait donc faux ; il décode.
    guard let donnees = try? encodeur.encode(Demande(session: identifiant, depuisSeq: depuisSeq)),
      let texte = String(data: donnees, encoding: .utf8)
    else {
      // Un identifiant encodable est une chaîne : ce chemin est inatteignable, et
      // s'il l'était, mieux vaut une demande vide — que le serveur refuse en
      // silence — qu'un plantage dans un flux temps réel.
      return #"{"type":"demarrer","session":""}"#
    }
    return texte
  }

  /// Signale une erreur de flux et ferme la séquence.
  ///
  /// Rend la main à l'appelant, qui rouvrira avec `depuisSeq` : c'est ce qui
  /// transforme une panne silencieuse en reconnexion.
  private func signaler(_ detail: String, a continuation: AsyncStream<MessageFlux>.Continuation) {
    continuation.yield(.erreur(message: detail))
    continuation.finish()
  }

  /// Envoie un ping et exige son pong dans le délai.
  ///
  /// Rend `false` quand le pong n'est pas venu à temps — la seule preuve qu'une
  /// socket est morte sans l'avoir dit.
  private func pongRecu(dans delai: TimeInterval) async -> Bool {
    let tache = self.tache
    let boite = BoiteDePong()
    return await withCheckedContinuation { (suite: CheckedContinuation<Bool, Never>) in
      boite.attendre(suite)
      tache.sendPing { erreur in boite.conclure(erreur == nil) }
      // L'ÉCHÉANCE EST TENUE PAR UNE AUTRE TÂCHE, ET C'EST NÉCESSAIRE : quand la
      // socket est morte sans le dire, `sendPing` peut ne JAMAIS appeler son
      // bloc. Une attente qui ne dépendrait que de lui serait celle qu'on vient
      // corriger — quinze minutes de `receive()` suspendu.
      Task {
        try? await Task.sleep(nanoseconds: UInt64(delai * 1_000_000_000))
        boite.conclure(false)
      }
    }
  }

  /// Le contrôle de vie : ping périodique, pong exigé.
  private func battre(_ battement: Battement, vers continuation: AsyncStream<MessageFlux>.Continuation) async {
    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: UInt64(battement.intervalle * 1_000_000_000))
      if Task.isCancelled { return }
      if await pongRecu(dans: battement.delaiPong) { continue }
      signaler("battement de coeur perdu", a: continuation)
      return
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
    case .statut, .tronque, .erreur:
      // Un statut ne porte AUCUN `seq` : ce n'est pas un enregistrement du
      // journal, seulement un fait sur l'agent. Il ne fait donc pas avancer le
      // curseur de reprise — le confondre avec un evenement ferait sauter des
      // enregistrements a la reconnexion suivante.
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
    case "statut":
      // Un statut VIDE n'est pas un statut : le type du modèle ne connaît que
      // `en_cours` et `inactif`, et un message sans valeur serait un mensonge.
      guard let statut = brut.statut, !statut.isEmpty else { return nil }
      return .statut(statut)
    case "tronque":
      return .tronque(message: brut.message ?? "fenêtre de lecture insuffisante")
    case "erreur":
      return .erreur(message: brut.message ?? "erreur du serveur")
    default:
      return nil
    }
  }
}

/// UNE BOÎTE À UN SEUL GAGNANT, POUR LE PONG.
///
/// POURQUOI ELLE EXISTE. Trois issues sont possibles pour un même ping : le pong
/// arrive, il est refusé, ou il NE VIENT JAMAIS — et l'échéance conclut à sa
/// place. Dans les trois cas la continuation doit être reprise EXACTEMENT une
/// fois, sinon le programme s'arrête (`withCheckedContinuation` refuse la double
/// reprise), et c'est précisément le cas « jamais » qu'on vient corriger. La
/// boîte est donc le seul endroit qui tranche, sous verrou.
private final class BoiteDePong: @unchecked Sendable {
  private let verrou = NSLock()
  private var suite: CheckedContinuation<Bool, Never>?
  private var conclu = false

  func attendre(_ continuation: CheckedContinuation<Bool, Never>) {
    verrou.lock()
    suite = continuation
    verrou.unlock()
  }

  func conclure(_ valeur: Bool) {
    verrou.lock()
    guard !conclu, let continuation = suite else {
      verrou.unlock()
      return
    }
    conclu = true
    suite = nil
    verrou.unlock()
    continuation.resume(returning: valeur)
  }
}
