import Foundation

/// LES ÉTAPES À FRANCHIR POUR QU'UN MAC DEVIENNE UN SERVEUR DSH UTILISABLE.
///
/// POURQUOI CE TYPE EXISTE. La page d'un serveur montrait un DIAGNOSTIC : une
/// erreur, puis un remède. C'est utile quand on sait déjà ce qu'on cherche, et
/// inutile quand on ne sait pas OÙ on en est — l'utilisateur voyait « pas de
/// DSH » sans savoir s'il lui manquait un port, un plugin, ou simplement un Mac
/// allumé.
///
/// Les QUATRE étapes sont celles de la mise en service, dans l'ordre où elles se
/// franchissent — chacune suppose la précédente :
///
///   1. TAILSCALE EST CONNECTÉ SUR CET APPAREIL : il porte une adresse de
///      tailnet. Sans elle, aucune des étapes suivantes n'est atteignable — et
///      c'est la seule qui se constate localement, sans rien demander à personne ;
///   2. le Mac est VISIBLE : il est en ligne sur le tailnet, donc la découverte le
///      propose ;
///   3. le PORT est OUVERT : quelque chose répond sur son port 80, publié par
///      `tailscale serve` ;
///   4. le PLUGIN est INSTALLÉ : DSH Remote y répond.
///
/// LA PREMIÈRE A ÉTÉ AJOUTÉE APRÈS COUP, à la demande du propriétaire : « j'ai
/// oublié un goal avant, le fait que Tailscale est connecté ». Elle manquait
/// effectivement — sur un iPhone où Tailscale n'est pas installé, les trois autres
/// étapes ne peuvent pas être franchies, et le parcours commençait pourtant par
/// elles.
///
/// CHAQUE ÉTAT VIENT D'UNE MESURE, JAMAIS D'UNE DÉDUCTION. L'adresse de tailnet
/// se lit sur les interfaces de l'appareil ; « en ligne » vient de Tailscale ;
/// les deux dernières de la sonde : une machine qui répond autre chose qu'un
/// `404` (`-1004`, délai, DNS) a son port fermé ; une machine qui répond `404` a
/// son port ouvert mais pas le plugin. Quand on ne sait pas encore, on dit
/// « à vérifier » — un parcours qui affirme à tort est pire qu'un parcours
/// incomplet, parce qu'il envoie chercher au mauvais endroit.
public enum EtapesServeur {

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
  /// serveur », les étapes 2 à 4 sont déclarées « à faire » par construction —
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
  public static func presentation(
    _ etape: Etape, dans etapes: [Etape], mode: Mode
  ) -> Presentation {
    guard etape.etat != .franchie else { return .rien }
    let frontiere = premiereAEtapesFranchir(etapes)
    switch mode {
    case .diagnostic:
      // Un diagnostic DIT tout, mais n'OUTILLE qu'une chose à la fois : trois
      // jeux de commandes à l'écran noient celle qui est exécutable maintenant.
      return etape.numero == frontiere ? .ouverte : .repliee
    case .objectifs:
      return estVerrouillee(etape, dans: etapes) ? .repliee : .ouverte
    }
  }

  public struct Etape: Equatable, Sendable {
    public let numero: Int
    public let titre: String
    /// Ce que l'étape veut dire, en une phrase — affichée seulement si elle
    /// reste à franchir.
    public let explication: String
    public let etat: Etat

    public init(numero: Int, titre: String, explication: String, etat: Etat) {
      self.numero = numero
      self.titre = titre
      self.explication = explication
      self.etat = etat
    }
  }

