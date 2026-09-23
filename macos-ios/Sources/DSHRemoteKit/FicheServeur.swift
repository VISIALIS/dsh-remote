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
///   3. SES RÉGLAGES — suivi et filtre, repliés. Rien de tout cela n'est une
///      raison d'ouvrir la page ; tout y reste pourtant, parce que chaque réglage
///      vit à l'endroit qui le rend vrai ;
///   4. LE DÉTAIL TECHNIQUE — l'erreur brute, quand elle apprend quelque chose, et
///      elle seule : une phrase en français n'est pas un détail technique.
///
/// LES BANDES 3 ET 4 N'EXISTENT PAS EN MODE AJOUT : il n'y a pas encore de
/// machine dont on puisse régler le suivi ni lire l'erreur.
///
/// LA BANDE 3 A PERDU SON CHAMP DE JETON, ET C'EST UNE DEMANDE DU PROPRIÉTAIRE :
/// « le jeton d'appareil de cet hôte ne correspond plus au contexte actuel des
/// réglages […] quitte à la supprimer ». Il avait raison sur les trois points :
/// le bloc s'appelait « à la main » alors que l'appairage est devenu le chemin
/// normal, il redisait le refus que l'étape 5 dit MIEUX (« c'est celui d'une autre
/// machine. Appairez à nouveau. »), et il vivait dans des « réglages » alors qu'un
/// jeton n'est pas un réglage mais une RÉPARATION — dont le geste est l'appairage.
/// Le suivi et le filtre, eux, restent : ils portent bien sur la connexion à
/// cette machine-là, et c'est le propriétaire qui les y a mis.
struct FicheServeur: View {
  @Bindable var modele: ModeleApp
  /// La machine affichée. `nil` = la page « Ajouter un serveur ».
  let serveur: ServeurMac?
  /// Ouvre la feuille de saisie d'une adresse — la voie manuelle, quand la
  /// découverte ne suffit pas. N'a de sens qu'en mode ajout.
  var surAdresse: () -> Void = {}
  /// PRÉVIENT QUE LA PAGE D'AJOUT A FINI SON TRAVAIL — l'appelant quitte alors la
  /// page d'ajout dans la colonne de détail (macOS, iPad).
  ///
  /// POURQUOI CE RAPPEL EXISTE, ET CE QU'IL RÉPARE. Constaté à l'usage : « quand je
  /// scanne le QR code, il faudrait que la page s'actualise ». L'appairage
  /// réussissait — jeton rangé, connexion faite, sessions chargées — mais la page
  /// d'ajout RESTAIT à l'écran : rien ne la quittait, et son travail est terminé
  /// dès qu'une machine est appairée.
  var surAppairage: () -> Void = {}

  /// LA PAGE POUSSÉE SE DÉPILE ELLE-MÊME (iPhone, iPad).
  ///
  /// Deux fermetures pour un seul fait, parce que les deux plateformes ne
  /// présentent pas la page de la même façon : sur iPhone elle est POUSSÉE dans
  /// une pile — `dismiss` la dépile —, alors que sur macOS et iPad elle occupe la
  /// colonne de détail, où c'est l'état de l'application qui décide de ce qu'on
  /// regarde (`surAppairage`). Sur une vue non présentée, `dismiss` ne fait rien :
  /// on peut donc appeler les deux sans savoir laquelle s'applique.
  @Environment(\.dismiss) private var depiler

  /// Les étapes de CETTE machine — la fabrique est dans le modèle, pour que la
  /// fiche et la barre latérale ne puissent pas diverger.
  private var etapes: [EtapesServeur.Etape] { modele.etapes(pour: serveur) }

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
    // ── OUVRIR LA PAGE REPOSE LA QUESTION — ET C'ÉTAIT NÉCESSAIRE ─────────────
    //
    // Demande du propriétaire : « le diagnostic se met à jour à chaque fois qu'on
    // recharge la page ? Ce serait nécessaire ». Il ne l'était pas, et le défaut
    // était visible : on installe le plugin `dsh-remote` sur MacMini, la machine ne
    // change pas d'état sur le tailnet, l'empreinte de sonde reste identique — et
    // la page continue d'afficher « 4. Le plugin est installé : à faire » alors que
    // c'est fait. Ni rouvrir la page, ni changer de machine puis revenir ne
    // relançaient la sonde : il fallait quitter l'application, ou penser à
    // « Revérifier ».
    //
    // LE DÉLAI DE GARDE VIT DANS LE MODÈLE, PAS ICI : la barre latérale montre le
    // même diagnostic et doit appliquer le même délai. Une vue qui déciderait
    // seule combien de requêtes un aller-retour mérite ferait diverger les deux
    // surfaces dès le premier ajustement.
    //
    // LE MODE AJOUT N'EST PAS CONCERNÉ : il n'y a pas de machine à sonder, et
    // `sonderLesServeurs` laisse alors la liste vide tranquille.
    .task(id: serveur?.id) {
      guard serveur != nil else { return }
      await modele.sonderSiLeDelaiEstPasse()
    }
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

  // MARK: - 2. Le diagnostic

  /// LA DEUXIÈME BANDE — les cinq constats, et la méthode de celui qui bloque.
  ///
  /// ELLE EST DESSINÉE PAR UNE VUE À PART (`DiagnosticDuServeur`), parce que la
  /// barre latérale la montre AUSSI, quand la machine choisie n'est pas appairée :
  /// c'est ce qui garantit que les deux surfaces disent la même chose.
  private var parcours: some View {
    DiagnosticDuServeur(modele: modele, serveur: serveur, surAppairage: surAppairage)
  }

  // MARK: - 3. Les réglages de cette machine

  /// REPLIÉS, MAIS SUR CETTE PAGE. Un réglage vit à l'endroit qui le rend vrai —
  /// le suivi décide si l'on interroge CE serveur, le filtre ce qu'on affiche de
  /// SA liste —, et rien de tout cela n'est une raison d'ouvrir la page. Un bloc
  /// replié satisfait les deux : il est là sans s'interposer entre l'adresse et le
  /// verdict.
  private func reglagesDeLaMachine(_ serveur: ServeurMac) -> some View {
    DisclosureGroup {
      suiviEtFiltre(serveur)
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
    if modele.sertDsh(serveur) == true {
      let dejaVise = modele.serveurChoisi == serveur
      return (
        dejaVise ? L("Reconnecter") : L("Se connecter"), "bolt.horizontal",
        { Task { await modele.choisirEtConnecter(serveur) } }
      )
    } else {
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
}
