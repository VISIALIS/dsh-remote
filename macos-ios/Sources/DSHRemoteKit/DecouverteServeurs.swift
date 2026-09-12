import Foundation

/// Un Mac joignable sur le tailnet, tel qu'on peut le proposer à l'utilisateur.
///
/// L'idée directrice : personne ne devrait avoir à taper
/// `http://<machine>.<tailnet>.ts.net` pour choisir un serveur.
/// La découverte interroge Tailscale ; l'utilisateur choisit un nom, l'adresse
/// en découle.
public struct ServeurMac: Sendable, Identifiable, Hashable {
  /// Nom lisible, tel que Tailscale le connaît (« MacMini », « MacBook Air de … »).
  public let nom: String
  /// Nom DNS complet, sans point final — c'est l'adresse du serveur.
  public let nomDNS: String
  public let enLigne: Bool
  /// Identifiant stable : le nom DNS.
  public var id: String { nomDNS }

  public init(nom: String, nomDNS: String, enLigne: Bool) {
    self.nom = nom
    self.nomDNS = nomDNS
    self.enLigne = enLigne
  }

  /// Adresse à donner au `RemoteClient`. `tailscale serve` publie sur le
  /// port 80 du nom MagicDNS, donc sans port explicite.
  public var adresse: String { "http://\(nomDNS)" }

  /// Symbole à afficher, déduit du nom de la machine.
  ///
  /// Tailscale ne rapporte PAS le modèle matériel (`tailscale status --json`
  /// donne le système d'exploitation, pas le châssis). On déduit donc l'icône du
  /// nom, que macOS construit à partir du modèle — « MacBook Air de … »,
  /// « MacMini ». C'est une heuristique d'affichage, assumée : une machine
  /// renommée « bureau » retombera sur l'icône générique, ce qui reste correct.
  public var symbole: String {
    // Deux formes à reconnaître : le NOM de la machine (« MacBook Air de … »)
    // et le NOM D'HÔTE Tailscale, qui remplace les espaces par des tirets
    // (`macbook-air-de-…`, `macmini`). Sans ce repli, une adresse saisie à la
    // main afficherait l'icône générique pour un portable.
    let minuscule = nom.lowercased().replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
    if minuscule.contains("macbook air") { return "macbook.air" }
    if minuscule.contains("macbook pro") { return "macbook.pro" }
    if minuscule.contains("macbook") { return "macbook" }
    // « macmini » et « mac mini » se ramènent tous deux à « macmini » après
    // retrait des séparateurs.
    let compact = minuscule.replacingOccurrences(of: " ", with: "")
    if compact.contains("macmini") { return "macmini" }
    if compact.contains("macstudio") { return "macstudio" }
    if compact.contains("imac") { return "desktopcomputer" }
    return "desktopcomputer"
  }

  /// Vrai si ce Mac est celui qui exécute l'application (donc joignable en local).
  public var estLocal: Bool { false }
}

/// Découverte des Macs joignables.
///
/// ÉTAT RÉEL, MESURÉ, ET SA LIMITE — à lire avant de s'étonner que la liste soit
/// vide :
///
///   1. Sur iPhone, la découverte automatique est IMPOSSIBLE : une application
///      iOS ne peut pas exécuter de processus, et le socket LocalAPI de
///      l'application Tailscale n'est pas accessible depuis un autre bac à
///      sable. Rien à corriger : c'est la plateforme.
///   2. Sur macOS, `tailscale status --json` échoue aujourd'hui avec
///      « The current bundleIdentifier is unknown to the registry » : le CLI
///      exige un contexte applicatif que ce binaire n'a pas. Fournir
///      `__CFBundleIdentifier` n'y change rien (essayé, avec
///      `io.tailscale.ipn.macos`).
///
/// CONSÉQUENCE ASSUMÉE : la saisie manuelle de l'adresse reste le chemin
/// principal, et la liste des machines est un CONFORT quand elle est
/// disponible. L'interface ne doit donc jamais dépendre d'elle — et quand elle
/// est vide, elle doit dire POURQUOI et quoi faire, pas rester muette.
public enum DecouverteServeurs {
  /// Chemins usuels du binaire, dans l'ordre d'essai.
  /// Chemins essayés dans l'ordre.
  ///
  /// Le binaire du paquet `.app` est en DERNIER : mesuré, il échoue avec
  /// « The current bundleIdentifier is unknown to the registry », comme celui
  /// du chemin utilisateur. Les binaires en ligne de commande sont donc tentés
  /// d'abord, et l'échec est rapporté au lieu d'être masqué.
  private static let cheminsBinaire = [
    "/usr/local/bin/tailscale",
    "/opt/homebrew/bin/tailscale",
    "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
  ]

  private static func binaire() -> String? {
    let maison = NSHomeDirectory()
    let candidats = cheminsBinaire + ["\(maison)/.local/bin/tailscale"]
    for chemin in candidats where FileManager.default.isExecutableFile(atPath: chemin) {
      return chemin
    }
    return nil
  }

