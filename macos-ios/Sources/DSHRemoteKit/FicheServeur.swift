import DSHRemoteKit
import SwiftUI

/// LA FICHE D'UN SERVEUR — et la page qui apprend à en ajouter un.
///
/// POURQUOI UNE SEULE VUE POUR DEUX PAGES. « Ajouter un serveur » et la page
/// d'une machine racontaient le même parcours avec deux compositions différentes :
/// l'une empilait un en-tête, les étapes de l'appareil, deux actions et un bloc
/// replié pour le Mac ; l'autre enchaînait une identité, une carte de diagnostic,
/// des réglages et un détail technique. Deux mises en page pour un seul contenu,
/// donc deux endroits à corriger à chaque changement — et deux jeux de méthodes
/// qui avaient DÉJÀ divergé sur les deux premières étapes. Le propriétaire l'a
/// demandé ainsi : « ajouter un serveur devrait garder le même patron ».
///
/// CE QUI CHANGE DE NATURE, ET NON DE FORME. `serveur == nil` veut dire « aucune
/// machine n'est jugée » : la page liste alors le travail à faire (`.objectifs`),
/// et ses deux actions servent à trouver une machine. Sinon, elle JUGE celle
/// qu'on lui donne (`.diagnostic`). C'est la seule différence — le mode —, et il
/// vit dans le modèle (`EtapesServeur.Mode`), pas ici.
///
/// L'ORDRE DES BANDES SUIT LES QUESTIONS QU'ON SE POSE, et rien d'autre :
///
///   1. QUELLE MACHINE, ET DANS QUEL ÉTAT ? — la pastille, la CONCLUSION en une
///      phrase, l'adresse, et UNE action : celle qui peut aboutir dans cet état ;
///   2. S'IL MANQUE QUELQUE CHOSE, QUOI ? — les cinq étapes. Toutes restent
///      visibles (un diagnostic ne cache rien), mais seule celle qui bloque porte
///      sa méthode dépliée : c'est la seule exécutable maintenant, et trois jeux
///      de commandes noient celle qui compte ;
///   3. SES RÉGLAGES — jeton d'appoint, suivi, filtre, repliés. Rien de tout cela
///      n'est une raison d'ouvrir la page ; tout y reste pourtant, parce que
///      chaque réglage vit à l'endroit qui le rend vrai ;
///   4. LE DÉTAIL TECHNIQUE — l'erreur brute, quand elle apprend quelque chose, et
///      elle seule : une phrase en français n'est pas un détail technique.
///
/// LES BANDES 3 ET 4 N'EXISTENT PAS EN MODE AJOUT : il n'y a pas encore de
/// machine dont on puisse régler le jeton ni lire l'erreur.
struct FicheServeur: View {
  @Bindable var modele: ModeleApp
  /// La machine affichée. `nil` = la page « Ajouter un serveur ».
  let serveur: ServeurMac?
  /// Ouvre la feuille de saisie d'une adresse — la voie manuelle, quand la
  /// découverte ne suffit pas. N'a de sens qu'en mode ajout.
  var surAdresse: () -> Void = {}

  private var estAjout: Bool { serveur == nil }

  /// COMMENT LIRE LES ÉTAPES : ce qu'on constate, ou ce qu'il reste à faire.
  ///
  /// Les deux cas vivent dans `EtapesServeur` (`Mode`) : ce qu'ils décident — ce
  /// qui est verrouillé, donc ce qui est ATTEIGNABLE — est une règle, et elle est
  /// éprouvée là-bas.
  private var mode: EtapesServeur.Mode { estAjout ? .objectifs : .diagnostic }

