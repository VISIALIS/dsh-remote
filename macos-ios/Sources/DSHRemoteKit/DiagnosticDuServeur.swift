import SwiftUI

/// LE DIAGNOSTIC D'UN SERVEUR — les cinq constats, et la méthode de celui qui bloque.
///
/// POURQUOI IL A QUITTÉ LA FICHE. Deux surfaces le montrent désormais, et une seule
/// doit le dessiner : la FICHE d'un serveur (sa deuxième bande), et la BARRE
/// LATÉRALE quand la machine choisie n'est pas appairée — demande du
/// propriétaire : « si je sélectionne un serveur, s'il n'est pas appairé, le
/// diagnostic s'affiche à la place de l'espace de travail ». Deux copies de ces
/// cinq constats auraient divergé, comme les deux `switch` de méthodes que la
/// refonte venait justement de réunir.
///
/// `serveur == nil` VEUT DIRE « AJOUTER UN SERVEUR » : la liste est alors un travail
/// à faire (`EtapesServeur.etapesDAjout`), pas un verdict — et les deux surfaces
/// partagent ce cas sans le savoir.
struct DiagnosticDuServeur: View {
  @Bindable var modele: ModeleApp
  /// La machine jugée. `nil` = la liste de travail de la page d'ajout.
  let serveur: ServeurMac?
  /// Prévient que la page d'ajout a fini son travail (voir `FicheServeur`).
  var surAppairage: () -> Void = {}

  /// LA PAGE POUSSÉE SE DÉPILE ELLE-MÊME (iPhone, iPad).
  ///
  /// Déclaré ICI, et non hérité de la fiche : c'est cette vue qui appelle
  /// `depiler`, depuis qu'elle porte l'appairage. Sur une vue non présentée,
  /// `dismiss` ne fait rien — et dans la barre latérale, `estAjout` est toujours
  /// faux, donc `depiler` n'est jamais appelé. Constaté en construisant pour iOS :
  /// macOS compilait, parce que l'appel est sous `#if os(iOS)`.
  @Environment(\.dismiss) private var depiler

  private var estAjout: Bool { serveur == nil }

  /// COMMENT LIRE LES ÉTAPES : ce qu'on constate, ou ce qu'il reste à faire.
  ///
  /// Les deux cas vivent dans `EtapesServeur` (`Mode`) : ce qu'ils décident — ce
  /// qui est verrouillé, donc ce qui est ATTEIGNABLE — est une règle, et elle est
  /// éprouvée là-bas.
  private var mode: EtapesServeur.Mode { estAjout ? .objectifs : .diagnostic }

  /// Les étapes, recalculées à chaque rendu : la sonde peut rendre son verdict
  /// entre deux affichages. La fabrique est dans le MODÈLE, pour que la fiche et la
  /// barre latérale ne puissent pas diverger sur ce qu'elles montrent.
  private var etapes: [EtapesServeur.Etape] { modele.etapes(pour: serveur) }

  // MARK: - Les cinq constats

  var body: some View {
    // PAS DE TITRE, ET C'EST VOULU. « Diagnostic », « Le parcours », « Les étapes »
    // : sur la fiche, la conclusion est juste au-dessus ; dans la barre latérale,
    // c'est l'en-tête de section qui le nomme. Un titre de plus serait un mot de
    // plus à parcourir.
    ParcoursDesEtapes(etapes: etapes, mode: mode) { etape in
      methode(pour: etape)
    }
  }

  // MARK: - Les méthodes, une par étape

  /// LA MÉTHODE POUR FRANCHIR L'ÉTAPE — ou pour la VÉRIFIER quand on ne sait pas.
  ///
  /// ELLE VIT ICI, UNE SEULE FOIS. Les deux pages en avaient chacune un `switch`,
  /// et les deux avaient déjà divergé sur les deux premières étapes : mêmes gestes,
  /// deux textes, deux ordres de commandes. L'utilisateur, lui, compare.
  @ViewBuilder
  private func methode(pour etape: EtapesServeur.Etape) -> some View {
    switch etape.numero {
    case 1:
      // TAILSCALE SUR CET APPAREIL. Il n'y a pas de commande à copier sur un
      // iPhone : on dit quoi faire, et le bouton fait ce que la carte fait déjà
      // — ouvrir l'application, ou son magasin si elle manque.
      methodeTailscale
    case 2:
      // LA MACHINE VISÉE, pas cet appareil-ci : ces commandes se tapent SUR ELLE.
      methodeVisibilite(connue: etape.etat == .aFaire)
    case 3:
      if etape.etat == .aFaire {
        DemarchePublicationPort()
      } else {
        T("Vérifiez sur cette machine ce qui est publié :")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        LigneCommande(commande: "tailscale serve status")
      }
    case 4:
      // L'installation du plugin : la démarche complète, avec le bloc à copier.
      DemarcheInstallationPlugin()
    default:
      methodeAppairage
    }
  }

