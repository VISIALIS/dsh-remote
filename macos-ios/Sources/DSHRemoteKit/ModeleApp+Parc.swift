import Foundation

/// LE PARC — quelles machines existent, laquelle est visée, et laquelle sert DSH.
///
/// POURQUOI CE FICHIER EXISTE. C'est le domaine où se prennent les décisions que
/// l'utilisateur VOIT : quelle machine est visée, laquelle est proposée par défaut,
/// quand basculer, et ce que la sonde a constaté. Ses règles sont nées de défauts
/// constatés — la « génération » (une réponse partie vers l'ancienne machine ne doit
/// pas s'écrire sous la nouvelle), la sélection qui ne remplace qu'au lancement (une
/// cible remplacée vide les sessions et les espaces de travail), la sonde qui ne
/// réinterroge pas une liste inchangée, et la machine éteinte qui n'est PAS sondée
/// (on ne paie pas un délai pour un verdict déjà connu).
///
/// LA CONTRAINTE, RAPPELÉE ICI : une extension Swift ne porte pas de propriété
/// stockée. L'état du parc — `serveurs`, `sonde`, `cible`, `serveurOuvert`,
/// `empreinteSondee`, `tacheServeurs`, `sourceServeurs`, `adressesDeCetAppareil` —
/// reste dans la classe ; ses méthodes vivent ici.
///
/// CE QUE CE DÉPLACEMENT COÛTE, ET QUI EST ASSUMÉ : les membres que ces méthodes
/// touchent passent de `private` à `internal`, y compris les setters `private(set)`
/// de `serveurs`, `sonde`, `cible` et `serveurOuvert`. La surface PUBLIQUE ne change
/// pas ; un autre fichier du module peut désormais écrire ces champs.
extension ModeleApp {

  /// LE SEUL endroit qui remplace la cible.
  ///
  /// Ellecharge aussi le jeton QUI VA AVEC : puisque chaque hôte a le sien
  /// (mesuré), changer de machine sans changer de jeton enverrait à l'une le
  /// secret de l'autre.
  func viser(_ nouvelle: Cible) {
    cible = nouvelle
    // La cible a changé : tout ce qui était en vol décrivait l'ancienne.
    generation += 1
    // LE CONSTAT DE SONDE APPARTENAIT À L'ANCIENNE CIBLE, et il est oublié ICI —
    // au seul endroit qui remplace la cible — parce que c'est un fait de
    // L'ENSEMBLE QUE CET HÔTE VOIT : un autre hôte en voit d'autres. Le garder
    // ferait sauter la sonde sur la nouvelle machine, et les vignettes
    // resteraient sur le verdict de l'ancien réseau.
    //
    // POSÉ ICI, ET NON DANS `oublierLesDonneesDeLancienServeur` : une adresse
    // saisie à la main passe par `viser` SANS passer par cette remise à zéro —
    // c'est mesuré, le premier emplacement ne suffisait pas.
    empreinteSondee = nil
    chargerJetonDeLaCible()
  }

  /// Liste des machines du TAILNET — **sans** garde de génération, et c'est
  /// délibéré : c'est un fait du tailnet, pas une donnée d'un serveur. La jeter
  /// parce que la cible a bougé viderait la liste sous les yeux de l'utilisateur
  /// au moment précis où il choisit une machine.
  func appliquerServeursDuTailnet(_ liste: [ServeurMac], diagnostic: String?) {
    serveurs = liste
    diagnosticServeurs = diagnostic
    sourceServeurs = .tailscaleLocal
    // LES ADRESSES DE CET APPAREIL, APPRISES ICI ET NULLE PART AILLEURS.
    //
    // POURQUOI CE N'EST PAS `estLocal` LU À LA DEMANDE. Le marqueur `local` d'une
    // liste reçue dit « je suis l'hôte que tu interroges » — pas « je suis la
    // machine qui exécute cette application ». MacMini se marque donc LUI-MÊME
    // local dans sa propre liste, et l'application a cru que son adresse était la
    // sienne : elle lui a présenté le jeton du coffre LOCAL (43 caractères,
    // empreinte `cacde495`, `401` mesuré). Ce que la découverte LOCALE marque
    // `local`, en revanche, est bien CETTE machine — c'est le seul endroit d'où ce
    // fait peut venir, et il est conservé ici.
    adressesDeCetAppareil = Set(
      liste.filter(\.estLocal).map { IdentiteHote.cle($0.adresse) }.filter { !$0.isEmpty })
    relireEtatTailscale()
    // Après une réponse, on n'écrase pas une cible : on rattache seulement.
    assurerUneSelection(auLancement: false, listeVientDeLHote: false)
  }

