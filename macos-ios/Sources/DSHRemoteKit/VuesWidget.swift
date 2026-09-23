import SwiftUI

/// Vues SwiftUI pour les widgets iOS et macOS.
///
/// POURQUOI ELLES SONT DANS DSHRemoteKit.
/// Les vues de widget vivent dans la bibliothèque partagée pour pouvoir être
/// compilées à la fois pour iOS et macOS, prévisualisées dans Xcode, et
/// couvertes par les tests sans dupliquer le code de rendu dans les cibles d'extension.

/// Vue du widget au format compact (Small : carré 2x2).
public struct VueWidgetSmall: View {
  public let instantane: InstantaneWidget

  public init(instantane: InstantaneWidget) {
    self.instantane = instantane
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // En-tête : Serveur et pastille de statut
      HStack(alignment: .center, spacing: 6) {
        Image(systemName: "desktopcomputer")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        Text(instantane.nomServeur.isEmpty ? "DSH" : instantane.nomServeur)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)

        Spacer()

        Circle()
          .fill(instantane.estConnecte ? Color.green : Color.red)
          .frame(width: 8, height: 8)
      }

      Spacer()

      // Compteur de sessions
      VStack(alignment: .leading, spacing: 2) {
        Text("\(instantane.nombreSessionsActives)")
          .font(.system(size: 34, weight: .bold, design: .rounded))
          .foregroundStyle(.primary)

        Text(instantane.nombreSessionsActives <= 1 ? L("session active") : L("sessions actives"))
          .font(.caption2.weight(.medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      // Badge d'activité de l'agent
      if instantane.nombreSessionsAuTravail > 0 {
        HStack(spacing: 4) {
          Image(systemName: "bolt.fill")
            .font(.caption2)
            .foregroundStyle(.orange)
          Text("\(instantane.nombreSessionsAuTravail) \(L("au travail"))")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.orange.opacity(0.15), in: Capsule())
      } else {
        HStack(spacing: 4) {
          Image(systemName: instantane.estConnecte ? "checkmark.circle" : "exclamationmark.circle")
            .font(.caption2)
            .foregroundStyle(.secondary)
          Text(instantane.estConnecte ? L("En ligne") : L("Déconnecté"))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .widgetURL(URL(string: "dshremote://serveur"))
  }
}

/// Vue du widget au format moyen (Medium : rectangle 4x2).
public struct VueWidgetMedium: View {
  public let instantane: InstantaneWidget

  public init(instantane: InstantaneWidget) {
    self.instantane = instantane
  }

  public var body: some View {
    HStack(spacing: 12) {
      // Colonne gauche : État du serveur et sessions
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Circle()
            .fill(instantane.estConnecte ? Color.green : Color.red)
            .frame(width: 8, height: 8)

          Text(instantane.nomServeur.isEmpty ? "DSH" : instantane.nomServeur)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
        }

        Spacer()

        VStack(alignment: .leading, spacing: 2) {
          Text("\(instantane.nombreSessionsActives)")
            .font(.system(size: 30, weight: .bold, design: .rounded))
          Text(instantane.nombreSessionsActives <= 1 ? L("session active") : L("sessions actives"))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }

        Spacer()

        if instantane.nombreSessionsAuTravail > 0 {
          HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
              .font(.caption2)
            Text("\(instantane.nombreSessionsAuTravail) \(L("au travail"))")
              .font(.caption2.weight(.medium))
          }
          .foregroundStyle(.orange)
        } else {
          Text(instantane.estConnecte ? L("Prêt") : L("Déconnecté"))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: 120, alignment: .leading)

      Divider()

      // Colonne droite : Dernière session active ou statut
      VStack(alignment: .leading, spacing: 4) {
        if let session = instantane.derniereSession {
          HStack {
            Text(session.espaceNom.isEmpty ? L("Session") : session.espaceNom)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
              .lineLimit(1)

            Spacer()

            if session.etat == "en_cours" {
              Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
            }
          }

          Text(session.titre.isEmpty ? L("(sans titre)") : session.titre)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(2)

          Spacer()

          if let etape = session.derniereEtape, !etape.isEmpty {
            Text(etape)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }

          Text(session.dateDerniereActivite, style: .relative)
            .font(.caption2)
            .foregroundStyle(.tertiary)
        } else {
          Spacer()
          VStack(alignment: .center, spacing: 4) {
            Image(systemName: "tray")
              .font(.title3)
              .foregroundStyle(.secondary)
            Text(L("Aucune session active"))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          Spacer()
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .widgetURL(instantane.derniereSession?.urlDeepLink ?? URL(string: "dshremote://serveur"))
  }
}

#Preview("Widget Small") {
  VueWidgetSmall(instantane: .apercu)
    .frame(width: 160, height: 160)
    .background(Color.secondary.opacity(0.1))
}

#Preview("Widget Medium") {
  VueWidgetMedium(instantane: .apercu)
    .frame(width: 340, height: 160)
    .background(Color.secondary.opacity(0.1))
}
