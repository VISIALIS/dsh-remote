import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

/// Réglages : ce qui concerne l'APPLICATION, et non une machine.
///
/// POURQUOI CETTE FEUILLE EXISTE. L'adresse, le jeton, le test d'adresse et les
/// filtres occupaient plus de la moitié de la hauteur utile de la page
/// principale — pour des gestes qu'on fait une fois, puis plus jamais. La page
/// principale est redevenue ce qu'elle doit être : des appareils et des
/// sessions. Le reste descend d'un cran.
///
/// CE QUI N'A PAS LE DROIT D'ÊTRE PERDU EN CHEMIN. Chaque élément déplacé sur la
/// page d'une machine corrigeait un défaut RÉEL, constaté sur l'iPhone :
///
///   - le champ du jeton est TOUJOURS visible. Il était auparavant masqué dès
///     qu'un jeton était présent, c'est-à-dire dès le PREMIER caractère saisi :
///     le champ disparaissait sous les doigts de l'utilisateur, qui ne pouvait
///     jamais terminer sa saisie ;
///   - le compte de caractères est affiché en clair. Un champ de 43 caractères
///     affiche des puces : sans ce compte, un jeton tronqué est indiscernable
///     d'un jeton complet, et le `401` qui suit accuse le serveur à tort ;
///   - le bouton « Coller » existe. 43 caractères en base64url, recopiés depuis
///     un terminal, ne se tapent pas à la main sur un clavier de téléphone ;
///   - « Tester l'adresse » dit ce qu'il a trouvé. C'est l'action qui a du sens
///     quand on a saisi une adresse à la main, et elle nomme son résultat —
///     « rien ne s'est passé » ne doit jamais être une réponse possible.
///
/// CET ÉCRAN A LONGTEMPS ÉTÉ VIDE, ET C'ÉTAIT UN DÉFAUT D'INTERFACE. Tout ce qui
/// dépendait d'une machine étant descendu sur SA page, il ne restait ici qu'une
/// phrase expliquant qu'il n'y avait rien — derrière un bouton de barre d'outils
/// qui, lui, existait. Un écran qu'on ouvre pour lire qu'il est vide déçoit à
/// chaque fois. Il porte donc maintenant ce qui est GLOBAL et vérifiable : l'état
/// de cet appareil, l'emplacement du diagnostic, et les versions.
public struct FeuilleReglages: View {
  /// LE MODÈLE EST LU, PAS MODIFIÉ PAR LIAISON : cet écran ne possède aucun champ
  /// de saisie — il CONSTATE (état de l'appareil, chemin du diagnostic, versions)
  /// et propose deux actions. Un `@Bindable` n'y servirait à rien.
  let modele: ModeleApp
  @Environment(\.dismiss) private var fermer

  /// LA CONFIRMATION ET LE COMPTE RENDU — deux états LOCAUX à cette feuille.
  ///
  /// POURQUOI LOCAUX. Ils ne concernent que ce qu'on vient de faire ici : ni le
  /// modèle, ni une autre vue n'ont besoin de savoir qu'une confirmation est
  /// ouverte. Le compte rendu, lui, est gardé pour que l'utilisateur puisse le
  /// RELIRE — un message qui disparaît au premier rendu ne sert à rien.
  @State private var confirmationOuverte = false
  @State private var rapport: String?

  /// L'ENTRÉE PUBLIQUE EXISTE POUR LA SCÈNE `Settings` DE macOS.
  ///
  /// L'initialiseur membre à membre d'une structure publique est interne : sans
  /// celui-ci, le module de l'application macOS — qui déclare la scène — ne
  /// pourrait pas construire cet écran.
  public init(modele: ModeleApp) {
    self.modele = modele
  }

