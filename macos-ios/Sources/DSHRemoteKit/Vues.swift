import DSHRemoteKit
import SwiftUI

/// Fenêtre principale : la liste des sessions à gauche, le journal à droite.
///
/// `NavigationSplitView` est employé des deux côtés plutôt qu'une navigation par
/// pile : sur le Mac c'est une vraie vue en colonnes, et sur iPhone SwiftUI la
/// replie lui-même en pile. Une seule structure d'interface pour les deux
/// plateformes, donc un seul comportement à vérifier.
public struct VuePrincipale: View {
  @State private var modele = ModeleApp()
  @State private var sessionSelectionnee: SessionListee?

  public init() {}

  public var body: some View {
    NavigationSplitView {
      VueListeSessions(modele: modele, selection: $sessionSelectionnee)
    } detail: {
      if let session = sessionSelectionnee {
        VueJournal(modele: modele, session: session)
      } else {
        ContentUnavailableView(
          "Aucune session ouverte",
          systemImage: "terminal",
          description: Text("Choisissez une session dans la liste pour lire son journal.")
        )
      }
    }
    .task {
      if modele.jetonSaisi.isEmpty, let local = ModeleApp.jetonLocal() {
        modele.enregistrerJeton(local)
      }
      modele.demarrerDecouverte()
      await modele.connecter()
    }
  }
}

/// Colonne de gauche : connexion, état, puis liste des sessions.
/// Liste des sessions, destinée à l'emplacement LATÉRAL d'un `NavigationSplitView`.
///
/// POURQUOI CETTE VUE EXISTE SÉPARÉMENT, ET POURQUOI ELLE PORTE LA `List`.
/// Sur iOS, la sélection d'une liste liée à un `NavigationSplitView` n'est
/// fiable que si la `List` occupe directement l'emplacement latéral. Une liste
/// enveloppée dans une vue qui a son propre état de sélection ne pilote pas la
/// navigation : l'utilisateur appuie sur une ligne et rien ne s'ouvre. C'est
/// exactement le défaut observé — « Aucune session ouverte » après un appui.
struct VueListeSessions: View {
  @Bindable var modele: ModeleApp
  @Binding var selection: SessionListee?

  /// Espaces de travail dépliés, par identifiant.
  ///
  /// L'état est tenu par identifiant de chemin, pour que replier un espace ne
  /// touche pas aux autres et survive à un rafraîchissement de la liste. Un
  /// `DisclosureGroup` piloté par une constante ignorerait les clics.
  @State private var espacesDeplies: Set<String> = []

