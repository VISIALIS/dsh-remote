import WidgetKit
import SwiftUI
import DSHRemoteKit

/// Définition du widget principal DSH Remote.
public struct DSHRemoteWidget: Widget {
  public static let genre = "DSHRemoteWidget"

  public init() {}

  public var body: some WidgetConfiguration {
    StaticConfiguration(kind: Self.genre, provider: FournisseurTimeline()) { entree in
      VueConteneurWidget(instantane: entree.instantane)
    }
    .configurationDisplayName(L("DSH Remote"))
    .description(L("Affiche l'état du serveur DeepSeek Harness et les sessions en cours."))
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

/// Vue conteneur aiguillant vers la taille appropriée.
struct VueConteneurWidget: View {
  @Environment(\.widgetFamily) var famille
  let instantane: InstantaneWidget

  var body: some View {
    switch famille {
    case .systemMedium:
      VueWidgetMedium(instantane: instantane)
    default:
      VueWidgetSmall(instantane: instantane)
    }
  }
}
