import Foundation

/// LES ÉTAPES À FRANCHIR POUR QU'UN MAC DEVIENNE UN SERVEUR DSH UTILISABLE.
///
/// POURQUOI CE TYPE EXISTE. La page d'un serveur montrait un DIAGNOSTIC : une
/// erreur, puis un remède. C'est utile quand on sait déjà ce qu'on cherche, et
/// inutile quand on ne sait pas OÙ on en est — l'utilisateur voyait « pas de
/// DSH » sans savoir s'il lui manquait un port, un plugin, ou simplement un Mac
/// allumé.
///
/// Les CINQ étapes sont celles de la mise en service, dans l'ordre où elles se
/// franchissent — chacune suppose la précédente :
///
///   1. TAILSCALE EST CONNECTÉ SUR CET APPAREIL : il porte une adresse de
///      tailnet. Sans elle, aucune des étapes suivantes n'est atteignable — et
///      c'est la seule qui se constate localement, sans rien demander à personne ;
///   2. le Mac est VISIBLE : il est en ligne sur le tailnet, donc la découverte le
///      propose ;
///   3. le PORT est OUVERT : quelque chose répond sur son port 80, publié par
///      `tailscale serve` ;
///   4. le PLUGIN est INSTALLÉ : DSH Remote y répond ;
///   5. CET APPAREIL EST APPAIRÉ : un jeton, propre à lui, est rangé pour cette
///      machine — sans quoi la connexion est refusée, quelle que soit la santé du
///      Mac.
///
/// LA CINQUIÈME A ÉTÉ AJOUTÉE APRÈS COUP, et elle répare une confusion coûteuse :
/// sans jeton rangé, la sonde ne partait pas, le verdict restait vide, et la page
/// annonçait « pas de DSH » — donc envoyait installer un plugin déjà installé sur
/// une machine parfaitement prête. L'appairage est une ÉTAPE, la dernière, et
/// elle se constate localement : le jeton est là, ou il n'y est pas.
///
/// LA PREMIÈRE AVAIT ÉTÉ AJOUTÉE DE LA MÊME FAÇON, à la demande du propriétaire :
/// « j'ai oublié un goal avant, le fait que Tailscale est connecté ».
///
/// CHAQUE ÉTAT VIENT D'UNE MESURE, JAMAIS D'UNE DÉDUCTION. L'adresse de tailnet
/// se lit sur les interfaces de l'appareil, et l'appairage dans le trousseau ;
/// « en ligne » vient de Tailscale ; les deux du milieu de la sonde : une machine
/// qui répond autre chose qu'un `404` (`-1004`, délai, DNS) a son port fermé ;
/// une machine qui répond `404` a son port ouvert mais pas le plugin. Quand on ne
/// sait pas encore, on dit « à vérifier » — un parcours qui affirme à tort est
/// pire qu'un parcours incomplet, parce qu'il envoie chercher au mauvais endroit.
public enum EtapesServeur {

  /// OÙ EN EST L'APPAIRAGE DE CET APPAREIL AVEC CETTE MACHINE.
  ///
  /// POURQUOI CE N'EST PAS UN BOOLÉEN. « Pas de jeton » et « jeton refusé » ont
  /// la même conséquence — la connexion échoue —, mais pas le même remède : le
  /// premier se répare en appairant, le second en appairant À NOUVEAU, parce que
  /// le secret rangé n'est pas celui de cette machine-là. Un booléen obligerait
  /// la vue à relire ailleurs pour distinguer les deux, et c'est exactement le
  /// genre de déduction qui finit par diverger d'un écran à l'autre.
  public enum EtatAppairage: Equatable, Sendable {
    /// Un jeton bien formé est rangé pour cette machine.
    case appaire
    /// Aucun jeton n'est rangé pour cette machine.
    case absent
    /// Un jeton est rangé, et le service l'a refusé : ce n'est pas celui de cet hôte.
    case refuse
  }

  /// Où en est une étape.
  public enum Etat: Equatable, Sendable {
    case franchie
    /// On SAIT qu'elle n'est pas franchie.
    case aFaire
    /// On ne sait pas encore (sonde en cours, jeton absent).
    case inconnue
  }