  /// Liste des machines publiée PAR L'HÔTE — donnée d'un serveur, donc gardée.
  func appliquerServeursDeLhote(_ liste: ListeServeurs, vu generationVue: Int) {
    guard reponseEncoreValable(generationVue) else { return }
    serveurs = liste.serveurs
    // Le DIAGNOSTIC de l'hôte fait partie de la réponse : sans lui, une liste
    // vide n'explique rien — tailnet vide, Tailscale arrêté, binaire introuvable
    // ne se corrigent pas de la même façon.
    diagnosticServeurs = liste.diagnostic
    sourceServeurs = .hote
    // LE CAS DU DÉFAUT, ET LE SEUL ENDROIT OÙ IL POUVAIT ÊTRE CORRIGÉ. Sur
    // iPhone, cette liste arrive APRÈS la connexion : sans cet appel, la coche
    // n'apparaissait sur aucune vignette et le panneau des espaces restait vide.
    // C'est aussi le seul cas où le marqueur `estLocal` de la liste est un FAIT :
    // l'hôte se désigne lui-même, et c'est lui qu'on interroge.
    assurerUneSelection(auLancement: false, listeVientDeLHote: true)
  }

  /// Interroge chaque Mac pour savoir s'il sert DSH.
  ///
  /// Les sondes partent ENSEMBLE : une machine éteinte ne doit pas retarder les
  /// autres. Le délai est court — deux secondes et demie — parce qu'un Mac qui
  /// publie DSH répond en quelques millisecondes sur le tailnet, et qu'un Mac
  /// muet ne mérite pas qu'on l'attende.
  public func sonderLesServeurs() async {
    // ── ON SONDE SANS PORTEUR, ET C'EST UNE RÈGLE DE SÉCURITÉ ────────────────
    //
    // La sonde interroge les machines d'un tailnet qui NE SONT PAS la cible :
    // leur présenter le jeton de la cible ferait voyager un secret vers des hôtes
    // qui n'en ont aucun besoin, et chacun d'eux pourrait le rejouer. Or ce jeton
    // n'apprend rien ici — la question est « y a-t-il un DSH en face ? », et un
    // `401` y répond aussi bien qu'un `200`, puisque le service a répondu. C'est
    // la règle du modèle (chaque hôte a SON jeton) poussée jusqu'au bout : un
    // porteur ne se présente qu'à l'hôte dont il est le secret.
    //
    // ON SONDE MÊME SANS JETON — ET C'EST UNE CORRECTION, PAS UN OUBLI.
    //
    // Il y avait ici une garde : `guard jeton.count == 43`, avec pour raison
    // « sans jeton, aucune sonde n'est possible ». La raison était FAUSSE, et le
    // prix était le pire des mensonges de cette application : un appareil non
    // appairé ne sondait rien, publiait un verdict VIDE, et la vignette en
    // concluait « pas de DSH » — donc envoyait installer un plugin déjà installé
    // sur une machine parfaitement prête.
    //
    // `Sonde.interroger` compte déjà un `401` comme « DSH est là » : un jeton
    // refusé PROUVE que le service a répondu. Le jeton vide ne l'empêche donc
    // pas de mesurer le port et le plugin, qui ne dépendent pas de nous. Ce qui
    // manque, l'appairage, est une AUTRE question — et elle a désormais son
    // étape (`EtapesServeur`, cinquième), au lieu d'être confondue avec celle-ci.
    //
    // CE QUI RESTE VRAI, ET QUI RESTE GARDÉ : une liste VIDE n'est pas un
    // verdict — c'est une course, la sonde étant lancée avant que Tailscale ait
    // rendu sa liste. La déclarer « effectuée » empêchait à jamais tout verdict :
    // mesuré, toutes les icônes restaient ORANGE.
    guard !serveurs.isEmpty else { return }
    // ON NE SONDE QUE CE QUI PEUT RÉPONDRE. Interroger une machine que Tailscale
    // dit hors ligne, c'est payer un délai pour un verdict déjà connu — et
    // annoncer « pas de DSH » là où la seule vérité est « elle est éteinte ».
    // Mesuré : la sonde partait sur 3 candidats dont un Mac éteint depuis des
    // mois. Les machines hors ligne ne sont pas sondées, et leur légende reste
    // « hors ligne », ce qui est exactement ce qu'on sait d'elles.
    let candidats = serveurs.filter(\.enLigne)
    guard !candidats.isEmpty else {
      // Aucune machine joignable : verdict vide, et non « inconnu ».
      sonde = .connue(Sonde.Verdict())
      return
    }
    // On ne repasse PAS par « en cours » si un verdict est déjà connu : les
    // légendes ne doivent pas repartir de zéro à chaque rafraîchissement.
    if case .inconnue = sonde { sonde = .enCours }
    // ON NE REMET PAS LE VERDICT À ZÉRO PENDANT UN RAFRAÎCHISSEMENT.
    //
    // `sondageEffectue = false` était posé ici, à chaque sonde — donc toutes les
    // quinze secondes. Les légendes repassaient alors à « vérification… » le
    // temps de la sonde, et l'écran paraissait ne jamais conclure : c'est
    // exactement ce que le propriétaire a photographié deux fois, alors que la
    // sonde rendait son verdict en moins d'une seconde. Un verdict CONNU reste
    // affiché pendant qu'on le rafraîchit ; il n'est remis à « inconnu » que
    // lorsqu'il n'y en a jamais eu.
    let debutSonde = Date()
    Trace.siActive("[sonde] debut : \(candidats.count) candidat(s), deja annulee=\(Task.isCancelled)")

    let verdict = await sondeur.interroger(candidats)
    // ── UNE SONDE ANNULÉE N'EST PAS UN VERDICT ──────────────────────────────
    //
    // MESURÉ, ET C'EST UN FAUX NÉGATIF. La sonde est relancée à chaque
    // changement de liste, et SwiftUI ANNULE la précédente. Or une requête
    // annulée lève, le `catch` la range en « pas de DSH », et le groupe rend
    // donc un verdict VIDE — qui écrasait le bon. Le journal de l'application
    // montre exactement la suite : `fin : 1 serveur(s) DSH sur 2`, puis
    // `fin : 0 serveur(s) DSH sur 2`, sans qu'aucune machine ait changé d'état.
    //
    // On ne publie donc un résultat que si la sonde est allée au bout.
    let duree = Int(Date().timeIntervalSince(debutSonde) * 1000)
    // ON NE PUBLIE RIEN POUR UNE SONDE QUI N'A PAS ÉTÉ JUSQU'AU BOUT, et on ne
    // note pas non plus qu'elle a eu lieu : une sonde annulée doit pouvoir être
    // redemandée par la boucle suivante, sinon le verdict resterait vide.
    guard !Task.isCancelled else {
      Trace.siActive("[sonde] ANNULEE apres \(duree) ms — verdict non publie")
      return
    }
    sonde = .connue(verdict)
    // CE QUI SE RETIENT, C'EST CE QUI A ÉTÉ INTERROGÉ. L'empreinte est celle de
    // `candidats` — l'ensemble réellement sondé —, et non celle de la liste
    // entière : y mêler une machine hors ligne ferait croire qu'on a mesuré
    // quelque chose sur elle, alors qu'elle n'a reçu aucune requête.
    empreinteSondee = ModeleApp.empreinteDeSonde(candidats)
    Trace.siActive(
      "[sonde] fin : \(verdict.serventDsh.count) serveur(s) DSH sur \(candidats.count) en \(duree) ms, "
        + "\(verdict.causes.count) cause(s) connue(s)")
  }

