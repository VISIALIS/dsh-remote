import DSHRemoteKit
import SwiftUI

/// La page d'un serveur : ce qu'il est, ce qu'on peut en faire, et pourquoi quand
/// il ne répond pas.
///
/// POURQUOI CETTE PAGE A ÉTÉ RESTRUCTURÉE EN QUATRE BANDES. Elle empilait six
/// blocs de même poids dans l'ordre où le code avait grandi — en-tête, adresse,
/// jeton, interrupteurs, bandeau d'erreur, diagnostic —, si bien que le
/// DIAGNOSTIC, qui est la raison d'être de la page, se lisait en dernier : sur un
/// iPhone, il fallait faire défiler le jeton d'un hôte et deux réglages pour
/// savoir ce qui n'allait pas. Le même fait y était dit quatre fois (« hors
/// ligne » sous le titre, dans le bandeau rouge, dans le résumé du parcours, et
/// par le titre de l'étape 2), et deux avertissements de jeton passaient avant
/// toute information sur la machine — dont un FAUX, puisque l'état « hors ligne »
/// était pris pour un jeton refusé.
///
/// L'ordre suit maintenant les questions qu'on se pose, et rien d'autre :
///
///   1. QUELLE MACHINE, ET DANS QUEL ÉTAT ? — le nom, UNE pastille d'état, son
///      adresse, et UNE action : celle qui peut aboutir dans cet état ;
///   2. POURQUOI PAS, ET QUE FAIRE ? — la conclusion, puis les quatre constats.
///      Tous restent visibles (un diagnostic ne cache rien), mais seule l'étape
///      qui bloque porte sa méthode dépliée : c'est la seule exécutable
///      maintenant, et trois jeux de commandes noient celle qui compte ;
///   3. SES RÉGLAGES — jeton, suivi, filtre, repliés. Rien de tout cela n'est une
///      raison d'ouvrir la page ; tout y reste pourtant, parce que chaque réglage
///      vit à l'endroit qui le rend vrai (le jeton est propre à chaque hôte, le
///      suivi vaut pour cette machine) ;
///   4. LE DÉTAIL TECHNIQUE — l'erreur brute, quand elle apprend quelque chose, et
///      elle seule : une phrase en français n'est pas un détail technique.
struct VueServeur: View {
  @Bindable var modele: ModeleApp
  /// La machine affichée, résolue à chaque rendu par `VuePrincipale`.
  let serveur: ServeurMac

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        identite
        carteDiagnostic
        reglagesDeLaMachine
        detailTechnique
      }
      .padding(24)
      .frame(maxWidth: 680, alignment: .leading)
      // CENTRÉE, ET NON COLLÉE À GAUCHE. Sur macOS, la colonne de détail est
      // large : une colonne de texte de 680 points tassée contre le bord laissait
      // une bande grise vide à droite, et l'œil ne savait plus où était la page.
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .navigationTitle(serveur.nom)
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
  }

  // MARK: - 1. Identité, état, action

  /// L'ÉTAT DE LA MACHINE, dit dans les mots partagés avec le panneau latéral.
  private var etat: EtatMachine.Description {
    EtatMachine.decrire(
      enLigne: serveur.enLigne,
      sertDsh: modele.sertDsh(serveur),
      estLocal: serveur.estLocal,
      court: false)
  }

  private var identite: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 14) {
        Image(systemName: serveur.symbole)
          .font(.system(size: 30))
          .foregroundStyle(serveur.enLigne ? Color.accentColor : Color.secondary)
          .frame(width: 40)
        VStack(alignment: .leading, spacing: 6) {
          // LE NOM N'EST PAS RÉPÉTÉ ICI. Il est déjà dans la barre de navigation
          // sur iPhone, et dans la BARRE DE TITRE DE LA FENÊTRE sur macOS — où
          // `NavigationSplitView` reprend le titre de la colonne de détail.
          // Constaté sur capture : « MacMini » s'écrivait deux fois, à quarante
          // points d'écart, et la seconde ligne coûtait la place d'un constat du
          // diagnostic. L'identité de la bande, c'est l'icône, l'état et
          // l'adresse.
          PastilleDeMachine(description: etat)
        }
        Spacer(minLength: 8)
        if modele.serveurChoisi == serveur {
          Label("serveur courant", systemImage: "checkmark.circle.fill")
            .font(.caption)
            .foregroundStyle(Color.accentColor)
        }
      }

      // L'ADRESSE SE COPIE. Elle est faite pour voyager — la saisir sur un autre
      // appareil, la donner à `curl` — et le composant des commandes fait
      // exactement cela, libellé d'accessibilité compris (« Copier adresse »).
      // Le titre « Adresse » disparaît : une URL sous un nom de machine se lit
      // sans étiquette, et chaque mot retiré est un mot de moins à parcourir.
      LigneCommande(commande: serveur.adresse, libelle: "adresse")

      HStack(spacing: 10) {
        Button {
          actionPrincipale.geste()
        } label: {
          Label(actionPrincipale.titre, systemImage: actionPrincipale.symbole)
        }
        .buttonStyle(.borderedProminent)
        .disabled(modele.enChargement)

        if modele.enChargement { ProgressView().controlSize(.small) }
      }

      // La bascule de serveur se DIT : changer la machine de l'utilisateur sans
      // le prévenir serait une substitution silencieuse.
      if let ajuste = modele.choixAjuste {
        Label(ajuste, systemImage: "arrow.triangle.swap")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  /// L'ACTION PRINCIPALE — celle qui peut ABOUTIR dans l'état où est la machine.
  ///
  /// POURQUOI ELLE CHANGE, ET PAS SEULEMENT SON LIBELLÉ. « Se connecter » était
  /// offert à toutes les machines, y compris celles dont on sait déjà qu'elles ne
  /// répondront pas : le garde-fou local évite la requête, mais le seul résultat
  /// possible restait un message disant que la machine est éteinte. Une page qui
  /// met en avant une action sans issue fait douter de tout ce qu'elle affiche.
  private var actionPrincipale: (titre: String, symbole: String, geste: () -> Void) {
    guard serveur.enLigne else {
      if let autre = autreMacJoignable {
        return (
          "Choisir \(autre.premierMot)", "arrow.triangle.swap",
          { Task { await modele.choisirEtConnecter(autre) } }
        )
      }
      // Aucun autre Mac joignable : la seule chose utile est de redemander la
      // liste — le Mac a pu être rallumé depuis la dernière découverte.
      return (
        "Rafraîchir la liste", "arrow.clockwise",
        { Task { await modele.synchroniserServeurs() } }
      )
    }
    switch modele.sertDsh(serveur) {
    case true:
      let dejaVise = modele.serveurChoisi == serveur
      return (
        dejaVise ? "Reconnecter" : "Se connecter", "bolt.horizontal",
        { Task { await modele.choisirEtConnecter(serveur) } }
      )
    case false, nil:
      // LA MACHINE RÉPOND, mais rien ne dit encore que DSH y est. Deux gestes,
      // selon qu'elle est ou non celle que l'application VISE : si c'est elle, on
      // reteste son adresse — seul moyen de vérifier une adresse saisie à la
      // main, que la sonde ne voit pas puisqu'elle ne parcourt que le tailnet ;
      // sinon on redemande son verdict à la sonde, sans changer de cible.
      if ModeleApp.vise(modele.adresse, serveur) {
        return ("Revérifier", "stethoscope", { Task { await modele.testerAdresse() } })
      }
      return ("Revérifier", "stethoscope", { Task { await modele.sonderLesServeurs() } })
    }
  }

  /// Un AUTRE Mac joignable, s'il y en a un.
  ///
  /// On préfère celui dont la sonde a dit qu'il sert DSH : envoyer l'utilisateur
  /// vers une machine « en ligne » qui ne publie rien remplacerait une impasse
  /// par une autre.
  private var autreMacJoignable: ServeurMac? {
    let autres = modele.serveurs.filter { $0.id != serveur.id && $0.enLigne }
    return autres.first { modele.sertDsh($0) == true } ?? autres.first
  }

  // MARK: - 2. Le diagnostic

  /// La cause, POUR CETTE MACHINE.
  private var cause: CauseSansDsh? { modele.causeSansDsh(serveur) }

  /// Les étapes de CETTE machine, recalculées à chaque rendu : la sonde peut
  /// rendre son verdict entre deux affichages.
  private var etapes: [EtapesServeur.Etape] {
    EtapesServeur.etapes(
      tailnetDeLAppareil: modele.tailnetDeLAppareil,
      enLigne: serveur.enLigne,
      sertDsh: modele.sertDsh(serveur),
      cause: cause)
  }

  /// LA CARTE DU DIAGNOSTIC — conclusion, puis constats.
  ///
  /// La carte est dessinée ICI et non par `ParcoursDesEtapes` (`encadre: false`) :
  /// la conclusion appartient au même bloc que les constats, et deux cartes
  /// voisines auraient redit la même séparation que le texte.
  private var carteDiagnostic: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Diagnostic")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)

      Label(conclusion.texte, systemImage: conclusion.symbole)
        .font(.callout.weight(.medium))
        .foregroundStyle(conclusion.ton.couleur)
        .fixedSize(horizontal: false, vertical: true)

      ParcoursDesEtapes(etapes: etapes, mode: .diagnostic, encadre: false) { etape in
        methodologie(pour: etape.numero, connue: etape.etat == .aFaire)
      }
    }
    .padding(14)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
  }

  private var conclusion: EtatMachine.Description {
    EtatMachine.conclusion(enLigne: serveur.enLigne, etapes: etapes)
  }

  // MARK: - 3. Les réglages de cette machine

  /// REPLIÉS, MAIS SUR CETTE PAGE. Deux règles se rencontrent ici : un réglage
  /// vit à l'endroit qui le rend vrai — le jeton est propre à chaque hôte, le
  /// suivi décide si l'on interroge CE serveur —, et rien de tout cela n'est une
  /// raison d'ouvrir la page. Un bloc replié satisfait les deux : il est là sans
  /// s'interposer entre l'adresse et le verdict.
  private var reglagesDeLaMachine: some View {
    DisclosureGroup {
      VStack(alignment: .leading, spacing: 16) {
        jeton
        Divider()
        suiviEtFiltre
      }
      .padding(.top, 10)
    } label: {
      Label("Réglages de cette machine", systemImage: "slider.horizontal.3")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }
    .padding(14)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
  }

  /// Le suivi et le filtre de CETTE machine.
  ///
  /// POURQUOI ICI ET NON DANS LES RÉGLAGES GÉNÉRAUX — le propriétaire l'a
  /// demandé, et il a raison : les deux portent sur la connexion à une machine.
  /// Le suivi décide si l'on interroge CE serveur ; le filtre décide ce qu'on
  /// affiche de SA liste. Les garder globaux faisait hériter chaque serveur des
  /// choix faits pour le précédent.
  private var suiviEtFiltre: some View {
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
  /// mensonge d'endroit.
  ///
  /// ET C'EST LE JETON DE **CETTE** MACHINE, pas celui de la cible. La page peut
  /// être ouverte sur un hôte auquel on n'est PAS connecté : lire et écrire le
  /// jeton de la cible faisait alors afficher un secret sous le nom d'un autre,
  /// et un jeton collé ici partait vers une machine qui n'est pas celle qu'on
  /// regarde. Toutes les opérations de ce bloc passent donc par
  /// `serveur.adresse`.
  private var jeton: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Jeton d'appareil de cet hôte")
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack(spacing: 8) {
        SecureField(
          modele.jetonDisponible(pour: serveur.adresse)
            ? "déjà enregistré — saisir pour remplacer" : "jeton d'appareil",
          // Guardé dès la frappe POUR CET HÔTE : un jeton collé puis abandonné
          // serait perdu, alors qu'il vient d'être recopié.
          text: Binding(
            get: { modele.jeton(pour: serveur.adresse) },
            set: { modele.definirJeton($0, pour: serveur.adresse) })
        )
        .font(.callout.monospaced())
        .lineLimit(1)
        .autocorrectionDisabled()
        .layoutPriority(1)
        #if os(iOS)
          .textInputAutocapitalization(.never)
        #endif
        // LE COLLAGE, PAR LE BOUTON SYSTÈME SUR iOS — même raison que dans la
        // feuille Adresse : lire le presse-papiers sur un appui déclenche la
        // bannière système, alors que l'utilisateur demande précisément ce
        // collage. Sur macOS, la lecture sur geste explicite ne se signale pas.
        #if os(iOS)
          PasteButton(payloadType: String.self) { chaines in
            guard let brut = chaines.first else {
              modele.signaler(ModeleApp.messageJetonIllisible)
              return
            }
            modele.adopterJeton(brut, pour: serveur.adresse)
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
          .cibleTactile()
          .accessibilityLabel("Coller le jeton depuis le presse-papier")
        #else
          Button {
            // UN COLLAGE REFUSÉ SE DIT : un presse-papiers vide ne doit pas
            // produire un appui sans effet.
            if !modele.collerLeJeton(pour: serveur.adresse) {
              modele.signaler(ModeleApp.messageJetonIllisible)
            }
          } label: {
            Image(systemName: "doc.on.clipboard")
          }
          .buttonStyle(.borderless)
          .cibleTactile()
          .accessibilityLabel("Coller le jeton depuis le presse-papier")
        #endif
        if modele.jetonDisponible(pour: serveur.adresse) {
          Button {
            modele.effacerJeton(pour: serveur.adresse)
          } label: {
            Image(systemName: "xmark.circle")
          }
          .buttonStyle(.borderless)
          .cibleTactile()
          .accessibilityLabel("Effacer le jeton")
        }
      }

      // ON NE JUGE QUE CE QUI A ÉTÉ SAISI. « jeton incomplet : 0 caractères au
      // lieu de 43 » s'affichait sur une page où RIEN n'avait été tapé : un
      // reproche pour un champ vide, avant même le premier mot sur la machine.
      if modele.jetonDisponible(pour: serveur.adresse) {
        let complet = modele.jetonBienForme(pour: serveur.adresse)
        Label(
          complet
            ? "jeton complet (43 caractères)"
            : "jeton incomplet : \(modele.longueurJeton(pour: serveur.adresse)) caractères au lieu de 43",
          systemImage: complet ? "checkmark.seal" : "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(complet ? Color.green : Color.orange)
      }

      // Un `401` propose l'action qui RÉPARE, à portée de pouce : le champ est
      // juste au-dessus. Le rappel n'apparaît que pour cette cause-là — une
      // adresse injoignable ne se règle pas ici, et une machine ÉTEINTE non plus
      // — ET SEULEMENT SUR LA PAGE DE LA MACHINE VISÉE : un `401` parle de la
      // connexion en cours, pas d'une fiche qu'on consulte.
      if modele.jetonRefuseParLeService, ModeleApp.vise(modele.adresse, serveur) {
        VStack(alignment: .leading, spacing: 8) {
          Label(
            "Le service a refusé ce jeton. Collez celui de CET hôte : chaque machine a le sien.",
            systemImage: "key"
          )
          .font(.caption)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)

          // LE COFFRE EN SAIT PARFOIS PLUS QUE LE CHAMP. Quand le jeton détenu
          // n'est PAS celui du coffre de cette machine, l'application le DIT et
          // propose de l'essayer — sans jamais montrer ni recopier le secret.
          // C'est la sortie de secours qui manquait : un jeton étranger refusé
          // laissait l'application bloquée, sans autre issue qu'un recollage.
          if modele.jetonDuCoffreDiffert(pour: serveur.adresse) {
            Text("Le coffre du harness de cette machine contient un AUTRE jeton.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            Button("Essayer le jeton du coffre") {
              modele.adopterLeJetonDuCoffre(pour: serveur.adresse)
              Task { await modele.choisirEtConnecter(serveur) }
            }
            .buttonStyle(.bordered)
            .font(.caption)
          }
        }
      }

      Text("Il s'affiche une seule fois, dans la sortie du harness, au premier chargement du plugin sur cette machine. Il n'est jamais renvoyé par une route.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - 4. Le détail technique

  /// L'ERREUR BRUTE — quand elle apprend quelque chose.
  ///
  /// POURQUOI ELLE EST REPLIÉE, ET PAS SEULEMENT DÉPLACÉE. Le « pavé technique »
  /// affichait en rouge, avec un triangle d'alerte, une phrase en français —
  /// `messageHorsLigne` — que le garde-fou local range dans le même champ que les
  /// erreurs. Ce n'est pas un détail technique, et c'était la troisième fois que
  /// la page disait la même chose. Ne restent donc que les erreurs que RIEN
  /// n'explique : celles-là seules valent un bloc à part, et elles sont aussi
  /// écrites dans `diagnostic.json`.
  @ViewBuilder
  private var detailTechnique: some View {
    if let erreur = erreurInexpliquee {
      DisclosureGroup {
        Text(erreur)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 8)
      } label: {
        Label("Détail technique", systemImage: "text.alignleft")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .padding(14)
      .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
  }

  private var erreurInexpliquee: String? {
    guard cause == nil, modele.serveurVise?.id == serveur.id, let erreur = modele.erreur else {
      return nil
    }
    // « Hors ligne » a sa conclusion, plus haut : la répéter ici en charabia
    // rouge n'apprendrait rien.
    return erreur == ModeleApp.messageHorsLigne(serveur) ? nil : erreur
  }

  // MARK: - La méthode, pour l'étape qui bloque

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
        Text("Allumez cette machine-là, et vérifiez que Tailscale y est connecté :")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        LigneCommande(commande: "tailscale status")
        Text("S'il n'y est pas connecté :")
          .font(.caption)
          .foregroundStyle(.secondary)
        LigneCommande(commande: "tailscale up")
      } else {
        Text("Vérifiez l'état du tailnet, sur cette machine-là ou sur une autre :")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        LigneCommande(commande: "tailscale status")
      }
    case 3:
      if connue {
        DemarchePublicationPort()
      } else {
        Text("Vérifiez sur cette machine ce qui est publié :")
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
