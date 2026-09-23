import Foundation

/// L'instantané publié pour les widgets iOS et macOS.
///
/// POURQUOI CE TYPE EXISTE. Le widget s'exécute dans un processus séparé
/// (WidgetKit Extension), sans accès à la mémoire vive de l'application.
/// RÈGLE #0 : aucun secret (ni jeton, ni cookie) n'est jamais écrit ici.
/// Seules des données d'affichage nettoyées y figurent.
public struct InstantaneWidget: Codable, Sendable, Equatable {
  public let dateMiseAJour: Date
  public let nomServeur: String
  public let adresseServeur: String
  public let estConnecte: Bool
  public let nombreSessionsActives: Int
  public let nombreSessionsAuTravail: Int
  public let derniereSession: SommaireSessionWidget?

  public init(
    dateMiseAJour: Date = Date(),
    nomServeur: String,
    adresseServeur: String,
    estConnecte: Bool,
    nombreSessionsActives: Int,
    nombreSessionsAuTravail: Int,
    derniereSession: SommaireSessionWidget? = nil
  ) {
    self.dateMiseAJour = dateMiseAJour
    self.nomServeur = nomServeur
    self.adresseServeur = adresseServeur
    self.estConnecte = estConnecte
    self.nombreSessionsActives = nombreSessionsActives
    self.nombreSessionsAuTravail = nombreSessionsAuTravail
    self.derniereSession = derniereSession
  }

  /// Aperçu statique utilisé pour les placeholders et les prévisualisations.
  public static var apercu: InstantaneWidget {
    InstantaneWidget(
      dateMiseAJour: Date(),
      nomServeur: "Mac Studio",
      adresseServeur: "mac-studio.local:8080",
      estConnecte: true,
      nombreSessionsActives: 3,
      nombreSessionsAuTravail: 1,
      derniereSession: SommaireSessionWidget(
        identifiant: "session-demo-123",
        titre: "Refonte DSH Remote",
        espaceNom: "dsh-plugins",
        etat: "en_cours",
        derniereEtape: "Exécution de grep_search",
        dateDerniereActivite: Date()
      )
    )
  }

  /// État vide lorsque l'application n'est pas encore configurée ou connectée.
  public static var vide: InstantaneWidget {
    InstantaneWidget(
      dateMiseAJour: Date(),
      nomServeur: "DSH",
      adresseServeur: "",
      estConnecte: false,
      nombreSessionsActives: 0,
      nombreSessionsAuTravail: 0,
      derniereSession: nil
    )
  }
}

/// Résumé léger d'une session, adapté à l'espace restreint d'un widget.
public struct SommaireSessionWidget: Codable, Sendable, Equatable {
  public let identifiant: String
  public let titre: String
  public let espaceNom: String
  public let etat: String
  public let derniereEtape: String?
  public let dateDerniereActivite: Date

  public init(
    identifiant: String,
    titre: String,
    espaceNom: String,
    etat: String,
    derniereEtape: String? = nil,
    dateDerniereActivite: Date = Date()
  ) {
    self.identifiant = identifiant
    self.titre = titre
    self.espaceNom = espaceNom
    self.etat = etat
    self.derniereEtape = derniereEtape
    self.dateDerniereActivite = dateDerniereActivite
  }

  /// URL de lien profond pour ouvrir directement cette session dans l'app
  public var urlDeepLink: URL? {
    URL(string: "dshremote://session/\(identifiant)")
  }
}