  /// Le Mac sert-il DSH, d'après la dernière sonde ?
  ///
  /// `nil` veut dire « pas encore su » — et l'interface ne doit pas transformer
  /// ce doute en affirmation. C'est la leçon de `macmini`.
  public func sertDsh(_ serveur: ServeurMac) -> Bool? {
    // « Pas encore su » : c'est l'ABSENCE de verdict qui compte, pas la
    // présence d'un résultat. Un ensemble vide après une sonde complète est un
    // verdict : aucun Mac ne sert DSH.
    switch sonde {
    case let .connue(verdict): return verdict.serventDsh.contains(serveur.id)
    // « En cours » n'est pas un verdict : pendant un rafraîchissement, on rend
    // donc l'ANCIEN, qui reste affiché (voir le commentaire de `sonderLesServeurs`).
    case .inconnue, .enCours: return nil
    }
  }

  /// Change l'adresse ET la mémorise immédiatement.
  ///
  /// POURQUOI PAS SEULEMENT APRÈS UNE CONNEXION RÉUSSIE. C'était le défaut :
  /// l'adresse n'était enregistrée que par `connecter()`, donc une tentative
  /// échouée — jeton absent, faute de frappe, serveur éteint — ne laissait
  /// aucune trace, et l'ouverture suivante repartait du champ vide. Or c'est
  /// précisément quand la connexion échoue qu'on veut retrouver son adresse.
  ///
  /// L'adresse n'est pas un secret : la mémoriser à la frappe ne coûte rien.
  /// Le jeton, lui, ne suit PAS ce chemin et reste confié au seul trousseau.
  public func definirAdresse(_ valeur: String) {
    let effective = ModeleApp.adresseEffective(valeur)
    // Le nom et la machine suivent l'adresse : si elle correspond à une machine
    // découverte, on la reconnaît ; sinon on n'affirme RIEN (le nom reste vide,
    // et l'icône se déduit de l'adresse).
    let machine = ModeleApp.serveurA(adresse: effective, dans: serveurs)
    viser(Cible(adresse: effective, nom: machine?.nom, machine: machine))
    memoriserPreference()
  }

