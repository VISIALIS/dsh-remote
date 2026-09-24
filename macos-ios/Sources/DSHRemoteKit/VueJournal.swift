import SwiftUI

/// Vue du journal d'une session : les enregistrements, du plus ancien au plus récent.
///
/// Les types d'événements sont rendus par une couleur et une icône plutôt que par
/// un tableau de correspondance exhaustif : un type que cette version ne connaît
/// pas s'affiche quand même, avec son nom. Le harness ajoute des types d'événements
/// régulièrement, et une interface qui casse à chaque ajout serait inutilisable.
///
/// TROIS RÈGLES TENUES ICI, chacune née d'un défaut vu à l'écran :
///
///   1. **le journal appartient à SA session.** Un échec de lecture laissait
///      l'ancien journal sous le titre de la nouvelle session — les événements
///      d'une conversation affichés sous le nom d'une autre, sans rien pour le
///      dire. Tout ce qui est montré est donc filtré par `journalPour` ;
///   2. **un échec se dit, et se réessaie.** La connexion peut très bien aller
///      bien : c'est la lecture de CE journal qui a échoué. Le taire ferait
///      chercher une panne ailleurs ;
///   3. **le journal suit sa fin.** Il s'ouvre sur le dernier événement et y reste
///      tant qu'on ne remonte pas lire ; quand on remonte, un compteur dit ce qui
///      est arrivé pendant ce temps, et ramène en bas d'un appui.
struct VueJournal: View {
  let modele: ModeleApp
  let session: SessionListee

  /// L'ancre du défilement : une ligne invisible, en fin de liste.
  private static let ancreDeFin = "fin-du-journal"

  /// L'utilisateur est-il AU BAS du journal ? (Voir `SuiviDuBas` pour le repli.)
  @State private var auBas = true
  /// Combien d'événements sont arrivés depuis qu'il en est parti ?
  @State private var arrivesDepuis = 0

  /// LE RÉSUMÉ DE **CETTE** SESSION — jamais celui d'une autre.
  ///
  /// POURQUOI LA GARDE. `sessionOuverte` décrit la dernière session Chargée ; si
  /// elle n'est pas celle qu'on regarde, son titre et son chemin ne doivent pas
  /// s'afficher ici. C'est exactement le défaut réparé, à l'endroit où il se
  /// voyait.
  private var resume: ResumeSession? {
    modele.sessionOuverte?.id == session.id ? modele.sessionOuverte : nil
  }

  /// LES ÉVÉNEMENTS DE **CETTE** SESSION — vides s'ils appartiennent à une autre.
  ///
  /// POURQUOI LA GARDE EST ICI AUSSI. `ouvrir` remet le journal à zéro avant de
  /// demander, mais entre l'apparition de la vue et l'exécution de sa tâche, un
  /// rendu peut avoir lieu : sans ce filtre, l'espace d'une image, les
  /// événements de la session précédente s'afficheraient sous le nouveau titre.
  private var evenements: [EvenementAffiche] {
    modele.journalPour == session.id ? modele.journal : []
  }

  private var erreurDeLecture: String? { modele.erreurJournal(pour: session.id) }
  private var enLecture: Bool { modele.journalEnLecture(pour: session.id) }

