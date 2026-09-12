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

  /// Les états de la maquette, dans l'ordre de l'appui sur le titre.
  static let ecrans = ["complet", "carte", "sans-mac", "reglages"]

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
    ecran == "sans-mac" ? [] : DonneesDemo.serveurs
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
            CarrouselServeurs(serveurs: serveurs, choix: $serveurChoisi)
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
      .safeAreaInset(edge: .bottom, spacing: 0) {
        BarreRecherche(texte: $recherche)
      }
    }
  }

  /// Nom lisible de l'écran courant, affiché sous le titre.
  private var libelleEcran: String {
    switch ecran {
    case "carte": return "tailscale à installer"
    case "sans-mac": return "aucun Mac"
    case "reglages": return "réglages"
    default: return "connecté"
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
/// Le défilement horizontal est `ScrollView` et non `TabView` : avec quatre Macs
/// ou plus, un carrousel paginé cacherait la moitié des machines derrière un
/// geste que rien n'annonce.
struct CarrouselServeurs: View {
  let serveurs: [ServeurDemo]
  @Binding var choix: String?

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 16) {
        ForEach(serveurs) { serveur in
          Button {
            choix = serveur.id
          } label: {
            IconeServeur(serveur: serveur, choisi: choix == serveur.id)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            "\(serveur.nom), \(serveur.enLigne ? "en ligne" : "hors ligne")\(serveur.estLocal ? ", hôte interrogé" : "")")
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
  let serveur: ServeurDemo
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
        // propres bords — mesuré à l'écran, le serveur choisi ne se distinguait
        // pas des autres. Le coin haut-gauche est libre : la pastille d'état
        // occupe le coin bas-droit.
        if choisi {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 19))
            .foregroundStyle(.white, Color.accentColor)
            .offset(x: -29, y: -29)
        }
      }
      .frame(width: 62, height: 62)
      .overlay(alignment: .bottomTrailing) {
        // Pastille d'état : verte en ligne, grise hors ligne. Elle est ce qui
        // distingue « je peux travailler » de « machine éteinte ».
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
      // « hôte interrogé » : la seule mention qui vient de l'hôte, et non du nom.
      // `opacity(0)` et non une espace : la place est réservée sans qu'un blanc
      // soit rendu, ce qui garde les icônes alignées entre elles.
      Text("hôte")
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
        .opacity(serveur.estLocal ? 1 : 0)
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