  /// Lance la découverte LOCALE hors du fil principal.
  ///
  /// POURQUOI PAS DANS `init`. La découverte exécute un processus
  /// (`tailscale status --json`) : la lancer pendant l'initialisation du modèle
  /// bloquerait l'affichage de la fenêtre tant que le processus n'a pas rendu
  /// la main. L'interface doit s'afficher immédiatement, la liste se remplir
  /// ensuite — ou jamais, sans que cela se voie.
  ///
  /// Sur iPhone, il n'y a rien à lancer : voir `chargerServeursDeLhote()`, qui
  /// interroge le serveur déjà joint — la seule voie possible depuis iOS.
  /// Découverte locale, ATTENDABLE.
  ///
  /// `demarrerDecouverte` lance une tâche détachée : c'est ce qu'il faut pour
  /// l'affichage, pas pour un démarrage qui doit connaître la liste avant de se
  /// connecter. Ici, on attend le résultat.
  public func chargerServeursLocaux() async {
    guard decouverteLocalePossible else { return }
    let trouvees = await Task.detached { DecouverteServeurs.machinesDuTailnet() }.value
    let raison = DecouverteServeurs.diagnostic
    // L'hôte a déjà répondu, et sa liste est plus fraîche : on ne l'écrase pas.
    guard sourceServeurs != .hote else { return }
    appliquerServeursDuTailnet(trouvees, diagnostic: raison)
  }

  public func demarrerDecouverte() {
    guard decouverteLocalePossible else { return }
    Task.detached { [weak self] in
      let trouvees = DecouverteServeurs.machinesDuTailnet()
      let raison = DecouverteServeurs.diagnostic
      await MainActor.run {
        guard let self else { return }
        // L'hôte a déjà répondu, et sa liste est plus fraîche que celle d'un
        // processus lancé avant la connexion : on ne l'écrase pas.
        guard self.sourceServeurs != .hote else { return }
        self.appliquerServeursDuTailnet(trouvees, diagnostic: raison)
        // La liste vient d'arriver : c'est le moment de refaire les constats
        // locaux sur Tailscale, qui décident de la première étape du parcours.
        self.relireEtatTailscale()
        // La sonde ne part PAS d'ici : à cet instant la liste vient d'être
        // posée, mais la vue n'a pas encore été réévaluée. C'est
        // `task(id: modele.empreinteServeurs)` qui s'en charge, et lui seul —
        // un appel ici ne ferait que doubler la sonde.
      }
    }
  }

  /// Demande la liste à l'hôte déjà joint — la voie qui fonctionne sur iPhone.
  ///
  /// Sans bruit en cas d'échec : l'utilisateur n'a rien demandé, et une liste
  /// qui ne vient pas ne doit pas effacer celle qu'il a sous les yeux.
  ///
  /// LA SONDE NE REPART QUE SI LA LISTE A CHANGÉ, et c'est un correctif chiffré,
  /// pas une coquetterie. Cette méthode est appelée par la boucle de
  /// synchronisation toutes les quinze secondes ; la sonde, elle, interroge
  /// `/v1/sante` sur CHAQUE machine en ligne — quatre requêtes en parallèle, sur
  /// un iPhone, toutes les quinze secondes, pour un verdict qui ne peut pas
  /// changer tant que la liste est la même. L'empreinte qui sert à ça existait
  /// déjà (`empreinteServeurs`), et son commentaire annonçait exactement cette
  /// économie : elle n'était vérifiée que par la vue, jamais par cette boucle.
  ///
  /// Le geste explicite garde son effet : « Revérifier » appelle la sonde
  /// directement, sans passer par ici.
  func chargerServeursDeLhote() async {
    guard hoteEstJoint else { return }
    guard let liste = try? await transport.serveursDeLhote(adresse: adresse, jeton: jetonDeLaCible())
    else {
      Trace.siActive("[demarrage] liste des serveurs : ECHEC")
      return
    }
    Trace.siActive("[demarrage] liste des serveurs : \(liste.serveurs.count)")
    appliquerServeursDeLhote(liste, vu: generationDuDepart())
    relireEtatTailscale()
    // L'EMPREINTE EST CELLE DE L'ENSEMBLE SONDÉ, pas de la liste entière. Une
    // machine HORS LIGNE n'est jamais interrogée — c'est délibéré, et mesuré : on
    // ne paie pas un délai pour un verdict déjà connu. Son entrée ou sa sortie de
    // la liste ne change donc RIEN aux requêtes qui partent, et relancer la sonde
    // pour elle ferait exactement ce qu'on veut éviter.
    let empreinte = ModeleApp.empreinteDeSonde(serveurs.filter(\.enLigne))
    guard empreinte != empreinteSondee else {
      Trace.siActive("[sonde] liste inchangee (\(empreinte)) : aucune sonde envoyee")
      return
    }
    // On demande à chaque Mac s'il sert DSH, plutôt que de le supposer.
    await sonderLesServeurs()
  }

