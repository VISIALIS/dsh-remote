// Prototype de la nouvelle interface iOS de « DSH Remote ».
//
// CE FICHIER N'EST PAS L'APPLICATION. C'est une maquette EXÉCUTABLE : elle
// rejoue les données d'une vraie installation (trois Macs, cinq espaces de
// travail, des statuts contrastés) avec les vues telles qu'elles sont
// envisagées, pour juger le rendu avant d'écrire quoi que ce soit dans
// `Sources/DSHRemoteKit`.
//
// POURQUOI UNE MAQUETTE SWIFTUI ET NON UN DESSIN. Une capture d'écran du
// simulateur dit la vérité sur les métriques iOS — marges, tailles de texte,
// comportement du verre, troncature — qu'un dessin extérieur ne peut
// qu'approximer. Le prototype se compile et s'installe comme l'application, donc
// ce qui est montré est exactement ce que SwiftUI rend.
//
// Structure de l'écran :
//   1. « TailScale » — une carte d'état et d'action (installer / ouvrir / à jour)
//   2. « Serveurs »  — un carrousel d'icônes, une par Mac, nom sous l'icône
//   3. « Workspaces » — l'arbre des sessions, groupé comme aujourd'hui
//   4. Recherche      — en bas, ancrée, toujours accessible
//
// L'écran se choisit par l'environnement, ce qui permet de capturer chaque état
// sans recompiler :
//   DSH_ECRAN=carte      → la carte Tailscale seule, application absente
//   DSH_ECRAN=sans-mac   → aucun Mac découvert : ce que voit un premier lancement
//   DSH_ECRAN=complet    → l'écran entier (défaut)
//   DSH_ECRAN=reglages   → la feuille de configuration (adresse + jeton)

import SwiftUI

// MARK: - Modèle de démonstration

/// Un serveur, réduit à ce que la vue consomme.
struct ServeurDemo: Identifiable, Hashable {
  let nom: String
  let nomDNS: String
  let enLigne: Bool
  let estLocal: Bool
  var id: String { nomDNS }

  /// Premier mot du nom, affiché SOUS l'icône : un nom de machine Tailscale est
  /// long (« MacBook Air de Camille »), et une légende d'icône se lit d'un mot.
  var premierMot: String {
    nom.split(separator: " ").first.map(String.init) ?? nom
  }

  /// Symbole déduit du nom, comme dans `ServeurMac.symbole` : les mêmes règles,
  /// pour que le prototype ne promette pas une icône que la vraie donnée ne
  /// permet pas de choisir.
  var symbole: String {
    let minuscule = nom.lowercased().replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
    if minuscule.contains("macbook") { return "macbook" }
    let compact = minuscule.replacingOccurrences(of: " ", with: "")
    if compact.contains("macmini") { return "macmini" }
    if compact.contains("macstudio") { return "macstudio" }
    return "desktopcomputer"
  }
}

/// État d'une session, pour la pastille.
enum EtatDemo {
  case repos, travaille, attend, termine, inconnu

  var symbole: String? {
    switch self {
    case .repos: return nil
    case .travaille: return "square.grid.2x2"
    case .attend: return "hand.raised.fill"
    case .termine: return "checkmark.circle.fill"
    case .inconnu: return "circle.dotted"
    }
  }

  var teinte: Color {
    switch self {
    case .termine: return .green
    case .inconnu: return .secondary
    default: return .orange
    }
  }
}

struct SessionDemo: Identifiable, Hashable {
  let titre: String
  let etat: EtatDemo
  let evenements: Int
  let volume: String
  let age: String
  let sousAgent: Bool
  var id: String { titre }
}

struct EspaceDemo: Identifiable, Hashable {
  let nom: String
  let sessions: [SessionDemo]
  var id: String { nom }
}

enum DonneesDemo {
  static let serveurs: [ServeurDemo] = [
    ServeurDemo(nom: "MacMini Bureau", nomDNS: "macmini.exemple.ts.net", enLigne: true, estLocal: true),
    ServeurDemo(nom: "MacBook Air Camille", nomDNS: "macbook-air.exemple.ts.net", enLigne: true, estLocal: false),
    ServeurDemo(nom: "MacStudio Atelier", nomDNS: "macstudio.exemple.ts.net", enLigne: false, estLocal: false),
  ]

