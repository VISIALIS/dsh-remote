import DSHRemoteKit
import SwiftUI

/// Saisie manuelle d'une adresse de serveur : le chemin des cas que la
/// découverte ne couvre pas — et le SEUL chemin d'un iPhone neuf.
///
/// POURQUOI CETTE FEUILLE EXISTE SÉPARÉMENT. L'adresse vivait dans les réglages
/// généraux, avec le jeton. Elle concerne pourtant **une machine**, pas
/// l'application : quand la découverte ne rend rien — aucun Mac ne publie, ou
/// l'iPhone n'a encore joint personne — on veut saisir une adresse et ESSAYER,
/// pas ouvrir un écran de configuration. Cette feuille ne fait que cela.
///
/// POURQUOI LE JETON Y EST AUSSI, ET C'EST UNE CORRECTION. Les trois chemins de
/// saisie du jeton étaient : la page d'une machine CONNUE, l'amorçage macOS
/// depuis le coffre, et un fichier de configuration de simulateur. Aucun n'est
/// atteignable depuis un iPhone vierge — la liste est vide, donc aucune page de
/// machine ne s'ouvre, et cette feuille-ci portait l'adresse, les deux actions,
/// et **aucun champ de jeton**. La connexion ne pouvait donc finir qu'en `401`,
/// et le message du `401` renvoyait vers les Réglages, qui ne contiennent plus
/// aucun champ de jeton depuis que chaque hôte a le sien : le remède prescrit
/// était un écran vide, et le champ réel était derrière une porte fermée.
///
/// Le jeton est donc ici, à côté de l'adresse à laquelle il appartient — la
/// seule feuille qu'un appareil neuf puisse ouvrir.
struct FeuilleAdresse: View {
  @Bindable var modele: ModeleApp
  @Environment(\.dismiss) private var fermer

  /// LE JETON SAISI ICI, TENU À PART DU MODÈLE JUSQU'À LA SOUMISSION.
  ///
  /// POURQUOI PAS UNE LIAISON DIRECTE, comme la page d'une machine le fait. Là-bas,
  /// la clé du jeton est l'adresse d'une machine CONNUE : elle ne bouge pas, et
  /// une frappe n'écrit qu'une entrée, corrigée à chaque caractère. Ici, la clé
  /// EST l'adresse en cours de saisie : une liaison directe confierait au
  /// trousseau, caractère par caractère, un jeton tronqué rangé sous une adresse
  /// tronquée — autant de copies partielles d'un secret que de préfixes
  /// d'adresse. Le champ reste donc local, et n'est engagé qu'au moment d'agir.
  @State private var jeton = ""

  /// Ce que CE paquet autorise, et ce qu'il a donc le droit de conseiller.
  ///
  /// L'Info.plist du paquet en cours est LISIBLE : conseiller `http://` vers un
  /// nom de domaine, c'est affirmer que l'exception ATS est là. Quand elle n'y
  /// est pas, le conseil change au lieu de mentir.
  private var conseil: ConseilAdresse {
    ConseilAdresse.pour(adresse: modele.adresse, plist: Bundle.main.infoDictionary)
  }

