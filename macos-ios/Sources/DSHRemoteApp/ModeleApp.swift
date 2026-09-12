import DSHRemoteKit
import Foundation

#if canImport(Security)
  import Security
#endif

/// État de l'application : une connexion, la liste des sessions, un journal ouvert.
///
/// La vue ne parle jamais au réseau : elle observe ce modèle et lui demande des
/// actions. C'est ce qui permet de tester la logique sans interface, et de
/// remplacer le transport sans toucher aux vues.
@MainActor
@Observable
public final class ModeleApp {
  /// Adresse du serveur DSH. Par défaut la boucle locale : sur le Mac, c'est
  /// toujours la bonne. Sur iPhone, on y met l'adresse tailnet du Mac.
  public var adresse: String = "http://127.0.0.1:3080"
  public var jetonSaisi: String = ""

  public private(set) var sessions: [SessionListee] = []
  public private(set) var journal: [EvenementAffiche] = []
  public private(set) var sessionOuverte: ResumeSession?
  public private(set) var capacites: Sante.Capacites?
  public private(set) var enChargement = false
  public private(set) var erreur: String?
  public var filtresActifs = true

  private var client: RemoteClient?

  public init() {}

  /// Vrai si un jeton est disponible, sans jamais le révéler.
  public var jetonDisponible: Bool { !jetonSaisi.isEmpty }

  // MARK: - Jeton

  /// Lit le jeton d'appareil sur cette machine, si possible.
  ///
  /// Sur macOS, l'application tourne sur le même Mac que le harness : le coffre
  /// lui est accessible, et l'utilisateur n'a rien à saisir. Sur iOS, ce fichier
  /// n'existe pas — le jeton doit être saisi une fois, puis conservé au trousseau.
  public static func jetonLocal() -> String? {
    #if os(macOS)
      let base = ProcessInfo.processInfo.environment["DSH_HOME"].map { URL(fileURLWithPath: $0) }
        ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".dsh")
      let coffre = base.appendingPathComponent(".credentials.yaml")
      guard let contenu = try? String(contentsOf: coffre, encoding: .utf8) else { return nil }
      for ligne in contenu.split(separator: "\n") {
        let texte = ligne.trimmingCharacters(in: .whitespaces)
        guard texte.hasPrefix("token:") else { continue }
        let valeur = texte.dropFirst("token:".count).trimmingCharacters(in: .whitespaces)
        if valeur.count >= 20 { return valeur }
      }
      return nil
    #else
      return Trousseau.lire()
    #endif
  }

  /// Enregistre le jeton saisi : au trousseau sur iOS, en mémoire sur macOS.
  public func enregistrerJeton(_ valeur: String) {
    jetonSaisi = valeur.trimmingCharacters(in: .whitespacesAndNewlines)
    #if !os(macOS)
      Trousseau.ecrire(jetonSaisi)
    #endif
  }

  // MARK: - Connexion

  public func connecter() async {
    let jeton = jetonSaisi.isEmpty ? (Self.jetonLocal() ?? "") : jetonSaisi
    guard !jeton.isEmpty else {
      erreur = "Aucun jeton d'appareil. Récupérez-le dans la sortie du harness sur le Mac, au premier chargement du plugin."
      return
    }
    jetonSaisi = jeton
    await executer {
      let client = try RemoteClient(adresse: self.adresse, jeton: jeton)
      let sante = try await client.verifierSante()
      self.client = client
      self.capacites = sante.capacites
      let liste = try await client.listerSessions(limite: 200)
      self.sessions = liste.sessions
    }
  }

  public func rafraichir() async {
    guard let client else { return }
    await executer {
      let liste = try await client.listerSessions(limite: 200)
      self.sessions = liste.sessions
    }
  }

  public func ouvrir(_ session: SessionListee) async {
    guard let client else { return }
    await executer {
      let journal = try await client.lireSession(
        session.id,
        demande: DemandeJournal(depuis: 0, limite: 400))
      self.sessionOuverte = journal.session
      self.journal = journal.enregistrements.map(DecodeurEvenement.afficher)
    }
  }

  public func fermerJournal() {
    journal = []
    sessionOuverte = nil
  }

  /// Sessions affichées, selon le filtre « vivantes seulement ».
  public var sessionsAffichees: [SessionListee] {
    filtresActifs ? sessions.filter { $0.vivante == true } : sessions
  }

  private func executer(_ travail: @escaping () async throws -> Void) async {
    enChargement = true
    erreur = nil
    do {
      try await travail()
    } catch {
      self.erreur = String(describing: error)
    }
    enChargement = false
  }
}

/// Trousseau iOS : le jeton ne doit jamais atterrir dans les préférences, où il
/// serait lisible par une sauvegarde ou un autre composant.
enum Trousseau {
  private static let service = "org.example.dsh-remote"
  private static let compte = "jeton-appareil"

  static func lire() -> String? {
    #if canImport(Security)
      let requete: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: compte,
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

  static func ecrire(_ valeur: String) {
    #if canImport(Security)
      let requete: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: compte,
      ]
      SecItemDelete(requete as CFDictionary)
      guard !valeur.isEmpty, let donnees = valeur.data(using: .utf8) else { return }
      var ajout = requete
      ajout[kSecValueData as String] = donnees
      ajout[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      SecItemAdd(ajout as CFDictionary, nil)
    #endif
  }
}