  var body: some View {
    ScrollViewReader { proxy in
      List {
        enTete
        sectionJournal
      }
      .navigationTitle(session.titreAffiche)
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      // LE JOURNAL S'OUVRE SUR SA FIN, et y reste quand le contenu grandit :
      // c'est ce que fait `defaultScrollAnchor(.bottom)`, et c'est le seul
      // réglage qui donne le comportement attendu d'un journal.
      .defaultScrollAnchor(.bottom)
      .modifier(SuiviDuBas(auBas: $auBas))
      .onChange(of: modele.journal.count) { ancien, nouveau in
        suivreLaFin(proxy, ancien: ancien, nouveau: nouveau)
      }
      .onChange(of: session.id) { _, _ in
        // Changer de session remet le compteur à zéro : il comptait pour une
        // autre conversation.
        arrivesDepuis = 0
        auBas = true
      }
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          // Le suivi en direct se voit et se commande : un flux silencieux qui
          // s'arrête sans le dire laisserait croire que la session est inactive.
          //
          // TROIS ÉTATS, PAS DEUX. « En direct », « Suivi arrêté », et — depuis que
          // le flux se rouvre tout seul — « Reconnexion… ». Le troisième n'est pas
          // un ornement : sans lui, une coupure de réseau de dix secondes
          // afficherait « En direct » sur un journal qui ne reçoit rien, ou
          // « Suivi arrêté » alors que l'application est en train de réessayer.
          Button {
            if modele.enDirect {
              modele.arreterFlux()
            } else {
              Task { await modele.demarrerFlux(session.id) }
            }
          } label: {
            Label(
              modele.reconnexion?.libelle ?? (modele.enDirect ? "En direct" : "Suivi arrêté"),
              systemImage: modele.reconnexion != nil
                ? "arrow.clockwise"
                : (modele.enDirect ? "dot.radiowaves.left.and.right" : "pause.circle")
            )
            .foregroundStyle(
              (modele.reconnexion != nil ? EtatVisuel.attente : (modele.enDirect ? EtatVisuel.pret : .attente))
                .couleur)
          }
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
      .safeAreaInset(edge: .bottom, spacing: 0) {
        VStack(spacing: 8) {
          if !auBas, arrivesDepuis > 0 { boutonRevenirEnBas(proxy) }
          if modele.ecriturePossible {
            ComposeurEcriture(modele: modele, session: session)
          } else if let raison = modele.raisonSansEcriture {
            // LE COMPOSEUR ABSENT SE DIT. Il disparaissait sans un mot : l'écran
            // semblait complet, et rien n'indiquait que répondre était impossible
            // — ni pourquoi. La raison vient du modèle, qui la tient de l'hôte ;
            // les causes ont des remèdes qui ne sont PAS au même endroit, et
            // c'est précisément pour cela qu'il faut les nommer.
            Label(raison, systemImage: "pencil.slash")
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(.bar)
          }
        }
      }
    }
  }

  // MARK: - L'en-tête

  @ViewBuilder
  private var enTete: some View {
    if let resume {
      Section {
        VStack(alignment: .leading, spacing: 4) {
          Text(resume.titre ?? session.titreAffiche).font(.headline)
          if let cwd = resume.cwd {
            Text(cwd).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
          }
          HStack(spacing: 10) {
            if let preset = resume.preset {
              Label(preset, systemImage: "slider.horizontal.3")
            }
            if let total = resume.nbEnregistrements {
              Label("\(total) " + (total > 1 ? L("évts") : L("évt")), systemImage: "list.bullet")
            }
          }
          .font(.caption2)
          .foregroundStyle(.secondary)
        }
      }
    }
  }

  // MARK: - Le journal, et ses trois états

