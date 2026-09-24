import WidgetKit
import SwiftUI
import DSHRemoteKit

/// Fournisseur de timeline pour le widget DSH Remote.
///
/// Lit l'instantané déposé par l'application dans le conteneur partagé App Group.
/// En cas d'inactivité de l'application, WidgetKit redemande une entrée selon la
/// politique de rechargement définie ici (15 minutes).
public struct FournisseurTimeline: TimelineProvider {
  public typealias Entry = EntreeWidget

  private let persistance: Persistance

  public init(persistance: Persistance = Persistance()) {
    self.persistance = persistance
  }

  public func placeholder(in context: Context) -> EntreeWidget {
    EntreeWidget(date: Date(), instantane: .apercu)
  }

  public func getSnapshot(in context: Context, completion: @escaping (EntreeWidget) -> Void) {
    let instantane = persistance.lireInstantaneWidget() ?? (context.isPreview ? .apercu : .vide)
    completion(EntreeWidget(date: Date(), instantane: instantane))
  }

  public func getTimeline(in context: Context, completion: @escaping (Timeline<EntreeWidget>) -> Void) {
    let instantane = persistance.lireInstantaneWidget() ?? .vide
    let maintenant = Date()
    var entrees = [EntreeWidget(date: maintenant, instantane: instantane)]
    // Deuxième entrée au moment où l'instantané devient ancien : la pastille
    // passe au gris sans attendre que le système relance l'extension.
    let bascule = instantane.dateMiseAJour.addingTimeInterval(InstantaneWidget.dureeDeFraicheur)
    if bascule > maintenant {
      entrees.append(EntreeWidget(date: bascule, instantane: instantane))
    }
    let prochaine = bascule > maintenant ? bascule : maintenant.addingTimeInterval(15 * 60)
    completion(Timeline(entries: entrees, policy: .after(prochaine)))
  }
}

/// Entrée de timeline portant l'instantané de l'application.
public struct EntreeWidget: TimelineEntry {
  public let date: Date
  public let instantane: InstantaneWidget

  public init(date: Date, instantane: InstantaneWidget) {
    self.date = date
    self.instantane = instantane
  }
}
