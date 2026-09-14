import SwiftUI

/// LES DEUX GESTES D'APPAIRAGE — sortis de la feuille « Adresse », où personne
/// ne les trouvait.
///
/// POURQUOI CE FICHIER EXISTE. Le scanner et le collage vivaient dans la feuille
/// « Adresse », en première section, et le raisonnement était : « un appareil neuf
/// n'ouvre que cette feuille ». Il était FAUX, et l'usage l'a dit en une phrase :
/// « sur l'iPhone, je n'ai pas de système avec un QR code ». Un appareil DÉJÀ
/// configuré — le cas normal, celui de tous les jours — n'a aucune raison
/// d'ouvrir la feuille « Adresse » : le geste doit donc être là où l'on AJOUTE un
/// serveur, et son libellé doit dire « QR code ».
///
/// CE QUI RESTE VRAI, ET QUI N'EST PAS PERDU : la feuille « Adresse » garde la
/// section (elle utilise cette vue-ci), parce qu'un appareil vierge n'a toujours
/// que ce chemin-là.
struct BoutonsAppairage: View {
  @Bindable var modele: ModeleApp
  /// Appelé UNIQUEMENT quand un appairage a été appliqué — l'appelant ferme alors
  /// ce qu'il a ouvert. Un appairage refusé laisse la feuille ouverte, avec son
  /// motif : c'est là qu'on peut relire le code, ou en demander un autre.
  var surSucces: () -> Void = {}
  /// Bouton PLEIN, ou style du système ? Les deux existent selon l'endroit : dans
  /// la page « Ajouter un serveur », le geste est LA chose à faire ; dans la
  /// feuille « Adresse », il cohabite avec la saisie manuelle et doit rester discret.
  var prominent: Bool = false

  @State private var scanOuvert = false

  var body: some View {
    // LE STYLE NE PEUT PAS ÊTRE UN TERNAIRE : `borderedProminent` et `automatic`
    // sont deux TYPES différents, et `ButtonStyle` est un protocole — mesuré, la
    // compilation refuse. On choisit donc la vue, pas la valeur.
    if prominent {
      gestes.buttonStyle(.borderedProminent)
    } else {
      gestes
    }
  }

  @ViewBuilder
  private var gestes: some View {
    Group {
      #if os(iOS)
        Button {
          scanOuvert = true
        } label: {
          Label { T("Scanner le QR code") } icon: { Image(systemName: "qrcode.viewfinder") }
        }
        .disabled(modele.enChargement)

        // LE COLLAGE PAR LE BOUTON SYSTÈME, ICI AUSSI : iOS l'accorde sans
        // bannière et sans que nous lisions le presse-papiers à l'insu de
        // l'utilisateur. C'est aussi le seul chemin possible dans un simulateur,
        // qui n'a pas de caméra.
        //
        // POURQUOI PAS DE LIBELLÉ ÉCRIT ICI. `PasteButton` n'offre AUCUN
        // initialiseur qui prenne une vue de libellé : mesuré à la construction,
        // un `label:` en fermeture de fin ne compile pas (Xcode 26.6). Le libellé
        // est celui du système, et c'est cohérent : c'est LUI qui accorde l'accès.
        // Le nom accessible, lui, est explicite ci-dessous.
        PasteButton(payloadType: String.self) { chaines in
          adopter(chaines.first)
        }
        .accessibilityLabel(T("Coller un appairage"))
      #else
        Button {
          coller()
        } label: {
          Label { T("Coller un appairage") } icon: { Image(systemName: "doc.on.clipboard") }
        }
        .disabled(modele.enChargement)
      #endif
    }
        #if os(iOS)
      .sheet(isPresented: $scanOuvert) {
        VueScanAppairage { texte in adopter(texte) }
      }
    #endif
  }

