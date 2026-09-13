import SwiftUI

/// LA PAGE « AJOUTER UN SERVEUR » — le travail à faire pour qu'un Mac en devienne un.
///
/// POURQUOI CETTE PAGE EXISTE. La vignette « Ajouter » lançait une RECHERCHE. Sur
/// un iPhone où rien n'est encore installé, elle ne pouvait donc rien trouver, et
/// l'utilisateur n'apprenait rien : ni ce qui manque, ni sur quelle machine, ni
/// dans quel ordre. Le propriétaire a demandé qu'elle mène à la page de détail,
/// « pour leur dire les goals à réaliser ».
///
/// C'EST LA MÊME LISTE QUE LA PAGE D'UN SERVEUR, à une différence près : là-bas,
/// on JUGE une machine connue ; ici, on liste le travail pour un Mac qu'on n'a pas
/// encore. Seule la première étape se constate depuis cet appareil, et l'état des
/// autres est « à faire » — un verdict demanderait de connaître la machine.
///
/// Les deux procédures longues (publier le port, installer le plugin) sont
/// PARTAGÉES avec la page d'un serveur : le travail à faire sur le Mac est le
/// même, et deux copies auraient divergé.
struct VueAjoutServeur: View {
  @Bindable var modele: ModeleApp
  /// Ouvre la feuille de saisie d'une adresse — la voie manuelle, quand la
  /// découverte ne suffit pas.
  var surAdresse: () -> Void

  private var etapes: [EtapesServeur.Etape] {
    EtapesServeur.etapesDAjout(tailnetDeLAppareil: modele.tailnetDeLAppareil)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        enTete
        parcours
        actions
      }
      .padding(24)
      .frame(maxWidth: 680, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle("Ajouter un serveur")
  }

  private var enTete: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Ajouter un serveur", systemImage: "plus.square.dashed")
        .font(.title3.weight(.semibold))
      Text(
        "Une machine devient un serveur DSH en quatre étapes. Elles se font dans cet ordre : chacune suppose la précédente."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var parcours: some View {
    // LA MISE EN PAGE EST PARTAGÉE, et la règle du verrou avec : une seule
    // frontière à la fois, les suivantes grisées.
    // OBJECTIFS : ici, on ne constate pas — on liste un travail à faire, dans
    // l'ordre. C'est la seule des deux pages où le verrou a un sens.
    ParcoursDesEtapes(etapes: etapes, mode: .objectifs) { etape in
      methode(pour: etape.numero)
    }
  }

  /// LA MÉTHODE DE CHAQUE ÉTAPE — les commandes se tapent SUR LE MAC CONCERNÉ.
  ///
  /// L'étape 1 concerne CET APPAREIL, les trois autres le Mac À AJOUTER. Le dire
  /// évite de taper sur la mauvaise machine, ce que rien ne signalerait.
  @ViewBuilder
  private func methode(pour numero: Int) -> some View {
    switch numero {
    case 1:
      Text(
        modele.tailscaleInstalle
          ? "Sur cet appareil : ouvrez Tailscale, et connectez-le au tailnet."
          : "Sur cet appareil : installez Tailscale, puis connectez-le au tailnet."
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
        Text("Ou, en ligne de commande :")
          .font(.caption)
          .foregroundStyle(.secondary)
        LigneCommande(commande: "tailscale status")
        LigneCommande(commande: "tailscale up")
      #endif
    case 2:
      Text("Sur cette machine-là : installez Tailscale, connectez-le, puis vérifiez :")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      LigneCommande(commande: "tailscale status")
      Text("Il doit y apparaître en ligne, avec un nom en `.ts.net`.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    case 3:
      DemarchePublicationPort()
    default:
      DemarcheInstallationPlugin()
    }
  }

  /// LES DEUX RECOURS, quand la découverte ne suffit pas.
  ///
  /// La recherche reste offerte : sur iPhone, la vignette « Ajouter » la lançait,
  /// et c'est la seule façon de redemander sa liste à l'hôte. La saisie manuelle
  /// reste le dernier mot — une adresse connue doit toujours pouvoir être tentée.
  private var actions: some View {
    HStack(spacing: 12) {
      if modele.rechercheServeursPossible {
        Button {
          Task { await modele.synchroniserServeurs() }
        } label: {
          Label("Chercher une machine", systemImage: "arrow.clockwise")
        }
        .disabled(modele.synchronisationEnCours)
      }
      Button {
        surAdresse()
      } label: {
        Label("Saisir une adresse", systemImage: "keyboard")
      }
    }
    .font(.callout)
  }
}