  @ViewBuilder
  private var sectionJournal: some View {
    Section(String(format: L("Journal (%d affichés)"), evenements.count)) {
      ForEach(evenements) { evenement in
        LigneEvenement(evenement: evenement)
      }
      // L'ANCRE DE FIN. Une ligne vide, haute d'un point, qui donne au
      // défilement un point d'arrivée stable — et qui sert aussi de cible au
      // bouton « aller à la fin ».
      Color.clear
        .frame(height: 1)
        .id(Self.ancreDeFin)
        .listRowSeparator(.hidden)
        .sansSeparateurMac()

      // ON LIT : c'est un état, et il se voit. Il était conditionné à
      // `journal.isEmpty` — donc jamais montré quand un ancien journal
      // traînait, ce qui était précisément le cas où l'écran mentait.
      if enLecture {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          T("Lecture du journal…").font(.callout).foregroundStyle(.secondary)
        }
      }

      // ON A ÉCHOUÉ : on le dit, et on offre de recommencer.
      if let erreurDeLecture {
        VStack(alignment: .leading, spacing: 8) {
          Label { T("Le journal n'a pas pu être lu.") } icon: { Image(systemName: EtatVisuel.attention.symbole) }
            .font(.callout)
            .foregroundStyle(EtatVisuel.attention.couleur)
          Text(erreurDeLecture)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          Button(L("Réessayer")) {
            Task { await modele.ouvrir(session) }
          }
          .buttonStyle(.bordered)
        }
      }

      // ON A LU, ET IL N'Y A RIEN : un état vide se dit, il ne se devine pas.
      if evenements.isEmpty, !enLecture, erreurDeLecture == nil {
        ContentUnavailableView {
          Label { T("Aucun événement") } icon: { Image(systemName: "text.page.slash") }
        } description: {
          T("Cette session n'a encore rien écrit.")
        }
      }
    }
  }

  // MARK: - Suivre la fin

  /// Ramène en bas quand de nouveaux événements arrivent — SI on y était déjà.
  private func suivreLaFin(_ proxy: ScrollViewProxy, ancien: Int, nouveau: Int) {
    guard nouveau != ancien else { return }
    if auBas {
      withAnimation(.easeOut(duration: 0.2)) {
        proxy.scrollTo(Self.ancreDeFin, anchor: .bottom)
      }
    } else if nouveau > ancien {
      // ON REMONTE POUR LIRE : on ne tire pas l'utilisateur par la manche, on
      // lui DIT ce qui est arrivé et on lui laisse le geste.
      arrivesDepuis += nouveau - ancien
    }
  }

  /// Le bouton qui ramène à la fin, avec ce qui attend.
  private func boutonRevenirEnBas(_ proxy: ScrollViewProxy) -> some View {
    Button {
      arrivesDepuis = 0
      auBas = true
      withAnimation(.easeOut(duration: 0.2)) {
        proxy.scrollTo(Self.ancreDeFin, anchor: .bottom)
      }
    } label: {
      Label(
        arrivesDepuis > 1
          ? String(format: L("%d nouveaux événements"), arrivesDepuis) : L("1 nouvel événement"),
        systemImage: "arrow.down.circle.fill")
        .font(.caption)
    }
    .buttonStyle(.borderedProminent)
    .buttonBorderShape(.capsule)
    .padding(.bottom, 4)
    .accessibilityLabel(
      arrivesDepuis > 1
        ? String(format: L("%d nouveaux événements — aller à la fin du journal"), arrivesDepuis)
        : L("Un nouvel événement — aller à la fin du journal"))
  }
}

/// « SUIS-JE AU BAS DU JOURNAL ? » — mesuré, quand la plateforme sait le dire.
///
/// POURQUOI CE MODIFICATEUR SÉPARÉ. `onScrollGeometryChange` demande iOS 18 /
/// macOS 15, alors que l'application vise iOS 17 / macOS 14 : l'appeler
/// directement ne compilerait plus pour sa cible. Le repli ne prétend pas
/// savoir — il répond « oui, je suis en bas », donc le journal suit sa fin. C'est
/// le comportement d'un journal qu'on vient d'ouvrir, et le moins surprenant
/// quand on ne peut pas mesurer.
struct SuiviDuBas: ViewModifier {
  @Binding var auBas: Bool

