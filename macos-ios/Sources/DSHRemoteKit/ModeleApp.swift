import DSHRemoteKit
import Foundation

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

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
  /// Boucle locale par défaut : sur le Mac, c'est toujours la bonne. Surchargeable
  /// par `DSH_REMOTE_ADRESSE` — ce qui sert à viser l'adresse tailnet depuis un
  /// iPhone, et à lancer l'application dans le simulateur iOS sans saisie manuelle.
  /// Le simulateur partage la pile réseau et le système de fichiers du Mac, donc
  /// il atteint le tailnet et lit le coffre : c'est ce qui rend l'essai possible.
  public var adresse: String = ModeleApp.adresseParDefaut
  public var jetonSaisi: String = ""

  public private(set) var sessions: [SessionListee] = []
  public private(set) var journal: [EvenementAffiche] = []
  public private(set) var sessionOuverte: ResumeSession?
  public private(set) var capacites: Sante.Capacites?
  public private(set) var enChargement = false
  public private(set) var erreur: String?
  public var filtresActifs = true

  private var client: RemoteClient?
  private var flux: FluxSession?
  private var tacheFlux: Task<Void, Never>?

  /// Vrai quand le suivi temps réel est actif sur la session ouverte.
  public private(set) var enDirect = false
  /// Dernier `seq` reçu par le flux, à repasser en `depuisSeq` si l'on rouvre.
  public private(set) var dernierSeqVu: Int?

  public init() {
    chargerConfiguration()
  }

  /// Charge une configuration déposée dans le conteneur de l'application.
  ///
  /// POURQUOI CE FICHIER EXISTE. `simctl launch` transmet ses arguments en
  /// `argv`, pas dans l'environnement : les surcharges par variable
  /// d'environnement n'arrivent donc pas à une application iOS, et il n'existe
  /// aucun autre moyen d'amorcer une application non signée sans saisie manuelle.
  /// Ce fichier permet d'ESSAYER l'application sur un simulateur en y déposant
  /// adresse et jeton depuis le Mac.
  ///
  /// PORTÉE RÉELLE : en production, ce fichier n'existe pas — il n'est jamais
  /// créé par l'application, et il doit être déposé explicitement dans un
  /// conteneur de simulateur. Sur un iPhone réel, rien ne le lit.
  private func chargerConfiguration() {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    guard let documents else { return }
    let fichier = documents.appendingPathComponent("dsh-remote-config.json")
    guard let donnees = try? Data(contentsOf: fichier),
      let objet = try? JSONSerialization.jsonObject(with: donnees) as? [String: String]
    else { return }
    if let valeur = objet["adresse"], !valeur.isEmpty { adresse = valeur }
    if let valeur = objet["jeton"], valeur.count >= 20 { jetonSaisi = valeur }
  }

  /// Vrai si un jeton est disponible, sans jamais le révéler.
  public var jetonDisponible: Bool { !jetonSaisi.isEmpty }

  // MARK: - Jeton

  /// Adresse par défaut, surchargeable par l'environnement.
  public static var adresseParDefaut: String {
    let declaree = ProcessInfo.processInfo.environment["DSH_REMOTE_ADRESSE"]
    return declaree.flatMap { $0.isEmpty ? nil : $0 } ?? "http://127.0.0.1:3080"
  }

  /// Lit le jeton d'appareil dans le coffre du harness, si le fichier est là.
  ///
  /// Sur le Mac, l'application et le harness partagent le même utilisateur : le
  /// coffre est lisible et l'utilisateur n'a rien à saisir. Sur iPhone, ce fichier
  /// n'existe pas — `Trousseau.lire()` prend alors le relais, et le jeton a été
  /// saisi une fois puis conservé au trousseau.
  ///
  /// `DSH_REMOTE_COFFRE` force le chemin du coffre, ce qui permet d'essayer
  /// l'application dans le simulateur iOS où `HOME` désigne le conteneur simulé.
  public static func jetonLocal() -> String? {
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
      let valeur = Self.jetonDuCoffre(contenu)
    {
      return valeur
    }
    return Trousseau.lire()
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

  /// Colle le jeton depuis le presse-papier.
  ///
  /// POURQUOI CE BOUTON. Le jeton fait 43 caractères en base64url, copié depuis
  /// un terminal : à la main, sur un clavier de téléphone, une saisie exacte
  /// est improbable. Le presse-papier supprime le risque de faute — et comme on
  /// nettoie les espaces, un retour à la ligne collé avec la valeur ne gêne pas.
  @discardableResult
  public func collerLeJeton() -> Bool {
    let valeur: String?
    #if canImport(UIKit)
      valeur = UIPasteboard.general.string
    #elseif canImport(AppKit)
      valeur = NSPasteboard.general.string(forType: .string)
    #else
      valeur = nil
    #endif
    guard let valeur else { return false }
    let nettoye = valeur.trimmingCharacters(in: .whitespacesAndNewlines)
    guard nettoye.count >= 20 else { return false }
    jetonSaisi = nettoye
    return true
  }

  /// Enregistre le jeton saisi : au trousseau sur iOS, en mémoire sur macOS.
  ///
  /// N'est appelé qu'à la SOUMISSION du formulaire, jamais à la frappe : un
  /// enregistrement par caractère persistait un jeton tronqué, et faisait
  /// croire à un jeton disponible alors que la saisie n'était pas terminée.
  public func enregistrerJeton(_ valeur: String) {
    jetonSaisi = valeur.trimmingCharacters(in: .whitespacesAndNewlines)
    #if !os(macOS)
      if !jetonSaisi.isEmpty { Trousseau.ecrire(jetonSaisi) }
    #endif
  }

  // MARK: - Connexion

  public func connecter() async {
    let jeton = jetonSaisi.isEmpty ? (Self.jetonLocal() ?? "") : jetonSaisi
    guard !jeton.isEmpty else {
      erreur = "Aucun jeton d'appareil. Récupérez-le dans la sortie du harness sur le Mac, au premier chargement du plugin."
      return
    }
    // Le jeton n'est confié au trousseau qu'ici, une fois la saisie terminée.
    enregistrerJeton(jeton)
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
    await demarrerFlux(session.id)
  }

  /// Suit la session en direct, en reprenant au dernier `seq` déjà chargé.
  ///
  /// La reprise n'est pas un confort : sans `depuisSeq`, le serveur renverrait
  /// tout ce que la page vient de charger, et le journal afficherait des doublons.
  public func demarrerFlux(_ identifiant: String) async {
    if let precedent = flux { await precedent.fermer() }
    flux = nil
    enDirect = true
    guard let client else { return }
    let jeton = jetonSaisi
    let adresse = self.adresse
    guard
      let session = FluxSession(
        adresse: adresse, jeton: jeton, identifiant: identifiant,
        depuisSeq: journal.last?.enregistrement.seq)
    else { return }
    flux = session
    let tache = Task { [weak self] in
      for await message in await session.messages() {
        guard let self else { return }
        await self.appliquer(message)
      }
    }
    tacheFlux = tache
  }

  /// Arrête le suivi. Le journal déjà chargé reste affiché.
  public func arreterFlux() {
    tacheFlux?.cancel()
    tacheFlux = nil
    Task { await flux?.fermer() }
    flux = nil
    enDirect = false
  }

  /// Applique un message du flux au journal affiché.
  ///
  /// Un `seq` déjà présent est ignoré : une reprise peut recouvrir la page
  /// chargée, et un doublon à l'écran serait un défaut visible.
  private func appliquer(_ message: MessageFlux) async {
    switch message {
    case let .base(_, enregistrements, _):
      for enregistrement in enregistrements {
        ajouterSiNouveau(enregistrement)
      }
    case let .evenement(enregistrement):
      ajouterSiNouveau(enregistrement)
    case let .delta(dernierSeq):
      if let dernierSeq { dernierSeqVu = dernierSeq }
    case let .tronque(detail):
      erreur = "Flux incomplet : \(detail)"
    case let .erreur(detail):
      erreur = detail
      enDirect = false
    }
  }

  private func ajouterSiNouveau(_ enregistrement: EnregistrementJournal) {
    if let seq = enregistrement.seq, journal.contains(where: { $0.enregistrement.seq == seq }) {
      return
    }
    journal.append(DecodeurEvenement.afficher(enregistrement))
  }

  public func fermerJournal() {
    arreterFlux()
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
      let message = String(describing: error)
      self.erreur = message
      Self.journaliserDiagnostic(adresse: adresse, message: message)
    }
    enChargement = false
  }

  /// Écrit la dernière erreur de connexion dans le conteneur de l'application.
  ///
  /// POURQUOI. Un message d'erreur affiché à l'écran d'un téléphone est difficile
  /// à rapporter fidèlement, et il ne contient pas toujours le code qui
  /// distingue un refus App Transport Security (`-1022`) d'un DNS injoignable
  /// (`-1003`) ou d'un délai dépassé (`-1001`) — trois causes aux corrections
  /// opposées. Ce fichier permet de lire la cause EXACTE depuis le Mac :
  ///
  ///   xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
  ///     --domain-identifier org.example.DSHRemote \
  ///     --source Documents/diagnostic.json --destination /tmp/diagnostic.json
  ///
  /// Il est écrasé à chaque échec : jamais de croissance, jamais d'historique.
  /// Le jeton n'y figure jamais, ni le contenu d'une session.
  private static func journaliserDiagnostic(adresse: String, message: String) {
    guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
      return
    }
    let contenu: [String: String] = [
      "adresse": adresse,
      "message": message,
      "date": ISO8601DateFormatter().string(from: Date()),
    ]
    guard let donnees = try? JSONSerialization.data(withJSONObject: contenu, options: [.prettyPrinted]) else {
      return
    }
    try? donnees.write(to: documents.appendingPathComponent("diagnostic.json"), options: .atomic)
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