  private var adresseRenseignee: Bool {
    !modele.adresse.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private var jetonComplet: Bool { ModeleApp.jetonBienForme(jeton) }

  var body: some View {
    NavigationStack {
      Form {
        sectionAppairage
        sectionAdresse
        sectionJeton
        sectionActions
      }
      .navigationTitle(T("Adresse"))
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(L("Terminé")) { fermer() }
        }
      }
      // LE CHAMP MONTRE LE JETON DE L'ADRESSE AFFICHÉE. `viser` recharge déjà
      // celui de la nouvelle adresse à chaque frappe ; on se recale dessus, sans
      // quoi un jeton saisi pour une machine pourrait être engagé pour une autre.
      .onAppear { jeton = modele.jetonSaisi }
      .onChange(of: modele.adresse) { _, _ in jeton = modele.jetonSaisi }
    }
    #if os(macOS)
      // Une adresse de tailnet fait une quarantaine de caractères : la feuille
      // doit être assez large pour l'afficher entière (même mesure que les
      // réglages, même correction). La hauteur a suivi le jeton et ses deux
      // actions, puis l'appairage : quatre sections ne tiennent plus dans
      // 280 points.
      .frame(minWidth: 520, idealWidth: 580, minHeight: 520, idealHeight: 580)
    #endif
  }

  // MARK: - 0. L'appairage — le chemin court

  /// L'APPAIRAGE : UN GESTE QUI REMPLIT LES DEUX CHAMPS.
  ///
  /// POURQUOI IL EST EN PREMIER. Le panneau « Appairer un appareil », dans
  /// l'interface web du Mac, affiche un QR code ET son texte ; les deux portent
  /// l'adresse et le jeton ENSEMBLE. Le scanner (iPhone) ou le collage (Mac, qui
  /// ne peut pas scanner son propre écran) remplace donc deux saisies — dont
  /// 43 caractères recopiés d'un terminal où ils ne s'affichent qu'une fois.
  ///
  /// LA SAISIE MANUELLE RESTE EN DESSOUS, et elle n'est pas un vestige : elle
  /// couvre le cas où le Mac n'est pas à portée, où la caméra est refusée, et
  /// celui d'un jeton déjà connu qu'on veut simplement poser.
  private var sectionAppairage: some View {
    Section {
      // LES DEUX GESTES SONT DANS UNE VUE PARTAGÉE, et c'est une correction : ils
      // vivaient ici, en pensant qu'un appareil neuf n'ouvrirait que cette
      // feuille. Vrai pour un appareil VIERGE, faux pour tous les autres — et
      // l'usage a tranché en une phrase : « sur l'iPhone, je n'ai pas de système
      // avec un QR code ». La feuille garde la section (le chemin d'un appareil
      // neuf reste celui-ci), mais l'implémentation n'existe plus qu'une fois.
      BoutonsAppairage(modele: modele) { fermer() }
    } header: {
      T("Appairer")
    } footer: {
      T("Le panneau « Appairer un appareil » de l'interface DSH affiche un QR code et le texte qui va avec : le scanner (ou le collage) remplit l'adresse ET le jeton d'un seul geste, puis se connecte.")
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - 1. L'adresse

  private var sectionAdresse: some View {
    Section {
      // Liaison passant par le modèle : l'adresse est mémorisée dès la
      // frappe, sans attendre une connexion réussie. C'est précisément quand
      // la connexion échoue qu'on veut retrouver son adresse.
      TextField(
        conseil.exemple,
        text: Binding(
          get: { modele.adresse },
          set: { modele.definirAdresse($0) }
        )
      )
      // Chasse fixe : une adresse se lit caractère par caractère, et c'est ce
      // qui permet de repérer une faute de frappe.
      .font(.callout.monospaced())
      .lineLimit(1)
      .autocorrectionDisabled()
      .layoutPriority(1)
      #if os(iOS)
        .textInputAutocapitalization(.never)
        .keyboardType(.URL)
      #endif

      // L'AVERTISSEMENT VIENT AVANT L'ESSAI, parce qu'il est CERTAIN : ce build
      // n'a pas d'exception ATS, donc iOS refusera cette adresse en `-1022`.
      // Le dire après coup obligerait à chercher une panne réseau là où le refus
      // était connu d'avance.
      if let avertissement = conseil.avertissement {
        Label(avertissement, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }
    } header: {
      T("Adresse de la machine")
    } footer: {
      Text(conseil.aide)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - 2. Le jeton

  private var sectionJeton: some View {
    Section {
      HStack(spacing: 8) {
        SecureField("jeton d'appareil", text: $jeton)
          .font(.callout.monospaced())
          .lineLimit(1)
          .autocorrectionDisabled()
          .layoutPriority(1)
          #if os(iOS)
            .textInputAutocapitalization(.never)
          #endif

        // LE COLLAGE, PAR LE BOUTON SYSTÈME SUR iOS.
        //
        // POURQUOI. Lire `UIPasteboard.general.string` sur un appui déclenche la
        // bannière « Collé depuis … » : iOS avertit qu'une application a lu le
        // presse-papiers, et c'est une bonne règle — sauf qu'ici l'utilisateur
        // DEMANDE ce collage. Le bouton système (`PasteButton`) exprime la même
        // intention AU SYSTÈME, qui accorde l'accès sans bannière et sans lire le
        // presse-papiers à son insu. La validation, elle, reste la même des deux
        // côtés (`ModeleApp.jetonPlausible`).
        #if os(iOS)
          PasteButton(payloadType: String.self) { chaines in
            adopter(chaines.first)
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
          .cibleTactile()
          .accessibilityLabel(T("Coller le jeton depuis le presse-papier"))
        #else
          Button {
            coller()
          } label: {
            Image(systemName: "doc.on.clipboard")
          }
          .buttonStyle(.borderless)
          .cibleTactile()
          .accessibilityLabel(T("Coller le jeton depuis le presse-papier"))
        #endif

        if !jeton.isEmpty {
          Button {
            jeton = ""
          } label: {
            Image(systemName: "xmark.circle")
          }
          .buttonStyle(.borderless)
          .cibleTactile()
          .accessibilityLabel(T("Effacer le jeton saisi"))
        }
      }

      // ON NE JUGE QUE CE QUI A ÉTÉ SAISI. Un champ vide n'est pas un jeton
      // incomplet : lui reprocher ses 0 caractères serait un reproche pour rien.
      if !jeton.isEmpty {
        Label(
          jetonComplet
            ? "jeton complet (43 caractères)"
            : "jeton incomplet : \(jeton.count) caractères au lieu de 43",
          systemImage: jetonComplet ? "checkmark.seal" : "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(jetonComplet ? Color.green : Color.orange)
      }

      // Le rappel du `401` est ICI AUSSI : c'est le message que reçoit un
      // appareil neuf, et le champ qui répare est juste au-dessus.
      if modele.jetonRefuseParLeService {
        Label { T("Le service a refusé ce jeton. Chaque machine a le sien : recopiez celui de CET hôte.") } icon: { Image(systemName: "key") }
        .font(.caption)
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
      }
    } header: {
      T("Jeton d'appareil")
    } footer: {
      T("Il s'affiche une seule fois, dans la sortie du harness, au premier chargement du plugin sur cette machine. Il est gardé au trousseau — jamais dans les préférences — et n'est jamais renvoyé par une route.")
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - 3. Agir

  private var sectionActions: some View {
    Section {
      HStack(spacing: 12) {
        Button(L("Se connecter")) {
          soumettre { await modele.connecter() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(modele.enChargement || !adresseRenseignee)

        Button(L("Tester l'adresse")) {
          soumettre { await modele.testerAdresse() }
        }
        .disabled(modele.enChargement || !adresseRenseignee)

        if modele.enChargement { ProgressView().controlSize(.small) }
      }

      // Le résultat du test, NOMMÉ : « rien ne s'est passé » ne doit jamais
      // être une réponse possible à un appui.
      switch modele.etatAdresse {
      case .inconnu:
        EmptyView()
      case .enCours:
        Label { T("test de l'adresse…") } icon: { Image(systemName: "hourglass") }.font(.caption)
      case let .joignable(reponses):
        Label("\(reponses) session(s) — adresse et jeton acceptés", systemImage: "checkmark.circle")
          .font(.caption)
          .foregroundStyle(.green)
      case let .injoignable(detail):
        Label(detail, systemImage: "xmark.circle")
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
    } footer: {
      T("« Se connecter » vise cette adresse tout de suite. « Tester l'adresse » ne change pas de serveur : elle dit seulement ce qu'elle a trouvé.")
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Les deux gestes

  /// ENGAGE LE JETON SAISI, PUIS AGIT.
  ///
  /// POURQUOI LES DEUX GESTES PASSENT PAR ICI. Le test d'adresse vérifie
  /// « adresse ET jeton acceptés » : sans engager le jeton d'abord, il
  /// éprouverait celui de la machine précédente, et accuserait un secret qui n'a
  /// rien à voir avec ce qu'on vient de coller.
  private func soumettre(_ geste: @escaping () async -> Void) {
    modele.enregistrerJeton(jeton)
    Task { await geste() }
  }

  /// Colle le presse-papier dans le champ, ET DIT quand il n'y a rien à coller.
  ///
  /// macOS SEULEMENT depuis que le bouton système fait ce travail sur iOS : le
  /// presse-papiers y est lu sur un geste explicite, ce que la plateforme ne
  /// signale pas.
  private func coller() {
    if modele.collerLeJeton() {
      jeton = modele.jetonSaisi
    } else {
      // Un presse-papiers vide est le cas le plus fréquent d'échec ici, et un
      // appui qui ne produit RIEN est un mensonge d'interface.
      modele.signaler(ModeleApp.messageJetonIllisible)
    }
  }

  /// ADOPTE LE TEXTE FOURNI PAR LE BOUTON SYSTÈME — même règle, même message.
  private func adopter(_ brut: String?) {
    guard let brut else {
      // Le système n'a rien rendu : c'est le cas « presse-papiers vide ».
      modele.signaler(ModeleApp.messageJetonIllisible)
      return
    }
    // Si le texte est inexploitable, `adopterJeton` a DÉJÀ posé le message : le
    // répéter ici ferait deux fois le même reproche.
    if modele.adopterJeton(brut) {
      jeton = modele.jetonSaisi
    }
  }
}