  /// Les étapes de CETTE page, recalculées à chaque rendu : la sonde peut rendre
  /// son verdict entre deux affichages.
  private var etapes: [EtapesServeur.Etape] {
    guard let serveur else {
      return EtapesServeur.etapesDAjout(tailnetDeLAppareil: modele.tailnetDeLAppareil)
    }
    return EtapesServeur.etapes(
      tailnetDeLAppareil: modele.tailnetDeLAppareil,
      enLigne: serveur.enLigne,
      sertDsh: modele.sertDsh(serveur),
      cause: modele.causeSansDsh(serveur),
      appairage: modele.etatAppairage(pour: serveur))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        verdict
        parcours
        if let serveur {
          reglagesDeLaMachine(serveur)
          detailTechnique(serveur)
        }
      }
      .padding(24)
      .frame(maxWidth: 680, alignment: .leading)
      // CENTRÉE, ET NON COLLÉE À GAUCHE. Sur macOS, la colonne de détail est
      // large : une colonne de texte de 680 points tassée contre le bord laissait
      // une bande grise vide à droite, et l'œil ne savait plus où était la page.
      .frame(maxWidth: .infinity, alignment: .center)
    }
    // `L` ET NON `T` : le titre est un `String` dans un cas et une clé dans
    // l'autre, et `T` rend un `Text` — les deux ne se rencontrent pas dans un
    // `??`. Les deux helpers lisent la même table.
    .navigationTitle(serveur?.nom ?? L("Ajouter un serveur"))
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
  }

  // MARK: - 1. Quelle machine, et dans quel état

  @ViewBuilder
  private var verdict: some View {
    if let serveur {
      verdictDeLaMachine(serveur)
    } else {
      verdictDAjout
    }
  }

  private func verdictDeLaMachine(_ serveur: ServeurMac) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 14) {
        Image(systemName: serveur.symbole)
          .font(.system(size: 30))
          .foregroundStyle(serveur.enLigne ? Color.accentColor : Color.secondary)
          .frame(width: 40)
        // LE NOM N'EST PAS RÉPÉTÉ ICI. Il est déjà dans la barre de navigation sur
        // iPhone, et dans la BARRE DE TITRE DE LA FENÊTRE sur macOS — où
        // `NavigationSplitView` reprend le titre de la colonne de détail. Constaté
        // sur capture : « MacMini » s'écrivait deux fois, à quarante points
        // d'écart. L'identité de la bande, c'est l'icône, l'état et l'adresse.
        PastilleDeMachine(description: etat(serveur))
        Spacer(minLength: 8)
        if modele.serveurChoisi == serveur {
          Label { T("serveur courant") } icon: { Image(systemName: "checkmark.circle.fill") }
            .font(.caption)
            .foregroundStyle(Color.accentColor)
        }
      }

      // LA CONCLUSION, EN UNE PHRASE — et c'est la seule fois que l'état se dit en
      // toutes lettres. Elle était dans un bloc « Diagnostic » plus bas, ce qui
      // obligeait à lire quatre constats pour apprendre ce que la page avait à
      // dire. Le verdict vient en tête, là où on le cherche.
      Label(conclusion(serveur).texte, systemImage: conclusion(serveur).symbole)
        .font(.callout.weight(.medium))
        .foregroundStyle(conclusion(serveur).ton.couleur)
        .fixedSize(horizontal: false, vertical: true)

      // L'ADRESSE SE COPIE. Elle est faite pour voyager — la saisir sur un autre
      // appareil, la donner à `curl` — et le composant des commandes fait
      // exactement cela, libellé d'accessibilité compris (« Copier adresse »). Le
      // titre « Adresse » disparaît : une URL sous un nom de machine se lit sans
      // étiquette, et chaque mot retiré est un mot de moins à parcourir.
      LigneCommande(commande: serveur.adresse, libelle: "adresse")

      HStack(spacing: 10) {
        Button {
          actionPrincipale(serveur).geste()
        } label: {
          Label(actionPrincipale(serveur).titre, systemImage: actionPrincipale(serveur).symbole)
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

  /// LA PAGE D'AJOUT — ce qui se fait ICI, et les deux recours.
  ///
  /// POURQUOI LA PHRASE A CHANGÉ. Elle disait « une seule chose est à faire sur
  /// cet appareil : que Tailscale soit connecté ». C'était vrai tant que
  /// l'appairage n'était pas une étape ; il l'est devenu, et il se fait ici
  /// aussi. Une phrase qui compte faux est pire qu'une phrase vague : elle fait
  /// croire qu'il n'y a plus rien à faire après Tailscale.
  private var verdictDAjout: some View {
    VStack(alignment: .leading, spacing: 10) {
      T("Sur cet appareil, deux choses se font : que Tailscale soit connecté, et l'appairage. Tout le reste se passe sur le Mac qui héberge DSH — et l'application le vérifie toute seule, dès qu'une machine répond.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      // LES DEUX RECOURS, quand la découverte ne suffit pas — ou quand on connaît
      // déjà l'adresse. L'appairage, lui, n'est PAS ici : il a son étape, plus
      // bas, et c'est elle qui porte le geste (le QR code, le collage).
      VStack(alignment: .leading, spacing: 8) {
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

  // MARK: - 2. Le parcours

  private var parcours: some View {
    // PAS DE TITRE, ET C'EST VOULU. « Diagnostic », « Le parcours », « Les étapes »
    // : la conclusion est juste au-dessus, et la première ligne s'annonce
    // elle-même. Un titre de plus ne serait qu'un mot de plus à parcourir.
    ParcoursDesEtapes(etapes: etapes, mode: mode) { etape in
      methode(pour: etape)
    }
  }

  // MARK: - 3. Les réglages de cette machine

  /// REPLIÉS, MAIS SUR CETTE PAGE. Deux règles se rencontrent ici : un réglage
  /// vit à l'endroit qui le rend vrai — le jeton est propre à chaque hôte, le
  /// suivi décide si l'on interroge CE serveur —, et rien de tout cela n'est une
  /// raison d'ouvrir la page. Un bloc replié satisfait les deux : il est là sans
  /// s'interposer entre l'adresse et le verdict.
  private func reglagesDeLaMachine(_ serveur: ServeurMac) -> some View {
    DisclosureGroup {
      VStack(alignment: .leading, spacing: 16) {
        jeton(serveur)
        Divider()
        suiviEtFiltre(serveur)
      }
      .padding(.top, 10)
    } label: {
      Label { T("Réglages de cette machine") } icon: { Image(systemName: "slider.horizontal.3") }
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
  private func suiviEtFiltre(_ serveur: ServeurMac) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Toggle(
        isOn: Binding(
          get: { modele.preferences(pour: serveur.adresse).suivi },
          set: { actif in modele.definirPreferences(pour: serveur.adresse) { $0.suivi = actif } })
      ) {
        T("Suivre l'activité")
      }
      Toggle(
        isOn: Binding(
          get: { modele.preferences(pour: serveur.adresse).chargeesSeulement },
          set: { actif in
            modele.definirPreferences(pour: serveur.adresse) { $0.chargeesSeulement = actif }
          })
      ) {
        T("Chargées en mémoire seulement")
      }

      Text(
        modele.serveurVise?.id == serveur.id
          ? L("Ces deux réglages valent pour cet hôte, et s'appliquent maintenant : c'est le serveur connecté. « Chargées » veut dire prêtes à être reprises instantanément, pas en train de travailler.")
          : L("Ces deux réglages valent pour cet hôte et seront appliqués quand vous vous y connecterez.")
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// LE JETON D'APPAREIL, À LA MAIN — le dépannage, plus le chemin principal.
  ///
  /// POURQUOI ICI, ET NON DANS LES RÉGLAGES GÉNÉRAUX — mesuré. Le jeton est tiré
  /// par CHAQUE hôte et rangé dans son coffre : deux Macs qui hébergent le plugin
  /// ont deux jetons distincts, et celui d'une machine ne vaut pas pour une autre.
  /// Un réglage « général » qui ne vaut que pour un hôte serait un mensonge
  /// d'endroit.
  ///
  /// ET C'EST LE JETON DE **CETTE** MACHINE, pas celui de la cible. La page peut
  /// être ouverte sur un hôte auquel on n'est PAS connecté : lire et écrire le
  /// jeton de la cible faisait alors afficher un secret sous le nom d'un autre, et
  /// un jeton collé ici partait vers une machine qui n'est pas celle qu'on
  /// regarde. Toutes les opérations de ce bloc passent donc par `serveur.adresse`.
  ///
  /// CE QUI A ÉTÉ RETIRÉ, ET POURQUOI. Ce bloc portait un paragraphe expliquant
  /// que le jeton ne s'affiche qu'une fois, dans la sortie du harness. C'est vrai,
  /// et cela n'a plus sa place ICI : le chemin normal est l'appairage — l'étape 5,
  /// juste au-dessus —, qui remplit l'adresse ET le jeton d'un seul geste. Le
  /// champ reste pour ce qu'il est devenu : la porte de service, quand on a le
  /// jeton sous la main et rien d'autre à faire.
  private func jeton(_ serveur: ServeurMac) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      T("Jeton d'appareil de cet hôte — à la main")
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack(spacing: 8) {
        SecureField(
          modele.jetonDisponible(pour: serveur.adresse)
            ? L("déjà enregistré — saisir pour remplacer") : L("jeton d'appareil"),
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
          .accessibilityLabel(T("Coller le jeton depuis le presse-papier"))
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
          .accessibilityLabel(T("Coller le jeton depuis le presse-papier"))
        #endif
        if modele.jetonDisponible(pour: serveur.adresse) {
          Button {
            modele.effacerJeton(pour: serveur.adresse)
          } label: {
            Image(systemName: "xmark.circle")
          }
          .buttonStyle(.borderless)
          .cibleTactile()
          .accessibilityLabel(T("Effacer le jeton"))
        }
      }

      // ON NE JUGE QUE CE QUI A ÉTÉ SAISI. « jeton incomplet : 0 caractères au
      // lieu de 43 » s'affichait sur une page où RIEN n'avait été tapé : un
      // reproche pour un champ vide, avant même le premier mot sur la machine.
      if modele.jetonDisponible(pour: serveur.adresse) {
        let complet = modele.jetonBienForme(pour: serveur.adresse)
        Label(
          complet
            ? L("jeton complet (43 caractères)")
            : L("jeton incomplet :") + " \(modele.longueurJeton(pour: serveur.adresse)) " + L("caractères au lieu de 43"),
          systemImage: complet ? "checkmark.seal" : EtatVisuel.attention.symbole
        )
        .font(.caption)
        .foregroundStyle((complet ? EtatVisuel.pret : .attention).couleur)
      }

      // Un `401` propose l'action qui RÉPARE, à portée de pouce : le champ est
      // juste au-dessus. Le rappel n'apparaît que pour cette cause-là — une
      // adresse injoignable ne se règle pas ici, et une machine ÉTEINTE non plus
      // — ET SEULEMENT SUR LA PAGE DE LA MACHINE VISÉE : un `401` parle de la
      // connexion en cours, pas d'une fiche qu'on consulte.
      if modele.jetonRefuseParLeService, ModeleApp.vise(modele.adresse, serveur) {
        VStack(alignment: .leading, spacing: 8) {
          Label { T("Le service a refusé ce jeton. Collez celui de CET hôte : chaque machine a le sien.") } icon: { Image(systemName: "key") }
          .font(.caption)
          .foregroundStyle(EtatVisuel.attention.couleur)
          .fixedSize(horizontal: false, vertical: true)

          // LE COFFRE EN SAIT PARFOIS PLUS QUE LE CHAMP. Quand le jeton détenu
          // n'est PAS celui du coffre de cette machine, l'application le DIT et
          // propose de l'essayer — sans jamais montrer ni recopier le secret.
          // C'est la sortie de secours qui manquait : un jeton étranger refusé
          // laissait l'application bloquée, sans autre issue qu'un recollage.
          if modele.jetonDuCoffreDiffert(pour: serveur.adresse) {
            T("Le coffre du harness de cette machine contient un AUTRE jeton.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            Button(L("Essayer le jeton du coffre")) {
              modele.adopterLeJetonDuCoffre(pour: serveur.adresse)
              Task { await modele.choisirEtConnecter(serveur) }
            }
            .buttonStyle(.bordered)
            .font(.caption)
          }
        }
      }
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
  private func detailTechnique(_ serveur: ServeurMac) -> some View {
    if let erreur = erreurInexpliquee(serveur) {
      DisclosureGroup {
        Text(erreur)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 8)
      } label: {
        Label { T("Détail technique") } icon: { Image(systemName: "text.alignleft") }
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .padding(14)
      .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
  }

  private func erreurInexpliquee(_ serveur: ServeurMac) -> String? {
    guard modele.causeSansDsh(serveur) == nil, modele.serveurVise?.id == serveur.id,
      let erreur = modele.erreur
    else {
      return nil
    }
    // « Hors ligne » a sa conclusion, plus haut : la répéter ici en charabia
    // rouge n'apprendrait rien.
    return erreur == ModeleApp.messageHorsLigne(serveur) ? nil : erreur
  }

  // MARK: - L'état, la conclusion, l'action

  /// L'ÉTAT DE LA MACHINE, dit dans les mots partagés avec le panneau latéral.
  private func etat(_ serveur: ServeurMac) -> EtatMachine.Description {
    EtatMachine.decrire(
      enLigne: serveur.enLigne,
      sertDsh: modele.sertDsh(serveur),
      estLocal: serveur.estLocal,
      appairage: modele.etatAppairage(pour: serveur),
      court: false)
  }

  private func conclusion(_ serveur: ServeurMac) -> EtatMachine.Description {
    // L'APPAIRAGE N'EST PAS PASSÉ ICI : il est DÉJÀ dans les étapes, et
    // `EtatMachine.conclusion` ne fait que mettre en mots ce que la liste dit.
    // Le lui donner une seconde fois ouvrirait la porte à deux vérités.
    EtatMachine.conclusion(enLigne: serveur.enLigne, etapes: etapes)
  }

  /// L'ACTION PRINCIPALE — celle qui peut ABOUTIR dans l'état où est la machine.
  ///
  /// POURQUOI ELLE CHANGE, ET PAS SEULEMENT SON LIBELLÉ. « Se connecter » était
  /// offert à toutes les machines, y compris celles dont on sait déjà qu'elles ne
  /// répondront pas : le garde-fou local évite la requête, mais le seul résultat
  /// possible restait un message disant que la machine est éteinte. Une page qui
  /// met en avant une action sans issue fait douter de tout ce qu'elle affiche.
  private func actionPrincipale(_ serveur: ServeurMac) -> (
    titre: String, symbole: String, geste: () -> Void
  ) {
    guard serveur.enLigne else {
      if let autre = autreMacJoignable(serveur) {
        return (
          L("Choisir") + " \(autre.premierMot)", "arrow.triangle.swap",
          { Task { await modele.choisirEtConnecter(autre) } }
        )
      }
      // Aucun autre Mac joignable : la seule chose utile est de redemander la
      // liste — le Mac a pu être rallumé depuis la dernière découverte.
      return (
        L("Rafraîchir la liste"), "arrow.clockwise",
        { Task { await modele.synchroniserServeurs() } }
      )
    }
    switch modele.sertDsh(serveur) {
    case true:
      let dejaVise = modele.serveurChoisi == serveur
      return (
        dejaVise ? L("Reconnecter") : L("Se connecter"), "bolt.horizontal",
        { Task { await modele.choisirEtConnecter(serveur) } }
      )
    case false, nil:
      // LA MACHINE RÉPOND, mais rien ne dit encore que DSH y est. Deux gestes,
      // selon qu'elle est ou non celle que l'application VISE : si c'est elle, on
      // reteste son adresse — seul moyen de vérifier une adresse saisie à la
      // main, que la sonde ne voit pas puisqu'elle ne parcourt que le tailnet ;
      // sinon on redemande son verdict à la sonde, sans changer de cible.
      if ModeleApp.vise(modele.adresse, serveur) {
        return (L("Revérifier"), "stethoscope", { Task { await modele.testerAdresse() } })
      }
      return (L("Revérifier"), "stethoscope", { Task { await modele.sonderLesServeurs() } })
    }
  }

  /// Un AUTRE Mac joignable, s'il y en a un.
  ///
  /// On préfère celui dont la sonde a dit qu'il sert DSH : envoyer l'utilisateur
  /// vers une machine « en ligne » qui ne publie rien remplacerait une impasse
  /// par une autre. La liste est prise dans l'ordre d'AFFICHAGE (le serveur
  /// connecté en tête) : à mérite égal, c'est la machine qu'on voit en premier
  /// qui est proposée — celle-ci exclue, puisqu'il s'agit d'« un autre ».
  private func autreMacJoignable(_ serveur: ServeurMac) -> ServeurMac? {
    let autres = modele.serveursAffiches.filter { $0.id != serveur.id && $0.enLigne }
    return autres.first { modele.sertDsh($0) == true } ?? autres.first
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
    BoutonsAppairage(modele: modele, prominent: estAjout)

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
}
