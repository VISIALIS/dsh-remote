import DSHRemoteKit
import SwiftUI

/// La page d'un serveur : ce qu'il est, ce qu'on peut faire avec lui, et quoi
/// faire quand il ne publie rien.
///
/// POURQUOI CETTE PAGE EXISTE, ET CE QU'ELLE DÉPLACE. Le panneau latéral portait
/// l'état des machines **et** le diagnostic complet, jusqu'aux commandes à
/// recopier sur l'autre Mac. Résultat : une colonne encombrée, où le message le
/// plus long prenait la place des sessions — il fallait faire défiler pour voir
/// son propre travail.
///
/// Le diagnostic appartient à la MACHINE : il vit donc sur SA page, qu'on ouvre
/// en touchant son icône. Le panneau latéral garde ce qui se lit d'un coup
/// d'œil : la pastille, la légende, le nom.
struct VueServeur: View {
  @Bindable var modele: ModeleApp
  /// La machine affichée, résolue à chaque rendu par `VuePrincipale`.
  let serveur: ServeurMac
  var ouvrirReglages: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        enTete
        adresseEtActions
        session
        // La bascule de serveur se DIT : changer la machine de l'utilisateur
        // sans le prévenir serait une substitution silencieuse. L'avis est ici
        // plutôt qu'à gauche : il concerne une machine, et c'est sa page.
        if let ajuste = modele.choixAjuste {
          Label(ajuste, systemImage: "arrow.triangle.swap")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        // LE PAVÉ TECHNIQUE reste disponible : c'est le seul diagnostic quand
        // aucune cause n'est connue, et il est aussi écrit dans `diagnostic.json`.
        paveTechnique
        parcours
      }
      .padding(24)
      .frame(maxWidth: 680, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle(serveur.nom)
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
  }

  // MARK: - En-tête

  private var enTete: some View {
    HStack(alignment: .center, spacing: 14) {
      Image(systemName: serveur.symbole)
        .font(.system(size: 34))
        .foregroundStyle(serveur.enLigne ? Color.accentColor : Color.secondary)
        .frame(width: 46)
      VStack(alignment: .leading, spacing: 3) {
        Text(serveur.nom).font(.title2)
        Text(etatLisible)
          .font(.callout)
          .foregroundStyle(serveur.enLigne ? Color.green : Color.secondary)
      }
      Spacer()
      if modele.serveurChoisi == serveur {
        Label("serveur courant", systemImage: "checkmark.circle.fill")
          .font(.caption)
          .foregroundStyle(Color.accentColor)
      }
    }
  }

  /// L'état en clair, avec ce qui est SU et ce qui ne l'est pas.
  ///
  /// « Vérification… » n'est pas une décoration : tant que la sonde n'a pas
  /// rendu son verdict, on ne sait pas si la machine sert DSH, et le dire est
  /// plus honnête que de laisser croire à un « non ».
  private var etatLisible: String {
    guard serveur.enLigne else { return "hors ligne sur le tailnet" }
    switch modele.sertDsh(serveur) {
    case true: return serveur.estLocal ? "en ligne · DSH · hôte interrogé" : "en ligne · DSH"
    case false: return "en ligne · pas de DSH"
    case nil: return "en ligne · vérification en cours"
    }
  }

  // MARK: - Adresse et actions

