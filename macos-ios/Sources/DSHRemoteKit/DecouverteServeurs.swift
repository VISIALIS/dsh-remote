import Foundation

/// Un Mac joignable sur le tailnet, tel qu'on peut le proposer à l'utilisateur.
///
/// L'idée directrice : personne ne devrait avoir à taper
/// `http://<machine>.<tailnet>.ts.net` pour choisir un serveur.
/// La découverte interroge Tailscale — localement sur macOS, ou par l'hôte DSH
/// déjà joint, ce qui est la seule voie possible depuis un iPhone ; l'utilisateur
/// choisit un nom, l'adresse en découle.
public struct ServeurMac: Sendable, Identifiable, Hashable, Decodable {
  /// Nom lisible, tel que Tailscale le connaît (« MacMini », « MacBook Air de … »).
  public let nom: String
  /// Nom DNS complet, sans point final — c'est l'adresse du serveur.
  public let nomDNS: String
  public let enLigne: Bool
  /// Vrai pour la machine qui a RÉPONDU à la découverte — donc celle qui exécute
  /// l'instance DSH interrogée. Ce n'est pas forcément celle qui exécute
  /// l'application : c'est justement l'intérêt, un iPhone n'exécute aucun serveur.
  /// Seul l'hôte peut renseigner ce champ ; la découverte locale le laisse faux.
  public let estLocal: Bool
  /// Identifiant stable : le nom DNS.
  public var id: String { nomDNS }

  public init(nom: String, nomDNS: String, enLigne: Bool, estLocal: Bool = false) {
    self.nom = nom
    self.nomDNS = nomDNS
    self.enLigne = enLigne
    self.estLocal = estLocal
  }

  enum CodingKeys: String, CodingKey {
    case nom, nomDNS, enLigne
    case estLocal = "local"
  }

  /// Décodage TOLÉRANT, à dessein.
  ///
  /// Seuls `nom` et `nomDNS` sont exigés — sans eux il n'y a ni libellé ni
  /// adresse, donc rien à proposer. Les deux booléens sont facultatifs : un hôte
  /// qui n'annonce pas `local` ne doit pas faire échouer TOUTE la liste pour un
  /// champ d'affichage. Une liste vide à cause d'un détail serait un défaut bien
  /// plus coûteux que l'absence d'un badge.
  public init(from decoder: any Decoder) throws {
    let conteneur = try decoder.container(keyedBy: CodingKeys.self)
    self.nom = try conteneur.decode(String.self, forKey: .nom)
    self.nomDNS = try conteneur.decode(String.self, forKey: .nomDNS)
    self.enLigne = try conteneur.decodeIfPresent(Bool.self, forKey: .enLigne) ?? false
    self.estLocal = try conteneur.decodeIfPresent(Bool.self, forKey: .estLocal) ?? false
  }

  /// Adresse à donner au `RemoteClient` : `https` quand ce paquet REFUSE le clair
  /// vers un nom qualifié, `http` sinon (voir `AdresseMachine`).
  ///
  /// LA RÈGLE ÉTAIT `"http://\(nomDNS)"` EN DUR, et c'était le plus gros obstacle
  /// à la distribution : un clone du dépôt — donc un paquet SANS exception ATS —
  /// proposait une adresse que le système refusait (`-1022`) pour chaque machine
  /// du tailnet. Le port suit le transport : 443 pour `https`, 80 pour `http`,
  /// les deux conventions que `tailscale serve` publie.
  public var adresse: String { AdresseMachine.pour(hote: nomDNS) }

  /// Premier mot du nom, pour la légende d'une icône de serveur.
  ///
  /// POURQUOI UN SEUL MOT. Un nom de machine Tailscale est long — « MacBook Air
  /// de Camille », « MacStudio Atelier » — et une légende d'icône se lit d'un
  /// mot : au-delà, elle est tronquée à l'écran et n'apprend rien. Le nom
  /// complet reste lu par VoiceOver, qui n'a pas cette contrainte de place.
  ///
  /// ATTENTION : CE N'EST PAS TOUJOURS ASSEZ. Deux machines peuvent partager leur
  /// premier mot — « Portable Un » et « Portable Deux » —, et l'appui sur une
  /// vignette change la connexion. Le carrousel n'emploie donc pas cette
  /// propriété : il demande à `NomsCourts` les libellés de la LISTE, qui
  /// s'allongent quand un mot ne distingue pas. Celle-ci reste pour les écrans qui
  /// nomment UNE machine sans connaître ses voisines (une page, un message).
  ///
  /// La règle de découpage vit dans `NomsCourts.raccourci`, pour qu'il n'y en ait
  /// qu'une.
  public var premierMot: String {
    NomsCourts.raccourci(nom, mots: 1)
  }

