import Foundation

// L'INFRASTRUCTURE DU JETON : où il est gardé, et où on le trouve.
//
// POURQUOI CE FICHIER. Ces trois pièces vivaient à la fin de `ModeleApp`, noyées
// dans 2 100 lignes : le protocole de stockage, ses deux implémentations, et la
// lecture du coffre du harness. Elles ne dépendent NI de l'état ni de
// l'interface — ce sont des adaptateurs. Les sortir rend visible la frontière
// entre « ce qu'on sait du jeton » (une règle du domaine : il est propre à chaque
// hôte) et « où on le range » (un détail de plateforme).

/// OÙ LES JETONS SONT GARDÉS — un par hôte.
///
/// POURQUOI UN PROTOCOLE. Deux raisons, et la seconde est la vraie :
///
/// 1. les tests ne doivent pas écrire dans le trousseau de la machine qui les
///    exécute — un test qui touche un secret réel est un test qu'on n'ose plus
///    lancer ;
/// 2. le stockage peut changer (trousseau, coffre, mémoire) sans que le modèle
///    le sache.
public protocol GardienDeJetons: Sendable {
  func lire(pour hote: String) -> String?
  func ecrire(_ valeur: String, pour hote: String)
  func effacer(pour hote: String)
  /// EFFACE TOUS LES JETONS DE CETTE APPLICATION, ET REND LE COMPTE.
  ///
  /// POURQUOI CE N'EST PAS « effacer(pour:) » APPLIQUÉ AUX HÔTES CONNUS. Un hôte
  /// qu'on a retiré de la liste n'est plus connu de l'application — et son jeton
  /// resterait dans le trousseau, vivant, pour une machine qu'on ne visite plus.
  /// Une réinitialisation qui laisserait ces entrées-là serait celle qui ment :
  /// elle dirait « tout est effacé » en gardant des accès.
  ///
  /// LE COMPTE EST RENDU, et il n'est pas décoratif : c'est ce que l'écran affiche
  /// après le geste. Un bouton qui ne dit pas ce qu'il a fait ne vaut pas mieux
  /// qu'un bouton sans effet.
  @discardableResult
  func effacerTout() -> Int
}

/// Le trousseau de la machine : le jeton ne doit JAMAIS atterrir dans les
/// préférences, où il serait lisible par une sauvegarde ou un autre composant.
///
/// CHAQUE HÔTE A SA PROPRE ENTRÉE. Ce n'est pas une commodité : le jeton est tiré
/// par chaque hôte (mesuré), donc deux machines ont deux secrets distincts. Un
/// compte unique — c'était le cas — obligeait à recopier le jeton à chaque
/// bascule, et faisait envoyer à une machine le secret d'une autre quand on
/// oubliait.
/// Le gardien PAR DÉFAUT de la plateforme.
///
/// SUR macOS, LES JETONS VIVENT LE TEMPS DE L'APPLICATION. Ce n'est pas une
/// paresse : l'application est construite en **ad-hoc** par
/// `Scripts/empaqueter-app-macos.sh`, et un élément de trousseau est lié à la
/// signature. Une reconstruction changerait l'identité, donc l'accès : au mieux
/// une invite système à chaque lancement, au pire un secret perdu. On préfère
/// une limite DITE à une invite qui surprend.
///
/// CONSÉQUENCE, ÉCRITE POUR ÊTRE VUE : sur le Mac, le jeton d'un hôte DISTANT
/// est à recoller après un redémarrage de l'application. Celui de l'hôte local
/// n'a jamais à l'être — il vient du coffre du harness. Sur iPhone, le trousseau
/// garde tout, et rien n'est à recoller.
public enum GardienParDefaut {
  public static func faire() -> GardienDeJetons {
    #if os(macOS)
      return GardienEnMemoire()
    #else
      return TrousseauDeLaMachine()
    #endif
  }
}

/// Garde les jetons en mémoire, PAR HÔTE, le temps de l'application.
///
/// Sert de gardien par défaut sur macOS (voir ci-dessus) et de doublure dans les
/// tests — un test ne doit jamais écrire dans un secret réel.
public final class GardienEnMemoire: GardienDeJetons, @unchecked Sendable {
  private var jetons: [String: String] = [:]
  private let verrou = NSLock()

