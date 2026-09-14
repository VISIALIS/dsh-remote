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

  /// LE MODE D'ENVOI APPARTIENT AU MODÈLE, ET SE RETROUVE À LA RÉOUVERTURE.
  ///
  /// POURQUOI IL N'EST PLUS UN `@State` LOCAL. Il repartait à « à la suite » à
  /// chaque changement de session, sans le dire : quelqu'un qui travaille en
  /// « tout de suite » le re-sélectionnait à chaque fois, et le menu ne disait
  /// jamais que le choix avait été oublié. Le mode est un choix DURABLE de
  /// l'utilisateur, pas un état de passage.
  private var mode: ModePrompt { modele.navigation.modeEnvoi }

  private func definirMode(_ nouveau: ModePrompt) {
    modele.definirModeEnvoi(nouveau)
  }
  @FocusState private var champActif: Bool
  /// L'interruption DEMANDE CONFIRMATION : elle est demandée par un appui, et
  /// elle arrête un travail en cours.
  @State private var confirmationInterruption = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let erreur = modele.refusEcriture(pour: session.id) {
        EtatEcriture(texte: erreur, icone: "exclamationmark.triangle.fill", teinte: .orange)
      } else if let accuse = modele.acquittement(pour: session.id) {
        EtatEcriture(texte: accuse, icone: "checkmark.circle.fill", teinte: .green)
      }

      HStack(alignment: .bottom, spacing: 8) {
        // LE CHAMP APPARTIENT À CETTE SESSION. Une liaison directe à un champ
        // unique du modèle faisait suivre le texte d'une session à l'autre :
        // un message écrit pour l'une pouvait partir vers l'autre.
        TextField(
          text: Binding(
            get: { modele.brouillon(pour: session.id) },
            set: { modele.definirBrouillon($0, pour: session.id) }
          ),
          axis: .vertical
        ) {
          T("Écrire à cette session…")
        }
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
          .foregroundStyle(
            modele.brouillonVide(pour: session.id) ? Color.secondary : Color.accentColor
          )
          .disabled(modele.brouillonVide(pour: session.id))
          .cibleTactile()
          .help(T("Envoyer"))
          .accessibilityLabel(T("Envoyer le message"))
        }

        if modele.estEnCours(session.id), modele.annulationPossible {
          // SÉPARATION. Le glyphe rouge était COLLÉ au bouton d'envoi, à huit
          // points : viser l'un et toucher l'autre arrêtait un travail en cours.
          // Un trait, et un peu d'air, disent que ce sont deux actions
          // différentes — l'une compose, l'autre interrompt.
          Divider().frame(height: 26)

          // ET L'INTERRUPTION SE CONFIRME. Elle était immédiate, sans retour
          // possible : un appui mal placé suffisait à arrêter un tour. Ce qui
          // est conservé est dit à l'écran, pour que la décision se prenne en
          // connaissance de cause.
          Button {
            confirmationInterruption = true
          } label: {
            Image(systemName: "stop.circle.fill").font(.title2)
          }
          .buttonStyle(.plain)
          .foregroundStyle(Color.red)
          .cibleTactile()
          .help(T("Interrompre le tour en cours — la file d'attente est conservée"))
          .accessibilityLabel(T("Interrompre le tour en cours"))
          .confirmationDialog(
            "Interrompre le tour en cours ?",
            isPresented: $confirmationInterruption,
            titleVisibility: .visible
          ) {
            Button(L("Interrompre"), role: .destructive) {
              Task { await modele.annulerTour(session) }
            }
            Button(L("Annuler"), role: .cancel) {}
          } message: {
            T("Le travail déjà fait est conservé, et la file d'attente aussi.")
          }
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.bar)
    // LE RETOUR HAPTIQUE COMPLÈTE CE QUI SE VOIT MAL. Envoyer un message à un
    // agent distant prend des secondes, et l'acquittement s'affiche en haut d'un
    // composeur qu'on ne regarde pas : on regarde ce qu'on vient d'écrire. Un
    // refus, lui, se remarque encore moins — c'est pourtant le cas où il faut
    // réagir.
    // ⌘↩ VIENT ICI. La garde est CELLE DU BOUTON — pas de texte, ou un envoi en
    // vol, et il n'y a rien à faire : une commande de menu qui agirait malgré
    // tout contredirait l'état affiché, ce que ce dépôt refuse partout ailleurs.
    #if os(macOS)
      .focusedSceneValue(\.envoyerMessage) {
        guard !modele.brouillonVide(pour: session.id), !modele.envoiEnCours else { return }
        envoyer()
      }
    #endif
    .modifier(
      RetourDuComposeur(
        accuse: modele.acquittement(pour: session.id),
        refus: modele.refusEcriture(pour: session.id)))
    .onChange(of: session.id) {
      // Changer de session oublie les MESSAGES du composeur : un acquittement
      // affiché sous une AUTRE session ferait croire qu'elle la concerne.
      // Le TEXTE, lui, reste : chaque session a le sien, et le perdre au
      // changement de session coûterait à l'utilisateur ce qu'il vient
      // d'écrire.
      modele.oublierEtatEcriture()
    }
  }

  /// Sélecteur de mode, en clair plutôt qu'en icône : la différence entre
  /// « à la suite » et « tout de suite » ne se devine pas.
  private var menuMode: some View {
    Menu {
      Button {
        definirMode(.queue)
      } label: {
        Label { T("À la suite") } icon: { Image(systemName: mode == .queue ? "checkmark" : "text.badge.plus") }
      }
      Button {
        definirMode(.steer)
      } label: {
        Label { T("Tout de suite (interrompt)") } icon: { Image(systemName: mode == .steer ? "checkmark" : "bolt.fill") }
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

/// LE RETOUR HAPTIQUE DU COMPOSEUR, dans un modificateur à part.
///
/// POURQUOI IL N'EST PAS ÉCRIT DANS LE CORPS. Posés directement sur le `VStack`
/// du composeur — qui porte déjà le champ, le menu de mode, deux boutons et une
/// boîte de confirmation —, les deux `sensoryFeedback` à clôture ont fait
/// dépasser au compilateur son budget de vérification de type : « the compiler is
/// unable to type-check this expression in reasonable time ». Mesuré, pas
/// supposé. Le modificateur garde le corps lisible et rassemble le calcul des
/// déclencheurs en un seul endroit.
///
/// LE DÉCLENCHEUR EST LA VALEUR, PAS LE RENDU : le retour ne se produit que quand
/// l'acquittement (ou le refus) de CETTE session change vraiment — et jamais au
/// changement de session, qui remet les deux à zéro.
struct RetourDuComposeur: ViewModifier {
  let accuse: String?
  let refus: String?

  /// LE DÉCLENCHEUR EST UN PRÉDICAT TYPÉ, et ce n'est pas un détail de style.
  ///
  /// La variante à clôture rendant un `SensoryFeedback?` a été essayée d'abord :
  /// le compilateur n'arrivait pas à trancher entre ses surcharges et refusait le
  /// corps entier (« unable to type-check this expression in reasonable time »).
  /// La variante `condition:` reçoit une valeur concrète et un prédicat dont les
  /// types sont écrits : elle se vérifie sans hésitation.
  private func apparait(_ ancien: String?, _ nouveau: String?) -> Bool {
    nouveau != nil && nouveau != ancien
  }

  func body(content: Content) -> some View {
    content
      .sensoryFeedback(.success, trigger: accuse, condition: apparait)
      .sensoryFeedback(.error, trigger: refus, condition: apparait)
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
