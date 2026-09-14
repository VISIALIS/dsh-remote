import Foundation

#if canImport(UserNotifications)
  import UserNotifications
#endif

/// UNE ALERTE À POSER SUR L'ÉCRAN DE L'UTILISATEUR.
///
/// POURQUOI CE TYPE EST MINUSCULE. Il ne porte que ce qui se décide : deux
/// phrases. Le CANAL (notification locale, bandeau, journal) et le moment de
/// l'envoi n'appartiennent pas à la décision, et les mêler rendrait la décision
/// intestable.
public struct Alerte: Equatable, Sendable {
  public let titre: String
  public let corps: String

  public init(titre: String, corps: String) {
    self.titre = titre
    self.corps = corps
  }
}

/// CE QUI MÉRITE UNE ALERTE, D'APRÈS CE QUI A CHANGÉ ENTRE DEUX LISTES.
///
/// POURQUOI UNE FONCTION PURE, ET POURQUOI ELLE EST ICI. Ce qui alerte est une
/// DÉCISION — ce qui a changé, ce qu'on ne regarde pas déjà, et ce qu'on
/// regroupe pour ne pas harceler —, et une décision se relit et s'éprouve. Un
/// envoi, lui, dépend du système : les deux sont séparés pour que le second ne
/// puisse pas cacher le premier.
///
/// TROIS RÈGLES, chacune née d'un défaut évitable :
///
///   1. **on n'alerte que sur un CHANGEMENT.** Une session qui attendait déjà ne
///      réalerte pas à chaque rafraîchissement de trois secondes — sans quoi
///      l'application enverrait vingt alertes par minute ;
///   2. **on n'alerte pas sur ce qu'on REGARDE.** Le rappel de fin suit déjà
///      cette règle ; l'alerte la suit aussi, sinon ouvrir une session et la
///      voir se terminer produirait une notification pour un écran sous les
///      yeux ;
///   3. **on regroupe.** Cinq sessions qui se terminent ensemble font UNE alerte
///      avec un compte, pas cinq — une pile de notifications identiques
///      s'apprend à être ignorée.
///
/// L'ORDRE COMPTE : l'attente d'abord. C'est la seule des deux qui demande une
/// ACTION de l'utilisateur ; une fin de tour est une bonne nouvelle à lire.
public extension Alerte {
  static func aEnvoyer(
    attendent: Set<String>,
    attendaientAvant: Set<String>,
    terminees: Set<String>,
    termineesAvant: Set<String>,
    regardee: String?
  ) -> [Alerte] {
    var alertes: [Alerte] = []

    let nouvellesAttentes = attendent
      .subtracting(attendaientAvant)
      .subtracting(regardee.map { [$0] } ?? [])
    if !nouvellesAttentes.isEmpty {
      alertes.append(
        Alerte(
          titre: nouvellesAttentes.count > 1
            ? "\(nouvellesAttentes.count) sessions attendent votre réponse"
            : "Une session attend votre réponse",
          corps: nouvellesAttentes.count > 1
            ? "L'agent est bloqué sur une décision, dans plusieurs sessions."
            : "L'agent est bloqué sur une décision."))
    }

    let nouvellesFins = terminees
      .subtracting(termineesAvant)
      .subtracting(regardee.map { [$0] } ?? [])
    if !nouvellesFins.isEmpty {
      alertes.append(
        Alerte(
          titre: nouvellesFins.count > 1
            ? "\(nouvellesFins.count) tours viennent de se terminer"
            : "Un tour vient de se terminer",
          corps: nouvellesFins.count > 1
            ? "Le résultat est dans le journal de ces sessions."
            : "Le résultat est dans le journal de cette session."))
    }

    return alertes
  }
}

