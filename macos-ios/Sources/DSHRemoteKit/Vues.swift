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
  /// La feuille de réglages. Elle est tenue ICI parce que trois endroits
  /// l'ouvrent : la barre d'outils, le panneau latéral, la page d'un serveur.
  @State private var reglagesOuverts = ProcessInfo.processInfo.arguments.contains("--reglages")
  /// La saisie manuelle d'une adresse : le chemin des cas que la découverte ne
  /// couvre pas. Elle n'est plus dans les réglages — une adresse est celle d'UNE
  /// machine, pas un réglage de l'application.
  @State private var adresseOuverte = ProcessInfo.processInfo.arguments.contains("--adresse")

  public init() {}

  /// Ancre de VÉRIFICATION, et rien d'autre : `--serveur` ouvre la page du
  /// premier serveur au lancement, ce qui permet de la CAPTURER sans piloter la
  /// souris. Même rôle que `--reglages` et `--deplier` : aucun effet sans
  /// l'argument, jamais transmis par un lancement depuis le Dock.
  /// Le nom demandé par `--serveur=<fragment>`, s'il y en a un.
  /// La machine désignée par `--serveur=<fragment>`, si elle existe dans la liste.
  private var machineNommee: ServeurMac? {
    guard let demande = VuePrincipale.nomDeMachineDemande else { return nil }
    return modele.serveurs.first { machine in
      machine.nom.lowercased().contains(demande) || machine.nomDNS.lowercased().contains(demande)
    }
  }

  /// La machine que `--page-seule` affiche.
  ///
  /// ELLE RÉSOUT ELLE-MÊME, ET C'EST UNE CORRECTION : avec `--page-seule`, le
  /// panneau latéral n'est pas rendu — donc l'ancre `--serveur=` qui y vit ne
  /// s'exécutait jamais, et la page affichée était toujours celle du serveur
  /// visé. La capture montrait le MacBook Air quand on avait demandé MacMini.
  private var machineDeLaPageSeule: ServeurMac? {
    machineNommee ?? modele.serveurChoisi ?? modele.serveurs.first
  }

  private static var nomDeMachineDemande: String? {
    for argument in ProcessInfo.processInfo.arguments where argument.hasPrefix("--serveur=") {
      let valeur = argument.dropFirst("--serveur=".count).lowercased()
      if !valeur.isEmpty { return valeur }
    }
    return nil
  }

  private var serveurParArgument: Bool {
    ProcessInfo.processInfo.arguments.contains("--serveur")
  }

  /// Ancre de VÉRIFICATION : `--page-seule` remplace la fenêtre entière par la
  /// page du serveur courant.
  ///
  /// POURQUOI ELLE EXISTE, EN PLUS DE `--serveur`. Sur iPhone, la page d'un
  /// serveur s'EMPILE : elle n'est visible qu'après un appui sur une icône, et
  /// cet environnement n'injecte pas d'appui dans le simulateur. Sans cette
  /// ancre, la page ne pourrait être ni capturée ni jugée sur iPhone — or c'est
  /// là qu'elle a le plus de raisons d'être mal fichue, faute de place.
  private var pageSeuleParArgument: Bool {
    ProcessInfo.processInfo.arguments.contains("--page-seule")
  }

  /// La machine affichée, résolue dans la liste courante.
  ///
  /// L'état vit dans le MODÈLE (`serveurOuvert`) et non ici : la vignette du
  /// panneau latéral doit le connaître pour montrer la page ouverte, et elle est
  /// trop loin dans la hiérarchie pour qu'on lui passe une liaison sans la
  /// traverser de bout en bout.
  private var serveurDeLaPage: ServeurMac? {
    guard let identifiant = modele.serveurOuvert else { return nil }
    return modele.serveurs.first { $0.id == identifiant }
  }

  /// La machine visée par l'adresse courante, quand une erreur l'attend.
  private var serveurDUneErreur: ServeurMac? {
    guard modele.erreur != nil else { return nil }
    return modele.serveurVise
  }

  public var body: some View {
    Group {
      if pageSeuleParArgument, let serveur = machineDeLaPageSeule {
        // Ancre de vérification : la page seule, pour la capturer.
        NavigationStack {
          VueServeur(modele: modele, serveur: serveur) { reglagesOuverts = true }
        }
      } else {
        contenu
      }
    }
  }

  private var contenu: some View {
    NavigationSplitView {
      VueListeSessions(
        modele: modele,
        selection: $sessionSelectionnee,
        reglagesOuverts: $reglagesOuverts,
        adresseOuverte: $adresseOuverte,
        // Toucher une machine ouvre SA page : c'est là que vivent son état
        // détaillé, ses actions et les remèdes. La sélection de session est
        // effacée, sans quoi le journal resterait affiché par-dessus.
        surSelectionServeur: { serveur in
          sessionSelectionnee = nil
          modele.ouvrirPage(serveur)
        })
    } detail: {
      if let session = sessionSelectionnee {
        VueJournal(modele: modele, session: session)
      } else if let serveur = serveurDeLaPage ?? serveurDUneErreur {
        VueServeur(modele: modele, serveur: serveur) { reglagesOuverts = true }
      } else {
        ContentUnavailableView(
          "Aucune session ouverte",
          systemImage: "terminal",
          description: Text("Choisissez une session dans la liste pour lire son journal.")
        )
      }
    }
    .sheet(isPresented: $reglagesOuverts) {
      FeuilleReglages(modele: modele)
    }
    .sheet(isPresented: $adresseOuverte) {
      FeuilleAdresse(modele: modele)
    }
    .task {
      if modele.jetonSaisi.isEmpty, let local = CoffreDuHarness.jetonDeLaMachine() {
        modele.enregistrerJeton(local)
      }
      modele.relireEtatTailscale()
      let debutDemarrage = Date()
      Trace.siActive("[demarrage] debut, adresse=\(modele.adresse)")
      // UN SEUL point d'entrée : il choisit une machine joignable AVANT de se
      // connecter. `demarrerDecouverte` reste pour le rafraîchissement manuel.
      await modele.demarrer()
      Trace.siActive("[demarrage] demarrer() : \(Int(Date().timeIntervalSince(debutDemarrage) * 1000)) ms")
      if serveurParArgument, modele.serveurOuvert == nil {
        // `--serveur=macmini` ouvre UNE machine nommée ; `--serveur` seul ouvre
        // celle qui est visée. La forme nommée est ce qui permet de capturer la
        // page d'une machine à laquelle on n'est PAS connecté — le cas même du
        // remède d'installation, qui n'a de sens que là.
        if let cible = machineDeLaPageSeule { modele.ouvrirPage(cible) }
      }
    }
    // ── POURQUOI UNE ERREUR FORCE LA PAGE DU SERVEUR ───────────────────────
    //
    // Le diagnostic a quitté le panneau latéral : sans cette règle, un échec de
    // connexion au lancement ne s'afficherait NULLE PART, et l'écran se
    // contenterait d'un « aucune session ouverte » — c'est-à-dire d'un silence.
    // L'erreur concerne une machine : on montre sa page.
    .onChange(of: modele.erreur) { _, nouvelle in
      guard nouvelle != nil, sessionSelectionnee == nil, modele.serveurOuvert == nil else { return }
      if let vise = modele.serveurVise { modele.ouvrirPage(vise) }
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
  /// La feuille de réglages, tenue par `VuePrincipale` : trois endroits
  /// l'ouvrent — barre d'outils, panneau latéral, page d'un serveur — elle ne
  /// peut donc appartenir à aucun d'eux.
  @Binding var reglagesOuverts: Bool
  /// La saisie manuelle d'une adresse, tenue par `VuePrincipale`.
  @Binding var adresseOuverte: Bool
  /// Appelé quand une machine est touchée : la page de droite devient la sienne.
  var surSelectionServeur: (ServeurMac) -> Void

  /// Espaces de travail dépliés, par identifiant.
  ///
  /// L'état est tenu par identifiant de chemin, pour que replier un espace ne
  /// touche pas aux autres et survive à un rafraîchissement de la liste. Un
  /// `DisclosureGroup` piloté par une constante ignorerait les clics.
  @State private var espacesDeplies: Set<String> = []

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
  /// Combien de machines sont UTILISABLES : en ligne **et** DSH joignable.
  ///
  /// POURQUOI CE N'EST PLUS « N en ligne ». Le compte annonçait des machines
  /// allumées, alors que la section liste des SERVEURS DSH : une machine en ligne
  /// dont DSH ne répond pas n'est pas un serveur utilisable. Le titre et le
  /// compte disent maintenant la même chose que ce que la liste sert à faire.
  ///
  /// Tant que la sonde n'a pas rendu son verdict, annoncer « 0 » serait faux :
  /// on ne sait pas encore — et le titre le dit, au lieu de compter faux.
  private var resumeServeurs: String? {
    guard !modele.serveurs.isEmpty else { return nil }
    guard case .connue = modele.sonde else { return "vérification…" }
    let joignables = modele.serveurs.filter { $0.enLigne && modele.sertDsh($0) == true }.count
    return "\(joignables) joignable\(joignables > 1 ? "s" : "")"
  }

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
          .sansSeparateurMac()
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
          // « Saisir une adresse » ouvre la SAISIE D'ADRESSE, et non les
          // réglages généraux : c'est une machine qu'on vise, pas un réglage de
          // l'application.
          ServeursVides(modele: modele) { adresseOuverte = true }
            .sansSeparateurMac()
        } else {
          CarrouselServeurs(modele: modele, surSelectionServeur: surSelectionServeur)
            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 6, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
      } header: {
        // ── LE TITRE DIT CE QUE LA SECTION SERT, LE COMPTE DIT CE QUI MARCHE ─
        //
        // « Serveurs » ne disait pas de quel genre de serveur il s'agit — et
        // cette liste ne contient QUE des machines capables d'héberger DSH.
        // Quant au compte, « 2 en ligne » comptait des machines allumées : une
        // machine en ligne dont DSH n'est pas joignable n'est PAS un serveur
        // utilisable, et l'annoncer la faisait passer pour tel. Le nombre est
        // donc celui des machines EN LIGNE **ET** dont DSH répond — la liste,
        // elle, continue de toutes les montrer, avec leurs états.
        EnteteSection("Serveur DeepSeek Harness", detail: resumeServeurs)
      }

      // ── Ce qui est PARTI sur la page du serveur ──────────────────────────
      //
      // La bascule de serveur, le diagnostic et les commandes à recopier ne
      // sont plus ici : ils vivent sur la page de la machine concernée
      // (`VueServeur`), qu'on ouvre en touchant son icône. Le panneau latéral
      // garde ce qui se lit d'un coup d'œil — pastille, légende, nom — et
      // rend la place aux sessions, qui sont ce qu'on vient y chercher.

      // ── Arbre des sessions, groupé par espace de travail ───────────────────
      //
      // Une liste plate de plus de cent sessions mêlant dix projets est
      // illisible : on ne cherche pas « une session », on cherche « la session
      // de ce projet ». On reproduit donc l'arbre de l'interface web plutôt que
      // d'inventer une présentation différente pour le même contenu.
      Section {
        ForEach(modele.espaces) { espace in
          // Un espace ENREGISTRÉ mais sans session n'est pas un dossier à
          // déplier : il n'a rien à montrer, et un chevron qui ne révèle rien
          // est un mensonge d'interface. Il est donc rendu à plat, avec une
          // icône distincte — la différence que l'interface web fait entre un
          // espace utilisé et un dossier choisi mais encore vide.
          if espace.sansSession {
            HStack(spacing: 8) {
              Image(systemName: "tray")
                .foregroundStyle(.secondary)
              Text(espace.nom).font(.body)
              Spacer()
              Text("aucune session")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .sansSeparateurMac()
          } else {
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
                  .sansSeparateurMac()
                } else {
                  LigneSession(
                    affiche: AfficheLigneSession(
                      session: session, rappelDeFin: modele.aTermine(session.id))
                  ).tag(session)
                  .sansSeparateurMac()
                }
              }
            } label: {
              HStack(spacing: 8) {
                Image(systemName: espace.horsEspaces ? "folder.badge.questionmark" : "folder")
                  .foregroundStyle(Color.accentColor)
                Text(espace.nom).font(.body)
                Spacer()
                Text("\(espace.nbSessions)")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
            .sansSeparateurMac()
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
      // LARGEUR MINIMALE DE LA COLONNE, ET C'EST UN DÉFAUT MESURÉ.
      //
      // Sur macOS, `NavigationSplitView` laisse la colonne latérale se réduire
      // jusqu'à une centaine de points : la carte Tailscale, le carrousel de
      // serveurs et le titre des workspaces y sont alors ILLISIBLES — le
      // propriétaire a vu la colonne réduite à une bande vide, avec la seule
      // pastille verte de la carte qui dépassait. Aucune vue de ce contenu ne
      // tient sous 280 points : la colonne ne descend donc plus jusque-là.
      //
      // 320 points est la largeur à laquelle la carte, le carrousel à trois
      // icônes (3 × 68 + marges) et une ligne de session tiennent sans
      // troncature.
      .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 480)
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
    #if os(iOS)
      // La destination des icônes de serveur, déclarée DANS la colonne qui
      // l'affiche : sur iPhone elle s'empile, sur iPad elle remplit le détail.
      .navigationDestination(for: ServeurMac.self) { serveur in
        VueServeur(modele: modele, serveur: serveur) { reglagesOuverts = true }
      }
    #endif
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
    // LA SONDE PART D'ICI, ET C'EST UNE CORRECTION DE COURSE.
    //
    // Elle était lancée par `demarrerDecouverte`, donc AVANT que Tailscale ait
    // rendu sa liste : le garde-fou la renvoyait faute de candidats, et rien ne
    // la relançait. Résultat mesuré : toutes les icônes restaient ORANGE, et le
    // Mac pourtant vert — celui qui sert DSH — n'obtenait jamais son verdict.
    //
    // `task(id:)` la relance à chaque changement RÉEL de la liste (l'empreinte
    // ne dépend pas de l'état en ligne), donc une seule fois à l'arrivée des
    // serveurs, et de nouveau si le tailnet en gagne ou en perd un.
    .task(id: modele.empreinteServeurs) {
      guard !modele.empreinteServeurs.isEmpty else { return }
      // L'ORDRE COMPTE : on écarte d'abord une machine hors ligne, on sonde
      // ensuite. Sonder d'abord ferait attendre deux secondes et demie pour un
      // verdict dont on n'a plus besoin.
      await modele.ajusterAuParc()
      await modele.sonderLesServeurs()
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
      case .absent:
        // Seul cas où l'on ouvre Tailscale : quand il n'est pas INSTALLÉ, le
        // lien mène à l'App Store, et un appui sans effet serait un mensonge.
        if !modele.ouvrirTailscale() {
          modele.signaler(
            "L'App Store n'a pas pu être ouvert. Cherchez « Tailscale » à la main.")
        }
      case .installe:
        // L'APPUI N'OUVRE PAS TAILSCALE, ET C'EST UN DÉFAUT CORRIGÉ.
        //
        // `tailscale://` fonctionne — mais son gestionnaire, dans l'application
        // Tailscale, déclenche un flux d'ENREGISTREMENT D'APPAREIL. Sur l'iPhone
        // du propriétaire, il a affiché « Could not sign device : unable to
        // verify deeplink » : notre bouton jetait l'utilisateur dans un
        // cul-de-sac d'une autre application. L'appui relit donc l'état, et la
        // carte dit quoi faire.
        modele.relireEtatTailscale()
        Task { await modele.synchroniserServeurs() }
      case .connecte:
        modele.relireEtatTailscale()
        Task { await modele.synchroniserServeurs() }
      }
    } label: {
      contenu
    }
    .buttonStyle(.plain)
    .tint(teinte)
  }

  private var contenu: some View {
    HStack(spacing: 12) {
      // L'ICÔNE EST CENTRÉE VERTICALEMENT SUR TOUTE LA CARTE, et ce n'est pas
      // cosmétique : sans le `maxHeight: .infinity`, SwiftUI la centrait sur sa
      // seule ligne, qui est plus courte que la description — l'icône
      // descendait donc d'une dizaine de points, et le dessin du bouton
      // « Rafraîchir » ne tombait plus à la même hauteur que celui des serveurs.
      // Défaut vu sur deux captures du Mac.
      Image(systemName: symbole)
        .font(.system(size: 28, weight: .semibold))
        .foregroundStyle(teinte)
        .frame(width: 34, height: 68)
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
      // On dit QUOI FAIRE plutôt que d'ouvrir une autre application de force :
      // c'est la leçon du deep link qui échouait.
      return
        "Ouvrez Tailscale depuis vos apps et connectez-vous : sans le tailnet, aucun Mac n'est joignable. Touchez ici pour relire l'état."
    case .connecte:
      // L'état « connecté » ne dépend plus d'un serveur en ligne : il vient de
      // l'adresse de tailnet portée par l'appareil. Il faut donc distinguer le
      // cas où aucun Mac ne publie DSH — sinon la carte annoncerait « 0 Mac
      // répond » comme si c'était une panne de Tailscale.
      let enLigne = modele.serveurs.filter(\.enLigne).count
      if enLigne == 0 {
        return
          "Cet appareil est bien sur le tailnet. Touchez pour chercher les Macs qui publient DSH — la liste peut être vide si aucun n'est allumé."
      }
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
  /// Touché une machine : la page de droite devient la sienne.
  var surSelectionServeur: (ServeurMac) -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 16) {
        ForEach(modele.serveurs) { serveur in
          // ── TOUCHER UNE MACHINE OUVRE SA PAGE ET S'Y CONNECTE ─────────────
          //
          // Deux effets pour un geste, et c'est délibéré : on touche une machine
          // pour s'y connecter, et la page est ce qui EXPLIQUE le résultat —
          // état, adresse, jeton, remèdes. Ce qui a changé par rapport au début
          // n'est pas le geste, c'est l'ENDROIT du diagnostic : il s'affichait
          // dans la colonne de gauche, au milieu des sessions ; il vit
          // maintenant sur la page de la machine concernée.
          //
          // DEUX MÉCANISMES, PARCE QUE LES PLATEFORMES DIFFÈRENT. Sur macOS, les
          // deux colonnes sont visibles : la page remplace le contenu de droite.
          // Sur iPhone, la colonne de détail n'existe pas : il faut EMPILER la
          // page (`NavigationLink`), sinon l'appui ne montre rien — et un appui
          // qui ne montre rien est un appui cassé.
          #if os(iOS)
            NavigationLink(value: serveur) {
              IconeServeur(
                serveur: serveur,
                choisi: modele.serveurChoisi == serveur,
                sertDsh: modele.sertDsh(serveur))
            }
            .buttonStyle(.plain)
            // Le lien EMPILE la page ; ce geste simultané dit au modèle laquelle
            // est ouverte (pour que la vignette l'indique) ET lance la connexion.
            .simultaneousGesture(
              TapGesture().onEnded {
                surSelectionServeur(serveur)
                Task { await modele.choisirEtConnecter(serveur) }
              })
            .accessibilityLabel(
              "\(serveur.nom), \(serveur.enLigne ? "en ligne" : "hors ligne")\(serveur.estLocal ? ", hôte interrogé" : "")"
            )
          #else
            Button {
              // OUVRIR **ET** CONNECTER — les deux, et c'est une correction.
              //
              // J'avais séparé les deux gestes : l'appui ouvrait la page, et il
              // fallait ensuite viser « Se connecter ». Le propriétaire a
              // demandé le contraire : « je voulais lancer une méthode ».
              // Toucher une machine, c'est vouloir s'y connecter ; la page, elle,
              // est ce qui l'EXPLIQUE quand ça ne marche pas.
              surSelectionServeur(serveur)
              Task { await modele.choisirEtConnecter(serveur) }
            } label: {
              IconeServeur(
                serveur: serveur,
                choisi: modele.serveurChoisi == serveur,
                sertDsh: modele.sertDsh(serveur))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
              "\(serveur.nom), \(serveur.enLigne ? "en ligne" : "hors ligne")\(serveur.estLocal ? ", hôte interrogé" : "")"
            )
          #endif
        }
        // « Rafraîchir » n'est proposé QUE là où le rafraîchissement peut
        // réellement rendre des machines : sur le Mac par la découverte locale,
        // sur iPhone par l'hôte une fois qu'un serveur est joint. Ailleurs, le
        // bouton ne produirait ni succès ni erreur — et un bouton sans effet est
        // un mensonge d'interface.
        // LE BOUTON EN POINTILLÉS CHERCHE, IL NE RAFRAÎCHIT PLUS.
        //
        // La liste se rafraîchit toute seule (voir `synchroniserServeurs`), donc
        // un bouton « Rafraîchir » n'avait plus de raison d'être. En revanche,
        // « chercher un Mac » en a une, et c'est la seule façon d'en AJOUTER un
        // sur iPhone : la découverte locale y est impossible, et l'hôte joint ne
        // republie sa liste que si on le lui demande.
        if modele.rechercheServeursPossible {
          BoutonAjouterServeur(enRecherche: modele.synchronisationEnCours) {
            Task { await modele.synchroniserServeurs() }
          }
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
  /// Le serveur CONNECTÉ, donc celui dont la page est ouverte : une coche.
  ///
  /// POURQUOI UN SEUL SIGNAL. J'avais ajouté un anneau bleu autour de la vignette
  /// lue, pour distinguer « connecté » de « page ouverte ». Le propriétaire l'a
  /// fait retirer : depuis que l'appui CONNECTE, les deux états coïncident
  /// toujours, et la coche du coin suffit. Un signal qui ne dit jamais rien de
  /// plus qu'un autre est du bruit.
  let choisi: Bool

  /// Le Mac sert-il DSH ? `nil` = pas encore su.
  ///
  /// POURQUOI CE TROISIÈME ÉTAT EXISTE. La découverte liste tous les Macs du
  /// tailnet, mais seuls ceux qui publient DSH peuvent répondre. Tant que la
  /// sonde n'a pas rendu son verdict, l'icône ne doit RIEN affirmer : c'est un
  /// « je ne sais pas », pas un « non ».
  let sertDsh: Bool?

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
        // Vert : en ligne ET DSH vérifié. Orange : en ligne, mais la sonde n'a
        // pas encore répondu. Gris : hors ligne, ou DSH absent — dans les deux
        // cas, appuyer ne donnera rien.
        Circle()
          .fill(couleurPastille)
          .frame(width: 15, height: 15)
          .overlay { Circle().strokeBorder(.background, lineWidth: 2.5) }
          .offset(x: 3, y: 3)
      }
      .frame(width: 68, height: 68)
      // Une vignette SANS DSH est atténuée : c'est ce qui se voit d'un coup
      // d'œil, avant même de lire la légende.
      .opacity(sertDsh == false ? 0.55 : 1)

      Text(serveur.premierMot)
        .font(.caption2)
        .lineLimit(1)
        .foregroundStyle(choisi ? Color.primary : Color.secondary)
        .frame(width: 68)
      // La légende dit l'état RÉEL : « hôte » pour la machine interrogée, et
      // « pas de DSH » pour celle dont la sonde a montré qu'elle ne répondra
      // pas. Réservée en place (`opacity`) pour que les icônes restent alignées.
      Text(legende)
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
        .frame(width: 68)
        .opacity(legende.isEmpty ? 0 : 1)
    }
  }

  /// Le POINT dit si la MACHINE répond ; la LÉGENDE dit si DSH y répond.
  ///
  /// POURQUOI LES SÉPARER — c'est une distinction que le propriétaire a
  /// lui-même formulée : « savoir si le serveur est en ligne est une chose,
  /// savoir s'il est DSH joignable en est une autre ». La version précédente
  /// les confondait : le même point GRIS servait à « machine éteinte » et à
  /// « machine allumée, mais rien n'écoute ». Or les deux n'appellent pas la
  /// même action — allumer un Mac, ou y publier DSH avec `tailscale serve`.
  ///
  /// Le cas qui a rendu le défaut visible : MacMini répond au ping en 7 ms
  /// (`en ligne`) et ses ports 80, 443 et 3080 sont tous fermés (`pas de DSH`).
  /// Il affichait pourtant le même point qu'un Mac éteint depuis 206 jours.
  private var couleurPastille: Color {
    // Vert : la machine répond. Gris : elle ne répond pas — inutile d'aller
    // plus loin, et la légende n'ajoutera rien.
    serveur.enLigne ? .green : .gray
  }

  /// Légende sous le nom : ce qui RESTE à savoir après l'état de la machine.
  private var legende: String {
    guard serveur.enLigne else { return "hors ligne" }
    switch sertDsh {
    case true: return serveur.estLocal ? "DSH · hôte" : "DSH"
    case false: return "pas de DSH"
    case nil: return "vérification…"
    }
  }
}