  /// COMMENT LIRE LES ÉTAPES : ce qu'on constate, ou ce qu'il reste à faire.
  ///
  /// POURQUOI CE TYPE A QUITTÉ LA VUE. Il décide de ce qui est VERROUILLÉ, donc
  /// de ce qui est ATTEIGNABLE — une règle, pas un dessin. Il vit ici, à côté de
  /// `estVerrouillee`, pour être éprouvé sans rendre une vue.
  public enum Mode: Equatable, Sendable {
    /// Toutes les étapes sont montrées, avec leur méthode si elles ne sont pas
    /// franchies. Aucune n'est verrouillée : un diagnostic dit tout.
    case diagnostic
    /// Une seule frontière : les suivantes sont grisées, sans méthode ouverte.
    case objectifs
  }

  /// COMMENT LA MÉTHODE D'UNE ÉTAPE EST MONTRÉE.
  public enum Presentation: Equatable, Sendable {
    /// Rien à faire : l'étape est franchie.
    case rien
    /// La méthode est OUVERTE : c'est l'étape qui bloque.
    case ouverte
    /// La méthode est REPLIÉE derrière un bouton — lisible, mais pas dépliée.
    case repliee
  }

  /// LA RÈGLE, EN UNE FONCTION PURE : ouverte, repliée, ou rien.
  ///
  /// POURQUOI ELLE EXISTE, ET CE QU'ELLE CORRIGE. Sur la page « Ajouter un
  /// serveur », les étapes du Mac sont déclarées « à faire » par construction —
  /// on ne juge pas une machine qu'on n'a pas encore. La frontière ne pouvait
  /// donc JAMAIS avancer, et les étapes 3 et 4, verrouillées à perpétuité,
  /// n'affichaient NI leur explication NI leur méthode : « publier le port » et
  /// « installer le plugin » étaient inatteignables depuis la seule page qui
  /// existe pour les enseigner.
  ///
  /// CE QUI CHANGE, ET CE QUI NE CHANGE PAS. Le verrou reste un REPÈRE D'ORDRE —
  /// la ligne est grisée, l'icône est un cadenas, « après l'étape N-1 » est
  /// écrit. Mais la méthode redevient LISIBLE : repliée, donc la page reste
  /// courte, et atteignable, donc plus personne ne bute sur une porte fermée.
  /// On ne demande à personne de faire l'étape 4 avant la 2 ; on refuse
  /// seulement de cacher comment on la fait.
  ///
  /// SUR UNE LISTE DE TRAVAIL, LA MÉTHODE OUVERTE EST CELLE DE CET APPAREIL. Les
  /// deux côtés ne se mesurent pas : le Mac n'a même pas encore d'adresse. Ouvrir
  /// la méthode du Mac ferait donc apprendre ici un travail qui se fait ailleurs —
  /// et c'est précisément ce que le propriétaire a demandé de retirer. Le travail
  /// du Mac reste écrit, replié : on le lit quand on est devant lui.
  public static func presentation(
    _ etape: Etape, dans etapes: [Etape], mode: Mode
  ) -> Presentation {
    guard etape.etat != .franchie else { return .rien }
    switch mode {
    case .diagnostic:
      // Un diagnostic DIT tout, mais n'OUTILLE qu'une chose à la fois : trois
      // jeux de commandes à l'écran noient celle qui est exécutable maintenant.
      let frontiere = premiereAEtapesFranchir(etapes)
      return etape.numero == frontiere ? .ouverte : .repliee
    case .objectifs:
      guard !estVerrouillee(etape, dans: etapes, mode: mode) else { return .repliee }
      return etape.responsable == .appareil ? .ouverte : .repliee
    }
  }