  static let espaces: [EspaceDemo] = [
    EspaceDemo(
      nom: "dsh-plugins",
      sessions: [
        SessionDemo(titre: "Application iOS Swift pour DeepSeek", etat: .travaille, evenements: 486, volume: "1,2 Mo", age: "2min", sousAgent: false),
        SessionDemo(titre: "Vérifier la signature de l'application", etat: .termine, evenements: 132, volume: "310 Ko", age: "1h", sousAgent: false),
        SessionDemo(titre: "Explorer la découverte des serveurs", etat: .repos, evenements: 88, volume: "204 Ko", age: "3h", sousAgent: true),
      ]),
    EspaceDemo(
      nom: "acme-project",
      sessions: [
        SessionDemo(titre: "Refonte de la page d'accueil", etat: .attend, evenements: 214, volume: "640 Ko", age: "22min", sousAgent: false),
        SessionDemo(titre: "Corriger le formulaire de contact", etat: .repos, evenements: 57, volume: "96 Ko", age: "2j", sousAgent: false),
      ]),
    EspaceDemo(
      nom: "outils-internes",
      sessions: [
        SessionDemo(titre: "Générateur de factures — lot 4", etat: .repos, evenements: 301, volume: "820 Ko", age: "5h", sousAgent: false),
      ]),
  ]
}

// MARK: - Détection de Tailscale

/// Ce que l'application sait de Tailscale, sans jamais interroger le réseau.
///
/// iOS n'expose PAS la liste des applications installées : aucune API ne répond
/// à « Tailscale est-il là ? ». Deux faits sont en revanche vérifiables :
///
///   1. l'application répond-elle à son schéma d'URL (`tailscale://`) ? C'est le
///      seul test d'installation possible, et il ne demande aucune permission —
///      `canOpenURL` sur un schéma déclaré dans `LSApplicationQueriesSchemes` ;
///   2. un serveur répond-il, c'est-à-dire le tailnet fonctionne-t-il ?
///
/// Le second compte autant que le premier : Tailscale peut être installé ET
/// déconnecté, auquel cas « Ouvrir » est la bonne action, pas « Installer ».
enum EtatTailscale {
  case absent
  case installe
  case connecte

  var titre: String {
    switch self {
    case .absent: return "Tailscale n'est pas installé"
    case .installe: return "Tailscale est installé"
    case .connecte: return "Tailscale est connecté"
    }
  }

  /// La description porte le VERBE de l'action, parce que la carte entière est
  /// cliquable : sans cela, l'appui serait un pari sur ce qui va s'ouvrir.
  var detail: String {
    switch self {
    case .absent:
      return "Touchez pour l'installer : c'est lui qui relie l'iPhone au Mac, sans câble ni configuration réseau."
    case .installe:
      return "Touchez pour l'ouvrir et vous connecter. Sans connexion au tailnet, aucun Mac n'est joignable."
    case .connecte:
      return "Touchez pour vérifier : 3 Macs répondent sur le tailnet, dont l'hôte interrogé."
    }
  }

  var symbole: String {
    switch self {
    case .absent: return "arrow.down.circle"
    case .installe: return "arrow.up.forward.app"
    case .connecte: return "checkmark.seal.fill"
    }
  }

  var teinte: Color {
    switch self {
    case .absent: return .orange
    case .installe: return .orange
    case .connecte: return .green
    }
  }

  /// Libellé du bouton : il dit ce que l'appui FERA, jamais autre chose.
  var action: String {
    switch self {
    case .absent: return "Installer"
    case .installe: return "Ouvrir"
    case .connecte: return "Vérifier"
    }
  }

  var iconeAction: String {
    switch self {
    case .absent: return "arrow.down.circle.fill"
    case .installe: return "arrow.up.forward.app.fill"
    case .connecte: return "arrow.clockwise"
    }
  }
}

/// Vrai si l'application Tailscale répond à son schéma d'URL.
///
/// C'est le SEUL test d'installation possible depuis iOS, qui n'expose pas la
/// liste des applications installées. Il exige que `tailscale` figure dans
/// `LSApplicationQueriesSchemes` de l'Info.plist : sans cette déclaration,
/// `canOpenURL` rend toujours `false`, et l'application proposerait d'installer
/// un Tailscale déjà présent. Le script de construction déclare le schéma.
///
/// Ce que ce test NE dit PAS : si Tailscale est connecté. Un tailnet déconnecté
/// se voit au fait qu'aucun serveur ne répond, pas ici.
func tailscaleInstalle() -> Bool {
  guard let url = URL(string: "tailscale://") else { return false }
  return UIApplication.shared.canOpenURL(url)
}

// MARK: - Écran principal

