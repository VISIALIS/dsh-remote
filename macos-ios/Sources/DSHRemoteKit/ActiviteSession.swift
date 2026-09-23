import Foundation

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
    derniereEtape: String? = nil
  ) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

    guard let session, session.statut == "en_cours" else {
      arreter()
      return
    }

    let nouvelEtat = ActiviteSessionAttributes.ContentState(
      statut: "en_cours",
      derniereEtape: derniereEtape,
      horodatageEtape: Date()
    )

    if let existante = activiteEnCours, existante.attributes.sessionId == session.id {
      Task {
        await existante.update(ActivityContent(state: nouvelEtat, staleDate: nil))
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
          content: ActivityContent(state: nouvelEtat, staleDate: nil)
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
        ActivityContent(state: etatFinal, staleDate: nil),
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
  public func synchroniser(session: SessionListee?, nomServeur: String, derniereEtape: String? = nil) {}
  public func arreter() {}
}
#endif
