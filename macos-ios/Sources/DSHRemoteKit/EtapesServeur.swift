import Foundation

/// LES ÉTAPES À FRANCHIR POUR QU'UN MAC DEVIENNE UN SERVEUR DSH UTILISABLE.
///
/// POURQUOI CE TYPE EXISTE. La page d'un serveur montrait un DIAGNOSTIC : une
/// erreur, puis un remède. C'est utile quand on sait déjà ce qu'on cherche, et
/// inutile quand on ne sait pas OÙ on en est — l'utilisateur voyait « pas de
/// DSH » sans savoir s'il lui manquait un port, un plugin, ou simplement un Mac
/// allumé.
///
/// Les trois étapes sont celles de la mise en service, dans l'ordre où elles se
/// franchissent — chacune suppose la précédente :
///
///   1. le Mac est VISIBLE : il est en ligne sur le tailnet, donc la découverte le
///      propose ;
///   2. le PORT est OUVERT : quelque chose répond sur son port 80, publié par
///      `tailscale serve` ;
///   3. le PLUGIN est INSTALLÉ : DSH Remote y répond.
///
/// CHAQUE ÉTAT VIENT D'UNE MESURE, JAMAIS D'UNE DÉDUCTION. « En ligne » vient de
/// Tailscale, les deux autres de la sonde : une machine qui répond autre chose
/// qu'un `404` (`-1004`, délai, DNS) a son port fermé ; une machine qui répond
/// `404` a son port ouvert mais pas le plugin. Quand on ne sait pas encore, on
/// dit « à vérifier » — un parcours qui affirme à tort est pire qu'un parcours
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

  /// Les trois étapes, dans l'ordre, pour une machine donnée.
  ///
  /// - Parameters:
  ///   - enLigne: ce que Tailscale dit de la machine (un fait, pas une mesure de
  ///     l'application).
  ///   - sertDsh: le verdict de la sonde — `nil` = pas encore su.
  ///   - cause: POURQUOI elle ne sert pas DSH, quand on le sait.
  public static func etapes(enLigne: Bool, sertDsh: Bool?, cause: CauseSansDsh?) -> [Etape] {
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

    let plugin: Etat
    if !enLigne {
      plugin = .inconnue
    } else {
      switch sertDsh {
      case true: plugin = .franchie
      case false: plugin = .aFaire
      case nil: plugin = .inconnue
      }
    }

    return [
      Etape(
        numero: 1,
        titre: "Ce Mac est visible",
        explication: "Il est en ligne sur le tailnet, donc la découverte le propose.",
        etat: visibilite),
      Etape(
        numero: 2,
        titre: "Le port de DSH est ouvert",
        explication:
          "Son port 80 est publié par `tailscale serve`, donc quelque chose répond à son adresse.",
        etat: port),
      Etape(
        numero: 3,
        titre: "Le plugin `dsh-remote` est installé",
        explication: "DSH Remote y répond : la machine peut servir l'application.",
        etat: plugin),
    ]
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
