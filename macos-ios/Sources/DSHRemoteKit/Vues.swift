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
      modele.relireEtatTailscale()
      modele.demarrerDecouverte()
      await modele.connecter()
    }
  }
}

/// Colonne de gauche : Tailscale, les serveurs, puis les sessions groupées.
///
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
  /// La feuille de configuration : adresse, jeton, filtres.
  @State private var reglagesOuverts = false

  /// Ancre de VÉRIFICATION, et rien d'autre.
  ///
  /// POURQUOI ELLE EXISTE. Le propriétaire ne peut pas juger l'arbre des
  /// sessions sur une capture où tous les espaces sont repliés, et piloter un
  /// simulateur à la souris depuis un script est fragile. `simctl launch`
  /// transmet ses arguments à `argv` : passer `--deplier` déplie donc tous les
  /// espaces, ce qui rend l'état visible sur une capture.
  ///
  /// PORTÉE RÉELLE : aucun effet sans cet argument, jamais transmis par un
  /// lancement depuis l'écran d'accueil — ni sur iPhone, ni sur Mac. Ce n'est
  /// pas un réglage caché : c'est un outil de constat, comme `DSH_REMOTE_ADRESSE`.
  private var deplieParArgument: Bool {
    ProcessInfo.processInfo.arguments.contains("--deplier")
  }

  var body: some View {
    // La List occupe DIRECTEMENT cet emplacement : c'est la condition pour que la
    // sélection pilote la navigation sur iOS.
    List(selection: $selection) {
      // ── Tailscale ──────────────────────────────────────────────────────────
      //
      // POURQUOI EN PREMIER. Sans Tailscale, l'application ne joint rien du
      // tout — et la cause est INVISIBLE : un tailnet déconnecté ressemble à un
      // serveur éteint, et l'utilisateur cherche la panne du mauvais côté. La
      // carte porte donc l'explication ET l'action, avant tout le reste.
      Section {
        CarteTailscale(modele: modele)
          .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 8, trailing: 0))
          .listRowBackground(Color.clear)
      } header: {
        EnteteSection("TailScale")
      }

      // ── Serveurs ───────────────────────────────────────────────────────────
      //
      // On choisit une MACHINE, pas une adresse. L'adresse en découle : personne
      // ne devrait avoir à taper un nom MagicDNS de 40 caractères pour dire
      // « le Mac mini ». La saisie manuelle reste possible, dans les réglages.
      Section {
        if modele.serveurs.isEmpty {
          // Une liste vide DOIT s'expliquer, et l'explication dépend de la
          // SOURCE : « l'hôte joint ne voit aucun Mac » n'appelle pas la même
          // action que « cette plateforme ne peut pas découvrir ».
          ServeursVides(modele: modele) { reglagesOuverts = true }
        } else {
          CarrouselServeurs(modele: modele)
            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 6, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
      } header: {
        EnteteSection(
          "Serveurs",
          detail: modele.serveurs.isEmpty
            ? nil : "\(modele.serveurs.filter(\.enLigne).count) en ligne")
      }

      if let erreur = modele.erreur {
        Section {
          VStack(alignment: .leading, spacing: 10) {
            Label(erreur, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.red)
              .font(.callout)
              .fixedSize(horizontal: false, vertical: true)
            // Un `401` propose l'action qui RÉPARE, à portée de pouce : le
            // jeton est recopié dans Réglages, et l'utilisateur n'a pas à
            // deviner où. Le bouton n'apparaît que pour cette cause-là : une
            // adresse injoignable, elle, ne se règle pas dans les réglages du
            // jeton.
            if modele.jetonRefuse {
              Button {
                reglagesOuverts = true
              } label: {
                Label("Recopier le jeton", systemImage: "key")
                  .font(.callout)
              }
              .buttonStyle(.bordered)
            }
          }
        }
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
              get: {
                !modele.recherche.isEmpty || deplieParArgument || espacesDeplies.contains(espace.id)
              },
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
        EnteteSection(
          "Workspaces",
          detail: "\(modele.sessionsFiltrees.count) session\(modele.sessionsFiltrees.count > 1 ? "s" : "")")
      }
    }
    // `insetGrouped` est INDISPONIBLE sur macOS — la compilation le refuse, et
    // pas seulement à l'exécution. Chaque plateforme reçoit donc le style qui
    // existe chez elle : iOS la liste encartée, macOS la liste latérale
    // habituelle, qui est déjà celle d'une colonne de navigation.
    #if os(iOS)
      .listStyle(.insetGrouped)
    #else
      .listStyle(.inset)
    #endif
    // Titre EN LIGNE, et non grand. Mesuré sur le prototype : le grand titre
    // coûtait 60 points pour répéter le nom de l'application, déjà connu de qui
    // l'ouvre — et ces 60 points manquaient aux sessions, dont deux seulement
    // restaient visibles. La carte, le carrousel et les workspaces tiennent
    // maintenant à l'écran, ce qui était l'objet de la refonte.
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .navigationTitle("DSH Remote")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          reglagesOuverts = true
        } label: {
          Image(systemName: "gearshape")
        }
        .accessibilityLabel("Réglages")
      }
    }
    .sheet(isPresented: $reglagesOuverts) {
      FeuilleReglages(modele: modele)
    }
    // La recherche ANCRÉE EN BAS, sous le pouce.
    //
    // POURQUOI PAS `.searchable`. La recherche de la barre de navigation se
    // replie sous un geste de défilement : avec cent sessions et des espaces
    // dépliés, on la perd exactement au moment où l'on en a besoin. Ancrée en
    // bas, elle reste accessible — c'est aussi la place qu'elle occupe dans
    // l'interface web, donc rien à réapprendre.
    .safeAreaInset(edge: .bottom, spacing: 0) {
      BarreRecherche(texte: $modele.recherche)
    }
  }
}

