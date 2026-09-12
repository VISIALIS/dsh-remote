import Foundation

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// État de Tailscale tel que l'application peut le CONNAÎTRE, sans jamais
/// interroger le réseau.
///
/// POURQUOI CE TYPE EXISTE. La carte d'accueil propose trois actions
/// différentes — installer, ouvrir, vérifier — et se tromper d'action est un
/// mensonge d'interface : envoyer quelqu'un sur l'App Store pour une
/// application déjà installée, ou lui proposer « Ouvrir » quand le tailnet est
/// déjà connecté. Or iOS ne donne AUCUNE API qui réponde à « Tailscale
/// est-il installé ? » : le système ne publie pas la liste des applications.
///
/// Deux faits seulement sont vérifiables depuis une application :
///
///   1. **Le schéma d'URL répond-il ?** `canOpenURL("tailscale://")` est le seul
///      test d'installation possible. Il exige que `tailscale` soit déclaré
///      dans `LSApplicationQueriesSchemes` de l'Info.plist : sans cette
///      déclaration, la réponse est TOUJOURS `false` et l'application
///      proposerait d'installer un Tailscale déjà présent. C'est un piège
///      silencieux — `canOpenURL` ne lève pas, il rend `false`.
///   2. **Un serveur du tailnet répond-il ?** C'est ce qui distingue « installé »
///      de « connecté », et cela ne se lit nulle part ailleurs.
public enum EtatTailscale: Equatable, Sendable {
  /// L'application Tailscale ne répond pas à son schéma d'URL.
  case absent
  /// Elle est là, mais aucun serveur du tailnet n'a encore répondu.
  ///
  /// C'est un état d'ATTENTE, pas un diagnostic : Tailscale peut être connecté
  /// et le Mac éteint. La carte le dit, et propose d'ouvrir l'application.
  case installe
  /// Au moins un serveur du tailnet est en ligne : le tailnet fonctionne.
  case connecte

  /// Vrai si l'application Tailscale est présente sur CET appareil.
  public var installe: Bool { self != .absent }

  /// Libellé de l'action proposée — le verbe que l'appui tiendra.
  public var action: String {
    switch self {
    case .absent: return "Installer"
    case .installe: return "Ouvrir"
    case .connecte: return "Vérifier"
    }
  }
}

/// Détection de Tailscale, sans processus ni requête sortante.
///
/// La fonction est `@MainActor` parce que `canOpenURL` l'est de fait : elle
/// touche l'état du système et n'est pas libre de tout contexte.
@MainActor
public enum DetectionTailscale {
  /// Schéma d'URL de l'application Tailscale.
  ///
  /// À DÉCLARER dans `LSApplicationQueriesSchemes` de l'Info.plist de
  /// l'application. Le projet Xcode le fait ; un binaire qui ne le déclarerait
  /// pas rendrait toujours `false` ici.
  public static let schema = "tailscale://"

  /// Adresse de l'application Tailscale sur l'App Store.
  public static let adresseAppStore = "https://apps.apple.com/app/tailscale/id1470499037"

  /// Vrai si l'application Tailscale répond à son schéma.
  ///
  /// Sur macOS, `canOpenURL` n'existe pas pour les schémas d'application :
  /// la détection se fait donc par le système de fichiers, et seulement par
  /// lui. Les deux plateformes n'ont pas la même preuve disponible, et le code
  /// le dit plutôt que de faire semblant.
  public static func applicationInstallee() -> Bool {
    #if canImport(UIKit)
      guard let url = URL(string: schema) else { return false }
      return UIApplication.shared.canOpenURL(url)
    #else
      return FileManager.default.fileExists(atPath: "/Applications/Tailscale.app")
    #endif
  }

  /// Ouvre l'application Tailscale, ou son magasin si elle est absente.
  ///
  /// Rend `false` quand rien n'a pu être ouvert, pour que l'appelant puisse le
  /// DIRE : un bouton qui ne produit rien est un mensonge d'interface.
  @discardableResult
  public static func ouvrir() -> Bool {
    #if canImport(UIKit)
      guard let url = URL(string: schema), UIApplication.shared.canOpenURL(url) else { return false }
      UIApplication.shared.open(url)
      return true
    #else
      guard let url = URL(string: adresseAppStore) else { return false }
      NSWorkspace.shared.open(url)
      return true
    #endif
  }
}
