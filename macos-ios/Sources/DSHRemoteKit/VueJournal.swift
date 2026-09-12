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
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        // Le suivi en direct se voit et se commande : un flux silencieux qui
        // s'arrête sans le dire laisserait croire que la session est inactive.
        Button {
          if modele.enDirect {
            modele.arreterFlux()
          } else {
            Task { await modele.demarrerFlux(session.id) }
          }
        } label: {
          Label(
            modele.enDirect ? "En direct" : "Suivi arrêté",
            systemImage: modele.enDirect ? "dot.radiowaves.left.and.right" : "pause.circle")
            .foregroundStyle(modele.enDirect ? Color.green : Color.secondary)
        }
      }
    }
    .overlay {
      if modele.enChargement, modele.journal.isEmpty {
        ProgressView("Lecture du journal…")
      }
    }
    // Charger le journal est ce qui DONNE son contenu à cette vue.
    //
    // POURQUOI CE `.task` EST INDISPENSABLE. La sélection d'une session fait bien
    // apparaître cet écran — titre, chemin, preset — mais l'en-tête seul ne lit
    // rien : sans cet appel, le journal affichait « 0 affichés » pour une session
    // qui en comptait 48. Un écran qui a l'air fonctionnel et qui ne montre rien
    // est plus trompeur qu'une erreur. Le défaut a été trouvé en REGARDANT le
    // simulateur, pas en compilant.
    //
    // `.task(id:)` et non `.task` : changer de session doit relire le journal,
    // sans quoi la seconde session ouvrirait le journal de la première.
    .task(id: session.id) {
      await modele.ouvrir(session)
    }
    // Quitter le journal, c'est cesser de REGARDER la session : son rappel de fin
    // pourra de nouveau s'armer. Le journal chargé et le flux restent en place.
    .onDisappear {
      modele.quitterJournal(session.id)
    }
    // Le composeur n'apparaît que si l'HÔTE a annoncé savoir écrire : une barre
    // de saisie qui ne peut rien envoyer est pire que pas de barre du tout.
    .safeAreaInset(edge: .bottom) {
      if modele.ecriturePossible {
        ComposeurEcriture(modele: modele, session: session)
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