  /// Choisit un serveur et met l'adresse en conséquence.
  ///
  /// L'adresse n'est plus un champ que l'on remplit : elle DÉCOULE du choix.
  /// Le champ reste modifiable pour les cas que la découverte ne couvre pas.
  ///
  /// CHANGER DE SERVEUR VIDE CE QUI VIENT DU PRÉCÉDENT, et c'est un défaut
  /// mesuré : le propriétaire a choisi MacMini, la connexion a échoué, et la
  /// liste a continué d'afficher les 11 sessions de `macbook-air` — avec la
  /// coche sur MacMini. L'écran affirmait donc une chose fausse : que ces
  /// sessions venaient du serveur coché. Une liste qui ne se vide pas quand sa
  /// source change est pire qu'une liste vide : elle est crédible et fausse.
  ///
  /// On vide donc sessions et journal dès que l'adresse visée change vraiment.
  /// La comparaison porte sur l'ADRESSE, pas sur l'identité du serveur : deux
  /// entrées de la découverte peuvent mener à la même machine, et re-vider dans
  /// ce cas ferait clignoter la liste pour rien.
  public func choisir(_ serveur: ServeurMac) {
    // Un avis de bascule ne survit PAS à un choix de l'utilisateur : il
    // racontait ce que l'application avait décidé au démarrage, et il restait
    // affiché ensuite — mesuré : « <adresse> ne répond pas : basculé sur … »
    // sous une liste chargée, alors que plus rien n'était en cause.
    let adresseAvant = adresse
    // Un avis de bascule ne survit PAS à un choix de l'utilisateur : la cible
    // est reconstruite sans lui.
    viser(Cible(adresse: serveur.adresse, nom: serveur.nom, machine: serveur))
    memoriserPreference()
    if adresse != adresseAvant { oublierLesDonneesDeLancienServeur() }
    relireEtatTailscale()
  }

  /// L'application change ELLE-MÊME de machine, et le dit.
  ///
  /// Passe par `choisir` — même transition que l'utilisateur, donc mêmes
  /// conséquences — puis ajoute l'avis, qui est la seule chose en plus.
  func basculer(sur machine: ServeurMac, avis: String) {
    choisir(machine)
    var nouvelle = cible
    nouvelle.avis = avis
    viser(nouvelle)
  }

