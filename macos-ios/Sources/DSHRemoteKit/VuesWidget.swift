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
  public let dateAffichee: Date

  public init(instantane: InstantaneWidget, dateAffichee: Date = Date()) {
    self.instantane = instantane
    self.dateAffichee = dateAffichee
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
          .fill(PastilleWidget.couleur(instantane, a: dateAffichee))
          .frame(width: 8, height: 8)
      }

      Spacer()

      if instantane.estFrais(a: dateAffichee), instantane.nombreSessionsActives == 0 {
        VStack(alignment: .leading, spacing: 4) {
          Image(systemName: instantane.estConnecte ? "sparkles" : "moon.stars.fill")
            .font(.title2)
            .foregroundStyle(.secondary)
          Text(L("Tout est calme"))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
        }
      } else {
        VStack(alignment: .leading, spacing: 2) {
          Text("\(instantane.nombreSessionsActives)")
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)

          Text(instantane.nombreSessionsActives <= 1 ? L("session suivie") : L("sessions suivies"))
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer()

      PiedDeWidget(instantane: instantane, dateAffichee: dateAffichee)
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .widgetURL(URL(string: "dshremote://serveur"))
  }
}

/// Vue du widget au format moyen (Medium : rectangle 4x2).
public struct VueWidgetMedium: View {
  public let instantane: InstantaneWidget
  public let dateAffichee: Date

  public init(instantane: InstantaneWidget, dateAffichee: Date = Date()) {
    self.instantane = instantane
    self.dateAffichee = dateAffichee
  }

  public var body: some View {
    HStack(spacing: 12) {
      // Colonne gauche : État du serveur et sessions
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Circle()
            .fill(PastilleWidget.couleur(instantane, a: dateAffichee))
            .frame(width: 8, height: 8)

          Text(instantane.nomServeur.isEmpty ? "DSH" : instantane.nomServeur)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
        }

        Spacer()

        VStack(alignment: .leading, spacing: 2) {
          Text("\(instantane.nombreSessionsActives)")
            .font(.system(size: 30, weight: .bold, design: .rounded))
          Text(instantane.nombreSessionsActives <= 1 ? L("session suivie") : L("sessions suivies"))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }

        Spacer()

        PiedDeWidget(instantane: instantane, dateAffichee: dateAffichee, compact: true)
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

            if instantane.estFrais(a: dateAffichee), session.etat == "en_cours" {
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
          VStack(alignment: .center, spacing: 6) {
            Image(systemName: instantane.estConnecte ? "sparkles" : "moon.stars.fill")
              .font(.title2)
              .foregroundStyle(.secondary)
            Text(L("Tout est calme"))
              .font(.subheadline.weight(.medium))
              .foregroundStyle(.primary)
            Text(instantane.estConnecte ? L("Prêt pour la suite") : L("Touchez pour synchroniser"))
              .font(.caption2)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
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

/// Pastille verte tant que le relevé est frais et la machine jointe, grise
/// ensuite. L'âge affiché est celui de `dateMiseAJour`, pas celui du dessin.
private struct AgeDuReleve: View {
  let date: Date

  var body: some View {
    Text(date, style: .relative)
      .font(.caption2)
      .foregroundStyle(.tertiary)
      .lineLimit(1)
  }
}

enum PastilleWidget {
  static func couleur(_ instantane: InstantaneWidget, a date: Date) -> Color {
    guard instantane.estFrais(a: date), instantane.estConnecte else { return Color.secondary }
    return Color.green
  }
}

private struct PiedDeWidget: View {
  let instantane: InstantaneWidget
  let dateAffichee: Date
  var compact = false

  var body: some View {
    let frais = instantane.estFrais(a: dateAffichee)
    VStack(alignment: .leading, spacing: 2) {
    if frais, instantane.nombreSessionsAuTravail > 0 {
      HStack(spacing: 4) {
        Image(systemName: "bolt.fill")
          .font(.caption2)
        Text("\(instantane.nombreSessionsAuTravail) \(L("au travail"))")
          .font(.caption2.weight(compact ? .medium : .semibold))
          .lineLimit(1)
      }
      .foregroundStyle(.orange)
      .padding(.horizontal, compact ? 0 : 6)
      .padding(.vertical, compact ? 0 : 3)
      .background {
        if !compact {
          Capsule().fill(Color.orange.opacity(0.15))
        }
      }
      AgeDuReleve(date: instantane.dateMiseAJour)
    } else if frais {
      HStack(spacing: 4) {
        Image(systemName: instantane.estConnecte ? "checkmark.circle" : "moon.fill")
          .font(.caption2)
        Text(instantane.estConnecte ? L("Prêt") : L("En veille"))
          .font(.caption2)
          .lineLimit(1)
      }
      .foregroundStyle(.secondary)
      AgeDuReleve(date: instantane.dateMiseAJour)
    } else {
      HStack(spacing: 4) {
        Image(systemName: "clock")
          .font(.caption2)
        Text(L("relevé"))
          .font(.caption2)
        Text(instantane.dateMiseAJour, style: .relative)
          .font(.caption2)
      }
      .foregroundStyle(.secondary)
      .lineLimit(1)
    }
    }
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