/// En-tête de section : la graisse des en-têtes natifs, avec une valeur à droite.
struct EnteteSection: View {
  let titre: String
  var detail: String?

  init(_ titre: String, detail: String? = nil) {
    self.titre = titre
    self.detail = detail
  }

  var body: some View {
    HStack {
      Text(titre)
      Spacer()
      if let detail {
        Text(detail).foregroundStyle(.secondary)
      }
    }
  }
}

// MARK: - Tailscale

/// La carte d'état de Tailscale : icône, titre, raison d'être, action.
///
/// La carte ENTIÈRE est la cible, avec un chevron : c'est la convention iOS pour
/// « cette ligne mène quelque part ». Le verbe de l'action est écrit dans la
/// description, pour qu'aucun appui ne soit un pari sur ce qui va s'ouvrir.
///
/// POURQUOI PAS UN BOUTON TEXTE. Deux dispositions ont été essayées sur le
/// prototype et écartées POUR UNE RAISON MESURÉE À L'ÉCRAN : un bouton pleine
/// largeur sous la carte (60 points de hauteur pour redire ce que la carte
/// venait de dire, et plus aucune session visible), puis un bouton capsule à
/// droite du titre (« Tailscale est connecté » se cassait sur deux lignes).
///
/// UN PIÈGE DE `Link` : sa teinte s'applique à TOUT son contenu. Dans l'état
/// « à installer », le titre et la description viraient au bleu du système, et
/// la carte se lisait comme une phrase cliquable au lieu d'un avertissement.
/// Chaque texte porte donc explicitement sa couleur, et la teinte ne colore que
/// le chevron — qui est l'affordance.
struct CarteTailscale: View {
  @Bindable var modele: ModeleApp

  private var etat: EtatTailscale { modele.etatTailscale }

  var body: some View {
    Button {
      switch etat {
      case .absent, .installe:
        // L'action peut échouer — Tailscale désinstallé entre l'affichage et
        // l'appui. On le DIT, plutôt que de laisser un appui sans effet.
        if !modele.ouvrirTailscale() {
          modele.signaler(
            "Tailscale n'a pas pu être ouvert. Vérifiez qu'il est bien installé, puis rouvrez DSH Remote.")
        }
      case .connecte:
        modele.rafraichirServeurs()
      }
    } label: {
      contenu
    }
    .buttonStyle(.plain)
    .tint(teinte)
  }

  private var contenu: some View {
    HStack(spacing: 12) {
      Image(systemName: symbole)
        .font(.system(size: 28, weight: .semibold))
        .foregroundStyle(teinte)
        .frame(width: 34)
      VStack(alignment: .leading, spacing: 3) {
        Text(titre)
          .font(.headline)
          .foregroundStyle(Color.primary)
        Text(detail)
          .font(.footnote)
          .foregroundStyle(Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 4)
      Image(systemName: "chevron.right")
        .font(.footnote.weight(.semibold))
    }
    .padding(14)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .strokeBorder(teinte.opacity(0.25), lineWidth: 1)
    }
  }