  /// Symbole à afficher, déduit du nom de la machine.
  ///
  /// Tailscale ne rapporte PAS le modèle matériel (`tailscale status --json`
  /// donne le système d'exploitation, pas le châssis). On déduit donc l'icône du
  /// nom, que macOS construit à partir du modèle — « MacBook Air de … »,
  /// « MacMini ». C'est une heuristique d'affichage, assumée : une machine
  /// renommée « bureau » retombera sur l'icône générique, ce qui reste correct.
  ///
  /// MESURÉ, ET CORRIGÉ APRÈS UNE CAPTURE D'ÉCRAN : `macbook.air`,
  /// `macbook.pro` et `imac` NE SONT PAS des symboles SF. `Image(systemName:)`
  /// ne se plaint pas — il n'affiche RIEN — donc ces trois branches rendaient une
  /// ligne sans icône, et le repli n'était jamais atteint puisqu'un nom était
  /// bien rendu. Les seuls symboles employés ici sont désormais ceux qui
  /// existent, et un test vérifie qu'ils se résolvent tous.
  ///
  /// SF Symbols ne distingue pas un Air d'un Pro : l'icône dit « portable » ou
  /// « bureau », ce que la donnée porte réellement. Prétendre au modèle serait
  /// une promesse que la source ne permet pas de tenir.
  public var symbole: String {
    // Deux formes à reconnaître : le NOM de la machine (« MacBook Air de … »)
    // et le NOM D'HÔTE Tailscale, qui remplace les espaces par des tirets
    // (`macbook-air-de-…`, `macmini`). Sans ce repli, une adresse saisie à la
    // main afficherait l'icône générique pour un portable.
    let minuscule = nom.lowercased().replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
    if minuscule.contains("macbook") { return "macbook" }
    // « macmini » et « mac mini » se ramènent tous deux à « macmini » après
    // retrait des séparateurs.
    let compact = minuscule.replacingOccurrences(of: " ", with: "")
    if compact.contains("macmini") { return "macmini" }
    if compact.contains("macstudio") { return "macstudio" }
    return "desktopcomputer"
  }

}

/// Découverte des machines joignables.
///
/// DEUX SOURCES, DANS CET ORDRE DE QUALITÉ :
///
///   1. **L'hôte DSH déjà joint** (`GET /dsh-remote/v1/serveurs`, lu par
///      `RemoteClient.listerServeurs`). C'est la voie retenue : l'hôte tourne sur
///      un Mac qui a Tailscale, il publie la liste, et l'application la LIT. Elle
///      marche donc sur iPhone, où rien d'autre ne marche.
///   2. **Le Tailscale local** (`machinesDuTailnet`, macOS seulement). Utile quand
///      aucun serveur n'est encore connu — c'est-à-dire au tout premier
///      lancement, et pour le tool `dsh-remote-ctl`.
///
/// CE QUI EST MESURÉ, ET QUI A COÛTÉ DU TEMPS :
///
///   1. Sur iPhone, la découverte LOCALE est impossible : une application iOS ne
///      peut pas exécuter de processus, et le socket LocalAPI de l'application
///      Tailscale n'est pas accessible depuis un autre bac à sable. C'est
///      pourquoi la source n° 1 existe.
///   2. Sur macOS, `tailscale status --json` dépend du CHEMIN employé pour
///      lancer le binaire : `/usr/local/bin/tailscale` est un lien symbolique
///      vers le binaire de l'application, et par ce lien le CLI échoue avec
///      « The current bundleIdentifier is unknown to the registry » — alors que
///      le chemin direct réussit. On essaie donc les candidats jusqu'à un
///      SUCCÈS, et non jusqu'au premier fichier exécutable.
///
/// CONSÉQUENCE ASSUMÉE : la saisie manuelle de l'adresse reste possible, mais
/// elle n'est plus le chemin principal. Une liste vide doit dire POURQUOI et
/// quoi faire, pas rester muette.
public enum DecouverteServeurs {
  /// Chemins usuels du binaire, dans l'ordre d'essai.
  ///
  /// Le binaire de l'application vient en PREMIER : c'est le seul qui réponde
  /// sur une installation où `/usr/local/bin/tailscale` n'est qu'un lien
  /// symbolique vers lui. `~/.local/bin/tailscale` est ajouté par `binaire()`,
  /// juste après, car c'est là que le lanceur de l'application s'installe sur
  /// certaines machines.
  private static let cheminsBinaire = [
    "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
    "/opt/homebrew/bin/tailscale",
    "/usr/local/bin/tailscale",
  ]