  /// Les quatre étapes, dans l'ordre, pour une machine donnée.
  ///
  /// - Parameters:
  ///   - tailnetDeLAppareil: CET appareil porte-t-il une adresse de tailnet ?
  ///     Une constatation locale (`getifaddrs`), pas une déduction.
  ///   - enLigne: ce que Tailscale dit de la machine VISÉE (un fait, pas une
  ///     mesure de l'application).
  ///   - sertDsh: le verdict de la sonde — `nil` = pas encore su.
  ///   - cause: POURQUOI elle ne sert pas DSH, quand on le sait.
  public static func etapes(
    tailnetDeLAppareil: Bool?, enLigne: Bool, sertDsh: Bool?, cause: CauseSansDsh?
  ) -> [Etape] {
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
      titre = "Tailscale est connecté sur cet appareil"
      explication = "Sans cela, aucune machine du tailnet n'est joignable — ni celui-ci, ni un autre."
    case 2:
      titre = "Cette machine est visible"
      switch etat {
      case .franchie:
        explication = "Il est en ligne sur le tailnet, donc la découverte le propose."
      case .aFaire:
        explication = "Il est hors ligne sur le tailnet : la découverte ne le propose donc pas."
      case .inconnue:
        explication = "On ne peut pas le savoir d'ici : Tailscale n'est pas connecté sur cet appareil."
      }
    case 3:
      titre = "Le port de DSH est ouvert"
      switch etat {
      case .franchie:
        explication =
          "Son port 80 est publié par `tailscale serve`, donc quelque chose répond à son adresse."
      case .aFaire:
        explication = "Rien ne répond sur son port 80 : `tailscale serve` ne le publie pas."
      case .inconnue:
        explication =
          "Son port 80 doit être publié par `tailscale serve` pour que quelque chose réponde à son adresse."
      }
    default:
      titre = "Le plugin `dsh-remote` est installé"
      switch etat {
      case .franchie:
        explication = "DSH Remote y répond : la machine peut servir l'application."
      case .aFaire:
        explication = "DSH Remote n'y répond pas : la machine ne peut pas servir l'application."
      case .inconnue:
        explication = "DSH Remote doit y répondre pour que la machine serve l'application."
      }
    }
    return Etape(numero: numero, titre: titre, explication: explication, etat: etat)
  }

  /// LES ÉTAPES POUR AJOUTER UN SERVEUR — quand aucune machine n'est choisie.
  ///
  /// POURQUOI CE N'EST PAS `etapes(...)`. Là, on ne juge pas une machine : on
  /// liste le travail à faire pour qu'un Mac DEVIENNE un serveur. Seule la
  /// première étape se constate depuis ici (Tailscale sur cet appareil) ; les
  /// autres s'adressent au Mac qu'on veut ajouter, et sont donc « à faire » —
  /// c'est une LISTE, pas un verdict. Un verdict demanderait de connaître la
  /// machine, et il n'y en a pas encore.
  public static func etapesDAjout(tailnetDeLAppareil: Bool?) -> [Etape] {
    [
      Etape(
        numero: 1,
        titre: "Tailscale est connecté sur cet appareil",
        explication:
          "Sans cela, aucune machine du tailnet n'est joignable — ni celui-ci, ni un autre.",
        etat: tailnetDeLAppareil == nil ? .inconnue : (tailnetDeLAppareil! ? .franchie : .aFaire)),
      Etape(
        numero: 2,
        titre: "La machine à ajouter est sur le tailnet",
        explication:
          "Il doit avoir Tailscale installé et connecté : c'est ce qui le rend visible depuis cet appareil.",
        etat: .aFaire),
      Etape(
        numero: 3,
        titre: "Le port de DSH y est ouvert",
        explication:
          "Son port 80 doit être publié par `tailscale serve` — sans quoi rien ne répond à son adresse.",
        etat: .aFaire),
      Etape(
        numero: 4,
        titre: "Le plugin `dsh-remote` y est installé",
        explication: "DSH Remote doit y répondre : publier DSH ne suffit pas.",
        etat: .aFaire),
    ]
  }

  /// LA CONCLUSION DU DIAGNOSTIC, en une ligne.
  ///
  /// POURQUOI UN RÉSUMÉ. Un diagnostic se lit d'abord par sa conclusion : « ce
  /// serveur est-il utilisable ? » est la question, et les quatre étapes sont la
  /// démonstration. Sans cette ligne, il fallait lire quatre lignes pour savoir
  /// si tout allait bien — et c'est le cas le plus fréquent.
  ///
  /// Elle distingue trois situations, parce qu'elles n'appellent pas la même
  /// réaction : tout est prêt ; il reste du travail ; on ne sait pas encore.
  public static func resume(_ etapes: [Etape]) -> String {
    let restantes = etapes.filter { $0.etat != .franchie }
    if restantes.isEmpty { return "Ce serveur est prêt." }
    let sures = restantes.filter { $0.etat == .aFaire }
    if sures.isEmpty { return "Vérification en cours…" }
    if sures.count == 1, let seule = sures.first {
      // LE TITRE EST CITÉ TEL QUEL. Le mettre en minuscules abîmait les noms
      // propres — « Cette machine est visible » devenait « cette machine est visible »,
      // constaté sur capture.
      return "Il reste une étape : « \(seule.titre) »."
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
  /// Rend `false` quand tout est franchi : il n'y a alors plus de frontière, donc
  /// plus rien à verrouiller.
  public static func estVerrouillee(_ etape: Etape, dans etapes: [Etape]) -> Bool {
    guard let frontiere = premiereAEtapesFranchir(etapes) else { return false }
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