/// Le bouton « Ajouter », à la même place qu'une icône de serveur.
///
/// POURQUOI « AJOUTER » ET NON « RAFRAÎCHIR ». La liste se rafraîchit
/// automatiquement toutes les quinze secondes ; un bouton de rafraîchissement
/// manuel ferait donc double emploi. Mais sur iPhone, la découverte locale est
/// IMPOSSIBLE : la seule façon de faire apparaître un Mac que l'hôte ne
/// connaissait pas encore est de le lui demander. C'est cela que ce bouton fait,
/// et son libellé le dit.
///
/// POURQUOI IL EST UNE VUE À PART, ET POURQUOI L'ALIGNEMENT EST EXPLICITE. Deux
/// captures du Mac ont montré le bouton DÉCALÉ VERS LE BAS par rapport aux
/// serveurs, pour des raisons cumulées :
///
///   1. son cadre faisait 68 points de haut, alors qu'une icône de serveur en
///      fait 68 **plus** son nom **plus** la ligne « hôte » ;
///   2. son icône était centrée dans le carré en pointillés, quand l'icône de
///      châssis d'un serveur est centrée dans SA vignette — les deux dessins ne
///      tombaient donc pas à la même hauteur ;
///   3. et surtout : un `HStack` aligne ses éléments sur leur LIGNE DE BASE, pas
///      sur leur haut. Le bloc « vignette + nom » d'un serveur a sa ligne de base
///      SOUS le nom, celui du bouton l'a sous « Rafraîchir » : les hauteurs
///      égales ne suffisaient pas, il fallait aligner les SOMMETS.
///
/// La vue reprend donc la structure exacte d'`IconeServeur` — même vignette de
/// 62 points, même cadre de 68, mêmes espacements, même ligne de légende — et le
/// carrousel est aligné en haut.
struct BoutonAjouterServeur: View {
  /// Vrai pendant une recherche : le carré en pointillés se remplit d'un
  /// indicateur, pour qu'un appui ne reste jamais sans réponse visible.
  let enRecherche: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 6) {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
          .strokeBorder(
            Color.secondary.opacity(0.45),
            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
          )
          .frame(width: 62, height: 62)
          .overlay {
            if enRecherche {
              ProgressView().controlSize(.small)
            } else {
              Image(systemName: "plus")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color.secondary)
            }
          }
          // Le cadre de 68 points, comme la vignette d'un serveur : c'est lui
          // qui place les deux dessins à la même hauteur.
          .frame(width: 68, height: 68)

        Text("Ajouter")
          .font(.caption2)
          .foregroundStyle(Color.secondary)
          .frame(width: 68)
        // La même ligne que « hôte », laissée vide : c'est elle qui donne aux
        // deux blocs la même hauteur totale.
        Text(" ")
          .font(.system(size: 9))
      }
    }
    .buttonStyle(.plain)
    .disabled(enRecherche)
    .accessibilityLabel("Chercher un Mac qui publie DSH")
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
        if modele.rechercheServeursPossible {
          Button("Chercher un Mac") { Task { await modele.synchroniserServeurs() } }
            .font(.callout)
            .buttonStyle(.bordered)
            .disabled(modele.synchronisationEnCours)
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
