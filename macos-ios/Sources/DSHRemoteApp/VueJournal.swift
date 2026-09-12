import DSHRemoteKit
import SwiftUI

/// Vue du journal d'une session : les enregistrements, du plus ancien au plus récent.
///
/// Les types d'événements sont rendus par une couleur et une icône plutôt que par
/// un tableau de correspondance exhaustif : un type que cette version ne connaît
/// pas s'affiche quand même, avec son nom. Le harness ajoute des types d'événements
/// régulièrement, et une interface qui casse à chaque ajout serait inutilisable.
struct VueJournal: View {
  let modele: ModeleApp
  let session: SessionListee

  var body: some View {
    List {
      if let titre = modele.sessionOuverte?.titre ?? session.resume.titre {
        Section {
          VStack(alignment: .leading, spacing: 4) {
            Text(titre).font(.headline)
            if let cwd = modele.sessionOuverte?.cwd {
              Text(cwd).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            HStack(spacing: 10) {
              if let preset = modele.sessionOuverte?.preset {
                Label(preset, systemImage: "slider.horizontal.3")
              }
              if let total = modele.sessionOuverte?.nbEnregistrements {
                Label("\(total) évts", systemImage: "list.bullet")
              }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
          }
        }
      }

      Section("Journal (\(modele.journal.count) affichés)") {
        ForEach(modele.journal) { evenement in
          LigneEvenement(evenement: evenement)
        }
      }
    }
    .navigationTitle(session.titreAffiche)
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .overlay {
      if modele.enChargement, modele.journal.isEmpty {
        ProgressView("Lecture du journal…")
      }
    }
  }
}

/// Une ligne de journal : nature, séquence, et le texte utile.
struct LigneEvenement: View {
  let evenement: EvenementAffiche
  @State private var deplie = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Image(systemName: icone)
          .foregroundStyle(couleur)
          .font(.caption)
          .frame(width: 14)
        Text(evenement.type)
          .font(.caption2.monospaced())
          .foregroundStyle(.secondary)
        Spacer()
        if let seq = evenement.enregistrement.seq {
          Text("#\(seq)").font(.caption2.monospaced()).foregroundStyle(.tertiary)
        }
      }

      Text(evenement.resume)
        .font(.callout)
        .lineLimit(deplie ? nil : 4)
        .textSelection(.enabled)

      if evenement.estVolumineux {
        Button(deplie ? "Réduire" : "Développer") { deplie.toggle() }
          .buttonStyle(.plain)
          .font(.caption)
          .foregroundStyle(.tint)
      }
    }
    .padding(.vertical, 2)
  }

  private var icone: String {
    switch evenement.type {
    case "user/message": return "person.fill"
    case "assistant/message": return "sparkles"
    case "tool/call": return "wrench.and.screwdriver"
    case "tool/result": return "arrow.turn.down.right"
    case "step/start", "step/end": return "flag"
    case "turn/start": return "play.fill"
    case "session/title": return "textformat"
    case "goal/change": return "target"
    default: return "circle.dotted"
    }
  }

  private var couleur: Color {
    switch evenement.type {
    case "user/message": return .blue
    case "assistant/message": return .purple
    case "tool/call", "tool/result": return .orange
    case "goal/change": return .green
    default: return .secondary
    }
  }
}