  /// LES SYSTÈMES QUI PEUVENT HÉBERGER DSH — et ceux qui ne le peuvent pas.
  ///
  /// POURQUOI CETTE RÈGLE A CHANGÉ. Elle ne retenait que `macOS` : « proposer un
  /// PC Windows ou un iPhone comme serveur DSH serait une promesse que
  /// l'installation ne peut pas tenir ». La prémisse était fausse, et le
  /// propriétaire l'a relevée : « il y a un serveur windows qui n'est pas listé,
  /// or le serveur DSH est universel non ? c'est juste le remote qui est macOS ou
  /// iOS ». DSH est un harness Node : il tourne aussi sur Windows et sur Linux —
  /// le harness publie même un bac à sable Windows ACL. C'est l'APPLICATION
  /// CLIENT qui est macOS et iOS, pas l'hôte.
  ///
  /// Ce qui reste écarté, ce sont les systèmes qui ne peuvent pas exécuter de
  /// processus : iOS, iPadOS, Android, tvOS. Un iPhone ne peut pas héberger DSH.
  /// La liste est donc une LISTE BLANCHE — un système inconnu n'est pas proposé —
  /// et elle est IDENTIQUE à celle du plugin (`SYSTEMES_QUI_HEBERGENT`,
  /// `dynamic/tailscale.js`) : deux listes qui divergeraient feraient apparaître
  /// une machine côté hôte et pas côté client.
  ///
  /// CE QU'ELLE NE PROMET PAS : qu'une machine serve DSH. Elle dit qu'elle
  /// POURRAIT l'héberger ; c'est la sonde qui tranche, et une machine qui ne
  /// répond pas s'affiche « pas de DSH ».
  static let systemesQuiHebergent: Set<String> = ["macOS", "windows", "linux"]

  /// Candidats existants, dans l'ordre d'essai.
  private static func candidats() -> [String] {
    let maison = NSHomeDirectory()
    var liste = cheminsBinaire
    liste.insert("\(maison)/.local/bin/tailscale", at: 1)
    return liste.filter { FileManager.default.isExecutableFile(atPath: $0) }
  }

  /// Dernier binaire qui a RÉPONDU — et non simplement existé.
  ///
  /// Le conserver évite de repayer, à chaque rafraîchissement, l'échec des
  /// candidats qui ne répondent pas. `nonisolated(unsafe)` comme `diagnostic` :
  /// la découverte locale est lancée depuis une tâche détachée unique, et une
  /// course ne coûterait qu'un essai supplémentaire.
  public private(set) nonisolated(unsafe) static var binaireRetenu: String?

  /// Candidats à essayer, celui déjà éprouvé en tête.
  private static func candidatsOrdonnes() -> [String] {
    var liste = candidats()
    guard let retenu = binaireRetenu, let index = liste.firstIndex(of: retenu) else { return liste }
    liste.remove(at: index)
    liste.insert(retenu, at: 0)
    return liste
  }

  /// Macs du tailnet, ceux de cette machine inclus, triés : en ligne d'abord.
  ///
  /// Ne lève jamais. Une découverte impossible rend une liste vide, ce qui est
  /// un état normal et non une erreur : l'utilisateur garde la saisie manuelle.
  public static func machinesDuTailnet() -> [ServeurMac] {
    #if os(macOS)
      var raisons: [String] = []
      // On essaie CHAQUE candidat jusqu'à une réponse exploitable : le premier
      // fichier exécutable n'est pas forcément celui qui sait parler à
      // l'application Tailscale (voir l'en-tête de ce fichier).
      for binaire in candidatsOrdonnes() {
        let resultat = interroger(binaire)
        if let macs = resultat.macs {
          binaireRetenu = binaire
          diagnostic = macs.isEmpty ? "aucune machine du tailnet" : nil
          return macs
        }
        raisons.append(resultat.raison)
      }
      diagnostic = raisons.isEmpty ? "binaire tailscale introuvable" : "tailscale muet: \(raisons[0])"
      return []
    #else
      diagnostic = "découverte locale impossible sur cette plateforme"
      return []
    #endif
  }