struct EcranPrincipal: View {
  /// L'écran demandé au lancement, et l'écran COURANT.
  ///
  /// POURQUOI CE N'EST PAS UNE CONSTANTE. iOS ne transmet aucune variable
  /// d'environnement à une application lancée depuis l'écran d'accueil : sur
  /// l'iPhone, l'écran demandé à la construction serait le seul visible, et il
  /// faudrait réinstaller pour voir l'état suivant. Un appui sur le titre fait
  /// donc défiler les écrans — la maquette se juge sur l'appareil, pas sur le
  /// Mac.
  @State private var ecran: String

  @State private var serveurChoisi: String? = DonneesDemo.serveurs.first?.id
  @State private var recherche = ""
  @State private var plies: Set<String> = ["dsh-plugins"]
  @State private var reglagesOuverts: Bool
  @State private var serveurPourFiche: ServeurDemo?
  @State private var ajoutOuvert = false

  /// Les états de la maquette, dans l'ordre de l'appui sur le titre.
  static let ecrans = ["complet", "un-mac", "carte", "sans-mac", "reglages"]

  init(ecran: String) {
    _ecran = State(initialValue: ecran)
    // L'écran des réglages s'ouvre d'emblée quand on le demande : une capture
    // d'écran ne peut pas appuyer sur un bouton.
    _reglagesOuverts = State(initialValue: ecran == "reglages")
  }

  /// Écran suivant, en boucle.
  private func ecranSuivant() {
    let index = Self.ecrans.firstIndex(of: ecran) ?? 0
    let suivant = Self.ecrans[(index + 1) % Self.ecrans.count]
    ecran = suivant
    plies = ["dsh-plugins"]
    reglagesOuverts = suivant == "reglages"
  }

  private var serveurs: [ServeurDemo] {
    if ecran == "sans-mac" { return [] }
    if ecran == "un-mac" { return Array(DonneesDemo.serveurs.prefix(1)) }
    return DonneesDemo.serveurs
  }

  private var etatTailscale: EtatTailscale {
    if ecran == "sans-mac" { return .installe }
    if ecran == "carte" { return .absent }
    return .connecte
  }

  private var espaces: [EspaceDemo] {
    guard !recherche.isEmpty else { return DonneesDemo.espaces }
    let terme = recherche.lowercased()
    return DonneesDemo.espaces.compactMap { espace in
      let retenues = espace.sessions.filter { $0.titre.lowercased().contains(terme) }
      return retenues.isEmpty ? nil : EspaceDemo(nom: espace.nom, sessions: retenues)
    }
  }

  private var nbSessions: Int { espaces.reduce(0) { $0 + $1.sessions.count } }