  public init() {}

  public func lire(pour hote: String) -> String? {
    verrou.lock()
    defer { verrou.unlock() }
    return jetons[hote]
  }

  public func ecrire(_ valeur: String, pour hote: String) {
    verrou.lock()
    defer { verrou.unlock() }
    jetons[hote] = valeur
  }

  public func effacer(pour hote: String) {
    verrou.lock()
    defer { verrou.unlock() }
    jetons[hote] = nil
  }

  @discardableResult
  public func effacerTout() -> Int {
    verrou.lock()
    defer { verrou.unlock() }
    let compte = jetons.count
    jetons.removeAll()
    return compte
  }
}

public struct TrousseauDeLaMachine: GardienDeJetons {
  private static let service = "org.example.dsh-remote"

  /// Le compte PORTE l'hôte : c'est ce qui rend les entrées distinctes.
  private static func compte(pour hote: String) -> String { "jeton-appareil.\(hote)" }

  public init() {}

  public func lire(pour hote: String) -> String? {
    #if canImport(Security)
      let requete: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Self.service,
        kSecAttrAccount as String: Self.compte(pour: hote),
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ]
      var resultat: CFTypeRef?
      guard SecItemCopyMatching(requete as CFDictionary, &resultat) == errSecSuccess,
        let donnees = resultat as? Data
      else { return nil }
      return String(data: donnees, encoding: .utf8)
    #else
      return nil
    #endif
  }

  public func ecrire(_ valeur: String, pour hote: String) {
    #if canImport(Security)
      let requete: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Self.service,
        kSecAttrAccount as String: Self.compte(pour: hote),
      ]
      SecItemDelete(requete as CFDictionary)
      guard !valeur.isEmpty, let donnees = valeur.data(using: .utf8) else { return }
      var ajout = requete
      ajout[kSecValueData as String] = donnees
      ajout[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      SecItemAdd(ajout as CFDictionary, nil)
    #endif
  }

  public func effacer(pour hote: String) {
    #if canImport(Security)
      let requete: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Self.service,
        kSecAttrAccount as String: Self.compte(pour: hote),
      ]
      SecItemDelete(requete as CFDictionary)
    #endif
  }

  /// EFFACE TOUT CE QUE CETTE APPLICATION A DÉPOSÉ — et rien d'autre.
  ///
  /// LA REQUÊTE EST CLOSE SUR NOTRE `service` : c'est ce qui garantit qu'on ne
  /// touche à aucun autre mot de passe de l'appareil. On ÉNUMÈRE au lieu de
  /// supprimer en bloc parce que `SecItemDelete` veut une requête qui désigne des
  /// entrées ; on supprime donc compte par compte, en comptant.
  ///
  /// UN ÉCHEC DE SUPPRESSION N'EST PAS COMPTÉ. Rendre « 3 » parce qu'on a
  /// DEMANDÉ trois suppressions serait un compte rendu faux — et c'est exactement
  /// ce que l'écran ne doit pas afficher.
  @discardableResult
  public func effacerTout() -> Int {
    #if canImport(Security)
      let requete: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Self.service,
        kSecReturnAttributes as String: true,
        kSecMatchLimit as String: kSecMatchLimitAll,
      ]
      var resultat: CFTypeRef?
      guard SecItemCopyMatching(requete as CFDictionary, &resultat) == errSecSuccess,
        let trouves = resultat as? [[String: Any]]
      else { return 0 }
      var effaces = 0
      for entree in trouves {
        guard let compte = entree[kSecAttrAccount as String] as? String else { continue }
        let cible: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: Self.service,
          kSecAttrAccount as String: compte,
        ]
        if SecItemDelete(cible as CFDictionary) == errSecSuccess { effaces += 1 }
      }
      return effaces
    #else
      return 0
    #endif
  }
}

