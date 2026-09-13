import Foundation

// Écriture — les types de la SEULE partie du protocole qui MUTE l'hôte.
//
// POURQUOI CE FICHIER EXISTE. Tout le reste du client est en lecture : il
// transporte ce que le harness a déjà écrit. Ces types-ci font écrire le
// harness, et une écriture depuis un téléphone a deux propriétés qu'une lecture
// n'a pas :
//
//   - elle doit être IDEMPOTENTE. Un réseau mobile coupe, la réponse se perd, le
//     client rejoue — et sans identifiant stable, l'utilisateur se retrouve avec
//     deux fois le même message dans sa conversation. `requestId` est cet
//     identifiant : le client le CHOISIT, le conserve, et le réutilise à
//     l'identique tant que l'envoi n'a pas été acquitté.
//   - elle doit pouvoir être ANNULÉE. Écrire depuis un téléphone, c'est souvent
//     écrire pour arrêter ce qu'on a lancé ; sans annulation, il faut revenir au
//     Mac et la fonction perd son intérêt.
//
// Le succès d'une écriture n'est PAS « le modèle a répondu » : c'est « l'hôte a
// accepté le message ». La réponse du modèle arrive par le journal ou le flux,
// comme tout le reste.

/// Mode de remise d'un prompt à l'agent.
public enum ModePrompt: String, Sendable, Codable, CaseIterable {
  /// File d'attente : le message forme le prochain tour. Comportement par défaut.
  case queue
  /// Interruption : le message est remis au prochain pas du tour EN COURS.
  case steer

  public var libelle: String {
    switch self {
    case .queue: return "à la suite"
    case .steer: return "tout de suite (interrompt le tour en cours)"
    }
  }
}

/// Demande d'écriture adressée à une session.
public struct DemandePrompt: Sendable, Encodable {
  public var texte: String
  public var mode: ModePrompt
  /// Identité d'envoi. Le client la CHOISIT pour pouvoir rejouer sans doublon.
  public var requestId: String
  /// Fuseau IANA du client (`Europe/Paris`), facultatif.
  ///
  /// Il est enregistré dans la source du message et sert au modèle à situer
  /// l'heure locale de l'utilisateur. L'hôte valide la forme et refuse le reste.
  public var fuseau: String?

  public init(texte: String, mode: ModePrompt = .queue, requestId: String, fuseau: String? = nil) {
    self.texte = texte
    self.mode = mode
    self.requestId = requestId
    self.fuseau = fuseau
  }

  /// Un identifiant d'envoi neuf, à CONSERVER tant que l'envoi n'est pas acquitté.
  public static func identifiantNeuf() -> String {
    UUID().uuidString.lowercased()
  }
}

/// Accusé de réception d'un prompt.
public struct ReponsePrompt: Sendable, Decodable {
  public let protocole: Int
  /// L'hôte a accepté le message. Ce n'est PAS « le modèle a répondu ».
  public let accepte: Bool
  public let mode: String?
  public let requestId: String?
  /// `true` quand la session était froide sur l'hôte et qu'il a dû la reprendre.
  ///
  /// L'information est affichée : reprendre une session prend quelques secondes
  /// et démarre un tour, ce qui surprend si on ne l'a pas annoncé.
  public let reprise: Bool?
  public let erreur: String?
  public let detail: String?
}

/// Accusé d'annulation.
public struct ReponseAnnulation: Sendable, Decodable {
  public let protocole: Int
  public let annule: Bool
  public let erreur: String?
  public let detail: String?
}

/// Refus structuré renvoyé par l'hôte sur une écriture.
///
/// L'hôte distingue « réessayez » de « ça ne marchera jamais » par un CODE
/// stable (`session/not-found`, `session/model-unavailable`, `session/agent-busy`,
/// `session/steer-unavailable`…). Le traduire en message français ici évite que
/// chaque interface réinvente sa lecture d'un statut HTTP.
public struct RefusEcriture: Sendable, Decodable {
  public let erreur: String?
  public let code: String?
  public let detail: String?

  /// Lecture destinée à l'utilisateur, sans jargon de protocole.
  public var explication: String {
    RefusEcriture.expliquer(code: code, detail: detail, erreur: erreur)
  }

  /// Traduit un refus en phrase compréhensible.
  ///
  /// Statique pour être appelable depuis une erreur déjà levée
  /// (`ErreurRemote.refusServeur`), qui porte le code mais plus le corps JSON.
  public static func expliquer(code: String?, detail: String?, erreur: String?) -> String {
    switch code {
    case "session/not-found":
      return "cette session n'existe plus sur l'hôte"
    case "session/model-unavailable":
      return "aucun modèle n'est disponible pour cette session : choisissez-en un sur l'hôte"
    case "session/agent-busy":
      return "l'agent n'a pas pu prendre ce message maintenant"
    case "session/steer-unavailable":
      return "cette session ne peut pas être interrompue maintenant"
    case "session/invalid-time-zone":
      return "le fuseau horaire envoyé n'est pas reconnu"
    case "gateway/bad-request":
      return "l'hôte a refusé la demande"
    default:
      if let detail, !detail.isEmpty { return detail }
      return erreur ?? "l'hôte a refusé l'écriture"
    }
  }
}

/// Identité d'un envoi non encore acquitté.
///
/// POURQUOI CETTE VALEUR EXISTE, SÉPARÉE DU MODÈLE. C'est la seule règle de
/// l'écriture qui ne se voit pas à l'usage : un envoi rejoué doit porter le MÊME
/// identifiant que la tentative précédente, sinon l'hôte insère un second
/// message et la conversation affiche deux fois la même demande. Enfermée dans
/// une vue, cette règle ne serait vérifiable qu'en simulant une coupure réseau ;
/// isolée ici, elle se teste en trois lignes.
///
/// Elle est remise à zéro par l' ACQUITTEMENT, et par lui seul : un texte
/// DIFFÉRENT est un nouvel envoi, même si le précédent n'a pas abouti.
public struct EnvoiEnAttente: Equatable, Sendable {
  private var texte: String?
  private var identifiant: String?

  public init() {}

  /// L'identifiant à employer pour ce texte.
  ///
  /// Rend celui déjà en attente quand c'est le même texte — c'est tout l'intérêt :
  /// l'appelant peut réessayer autant de fois qu'il veut sans créer de doublon.
  public mutating func identifiant(pour texte: String) -> String {
    if self.texte == texte, let identifiant { return identifiant }
    let neuf = DemandePrompt.identifiantNeuf()
    self.texte = texte
    self.identifiant = neuf
    return neuf
  }

  /// L'hôte a acquitté l'envoi : l'identité n'a plus à être conservée.
  public mutating func acquitter() {
    texte = nil
    identifiant = nil
  }

  /// Y a-t-il un envoi en attente d'acquittement ?
  public var enAttente: Bool { identifiant != nil }
}