  /// ADOPTE UN APPAIRAGE — puis se connecte, parce que c'est ce qu'on voulait.
  ///
  /// LE REFUS EST DÉJÀ SIGNALÉ par le modèle, avec le message de son motif : le
  /// répéter ici ferait deux fois le même reproche, et surtout un reproche moins
  /// précis (« appairage invalide » au lieu de « ce lien vise la boucle locale »).
  private func adopter(_ brut: String?) {
    guard let brut else {
      modele.signaler(ModeleApp.messageAppairageIllisible)
      return
    }
    // DEUX FEUILLES SE FERMENT DANS LE MÊME GESTE — celle du scanner, puis
    // celle-ci. On leur laisse un tour de boucle : deux fermetures demandées dans
    // le même tick peuvent n'en produire qu'une, et l'utilisateur retomberait sur
    // un écran qu'il croyait avoir quitté. L'ORDRE EST RAISONNÉ, PAS MESURÉ : il
    // demande un vrai appareil (voir l'épreuve P4 du README du plugin).
    scanOuvert = false
    Task { @MainActor in
      // L'ÉCHANGE D'UN CODE EST UN APPEL RÉSEAU : la fermeture attend le verdict.
      guard await modele.appairer(brut) else { return }
      await Task.yield()
      surSucces()
      await modele.connecter()
    }
  }

  /// Colle un appairage du presse-papiers. macOS seulement : sur iOS, le bouton
  /// système fait ce travail sans bannière.
  private func coller() {
    guard let brut = ModeleApp.appairageDuPressePapiers() else {
      modele.signaler(ModeleApp.messageAppairageIllisible)
      return
    }
    adopter(brut)
  }
}

/// LA FEUILLE D'APPAIRAGE — le geste seul, atteignable depuis « Ajouter un
/// serveur ».
///
/// POURQUOI ELLE EST SÉPARÉE DE LA FEUILLE « ADRESSE ». Celle-ci sert à SAISIR une
/// adresse ; celle-là à RECEVOIR un appairage. Les mélanger obligeait à ouvrir
/// « Saisir une adresse » pour trouver un scanner — et le libellé du bouton
/// promettait autre chose que ce qu'on y trouvait.
struct FeuilleAppairage: View {
  @Bindable var modele: ModeleApp
  @Environment(\.dismiss) private var fermer

  /// LE TEXTE DU QR CODE, SAISI OU COLLÉ À LA MAIN.
  ///
  /// POURQUOI CE CHAMP EXISTE, ALORS QUE LE PRESSE-PAPIERS SUFFIT SOUVENT. Trois
  /// cas le rendent nécessaire, et ils sont réels : le presse-papiers contient
  /// AUTRE CHOSE (on vient de copier autre chose, et le bouton système ne propose
  /// alors que ce qu'il a) ; le code a été transmis par un message, pas par un
  /// écran à scanner ; et sur un appareil dont la caméra est refusée ou occupée.
  /// C'est aussi la seule voie qui laisse RELIRE ce qu'on valide avant de le faire.
  @State private var texte = ""

  var body: some View {
    NavigationStack {
      Form {
        Section {
          BoutonsAppairage(modele: modele) { fermer() }
        } header: {
          T("Appairer")
        } footer: {
          T("Le panneau « Appairer un appareil » de l'interface DSH affiche un QR code et le texte qui va avec : le scanner (ou le collage) remplit l'adresse ET le jeton d'un seul geste, puis se connecte.")
            .fixedSize(horizontal: false, vertical: true)
        }

        Section {
          TextField("dshremote://…", text: $texte, axis: .vertical)
            .font(.callout.monospaced())
            .lineLimit(1...3)
            .autocorrectionDisabled()
            #if os(iOS)
              .textInputAutocapitalization(.never)
            #endif
          Button {
            validerLeTexte()
          } label: {
            Label { T("Appairer avec ce texte") } icon: { Image(systemName: "checkmark.circle") }
          }
          .disabled(texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || modele.enChargement)
        } header: {
          T("Ou renseignez le texte du QR code")
        } footer: {
          // LA FORME EST MONTRÉE, ET ELLE EST VÉRIFIABLE : c'est ce qui permet de
          // reconnaître un texte tronqué avant de l'envoyer.
          T("Le texte affiché sous le QR code commence par `dshremote://` et contient le nom du Mac. Un texte d'un autre genre est refusé, avec la raison.")
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .navigationTitle(T("Appairer un appareil"))
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(L("Terminé")) { fermer() }
        }
      }
    }
    #if os(iOS)
      .presentationDetents([.medium, .large])
    #endif
  }

  /// Applique le texte saisi — et NE FERME PAS en cas de refus : le motif est
  /// affiché derrière, et l'utilisateur doit pouvoir corriger ce qu'il a écrit.
  private func validerLeTexte() {
    let brut = texte.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !brut.isEmpty else { return }
    Task { @MainActor in
      guard await modele.appairer(brut) else { return }
      texte = ""
      fermer()
      await modele.connecter()
    }
  }
}