  var body: some View {
    NavigationStack {
      List {
        Section {
          CarteTailscale(etat: etatTailscale)
            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
        } header: {
          Entete("TailScale")
        }

        Section {
          if serveurs.isEmpty {
            ListeVide()
          } else {
            CarrouselServeurs(
              serveurs: serveurs,
              choix: $serveurChoisi,
              surOuvrirFiche: { serveur in serveurPourFiche = serveur },
              surAjout: { ajoutOuvert = true }
            )
            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 6, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
          }
        } header: {
          Entete("Serveurs", detail: serveurs.isEmpty ? nil : "\(serveurs.filter(\.enLigne).count) en ligne")
        }

        Section {
          ForEach(espaces) { espace in
            DisclosureGroup(
              isExpanded: Binding(
                get: { !recherche.isEmpty || plies.contains(espace.id) },
                set: { ouvert in
                  if ouvert { plies.insert(espace.id) } else { plies.remove(espace.id) }
                }
              )
            ) {
              ForEach(espace.sessions) { session in
                LigneSessionDemo(session: session)
                  .padding(.leading, session.sousAgent ? 14 : 0)
              }
            } label: {
              HStack(spacing: 8) {
                Image(systemName: "folder")
                  .foregroundStyle(Color.accentColor)
                Text(espace.nom)
                Spacer()
                Text("\(espace.sessions.count)")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
        } header: {
          Entete("Workspaces", detail: "\(nbSessions) session\(nbSessions > 1 ? "s" : "")")
        }
      }
      .listStyle(.insetGrouped)
      .navigationTitle("DSH Remote")
      // Titre EN LIGNE, et non grand. Mesuré à l'écran : le grand titre coûtait
      // 60 points pour répéter le nom de l'application, déjà connu de qui
      // l'ouvre — et ces 60 points manquaient aux sessions, dont deux seulement
      // restaient visibles. Le titre reste écrit, en petit, dans la barre.
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        // L'écran courant est ÉCRIT dans la barre, et il est CLIQUABLE.
        //
        // Ce n'est pas un ornement : c'est ce qui permet de juger les quatre
        // états de la maquette sur l'iPhone lui-même. Une variable
        // d'environnement ne traverse pas le lancement depuis l'écran
        // d'accueil, et réinstaller entre chaque écran rendrait la
        // vérification impossible. La mention disparaîtra à l'implémentation.
        ToolbarItem(placement: .principal) {
          Button {
            ecranSuivant()
          } label: {
            VStack(spacing: 0) {
              Text("DSH Remote")
                .font(.headline)
                .foregroundStyle(.primary)
              Text("prototype · \(libelleEcran)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Prototype, écran \(libelleEcran). Appuyer pour l'écran suivant.")
        }
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
        FeuilleReglages(serveurChoisi: $serveurChoisi)
      }
      .sheet(item: $serveurPourFiche) { serveur in
        VueFicheServeurDemo(serveur: serveur)
      }
      .sheet(isPresented: $ajoutOuvert) {
        VueAjoutServeurDemo()
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        BarreRecherche(texte: $recherche)
      }
    }
  }

  /// Nom lisible de l'écran courant, affiché sous le titre.
  private var libelleEcran: String {
    switch ecran {
    case "un-mac": return "1 seul serveur"
    case "carte": return "tailscale à installer"
    case "sans-mac": return "aucun Mac"
    case "reglages": return "réglages"
    default: return "connecté (multi-serveurs)"
    }
  }
}

/// En-tête de section : la même graisse que les en-têtes iOS natifs, avec une
/// valeur à droite quand elle existe.
struct Entete: View {
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

// MARK: - 1. Carte Tailscale

/// La carte d'état de Tailscale : icône, titre, raison d'être, action.
///
/// POURQUOI UNE CARTE ET PAS UNE LIGNE. Tailscale n'est pas un réglage parmi
/// d'autres : sans lui, l'application ne joint rien du tout, et la cause est
/// invisible (un tailnet déconnecté ressemble à un serveur éteint). La carte
/// porte donc l'explication ET l'action, au-dessus de tout le reste.
///
/// L'ACTION EST DANS LA CARTE, ET ELLE CHANGE DE VERBE. « Installer » ouvre
/// l'App Store, « Ouvrir » lance l'application, « Vérifier » relit la liste des
/// serveurs.
///
/// POURQUOI UN CHEVRON ET NON UN BOUTON TEXTE. Deux dispositions ont été
/// essayées avant celle-ci, et toutes deux ont échoué POUR UNE RAISON MESURÉE À
/// L'ÉCRAN :
///
///   1. un bouton pleine largeur sous la carte — 60 points de hauteur pour
///      répéter ce que la carte venait de dire, et plus aucune session visible ;
///   2. un bouton capsule à droite du titre — « Tailscale est connecté » se
///      cassait sur deux lignes, et la pastille d'état se retrouvait orpheline
///      sous le titre. Un titre coupé en deux pour loger un bouton de 90 points
///      est un mauvais échange.
///
/// La carte ENTIÈRE est donc la cible, avec un chevron : c'est la convention iOS
/// pour « cette ligne mène quelque part ». Le libellé de l'action reste écrit
/// dans la description, pour qu'aucun appui ne soit un pari.
///
/// UN PIÈGE DE `Link`, MESURÉ À L'ÉCRAN : la teinte du lien s'applique à TOUT son
/// contenu. Dans l'état « à installer », le titre et la description viraient au
/// bleu du système — la carte se lisait comme une phrase cliquable, et non comme
/// un avertissement. `Link` est donc employé SANS style de bouton, et chaque
/// texte porte explicitement sa couleur ; la teinte ne colore plus que le
/// chevron, qui est l'affordance.
struct CarteTailscale: View {
  let etat: EtatTailscale

  var body: some View {
    Group {
      switch etat {
      case .absent:
        Link(destination: URL(string: "https://apps.apple.com/app/tailscale/id1470499037")!) { contenu }
      case .installe:
        Link(destination: URL(string: "tailscale://")!) { contenu }
      case .connecte:
        Button {
        } label: {
          contenu
        }
      }
    }
    .buttonStyle(.plain)
    .tint(etat.teinte)
  }

  private var contenu: some View {
    HStack(spacing: 12) {
      Image(systemName: etat.symbole)
        .font(.system(size: 28, weight: .semibold))
        .foregroundStyle(etat.teinte)
        .frame(width: 34)
      VStack(alignment: .leading, spacing: 3) {
        Text(etat.titre)
          .font(.headline)
          .foregroundStyle(Color.primary)
        Text(etat.detail)
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
        .strokeBorder(etat.teinte.opacity(0.25), lineWidth: 1)
    }
  }
}

// MARK: - 2. Carrousel des serveurs

/// Les serveurs en carrousel d'icônes, comme des icônes d'applications.
///
/// POURQUOI CE RENDU PLUTÔT QU'UNE LISTE DE LIGNES. Une liste de lignes dit
/// « réglage » ; un carrousel d'icônes dit « appareil ». Or c'est bien de cela
/// qu'il s'agit : chaque icône EST une machine, avec son icône de châssis, son
/// état, et son nom raccourci au premier mot — la forme sous laquelle on
/// reconnaît un appareil sur un bureau.
///
/// Évolution en cartes larges avec pagination à glissement et indicateurs de matériel.
/// Évolution en cartes larges avec pagination à glissement et indicateurs de matériel.
///
/// RECOMMANDATIONS DE L'AUDIT APPLIQUÉES :
/// - Pager `ScrollView(.horizontal)` sous iOS 17 avec `.scrollTargetBehavior(.viewAligned)`
///   et `.scrollPosition(id: $pageVisible)`.
/// - Dépassement visuel (*peek*) de 14 pt pour enseigner le geste de balayage.
/// - Hauteur intrinsèque et composition verticale aux tailles d'accessibilité.
/// - Découplage de la page affichée et de la sélection effective (debounce de 350 ms pour Option A).
/// - Premier appui sur une autre carte : sélection ; second appui : fiche détaillée.
/// - Suppression du badge redondant « Actif » sur la carte pour libérer l'espace du titre.
/// - Cibles tactiles 44×44 pt sur chaque indicateur et sur le bouton « + ».
/// - Barre conservée avec un serveur afin que le bouton « + » garde sa place.
struct CarrouselServeurs: View {
  let serveurs: [ServeurDemo]
  @Binding var choix: String?
  var surOuvrirFiche: (ServeurDemo) -> Void = { _ in }
  var surAjout: () -> Void = {}

  @State private var pageVisible: String?
  @State private var tacheDebounce: Task<Void, Never>?

  var body: some View {
    VStack(spacing: 8) {
      // 1. Pager horizontal natif iOS 17 avec peek
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(spacing: 12) {
          ForEach(serveurs) { serveur in
            CarteServeurDemo(
              serveur: serveur,
              actif: (pageVisible ?? choix) == serveur.id,
              surToucher: {
                if choix == serveur.id {
                  surOuvrirFiche(serveur)
                } else {
                  choix = serveur.id
                }
              },
              surOuvrirFiche: { surOuvrirFiche(serveur) }
            )
            .id(serveur.id)
            // Peek de 14 pt de chaque côté pour montrer la carte adjacente
            .containerRelativeFrame(.horizontal) { longueur, _ in
              serveurs.count > 1 ? max(longueur - 28, 260) : longueur
            }
          }
        }
        .scrollTargetLayout()
      }
      .scrollTargetBehavior(.viewAligned)
      .scrollPosition(id: $pageVisible)
      .scrollDisabled(serveurs.count < 2)
      .scrollBounceBehavior(serveurs.count > 1 ? .always : .basedOnSize)
      .contentMargins(.horizontal, 14, for: .scrollContent)
      .onChange(of: pageVisible) { _, nouvellePage in
        // Annulée à CHAQUE règlement, y compris un retour au choix courant :
        // sans ça, un aller-retour A→B→A laisse partir la sélection de B
        // 350 ms plus tard, alors que l'écran est revenu sur A.
        tacheDebounce?.cancel()
        guard let nouvellePage, nouvellePage != choix else { return }
        // Option A debouncée : 350 ms pour éviter d'enchaîner 3 reconnexions lors d'un balayage rapide
        tacheDebounce = Task {
          try? await Task.sleep(for: .milliseconds(350))
          guard !Task.isCancelled else { return }
          await MainActor.run {
            choix = nouvellePage
          }
        }
      }
      .onChange(of: choix, initial: true) { _, nouveauChoix in
        if pageVisible != nouveauChoix {
          withAnimation(.easeInOut(duration: 0.25)) {
            pageVisible = nouveauChoix
          }
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Serveurs")
      .accessibilityValue(valeurAccessiblePager)
      .accessibilityAdjustableAction { direction in
        guard serveurs.count > 1 else { return }
        let indexCourant = serveurs.firstIndex(where: { $0.id == (pageVisible ?? choix) }) ?? 0
        let nouvelIndex: Int
        switch direction {
        case .increment:
          nouvelIndex = min(indexCourant + 1, serveurs.count - 1)
        case .decrement:
          nouvelIndex = max(indexCourant - 1, 0)
        @unknown default:
          nouvelIndex = indexCourant
        }
        guard nouvelIndex != indexCourant else { return }
        let cible = serveurs[nouvelIndex].id
        tacheDebounce?.cancel()
        withAnimation {
          choix = cible
        }
      }
      .onDisappear {
        tacheDebounce?.cancel()
      }

      // 2. La barre conserve le bouton « + » même avec une seule machine.
      if !serveurs.isEmpty {
        IndicateursServeursDemo(
          serveurs: serveurs,
          choix: $choix,
          pageVisible: $pageVisible,
          surAjout: surAjout
        )
      }
    }
  }

  private var valeurAccessiblePager: String {
    let index = serveurs.firstIndex(where: { $0.id == (pageVisible ?? choix) }) ?? 0
    let nom = serveurs.first(where: { $0.id == (pageVisible ?? choix) })?.nom ?? ""
    return "\(nom), \(index + 1) sur \(serveurs.count)"
  }
}

/// Carte large d'un serveur : châssis, nom complet, DNS, statut DSH et chevron ouvrant la fiche.
struct CarteServeurDemo: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .title) private var cotePastille: CGFloat = 46

  let serveur: ServeurDemo
  let actif: Bool
  var surToucher: () -> Void = {}
  var surOuvrirFiche: () -> Void = {}

  private var diametrePastille: CGFloat { min(cotePastille, 64) }

  var body: some View {
    Button(action: surToucher) {
      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
              glypheMateriel
              identiteServeur(limiteNom: 3, limiteDNS: 2)
              Spacer(minLength: 4)
              if actif { chevron }
            }
            statutServeur(formeCompacte: false)
          }
        } else {
          HStack(spacing: 14) {
            glypheMateriel
            VStack(alignment: .leading, spacing: 4) {
              identiteServeur(limiteNom: 1, limiteDNS: 1)
              statutServeur(formeCompacte: true)
            }
            Spacer(minLength: 4)
            if actif { chevron }
          }
        }
      }
      .padding(14)
      .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
      .overlay {
        RoundedRectangle(cornerRadius: 16)
          .strokeBorder(
            actif ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.15),
            lineWidth: actif ? 1.5 : 1
          )
      }
      .contentShape(RoundedRectangle(cornerRadius: 16))
    }
    .buttonStyle(StyleCartePressee())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(serveur.nom)
    .accessibilityValue(descriptionAccessible)
    .accessibilityHint(
      actif ? "Ouvre la fiche détaillée de ce serveur" : "Sélectionne ce serveur")
    .accessibilityAction(named: "Ouvrir la fiche") { surOuvrirFiche() }
    .accessibilityAddTraits(actif ? [.isSelected] : [])
  }