  private var teinte: Color {
    switch etat {
    case .connecte: return .green
    case .installe: return .orange
    case .absent: return .blue
    }
  }

  private var symbole: String {
    switch etat {
    case .connecte: return "checkmark.seal.fill"
    case .installe: return "arrow.up.forward.app"
    case .absent: return "arrow.down.circle"
    }
  }

  private var titre: String {
    switch etat {
    case .connecte: return "Tailscale est connecté"
    case .installe: return "Tailscale est installé"
    case .absent: return "Tailscale n'est pas installé"
    }
  }

  private var detail: String {
    switch etat {
    case .absent:
      return
        "Touchez pour l'installer : c'est lui qui relie cet appareil au Mac, sans câble ni configuration réseau."
    case .installe:
      return
        "Touchez pour l'ouvrir et vous connecter. Sans connexion au tailnet, aucun Mac n'est joignable."
    case .connecte:
      let enLigne = modele.serveurs.filter(\.enLigne).count
      return
        "Touchez pour vérifier : \(enLigne) Mac\(enLigne > 1 ? "s" : "") répond\(enLigne > 1 ? "ent" : "") sur le tailnet."
    }
  }
}

// MARK: - Serveurs

/// Les serveurs en carrousel d'icônes, comme des icônes d'applications.
///
/// POURQUOI CE RENDU PLUTÔT QU'UNE LISTE DE LIGNES. Une liste de lignes dit
/// « réglage » ; un carrousel d'icônes dit « appareil ». Or c'est bien de cela
/// qu'il s'agit : chaque icône EST une machine, avec son icône de châssis, son
/// état, et son nom raccourci au premier mot — la forme sous laquelle on
/// reconnaît un appareil.
///
/// Le défilement est un `ScrollView` et non un `TabView` : avec quatre Macs ou
/// plus, un carrousel paginé cacherait la moitié des machines derrière un geste
/// que rien n'annonce.
struct CarrouselServeurs: View {
  @Bindable var modele: ModeleApp

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 16) {
        ForEach(modele.serveurs) { serveur in
          Button {
            Task { await modele.choisirEtConnecter(serveur) }
          } label: {
            IconeServeur(serveur: serveur, choisi: modele.serveurChoisi == serveur)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            "\(serveur.nom), \(serveur.enLigne ? "en ligne" : "hors ligne")\(serveur.estLocal ? ", hôte interrogé" : "")"
          )
        }
        // « Rafraîchir » n'est proposé QUE là où le rafraîchissement peut
        // réellement rendre des machines : sur le Mac par la découverte locale,
        // sur iPhone par l'hôte une fois qu'un serveur est joint. Ailleurs, le
        // bouton ne produirait ni succès ni erreur — et un bouton sans effet est
        // un mensonge d'interface.
        if modele.rafraichissementPossible {
          Button {
            modele.rafraichirServeurs()
          } label: {
            VStack(spacing: 6) {
              RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(
                  Color.secondary.opacity(0.45),
                  style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
                .frame(width: 62, height: 62)
                .overlay {
                  Image(systemName: "arrow.clockwise")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.secondary)
                }
              Text("Rafraîchir")
                .font(.caption2)
                .foregroundStyle(Color.secondary)
                .frame(width: 68)
            }
            .frame(width: 68, height: 68)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Rafraîchir la liste des serveurs")
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 4)
    }
    .scrollClipDisabled()
  }
}

/// Une icône de serveur : la vignette, la pastille d'état, le nom d'un mot.
struct IconeServeur: View {
  let serveur: ServeurMac
  let choisi: Bool