  /// Macs du tailnet, ceux de cette machine inclus, triés : en ligne d'abord.
  ///
  /// Ne lève jamais. Une découverte impossible rend une liste vide, ce qui est
  /// un état normal et non une erreur : l'utilisateur garde la saisie manuelle.
  /// Vrai si Tailscale semble installé sur CETTE machine.
  ///
  /// Sert à distinguer « pas de tailnet configuré » de « Tailscale absent » :
  /// les deux donnent une liste vide, mais n'appellent pas le même message.
  public static func tailscaleSembleInstalle() -> Bool {
    #if os(macOS)
      if binaire() != nil { return true }
      return FileManager.default.fileExists(atPath: "/Applications/Tailscale.app")
    #else
      // Sur iPhone, la seule trace fiable est l'application elle-meme :
      // le systeme ne publie pas la liste des applications installees.
      return false
    #endif
  }

  /// Message à afficher quand aucune machine n'a pu être trouvée.
  ///
  /// Il nomme la cause ET l'action. Une liste vide sans explication laisse
  /// croire à une panne de l'application, alors que la cause est presque
  /// toujours l'absence de Tailscale ou une adresse à saisir à la main.
  public static func messageDAbsence() -> String {
    if let diagnostic, !diagnostic.isEmpty {
      #if os(macOS)
        return "Découverte automatique indisponible (\(diagnostic)). Saisissez l'adresse du Mac ci-dessous."
      #else
        return "Saisissez l'adresse du Mac ci-dessous."
      #endif
    }
    if tailscaleSembleInstalle() {
      return "Aucun Mac trouvé sur le tailnet. Vérifiez que Tailscale est connecté, puis rafraîchissez."
    }
    #if os(macOS)
      return "Tailscale ne semble pas installé : installez-le, connectez-vous, puis rafraîchissez."
    #else
      return "La liste des Macs ne peut pas être découverte depuis un iPhone : iOS interdit à une application d'interroger Tailscale. Saisissez l'adresse du Mac ci-dessous — et vérifiez que Tailscale est installé et connecté sur cet iPhone, sans quoi l'adresse ne répondra pas."
    #endif
  }

  public static func macsDuTailnet() -> [ServeurMac] {
    #if os(macOS)
      guard let binaire = binaire() else {
        diagnostic = "binaire tailscale introuvable"
        return []
      }
      let processus = Process()
      processus.executableURL = URL(fileURLWithPath: binaire)
      processus.arguments = ["status", "--json"]
      let tube = Pipe()
      let erreurs = Pipe()
      processus.standardOutput = tube
      processus.standardError = erreurs
      do {
        try processus.run()
      } catch {
        // Un échec muet rend le diagnostic impossible : on garde la raison.
        diagnostic = "exécution impossible: \(error.localizedDescription)"
        return []
      }
      let donnees = tube.fileHandleForReading.readDataToEndOfFile()
      processus.waitUntilExit()
      guard processus.terminationStatus == 0 else {
        let texte = String(data: erreurs.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        diagnostic = "tailscale a échoué (code \(processus.terminationStatus)): \(texte.prefix(200))"
        return []
      }
      let macs = analyser(donnees)
      diagnostic = macs.isEmpty ? "sortie analysée mais aucun Mac macOS trouvé" : nil
      return macs
    #else
      diagnostic = "découverte automatique indisponible sur cette plateforme"
      return []
    #endif
  }

  /// Dernière raison d'échec de la découverte, pour l'affichage et le diagnostic.
  ///
  /// Une liste vide sans explication est indébogable : on ne sait pas si le
  /// binaire manque, si le tailnet est injoignable ou si la sortie est
  /// illisible. Ces trois causes demandent des corrections différentes.
  public private(set) nonisolated(unsafe) static var diagnostic: String?

  /// Analyse la sortie de `tailscale status --json`.
  ///
  /// Séparée de l'exécution pour être testable sans lancer de processus.
  static func analyser(_ donnees: Data) -> [ServeurMac] {
    guard
      let racine = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any]
    else { return [] }

    var trouves: [ServeurMac] = []

    func retenir(_ objet: [String: Any], soiMeme: Bool) {
      guard (objet["OS"] as? String) == "macOS" else { return }
      guard let dns = objet["DNSName"] as? String, !dns.isEmpty else { return }
      let nom = (objet["HostName"] as? String) ?? dns
      // Le point final est la forme absolue du DNS : on le retire pour que
      // l'adresse soit directement utilisable.
      let propre = dns.hasSuffix(".") ? String(dns.dropLast()) : dns
      let enLigne = soiMeme ? true : ((objet["Online"] as? Bool) ?? false)
      trouves.append(ServeurMac(nom: nom, nomDNS: propre, enLigne: enLigne))
    }

    if let soi = racine["Self"] as? [String: Any] { retenir(soi, soiMeme: true) }
    if let pairs = racine["Peer"] as? [String: Any] {
      for (_, valeur) in pairs {
        if let objet = valeur as? [String: Any] { retenir(objet, soiMeme: false) }
      }
    }

    // En ligne d'abord, puis par nom : l'ordre doit être stable entre deux
    // ouvertures, sinon la liste semble sauter d'un affichage à l'autre.
    return trouves.sorted { gauche, droite in
      if gauche.enLigne != droite.enLigne { return gauche.enLigne }
      return gauche.nom.localizedStandardCompare(droite.nom) == .orderedAscending
    }
  }
}