  private var glypheMateriel: some View {
    ZStack {
      Circle()
        .fill(
          serveur.enLigne
            ? LinearGradient(
                colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(
                colors: [Color.secondary.opacity(0.4), Color.secondary.opacity(0.2)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .frame(width: diametrePastille, height: diametrePastille)
      Image(systemName: serveur.symbole)
        .font(.system(size: diametrePastille * 0.46, weight: .regular))
        .foregroundStyle(.white)
    }
  }

  private func identiteServeur(limiteNom: Int, limiteDNS: Int) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(serveur.nom)
        .font(.headline)
        .foregroundStyle(Color.primary)
        .lineLimit(limiteNom)
      Text(serveur.nomDNS)
        .font(.caption)
        .foregroundStyle(Color.secondary)
        .lineLimit(limiteDNS)
    }
  }

  private func statutServeur(formeCompacte: Bool) -> some View {
    let teinte = serveur.enLigne ? Color.green : Color.secondary
    return HStack(spacing: 5) {
      Circle().fill(teinte).frame(width: 7, height: 7)
      Text(serveur.enLigne ? "En ligne · DSH actif" : "Hors ligne")
        .font(.caption2.weight(.medium))
        .foregroundStyle(teinte)
      if serveur.estLocal {
        Text("· hôte").font(.caption2).foregroundStyle(.tertiary)
      }
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 2.5)
    .background {
      if formeCompacte {
        Capsule().fill(teinte.opacity(0.12))
      } else {
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(teinte.opacity(0.12))
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private var chevron: some View {
    Image(systemName: "chevron.forward")
      .font(.footnote.weight(.semibold))
      .foregroundStyle(.tertiary)
      .padding(.trailing, 2)
  }

  private var descriptionAccessible: String {
    var elements: [String] = []
    elements.append(serveur.enLigne ? "En ligne, DSH actif" : "Hors ligne")
    if serveur.estLocal { elements.append("hôte interrogé") }
    if actif { elements.append("serveur actif") }
    return elements.joined(separator: ", ")
  }
}

/// Style avec retour d'enfoncement discret pour la carte
private struct StyleCartePressee: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.75 : 1.0)
      .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}

/// Indicateurs de pagination avec icônes de matériel et zone tactile 44×44 pt.
struct IndicateursServeursDemo: View {
  let serveurs: [ServeurDemo]
  @Binding var choix: String?
  @Binding var pageVisible: String?
  var surAjout: () -> Void = {}

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 4) {
        ForEach(Array(serveurs.enumerated()), id: \.element.id) { index, serveur in
          let estActif = (pageVisible ?? choix) == serveur.id
          Button {
            withAnimation(.easeInOut(duration: 0.25)) {
              choix = serveur.id
            }
          } label: {
            ZStack {
              if estActif {
                Capsule()
                  .fill(Color.accentColor.opacity(0.18))
                  .overlay {
                    Capsule().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
                  }
                  .frame(width: 36, height: 24)
              }
              Image(systemName: serveur.symbole)
                .font(.system(size: 13, weight: estActif ? .semibold : .regular))
                .foregroundStyle(estActif ? Color.accentColor : Color.secondary)
            }
            .frame(width: 36, height: 24)
            // Zone tactile minimale Apple 44×44 pt
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(serveur.nom)
          .accessibilityHint("Affiche ce serveur")
          .accessibilityAddTraits(estActif ? [.isSelected] : [])
        }

        // Bouton "+" pour ajouter un serveur avec zone tactile 44×44 pt
        Button {
          surAjout()
        } label: {
          Image(systemName: "plus")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.secondary)
            .frame(width: 24, height: 24)
            .background(Color.secondary.opacity(0.1), in: Circle())
            // Zone tactile minimale Apple 44×44 pt
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ajouter un serveur")
        .accessibilityHint("Ouvre la feuille d'ajout et d'appairage")
      }
      .padding(.horizontal, 16)
    }
    .scrollBounceBehavior(.basedOnSize)
    .padding(.top, 2)
  }
}

/// Feuille de fiche détaillée d'un serveur pour le prototype.
struct VueFicheServeurDemo: View {
  let serveur: ServeurDemo
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack(spacing: 14) {
            Image(systemName: serveur.symbole)
              .font(.system(size: 32))
              .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
              Text(serveur.nom).font(.headline)
              Text(serveur.nomDNS).font(.subheadline).foregroundStyle(.secondary)
            }
          }
        } header: {
          Text("Machine")
        }

        Section {
          HStack {
            Text("État")
            Spacer()
            Text(serveur.enLigne ? "En ligne · DSH joignable" : "Hors ligne")
              .foregroundStyle(serveur.enLigne ? .green : .secondary)
          }
          HStack {
            Text("Type")
            Spacer()
            Text(serveur.estLocal ? "Hôte local" : "Machine distante (Tailscale)")
              .foregroundStyle(.secondary)
          }
        } header: {
          Text("Diagnostic")
        }
      }
      .navigationTitle(serveur.premierMot)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Fermer") { dismiss() }
        }
      }
    }
  }
}