  public var body: some View {
    NavigationStack {
      Form {
        appareil
        alertes
        diagnostic
        reinitialiser
        aPropos
      }
      .navigationTitle(T("Réglages"))
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        #if os(iOS)
          ToolbarItem(placement: .confirmationAction) {
            Button(L("Terminé")) { fermer() }
          }
        #endif
      }
      .task {
        // L'ÉTAT EST RELU EN ARRIVANT, et non supposé : il a pu changer depuis le
        // lancement — Tailscale s'installe, se connecte, se coupe. Un écran de
        // diagnostic qui montrerait un constat d'il y a une heure serait un
        // mensonge par omission.
        let _ = modele.relireEtatTailscale()
      }
    }
    #if os(macOS)
      // ── LA FEUILLE AVAIT LA LARGEUR DE SON CONTENU LE PLUS ÉTROIT ──────────
      //
      // POURQUOI CE CADRE EXISTE, ET POURQUOI IL EST LARGE. Sans lui, macOS
      // dimensionne la feuille sur la largeur IDÉALE du `Form` — de l'ordre de
      // 400 points — et tout ce qui dépasse est TRONQUÉ À DROITE. Constaté sur
      // la capture du propriétaire : la phrase d'aide de l'adresse s'arrêtait au
      // milieu d'un mot, celle des sessions aussi, et l'URL du tailnet était
      // coupée. Ce n'était pas un problème de texte, mais de place.
      //
      // 560 points est la largeur à laquelle une adresse de tailnet complète
      // (`http://` + machine + tailnet + `.ts.net`, une quarantaine de
      // caractères en chasse fixe) tient SANS troncature, boutons compris.
      .frame(minWidth: 560, idealWidth: 640, maxWidth: .infinity, minHeight: 520, idealHeight: 620)
      // `grouped` est le style des réglages macOS : sections encartées, en-têtes
      // en petites capitales, fond de fenêtre. Le style par défaut, lui, ressemble
      // à un formulaire de saisie — ce que ces réglages ne sont pas.
      .formStyle(.grouped)
    #endif
  }

  // MARK: - Cet appareil

  /// CE QUE CET APPAREIL SAIT DE LUI-MÊME.
  ///
  /// POURQUOI C'EST ICI, ET PAS SEULEMENT SUR LA PAGE D'UNE MACHINE. L'état de
  /// Tailscale sur CET appareil est la première étape du parcours de CHAQUE
  /// machine : quand rien ne répond, c'est la première cause à écarter. Il fallait
  /// jusqu'ici ouvrir la page d'une machine — n'importe laquelle — pour la lire,
  /// et il n'y avait aucun endroit où la lire quand aucune machine n'est connue :
  /// exactement l'état d'un appareil neuf, celui qui en a le plus besoin.
  @ViewBuilder
  private var appareil: some View {
    Section {
      LabeledContent("Tailscale", value: modele.tailscaleInstalle ? L("installé") : L("absent"))
      LabeledContent("Réseau tailnet", value: etatTailnet)
      if ExceptionATS.sousATS {
        LabeledContent("Transport en clair", value: etatTransport)
      }
      Button(L("Vérifier maintenant")) {
        let _ = modele.relireEtatTailscale()
      }
    } header: {
      T("Cet appareil")
    } footer: {
      Text(
        modele.tailnetDeLAppareil == true
          ? "Cet appareil porte une adresse de tailnet : il peut joindre les machines qui publient DSH."
          : "Sans tailnet, aucune machine distante n'est joignable — c'est la première étape du parcours de chaque serveur."
      )
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Alertes

  /// LES ALERTES, ET LEUR LIMITE DITE LÀ OÙ ON LES ALLUME.
  ///
  /// POURQUOI LA LIMITE EST ÉCRITE ICI, ET PAS SEULEMENT DANS LE README. Une
  /// alerte locale part d'un processus VIVANT : iOS suspend une application
  /// quelques secondes après son passage en arrière-plan, et rien ne peut alors
  /// être observé. Promettre « soyez prévenu » sans le dire ferait passer une
  /// limite de plateforme pour une panne — et c'est exactement ce que ce projet
  /// refuse d'écrire.
  ///
  /// L'INTERRUPTEUR DIT LA VÉRITÉ : il suit l'état RÉELLEMENT obtenu, donc un
  /// refus du système le laisse éteint au lieu d'afficher un « oui » qui ne
  /// produirait rien.
  @ViewBuilder
  private var alertes: some View {
    Section {
      Toggle(
        isOn: Binding(
          get: { modele.alertesActives },
          set: { actives in
            Task { await modele.definirAlertes(actives) }
          })
      ) {
        T("Me prévenir quand l'agent attend ou termine")
      }
    } header: {
      T("Alertes")
    } footer: {
      T("Une alerte part quand une session se met à ATTENDRE une réponse, ou quand un tour se termine — jamais pour ce que vous êtes en train de regarder. Elle n'est envoyée que tant que l'application tourne : iOS la suspend en arrière-plan, et la réveiller demanderait un serveur de notification, que ce projet n'a pas.")
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// Le tri-état de `tailnetDeLAppareil`, dit en mots.
  ///
  /// « pas encore mesuré » n'est PAS « non » : le constat se fait par une lecture
  /// d'interfaces réseau, et tant qu'il n'a pas eu lieu, l'écran n'affirme rien.
  private var etatTailnet: String {
    guard let tailnet = modele.tailnetDeLAppareil else {
      return L("vérification…")
    }
    return tailnet ? L("connecté") : L("absent")
  }

  /// CE QUE LE PAQUET CONSTRUIT AUTORISE, en une ligne.
  ///
  /// POURQUOI CETTE LIGNE EXISTE. Une adresse en clair vers un nom MagicDNS est
  /// refusée par App Transport Security AVANT toute tentative réseau, sauf si le
  /// paquet construit porte une exception. Le nombre d'exceptions déclarées est
  /// donc la réponse à « pourquoi cette adresse ne répond-elle pas alors que le
  /// tailnet fonctionne ? » — une question qui a coûté une soirée.
  private var etatTransport: String {
    let declarations = ExceptionATS.duBuildCourant.count
    switch declarations {
    case 0: return L("aucune exception déclarée")
    case 1: return L("1 exception déclarée")
    default: return String(format: L("%d exceptions déclarées"), declarations)
    }
  }

  // MARK: - Diagnostic

  /// OÙ L'APPLICATION ÉCRIT CE QU'ELLE N'EXPLIQUE PAS.
  ///
  /// POURQUOI LE CHEMIN EST MONTRÉ, ET COPIABLE. Le fichier n'est lisible ni
  /// depuis l'interface ni depuis l'iPhone : il faut aller le chercher sur la
  /// machine, ou le faire passer. Un chemin qu'on ne peut pas copier oblige à le
  /// recopier caractère par caractère — et c'est un chemin absolu.
  @ViewBuilder
  private var diagnostic: some View {
    Section {
      if let chemin {
        Button(L("Copier le chemin du fichier")) {
          PressePapiers.ecrire(chemin)
        }
        Text(chemin)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        T("Aucun dossier de documents : cette exécution n'écrit pas de diagnostic.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    } header: {
      T("Diagnostic")
    } footer: {
      T("Les erreurs qu'aucune explication ne couvre y sont écrites : l'adresse visée, le message, la longueur du jeton et une empreinte de celui-ci. Le jeton lui-même n'y est jamais recopié.")
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// Le chemin du fichier de diagnostic, quand l'exécution en a un.
  private var chemin: String? {
    Persistance.documentsParDefaut?
      .appendingPathComponent(Persistance.nomDuDiagnostic)
      .path
  }

  // MARK: - Réinitialiser

  /// LA RÉINITIALISATION — destructrice, donc DITE, CONFIRMÉE, et COMPTÉE.
  ///
  /// POURQUOI ELLE EST DANS LES RÉGLAGES. « Oublier le serveur » vivait dans le
  /// menu contextuel d'une vignette, et il n'oubliait que l'adresse : les jetons du
  /// trousseau, les préférences par machine et la session consultée restaient. Il
  /// n'existait donc **aucun** geste pour repartir d'un appareil propre — et la
  /// seule façon de le faire était de désinstaller l'application.
  ///
  /// TROIS PROPRIÉTÉS, ET CHACUNE RÉPOND À UN DÉFAUT CONNU DE CE GENRE D'ÉCRAN :
  ///
  ///   1. **elle dit ce qu'elle efface** — dans le pied, avant le geste, y compris
  ///      ce qu'elle ne touche PAS (le jeton du harness, le fichier d'amorçage) ;
  ///   2. **elle demande confirmation**, avec la conséquence nommée : un jeton
  ///      effacé se retrouve en RÉAPPAIRANT, pas en annulant ;
  ///   3. **elle rend compte** — le détail de ce qui a été effacé reste affiché
  ///      sous le bouton. Un bouton qui ne dit pas ce qu'il a fait ne vaut pas
  ///      mieux qu'un bouton sans effet.
  @ViewBuilder
  private var reinitialiser: some View {
    Section {
      Button(role: .destructive) {
        confirmationOuverte = true
      } label: {
        Label {
          T("Réinitialiser l'application")
        } icon: {
          Image(systemName: "arrow.counterclockwise")
        }
      }
      if let rapport {
        Text(rapport)
          .font(.caption)
          .foregroundStyle(EtatVisuel.attente.couleur)
          .fixedSize(horizontal: false, vertical: true)
      }
    } header: {
      T("Réinitialiser")
    } footer: {
      T("Efface les jetons d'appareil gardés sur cet appareil — TOUS, y compris ceux de machines que vous ne visitez plus —, l'adresse et le nom mémorisés, les préférences par serveur, la dernière session consultée, le réglage des alertes et le fichier de diagnostic. Le jeton du harness, sur le Mac, n'est pas touché. Un fichier d'amorçage déposé à la main n'est PAS effacé : il ramènerait l'adresse et le jeton au prochain lancement, et le compte rendu le dit.")
        .fixedSize(horizontal: false, vertical: true)
    }
    .confirmationDialog(
      T("Réinitialiser l'application ?"),
      isPresented: $confirmationOuverte,
      titleVisibility: .visible
    ) {
      Button(L("Tout effacer"), role: .destructive) {
        Task { @MainActor in
          let resultat = await modele.reinitialiser()
          rapport = modele.texteDuRapport(resultat)
        }
      }
      Button(L("Annuler"), role: .cancel) {}
    } message: {
      T("Les jetons gardés sur cet appareil seront effacés : il faudra réappairer pour retrouver l'accès. Cette action ne se défait pas.")
    }
  }

  // MARK: - À propos

  /// LES VERSIONS, ET RIEN DE PLUS.
  ///
  /// Un client et un hôte qui ne s'entendent pas le disent par un message
  /// d'incompatibilité ; savoir quelle version du protocole ce client sait lire
  /// est ce qui permet de comprendre ce message. Le reste — mentions, licence —
  /// appartient au dépôt, pas à l'écran.
  private var aPropos: some View {
    Section(header: T("À propos")) {
      LabeledContent("Application", value: versionApplication)
      LabeledContent("Protocole lu", value: "version \(versionProtocoleSupportee)")
      #if os(iOS)
        LabeledContent("Plateforme", value: "iPhone")
      #else
        LabeledContent("Plateforme", value: "macOS")
      #endif
    }
  }

  /// La version déclarée par le PAQUET, ou un tiret s'il n'y en a pas.
  ///
  /// Un binaire lancé hors paquet (`swift run DSHRemoteMac`) n'a pas
  /// d'`Info.plist` : afficher « 0.2 » y serait une invention. Le tiret dit
  /// « pas de version déclarée », ce qui est la vérité de cette exécution-là.
  private var versionApplication: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String
    let build = info?["CFBundleVersion"] as? String
    switch (version, build) {
    case let (version?, build?): return "\(version) (\(build))"
    case let (version?, nil): return version
    default: return "—"
    }
  }
}
