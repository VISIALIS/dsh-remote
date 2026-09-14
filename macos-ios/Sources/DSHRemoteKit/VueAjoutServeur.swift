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
        sectionAppareil
        actions
        sectionHote
      }
      .padding(24)
      .frame(maxWidth: 680, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle(T("Ajouter un serveur"))
  }

  private var enTete: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label { T("Ajouter un serveur") } icon: { Image(systemName: "plus.square.dashed") }
        .font(.title3.weight(.semibold))
      // LA PHRASE QUI SÉPARE LES DEUX MONDES, et c'est la correction demandée par
      // l'usage : une seule chose se fait ICI, le reste se fait sur le Mac — et
      // l'application constate le reste toute seule, sans qu'on ait à l'enseigner.
      T("Sur cet appareil, une seule chose est à faire : que Tailscale soit connecté. Tout le reste se passe sur le Mac qui héberge DSH — et l'application le vérifie toute seule, dès qu'une machine répond.")
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// CE QUE CET APPAREIL DOIT FAIRE — une étape, et le geste.
  ///
  /// POURQUOI LES DEUX SONT DANS LE MÊME BLOC. « Vérifier Tailscale » et « prendre
  /// le QR code » sont les DEUX SEULES choses qui se passent ici : les séparer par
  /// des titres les ferait passer pour un parcours, alors que le second n'attend
  /// rien du premier (le QR code se lit même si Tailscale est arrêté — c'est la
  /// CONNEXION qui échouera, et elle le dira).
  private var sectionAppareil: some View {
    VStack(alignment: .leading, spacing: 12) {
      ParcoursDesEtapes(etapes: EtapesServeur.deLAppareil(etapes), mode: .objectifs) { etape in
        methode(pour: etape.numero)
      }

      BoutonsAppairage(modele: modele, prominent: true)

      T("Le QR code porte l'adresse du Mac et un code à usage unique : le scan (ou le collage) remplit les deux champs, puis se connecte.")
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// LE TRAVAIL DU MAC — replié, et présenté pour ce qu'il est.
  ///
  /// POURQUOI IL N'EST PLUS AU MÊME NIVEAU QU'AVANT. Ces trois étapes ne se font
  /// pas ici, et l'application les CONSTATE : dès qu'une machine répond, la page
  /// de cette machine dit laquelle manque (« publier le port », « installer le
  /// plugin »). Les enseigner d'abord faisait apprendre au remote un travail qui
  /// n'est pas le sien, et noyait les deux seules choses qu'il a à faire.
  ///
  /// ELLES RESTENT ÉCRITES, repliées : on est souvent devant le Mac quand on
  /// cherche pourquoi rien ne répond, et ces commandes-là sont exactement ce
  /// qu'il faut alors.
  private var sectionHote: some View {
    DisclosureGroup {
      VStack(alignment: .leading, spacing: 10) {
        ParcoursDesEtapes(etapes: EtapesServeur.deLHote(etapes), mode: .objectifs) { etape in
          methode(pour: etape.numero)
        }
        T("Ces trois points se vérifient aussi tout seuls : ouvrez la page de la machine, et le diagnostic dit lequel manque.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.top, 8)
    } label: {
      Label { T("Si le Mac n'est pas encore prêt") } icon: { Image(systemName: "desktopcomputer") }
        .font(.callout.weight(.medium))
    }
  }

  /// LES DEUX RECOURS, quand la découverte ne suffit pas.
  ///
  /// La recherche reste offerte : sur iPhone, la vignette « Ajouter » la lançait,
  /// et c'est la seule façon de redemander sa liste à l'hôte. La saisie manuelle
  /// reste le dernier mot — une adresse connue doit toujours pouvoir être tentée.
  /// LA MÉTHODE DE CHAQUE ÉTAPE — les commandes se tapent SUR LE MAC CONCERNÉ.
  ///
  /// L'étape 1 concerne CET APPAREIL, les trois autres le Mac À AJOUTER. Le dire
  /// évite de taper sur la mauvaise machine, ce que rien ne signalerait.
  /// Désormais, `Responsable` porte cette distinction dans le MODÈLE : la page
  /// n'a plus à la redire, elle s'en sert pour séparer les deux blocs.
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
        T("Ou, en ligne de commande :")
          .font(.caption)
          .foregroundStyle(.secondary)
        LigneCommande(commande: "tailscale status")
        LigneCommande(commande: "tailscale up")
      #endif
    case 2:
      T("Sur cette machine-là : installez Tailscale, connectez-le, puis vérifiez :")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      LigneCommande(commande: "tailscale status")
      T("Il doit y apparaître en ligne, avec un nom en `.ts.net`.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    case 3:
      DemarchePublicationPort()
    default:
      DemarcheInstallationPlugin()
    }
  }

  /// LES ACTIONS, DANS L'ORDRE OÙ ELLES SERVENT — et l'appairage EN PREMIER.
  ///
  /// POURQUOI L'APPAIRAGE EST ICI, ET PAS SEULEMENT DANS LA FEUILLE « ADRESSE ».
  /// C'est la correction d'un défaut d'usage : le scanner vivait dans la feuille
  /// « Adresse », sous un bouton qui promettait « Saisir une adresse ». Un appareil
  /// DÉJÀ configuré n'a aucune raison d'ouvrir cette feuille — et son
  /// utilisateur a donc conclu, à juste titre, que l'application n'avait « pas de
  /// système avec un QR code ». Le geste est désormais là où l'on ajoute un
  /// serveur, et son libellé le nomme.
  ///
  /// POURQUOI EMPILÉES ET NON ALIGNÉES : trois libellés côte à côte ne tiennent
  /// pas sur un iPhone — même mesure que `ServeursVides`, même correction.
  private var actions: some View {
    VStack(alignment: .leading, spacing: 8) {
      // PAS DE BOUTON D'APPAIRAGE ICI : il est dans le bloc de l'appareil, juste
      // au-dessus — et l'avoir aux DEUX endroits l'affichait deux fois, constaté
      // sur capture. Ces deux recours-ci ne servent que lorsque le geste n'a pas
      // suffi : aucun Mac à portée, ou une adresse connue à saisir.
      if modele.rechercheServeursPossible {
        Button {
          Task { await modele.synchroniserServeurs() }
        } label: {
          Label { T("Chercher une machine") } icon: { Image(systemName: "arrow.clockwise") }
        }
        .disabled(modele.synchronisationEnCours)
      }
      Button {
        surAdresse()
      } label: {
        Label { T("Saisir une adresse") } icon: { Image(systemName: "keyboard") }
      }
    }
    .font(.callout)
  }
}