  /// GARANTIT QU'UNE MACHINE EST SÉLECTIONNÉE DÈS QU'IL Y EN A UNE.
  ///
  /// LA RÈGLE EST DANS `SelectionParDefaut`, et elle est éprouvée là-bas : la
  /// machine jointe d'abord (un fait), la première de la liste affichée ensuite —
  /// mais seulement au lancement, jamais après une réponse de l'hôte.
  ///
  /// ELLE EST APPELÉE LÀ OÙ LA LISTE DEVIENT CONNUE, et pas seulement au
  /// démarrage : sur iPhone, c'est la réponse de l'hôte qui apporte la liste,
  /// donc bien après le début du lancement. C'est exactement l'ordre qui cachait
  /// le défaut : la coche n'apparaissait jamais, et les espaces de travail non
  /// plus.
  func assurerUneSelection(auLancement: Bool, listeVientDeLHote: Bool) {
    if cible.machine == nil {
      let liste = serveursAffiches
      if let reconnue = SelectionParDefaut.aSelectionner(
        parmi: liste, adresse: adresse, listeVientDeLHote: listeVientDeLHote,
        remplacerFauteDeMieux: auLancement)
      {
        switch reconnue {
        case let .jointe(machine), let .hote(machine):
          // ON ATTACHE, ON NE REMPLACE PAS — dans les DEUX cas, y compris quand
          // l'adresse diffère. C'est ce que l'hôte qui se désigne lui-même a
          // appris au simulateur : remplacer l'adresse de boucle locale par celle
          // du tailnet a vidé les six sessions et les sept espaces de travail qui
          // venaient d'être chargés, pour la seule raison qu'on changeait
          // d'écriture d'adresse.
          attacherLaMachine(machine)
        case let .premiere(machine):
          // Là seulement, la cible est REMPLACÉE : au lancement, l'adresse
          // courante ne désigne personne, et la première machine de la liste est
          // le meilleur choix — l'appelant se connecte juste après.
          choisir(machine)
        }
      }
    }
    // AU LANCEMENT, LA PAGE DE LA MACHINE SÉLECTIONNÉE EST OUVERTE : l'écran de
    // droite ne reste pas vide, il explique la machine qu'on a sous les yeux.
    //
    // POURQUOI CE N'EST PAS DANS LE BLOC CI-DESSUS, ET CE QUE LA CAPTURE A MONTRÉ.
    // Le chargeur de liste (`chargerServeursLocaux`) appelle le même invariant
    // AVANT le démarrage : la machine est donc DÉJÀ attachée quand on arrive ici,
    // le bloc ne s'exécute pas, et le volet affichait l'écran de sélection au lieu
    // de la page — vu à l'écran, pas déduit. L'ouverture doit donc dépendre de
    // l'état, pas du chemin qui y a mené.
    //
    // AILLEURS ON N'OUVRE RIEN : un appui sur une autre vignette sélectionne et
    // recharge ses sessions et ses espaces, et c'est le SECOND appui qui ouvre.
    if auLancement, serveurOuvert == nil, let choisie = serveurChoisi { ouvrirPage(choisie) }
  }

  /// Démarrage : choisir une machine JOIGNABLE, puis se connecter.
  ///
  /// POURQUOI CET ORDRE, ET CE QU'IL CORRIGE. La vue appelait `connecter()` des
  /// l'affichage, sur l'adresse mémorisée — même si la machine était ÉTEINTE.
  /// L'utilisateur voyait donc un échec de transport au lancement, avant d'avoir
  /// rien demandé : mesuré sur ce Mac, à propos d'un MacBook Pro hors ligne
  /// depuis 206 jours. Ajuster APRÈS la connexion ne suffisait pas — l'erreur
  /// était déjà à l'écran.
  ///
  /// On charge donc la liste d'abord, on écarte les machines hors ligne, et on
  /// ne connecte qu'ensuite. Le repli est la boucle locale : sur le Mac qui
  /// exécute le harness, elle répond toujours, et elle est la SEULE source
  /// possible avant qu'un serveur ait été joint (c'est lui qui publie le
  /// tailnet).
  public func demarrer() async {
    if sourceServeurs == .aucune, !decouverteLocalePossible, serveurs.isEmpty {
      // Aucune liste locale possible (iPhone) : on tente l'adresse mémorisée.
      await connecter()
      return
    }
    if decouverteLocalePossible { await chargerServeursLocaux() }
    await ajusterAuParc()
    // AU LANCEMENT, ET LÀ SEULEMENT, on peut remplacer faute de mieux : la liste
    // affichée est en ligne d'abord, donc « le premier » est le premier joignable.
    assurerUneSelection(auLancement: true, listeVientDeLHote: false)
    guard !adresse.isEmpty else { return }
    await connecter()
  }

  /// Préfère un serveur EN LIGNE à celui qui a été mémorisé — sur preuve.
  ///
  /// POURQUOI CE N'EST PAS UNE TRAHISON DU CHOIX DE L'UTILISATEUR. L'application
  /// mémorise la dernière machine utilisée, et s'y connecte au lancement — même
  /// si elle est ÉTEINTE. Mesuré : au démarrage, un échec de transport
  /// s'affichait avant toute action, à propos d'un Mac hors ligne depuis 206
  /// jours. Un écran d'erreur au lancement n'est pas une information : c'est un
  /// bruit que l'utilisateur n'a pas provoqué.
  ///
  /// On ne bascule PAS silencieusement : on le DIT (`choixAjuste`), et on ne
  /// touche à rien si la machine mémorisée répond. Le choix reste celui de
  /// l'utilisateur dès qu'elle est joignable.
  public func ajusterAuParc() async {
    guard !serveurs.isEmpty else { return }
    guard let enLigne = ModeleApp.cibleDeBascule(
      serveurs: serveurs, choisie: serveurChoisi, echec: echecCible, adresse: adresse)
    else { return }

    // L'avis se calcule AVANT la transition, et sur l'ANCIENNE cible : après,
    // l'échec a été remis à zéro et l'adresse a changé — l'avis parlerait alors
    // de la machine sur laquelle on vient de basculer. C'est exactement ce que
    // le test a attrapé : « ne répond pas » au lieu de « est hors ligne ».
    let visee = echecCible?.adresse ?? adresse
    let etiquette = serveurChoisi?.nom ?? (visee.isEmpty ? "le serveur mémorisé" : visee)
    let horsLigne = echecCible?.raison == .horsLigne
    let avis =
      horsLigne
      ? "« \(etiquette) » est hors ligne sur le tailnet : basculé sur « \(enLigne.nom) », qui est en ligne."
      : "« \(etiquette) » ne répond pas : basculé sur « \(enLigne.nom) », qui est en ligne."

    // UNE SEULE TRANSITION : elle choisit la machine — donc remet l'échec à zéro,
    // car c'est une autre cible — vide les données de l'ancienne, et laisse
    // l'avis. L'erreur affichée ne survit pas non plus.
    basculer(sur: enLigne, avis: avis)
  }