/// Feuille d'ajout / appairage pour le prototype.
struct VueAjoutServeurDemo: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text("Scannez le QR code ou collez un lien d'appairage pour ajouter une nouvelle machine.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        } header: {
          Text("Appairage")
        }
      }
      .navigationTitle("Ajouter un serveur")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Fermer") { dismiss() }
        }
      }
    }
  }
}

// MARK: - 3. Sessions

struct LigneSessionDemo: View {
  let session: SessionDemo

  var body: some View {
    HStack(spacing: 10) {
      Group {
        if let symbole = session.etat.symbole {
          Image(systemName: symbole)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(session.etat.teinte)
        } else {
          Color.clear
        }
      }
      .frame(width: 14)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 5) {
          if session.sousAgent {
            Image(systemName: "arrow.turn.down.right")
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
          Text(session.titre).lineLimit(1)
        }
        HStack(spacing: 8) {
          Text("\(session.evenements) évts")
          Text(session.volume)
          Spacer()
          Text(session.age)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
    }
  }
}

/// Ce qu'on voit quand aucun Mac n'a été trouvé : la cause ET l'action.
struct ListeVide: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Aucun Mac trouvé sur le tailnet", systemImage: "wifi.exclamationmark")
        .font(.callout)
        .foregroundStyle(.orange)
      Text("Saisissez l'adresse d'un Mac : une fois connecté, ce Mac publiera la liste des machines de votre tailnet.")
        .font(.footnote)
        .foregroundStyle(.secondary)
      Button {
      } label: {
        Label("Saisir une adresse", systemImage: "keyboard")
          .font(.callout)
      }
      .buttonStyle(.bordered)
    }
    .padding(.vertical, 2)
  }
}