  @ViewBuilder
  private var methodeTailscale: some View {
    Text(
      modele.tailscaleInstalle
        ? L("Ouvrez Tailscale sur cet appareil, et connectez-le au tailnet.")
        : L("Installez Tailscale sur cet appareil, puis connectez-le au tailnet.")
    )
    .font(.caption)
    .foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
    Button {
      if !modele.ouvrirTailscale() {
        modele.signaler(L("Tailscale n'a pas pu être ouvert sur cet appareil."))
      }
    } label: {
      Label(
        modele.tailscaleInstalle ? L("Ouvrir Tailscale") : L("Installer Tailscale"),
        systemImage: "arrow.up.forward.app")
    }
    .buttonStyle(.borderless)
    .font(.caption)
    #if os(macOS)
      // SUR macOS, l'appareil qui affiche la page est aussi celui qui a le CLI :
      // la commande est le moyen le plus direct, et elle se copie.
      T("Ou, en ligne de commande :")
        .font(.caption)
        .foregroundStyle(.secondary)
      LigneCommande(commande: "tailscale status")
      LigneCommande(commande: "tailscale up")
    #endif
  }

  /// La visibilité de la machine VISÉE — et le texte suit ce qu'on SAIT.
  ///
  /// Quand l'état est inconnu, on ne donne que la commande de constat : envoyer
  /// publier un port dont on ignore s'il l'est déjà ferait douter de tout.
  @ViewBuilder
  private func methodeVisibilite(connue: Bool) -> some View {
    if connue {
      T("Allumez cette machine-là, et vérifiez que Tailscale y est connecté :")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      LigneCommande(commande: "tailscale status")
      T("S'il n'y est pas connecté :")
        .font(.caption)
        .foregroundStyle(.secondary)
      LigneCommande(commande: "tailscale up")
    } else {
      T("Vérifiez l'état du tailnet, sur cette machine-là ou sur une autre :")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      LigneCommande(commande: "tailscale status")
    }
  }

  /// L'APPAIRAGE — la cinquième étape, et le seul geste qui se fait des deux côtés.
  ///
  /// POURQUOI CE TEXTE EST COURT. Il dit où est le panneau — c'est la seule chose
  /// que l'application ne peut pas montrer, parce qu'il vit sur l'AUTRE machine —
  /// et il laisse les boutons faire le reste. Le reste, précisément : ce que
  /// contient la charge utile, sa durée de vie, ce que l'hôte enregistre, est
  /// écrit dans le README et n'a jamais aidé personne à appuyer.
  ///
  /// LE REFUS A SON MOT, ET IL EN A BESOIN. Un jeton rangé mais refusé n'est pas
  /// « pas encore appairé » : c'est le jeton d'une AUTRE machine, et le geste est
  /// le même — appairer à nouveau —, mais la raison, elle, se dit.
  @ViewBuilder
  private var methodeAppairage: some View {
    BoutonsAppairage(modele: modele, surSucces: apresAppairage, prominent: estAjout)

    T("Sur le Mac : le bouton « DSH Remote », en bas de la barre latérale — il ouvre un QR code et son texte, valables deux minutes.")
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

    if let serveur, modele.etatAppairage(pour: serveur) == .refuse {
      Label {
        T("Le jeton rangé a été refusé : c'est celui d'une autre machine. Appairez à nouveau pour le remplacer.")
      } icon: {
        Image(systemName: "key.slash")
      }
      .font(.caption)
      .foregroundStyle(EtatVisuel.attention.couleur)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// APRÈS UN APPAIRAGE RÉUSSI — LA PAGE D'AJOUT S'EFFACE.
  ///
  /// POURQUOI ELLE, ET PAS LA PAGE D'UNE MACHINE. Sur la fiche d'une machine qu'on
  /// vient d'appairer, il y a encore à lire : le verdict change, les cinq constats
  /// passent au vert, et la page se met à jour TOUTE SEULE (le modèle est
  /// observé). La page d'ajout, elle, a fini son travail : elle n'existe que pour
  /// amener une machine dans la liste, et la garder à l'écran après coup laissait
  /// l'utilisateur devant un écran qui ne bougeait plus — le défaut signalé.
  ///
  /// ELLE PART AVANT LA CONNEXION, et c'est voulu : `BoutonsAppairage` appelle ce
  /// rappel entre l'échange du code et `connecter()`. L'écran se libère donc
  /// pendant que la connexion se fait, et la liste des sessions arrive ensuite
  /// dans la barre latérale, sans que personne ait à attendre sur une page morte.
  private func apresAppairage() {
    guard estAjout else { return }
    surAppairage()
    // `depiler` N'EST APPELÉ QUE SUR iOS, et c'est délibéré : c'est la seule
    // plateforme où la page est POUSSÉE. Sur macOS, elle occupe la colonne de
    // détail, et `dismiss` y viserait la fenêtre — pas la page. Le geste qui
    // convient là-bas est celui de l'appelant (`surAppairage`), qui change ce
    // qu'on regarde au lieu de fermer quelque chose.
    #if os(iOS)
      depiler()
    #endif
  }
}
