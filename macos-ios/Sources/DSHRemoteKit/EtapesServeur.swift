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
    tailnetDeLAppareil: Bool, enLigne: Bool, sertDsh: Bool?, cause: CauseSansDsh?
  ) -> [Etape] {
    // SANS TAILSCALE SUR CET APPAREIL, RIEN EN AVAL NE SE CONCLUT. Une liste de
    // machines peut dater d'avant la coupure ; une sonde peut avoir répondu il y
    // a une minute. Affirmer quoi que ce soit des étapes suivantes depuis un
    // appareil qui ne peut plus rien joindre serait parler du passé.
    guard tailnetDeLAppareil else {
      return [
        Etape(
          numero: 1,
          titre: "Tailscale est connecté sur cet appareil",
          explication:
            "Sans cela, aucun Mac du tailnet n'est joignable — ni celui-ci, ni un autre.",
          etat: .aFaire),
        Etape(
          numero: 2, titre: "Ce Mac est visible",
          explication: "Il est en ligne sur le tailnet, donc la découverte le propose.",
          etat: .inconnue),
        Etape(
          numero: 3, titre: "Le port de DSH est ouvert",
          explication:
            "Son port 80 est publié par `tailscale serve`, donc quelque chose répond à son adresse.",
          etat: .inconnue),
        Etape(
          numero: 4, titre: "Le plugin `dsh-remote` est installé",
          explication: "DSH Remote y répond : la machine peut servir l'application.",
          etat: .inconnue),
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
      Etape(
        numero: 1,
        titre: "Tailscale est connecté sur cet appareil",
        explication:
          "Sans cela, aucun Mac du tailnet n'est joignable — ni celui-ci, ni un autre.",
        etat: .franchie),
      Etape(
        numero: 2,
        titre: "Ce Mac est visible",
        explication: "Il est en ligne sur le tailnet, donc la découverte le propose.",
        etat: visibilite),
      Etape(
        numero: 3,
        titre: "Le port de DSH est ouvert",
        explication:
          "Son port 80 est publié par `tailscale serve`, donc quelque chose répond à son adresse.",
        etat: port),
      Etape(
        numero: 4,
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