// MARK: - 4. Recherche ancrée en bas

/// La recherche, en bas et toujours là.
///
/// POURQUOI PAS `.searchable`. La recherche de la barre de navigation se replie
/// sous un geste de défilement : avec cent sessions et des espaces dépliés, on
/// la perd exactement au moment où l'on en a besoin. Ancrée en bas, elle reste
/// sous le pouce — c'est aussi la place qu'elle occupe dans l'interface web.
struct BarreRecherche: View {
  @Binding var texte: String
  @FocusState private var actif: Bool

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField("Rechercher une session, un projet…", text: $texte)
        .textFieldStyle(.plain)
        .focused($actif)
        .submitLabel(.search)
        .autocorrectionDisabled()
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
    .background(.bar)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(.quaternary, lineWidth: 1)
    }
    .padding(.horizontal, 16)
    // La barre FLOTTE au-dessus du contenu, avec de l'air : collée à la
    // dernière ligne, elle se lisait comme une ligne de plus. La bande
    // inférieure est en matière, comme la barre d'outils d'iOS, pour que le
    // contenu qui défile passe visiblement DERRIÈRE elle.
    .padding(.top, 8)
    .padding(.bottom, 10)
    .background(.bar)
  }
}

// MARK: - Feuille de configuration

/// Ce qui n'est pas du usage quotidien descend d'un cran : l'adresse saisie à la
/// main, le jeton, l'oubli du serveur. La page principale reste une page
/// d'appareils et de sessions.
struct FeuilleReglages: View {
  @Binding var serveurChoisi: String?
  @Environment(\.dismiss) private var fermer
  @State private var adresse = ""
  @State private var jeton = ""
  @State private var jetonEnPlace = true