/// L'EMPREINTE D'UN JETON — jamais le jeton.
///
/// Sert au diagnostic : elle permet de dire SI le jeton détenu est celui du
/// coffre, sans jamais écrire le secret sur disque.
public enum Empreinte {
  public static func de(_ valeur: String) -> String {
  let donnees = Data(valeur.utf8)
  var hash = [UInt8](repeating: 0, count: 32)
  donnees.withUnsafeBytes { tampon in
    var accumulateur: UInt64 = 0xcbf29ce484222325
    // Implémentation FNV-1a 64 bits : suffisante pour COMPARER deux valeurs,
    // sans dépendance, et sans prétendre à une résistance cryptographique —
    // ce n'est pas un secret à protéger ici, seulement à distinguer.
    for octet in tampon {
      accumulateur ^= UInt64(octet)
      accumulateur = accumulateur &* 0x100000001b3
    }
    for index in 0..<8 {
      hash[index] = UInt8((accumulateur >> (UInt64(index) * 8)) & 0xff)
    }
  }
  return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
}
}

/// LE COFFRE DU HARNESS, sur la machine locale.
///
/// `~/.dsh/.credentials.yaml` contient le jeton émis par l'hôte LOCAL — et rien
/// d'autre. Il ne peut donc pas répondre pour une autre machine : c'est la règle
/// qui a corrigé « on envoie à une machine le secret d'une autre ».
public enum CoffreDuHarness {
/// Lit le jeton d'appareil dans le coffre du harness, si le fichier est là.
///
/// Sur le Mac, l'application et le harness partagent le même utilisateur : le
/// coffre est lisible et l'utilisateur n'a rien à saisir. Sur iPhone, ce fichier
/// n'existe pas — `Trousseau.lire()` prend alors le relais, et le jeton a été
/// saisi une fois puis conservé au trousseau.
///
/// `DSH_REMOTE_COFFRE` force le chemin du coffre, ce qui permet d'essayer
/// l'application dans le simulateur iOS où `HOME` désigne le conteneur simulé.
public static func jetonDeLaMachine() -> String? {
  let environnement = ProcessInfo.processInfo.environment
  let coffre: URL
  if let force = environnement["DSH_REMOTE_COFFRE"], !force.isEmpty {
    coffre = URL(fileURLWithPath: force)
  } else {
    let base = environnement["DSH_HOME"].flatMap { $0.isEmpty ? nil : $0 }.map { URL(fileURLWithPath: $0) }
      ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".dsh")
    coffre = base.appendingPathComponent(".credentials.yaml")
  }
  if let contenu = try? String(contentsOf: coffre, encoding: .utf8),
    let valeur = jetonDuCoffre(contenu)
  {
    return valeur
  }
  // Plus de repli sur le trousseau ICI : le coffre local parle de la machine
  // LOCALE, et c'est tout. Le jeton d'un hôte distant se lit par la clé de cet
  // hôte (`jetonDeLaCible`), pas en dernier recours.
  return nil
}

/// Extrait le jeton d'appareil du coffre, en ciblant SA clé.
///
/// POURQUOI CE N'EST PAS UN SIMPLE `grep`. Le coffre contient au moins deux
/// secrets de 43 caractères en base64url : le jeton du plugin, mais aussi le
/// secret qui signe les cookies de session du navigateur
/// (`client-connection/browser-session`). Prendre la première ligne « token »
/// ramassait donc souvent le secret de signature, que le serveur refuse en
/// `401` — un jeton d'apparence valide, mais qui n'en est pas un.
///
/// On suit donc la structure du document : on n'accepte un `token` que s'il
/// appartient à l'enregistrement `dsh-remote/device-token`.
static func jetonDuCoffre(_ contenu: String) -> String? {
  var dansLeBonEnregistrement = false
  for ligne in contenu.split(separator: "\n", omittingEmptySubsequences: false) {
    let texte = ligne.trimmingCharacters(in: .whitespaces)
    if texte.hasPrefix("dsh-remote/") || texte.hasPrefix("records/dsh-remote/") {
      dansLeBonEnregistrement = true
      continue
    }
    // Tout autre enregistrement de premier niveau referme la section.
    if texte.hasSuffix(":") && !texte.hasPrefix("token") && !texte.hasPrefix("payload") {
      if dansLeBonEnregistrement && !texte.contains("device-token") { dansLeBonEnregistrement = false }
    }
    guard dansLeBonEnregistrement, texte.hasPrefix("token:") else { continue }
    let valeur = texte.dropFirst("token:".count).trimmingCharacters(in: .whitespaces)
    if valeur.count >= 20 { return valeur }
  }
  return nil
}
}