  var body: some View {
    VStack(spacing: 6) {
      ZStack {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
          .fill(
            LinearGradient(
              colors: serveur.enLigne
                ? [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.65)]
                : [Color.secondary.opacity(0.45), Color.secondary.opacity(0.28)],
              startPoint: .topLeading, endPoint: .bottomTrailing)
          )
          .frame(width: 62, height: 62)
          .overlay {
            Image(systemName: serveur.symbole)
              .font(.system(size: 27, weight: .regular))
              .foregroundStyle(.white)
          }
        // La sélection est une COCHE, dans le coin, et non un contour : sur une
        // vignette déjà colorée, un anneau de 2 points se confond avec ses
        // propres bords — mesuré sur le prototype, le serveur choisi ne se
        // distinguait pas des autres. Le coin haut-gauche est libre : la
        // pastille d'état occupe le coin bas-droit.
        if choisi {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 19))
            .foregroundStyle(.white, Color.accentColor)
            .offset(x: -29, y: -29)
        }
      }
      .frame(width: 62, height: 62)
      .overlay(alignment: .bottomTrailing) {
        Circle()
          .fill(serveur.enLigne ? Color.green : Color.gray)
          .frame(width: 15, height: 15)
          .overlay { Circle().strokeBorder(.background, lineWidth: 2.5) }
          .offset(x: 3, y: 3)
      }
      .frame(width: 68, height: 68)

      Text(serveur.premierMot)
        .font(.caption2)
        .lineLimit(1)
        .foregroundStyle(choisi ? Color.primary : Color.secondary)
        .frame(width: 68)
      // « hôte interrogé » : la seule mention qui vient de l'hôte, et non du nom
      // de la machine. Réservée en place (`opacity`) pour que les icônes restent
      // alignées entre elles.
      Text("hôte")
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
        .opacity(serveur.estLocal ? 1 : 0)
    }
  }
}

/// Ce qu'on voit quand aucun Mac n'a été trouvé : la cause ET l'action.
struct ServeursVides: View {
  let modele: ModeleApp
  let ouvrirReglages: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(modele.messageListeVide, systemImage: "wifi.exclamationmark")
        .font(.callout)
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 12) {
        Button {
          ouvrirReglages()
        } label: {
          Label("Saisir une adresse", systemImage: "keyboard")
            .font(.callout)
        }
        .buttonStyle(.bordered)
        // Le bouton n'apparaît que là où il peut agir : sur iPhone, la
        // découverte locale est impossible, et un bouton sans effet est un
        // mensonge d'interface.
        if modele.rafraichissementPossible {
          Button("Rafraîchir") { modele.rafraichirServeurs() }
            .font(.callout)
            .buttonStyle(.bordered)
        }
      }
    }
    .padding(.vertical, 4)
  }
}

// MARK: - Recherche

/// La recherche, en bas et toujours là.
struct BarreRecherche: View {
  @Binding var texte: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField("Rechercher une session, un projet…", text: $texte)
        .textFieldStyle(.plain)
        .autocorrectionDisabled()
        #if os(iOS)
          .textInputAutocapitalization(.never)
        #endif
      if !texte.isEmpty {
        Button {
          texte = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Effacer la recherche")
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(.quaternary, lineWidth: 1)
    }
    .padding(.horizontal, 16)
    // La barre FLOTTE au-dessus du contenu, avec de l'air : collée à la
    // dernière ligne, elle se lisait comme une ligne de plus sur le prototype.
    // La bande est en matière, comme une barre d'outils, pour que le contenu qui
    // défile passe visiblement DERRIÈRE elle.
    .padding(.top, 8)
    .padding(.bottom, 10)
    .background(.bar)
  }
}

/// Pastille d'état d'une session.
///
/// Cinq cas, dont un qui ne s'affiche PAS : la session au repos ne porte aucun
/// indicateur. Une pastille permanente pour l'état le plus banal apprend à
/// l'utilisateur à ne plus les regarder — et c'est précisément quand l'une change
/// qu'il faut qu'elle se voie.
struct PastilleEtat: View {
  let etat: EtatSession
  @State private var phase = 0.0

  var body: some View {
    Group {
      switch etat {
      case .rien:
        // Volontairement vide, en conservant l'emplacement : le titre reste
        // aligné avec les lignes qui, elles, portent un indicateur.
        Color.clear
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
      case .attendReponse:
        // Un point orange PLEIN, et non les carrés : ce n'est pas « ça tourne »,
        // c'est « ça t'attend ». La distinction visuelle est le fond du message —
        // une session bloquée sur une question ne repartira pas toute seule.
        Circle().fill(Color.orange).frame(width: 8, height: 8)
      case .terminee:
        // Le rappel de fin : plein et vert. Il s'efface quand la session est
        // ouverte.
        Circle().fill(Color.green).frame(width: 7, height: 7)
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
      statut: session.statut, vivante: session.vivante, rappelDeFin: rappelDeFin,
      attendReponse: session.attendReponse == true)
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