  func body(content: Content) -> some View {
    if #available(iOS 18.0, macOS 15.0, *) {
      content.onScrollGeometryChange(for: Bool.self) { geometrie in
        // 24 points de tolérance : le bas exact dépend du rebond élastique, et
        // exiger l'égalité ferait clignoter le bouton.
        geometrie.contentOffset.y + geometrie.containerSize.height
          >= geometrie.contentSize.height - 24
      } action: { _, nouveau in
        auBas = nouveau
      }
    } else {
      content
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

      contenu

      // LE BOUTON DIT CE QU'IL CACHE. Il n'apparaissait qu'au-delà de 120
      // caractères, alors que la ligne en montre QUATRE : un message de six
      // lignes courtes — quatre-vingt-dix caractères — était tronqué sans aucun
      // moyen de lire la suite. Le seuil suit maintenant la troncature réelle
      // (`Evenements.estVolumineux`).
      if evenement.estVolumineux {
        Button(deplie ? "Réduire" : "Développer") { deplie.toggle() }
          .buttonStyle(.plain)
          .font(.caption)
          .foregroundStyle(.tint)
          .cibleTactile()
      }
    }
    .padding(.vertical, 2)
  }

  /// LE CONTENU, DÉCOUPÉ EN SEGMENTS — texte ordinaire, et blocs de code.
  ///
  /// POURQUOI LE DÉCOUPAGE SE FAIT À CHAQUE RENDU, ET NON UNE FOIS POUR TOUTES.
  /// C'est une passe sur le texte, sans allocation notable, et le mémoriser
  /// demanderait de le tenir à jour quand le dépliage change : deux états pour une
  /// seule vérité. Le texte d'un événement ne change pas pendant la vie de la
  /// ligne, donc la passe est faite au plus une fois par affichage utile.
  ///
  /// CE QUI N'EST PAS TRAITÉ, ET QUI EST UN CHOIX. Le reste du Markdown — titres,
  /// listes, gras, tableaux — reste du texte. Un analyseur complet est un chantier
  /// de plusieurs jours, la RÈGLE #0 interdit d'en importer un, et le vrai lecteur
  /// d'un long document reste l'interface web. Ce qui est traité ici est ce qui
  /// manquait le plus : 8,2 % des messages de l'agent portent un bloc de code
  /// (mesuré sur 40 journaux réels), et c'est celui qu'on veut LIRE et RECOPIER.
  @ViewBuilder
  private var contenu: some View {
    let segments = BlocsDeCode.decouper(evenement.resume)
    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
      switch segment {
      case let .texte(texte):
        Text(texte)
          .font(.callout)
          .lineLimit(deplie ? nil : 4)
          .textSelection(.enabled)
      case let .code(code, langue):
        BlocDeCode(contenu: code, langue: langue, deplie: deplie)
      }
    }
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

/// UN BLOC DE CODE DANS LE JOURNAL — monospace, fond distinct, copiable.
///
/// POURQUOI IL A SON PROPRE CADRE. Un bloc se reconnaît à sa FORME avant de se
/// lire : c'est ce qui le distingue d'une phrase de l'agent. Le fond et la chasse
/// fixe le disent sans un mot, et le bouton de copie évite de sélectionner à la
/// main quarante caractères sur un téléphone — le geste qu'on vient y faire.
///
/// POURQUOI IL EST LIMITÉ À DOUZE LIGNES REPLIÉ. Un bloc peut en faire deux cents
/// (un diff, un fichier entier) : le déplier d'office noierait la conversation.
/// Le bouton « Développer » de l'événement le déplie avec le reste, et c'est le
/// même état pour tout le message — deux dépliages séparés se contrediraient.
struct BlocDeCode: View {
  let contenu: String
  /// Le langage annoncé après les accents graves, s'il y en a un.
  let langue: String?
  let deplie: Bool
  @State private var copie = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        // LE LANGAGE N'EST MONTRÉ QUE S'IL EST CONNU. Écrire « code » quand
        // l'agent ne l'a pas dit n'apprendrait rien : le cadre le dit déjà.
        if let langue {
          Text(langue).font(.caption2).foregroundStyle(.tertiary)
        }
        Spacer(minLength: 4)
        Button {
          copier()
        } label: {
          Image(systemName: copie ? "checkmark" : "doc.on.doc").font(.caption)
        }
        .buttonStyle(.borderless)
        .cibleTactile()
        .accessibilityLabel(copie ? "Bloc de code copié" : "Copier le bloc de code")
        .sensoryFeedback(.success, trigger: copie) { ancien, nouveau in
          !ancien && nouveau
        }
      }
      Text(contenu)
        .font(.caption.monospaced())
        .lineLimit(deplie ? nil : 12)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(8)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
  }

  private func copier() {
    PressePapiers.ecrire(contenu)
    copie = true
    Task {
      try? await Task.sleep(nanoseconds: 1_800_000_000)
      copie = false
    }
  }
}
