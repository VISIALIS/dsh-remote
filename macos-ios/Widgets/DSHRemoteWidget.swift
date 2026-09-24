import WidgetKit
import SwiftUI
import DSHRemoteKit

/// Définition du widget principal DSH Remote.
public struct DSHRemoteWidget: Widget {
  public static let genre = "DSHRemoteWidget"

  public init() {}

  public var body: some WidgetConfiguration {
    StaticConfiguration(kind: Self.genre, provider: FournisseurTimeline()) { entree in
      VueConteneurWidget(instantane: entree.instantane, dateAffichee: entree.date)
    }
    .configurationDisplayName(L("DSH Remote"))
    .description(L("Affiche l'état du serveur DeepSeek Harness et les sessions en cours."))
    .supportedFamilies([.systemSmall, .systemMedium])
    .contentMarginsDisabled()
  }
}

/// Vue conteneur aiguillant vers la taille appropriée et posant le fond de conteneur.
struct VueConteneurWidget: View {
  @Environment(\.widgetFamily) var famille
  let instantane: InstantaneWidget
  let dateAffichee: Date

  var body: some View {
    Group {
      switch famille {
      case .systemMedium:
        VueWidgetMedium(instantane: instantane, dateAffichee: dateAffichee)
      default:
        VueWidgetSmall(instantane: instantane, dateAffichee: dateAffichee)
      }
    }
    .containerBackground(for: .widget) {
      #if os(macOS)
      Color(nsColor: .windowBackgroundColor)
      #else
      Color(uiColor: .systemBackground)
      #endif
    }
  }
}
