import SwiftUI
import WidgetKit
import DSHRemoteKit

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// Widget pour les Live Activities et la Dynamic Island d'iOS.
public struct ActiviteSessionWidget: Widget {
  public init() {}

  public var body: some WidgetConfiguration {
    ActivityConfiguration(for: ActiviteSessionAttributes.self) { context in
      // Vue Écran verrouillé et Bannière
      VueActiviteEcranVerrouille(context: context)
    } dynamicIsland: { context in
      DynamicIsland {
        // Vue Élargie (Expanded)
        DynamicIslandExpandedRegion(.leading) {
          HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
              .font(.caption)
              .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
              Text(context.attributes.nomServeur)
                .font(.caption2)
                .foregroundStyle(.secondary)
              Text(context.attributes.projetNom.isEmpty ? L("Projet") : context.attributes.projetNom)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            }
          }
        }

        DynamicIslandExpandedRegion(.trailing) {
          VStack(alignment: .trailing, spacing: 2) {
            Text(context.state.statut == "en_cours" ? L("au travail") : L("Prêt"))
              .font(.caption2.weight(.medium))
              .foregroundStyle(context.state.statut == "en_cours" ? Color.orange : Color.green)
            Text(context.state.horodatageEtape, style: .relative)
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
        }

        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 4) {
            Text(context.attributes.sessionTitre.isEmpty ? L("(sans titre)") : context.attributes.sessionTitre)
              .font(.subheadline.weight(.medium))
              .lineLimit(1)

            if let etape = context.state.derniereEtape, !etape.isEmpty {
              HStack(spacing: 4) {
                Image(systemName: "arrow.right.circle.fill")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                Text(etape)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            }
          }
          .padding(.top, 4)
        }
      } compactLeading: {
        Image(systemName: "bolt.fill")
          .font(.caption2)
          .foregroundStyle(.orange)
      } compactTrailing: {
        Text(context.state.statut == "en_cours" ? "…" : "✓")
          .font(.caption2.weight(.bold))
          .foregroundStyle(context.state.statut == "en_cours" ? Color.orange : Color.green)
      } minimal: {
        Image(systemName: "bolt.fill")
          .font(.caption2)
          .foregroundStyle(.orange)
      }
      .widgetURL(URL(string: "dshremote://session/\(context.attributes.sessionId)"))
    }
  }
}

/// Présentation sur l'écran verrouillé et dans la bannière de notification.
struct VueActiviteEcranVerrouille: View {
  let context: ActivityViewContext<ActiviteSessionAttributes>

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // En-tête : Serveur, projet et pastille
      HStack {
        HStack(spacing: 6) {
          Image(systemName: "desktopcomputer")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text("\(context.attributes.nomServeur) • \(context.attributes.projetNom.isEmpty ? L("Projet") : context.attributes.projetNom)")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        Spacer()

        HStack(spacing: 4) {
          Circle()
            .fill(context.state.statut == "en_cours" ? Color.orange : Color.green)
            .frame(width: 8, height: 8)
          Text(context.state.statut == "en_cours" ? L("Tour en cours") : L("Terminé"))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(context.state.statut == "en_cours" ? Color.orange : Color.green)
        }
      }

      // Titre de la session
      Text(context.attributes.sessionTitre.isEmpty ? L("(sans titre)") : context.attributes.sessionTitre)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)

      // Dernière étape et horodatage relatif
      if let etape = context.state.derniereEtape, !etape.isEmpty {
        HStack(spacing: 6) {
          Image(systemName: "arrow.right.circle.fill")
            .font(.caption2)
            .foregroundStyle(.secondary)
          Text(etape)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

          Spacer()

          Text(context.state.horodatageEtape, style: .relative)
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
    }
    .padding(14)
    .widgetURL(URL(string: "dshremote://session/\(context.attributes.sessionId)"))
  }
}
#endif