  /// DE QUI RELÈVE UNE ÉTAPE — et c'est ce qui décide OÙ elle s'affiche.
  ///
  /// POURQUOI CE TYPE EXISTE, ET CE QU'IL CORRIGE. La page « Ajouter un serveur »
  /// présentait les quatre étapes sur le même plan, comme un travail à faire par
  /// la même personne au même endroit. C'était faux, et l'usage l'a dit : sur
  /// l'application distante (macOS ou iOS), **deux** de ces étapes se constatent
  /// depuis l'appareil — Tailscale y est-il connecté, et cet appareil est-il
  /// appairé. Les trois autres dépendent du Mac qui héberge DSH, et l'application
  /// les VÉRIFIE déjà toute seule (le diagnostic, sur la page de la machine).
  ///
  /// Les enseigner au même niveau faisait donc apprendre au remote un travail qui
  /// n'est pas le sien — et noyait les deux seules choses qu'il a à faire :
  /// vérifier Tailscale, puis prendre le QR code.
  ///
  /// C'EST AUSSI CE QUI DÉCIDE DU VERROU. Sur une liste de travail, seules les
  /// étapes DU MÊME CÔTÉ se précèdent (voir `estVerrouillee`) : le geste d'ici
  /// n'attend pas un travail qui se fait ailleurs.
  public enum Responsable: Equatable, Sendable {
    /// CET APPAREIL : ce que l'utilisateur peut constater et corriger ici, et donc
    /// ce que l'application doit enseigner d'abord.
    case appareil
    /// LE MAC QUI HÉBERGE DSH : hors de portée de l'application, et **constaté**
    /// par la sonde dès qu'une machine répond. Sa méthode reste écrite — elle sert
    /// quand on est devant le Mac — mais repliée, et jamais en préalable.
    case hote
  }

  public struct Etape: Equatable, Sendable {
    public let numero: Int
    public let titre: String
    /// Ce que l'étape veut dire, en une phrase — affichée seulement si elle
    /// reste à franchir.
    public let explication: String
    public let etat: Etat
    /// De qui elle relève. Voir `Responsable`.
    public let responsable: Responsable

    public init(
      numero: Int, titre: String, explication: String, etat: Etat, responsable: Responsable = .hote
    ) {
      self.numero = numero
      self.titre = titre
      self.explication = explication
      self.etat = etat
      self.responsable = responsable
    }
  }

  /// Les étapes qui concernent CET APPAREIL — deux, aujourd'hui : Tailscale, et
  /// l'appairage.
  public static func deLAppareil(_ etapes: [Etape]) -> [Etape] {
    etapes.filter { $0.responsable == .appareil }
  }

  /// Les étapes qui concernent LE MAC qui héberge DSH — les trois du milieu.
  public static func deLHote(_ etapes: [Etape]) -> [Etape] {
    etapes.filter { $0.responsable == .hote }
  }

  /// Les cinq étapes, dans l'ordre, pour une machine donnée.
  ///
  /// - Parameters:
  ///   - tailnetDeLAppareil: CET appareil porte-t-il une adresse de tailnet ?
  ///     Une constatation locale (`getifaddrs`), pas une déduction.
  ///   - enLigne: ce que Tailscale dit de la machine VISÉE (un fait, pas une
  ///     mesure de l'application).
  ///   - sertDsh: le verdict de la sonde — `nil` = pas encore su.
  ///   - cause: POURQUOI elle ne sert pas DSH, quand on le sait.
  ///   - appairage: où en est l'appairage de CET APPAREIL avec cette machine.
  ///     Il ne dépend ni du réseau ni de la sonde : le jeton est rangé ici, ou
  ///     il ne l'est pas — c'est la seule des cinq étapes qui se lise sans rien
  ///     demander à personne, avec la première.
  public static func etapes(
    tailnetDeLAppareil: Bool?, enLigne: Bool, sertDsh: Bool?, cause: CauseSansDsh?,
    appairage: EtatAppairage
  ) -> [Etape] {
    // L'APPAIRAGE NE SE DÉDUIT PAS DU RÉSEAU. Il a donc sa valeur dès maintenant,
    // et il la garde dans les deux branches ci-dessous : un appareil hors tailnet
    // n'est pas appairé pour autant, et le dire n'engage à rien.
    let appaire: Etat = appairage == .appaire ? .franchie : .aFaire
    // « PAS ENCORE MESURÉ » N'EST PAS « NON ». Tant qu'on n'a pas constaté
    // l'adresse de tailnet de cet appareil, l'étape 1 est INCONNUE — et les
    // suivantes aussi, puisqu'on ne peut rien conclure d'un appareil dont on ne
    // sait pas s'il est sur le réseau.
    let etatDuReseau: Etat = tailnetDeLAppareil == nil ? .inconnue : (tailnetDeLAppareil! ? .franchie : .aFaire)
    // SANS TAILSCALE SUR CET APPAREIL, RIEN EN AVAL NE SE CONCLUT. Une liste de
    // machines peut dater d'avant la coupure ; une sonde peut avoir répondu il y
    // a une minute. Affirmer quoi que ce soit des étapes suivantes depuis un
    // appareil qui ne peut plus rien joindre serait parler du passé.
    guard tailnetDeLAppareil == true else {
      return [
        etape(1, etatDuReseau),
        etape(2, .inconnue),
        etape(3, .inconnue),
        etape(4, .inconnue),
        etape(5, appaire),
      ]
    }

    let visibilite: Etat = enLigne ? .franchie : .aFaire

    // Le port : on ne le sait que si la machine est joignable. Une machine hors
    // ligne ne dit rien de son port — et prétendre le contraire enverrait
    // publier un port sur un Mac éteint.
    let port: Etat
    if !enLigne {
      port = .inconnue
    } else {
      switch sertDsh {
      case true: port = .franchie
      case false:
        // DEUX CAUSES SEULEMENT permettent de conclure sur le port. Un `404`
        // prouve qu'il est ouvert (quelque chose a répondu) ; `-1004` prouve
        // qu'il est fermé. Toute autre erreur — délai, DNS — dit que la machine
        // ne répond pas SANS dire pourquoi : on ne conclut pas, sinon on envoie
        // publier un port qui l'est peut-être déjà.
        switch cause {
        case .pluginAbsent: port = .franchie
        case .rienNEcoute: port = .aFaire
        case nil: port = .inconnue
        }
      case nil: port = .inconnue
      }
    }

    // LE PLUGIN N'EST ACCUSÉ QUE SI QUELQU'UN A RÉPONDU. Un `404` prouve que le
    // port est ouvert, donc que ce qui manque est le plugin. Quand le port est
    // fermé — ou quand l'échec ne s'explique pas —, le plugin est peut-être
    // installé : on ne sait pas, et on le dit. (La version précédente le
    // déclarait « à faire » dans tous les cas, ce qui envoyait installer un
    // plugin derrière un port fermé.)
    let plugin: Etat
    if !enLigne {
      plugin = .inconnue
    } else {
      switch sertDsh {
      case true: plugin = .franchie
      case false: plugin = (cause == .pluginAbsent) ? .aFaire : .inconnue
      case nil: plugin = .inconnue
      }
    }

    return [
      etape(1, .franchie),
      etape(2, visibilite),
      etape(3, port),
      etape(4, plugin),
      etape(5, appaire),
    ]
  }

