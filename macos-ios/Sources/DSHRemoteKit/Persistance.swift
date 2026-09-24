import Foundation

/// L'IDENTITÉ D'UN HÔTE : son nom (et son port), JAMAIS son transport.
///
/// POURQUOI UNE FONCTION NOMMÉE, ET UNE SEULE. Cette clé sert à deux choses qui
/// ne doivent PAS diverger : ranger le jeton d'un hôte, et ranger ses
/// préférences. Deux normalisations légèrement différentes feraient que le jeton
/// d'une machine se retrouverait sous une clé et ses réglages sous une autre —
/// et le symptôme serait « le jeton ne revient pas » sur une machine sur deux.
///
/// POURQUOI LE SCHÉMA N'EN FAIT PAS PARTIE — c'est une correction, et elle a une
/// conséquence visible. La clé portait l'adresse complète (« http://mac… »), donc
/// la MÊME machine publiée en `https` devenait une AUTRE machine : le jeton rangé
/// pour la forme en clair était introuvable, la machine jointe n'était plus
/// reconnue, et l'utilisateur devait se ré-appairer pour un simple changement de
/// transport. Or le transport ne dépend pas de l'hôte : il dépend de ce que le
/// paquet autorise et de ce que `tailscale serve` publie. L'identité s'arrête donc
/// au nom — avec son port, qui distingue bien deux services d'une même machine.
///
/// L'ANCIENNE CLÉ RESTE LISIBLE : `ModeleApp.jetonGarde` essaie aussi
/// « http://<clé> », réécrit le jeton sous la clé neuve et efface l'ancienne. Un
/// secret rangé par une version antérieure n'est donc pas perdu.
public enum IdentiteHote {
  public static func cle(_ adresse: String) -> String {
    let normalisee = RemoteClient.normaliser(adresse).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard let separateur = normalisee.range(of: "://") else { return normalisee }
    return String(normalisee[separateur.upperBound...])
  }
}

/// LES DEUX RÉGLAGES D'UNE MACHINE, gardés d'une session à l'autre.
///
/// POURQUOI ILS SONT PAR SERVEUR, ET NON GÉNÉRAUX. Les deux portent sur la
/// CONNEXION à une machine : le suivi décide si l'on interroge CE serveur
/// toutes les trois secondes, le filtre décide ce qu'on affiche de SA liste. Les
/// garder globaux faisait hériter silencieusement chaque serveur des choix faits
/// pour le précédent — on coupait le suivi pour un Mac endormi, et la machine
/// suivante ne se rafraîchissait plus sans qu'on sache pourquoi.
public struct PreferencesServeur: Codable, Equatable, Sendable {
  /// Interroger ce serveur périodiquement (pastilles d'état à jour).
  public var suivi = true
  /// N'afficher de sa liste que les sessions qu'il garde en mémoire.
  public var chargeesSeulement = true

  public init() {}
}

/// CE QUI SE RETROUVE À LA RÉOUVERTURE : où l'on regardait, et comment on écrit.
///
/// POURQUOI CE TYPE EXISTE. L'application repartait à zéro à chaque lancement :
/// espaces repliés, aucune session ouverte, mode d'envoi remis à « à la suite ».
/// Rien de tout cela n'est une décision qu'on prend à chaque ouverture — ce sont
/// des CHOIX DURABLES, et les redemander chaque fois coûte des gestes répétés.
///
/// CE QU'IL NE CONTIENT PAS. Aucune donnée de session : ni titre, ni journal, ni
/// identifiant de projet. Seulement des identifiants OPAQUES (chemin d'espace,
/// identifiant de session), qui ne disent rien du travail lui-même — et qui sont
/// revalidés à l'usage : une session qui n'existe plus n'est pas rouverte, un
/// espace inconnu n'est pas déplié.
///
/// POURQUOI LES ESPACES SONT UNE LISTE ET NON UN `Set`. `Set<String>` est
/// `Codable`, mais son encodage JSON n'a pas d'ordre : deux écritures du même
/// ensemble produisaient deux fichiers différents, ce qui rend un test de
/// persistance instable pour rien. La liste est triée à l'écriture.
public struct EtatDeNavigation: Codable, Equatable, Sendable {
  /// Les espaces de travail dépliés, par identifiant (le chemin du dossier).
  public var espacesDeplies: [String] = []
  /// Le mode d'envoi choisi — « à la suite » ou « tout de suite ».
  public var modeEnvoi: ModePrompt = .queue
  /// La session dont le journal était ouvert, si elle existe encore.
  public var sessionConsultee: String?

