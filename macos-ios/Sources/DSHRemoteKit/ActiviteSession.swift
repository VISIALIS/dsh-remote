import Foundation

/// Décide si un relevé de Live Activity change vraiment l'affichage.
///
/// L'horloge montrée est celle du journal (`modifieLe`), pas l'instant du
/// rafraîchissement de la liste : sinon « il y a… » retombe à zéro à chaque
/// lecture, alors que l'étape n'a pas bougé.
enum ReleveDActivite {
  static var peremption: TimeInterval { InstantaneWidget.dureeDeFraicheur }

  static func horodatage(modifieLe: Double?) -> Date {
    guard let modifieLe else { return Date() }
    return Date(timeIntervalSince1970: modifieLe)
  }

  static func aChange(
    etape: String?, depuis etapeActuelle: String?, horodatage: Date, depuis horodatageActuel: Date
  ) -> Bool {
    if etape != etapeActuelle { return true }
    return abs(horodatage.timeIntervalSince(horodatageActuel)) >= 1
  }
}

#if canImport(ActivityKit) && os(iOS)
@preconcurrency import ActivityKit

/// Définition des attributs et de l'état pour les Live Activities de session d'agent.
///
/// POURQUOI CE TYPE EXISTE.
/// Permet à iOS (Dynamic Island et écran verrouillé) d'afficher l'état en direct
/// d'un tour d'agent lancé sur un Mac DSH sans obliger à garder l'application au premier plan.
/// RÈGLE #0 : aucun secret, aucun jeton, uniquement des données d'affichage.
public struct ActiviteSessionAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable, Sendable {
    public var statut: String
    public var derniereEtape: String?
    public var horodatageEtape: Date

    public init(
      statut: String,
      derniereEtape: String? = nil,
      horodatageEtape: Date = Date()
    ) {
      self.statut = statut
      self.derniereEtape = derniereEtape
      self.horodatageEtape = horodatageEtape
    }
  }

  public var sessionId: String
  public var sessionTitre: String
  public var projetNom: String
  public var nomServeur: String

  public init(
    sessionId: String,
    sessionTitre: String,
    projetNom: String,
    nomServeur: String
  ) {
    self.sessionId = sessionId
    self.sessionTitre = sessionTitre
    self.projetNom = projetNom
    self.nomServeur = nomServeur
  }
}

/// Gestionnaire du cycle de vie des Live Activities sur iOS.
@MainActor
public final class GestionnaireActivitesLive {
  public static let shared = GestionnaireActivitesLive()

  private var activiteEnCours: Activity<ActiviteSessionAttributes>?

  public init() {}

  /// Met à jour ou démarre une Live Activity si une session est au travail.
  public func synchroniser(
    session: SessionListee?,
    nomServeur: String,
    derniereEtape: String? = nil,
    horodatageEtape: Date = Date()
  ) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

    guard let session, session.statut == "en_cours" else {
      arreter()
      return
    }

    let peremption = Date().addingTimeInterval(ReleveDActivite.peremption)
    let nouvelEtat = ActiviteSessionAttributes.ContentState(
      statut: "en_cours",
      derniereEtape: derniereEtape,
      horodatageEtape: horodatageEtape
    )

    if let existante = activiteEnCours, existante.attributes.sessionId == session.id {
      let actuel = existante.content.state
      // L'application est encore là : on repousse la péremption. L'horloge ne
      // bouge que si l'étape ou la date du journal a changé.
      let etat = ReleveDActivite.aChange(
        etape: derniereEtape,
        depuis: actuel.derniereEtape,
        horodatage: horodatageEtape,
        depuis: actuel.horodatageEtape
      ) ? nouvelEtat : actuel
      Task {
        await existante.update(ActivityContent(state: etat, staleDate: peremption))
      }
    } else {
      arreter()
      let attributs = ActiviteSessionAttributes(
        sessionId: session.id,
        sessionTitre: session.titreAffiche,
        projetNom: session.projet ?? session.dossier ?? "",
        nomServeur: nomServeur
      )
      do {
        activiteEnCours = try Activity.request(
          attributes: attributs,
          content: ActivityContent(state: nouvelEtat, staleDate: peremption)
        )
      } catch {
        // En cas de refus système ou quota dépassé, on continue sans bloquer l'app.
      }
    }
  }

  /// Clôture la Live Activity en cours avec un court délai de dissipation.
  public func arreter() {
    guard let activite = activiteEnCours else { return }
    activiteEnCours = nil
    Task {
      let etatFinal = ActiviteSessionAttributes.ContentState(
        statut: "terminee",
        derniereEtape: nil,
        horodatageEtape: Date()
      )
      await activite.end(
        ActivityContent(state: etatFinal, staleDate: Date().addingTimeInterval(3)),
        dismissalPolicy: .after(Date().addingTimeInterval(3))
      )
    }
  }
}
#else
/// Repli no-op pour macOS et plateformes sans ActivityKit.
@MainActor
public final class GestionnaireActivitesLive {
  public static let shared = GestionnaireActivitesLive()
  public init() {}
  public func synchroniser(
    session: SessionListee?, nomServeur: String, derniereEtape: String? = nil, horodatageEtape: Date = Date()
  ) {
    _ = (session, nomServeur, derniereEtape, horodatageEtape)
  }
  public func arreter() {}
}
#endif
