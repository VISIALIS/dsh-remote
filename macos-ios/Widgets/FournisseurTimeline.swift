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
    let entree = EntreeWidget(date: Date(), instantane: instantane)

    // Rechargement planifié dans 15 minutes en cas d'inactivité de l'app
    let dateProchainRechargement = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
    let timeline = Timeline(entries: [entree], policy: .after(dateProchainRechargement))
    completion(timeline)
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
