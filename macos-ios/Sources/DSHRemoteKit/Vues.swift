import DSHRemoteKit
import SwiftUI

/// Fenêtre principale : la liste des sessions à gauche, le journal à droite.
///
/// `NavigationSplitView` est employé des deux côtés plutôt qu'une navigation par
/// pile : sur le Mac c'est une vraie vue en colonnes, et sur iPhone SwiftUI la
/// replie lui-même en pile. Une seule structure d'interface pour les deux
/// plateformes, donc un seul comportement à vérifier.
public struct VuePrincipale: View {
  /// LE MODÈLE EST INJECTABLE, et c'est macOS qui l'exige.
  ///
  /// POURQUOI. Une scène `Settings` et des commandes de menu doivent parler au
  /// MÊME modèle que la fenêtre : un ⌘R qui rafraîchirait une seconde instance,
  /// que personne ne voit, serait un raccourci qui ne fait rien — et un écran de
  /// réglages qui lirait un autre appareil que celui affiché serait pire encore.
  /// L'application macOS en crée donc un et le passe ; iOS et `swift run`
  /// gardent l'entrée sans argument, où la vue crée le sien comme avant.
  @State private var modele: ModeleApp
  @State private var sessionSelectionnee: SessionListee?
  /// La feuille de réglages. Elle est tenue ICI parce que trois endroits
  /// l'ouvrent : la barre d'outils, le panneau latéral, la page d'un serveur.
  @State private var reglagesOuverts = ProcessInfo.processInfo.arguments.contains("--reglages")
  /// La saisie manuelle d'une adresse : le chemin des cas que la découverte ne
  /// couvre pas. Elle n'est plus dans les réglages — une adresse est celle d'UNE
  /// machine, pas un réglage de l'application.
  @State private var adresseOuverte = ProcessInfo.processInfo.arguments.contains("--adresse")
  /// La page « Ajouter un serveur » est-elle ouverte ? C'est une page de
  /// NAVIGATION, pas une machine : elle n'a donc rien à faire dans le modèle.
  @State private var ajoutOuvert = ProcessInfo.processInfo.arguments.contains("--ajout")

  @MainActor
  public init() { _modele = State(initialValue: ModeleApp()) }

  /// L'entrée de l'application macOS : le modèle est déjà construit.
  @MainActor
  public init(modele: ModeleApp) { _modele = State(initialValue: modele) }