  var body: some View {
    // La List occupe DIRECTEMENT cet emplacement : c'est la condition pour que la
    // sélection pilote la navigation sur iOS.
    List(selection: $selection) {
    // ── Choix du serveur ───────────────────────────────────────────────────
    //
    // On choisit une MACHINE, pas une adresse. L'adresse en découle : personne
    // ne devrait avoir à taper un nom MagicDNS de 40 caractères pour dire
    // « le Mac mini ». Le champ d'adresse reste disponible plus bas pour les
    // cas que la découverte ne couvre pas.
    Section("Serveur") {
      if modele.serveurs.isEmpty {
        // Une liste vide DOIT s'expliquer, et l'explication dépend de la SOURCE :
        // « l'hôte joint ne voit aucun Mac » n'appelle pas la même action que
        // « cette plateforme ne peut pas découvrir ».
        VStack(alignment: .leading, spacing: 8) {
          Label(modele.messageListeVide, systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.orange)
          HStack(spacing: 12) {
            // « Rafraîchir » n'est proposé QUE là où le rafraîchissement peut
            // réellement rendre des machines : sur le Mac par la découverte
            // locale, sur iPhone par l'hôte une fois qu'un serveur est joint.
            // Ailleurs, le bouton ne produirait ni succès ni erreur — et un
            // bouton sans effet est un mensonge d'interface.
            if modele.rafraichissementPossible {
              Button("Rafraîchir la liste") { modele.rafraichirServeurs() }
                .font(.caption)
            }
            #if os(iOS)
              Button("Installer Tailscale") {
                if let url = URL(string: "https://apps.apple.com/app/tailscale/id1470499037") {
                  UIApplication.shared.open(url)
                }
              }
              .font(.caption)
            #endif
          }
        }
        .padding(.vertical, 4)
      } else {
        ForEach(modele.serveurs) { serveur in
          Button {
            Task { await modele.choisirEtConnecter(serveur) }
          } label: {
            HStack(spacing: 10) {
              Image(systemName: serveur.symbole)
                .font(.title3)
                .frame(width: 26)
                .foregroundStyle(serveur.enLigne ? Color.accentColor : Color.secondary)
              VStack(alignment: .leading, spacing: 2) {
                Text(serveur.nom).font(.body)
                Text(modele.legendeServeur(serveur))
                  .font(.caption2)
                  .foregroundStyle(serveur.enLigne ? Color.green : Color.secondary)
              }
              Spacer()
              if modele.serveurChoisi == serveur {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
              }
            }
          }
          .buttonStyle(.plain)
        }
        if modele.rafraichissementPossible {
          Button("Rafraîchir la liste") { modele.rafraichirServeurs() }
            .font(.caption)
        }
      }
    }

    Section(modele.serveurs.isEmpty ? "Serveur" : "Adresse") {
      LabeledContent("Adresse") {
        HStack(spacing: 8) {
          // L'icône dit à quelle machine on parle, d'un coup d'œil.
          Image(systemName: modele.symboleServeur)
            .font(.title3)
            .foregroundStyle(modele.adresse.isEmpty ? Color.secondary : Color.accentColor)
          // Liaison passant par le modèle : l'adresse est mémorisée dès la
          // frappe, sans attendre une connexion réussie.
          TextField(
            modele.adresseExemple,
            text: Binding(
              get: { modele.adresse },
              set: { modele.definirAdresse($0) }
            ))
            .textFieldStyle(.roundedBorder)
            #if os(iOS)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .keyboardType(.URL)
            #endif
          if !modele.adresse.isEmpty {
            Button {
              modele.oublierServeur()
            } label: {
              Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Oublier ce serveur")
          }
        }
      }
      if let nom = modele.nomServeur, !nom.isEmpty {
        Label(nom, systemImage: modele.symboleServeur)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      // Le champ du jeton est TOUJOURS visible.
      //
      // Il était auparavant conditionné par `!modele.jetonDisponible`, c'est-à-dire
      // caché dès qu'un jeton était présent. Le défaut : `jetonDisponible` devient
      // vrai dès le PREMIER caractère saisi, donc le champ disparaissait sous les
      // doigts de l'utilisateur, qui ne pouvait jamais terminer sa saisie. Un
      // formulaire dont un champ s'évapore à la frappe n'est pas un formulaire.
      //
      // Afficher aussi l'état permet de comprendre pourquoi « Se connecter »
      // fonctionne sans rien saisir sur le Mac.
      LabeledContent("Jeton") {
        HStack(spacing: 8) {
          SecureField(modele.jetonDisponible ? "déjà enregistré — saisir pour remplacer" : "jeton d'appareil", text: $modele.jetonSaisi)
            .textFieldStyle(.roundedBorder)
            #if os(iOS)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
            #endif
          // 43 caractères en base64url : les coller est plus sûr que les taper.
          Button {
            modele.collerLeJeton()
          } label: {
            Image(systemName: "doc.on.clipboard")
          }
          .buttonStyle(.borderless)
          .help("Coller le jeton depuis le presse-papier")
          if modele.jetonDisponible {
            Button {
              modele.effacerJeton()
            } label: {
              Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Effacer le jeton")
          }
        }
      }
      // L'état du jeton, en clair. Un champ de 43 caractères affiche des
      // puces : sans ce compte, un jeton tronqué est indiscernable d'un jeton
      // complet, et le 401 qui suit accuse le serveur à tort.
      if modele.jetonDisponible {
        Label(
          modele.jetonBienForme
            ? "jeton complet (43 caractères)"
            : "jeton incomplet : \(modele.longueurJeton) caractères au lieu de 43",
          systemImage: modele.jetonBienForme ? "checkmark.seal" : "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(modele.jetonBienForme ? Color.green : Color.orange)
      }
      HStack(spacing: 12) {
        Button("Se connecter") {
          Task { await modele.connecter() }
        }
        .disabled(modele.enChargement)
        // Vérifie l'adresse ET le jeton, et le dit. C'est l'action qui a du
        // sens quand on a saisi une adresse à la main.
        Button("Tester l'adresse") {
          Task { await modele.testerAdresse() }
        }
        .disabled(modele.enChargement || modele.adresse.isEmpty)
        if modele.enChargement { ProgressView().controlSize(.small) }
      }

      // Le résultat du test, nommé : « rien ne s'est passé » ne doit jamais
      // être une réponse possible à un appui.
      switch modele.etatAdresse {
      case .inconnu:
        EmptyView()
      case .enCours:
        Label("test de l'adresse…", systemImage: "hourglass").font(.caption)
      case let .joignable(reponses):
        Label("\(reponses) session(s) — adresse et jeton acceptés", systemImage: "checkmark.circle")
          .font(.caption)
          .foregroundStyle(.green)
      case let .injoignable(detail):
        Label(detail, systemImage: "xmark.circle")
          .font(.caption)
          .foregroundStyle(.red)
      }
    }

    if let erreur = modele.erreur {
      Section {
        Label(erreur, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
          .font(.callout)
      }
    }

    Section {
      // L'étiquette dit ce que le critère EST, pas ce qu'il suggère.
      //
      // « Vivantes » laissait croire à des sessions en train de travailler :
      // le propriétaire s'est étonné d'en compter dix. Or ce champ signifie
      // « chargée dans le processus du harness », c'est-à-dire prête à être
      // reprise instantanément — pas active. La nuance compte : dix sessions
      // actives serait anormal, dix sessions chargées est normal après une
      // journée de travail.
      Toggle("Chargées en mémoire seulement", isOn: $modele.filtresActifs)

      // Le suivi se voit et se commande : sans lui, les pastilles d'état
      // resteraient figées au moment du chargement, et une session qui se met
      // à travailler n'apparaîtrait jamais comme telle.
      Toggle("Suivre l'activité", isOn: $modele.suiviAutomatique)
    }

    // ── Arbre des sessions, groupé par espace de travail ───────────────────
    //
    // Une liste plate de plus de cent sessions mêlant dix projets est
    // illisible : on ne cherche pas « une session », on cherche « la session
    // de ce projet ». On reproduit donc l'arbre de l'interface web plutôt que
    // d'inventer une présentation différente pour le même contenu.
    Section {
      ForEach(modele.espaces) { espace in
        // Pendant une recherche, les groupes sont dépliés d'office : laisser
        // l'utilisateur replier chaque dossier pour voir ce qu'il vient de
        // chercher annulerait l'intérêt de la recherche.
        DisclosureGroup(
          isExpanded: Binding(
            get: { !modele.recherche.isEmpty || espacesDeplies.contains(espace.id) },
            set: { ouvert in
              if ouvert { espacesDeplies.insert(espace.id) } else { espacesDeplies.remove(espace.id) }
            }
          )
        ) {
          ForEach(espace.sessions, id: \.id) { session in
            if Regroupement.estSousAgent(session) {
              HStack(spacing: 6) {
                // Les sous-agents sont en retrait et marqués, comme dans
                // l'interface web : ce sont des sessions déléguées, pas des
                // conversations ouvertes par l'utilisateur.
                Image(systemName: "arrow.turn.down.right")
                  .font(.caption2)
                  .foregroundStyle(.tertiary)
                LigneSession(
                  affiche: AfficheLigneSession(
                    session: session, rappelDeFin: modele.aTermine(session.id))
                ).tag(session)
              }
              .padding(.leading, 14)
            } else {
              LigneSession(
                affiche: AfficheLigneSession(
                  session: session, rappelDeFin: modele.aTermine(session.id))
              ).tag(session)
            }
          }
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "folder")
              .foregroundStyle(Color.accentColor)
            Text(espace.nom).font(.body)
            Spacer()
            Text("\(espace.nbSessions)")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
      }
    } header: {
      // « Workspaces », comme la version web : c'est ce que la section liste,
      // et le nombre de sessions reste visible à côté.
      HStack {
        Text("Workspaces")
        Spacer()
        Text("\(modele.sessionsFiltrees.count) session\(modele.sessionsFiltrees.count > 1 ? "s" : "")")
      }
    }
  }
  }
}

/// Pastille d'état d'une session.
///
/// Quatre formes distinctes, pour ne pas confondre quatre situations :
/// des carrés qui tournent quand un tour s'exécute, un **point vert** quand un
/// tour vient de finir sans être vu, un point bleu pour une session chargée au
/// repos, un anneau vide quand l'état n'est pas connu.
struct PastilleEtat: View {
  let etat: EtatSession
  @State private var phase = 0.0

  var body: some View {
    Group {
      switch etat {
      case .enCours:
        // Quatre carrés qui tournent : le modèle travaille.
        HStack(spacing: 1.5) {
          ForEach(0..<2, id: \.self) { ligne in
            VStack(spacing: 1.5) {
              ForEach(0..<2, id: \.self) { colonne in
                RoundedRectangle(cornerRadius: 0.5)
                  .frame(width: 3, height: 3)
                  .opacity(opacite(ligne: ligne, colonne: colonne))
              }
            }
          }
        }
        .frame(width: 9, height: 9)
        .rotationEffect(.degrees(phase))
        .onAppear {
          withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
            phase = 360
          }
        }
        .foregroundStyle(Color.orange)
      case .terminee:
        // Le rappel de fin : plein et vert, jamais confondu avec le bleu du
        // repos. Il s'efface quand la session est ouverte.
        Circle().fill(Color.green).frame(width: 7, height: 7)
      case .inactive:
        Circle().fill(Color.blue).frame(width: 7, height: 7)
      case .inconnue:
        // Anneau vide, et non point plein : l'état n'est pas connu, et cela doit
        // se voir. Un point vert ici affirmerait « terminée », ce que le serveur
        // n'a pas dit.
        Circle()
          .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.5)
          .frame(width: 7, height: 7)
      }
    }
    .frame(width: 10, height: 10)
  }

  /// Les carrés s'allument en diagonale, ce qui donne une rotation lisible même
  /// sur 9 points de côté.
  private func opacite(ligne: Int, colonne: Int) -> Double {
    (ligne + colonne) % 2 == 0 ? 1.0 : 0.35
  }
}

/// Ce qu'une ligne de session affiche, en valeurs SIMPLES.
///
/// POURQUOI CE TYPE EXISTE — c'est un défaut réel, pas une élégance.
/// `SessionListee` a une égalité d'IDENTITÉ (projet + identifiant), et c'est
/// nécessaire : la sélection d'une liste est conservée d'un rafraîchissement à
/// l'autre, et une égalité par valeur ferait paraître la session sélectionnée
/// « différente » à chaque fois que son journal grandit — la sélection se
/// perdrait alors à chaque rafraîchissement de 3 secondes.
///
/// Mais SwiftUI se sert de `==` pour décider de REDESSINER une vue. Avec
/// l'identité seule, une ligne dont le statut change était considérée comme
/// inchangée : la liste interrogeait le serveur, recevait `inactif`, et
/// continuait d'afficher les carrés orange et un compteur périmé. Mesuré :
/// le serveur annonçait 30 enregistrements et la session au repos, l'écran
/// affichait encore « 27 évts » et l'animation, une minute plus tard.
///
/// La ligne reçoit donc des valeurs dont l'égalité est SYNTHÉTISÉE : elles
/// changent quand l'affichage doit changer. L'identité reste au modèle, la
/// comparaison d'affichage reste à la vue — chacun son rôle.
struct AfficheLigneSession: Equatable {
  let titre: String
  let etat: EtatSession
  let evenements: Int?
  let octets: Int?
  let age: String
  let illisible: String?

  init(session: SessionListee, rappelDeFin: Bool) {
    self.titre = session.titreAffiche
    self.etat = EtatSession(
      statut: session.statut, vivante: session.vivante, rappelDeFin: rappelDeFin)
    self.evenements = session.resume.nbEnregistrements
    self.octets = session.octets
    self.age = AgeLisible.texte(session.resume.dernierEvenementLe)
    self.illisible = session.illisible
  }
}

/// Une ligne de la liste : point d'état, titre, projet, volume et date.
struct LigneSession: View {
  let affiche: AfficheLigneSession

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        PastilleEtat(etat: affiche.etat)
        Text(affiche.titre)
          .lineLimit(1)
          .font(.body)
      }
      HStack(spacing: 8) {
        if let evenements = affiche.evenements {
          Text("\(evenements) évts")
        }
        if let octets = affiche.octets {
          Text(ByteCountFormatter.string(fromByteCount: Int64(octets), countStyle: .file))
        }
        Spacer()
        // L'âge, comme dans l'interface web : situe une session d'un coup d'œil.
        Text(affiche.age)
          .foregroundStyle(.tertiary)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      if let illisible = affiche.illisible {
        Text(illisible).font(.caption2).foregroundStyle(.orange)
      }
    }
    .padding(.vertical, 2)
  }
}