  var body: some View {
    NavigationStack {
      List {
        Section("Serveur") {
          ForEach(DonneesDemo.serveurs) { serveur in
            Button {
              serveurChoisi = serveur.id
            } label: {
              HStack(spacing: 12) {
                Image(systemName: serveur.symbole)
                  .foregroundStyle(serveur.enLigne ? Color.accentColor : Color.secondary)
                  .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                  Text(serveur.nom).foregroundStyle(.primary)
                  Text(serveur.nomDNS)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if serveurChoisi == serveur.id {
                  Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                }
              }
            }
          }
        }

        Section {
          LabeledContent("Adresse") {
            TextField("http://mon-mac.mon-tailnet.ts.net", text: $adresse)
              .multilineTextAlignment(.trailing)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .keyboardType(.URL)
              .font(.callout)
          }
          LabeledContent("Jeton") {
            HStack(spacing: 8) {
              SecureField(jetonEnPlace ? "déjà enregistré" : "jeton d'appareil", text: $jeton)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
              Button {
              } label: {
                Image(systemName: "doc.on.clipboard")
              }
              .buttonStyle(.borderless)
            }
          }
          if jetonEnPlace {
            Label("jeton complet (43 caractères)", systemImage: "checkmark.seal")
              .font(.caption)
              .foregroundStyle(.green)
          }
          HStack(spacing: 12) {
            Button("Tester l'adresse") {}
            Spacer()
            if jetonEnPlace {
              Button("Effacer le jeton", role: .destructive) {}
            }
          }
        } header: {
          Text("Adresse")
        } footer: {
          Text("L'adresse découle du serveur choisi. Ce champ ne sert qu'aux cas que la découverte ne couvre pas.")
        }

        Section {
          Toggle("Chargées en mémoire seulement", isOn: .constant(true))
          Toggle("Suivre l'activité", isOn: .constant(true))
        } footer: {
          Text("« Chargées » veut dire prêtes à être reprises instantanément, pas en train de travailler.")
        }
      }
      .navigationTitle("Réglages")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Terminé") { fermer() }
        }
      }
    }
  }
}

// MARK: - Point d'entrée

@main
struct PrototypeApp: App {
  var ecran: String { ProcessInfo.processInfo.environment["DSH_ECRAN"] ?? "complet" }

  var body: some Scene {
    WindowGroup {
      EcranPrincipal(ecran: ecran)
        .tint(.blue)
    }
  }
}