  private var adresseEtActions: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Adresse")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(serveur.adresse)
        .font(.callout.monospaced())
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 12) {
        Button {
          Task { await modele.choisirEtConnecter(serveur) }
        } label: {
          Label("Se connecter", systemImage: "bolt.horizontal")
        }
        .buttonStyle(.borderedProminent)
        .disabled(modele.enChargement)

        Button {
          Task { await modele.testerAdresse() }
        } label: {
          Label("Tester", systemImage: "stethoscope")
        }
        .disabled(modele.enChargement)

        if modele.enChargement { ProgressView().controlSize(.small) }
      }

      jeton
    }
  }

  /// Le suivi et le filtre de CETTE machine.
  ///
  /// POURQUOI ICI ET NON DANS LES RÉGLAGES GÉNÉRAUX — le propriétaire l'a
  /// demandé, et il a raison : les deux portent sur la connexion à une machine.
  /// Le suivi décide si l'on interroge CE serveur toutes les trois secondes ; le
  /// filtre décide ce qu'on affiche de SA liste. Les garder globaux faisait
  /// hériter chaque serveur des choix faits pour le précédent.
  ///
  /// La note dit aussi ce qui se passe si la machine n'est pas celle à laquelle
  /// on est connecté : le réglage est enregistré, et s'appliquera à la
  /// connexion. Un interrupteur doit dire quand il agit.
  private var session: some View {
    VStack(alignment: .leading, spacing: 10) {
      Toggle(
        "Suivre l'activité",
        isOn: Binding(
          get: { modele.preferences(pour: serveur.adresse).suivi },
          set: { actif in modele.definirPreferences(pour: serveur.adresse) { $0.suivi = actif } }))
      Toggle(
        "Chargées en mémoire seulement",
        isOn: Binding(
          get: { modele.preferences(pour: serveur.adresse).chargeesSeulement },
          set: { actif in
            modele.definirPreferences(pour: serveur.adresse) { $0.chargeesSeulement = actif }
          }))

      Text(
        modele.serveurVise?.id == serveur.id
          ? "Ces deux réglages valent pour cet hôte, et s'appliquent maintenant : c'est le serveur connecté. « Chargées » veut dire prêtes à être reprises instantanément, pas en train de travailler."
          : "Ces deux réglages valent pour cet hôte et seront appliqués quand vous vous y connecterez."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// Le jeton d'appareil, SUR LA PAGE DE LA MACHINE.
  ///
  /// POURQUOI ICI, ET NON DANS LES RÉGLAGES GÉNÉRAUX — mesuré. Le jeton est tiré
  /// par CHAQUE hôte et rangé dans son coffre : deux Macs qui hébergent le plugin
  /// ont deux jetons distincts, et celui d'une machine ne vaut pas pour une
  /// autre. Un réglage « général » qui ne vaut que pour un hôte serait un
  /// mensonge d'endroit. C'est aussi la première chose qu'on soupçonne quand une
  /// machine répond mais refuse — et l'avoir soupçonné à tort a déjà coûté du
  /// temps.
  private var jeton: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Jeton d'appareil de cet hôte")
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack(spacing: 8) {
        SecureField(
          modele.jetonDisponible ? "déjà enregistré — saisir pour remplacer" : "jeton d'appareil",
          // Guardé dès la frappe POUR CET HÔTE : un jeton collé puis abandonné
          // serait perdu, alors qu'il vient d'être recopié.
          text: Binding(get: { modele.jetonSaisi }, set: { modele.definirJeton($0) })
        )
        .font(.callout.monospaced())
        .lineLimit(1)
        .autocorrectionDisabled()
        .layoutPriority(1)
        #if os(iOS)
          .textInputAutocapitalization(.never)
        #endif
        Button {
          modele.collerLeJeton()
        } label: {
          Image(systemName: "doc.on.clipboard")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Coller le jeton depuis le presse-papier")
        if modele.jetonDisponible {
          Button {
            modele.effacerJeton()
          } label: {
            Image(systemName: "xmark.circle")
          }
          .buttonStyle(.borderless)
          .accessibilityLabel("Effacer le jeton")
        }
      }
      Label(
        modele.jetonBienForme
          ? "jeton complet (43 caractères)"
          : "jeton incomplet : \(modele.longueurJeton) caractères au lieu de 43",
        systemImage: modele.jetonBienForme ? "checkmark.seal" : "exclamationmark.triangle"
      )
      .font(.caption)
      .foregroundStyle(modele.jetonBienForme ? Color.green : Color.orange)

      // Un `401` propose l'action qui RÉPARE, à portée de pouce : le champ est
      // juste au-dessus. Le rappel n'apparaît que pour cette cause-là — une
      // adresse injoignable ne se règle pas ici.
      if modele.jetonRefuse {
        Label(
          "Le service a refusé ce jeton. Collez celui de CET hôte : chaque machine a le sien.",
          systemImage: "key"
        )
        .font(.caption)
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
      }

      Text("Il s'affiche une seule fois, dans la sortie du harness, au premier chargement du plugin sur cette machine. Il n'est jamais renvoyé par une route.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Le parcours

  /// La cause, POUR CETTE MACHINE.
  private var cause: CauseSansDsh? { modele.causeSansDsh(serveur) }

  /// LE PAVÉ TECHNIQUE — l'erreur brute de la connexion en cours.
  ///
  /// POURQUOI IL RESTE. Quand la cause est connue (port fermé, plugin absent), le
  /// parcours dit tout en une ligne ET répare : le pavé (`NSURLErrorDomain …
  /// CAUSE: rien n'écoute sur cet hôte et ce port`) ne fait que le répéter en
  /// charabia. Quand aucune cause n'est connue, en revanche, il est le SEUL
  /// diagnostic disponible — et il est aussi écrit dans `diagnostic.json`.
  @ViewBuilder
  private var paveTechnique: some View {
    if cause == nil, let erreur = modele.erreur, modele.serveurVise?.id == serveur.id {
      Label(erreur, systemImage: "exclamationmark.triangle")
        .foregroundStyle(.red)
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// LE PARCOURS : trois étapes, et la méthode pour celles qui restent.
  ///
  /// POURQUOI UN PARCOURS PLUTÔT QU'UN DIAGNOSTIC. Le bloc précédent disait
  /// « voici l'erreur, voici le remède » — utile quand on sait ce qu'on cherche,
  /// inutile quand on ne sait pas OÙ on en est. Le propriétaire a demandé une
  /// « ligne de goal à franchir » : trois étapes dans l'ordre où elles se
  /// franchissent, chacune avec sa méthode.
  ///
  /// L'ÉTAPE EN COURS EST CELLE QUI DÉBLOQUE LES SUIVANTES : inutile de publier
  /// un port sur un Mac éteint, inutile d'installer un plugin dont le port sera
  /// fermé. Le calcul des états vit dans `EtapesServeur`, où il est éprouvé.
  private var parcours: some View {
    let etapes = EtapesServeur.etapes(
      tailnetDeLAppareil: modele.tailnetDeLAppareil,
      enLigne: serveur.enLigne,
      sertDsh: modele.sertDsh(serveur),
      cause: cause)

    return VStack(alignment: .leading, spacing: 14) {
      ForEach(etapes, id: \.numero) { etape in
        etapeAffichee(etape)
      }
    }
    .padding(12)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
  }

  @ViewBuilder
  private func etapeAffichee(_ etape: EtapesServeur.Etape) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Image(systemName: symboleDeLEtat(etape.etat))
          .foregroundStyle(couleurDeLEtat(etape.etat))
        Text("\(etape.numero). \(etape.titre)")
          .font(.callout.weight(etape.etat == .franchie ? .regular : .medium))
          .foregroundStyle(etape.etat == .franchie ? Color.secondary : Color.primary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 4)
        if etape.etat == .inconnue {
          Text("à vérifier")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      // ON N'EXPLIQUE ET N'OUTILLE QUE CE QUI RESTE À FAIRE. Une étape franchie
      // n'a pas besoin de mode d'emploi, et l'afficher noierait celle qui bloque.
      if etape.etat != .franchie {
        Text(etape.explication)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        methodologie(pour: etape.numero, connue: etape.etat == .aFaire)
      }
    }
  }

  private func symboleDeLEtat(_ etat: EtapesServeur.Etat) -> String {
    switch etat {
    case .franchie: return "checkmark.circle.fill"
    case .aFaire: return "circle"
    case .inconnue: return "questionmark.circle"
    }
  }

  private func couleurDeLEtat(_ etat: EtapesServeur.Etat) -> Color {
    switch etat {
    case .franchie: return .green
    case .aFaire: return .orange
    case .inconnue: return .secondary
    }
  }

  /// LA MÉTHODE POUR FRANCHIR L'ÉTAPE — ou pour la VÉRIFIER quand on ne sait pas.
  ///
  /// Quand l'état est inconnu, on ne donne que la commande de constat : envoyer
  /// publier un port dont on ignore s'il l'est déjà ferait douter de tout.
  @ViewBuilder
  private func methodologie(pour numero: Int, connue: Bool) -> some View {
    switch numero {
    case 1:
      // TAILSCALE SUR CET APPAREIL. Il n'y a pas de commande à copier sur un
      // iPhone : on dit quoi faire, et le bouton fait ce que la carte fait déjà
      // — ouvrir l'application, ou son magasin si elle manque.
      Text(
        modele.tailscaleInstalle
          ? "Ouvrez Tailscale sur cet appareil, et connectez-le au tailnet."
          : "Installez Tailscale sur cet appareil, puis connectez-le au tailnet."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      Button {
        if !modele.ouvrirTailscale() {
          modele.signaler("Tailscale n'a pas pu être ouvert sur cet appareil.")
        }
      } label: {
        Label(
          modele.tailscaleInstalle ? "Ouvrir Tailscale" : "Installer Tailscale",
          systemImage: "arrow.up.forward.app")
      }
      .buttonStyle(.borderless)
      .font(.caption)
      #if os(macOS)
        // SUR macOS, l'appareil qui affiche la page est aussi celui qui a le CLI :
        // la commande est le moyen le plus direct, et elle se copie.
        Text("Ou, en ligne de commande :")
          .font(.caption)
          .foregroundStyle(.secondary)
        LigneCommande(commande: "tailscale status")
        LigneCommande(commande: "tailscale up")
      #endif
    case 2:
      // LA MACHINE VISÉE, pas cet appareil-ci : ces commandes se tapent SUR ELLE.
      if connue {
        Text("Allumez ce Mac-là, et vérifiez que Tailscale y est connecté :")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        LigneCommande(commande: "tailscale status")
        Text("S'il n'y est pas connecté :")
          .font(.caption)
          .foregroundStyle(.secondary)
        LigneCommande(commande: "tailscale up")
      } else {
        Text("Vérifiez l'état du tailnet, sur ce Mac-là ou sur un autre :")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        LigneCommande(commande: "tailscale status")
      }
    case 3:
      if connue {
        DemarchePublicationPort()
      } else {
        Text("Vérifiez sur ce Mac ce qui est publié :")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        LigneCommande(commande: "tailscale serve status")
      }
    default:
      // L'installation du plugin : la démarche complète, avec le bloc à copier.
      DemarcheInstallationPlugin()
    }
  }
}