  /// Lance un candidat et rend soit les Macs trouvés, soit la raison de l'échec.
  ///
  /// Le message d'erreur de Tailscale est tronqué à sa première ligne : il part
  /// dans un message affiché à l'utilisateur, pas dans un journal.
  ///
  /// `#if os(macOS)` N'EST PAS DÉCORATIF : `Process` n'existe pas sur iOS, et
  /// sans cette borne la compilation de l'application iPhone échoue. C'est aussi
  /// la formulation exacte du fait — cette voie n'existe que sur macOS.
  #if os(macOS)
    private static func interroger(_ binaire: String) -> (macs: [ServeurMac]?, raison: String) {
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
        return (nil, "exécution impossible: \(error.localizedDescription)")
      }
      let donnees = tube.fileHandleForReading.readDataToEndOfFile()
      processus.waitUntilExit()
      guard processus.terminationStatus == 0 else {
        let texte = String(data: erreurs.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let ligne = texte.split(separator: "\n").first.map(String.init) ?? ""
        return (nil, "tailscale a échoué (code \(processus.terminationStatus)): \(ligne.prefix(120))")
      }
      // LE CODE DE SORTIE NE SUFFIT PAS — mesuré. Voir `analyserEtat` : un CLI
      // qui n'a pas pu joindre Tailscale écrit son erreur sur STDOUT et sort en
      // code 0. On exige donc un état LISIBLE, sinon on passe au candidat
      // suivant en gardant ce que le CLI a dit.
      guard let macs = analyserEtat(donnees) else {
        return (nil, raisonCourte(donnees, defaut: "sortie illisible"))
      }
      return (macs, "")
    }
  #endif

  /// Première ligne non vide d'une sortie, tronquée — de quoi dire POURQUOI.
  ///
  /// Le CLI Tailscale écrit ses erreurs sur stdout, pas sur stderr : les ignorer
  /// rendrait l'échec muet, et un échec muet se diagnostique à l'aveugle.
  private static func raisonCourte(_ donnees: Data, defaut: String) -> String {
    let texte = String(data: donnees, encoding: .utf8) ?? ""
    let ligne = texte.split(separator: "\n").first.map(String.init) ?? ""
    let propre = ligne.trimmingCharacters(in: .whitespaces)
    return propre.isEmpty ? defaut : String(propre.prefix(120))
  }

  /// Vrai si Tailscale semble installé sur CETTE machine.
  ///
  /// Sert à distinguer « pas de tailnet configuré » de « Tailscale absent » :
  /// les deux donnent une liste vide, mais n'appellent pas le même message.
  public static func tailscaleSembleInstalle() -> Bool {
    #if os(macOS)
      if !candidats().isEmpty { return true }
      return FileManager.default.fileExists(atPath: "/Applications/Tailscale.app")
    #else
      // Sur iPhone, la seule trace fiable est l'application elle-meme :
      // le systeme ne publie pas la liste des applications installees.
      return false
    #endif
  }

  /// Message à afficher quand la liste est vide ET qu'aucun hôte n'a pu être
  /// interrogé.
  ///
  /// Il nomme la cause ET l'action. Une liste vide sans explication laisse
  /// croire à une panne de l'application, alors que la cause est presque
  /// toujours l'absence de Tailscale ou une adresse à saisir à la main — une
  /// seule fois.
  public static func messageDAbsence() -> String {
    #if os(macOS)
      if let diagnostic, !diagnostic.isEmpty {
        return "Découverte automatique indisponible (\(diagnostic)). Saisissez l'adresse de la machine ci-dessous."
      }
      if tailscaleSembleInstalle() {
        return "Aucune machine trouvée sur le tailnet. Vérifiez que Tailscale est connecté, puis rafraîchissez."
      }
      return "Tailscale ne semble pas installé : installez-le, connectez-vous, puis rafraîchissez."
    #else
      // On ne dit plus « impossible sur iPhone » : la découverte y est
      // impossible LOCALEMENT, mais un hôte déjà joint publie la liste. Le
      // message donne donc l'action qui débloque, au lieu d'un constat.
      return
        "Saisissez l'adresse d'une machine ci-dessous, puis connectez-vous : elle publiera ensuite la liste des machines de votre tailnet."
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
  /// Rend `[]` quand la sortie n'est pas exploitable. `analyserEtat` est la
  /// version STRICTE, employée par la découverte, qui doit distinguer « le
  /// tailnet est vide » de « le CLI n'a rien répondu ».
  static func analyser(_ donnees: Data) -> [ServeurMac] {
    analyserEtat(donnees) ?? []
  }

  /// Analyse STRICTE : `nil` signifie « le CLI n'a pas rendu d'état lisible ».
  ///
  /// POURQUOI CETTE DISTINCTION EXISTE — MESURÉ, ET C'EST UN DÉFAUT QUI A ÉTÉ
  /// VU À L'ÉCRAN. Lancé depuis une application ouverte par le Finder, le CLI
  /// Tailscale n'arrive pas à joindre son application et écrit :
  ///
  ///     The Tailscale GUI failed to start: … (Tailscale.CLIError error 3.)
  ///
  /// sur **stdout**, en sortant avec le **code 0**. Un code de sortie nul ne
  /// prouve donc rien. Le prendre pour un succès produisait deux fautes :
  /// l'analyse rendait `[]`, et la boucle des candidats s'ARRÊTAIT au premier
  /// au lieu d'essayer le suivant — alors que le lanceur `~/.local/bin/tailscale`
  /// répond, lui, dans ce même environnement. L'application annonçait donc
  /// « aucun Mac macOS dans le tailnet » : un mensonge, puisque le tailnet allait
  /// très bien et que c'était le CLI qui n'avait pas parlé.
  ///
  /// Un état Tailscale digne de ce nom porte `Self`. Sans lui, ce n'est pas un
  /// tailnet vide — c'est une réponse qui ne dit rien.
  static func analyserEtat(_ donnees: Data) -> [ServeurMac]? {
    guard let racine = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any] else { return nil }
    guard racine["Self"] is [String: Any] else { return nil }
    return analyserRacine(racine)
  }