  /// UNE ÉTAPE, DITE DANS LES MOTS DE SON ÉTAT.
  ///
  /// POURQUOI LES TEXTES SONT ICI, ET NON AUX DEUX POINTS DE CONSTRUCTION. Les
  /// quatre étapes étaient écrites DEUX FOIS — pour l'appareil hors tailnet, puis
  /// pour la machine jugée — et les deux copies décrivaient l'étape FRANCHIE quel
  /// que soit l'état. Constaté sur capture, sur un Mac éteint : l'étape 2,
  /// déclarée « à faire », s'expliquait par « Il est en ligne sur le tailnet, donc
  /// la découverte le propose ». Une explication qui contredit son propre titre
  /// fait douter du diagnostic entier — et envoie chercher au mauvais endroit.
  ///
  /// TROIS FORMES, une par état :
  ///
  /// - `franchie` : ce que l'état EST, constaté ;
  /// - `aFaire` : le constat INVERSE. La marche à suivre n'est pas répétée ici :
  ///   la méthode s'affiche juste en dessous, et l'écrire deux fois dilue celle
  ///   qui compte ;
  /// - `inconnue` : ce que l'étape DEMANDE, puisqu'on ne peut rien constater.
  private static func etape(_ numero: Int, _ etat: Etat) -> Etape {
    let titre: String
    let explication: String
    switch numero {
    case 1:
      titre = L("Tailscale est connecté sur cet appareil")
      explication = L("Sans cela, aucune machine du tailnet n'est joignable — ni celui-ci, ni un autre.")
    case 2:
      titre = L("Cette machine est visible")
      switch etat {
      case .franchie:
        explication = L("Il est en ligne sur le tailnet, donc la découverte le propose.")
      case .aFaire:
        explication = L("Il est hors ligne sur le tailnet : la découverte ne le propose donc pas.")
      case .inconnue:
        explication = L("On ne peut pas le savoir d'ici : Tailscale n'est pas connecté sur cet appareil.")
      }
    case 3:
      titre = L("Le port de DSH est ouvert")
      switch etat {
      case .franchie:
        explication =
          "Son port 80 est publié par `tailscale serve`, donc quelque chose répond à son adresse."
      case .aFaire:
        explication = L("Rien ne répond sur son port 80 : `tailscale serve` ne le publie pas.")
      case .inconnue:
        explication =
          "Son port 80 doit être publié par `tailscale serve` pour que quelque chose réponde à son adresse."
      }
    case 4:
      titre = L("Le plugin `dsh-remote` est installé")
      switch etat {
      case .franchie:
        explication = L("DSH Remote y répond : la machine peut servir l'application.")
      case .aFaire:
        explication = L("DSH Remote n'y répond pas : la machine ne peut pas servir l'application.")
      case .inconnue:
        explication = L("DSH Remote doit y répondre pour que la machine serve l'application.")
      }
    default:
      titre = L("Cet appareil est appairé")
      switch etat {
      case .franchie:
        explication = L("Il a son propre jeton pour cette machine : rien à recopier, jamais.")
      case .aFaire:
        // « PAS DE JETON ACCEPTÉ » COUVRE LES DEUX CAS — absent, ou refusé —, et
        // c'est voulu : la phrase doit rester vraie dans les deux, sans quoi elle
        // mentirait sur l'un des deux états. Le remède, lui, les distingue : c'est
        // la méthode qui les sépare, pas le constat.
        explication = L("Il n'a pas de jeton accepté par cette machine : la connexion serait refusée.")
      case .inconnue:
        explication = L("On ne sait pas encore si cet appareil est appairé à cette machine.")
      }
    }
    return Etape(
      numero: numero, titre: titre, explication: explication, etat: etat,
      responsable: (numero == 1 || numero == 5) ? .appareil : .hote)
  }