/// LE CANAL D'ENVOI, derrière un protocole.
///
/// POURQUOI UN PROTOCOLE, ET NON UN APPEL DIRECT. Le modèle doit pouvoir être
/// éprouvé sans envoyer de vraies notifications — et surtout : « aucune alerte
/// quand elles sont éteintes » est une propriété qui se vérifie, pas qui se
/// suppose. Les tests passent un espion ; l'application, le système.
public protocol Alerteur: Sendable {
  func prevenir(_ alerte: Alerte) async
  /// Demande l'autorisation, et dit si elle est accordée.
  ///
  /// ELLE EST DANS LE PROTOCOLE, et pas seulement en méthode statique : sans
  /// cela, le chemin « on allume les alertes » resterait intestable — le modèle
  /// appellerait le système, et un test ne pourrait ni l'accorder ni le refuser.
  func demanderAutorisation() async -> Bool
}

/// LES NOTIFICATIONS LOCALES DU SYSTÈME.
public struct AlerteurSysteme: Alerteur {
  public init() {}

  /// LES NOTIFICATIONS NE SONT POSSIBLES QUE DANS UN PAQUET.
  ///
  /// MESURÉ, ET C'EST POURQUOI CETTE GARDE EXISTE — pas par prudence de style.
  /// Un binaire nu appelant `UNUserNotificationCenter.current()` ne rend pas
  /// `nil` : il **lève**, et le processus **avorte**.
  ///
  /// ```text
  /// $ swiftc -o /tmp/essai-notif essai-notif.swift && /tmp/essai-notif
  /// identifiant de paquet : (aucun)
  /// *** Terminating app due to uncaught exception 'NSInternalInconsistencyException',
  ///     reason: 'bundleProxyForCurrentProcess is nil: mainBundle.bundleURL file:///tmp/'
  /// zsh: abort      /tmp/essai-notif        (code 134, signal 6)
  /// ```
  ///
  /// Autrement dit : sans cette garde, `swift run DSHRemoteMac` — le chemin de
  /// développement documenté de ce paquet — mourrait au lancement, et le message
  /// ne désignerait même pas la notification. On ne parle donc au centre de
  /// notifications que si l'exécution a un identifiant de paquet.
  public static var possibles: Bool {
    #if canImport(UserNotifications)
      return Bundle.main.bundleIdentifier != nil
    #else
      return false
    #endif
  }

  public func prevenir(_ alerte: Alerte) async {
    #if canImport(UserNotifications)
      guard Self.possibles else { return }
      let contenu = UNMutableNotificationContent()
      contenu.title = alerte.titre
      contenu.body = alerte.corps
      contenu.sound = .default
      // `trigger: nil` : la notification part TOUT DE SUITE. Il n'y a rien à
      // programmer dans le temps — l'événement vient d'être observé.
      let requete = UNNotificationRequest(
        identifier: UUID().uuidString, content: contenu, trigger: nil)
      try? await UNUserNotificationCenter.current().add(requete)
    #endif
  }

  /// Demande l'autorisation à l'utilisateur, et dit si elle est accordée.
  ///
  /// ELLE N'EST DEMANDÉE QU'AU MOMENT OÙ L'ON ALLUME LES ALERTES, jamais au
  /// lancement : une application qui réclame un droit qu'on ne lui a pas demandé
  /// apprend à être refusée.
  public func demanderAutorisation() async -> Bool {
    await Self.autorisationDemandee()
  }

  /// La demande elle-même, statique pour être lisible sans instance.
  public static func autorisationDemandee() async -> Bool {
    #if canImport(UserNotifications)
      guard possibles else { return false }
      return
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [
          .alert, .sound, .badge,
        ])) ?? false
    #else
      return false
    #endif
  }
}

/// UN CANAL QUI NE FAIT RIEN — pour les tests, et les plateformes sans notifications.
public struct AlerteurMuet: Alerteur {
  public init() {}
  public func prevenir(_ alerte: Alerte) async {}
  /// Un canal muet n'obtient jamais rien : c'est ce qui rend visible, dans les
  /// tests, qu'un refus laisse l'interrupteur ÉTEINT.
  public func demanderAutorisation() async -> Bool { false }
}