  private static func analyserRacine(_ racine: [String: Any]) -> [ServeurMac] {
    var trouves: [ServeurMac] = []

    func retenir(_ objet: [String: Any], soiMeme: Bool) {
      guard let systeme = objet["OS"] as? String, systemesQuiHebergent.contains(systeme) else { return }
      guard let dns = objet["DNSName"] as? String, !dns.isEmpty else { return }
      let nom = (objet["HostName"] as? String) ?? dns
      // Le point final est la forme absolue du DNS : on le retire pour que
      // l'adresse soit directement utilisable.
      let propre = dns.hasSuffix(".") ? String(dns.dropLast()) : dns
      let enLigne = soiMeme ? true : ((objet["Online"] as? Bool) ?? false)
      trouves.append(ServeurMac(nom: nom, nomDNS: propre, enLigne: enLigne, estLocal: soiMeme))
    }

    if let soi = racine["Self"] as? [String: Any] { retenir(soi, soiMeme: true) }
    if let pairs = racine["Peer"] as? [String: Any] {
      for (_, valeur) in pairs {
        if let objet = valeur as? [String: Any] { retenir(objet, soiMeme: false) }
      }
    }

    // En ligne d'abord, puis par nom : c'est la règle d'affichage sans verdict de
    // sonde — la découverte ne sait rien de ce qui sert DSH, et c'est
    // `ModeleApp.serveursAffiches` qui apporte ce fait.
    return ordonnerPourAffichage(trouves)
  }

  /// L'ORDRE D'AFFICHAGE DES MACHINES — JOIGNABLES D'ABORD, PRÊTES EN PREMIER.
  ///
  /// DEUX CLÉS, DANS CET ORDRE, ET RIEN D'AUTRE :
  ///
  ///   1. la machine JOIGNABLE avant celle qui ne l'est pas — une machine éteinte
  ///      ne peut rien rendre, quelle que soit sa configuration ;
  ///   2. à joignabilité égale, celle qui SERT DSH (« prête ») avant celle qui
  ///      reste à configurer : c'est celle-là qu'on vient ouvrir.
  ///
  /// À égalité sur les deux, l'ordre est celui du nom — et il ne dépend NI de la
  /// sélection, NI du dernier choix, NI de l'heure. **L'ordre ne doit pas bouger
  /// sous le doigt** de celui qui vient de toucher une vignette : un tri par
  /// « machine connectée d'abord » a existé ici, et il est retiré pour cette
  /// raison précise — la vignette visée sautait à l'instant où on la touchait.
  ///
  /// La vignette « Ajouter » n'entre pas dans ce tri : elle est rendue APRÈS la
  /// liste, donc après les machines hors ligne.
  ///
  /// - Parameters:
  ///   - serveurs: les machines à ordonner.
  ///   - sertDsh: le verdict de la sonde pour une machine — `true` = elle sert
  ///     DSH. Par défaut aucune n'est déclarée prête : la découverte locale, qui
  ///     ne sonde rien, garde l'ordre « joignable d'abord, puis par nom ».
  static func ordonnerPourAffichage(
    _ serveurs: [ServeurMac], sertDsh: (ServeurMac) -> Bool = { _ in false }
  ) -> [ServeurMac] {
    serveurs.sorted { gauche, droite in
      if gauche.enLigne != droite.enLigne { return gauche.enLigne }
      let gauchePrete = sertDsh(gauche)
      let droitePrete = sertDsh(droite)
      if gauchePrete != droitePrete { return gauchePrete }
      return gauche.nom.localizedStandardCompare(droite.nom) == .orderedAscending
    }
  }
}