  public init() {}

  /// Les espaces dépliés, sous la forme qu'attend la vue.
  public var espacesDepliesEnsemble: Set<String> { Set(espacesDeplies) }
}

/// CE QUI SURVIT À L'APPLICATION : adresse mémorisée, préférences par serveur,
/// fichier d'amorçage, et le diagnostic d'un échec.
///
/// POURQUOI CE TYPE EXISTE. Ces écritures étaient dispersées dans `ModeleApp`,
/// mêlées aux transitions et au réseau : `UserDefaults`, un fichier JSON dans
/// Documents et un fichier d'amorçage y cohabitaient avec soixante états. Un type
/// qui ne fait QUE cela rend visible ce qui touche au disque — et surtout, il
/// s'injecte : les tests écrivent dans un domaine `UserDefaults` à eux et dans un
/// dossier temporaire, jamais dans les préférences de la machine qui les exécute.
///
/// ELLE N'EST PAS `Sendable`, ET C'EST VOULU : elle tient un `UserDefaults`, qui
/// ne l'est pas, et vit sur l'acteur principal avec le modèle. Prétendre le
/// contraire obligerait à un `@unchecked` qui masquerait un vrai partage.
///
/// CE QU'IL N'ÉCRIT JAMAIS : un jeton. Les secrets vont au trousseau ou en
/// mémoire (voir `GardienDeJetons`) ; ici il n'y a que des réglages, une adresse
/// — qui n'est pas un secret — et l'EMPREINTE d'un jeton, jamais le jeton.
public struct Persistance {
  /// Clés de `UserDefaults`. Publiques pour que les tests puissent nettoyer.
  public static let cleAdresse = "dsh-remote.derniere-adresse"
  public static let cleNomServeur = "dsh-remote.dernier-nom-serveur"
  public static let clePreferences = "dsh-remote.preferences-serveurs"
  public static let cleNavigation = "dsh-remote.navigation"
  public static let cleAlertes = "dsh-remote.alertes"
  public static let cleInstantaneWidget = "dsh-remote.instantane-widget"
  public static let nomDuFichierDAmorcage = "dsh-remote-config.json"
  public static let nomDuDiagnostic = "diagnostic.json"
  public static let identifiantGroupeAppParDefaut = "group.org.example.DSHRemote"

  /// Identifiant du groupe App résolu dynamiquement depuis le Info.plist (xcconfig) ou repli par défaut.
  public static var groupeAppActif: String {
    if let specifie = Bundle.main.object(forInfoDictionaryKey: "DSHAppGroup") as? String,
      !specifie.isEmpty,
      !specifie.hasPrefix("$(")
    {
      return specifie
    }
    return identifiantGroupeAppParDefaut
  }

  private let defaults: UserDefaults
  private let appGroupDefaults: UserDefaults?
  private let documents: URL?

  /// - Parameters:
  ///   - defaults: le domaine de préférences. Les tests en passent un à eux.
  ///   - appGroupDefaults: le domaine partagé pour les extensions (WidgetKit).
  ///   - documents: le dossier des documents de l'application (`nil` dans un
  ///     contexte sans conteneur — l'écriture est alors simplement ignorée).
  public init(
    defaults: UserDefaults = .standard,
    appGroupDefaults: UserDefaults? = UserDefaults(suiteName: Persistance.groupeAppActif),
    documents: URL? = Persistance.documentsParDefaut
  ) {
    self.defaults = defaults
    self.appGroupDefaults = appGroupDefaults
    self.documents = documents
  }

  /// Le dossier des documents de l'application, quand il existe.
  public static var documentsParDefaut: URL? {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
  }

  // MARK: - L'adresse mémorisée