  /// Relit la liste des serveurs SANS intervention de l'utilisateur.
  ///
  /// POURQUOI CE N'EST PLUS UN GESTE MANUEL. Un Mac allumé, une session ouverte
  /// ailleurs, et la liste changeait sans que rien ne le dise : il fallait penser
  /// à rafraîchir. Le geste disparaît donc, comme il a disparu pour les sessions
  /// — la liste se remet à jour toute seule, et la sonde qui dit quels Macs
  /// servent DSH repasse avec elle.
  ///
  /// `synchronisationEnCours` sert de verrou : une synchronisation lente ne doit
  /// pas en empiler une autre toutes les quinze secondes.
  public func synchroniserServeurs() async {
    guard !synchronisationEnCours else { return }
    synchronisationEnCours = true
    defer { synchronisationEnCours = false }

    if client != nil {
      // Les espaces d'abord : un espace créé à l'instant doit apparaître même
      // vide, et c'est ce registre qui porte l'appartenance des sessions.
      if capacites?.espaces == true { await chargerEspacesDeLhote() }
      await chargerServeursDeLhote()
      // L'hôte a répondu — même une liste vide AVEC sa raison : c'est une
      // réponse, on ne la remplace pas par une supposition locale.
      if sourceServeurs == .hote { return }
    }
    await chargerServeursLocaux()
    await relancerSiLaCibleSertDsh()
  }

  /// Efface un échec devenu FAUX, et retente la connexion.
  ///
  /// POURQUOI. L'application affichait — à juste titre — « Aucun service ne
  /// répond sur le port 80 de ce Mac » avec les commandes qui le corrigent. Mais
  /// une fois la commande passée sur l'autre Mac, RIEN ne rejouait la connexion :
  /// le message restait à l'écran alors que la machine servait désormais DSH, et
  /// il fallait appuyer de nouveau sur la machine pour s'en apercevoir.
  ///
  /// La sonde, elle, le sait : elle vient d'interroger cette machine. Quand son
  /// verdict contredit l'erreur affichée, l'erreur disparaît et la connexion est
  /// retentée — c'est le cas où « tout d'un coup, il y arrive ».
  func relancerSiLaCibleSertDsh() async {
    guard erreur != nil, let vise = serveurVise else { return }
    guard sertDsh(vise) == true else { return }
    await connecter()
  }