  /// LES ÉTAPES POUR AJOUTER UN SERVEUR — quand aucune machine n'est choisie.
  ///
  /// POURQUOI CE N'EST PAS `etapes(...)`. Là, on ne juge pas une machine : on
  /// liste le travail à faire pour qu'un Mac DEVIENNE un serveur. Les étapes qui
  /// se constatent depuis ici (Tailscale sur cet appareil) disent donc leur état
  /// réel ; les autres s'adressent au Mac qu'on veut ajouter, et sont « à faire »
  /// — c'est une LISTE, pas un verdict. Un verdict demanderait de connaître la
  /// machine, et il n'y en a pas encore.
  ///
  /// L'APPAIRAGE AUSSI EST « À FAIRE », ET CE N'EST PAS UN OUBLI. On ne vient pas
  /// sur cette page pour constater un appairage existant, mais pour en obtenir un
  /// POUR LA MACHINE QU'ON AJOUTE — celle-ci n'existe pas encore. Un état lu sur
  /// la cible courante répondrait donc à une autre question, et afficherait
  /// « franchie » devant la seule chose qu'il reste à faire ici.
  public static func etapesDAjout(tailnetDeLAppareil: Bool?) -> [Etape] {
    [
      Etape(
        numero: 1,
        titre: L("Tailscale est connecté sur cet appareil"),
        explication:
          "Sans cela, aucune machine du tailnet n'est joignable — ni celui-ci, ni un autre.",
        etat: tailnetDeLAppareil == nil ? .inconnue : (tailnetDeLAppareil! ? .franchie : .aFaire),
        responsable: .appareil),
      Etape(
        numero: 2,
        titre: L("La machine à ajouter est sur le tailnet"),
        explication:
          "Il doit avoir Tailscale installé et connecté : c'est ce qui le rend visible depuis cet appareil.",
        etat: .aFaire),
      Etape(
        numero: 3,
        titre: L("Le port de DSH y est ouvert"),
        explication:
          "Son port 80 doit être publié par `tailscale serve` — sans quoi rien ne répond à son adresse.",
        etat: .aFaire),
      Etape(
        numero: 4,
        titre: L("Le plugin `dsh-remote` y est installé"),
        explication: L("DSH Remote doit y répondre : publier DSH ne suffit pas."),
        etat: .aFaire),
      Etape(
        numero: 5,
        titre: L("Cet appareil est appairé"),
        explication:
          "Le panneau « Appairer un appareil » du Mac affiche un QR code et son texte : ils portent l'adresse ET un code à usage unique, et remplacent les deux saisies.",
        etat: .aFaire,
        responsable: .appareil),
    ]
  }