  /// L'adresse et le nom retenus de la dernière session.
  public func lireAdresse() -> (adresse: String, nom: String?) {
    let memorisee = defaults.string(forKey: Self.cleAdresse) ?? ""
    return (memorisee, defaults.string(forKey: Self.cleNomServeur))
  }

  /// Retient l'adresse — et le nom, s'il est connu — dès la frappe.
  ///
  /// L'adresse n'est pas un secret : la mémoriser à la frappe ne coûte rien, et
  /// c'est précisément quand la connexion échoue qu'on veut la retrouver. Le
  /// jeton, lui, ne suit PAS ce chemin.
  public func memoriserAdresse(_ adresse: String, nom: String?) {
    defaults.set(adresse, forKey: Self.cleAdresse)
    if let nom { defaults.set(nom, forKey: Self.cleNomServeur) }
  }

  /// Oublie l'adresse mémorisée.
  public func oublierAdresse() {
    defaults.removeObject(forKey: Self.cleAdresse)
    defaults.removeObject(forKey: Self.cleNomServeur)
  }

  // MARK: - Les préférences par serveur

  public func lirePreferences() -> [String: PreferencesServeur] {
    guard let donnees = defaults.data(forKey: Self.clePreferences),
      let lues = try? JSONDecoder().decode([String: PreferencesServeur].self, from: donnees)
    else { return [:] }
    return lues
  }

  public func memoriserPreferences(_ preferences: [String: PreferencesServeur]) {
    guard let donnees = try? JSONEncoder().encode(preferences) else { return }
    defaults.set(donnees, forKey: Self.clePreferences)
  }

  // MARK: - Les alertes

  /// Les alertes sont ÉTEINTES par défaut, et l'absence de clé veut dire « non » :
  /// une application neuve n'a rien demandé, et n'a donc rien à se rappeler.
  public func lireAlertes() -> Bool {
    defaults.bool(forKey: Self.cleAlertes)
  }

  public func memoriserAlertes(_ actives: Bool) {
    defaults.set(actives, forKey: Self.cleAlertes)
  }

  // MARK: - L'état de navigation

  public func lireNavigation() -> EtatDeNavigation {
    guard let donnees = defaults.data(forKey: Self.cleNavigation),
      let lue = try? JSONDecoder().decode(EtatDeNavigation.self, from: donnees)
    else { return EtatDeNavigation() }
    return lue
  }

  public func memoriserNavigation(_ navigation: EtatDeNavigation) {
    guard let donnees = try? JSONEncoder().encode(navigation) else { return }
    defaults.set(donnees, forKey: Self.cleNavigation)
  }

  // MARK: - L'instantané du widget

  /// Écrit l'instantané dans le conteneur partagé pour WidgetKit.
  ///
  /// Si le domaine partagé est absent (ex. environnement de test ou absence d'entitlement),
  /// l'écriture se replie sur le domaine `defaults` ordinaire.
  public func memoriserInstantaneWidget(_ instantane: InstantaneWidget) {
    guard let donnees = try? JSONEncoder().encode(instantane) else { return }
    let cible = appGroupDefaults ?? defaults
    cible.set(donnees, forKey: Self.cleInstantaneWidget)
  }

  /// Lit le dernier instantané déposé pour le widget.
  public func lireInstantaneWidget() -> InstantaneWidget? {
    let source = appGroupDefaults ?? defaults
    guard let donnees = source.data(forKey: Self.cleInstantaneWidget),
      let instantane = try? JSONDecoder().decode(InstantaneWidget.self, from: donnees)
    else { return nil }
    return instantane
  }

  // MARK: - Le fichier d'amorçage