  public func connecter() async {
    guard !adresse.trimmingCharacters(in: .whitespaces).isEmpty else {
      // Pas d'adresse : ce n'est pas une erreur, c'est un formulaire pas encore
      // rempli. Afficher un échec de transport ici accuserait le réseau à tort.
      connexion = .inconnue
      return
    }
    // ── On ne vise pas une machine que l'on SAIT éteinte ──────────────────────
    //
    // POURQUOI CE GARDE EXISTE, ET CE QU'IL A COÛTÉ. L'application mémorise la
    // dernière machine utilisée et s'y reconnecte au lancement. Le propriétaire a
    // choisi un MacBook Pro ; ce Mac s'est éteint ; à chaque ouverture,
    // l'application lançait donc une requête vers une machine morte, attendait
    // 21 SECONDES (mesuré), puis affichait « échec de transport : délai dépassé,
    // hôte injoignable » — un message technique, pour une machine dont l'écran
    // affichait déjà « hors ligne » juste à côté. Le garde-fou `ajusterAuParc`
    // bascule bien sur un Mac en ligne, mais seulement si la liste est déjà
    // chargée : la requête était partie avant.
    //
    // L'état connu prime donc sur la tentative. Une machine hors ligne n'est pas
    // une panne réseau : c'est une machine éteinte, et cela se dit.
    if let vise = serveurViseHorsLigne {
      // Refus LOCAL : on n'a même pas tenté. Le texte dit l'état et l'action.
      connexion = .incomplete(ModeleApp.messageHorsLigne(vise))
      // L'échec est CONSIGNÉ : c'est la preuve qui autorise `ajusterAuParc` à
      // basculer, et elle dit pourquoi — la machine est hors ligne, ce qui n'est
      // pas la même chose qu'une tentative ratée.
      consigner(EchecCible(adresse: adresse, raison: .horsLigne))
      return
    }
    let jeton = jetonDeLaCible()
    guard !jeton.isEmpty else {
      // LE MESSAGE RENVOIE AU GESTE QUI EXISTE, PAS À CELUI D'AVANT.
      //
      // Il disait : « Récupérez-le dans la sortie du harness sur l'hôte, au
      // premier chargement du plugin. » C'était le chemin d'avant l'appairage —
      // lire 43 caractères dans un terminal, sur l'AUTRE machine, et les
      // recopier. Le chemin normal est désormais le panneau : un QR code, ou son
      // texte à coller, qui remplissent l'adresse ET le jeton d'un seul geste.
      // Le terminal reste dit, en second, parce qu'il reste vrai — et c'est le
      // seul chemin quand on est devant le Mac lui-même.
      connexion = .jetonInvalide(
        L("Cet appareil n'est pas appairé à cette machine. Ouvrez sa page et prenez le QR code du panneau « Appairer un appareil » — ou, sur le Mac lui-même, recopiez le jeton que le harness n'affiche qu'une fois, au premier chargement du plugin."))
      return
    }
    // Un jeton tronqué enverrait une requête vouée au 401, en accusant le
    // serveur à tort : on le dit avant, avec le compte exact.
    guard jeton.count == 43 else {
      connexion = .jetonInvalide(
        L("jeton incomplet :") + " \(jeton.count) " + L("caractères au lieu de 43. Recopiez-le en entier."))
      return
    }
    // TRACE TEMPORAIRE : ou passe le temps au demarrage.
    let debutConnexion = Date()
    let adresseVisee = adresse
    // Le jeton n'est confié au trousseau qu'ici, une fois la saisie terminée.
    enregistrerJeton(jeton)
    await executer {
      // DEUX DÉLAIS POUR DEUX QUESTIONS, et l'ordre qui va avec : la brève
      // d'abord. C'est la politique de `Connexion`, éprouvée là-bas.
      let jonction = try await self.transport.joindre(adresse: self.adresse, jeton: jeton)
      self.client = jonction.client
      let depart = self.generationDuDepart()
      self.appliquerSessions(
        ListeSessions(protocole: 1, racine: nil, total: jonction.reponses,
          sessions: jonction.sessions, erreur: nil),
        vu: depart)
      // LE serveur a répondu ET accepté le jeton : une seule valeur le dit —
      // capacités, nombre de sessions rendues, et « joint » en découlent.
      self.connexion = .jointe(jonction.sante, reponses: jonction.reponses)
    }
    Trace.siActive("[demarrage] connecter \(adresseVisee) : \(Int(Date().timeIntervalSince(debutConnexion) * 1000)) ms, erreur=\(erreur == nil ? "non" : "OUI")")
    if erreur == nil {
      // La cible a répondu : plus rien ne justifie de basculer ailleurs.
      consigner(nil)
      demarrerSuivi()
      demarrerSuiviServeurs()
      // Une connexion réussie est le moment où la liste des Macs devient
      // disponible sur iPhone : l'hôte joint, lui, sait voir le tailnet.
      if capacites?.decouverte == true { await chargerServeursDeLhote() }
      // Les espaces de travail viennent du registre de l'hôte : c'est ce qui
      // fait apparaître les dossiers enregistrés mais encore SANS session, que
      // l'application ne pouvait pas représenter en les déduisant des sessions.
      if capacites?.espaces == true { await chargerEspacesDeLhote() }
      relireEtatTailscale()
    } else {
      // Tentative RÉELLE qui a échoué — transport, jeton refusé, version
      // incompatible. C'est une preuve, et elle autorise la bascule.
      //
      // SAUF QUAND LA MACHINE A RÉPONDU : `-1004` veut dire « rien n'écoute sur
      // ce port », donc la machine est vivante et c'est son port 80 qui manque.
      // Ce cas a son propre message, avec les commandes qui le corrigent — on ne
      // l'efface pas en basculant ailleurs.
      let sansService = (erreur ?? "").contains("-1004")
      consigner(EchecCible(adresse: adresse, raison: sansService ? .sansService : .injoignable))
    }
  }
}