  /// Ancre de VÉRIFICATION, et rien d'autre : `--serveur` ouvre la page du
  /// premier serveur au lancement, ce qui permet de la CAPTURER sans piloter la
  /// souris. Même rôle que `--reglages` et `--deplier` : aucun effet sans
  /// l'argument, jamais transmis par un lancement depuis le Dock.
  /// Le nom demandé par `--serveur=<fragment>`, s'il y en a un.
  /// La machine désignée par `--serveur=<fragment>`, si elle existe dans la liste.
  private var machineNommee: ServeurMac? {
    guard let demande = VuePrincipale.nomDeMachineDemande else { return nil }
    return modele.serveursAffiches.first { machine in
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
    machineNommee ?? modele.serveurChoisi ?? modele.serveursAffiches.first
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

  /// Le fragment demandé par `--session=<fragment>`, s'il y en a un.
  ///
  /// ANCRE DE VÉRIFICATION, comme `--serveur=` : cet environnement n'injecte pas
  /// d'appui dans une liste, donc le JOURNAL d'une session ne peut être ni
  /// capturé ni jugé sans elle — et « ça compile » tiendrait lieu de preuve pour
  /// tout ce qui touche au rendu d'un événement. Le fragment est cherché dans le
  /// titre et dans le projet, en minuscules.
  private static var sessionDemandee: String? {
    for argument in ProcessInfo.processInfo.arguments where argument.hasPrefix("--session=") {
      let valeur = argument.dropFirst("--session=".count).lowercased()
      if !valeur.isEmpty { return valeur }
    }
    return nil
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

  /// CE QUE LE VOLET DE DÉTAIL DOIT MONTRER, calculé par la règle pure.
  ///
  /// POURQUOI ICI, ET PAS DANS LE `switch` DE LA VUE : la vue fournit les faits
  /// (session choisie, page ouverte, cible, liste), la règle décide. C'est ce qui
  /// permet de l'éprouver sans interface.
  ///
  /// LA LISTE EST CELLE DU CARROUSEL (`serveursAffiches`), et pas `serveurs` : la
  /// vignette mise en avant est la première de l'ordre AFFICHÉ, et la page du
  /// volet de détail doit être celle de cette vignette-là. Deux listes différentes
  /// feraient parler l'écran de droite d'une autre machine que celle qui est
  /// entourée à gauche.
  private var detailAAfficher: DetailAffiche {
    DetailAffiche.pour(
      session: sessionSelectionnee?.id,
      ajout: ajoutOuvert,
      pageOuverte: serveurDeLaPage,
      vise: modele.serveurChoisi,
      serveursAffiches: modele.serveursAffiches)
  }

  public var body: some View {
    Group {
      if pageSeuleParArgument, ajoutOuvert {
        // `--page-seule` court-circuite le démarrage : la tâche du panneau
        // latéral ne s'exécute pas, donc rien n'est mesuré — et la capture
        // montrait un parcours qui affirmait sans avoir constaté. On mesure ici.
        let _ = modele.relireEtatTailscale()
        // `--ajout --page-seule` : la page d'ajout, seule. Sans cette branche,
        // l'ancre affichait la page de la machine visée et la page d'ajout
        // n'était pas capturable — constaté sur la première capture.
        NavigationStack {
          VueAjoutServeur(modele: modele) { adresseOuverte = true }
        }
      } else if pageSeuleParArgument, let serveur = machineDeLaPageSeule {
        let _ = modele.relireEtatTailscale()
        // Ancre de vérification : la page seule, pour la capturer.
        NavigationStack {
          VueServeur(modele: modele, serveur: serveur)
        }
        // LA SONDE PART AUSSI D'ICI, et pour la même raison que la mesure
        // ci-dessus : sans le panneau latéral, aucune sonde n'est lancée, donc
        // les étapes 3 et 4 restaient à « vérification… » — les deux états qui
        // comptent le plus (port fermé, plugin absent) n'étaient PAS capturables,
        // et la capture d'une page saine était impossible. Constaté en essayant.
        .task { await modele.sonderLesServeurs() }
      } else {
        contenu
      }
    }
  }

  /// Ouvre la session demandée par `--session=<fragment>`, si elle est là.
  ///
  /// ELLE NE FAIT RIEN SANS L'ARGUMENT, ni si une session est déjà ouverte : une
  /// ancre de vérification ne doit jamais écraser un choix de l'utilisateur.
  private func ouvrirSessionDemandee() {
    guard sessionSelectionnee == nil, let demande = VuePrincipale.sessionDemandee else { return }
    guard
      let trouvee = modele.sessionsFiltrees.first(where: { session in
        session.titreAffiche.lowercased().contains(demande)
          || (session.projet ?? "").lowercased().contains(demande)
      })
    else { return }
    sessionSelectionnee = trouvee
  }

  private var contenu: some View {
    NavigationSplitView {
      VueListeSessions(
        modele: modele,
        selection: $sessionSelectionnee,
        reglagesOuverts: $reglagesOuverts,
        adresseOuverte: $adresseOuverte,
        // Choisir « Ajouter » QUITTE la page d'une machine : sans cela, la page
        // d'ajout serait remplacée par celle du serveur resté ouvert.
        surAjout: {
          sessionSelectionnee = nil
          modele.fermerPage()
          ajoutOuvert = true
        },
        // TOUCHER UNE MACHINE LA SÉLECTIONNE ; LA RETOUCHER OUVRE SA PAGE.
        //
        // La règle vit dans le modèle (`ModeleApp.toucher`, décidée par
        // `GesteSurServeur`) : ici on ne fait que l'appeler. La sélection de
        // session est effacée, sans quoi le journal resterait affiché par-dessus
        // la liste d'un autre serveur.
        surSelectionServeur: { serveur in
          sessionSelectionnee = nil
          ajoutOuvert = false
          Task { await modele.toucher(serveur) }
        })
    } detail: {
      // LA RÈGLE VIT DANS `DetailAffiche`, ET ELLE EST ÉPROUVÉE LÀ-BAS. Ce bloc ne
      // fait plus que la traduire en vues : cinq branches enchaînées ici
      // finissaient sur « Aucune session ouverte », donc sur un écran vide au
      // lancement alors qu'une machine était sélectionnée.
      switch detailAAfficher {
      case let .journal(identifiant):
        // La session est résolue dans la liste courante : un identifiant qui
        // n'existe plus ne doit pas fabriquer une session de toutes pièces.
        if let session = modele.sessionsAffichees.first(where: { $0.id == identifiant }) {
          VueJournal(modele: modele, session: session)
        } else if let session = sessionSelectionnee {
          VueJournal(modele: modele, session: session)
        }
      case .ajout:
        VueAjoutServeur(modele: modele) { adresseOuverte = true }
      case let .serveur(serveur):
        VueServeur(modele: modele, serveur: serveur)
      case let .selection(serveur):
        // LA MACHINE EST SÉLECTIONNÉE, SA PAGE N'EST PAS OUVERTE. On ne laisse pas
        // l'écran vide pour autant : on dit laquelle est choisie, ce que le
        // premier appui vient de faire (ses sessions sont à gauche), et ce que le
        // second fera. C'est la règle des deux temps, rendue lisible.
        ContentUnavailableView {
          Label { Text(serveur.nom) } icon: { Image(systemName: "checkmark.circle") }
        } description: {
          // L'ERREUR SE DIT ICI, ET C'EST UNE CORRECTION. Elle ouvrait la page à
          // la place : sélectionner une machine qui refuse la connexion (un `401`
          // sur un Mac non appairé) faisait donc apparaître sa fiche, et la règle
          // des deux temps ne tenait que pour les machines qui répondaient —
          // mesuré : « sur macOS, ça ne fonctionne que pour le premier serveur ».
          // Le message et son remède restent lisibles, sans décider de la
          // navigation. Le détail complet est sur la page, au second appui.
          if let erreur = modele.erreur {
            Text(erreur)
          } else {
            T("Ses sessions et ses espaces de travail sont à gauche. Touchez à nouveau sa vignette pour ouvrir sa page.")
          }
        }
        .accessibilityLabel(T("Serveur sélectionné"))
      case .rien:
        ContentUnavailableView {
          Label { T("Aucune session ouverte") } icon: { Image(systemName: "terminal") }
        } description: {
          T("Choisissez une session dans la liste pour lire son journal.")
        }
      }
    }
    .sheet(isPresented: $reglagesOuverts) {
      FeuilleReglages(modele: modele)
    }
    .sheet(isPresented: $adresseOuverte) {
      FeuilleAdresse(modele: modele)
        #if os(iOS)
          // UNE ADRESSE, UN JETON, DEUX BOUTONS : la moitié d'un écran suffit, et
          // laisser la liste visible derrière évite de perdre le contexte. La
          // feuille peut monter en plein écran quand le clavier s'ouvre.
          .presentationDetents([.medium, .large])
        #endif
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
      // ANCRE DE VÉRIFICATION : `--session=<fragment>` ouvre un journal précis.
      // Elle passe AVANT la restauration — une ancre explicite ne doit pas être
      // écrasée par ce qui a été consulté la veille.
      ouvrirSessionDemandee()
      // LA SESSION CONSULTÉE SE ROUVRE, si l'hôte vient de la nommer.
      //
      // POURQUOI APRÈS `demarrer()` : la liste des sessions n'existe qu'une fois
      // la connexion faite, et un identifiant mémorisé ne vaut que si la machine
      // le reconnaît encore. `sessionARouvrir` fait cette vérification — rouvrir
      // un journal disparu afficherait un écran vide sous un titre oublié.
      //
      // POURQUOI SEULEMENT SI RIEN N'EST SÉLECTIONNÉ : les ancres de vérification
      // (`--serveur`, `--ajout`) ouvrent un écran précis, et restaurer par-dessus
      // rendrait la capture dépendante de ce qui a été consulté la veille.
      if sessionSelectionnee == nil, modele.serveurOuvert == nil, !ajoutOuvert {
        sessionSelectionnee = modele.sessionARouvrir
      }
    }
    // LA SÉLECTION SE RETIENT, pour être rouverte au prochain lancement.
    .onChange(of: sessionSelectionnee) { _, nouvelle in
      modele.definirSessionConsultee(nouvelle?.id)
    }
    // L'ANCRE SE REJOUE QUAND LA LISTE ARRIVE — et c'est une correction mesurée.
    // La première tentative tombe juste après `demarrer()`, qui rend la main sur
    // la POIGNÉE DE MAIN : la liste des sessions arrive après, et l'ancre ne
    // trouvait rien. Constaté deux fois : la capture montrait la session
    // restaurée au lieu de celle demandée, ce qui rendait l'ancre trompeuse —
    // pire que pas d'ancre du tout.
    .onChange(of: modele.sessionsFiltrees) { _, _ in
      ouvrirSessionDemandee()
    }
    // ── UNE ERREUR N'OUVRE PLUS LA PAGE, ET C'EST LA SECONDE FOIS ──────────
    //
    // Il y avait ici un `onChange(of: modele.erreur)` qui forçait la page de la
    // machine visée dès qu'une erreur arrivait. Sa raison était juste — le
    // diagnostic avait quitté le panneau latéral, et un échec de connexion au
    // lancement ne se serait affiché nulle part —, mais la règle était ÉCRITE
    // DEUX FOIS : `DetailAffiche` avait la même branche (`cibleEnErreur`). J'ai
    // retiré celle du modèle, et le symptôme est resté : c'est celle-ci qui
    // ouvrait la page. Mesuré sur la machine du propriétaire, après un premier
    // correctif qui semblait complet.
    //
    // LES DEUX RESPONSABILITÉS SONT MAINTENANT AILLEURS, ET UNE SEULE FOIS :
    //   - au LANCEMENT, `ModeleApp` ouvre la page de la machine choisie par
    //     défaut : un échec de connexion s'y affiche, avec ses remèdes ;
    //   - APRÈS UN APPUI, l'erreur est dite DANS l'état de sélection (voir le cas
    //     `.selection`), sans décider de la navigation.
    // Une règle d'affichage écrite dans une vue ne se voit pas depuis le modèle :
    // c'est ce qui a rendu ce défaut invisible au deuxième examen.
  }
}

/// Colonne de gauche : les serveurs, puis les sessions groupées par espace de travail.
///
/// POURQUOI TAILSCALE N'Y A PLUS SA PLACE. La colonne s'ouvrait sur une carte
/// d'état de Tailscale — « connecté », « installé », « pas installé » — avec son
/// action. Le propriétaire l'a fait retirer : « la partie Tailscale n'est plus
/// utile car intégrée dans le détail de la page serveur ». C'est exact : l'état
/// de CET APPAREIL est la PREMIÈRE étape du parcours de chaque machine, avec la
/// même mesure et la même action (ouvrir Tailscale, ou l'installer), et elle est
/// dite là où elle sert — au moment où une machine ne répond pas.
///
/// CE QUI ÉTAIT LA SEULE VOIE NE L'EST PLUS : sur un appareil neuf, la carte
/// portait l'unique bouton « Installer Tailscale ». La page « Ajouter un
/// serveur » porte la même action, et elle est désormais offerte depuis la liste
/// VIDE — l'état où Tailscale est justement le suspect (voir `ServeursVides`).
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
  /// Touché « Ajouter » : ouvre la page qui dit comment faire naître un serveur.
  var surAjout: () -> Void
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
          ServeursVides(modele: modele, surAdresse: { adresseOuverte = true }, surAjout: surAjout)
            .sansSeparateurMac()
        } else {
          CarrouselServeurs(
            modele: modele, surSelectionServeur: surSelectionServeur, surAjout: surAjout)
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
        EnteteSection(L("Serveur DeepSeek Harness"), detail: resumeServeurs)
      }

      // ── Ce qui est PARTI sur la page du serveur ──────────────────────────
      //
      // La bascule de serveur, le diagnostic et les commandes à recopier ne
      // sont plus ici : ils vivent sur la page de la machine concernée
      // (`VueServeur`), qu'on ouvre en touchant son icône. Le panneau latéral
      // garde ce qui se lit d'un coup d'œil — pastille, légende, nom — et
      // rend la place aux sessions, qui sont ce qu'on vient y chercher.

      // ── CE QUI ATTEND, AVANT TOUT LE RESTE ────────────────────────────────
      //
      // POURQUOI UNE SECTION, ET POURQUOI ELLE EST EN HAUT. « Qui m'attend ? »
      // est la question qu'on se pose en ouvrant l'application, et la réponse
      // était enterrée : il fallait déplier les espaces et lire des pastilles de
      // huit points. Cette section ne remplace pas l'arbre — la session y figure
      // AUSSI, à sa place dans son projet —, elle le précède.
      //
      // Le tri est celui de l'urgence (`sessionsQuiAttendent`) : une session
      // bloquée sur une décision passe avant une fin de tour non lue.
      if !modele.sessionsQuiAttendent.isEmpty {
        Section {
          ForEach(modele.sessionsQuiAttendent, id: \.id) { session in
            LigneSession(
              affiche: AfficheLigneSession(
                session: session, rappelDeFin: modele.aTermine(session.id))
            ).tag(session)
            .sansSeparateurMac()
            .gestesDeSession(session, modele: modele, rappelArme: modele.aTermine(session.id))
          }
        } header: {
          EnteteSection(
            L("Demande votre attention"),
            detail: "\(modele.sessionsQuiAttendent.count)")
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
              T("aucune session")
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
                  // CE QUI EST DÉPLIÉ SE RETIENT. Sans cela, quitter l'écran ou
                  // relancer l'application refermait tous les dossiers, et il
                  // fallait les rouvrir un par un pour retrouver son travail.
                  modele.definirEspacesDeplies(espacesDeplies)
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
                  .gestesDeSession(
                    session, modele: modele, rappelArme: modele.aTermine(session.id))
                } else {
                  LigneSession(
                    affiche: AfficheLigneSession(
                      session: session, rappelDeFin: modele.aTermine(session.id))
                  ).tag(session)
                  .sansSeparateurMac()
                  .gestesDeSession(
                    session, modele: modele, rappelArme: modele.aTermine(session.id))
                }
              }
            } label: {
              HStack(spacing: 8) {
                Image(systemName: espace.horsEspaces ? "folder.badge.questionmark" : "folder")
                  .foregroundStyle(Color.accentColor)
                Text(espace.nom).font(.body)
                Spacer()
                // LE COMPTE DIT CE QUI ATTEND, pas seulement combien il y a :
                // replier un dossier cachait l'information la plus actionnable.
                Text(modele.resume(espace).texte)
                  .font(.caption2)
                  .foregroundStyle(
                    (modele.resume(espace).enAttente > 0 ? EtatVisuel.attention : .attente).couleur)
              }
            }
            .sansSeparateurMac()
          }
        }

        // ── LES ÉTATS VIDES SE DISENT ────────────────────────────────────────
        //
        // POURQUOI. Une section « Espaces de travail » vide, avec « 0 session »
        // pour tout discours, laisse croire à un chargement en panne. Deux cas
        // différents, deux phrases : personne n'a encore rien lancé, ou la
        // recherche ne rend rien — et dans le second, on nomme le terme cherché.
        if modele.espaces.isEmpty {
          if !modele.recherche.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView.search(text: modele.recherche)
          } else if modele.filtreCacheTout {
            // LE SERVEUR EN CONNAÎT, LE FILTRE LES CACHE. Le dire évite de croire
            // que la machine n'a rien — mesuré : 156 sessions rendues, 8
            // vivantes, et un arbre vide dès qu'aucune n'est en mémoire.
            VStack(alignment: .leading, spacing: 10) {
              ContentUnavailableView {
                Label { T("Aucune session en mémoire") } icon: { Image(systemName: "memorychip") }
              } description: {
                Text(
                  "Ce serveur en connaît \(modele.sessions.count), mais le filtre « Chargées en mémoire seulement » n'affiche que celles qui sont prêtes à reprendre tout de suite."
                )
              }
              Button(L("Les afficher toutes")) { modele.afficherToutesLesSessions() }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
          } else {
            ContentUnavailableView {
              Label { T("Aucune session") } icon: { Image(systemName: "rectangle.stack") }
            } description: {
              T("Les sessions de cette machine apparaîtront ici. Lancez-en une sur le Mac, ou choisissez une autre machine ci-dessus.")
            }
          }
        }
      } header: {
        // « ESPACES DE TRAVAIL », ET NON « Workspaces ». Le titre avait été
        // recopié de l'interface web pour que les deux se répondent ; le
        // propriétaire a tranché : « et en français, Workspaces = Espaces de
        // travail ». La RÈGLE #1 du dépôt le demandait déjà — le reste de
        // l'application est en français, et un titre anglais au milieu se lit
        // comme un terme du protocole, ce qu'il n'est pas : « Workspaces » ne
        // nomme ici qu'un dossier de travail.
        //
        // Le protocole, lui, garde son nom : `/v1/espaces` est déjà français, et
        // `workspaceRegistry` reste l'API du harness.
        // LES ESPACES DE TRAVAIL SONT CEUX D'UN SERVEUR, pas une liste globale :
        // ils changent quand on change de machine. Le nom du serveur est dit
        // ICI, parce que c'est le seul endroit qui reste visible quand une
        // session est ouverte — la vignette du carrousel, elle, n'affiche que le
        // premier mot du nom, et deux Macs peuvent le partager.
        EnteteSection(
          L("Espaces de travail"),
          detail: "\(modele.sessionsFiltrees.count) session\(modele.sessionsFiltrees.count > 1 ? "s" : "")",
          surtitre: modele.nomDuServeurAffiche)
      }
    }
    // `insetGrouped` est INDISPONIBLE sur macOS — la compilation le refuse, et
    // pas seulement à l'exécution. Chaque plateforme reçoit donc le style qui
    // existe chez elle : iOS la liste encartée, macOS la liste latérale
    // habituelle, qui est déjà celle d'une colonne de navigation.
    #if os(iOS)
      .listStyle(.insetGrouped)
      // LE GESTE QU'ON ESSAIE EN PREMIER, et qui n'existait pas.
      //
      // POURQUOI IL COMPTE MALGRÉ LA SYNCHRONISATION AUTOMATIQUE. Le suivi
      // interroge l'hôte toutes les trois secondes — mais seulement si « Suivre
      // l'activité » est actif, et il ne dit rien de la FRAÎCHEUR de ce qu'on
      // regarde. Après avoir rallumé une machine ou réparé le réseau, tirer la
      // liste est le geste qui répond « et maintenant ? » sans attendre un cycle.
      .refreshable { await modele.rafraichir() }
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
      // 340 POINTS, ET NON 320 : MESURÉ SUR IPAD. À 320 — le minimum macOS, choisi
    // pour que la carte, le carrousel et une ligne de session tiennent —, le titre
    // « Serveur DeepSeek Harness » passait à la DEUX LIGNES et le champ de
    // recherche tronquait son texte. 340 suffit à les tenir, et laisse encore
    // 480 points au journal sur un iPad (A16) en portrait.
    .navigationSplitViewColumnWidth(min: 340, ideal: 380, max: 480)
    #endif
    // LA LARGEUR VAUT AUSSI POUR L'IPAD, et c'est une correction VUE À L'ÉCRAN.
    // Le modificateur ne vivait que dans la branche macOS : sur iPad, la colonne
    // prenait donc la largeur par défaut du système — mesurée à environ 260
    // points sur un iPad (A16) —, où le titre de section passait à la ligne, le
    // carrousel était coupé au troisième chicon et le champ de recherche
    // tronquait son texte. Sur iPhone (largeur compacte), SwiftUI ignore cette
    // contrainte : la colonne est l'écran entier.
    // 340 POINTS, ET NON 320 : MESURÉ SUR IPAD. À 320 — le minimum macOS, choisi
    // pour que la carte, le carrousel et une ligne de session tiennent —, le titre
    // « Serveur DeepSeek Harness » passait à la DEUX LIGNES et le champ de
    // recherche tronquait son texte. 340 suffit à les tenir, et laisse encore
    // 480 points au journal sur un iPad (A16) en portrait.
    .navigationSplitViewColumnWidth(min: 340, ideal: 380, max: 480)
    // Titre EN LIGNE, et non grand. Mesuré sur le prototype : le grand titre
    // coûtait 60 points pour répéter le nom de l'application, déjà connu de qui
    // l'ouvre — et ces 60 points manquaient aux sessions, dont deux seulement
    // restaient visibles. La carte, le carrousel et les workspaces tiennent
    // maintenant à l'écran, ce qui était l'objet de la refonte.
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .navigationTitle(T("DSH Remote"))
    #if os(iOS)
      // La destination des icônes de serveur, déclarée DANS la colonne qui
      // l'affiche : sur iPhone elle s'empile, sur iPad elle remplit le détail.
      .navigationDestination(for: ServeurMac.self) { serveur in
        VueServeur(modele: modele, serveur: serveur)
      }
      .navigationDestination(for: PageAjoutServeur.self) { _ in
        VueAjoutServeur(modele: modele) { adresseOuverte = true }
      }
    #endif
    .toolbar {
      // LE BOUTON RÉGLAGES N'EXISTE QUE SUR iOS.
      //
      // POURQUOI. La directive macOS est explicite : les réglages s'ouvrent par
      // l'élément « Réglages… » du menu de l'application, avec ⌘, — pas par un
      // bouton de barre d'outils. Depuis que l'application macOS a une scène
      // `Settings`, ce bouton y ferait doublon avec le menu, au mauvais endroit.
      // Sur iPhone, au contraire, la feuille est le lieu prévu, et elle est la
      // seule porte.
      #if os(iOS)
        ToolbarItem(placement: .primaryAction) {
          Button {
            reglagesOuverts = true
          } label: {
            Image(systemName: "gearshape")
          }
          .accessibilityLabel(T("Réglages"))
        }
      #endif
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
    // LES ESPACES DÉPLIÉS SE RETROUVENT AU LANCEMENT.
    //
    // POURQUOI ICI, ET PAS DANS L'INITIALISATION DE `@State`. L'état vit dans la
    // vue — il n'appartient qu'à elle —, mais il doit SURVIVRE à sa disparition :
    // c'est le modèle qui l'a écrit, et c'est de lui qu'on le relit, une fois,
    // quand la vue apparaît.
    .task {
      if espacesDeplies.isEmpty {
        espacesDeplies = modele.navigation.espacesDepliesEnsemble
        // Les espaces dépliés pendant une recherche ne comptent pas : ils le sont
        // d'office, et les mémoriser ferait rouvrir au lancement des dossiers que
        // personne n'a ouverts.
        if !modele.recherche.isEmpty { espacesDeplies = [] }
      }
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
///
/// LE SURTITRE DIT À QUOI LA SECTION APPARTIENT. Une section dont le contenu
/// dépend d'un choix — les espaces de travail d'UN serveur, par exemple — doit
/// pouvoir le nommer : sans cela, rien ne distingue une liste globale d'une liste
/// liée à la machine qu'on regarde. Le nom est petit et discret AU-DESSUS du
/// titre, pour ne pas concurrencer ce que la section contient.
struct EnteteSection: View {
  let titre: String
  var detail: String?
  var surtitre: String?

  init(_ titre: String, detail: String? = nil, surtitre: String? = nil) {
    self.titre = titre
    self.detail = detail
    self.surtitre = surtitre
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      if let surtitre {
        Text(surtitre)
          .font(.caption2)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      HStack {
        Text(titre)
        Spacer()
        if let detail {
          Text(detail).foregroundStyle(.secondary)
        }
      }
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
  /// Touché « Ajouter » : la page qui dit comment faire naître un serveur.
  var surAjout: () -> Void

  /// LE CÔTÉ D'UNE VIGNETTE, MIS À L'ÉCHELLE DU TEXTE DE L'APPAREIL.
  ///
  /// POURQUOI `@ScaledMetric`. La vignette portait un glyphe de 27 points et un
  /// cadre de 68 **en dur** : à la taille de texte d'accessibilité, ils ne
  /// grandissaient pas d'un point, alors que le nom et la légende — sémantiques,
  /// eux — grossissaient : le texte finissait par ne plus tenir dans un cadre
  /// prévu pour lui. C'est le défaut que l'audit a relevé sous le nom de
  /// « Dynamic Type cassé », et il touchait le composant signature de l'écran.
  ///
  /// POURQUOI UN PLAFOND, ET POURQUOI IL EST ASSUMÉ. Au-delà de 96 points, une
  /// vignette cesse d'être une vignette : trois machines ne tiennent plus dans la
  /// colonne, et le carrousel perd ce pour quoi il existe — voir d'un coup d'œil
  /// quelles machines répondent. Le texte, lui, continue de grandir jusqu'au bout.
  @ScaledMetric(relativeTo: .caption2) private var coteMiseALEchelle: CGFloat = 62
  private var cote: CGFloat { min(coteMiseALEchelle, 96) }

  /// LES LIBELLÉS DE LA LISTE ENTIÈRE, calculés une fois par rendu.
  ///
  /// POURQUOI ICI, ET NON DANS LA VIGNETTE. Deux machines peuvent partager leur
  /// premier mot : c'est la comparaison entre elles qui décide si un mot suffit.
  /// Voir `NomsCourts`. La liste est celle de l'AFFICHAGE : les libellés sont
  /// calculés sur l'ENSEMBLE des machines, donc l'ordre ne les change pas — mais
  /// une seule liste circule dans la vue.
  private var libelles: [String: String] { NomsCourts.libelles(pour: modele.serveursAffiches) }

  var body: some View {
    // LES INDICATEURS DE DÉFILEMENT SONT CEUX DU SYSTÈME. Ils étaient masqués
    // (`showsIndicators: false`) : avec quatre machines, la quatrième apparaît
    // COUPÉE au bord de la colonne sans que rien n'annonce qu'on peut faire
    // défiler — constaté sur capture. La barre discrète du système est
    // précisément l'affordance qui manquait, et elle ne s'affiche que pendant le
    // geste.
    ScrollView(.horizontal) {
      HStack(alignment: .top, spacing: 16) {
        // L'ORDRE EST CELUI DE L'AFFICHAGE : joignables d'abord, prêtes en premier
        // (voir `ModeleApp.serveursAffiches`) — et il ne dépend PAS de la sélection.
        // Il en a dépendu : la vignette touchée sautait en tête, le contenu se
        // décalait sous le doigt, et la barre de défilement s'agitait à chaque
        // connexion. Une liste qu'on parcourt du doigt ne bouge pas parce qu'on
        // l'a touchée.
        ForEach(modele.serveursAffiches) { serveur in
          // ── TOUCHER UNE MACHINE OUVRE SA PAGE ET S'Y CONNECTE ─────────────
          //
          // Deux effets pour un geste, et c'est délibéré : on touche une machine
          // pour s'y connecter, et la page est ce qui EXPLIQUE le résultat —
          // état, adresse, jeton, remèdes. Ce qui a changé par rapport au début
          // n'est pas le geste, c'est l'ENDROIT du diagnostic : il s'affichait
          // dans la colonne de gauche, au milieu des sessions ; il vit
          // maintenant sur la page de la machine concernée.
          vignette(serveur)
            // L'APPUI LONG EST LE RECOURS DE CE QUI N'EST PAS UN APPUI : clavier
            // externe, VoiceOver, souris. Il porte les mêmes actions que la page,
            // à l'endroit où l'on désigne la machine.
            .contextMenu { menuDeMachine(serveur) }
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
          // LA VIGNETTE MÈNE À LA PAGE, elle ne lance plus une recherche. Sur un
          // iPhone où rien n'est encore installé, une recherche ne peut rien
          // trouver et n'apprend rien : ni ce qui manque, ni sur quelle machine,
          // ni dans quel ordre. La recherche reste offerte DANS la page.
          #if os(iOS)
            NavigationLink(value: PageAjoutServeur()) {
              ContenuAjouter(enRecherche: modele.synchronisationEnCours, cote: cote)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { surAjout() })
          #else
            Button {
              surAjout()
            } label: {
              ContenuAjouter(enRecherche: modele.synchronisationEnCours, cote: cote)
            }
            .buttonStyle(.plain)
          #endif
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 4)
      // LE RETOUR HAPTIQUE DIT CE QUE L'ŒIL PEUT MANQUER. Choisir une machine
      // déclenche une connexion de plusieurs secondes : sur un téléphone tenu à
      // une main, la coche de la vignette peut être hors du regard, et rien ne
      // confirmerait que l'appui a été pris en compte. Le retour ne se produit
      // que si la machine courante CHANGE — pas à chaque rendu.
      .sensoryFeedback(trigger: modele.serveurChoisi?.id) { ancien, nouveau in
        ancien == nouveau ? nil : .selection
      }
    }
    .scrollClipDisabled()
  }

  /// UNE VIGNETTE DE MACHINE, dans ses deux mécanismes de navigation.
  ///
  /// POURQUOI ELLE EST UNE FONCTION À PART. Le menu contextuel doit s'appliquer à
  /// la vignette sur les DEUX plateformes, alors que la navigation, elle, diffère
  /// — `NavigationLink` qui empile sur iPhone, `Button` qui remplace le contenu de
  /// droite sur macOS. Un `#if` au milieu d'une chaîne de modificateurs ne se
  /// compile pas, et dupliquer le menu l'aurait fait diverger d'une plateforme à
  /// l'autre : c'est précisément ce que la vue partagée évite partout ailleurs.
  ///
  /// DEUX MÉCANISMES, PARCE QUE LES PLATEFORMES DIFFÈRENT. Sur macOS, les deux
  /// colonnes sont visibles : la page remplace le contenu de droite. Sur iPhone,
  /// la colonne de détail n'existe pas : il faut EMPILER la page
  /// (`NavigationLink`), sinon l'appui ne montre rien — et un appui qui ne montre
  /// rien est un appui cassé.
  @ViewBuilder
  private func vignette(_ serveur: ServeurMac) -> some View {
    #if os(iOS)
      // ── LE MÉCANISME SUIT LA RÈGLE, ET C'EST LA CORRECTION ─────────────────
      //
      // DÉFAUT MESURÉ : la vignette était TOUJOURS un `NavigationLink`, qui
      // empile la page à CHAQUE appui — quoi que dise `GesteSurServeur`. Le
      // premier appui ne pouvait donc pas se contenter de sélectionner : pour
      // voir la liste d'à côté, il fallait ouvrir une fiche puis revenir en
      // arrière, et l'infobulle (« un second appui ouvre sa page ») mentait.
      //
      // C'est le MÉCANISME qui obéit maintenant : un lien quand la page doit
      // s'ouvrir, un bouton quand la machine doit être sélectionnée — et l'on
      // reste alors sur la liste, le temps que SES sessions et SES espaces de
      // travail se rechargent.
      let geste = GesteSurServeur.pour(serveur, choisi: modele.serveurChoisi)
      let icone = IconeServeur(
        serveur: serveur,
        libelle: libelles[serveur.id] ?? serveur.premierMot,
        cote: cote,
        choisi: modele.serveurChoisi == serveur,
        sertDsh: modele.sertDsh(serveur))
      // Le `Group` n'est pas décoratif : les modificateurs d'accessibilité qui
      // suivent (libellé, infobulle, action nommée) s'appliquent à un TYPE DE VUE,
      // et un `if` n'en est pas un — mesuré : « no exact matches in call to
      // instance method 'accessibilityLabel' ». Le `Group` rend les deux branches
      // habillables d'un seul jeu de modificateurs, donc d'un seul libellé.
      Group {
        if geste == .ouvrirLaPage {
          NavigationLink(value: serveur) { icone }
            .buttonStyle(.plain)
            // Le lien EMPILE la page ; ce geste simultané dit au modèle laquelle
            // est ouverte (pour que la vignette l'indique).
            .simultaneousGesture(TapGesture().onEnded { surSelectionServeur(serveur) })
        } else {
          Button {
            surSelectionServeur(serveur)
          } label: {
            icone
          }
          .buttonStyle(.plain)
        }
      }
      .accessibilityLabel(
        EtatMachine.libelleAccessible(
          nom: serveur.nom, enLigne: serveur.enLigne, sertDsh: modele.sertDsh(serveur),
          estLocal: serveur.estLocal)
      )
      // ── LA CONNEXION DEVIENT UNE ACTION NOMMÉE, ET C'EST UNE CORRECTION ────
      //
      // POURQUOI. Sur iPhone, la vignette est un LIEN doublé d'un geste parallèle :
      // c'est le GESTE qui agit. Or VoiceOver, le clavier externe, Voice Control
      // et les interrupteurs activent le LIEN — ils ouvraient donc la page d'une
      // machine sans la sélectionner, et rien ne le disait. Une action nommée rend
      // le geste atteignable par les mêmes moyens que le reste : c'est le chemin
      // canonique, et il ne demande aucune refonte de la navigation.
      //
      // L'INFOBULLE DIT CE QUE L'ACTIVATION SIMPLE FAIT VRAIMENT — sélectionner,
      // et ouvrir la page au second appui —, et c'est désormais exact : le
      // mécanisme suit la règle (voir plus haut).
      //
      // SUR macOS, RIEN À AJOUTER : la vignette y est un `Button` dont l'action
      // suit la même règle, et son menu contextuel porte « Se connecter ».
      .accessibilityHint(T("Sélectionne cette machine ; un second appui ouvre sa page"))
      .accessibilityAction(named: T("Se connecter")) {
        surSelectionServeur(serveur)
      }
    #else
      Button {
        // SÉLECTIONNER, OU OUVRIR LA PAGE — la règle est dans le modèle.
        //
        // L'historique de ce geste vaut d'être gardé : il a d'abord ouvert la page
        // seule (« il fallait ensuite viser “Se connecter” »), puis les deux à la
        // fois (« toucher une machine, c'est vouloir s'y connecter »). Il fait
        // maintenant ce que l'usage demande : un appui SÉLECTIONNE — on reste sur
        // la liste, avec les sessions de la nouvelle machine — et un second appui
        // ouvre sa fiche.
        surSelectionServeur(serveur)
      } label: {
        IconeServeur(
          serveur: serveur,
          libelle: libelles[serveur.id] ?? serveur.premierMot,
          cote: cote,
          choisi: modele.serveurChoisi == serveur,
          sertDsh: modele.sertDsh(serveur))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        EtatMachine.libelleAccessible(
          nom: serveur.nom, enLigne: serveur.enLigne, sertDsh: modele.sertDsh(serveur),
          estLocal: serveur.estLocal)
      )
    #endif
  }

  /// CE QU'UN APPUI LONG PROPOSE SUR UNE MACHINE.
  ///
  /// POURQUOI « OUblier » N'EST PAS OFFERT PARTOUT. `oublierServeur()` oublie
  /// l'adresse MÉMORISÉE — celle de la machine courante —, et vide la liste venue
  /// de son hôte. L'offrir sur une autre vignette agirait donc sur une machine
  /// que l'utilisateur n'a pas désignée : un bouton qui agit ailleurs, exactement
  /// ce que la page d'un serveur a déjà corrigé pour « Tester ». L'entrée
  /// n'apparaît donc que sur la machine courante.
  @ViewBuilder
  private func menuDeMachine(_ serveur: ServeurMac) -> some View {
    Button {
      // « SE CONNECTER » EST UNE ACTION NOMMÉE, DONC ELLE CONNECTE — elle ne
      // décide d'aucune page. C'est `ModeleApp.toucher` qui porte la règle de
      // l'appui sur la vignette (sélectionner, ou ouvrir si c'est déjà la cible),
      // et la mêler ici rendrait le menu imprévisible : on ne saurait plus si
      // « Se connecter » ouvre une fiche ou change de machine.
      //
      // La branche `#if os(macOS)` qui vivait ici a disparu avec elle : le menu
      // fait la même chose sur les deux plateformes.
      Task { await modele.choisirEtConnecter(serveur) }
    } label: {
      Label(
        modele.serveurChoisi == serveur ? "Reconnecter" : "Se connecter",
        systemImage: "bolt.horizontal")
    }
    Button {
      PressePapiers.ecrire(serveur.adresse)
    } label: {
      Label { T("Copier l'adresse") } icon: { Image(systemName: "doc.on.doc") }
    }
    if modele.serveurChoisi == serveur {
      Divider()
      Button(role: .destructive) {
        modele.oublierServeur()
      } label: {
        Label { T("Oublier ce serveur") } icon: { Image(systemName: "trash") }
      }
    }
  }
}

/// Une icône de serveur : la vignette, la pastille d'état, le nom d'un mot.
struct IconeServeur: View {
  let serveur: ServeurMac
  /// LE LIBELLÉ DE LA VIGNETTE — un mot, ou deux quand un seul ne distingue pas.
  ///
  /// POURQUOI IL VIENT DU DEHORS. Deux machines d'un même tailnet peuvent partager
  /// leur premier mot — « Portable Un » et « Portable Deux » s'affichaient toutes
  /// deux « Portable » —, et l'appui CHANGE la connexion. Le calcul appartient
  /// donc à la LISTE (`NomsCourts`) : c'est la comparaison entre machines qui dit
  /// si un mot suffit, et une vignette seule ne peut pas le savoir.
  let libelle: String
  /// LE CÔTÉ DE LA VIGNETTE, DÉJÀ MIS À L'ÉCHELLE DU TEXTE.
  ///
  /// POURQUOI UN SEUL CÔTÉ, ET NON CINQ. Le dessin est proportionné : le glyphe,
  /// la pastille, la coche et la largeur des deux lignes se déduisent tous du
  /// côté. Cinq `@ScaledMetric` indépendants auraient pu diverger et casser
  /// l'alignement — celui, surtout, que la vignette partage avec le bouton
  /// « Ajouter ».
  let cote: CGFloat
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

  /// Le côté du CADRE : la vignette, plus la marge qui la sépare des autres.
  private var cadre: CGFloat { cote + 6 }
  private var coteGlyphe: CGFloat { cote * 0.4355 }
  private var cotePastille: CGFloat { cote * 0.242 }
  private var coteCoche: CGFloat { cote * 0.3065 }

  var body: some View {
    VStack(spacing: 6) {
      ZStack {
        RoundedRectangle(cornerRadius: cote * 0.242, style: .continuous)
          .fill(
            LinearGradient(
              colors: serveur.enLigne
                ? [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.65)]
                : [Color.secondary.opacity(0.45), Color.secondary.opacity(0.28)],
              startPoint: .topLeading, endPoint: .bottomTrailing)
          )
          .frame(width: cote, height: cote)
          .overlay {
            Image(systemName: serveur.symbole)
              .font(.system(size: coteGlyphe, weight: .regular))
              .foregroundStyle(.white)
          }
        // La sélection est une COCHE, dans le coin, et non un contour : sur une
        // vignette déjà colorée, un anneau de 2 points se confond avec ses
        // propres bords — mesuré sur le prototype, le serveur choisi ne se
        // distinguait pas des autres. Le coin haut-gauche est libre : la
        // pastille d'état occupe le coin bas-droit.
        if choisi {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: coteCoche))
            .foregroundStyle(.white, Color.accentColor)
            .offset(x: -(cote / 2) + 2, y: -(cote / 2) + 2)
        }
      }
      .frame(width: cote, height: cote)
      .overlay(alignment: .bottomTrailing) {
        // Vert : en ligne ET DSH vérifié. Orange : en ligne, mais la sonde n'a
        // pas encore répondu. Gris : hors ligne, ou DSH absent — dans les deux
        // cas, appuyer ne donnera rien.
        Circle()
          .fill(couleurPastille)
          .frame(width: cotePastille, height: cotePastille)
          .overlay { Circle().strokeBorder(.background, lineWidth: 2.5) }
          .offset(x: 3, y: 3)
      }
      .frame(width: cadre, height: cadre)
      // Une vignette SANS DSH est atténuée : c'est ce qui se voit d'un coup
      // d'œil, avant même de lire la légende.
      .opacity(sertDsh == false ? 0.55 : 1)

      Text(libelle)
        .font(.caption2)
        .lineLimit(1)
        .foregroundStyle(choisi ? Color.primary : Color.secondary)
        .frame(width: cadre)
      // La légende dit l'état RÉEL : « hôte » pour la machine interrogée, et
      // « pas de DSH » pour celle dont la sonde a montré qu'elle ne répondra
      // pas. Réservée en place (`opacity`) pour que les icônes restent alignées.
      //
      // ELLE EST EN `.caption2`, ET NON EN 9 POINTS. Neuf points est sous le
      // minimum que la directive donne pour du texte utile — onze sur iOS, dix sur
      // macOS —, et c'est la SEULE ligne qui dit « pas de DSH » : la rendre
      // illisible revient à ne pas la dire. Deux lignes sont autorisées parce que
      // la vignette fait 68 points de large, et qu'un mot long vaut mieux coupé
      // que rapetissé.
      Text(legende)
        .font(.caption2)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .foregroundStyle(.tertiary)
        .frame(width: cadre)
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
  ///
  /// LES MOTS VIENNENT D'`EtatMachine`, comme ceux de la pastille de la page : les
  /// deux endroits disaient le même fait avec des mots différents — « hors ligne »
  /// ici, « hors ligne sur le tailnet » là —, et deux vocabulaires pour un fait
  /// obligent le lecteur à traduire. Ici la forme est ABRÉGÉE : la vignette tient
  /// en 68 points.
  private var legende: String {
    EtatMachine.decrire(
      enLigne: serveur.enLigne, sertDsh: sertDsh, estLocal: serveur.estLocal, court: true
    ).texte
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
/// Le CONTENU de la vignette « Ajouter » : un carré en pointillés, et sa légende.
///
/// POURQUOI LE CONTENU EST SÉPARÉ DU GESTE. Sur iPhone, la vignette est un
/// `NavigationLink` (elle EMPILE la page) ; sur macOS, un `Button` (la page
/// remplace le contenu de droite). Le dessin est le même — c'est la façon de
/// naviguer qui diffère, et elle seule.
struct ContenuAjouter: View {
  /// Vrai pendant une recherche : le carré en pointillés se remplit d'un
  /// indicateur, pour qu'un appui ne reste jamais sans réponse visible.
  let enRecherche: Bool
  /// Le côté de la vignette, mis à l'échelle du texte par le carrousel.
  ///
  /// IL VIENT DU DEHORS, ET C'EST LA CONDITION DE L'ALIGNEMENT : les deux dessins
  /// — une machine et « Ajouter » — doivent partager la même cote au point près,
  /// sinon l'un descend pendant que l'autre monte. Deux `@ScaledMetric` auraient
  /// été deux sources de vérité pour une seule cote.
  let cote: CGFloat

  private var cadre: CGFloat { cote + 6 }

  var body: some View {
    VStack(spacing: 6) {
      RoundedRectangle(cornerRadius: cote * 0.242, style: .continuous)
        .strokeBorder(
          Color.secondary.opacity(0.45),
          style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
        )
        .frame(width: cote, height: cote)
        .overlay {
          if enRecherche {
            ProgressView().controlSize(.small)
          } else {
            Image(systemName: "plus")
              .font(.system(size: cote * 0.387, weight: .light))
              .foregroundStyle(Color.secondary)
          }
        }
        // Le cadre, comme la vignette d'un serveur : c'est lui qui place les
        // deux dessins à la même hauteur.
        .frame(width: cadre, height: cadre)

      T("Ajouter")
        .font(.caption2)
        .foregroundStyle(Color.secondary)
        .frame(width: cadre)
    }
  }
}

/// Une valeur de NAVIGATION pour la page « Ajouter un serveur ».
///
/// Elle ne porte rien : la page n'a pas besoin de savoir d'où l'on vient. Elle
/// existe pour que le `NavigationLink` d'iOS ait une destination à empiler,
/// distincte de celle d'une machine.
struct PageAjoutServeur: Hashable {}

/// Ce qu'on voit quand aucun Mac n'a été trouvé : la cause, ET les voies qui en sortent.
///
/// POURQUOI « AJOUTER UN SERVEUR » EST ICI. La page d'ajout est le seul endroit
/// qui liste le travail à faire pour qu'un Mac devienne un serveur — dont
/// l'installation de Tailscale, quand il manque. Or elle n'était atteignable que
/// par la vignette du carrousel… qui ne s'affiche PAS quand la liste est vide :
/// l'appareil neuf, celui qui a le plus besoin des quatre étapes, n'y avait donc
/// aucun accès. C'était déjà un trou ; le retrait de la carte Tailscale l'aurait
/// rendu visible, puisque c'est elle qui portait le bouton « Installer ».
struct ServeursVides: View {
  let modele: ModeleApp
  /// Ouvre la saisie manuelle d'une adresse.
  let surAdresse: () -> Void
  /// Ouvre la page « Ajouter un serveur ».
  let surAjout: () -> Void
  /// La feuille d'appairage — le premier des trois chemins, parce que c'est le
  /// plus court quand le Mac est à portée.
  @State private var appairageOuvert = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(modele.messageListeVide, systemImage: "wifi.exclamationmark")
        .font(.callout)
        .foregroundStyle(EtatVisuel.attention.couleur)
        .fixedSize(horizontal: false, vertical: true)

      // LES VOIES SORTENT DE L'IMPASSE, dans l'ordre où elles servent : la page
      // qui EXPLIQUE (elle marche sans rien savoir de la machine), la saisie
      // d'une adresse connue, puis la recherche.
      //
      // Elles sont empilées et non alignées : trois libellés côte à côte ne
      // tiennent pas sur un iPhone, et la colonne latérale y est plus étroite
      // encore qu'ailleurs.
      VStack(alignment: .leading, spacing: 8) {
        // L'APPAIRAGE EN PREMIER, ET C'EST UN ORDRE DÉLIBÉRÉ : quand le Mac est à
        // portée, c'est UN geste contre quatre étapes expliquées. Le reste des
        // voies ne disparaît pas — elles servent quand le Mac est ailleurs.
        Button {
          appairageOuvert = true
        } label: {
          #if os(iOS)
            Label { T("Scanner le QR code") } icon: { Image(systemName: "qrcode.viewfinder") }
          #else
            Label { T("Coller un appairage") } icon: { Image(systemName: "doc.on.clipboard") }
          #endif
        }
        .buttonStyle(.borderedProminent)
        // LE MODIFICATEUR EST SUR LE BOUTON, PAS DANS LA FERMETURE : entre les
        // branches d'un `#if`, un modificateur après `#endif` se rattache à la
        // dernière branche et la compilation échoue (« cannot be used on type
        // View »). Mesuré, et corrigé ici.
        .font(.callout)

        #if os(iOS)
          // Même mécanique que la vignette « Ajouter » du carrousel : sur iPhone,
          // la page s'EMPILE.
          NavigationLink(value: PageAjoutServeur()) {
            Label { T("Ajouter un serveur") } icon: { Image(systemName: "plus.square.dashed") }
              .font(.callout)
          }
          .simultaneousGesture(TapGesture().onEnded { surAjout() })
        #else
          Button {
            surAjout()
          } label: {
            Label { T("Ajouter un serveur") } icon: { Image(systemName: "plus.square.dashed") }
              .font(.callout)
          }
          .buttonStyle(.borderedProminent)
        #endif

        Button {
          surAdresse()
        } label: {
          Label { T("Saisir une adresse") } icon: { Image(systemName: "keyboard") }
            .font(.callout)
        }
        .buttonStyle(.bordered)

        // Le bouton n'apparaît que là où il peut agir : sur iPhone, la
        // découverte locale est impossible, et un bouton sans effet est un
        // mensonge d'interface.
        if modele.rechercheServeursPossible {
          Button(L("Chercher une machine")) { Task { await modele.synchroniserServeurs() } }
            .font(.callout)
            .buttonStyle(.bordered)
            .disabled(modele.synchronisationEnCours)
        }
      }
    }
    .padding(.vertical, 4)
      .sheet(isPresented: $appairageOuvert) {
      FeuilleAppairage(modele: modele)
    }
}
}

// MARK: - Recherche

/// La recherche, en bas et toujours là.
struct BarreRecherche: View {
  @Binding var texte: String
  /// LE FOCUS DU CHAMP, tenu ici parce que ⌘F doit pouvoir le donner.
  @FocusState private var champActif: Bool

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      // LA FORME À FERMETURE, ET NON LE TITRE EN LITTÉRAL : c'est le seul moyen de
      // dire DANS QUEL PAQUET chercher la traduction. Mesuré : un littéral passé
      // directement cherche dans le programme principal, où la table de la
      // bibliothèque n'est pas.
      TextField(text: $texte) {
        T("Rechercher une session, un projet…")
      }
        .textFieldStyle(.plain)
        .autocorrectionDisabled()
        .focused($champActif)
        #if os(macOS)
          // ⌘F VIENT ICI. La commande de menu ne connaît pas ce champ : elle lit
          // la clôture publiée par cette vue, qui est la seule à pouvoir écrire
          // son `@FocusState` (voir `CommandesDeMenu`).
          .focusedSceneValue(\.focusRecherche) { champActif = true }
        #endif
        #if os(iOS)
          .textInputAutocapitalization(.never)
          // LA TOUCHE « RECHERCHER » DU CLAVIER, et la fermeture au défilement.
          // Sans elles, le clavier ne se refermait que par le geste système, et
          // rien ne disait que la saisie était finie.
          .submitLabel(.search)
          .onSubmit { champActif = false }
        #endif
      if !texte.isEmpty {
        Button {
          texte = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(T("Effacer la recherche"))
        .cibleTactile()
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    // UN SEUL FOND, ET PAS DEUX. Le champ portait une matière (`.regularMaterial`)
    // POSÉE SUR une bande elle aussi en matière (`.bar`), plus un contour : trois
    // épaisseurs pour un champ de recherche, et c'est exactement ce que la
    // documentation du SDK 26 demande d'éviter — les fonds maison derrière les
    // barres recouvrent le verre du système au lieu de le laisser faire.
    //
    // Le champ prend donc le même dessin que celui du composeur, qui n'a jamais
    // eu ce défaut : un fond discret, sans matière propre, sur la bande unique.
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
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
  /// « Réduire les animations », LU ET RESPECTÉ.
  ///
  /// POURQUOI CE N'EST PAS UNE OPTION. L'indicateur tournait en boucle
  /// infinie sur chaque session active, sans jamais consulter le réglage : une
  /// animation perpétuelle est précisément ce que ce réglage existe pour
  /// arrêter, et le modèle portait déjà `EtatSession.anime` — que personne ne
  /// lisait.
  @Environment(\.accessibilityReduceMotion) private var reduireLesAnimations: Bool
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
        .onAppear { reglerAnimation() }
        // Le réglage peut changer PENDANT que l'application vit : on le relit.
        .onChange(of: reduireLesAnimations) { _, _ in reglerAnimation() }
        // CE N'EST PAS UN `EtatVisuel`, ET C'EST DÉLIBÉRÉ : « un tour s'exécute »
        // est un marqueur d'ACTIVITÉ, pas un des cinq états (prêt, à vérifier,
        // erreur, en attente, information). L'interface web a une famille pour
        // cela — `--dsw-alias-state-business-*` —, et si l'on veut la parité
        // jusqu'à ce point-là, c'est un sixième cas à ajouter ici, pas une
        // couleur à choisir sur place.
        .foregroundStyle(.orange)
      case .attendReponse:
        // UN POINT D'INTERROGATION, et non un point orange de plus.
        //
        // POURQUOI LA FORME A CHANGÉ. « Attend une réponse » était un disque orange
        // de 8 points, « terminée » un disque vert de 7 : un point de différence,
        // c'est-à-dire rien. Or ces deux états appellent des gestes OPPOSÉS — l'un
        // demande une décision, l'autre est une bonne nouvelle à lire —, et ils se
        // distinguaient par la seule couleur, ce que la directive interdit
        // précisément. Le glyphe dit l'état par sa forme, la couleur le confirme :
        // un « ? » se reconnaît même pour qui ne distingue pas l'orange du vert.
        //
        // La taille reste celle des autres pastilles : c'est la forme qui porte le
        // sens, pas le volume.
        Image(systemName: "questionmark.circle.fill")
          .font(.caption2)
          .foregroundStyle(EtatVisuel.attention.couleur)
          .accessibilityHidden(true)
      case .terminee:
        // Le rappel de fin : plein et vert. Il s'efface quand la session est
        // ouverte.
        Circle().fill(EtatVisuel.pret.couleur).frame(width: 7, height: 7)
        // Pas de glyphe ici : le disque vert est l'état le plus fréquent des deux
        // « pleins », et lui donner un signe de plus encombrerait la liste. Ce qui
        // compte est qu'il ne ressemble PAS au point d'interrogation.
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
    // L'INDICATEUR EST DÉCORATIF POUR VOIXOVER, et seulement pour lui : la ligne
    // entière porte l'état en mots (`AfficheLigneSession.libelleAccessible`).
    // Le laisser parler doublerait l'information — et deux fois la même chose se
    // lit comme deux choses.
    .accessibilityHidden(true)
  }

  /// Démarre — ou arrête net — la rotation, selon le réglage système.
  ///
  /// QUAND ON ARRÊTE, L'ÉTAT RESTE VISIBLE : les quatre carrés orange demeurent,
  /// immobiles. Une animation supprimée ne doit jamais emporter l'information
  /// avec elle.
  private func reglerAnimation() {
    guard etat.anime, !reduireLesAnimations else {
      phase = 0
      return
    }
    withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
      phase = 360
    }
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
    // LA RÈGLE EST UNIQUE, et elle vit dans `EtatSession` : la pastille, le tri
    // d'urgence et les compteurs par espace répondent tous à la même question.
    self.etat = EtatSession.de(session, rappelDeFin: rappelDeFin)
    self.evenements = session.resume.nbEnregistrements
    self.octets = session.octets
    self.age = AgeLisible.texte(session.resume.dernierEvenementLe)
    self.illisible = session.illisible
  }

  /// CE QUE VOIXOVER ANNONCE POUR LA LIGNE — une phrase, pas cinq fragments.
  ///
  /// POURQUOI ELLE EST ICI, ET NON DANS LA VUE. Ce type est le seul endroit où
  /// le contenu d'une ligne est réuni en VALEURS ; la vue ne fait que le
  /// dessiner. Une phrase se relit et s'éprouve, un `Text` non.
  ///
  /// L'ORDRE EST CELUI DE L'IMPORTANCE : le titre, puis l'état — la seule chose
  /// qui appelle une action —, puis la matière, puis l'âge. « au repos » est tu :
  /// c'est le cas le plus fréquent, et le silence est ici une information.
  var libelleAccessible: String {
    var morceaux = [titre]
    if etat != .rien { morceaux.append(etat.libelle) }
    if let evenements {
      morceaux.append("\(evenements) événement\(evenements > 1 ? "s" : "")")
    }
    if let octets {
      morceaux.append(ByteCountFormatter.string(fromByteCount: Int64(octets), countStyle: .file))
    }
    if !age.isEmpty { morceaux.append(age) }
    if let illisible { morceaux.append(illisible) }
    return morceaux.joined(separator: ", ")
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
        Text(illisible).font(.caption2).foregroundStyle(EtatVisuel.attention.couleur)
      }
    }
    .padding(.vertical, 2)
    // UNE LIGNE, UNE PHRASE. Sans cela, VoiceOver énumère cinq fragments sans
    // jamais dire l'état — la seule information qui demande d'agir.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(affiche.libelleAccessible)
  }
}

// MARK: - Les gestes d'une session

extension View {
  /// LES ACTIONS D'UNE SESSION, au glissement comme au menu contextuel.
  ///
  /// POURQUOI LES DEUX, ET POURQUOI LES MÊMES. Le glissement est le geste qu'on
  /// essaie d'abord sur un iPhone ; le menu contextuel est le seul qui existe sur
  /// les DEUX plateformes, qui s'ouvre au clavier et que VoiceOver atteint. Les
  /// directives demandent que l'action de tête d'un glissement corresponde aux
  /// entrées du menu : les deux listes sont donc écrites ici, côte à côte, et
  /// l'ordre y est le même.
  ///
  /// POURQUOI LE GLISSEMENT EST RÉSERVÉ À iOS. Sur macOS, `swipeActions` se
  /// compile mais ne se déclenche pas : un geste qu'aucun matériel ne produit est
  /// du code mort, et le menu contextuel y fait déjà le travail.
  ///
  /// CE QU'IL N'Y A PAS, ET POURQUOI. Aucune action destructive : cette
  /// application ne supprime pas de session, et un menu qui proposerait de le
  /// faire promettrait ce que l'hôte ne sait pas faire.
  @ViewBuilder
  func gestesDeSession(_ session: SessionListee, modele: ModeleApp, rappelArme: Bool) -> some View {
    #if os(iOS)
      self
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
          // LE RAPPEL DE FIN SE CONSOMME ICI. Il ne s'effaçait qu'en ouvrant la
          // session — c'est-à-dire en quittant la liste, au moment précis où l'on
          // vient d'y repérer ce qui a fini.
          if rappelArme {
            Button {
              modele.marquerCommeVue(session.id)
            } label: {
              Label { T("Vu") } icon: { Image(systemName: "checkmark.circle") }
            }
            .tint(EtatVisuel.pret.couleur)
          }
          Button {
            PressePapiers.ecrire(session.titreAffiche)
          } label: {
            Label { T("Copier le titre") } icon: { Image(systemName: "doc.on.doc") }
          }
          .tint(.indigo)
        }
        .contextMenu { menuDeSession(session, modele: modele, rappelArme: rappelArme) }
    #else
      self.contextMenu { menuDeSession(session, modele: modele, rappelArme: rappelArme) }
    #endif
  }

  /// LES ENTRÉES DE MENU D'UNE SESSION, partagées par les deux gestes.
  ///
  /// L'IDENTIFIANT EST COPIABLE, et ce n'est pas un détail de technicien : c'est
  /// la clé qui relie une session à ce que l'hôte en dit — `dsh-remote-ctl`, le
  /// journal, une autre machine. Sans lui, on ne peut désigner une session à
  /// personne, ni la retrouver dans une sortie de commande.
  @ViewBuilder
  private func menuDeSession(_ session: SessionListee, modele: ModeleApp, rappelArme: Bool)
    -> some View
  {
    Button {
      PressePapiers.ecrire(session.titreAffiche)
    } label: {
      Label { T("Copier le titre") } icon: { Image(systemName: "doc.on.doc") }
    }
    Button {
      PressePapiers.ecrire(session.id)
    } label: {
      Label { T("Copier l'identifiant") } icon: { Image(systemName: "number") }
    }
    if rappelArme {
      Divider()
      Button {
        modele.marquerCommeVue(session.id)
      } label: {
        Label { T("Marquer comme vu") } icon: { Image(systemName: "checkmark.circle") }
      }
    }
  }
}