  /// Adresse et jeton déposés dans le conteneur de l'application.
  ///
  /// POURQUOI CE FICHIER EXISTE. `simctl launch` transmet ses arguments en
  /// `argv`, pas dans l'environnement : les surcharges par variable
  /// d'environnement n'arrivent donc pas à une application iOS, et il n'existe
  /// aucun autre moyen d'amorcer une application non signée sans saisie manuelle.
  ///
  /// PORTÉE RÉELLE : en production, ce fichier n'existe pas — il n'est jamais
  /// créé par l'application, et il doit être déposé explicitement dans un
  /// conteneur de simulateur. Sur un iPhone réel, rien ne le lit.
  public func lireAmorcage() -> (adresse: String?, jeton: String?) {
    guard let documents else { return (nil, nil) }
    let fichier = documents.appendingPathComponent(Self.nomDuFichierDAmorcage)
    guard let donnees = try? Data(contentsOf: fichier),
      let objet = try? JSONSerialization.jsonObject(with: donnees) as? [String: String]
    else { return (nil, nil) }
    let adresse = objet["adresse"].flatMap { $0.isEmpty ? nil : $0 }
    let jeton = objet["jeton"].flatMap { $0.count >= 20 ? $0 : nil }
    return (adresse, jeton)
  }

  // MARK: - Le diagnostic d'un échec

  /// EFFACE TOUT CE QUE L'APPLICATION A ÉCRIT DANS LES PRÉFÉRENCES, ET LE DIT.
  ///
  /// POURQUOI ELLE EST ICI, ET PAS DANS LE MODÈLE. Les clés sont définies dans ce
  /// fichier : les énumérer ailleurs, c'est se donner une liste à tenir à jour —
  /// et la première clé ajoutée sans y penser serait celle qu'une
  /// réinitialisation oublierait.
  ///
  /// - Returns: le nombre de clés effectivement retirées, pour le compte rendu.
  @discardableResult
  public func toutOublier() -> Int {
    var retirees = 0
    let cles = [
      Self.cleAdresse, Self.cleNomServeur, Self.clePreferences, Self.cleNavigation, Self.cleAlertes,
      Self.cleInstantaneWidget,
    ]
    for cle in cles {
      if defaults.object(forKey: cle) != nil {
        defaults.removeObject(forKey: cle)
        retirees += 1
      }
      if let appGroupDefaults, appGroupDefaults.object(forKey: cle) != nil {
        appGroupDefaults.removeObject(forKey: cle)
      }
    }
    return retirees
  }

  /// LE FICHIER D'AMORÇAGE EST-IL LÀ ? — et il n'est PAS effacé, délibérément.
  ///
  /// POURQUOI ON LE SIGNALE SANS LE SUPPRIMER. L'application ne l'écrit jamais :
  /// il a été déposé à la main, pour essayer, et le supprimer serait effacer le
  /// travail de quelqu'un d'autre. Mais s'il est là, il **ré-amorcera** au
  /// lancement suivant — adresse et jeton reviendront. Une réinitialisation qui
  /// ne le dit pas est celle qui ment : l'écran doit donc le nommer.
  public var amorcagePresent: Bool {
    guard let documents else { return false }
    return FileManager.default.fileExists(
      atPath: documents.appendingPathComponent(Self.nomDuFichierDAmorcage).path)
  }

  /// Efface le fichier de diagnostic, s'il existe. Rend `true` s'il a été retiré.
  @discardableResult
  public func effacerDiagnostic() -> Bool {
    guard let documents else { return false }
    let chemin = documents.appendingPathComponent(Self.nomDuDiagnostic)
    guard FileManager.default.fileExists(atPath: chemin.path) else { return false }
    do {
      try FileManager.default.removeItem(at: chemin)
      return true
    } catch {
      // Un fichier qu'on n'a pas pu retirer n'est pas un fichier retiré : on ne
      // l'annonce pas comme tel.
      return false
    }
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
  /// **Le jeton n'y figure jamais** — seulement son empreinte et sa longueur, ce
  /// qui suffit à dire SI le jeton détenu est celui du coffre.
  public func consignerDiagnostic(
    adresse: String, message: String, empreinteJeton: String, longueurJeton: Int
  ) {
    guard let documents else { return }
    let contenu: [String: String] = [
      "adresse": adresse,
      "message": message,
      "date": ISO8601DateFormatter().string(from: Date()),
      "empreinteJeton": empreinteJeton,
      "longueurJeton": String(longueurJeton),
    ]
    guard let donnees = try? JSONSerialization.data(withJSONObject: contenu, options: [.prettyPrinted]) else {
      return
    }
    try? donnees.write(to: documents.appendingPathComponent(Self.nomDuDiagnostic), options: .atomic)
  }
}