  /// LA CONCLUSION DU DIAGNOSTIC, en une ligne.
  ///
  /// POURQUOI UN RÉSUMÉ. Un diagnostic se lit d'abord par sa conclusion : « ce
  /// serveur est-il utilisable ? » est la question, et les cinq étapes sont la
  /// démonstration. Sans cette ligne, il fallait lire cinq lignes pour savoir
  /// si tout allait bien — et c'est le cas le plus fréquent.
  ///
  /// ELLE SE LIT SUR LA FRONTIÈRE, PAS SUR UN COMPTE. C'était le défaut : la
  /// conclusion comptait les étapes « à faire » et, quand il n'y en avait aucune,
  /// annonçait « Vérification en cours… ». Un appareil dont le Mac est
  /// parfaitement prêt mais qui n'a PAS de jeton tombait exactement là — deux
  /// étapes inconnues, rien à faire de mesuré —, et la page restait suspendue
  /// indéfiniment, sans jamais nommer ce qui manquait. Depuis que l'appairage est
  /// une étape, ce cas a une réponse : la cinquième est « à faire », elle est la
  /// frontière, et elle se nomme.
  ///
  /// LA FRONTIÈRE INCONNUE L'EMPORTE. Si la première étape non franchie est
  /// « à vérifier », on ne peut rien affirmer des suivantes : on le dit, au lieu
  /// de compter des étapes dont on ne sait rien.
  public static func resume(_ etapes: [Etape]) -> String {
    let restantes = etapes.filter { $0.etat != .franchie }
    guard let frontiere = restantes.first else { return "Ce serveur est prêt." }
    guard frontiere.etat == .aFaire else { return "Vérification en cours…" }
    let sures = restantes.filter { $0.etat == .aFaire }
    if sures.count == 1 {
      // LE TITRE EST CITÉ TEL QUEL. Le mettre en minuscules abîmait les noms
      // propres — « Cette machine est visible » devenait « cette machine est visible »,
      // constaté sur capture.
      return "Il reste une étape : « \(frontiere.titre) »."
    }
    return "Il reste \(sures.count) étapes sur \(etapes.count)."
  }

  /// Cette étape est-elle VERROUILLÉE par une précédente non franchie ?
  ///
  /// Demande du propriétaire : « si une étape de goal n'est pas réalisée, les goals
  /// suivants sont grisés (pas besoin de rentrer dans leur détail) ». C'est une
  /// conséquence de l'ordre : on ne publie pas un port sur un Mac qui n'est pas sur
  /// le réseau, et on n'installe pas un plugin derrière un port fermé.
  ///
  /// DEUX RÈGLES, PARCE QUE LES DEUX LISTES NE DISENT PAS LA MÊME CHOSE.
  ///
  ///   - en DIAGNOSTIC, on juge une machine : la frontière est MESURÉE, et rien
  ///     ne se fait avant ce qui la précède — les cinq étapes sont une chaîne ;
  ///   - en OBJECTIFS, on liste un travail, et les deux côtés sont INDÉPENDANTS :
  ///     le Mac n'a même pas encore d'adresse. Seules les étapes DU MÊME
  ///     RESPONSABLE se précèdent. Sans cette nuance, le geste que l'appareil a à
  ///     faire ici — prendre le QR code — restait grisé derrière un travail qui
  ///     se fait ailleurs, sur une machine que l'application ne connaît pas.
  ///
  /// Rend `false` quand tout est franchi : il n'y a alors plus de frontière, donc
  /// plus rien à verrouiller.
  public static func estVerrouillee(
    _ etape: Etape, dans etapes: [Etape], mode: Mode = .diagnostic
  ) -> Bool {
    let comparables: [Etape]
    switch mode {
    case .diagnostic: comparables = etapes
    case .objectifs: comparables = etapes.filter { $0.responsable == etape.responsable }
    }
    guard let frontiere = premiereAEtapesFranchir(comparables) else { return false }
    return etape.numero > frontiere
  }

  /// Le numéro de la PREMIÈRE étape à franchir, s'il y en a une.
  ///
  /// Sert à mettre en avant l'étape qui débloque les suivantes : inutile de
  /// publier un port sur une machine hors ligne, et inutile d'installer un plugin
  /// dont le port sera fermé.
  public static func premiereAEtapesFranchir(_ etapes: [Etape]) -> Int? {
    etapes.first { $0.etat != .franchie }?.numero
  }
}
