import SwiftUI

/// Composeur : écrire dans une session depuis l'application.
///
/// POURQUOI IL EXISTE. Sans lui, l'application ne sait qu'OBSERVER : il fallait
/// revenir au Mac pour répondre à une question posée par l'agent. Une surface de
/// lecture seule sur un téléphone, c'est une notification qu'on ne peut pas
/// traiter.
///
/// TROIS RÈGLES D'INTERFACE, chacune née d'un défaut réel :
///
///   1. **Le texte n'est effacé qu'après l'acquittement de l'hôte.** Un échec de
///      réseau ne doit pas coûter à l'utilisateur ce qu'il vient d'écrire.
///   2. **Un bouton ne s'affiche que s'il peut agir.** « Arrêter » n'apparaît que
///      si la session tourne ET si l'hôte a annoncé savoir interrompre
///      (`capacites.annulation`). Un bouton sans effet est un mensonge.
///   3. **Le mode d'envoi est visible.** « À la suite » et « tout de suite »
///      n'ont pas le même effet sur un tour en cours ; le mode courant est écrit
///      en toutes lettres, pas caché derrière une icône.
struct ComposeurEcriture: View {
  @Bindable var modele: ModeleApp
  let session: SessionListee

  @State private var mode: ModePrompt = .queue
  @FocusState private var champActif: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let erreur = modele.erreurEcriture {
        EtatEcriture(texte: erreur, icone: "exclamationmark.triangle.fill", teinte: .orange)
      } else if let accuse = modele.accuseEnvoi {
        EtatEcriture(texte: accuse, icone: "checkmark.circle.fill", teinte: .green)
      }

      HStack(alignment: .bottom, spacing: 8) {
        TextField("Écrire à cette session…", text: $modele.brouillon, axis: .vertical)
          .textFieldStyle(.plain)
          .lineLimit(1...5)
          .focused($champActif)
          .padding(.horizontal, 10)
          .padding(.vertical, 7)
          .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
          .onSubmit { envoyer() }

        menuMode

        if modele.envoiEnCours {
          ProgressView().controlSize(.small)
        } else {
          Button {
            envoyer()
          } label: {
            Image(systemName: "arrow.up.circle.fill").font(.title2)
          }
          .buttonStyle(.plain)
          .foregroundStyle(modele.brouillon.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.accentColor)
          .disabled(modele.brouillon.trimmingCharacters(in: .whitespaces).isEmpty)
          .cibleTactile()
          .help("Envoyer")
          .accessibilityLabel("Envoyer le message")
        }

        if modele.estEnCours(session.id), modele.annulationPossible {
          Button {
            Task { await modele.annulerTour(session) }
          } label: {
            Image(systemName: "stop.circle.fill").font(.title2)
          }
          .buttonStyle(.plain)
          .foregroundStyle(Color.red)
          .cibleTactile()
          .help("Interrompre le tour en cours — la file d'attente est conservée")
          .accessibilityLabel("Interrompre le tour en cours")
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.bar)
    .onChange(of: session.id) {
      // Changer de session efface les messages du composeur : un acquittement
      // affiché sous une AUTRE session ferait croire qu'il la concerne.
      modele.oublierEtatEcriture()
    }
  }

  /// Sélecteur de mode, en clair plutôt qu'en icône : la différence entre
  /// « à la suite » et « tout de suite » ne se devine pas.
  private var menuMode: some View {
    Menu {
      Button {
        mode = .queue
      } label: {
        Label("À la suite", systemImage: mode == .queue ? "checkmark" : "text.badge.plus")
      }
      Button {
        mode = .steer
      } label: {
        Label("Tout de suite (interrompt)", systemImage: mode == .steer ? "checkmark" : "bolt.fill")
      }
    } label: {
      Image(systemName: mode == .queue ? "text.badge.plus" : "bolt.fill")
        .font(.title3)
        .foregroundStyle(mode == .queue ? Color.secondary : Color.orange)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .cibleTactile()
    .help(mode == .queue ? "À la suite : forme le prochain tour" : "Tout de suite : remis au tour en cours")
    // LE MODE COURANT SE DIT AUSSI À VOIXOVER : l'icône change de couleur et de
    // glyphe, deux choses qu'un lecteur d'écran ne rend pas.
    .accessibilityLabel(
      mode == .queue
        ? "Mode d'envoi : à la suite" : "Mode d'envoi : tout de suite, interrompt le tour en cours")
  }

  private func envoyer() {
    champActif = false
    Task { await modele.envoyer(session, mode: mode) }
  }
}

/// Une ligne d'état du composeur : acquittement, refus, ou reprise de session.
struct EtatEcriture: View {
  let texte: String
  let icone: String
  let teinte: Color

  var body: some View {
    Label(texte, systemImage: icone)
      .font(.caption)
      .foregroundStyle(teinte)
      .lineLimit(2)
  }
}
