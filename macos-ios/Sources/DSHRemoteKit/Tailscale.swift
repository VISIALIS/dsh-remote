import Foundation

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// Détection de Tailscale, sans processus ni requête sortante.
///
/// POURQUOI DEUX CONSTATATIONS, ET NON UN ÉTAT À TROIS CAS. Un `EtatTailscale`
/// vivait ici — absent / installé / connecté — pour choisir l'action de la carte
/// d'accueil. Cette carte a été RETIRÉE : l'état de l'appareil est la première
/// étape du parcours de chaque serveur, et le panneau latéral n'a plus à le
/// répéter (voir `VueListeSessions`). Le type est parti avec son seul lecteur.
///
/// Ce qui reste est exactement ce dont le parcours a besoin :
///
///   1. **L'application est-elle là ?** `canOpenURL("tailscale://")` est le seul
///      test d'installation possible sur iOS, qui ne publie pas la liste des
///      applications installées. Il exige que `tailscale` soit déclaré dans
///      `LSApplicationQueriesSchemes` de l'Info.plist : sans cette déclaration,
///      la réponse est TOUJOURS `false`, et l'application proposerait d'installer
///      un Tailscale déjà présent. C'est un piège silencieux — `canOpenURL` ne
///      lève pas, il rend `false`.
///   2. **Cet appareil est-il sur le tailnet ?** Une adresse `100.64.0.0/10` sur
///      une de ses interfaces. C'est une MESURE, pas une déduction : elle ne
///      dépend ni d'un serveur allumé, ni de la liste des Macs.
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

  /// Vrai si CET APPAREIL a une adresse dans la plage du tailnet.
  ///
  /// POURQUOI CE TEST EXISTE, ET POURQUOI IL A REMPLACÉ UN DEEP LINK. La
  /// détection se contentait de deux signaux : l'application Tailscale
  /// répond-elle à son schéma, et un serveur répond-il. Sur l'iPhone du
  /// propriétaire, le second manquait — Tailscale installé et connecté, mais
  /// aucun serveur encore joint — et la carte proposait donc « Ouvrir ». Or
  /// ouvrir `tailscale://` sur iOS déclenche le flux d'ENREGISTREMENT D'APPAREIL
  /// de l'application Tailscale, qui a affiché « Could not sign device : unable
  /// to verify deeplink ». Un cul-de-sac, provoqué par notre propre bouton.
  ///
  /// La lecture des interfaces réseau donne la réponse sans rien ouvrir : quand
  /// Tailscale est connecté, l'appareil porte une adresse dans `100.64.0.0/10`,
  /// la plage réservée à ses adresses de tailnet. C'est une CONSTATION, pas une
  /// supposition — et elle est vraie même sans aucun serveur joignable.
  ///
  /// `getifaddrs` est disponible sur iOS ; lire les adresses de ses propres
  /// interfaces ne demande aucune autorisation.
  public static func adresseDeTailnetPresente() -> Bool {
    var curseur: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&curseur) == 0, let premiere = curseur else { return false }
    defer { freeifaddrs(curseur) }

    var noeud: UnsafeMutablePointer<ifaddrs>? = premiere
    while let interface = noeud {
      defer { noeud = interface.pointee.ifa_next }
      guard let adresse = interface.pointee.ifa_addr,
        adresse.pointee.sa_family == UInt8(AF_INET)
      else { continue }

      // `sin_addr` est stocké en OCTETS RÉSEAU : l'octet de tête est le premier.
      var brut = adresse.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
        $0.pointee.sin_addr.s_addr
      }
      let octets = withUnsafeBytes(of: &brut) { Array($0) }
      guard octets.count == 4 else { continue }
      // 100.64.0.0/10 : premier octet 100, second entre 64 et 127.
      if octets[0] == 100, (64...127).contains(octets[1]) { return true }
    }
    return false
  }

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
