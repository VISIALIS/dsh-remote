import Foundation

/// CE QUE CE BUILD AUTORISE EN CLAIR — et ce qu'il a donc le droit de conseiller.
///
/// POURQUOI CE FICHIER EXISTE. La feuille « Adresse » conseillait
/// `http://mon-mac.mon-tailnet.ts.net` sur iPhone, sans condition. Or App
/// Transport Security refuse le clair vers un nom de domaine qualifié : ce
/// chemin ne fonctionne QUE dans un paquet qui porte une exception ATS, et
/// celle-ci est injectée dans le `.app` CONSTRUIT, depuis
/// `Config/DomaineTailnet` — un fichier local, non versionné, absent de tout
/// clone.
///
/// Conséquence mesurée : un clone se construit SANS ERREUR, se lance, et refuse
/// chaque machine du tailnet en `-1022` — pendant que l'interface continue de
/// conseiller l'adresse qui échoue. Le remède prescrit était la cause de la
/// panne.
///
/// LA RÈGLE, ICI : l'interface ne suppose pas ce que le paquet autorise, elle le
/// LIT. `NSAppTransportSecurity` vit dans l'Info.plist du paquet EN COURS
/// D'EXÉCUTION, donc la réponse est un fait constatable, jamais une déduction
/// sur la façon dont l'application a été construite. Un paquet sans exception ne
/// conseille plus jamais le clair vers un nom : il propose HTTPS, ou le script
/// qui pose l'exception.
public enum ExceptionATS {

  /// Une déclaration d'exception, telle qu'elle est écrite dans l'Info.plist.
  public struct Declaration: Equatable, Sendable {
    /// Le domaine déclaré, en minuscules (l'appariement d'ATS est littéral).
    public let domaine: String
    /// `NSExceptionAllowsInsecureHTTPLoads` — sans lui, la déclaration existe
    /// mais n'autorise rien : c'est le cas « présente et inopérante », le pire
    /// des deux, puisqu'elle se voit sans protéger.
    public let autoriseLeClair: Bool
    /// `NSIncludesSubdomains` — sans lui, l'exception ne couvre pas
    /// `<machine>.<domaine>`, c'est-à-dire aucune machine du tailnet.
    public let inclutLesSousDomaines: Bool

    public init(domaine: String, autoriseLeClair: Bool, inclutLesSousDomaines: Bool) {
      self.domaine = domaine
      self.autoriseLeClair = autoriseLeClair
      self.inclutLesSousDomaines = inclutLesSousDomaines
    }
  }

  static let cleRacine = "NSAppTransportSecurity"
  static let cleDomaines = "NSExceptionDomains"
  static let cleToutAutoriser = "NSAllowsArbitraryLoads"
  static let cleClair = "NSExceptionAllowsInsecureHTTPLoads"
  static let cleSousDomaines = "NSIncludesSubdomains"

  /// Les exceptions déclarées dans un dictionnaire d'Info.plist, triées par
  /// domaine : l'ordre est stable, donc affichable et éprouvable.
  public static func declarations(_ plist: [String: Any]?) -> [Declaration] {
    guard let racine = plist?[cleRacine] as? [String: Any],
      let domaines = racine[cleDomaines] as? [String: Any]
    else { return [] }
    return
      domaines
      .compactMap { nom, valeur -> Declaration? in
        guard let regles = valeur as? [String: Any] else { return nil }
        return Declaration(
          domaine: nom.lowercased(),
          autoriseLeClair: (regles[cleClair] as? Bool) ?? false,
          inclutLesSousDomaines: (regles[cleSousDomaines] as? Bool) ?? false)
      }
      .sorted { $0.domaine < $1.domaine }
  }

  /// Le drapeau qui lève tout. Il n'est jamais posé par les scripts du dépôt
  /// (une exception ciblée vaut mieux qu'une porte ouverte), mais un build qui
  /// le porterait autorise réellement le clair partout : le nier serait faux.
  public static func autoriseTout(_ plist: [String: Any]?) -> Bool {
    guard let racine = plist?[cleRacine] as? [String: Any] else { return false }
    return (racine[cleToutAutoriser] as? Bool) ?? false
  }

  /// Le clair vers CET hôte est-il autorisé par ce paquet ?
  ///
  /// L'appariement reproduit celui d'App Transport Security : le domaine exact,
  /// ou un sous-domaine quand `NSIncludesSubdomains` est déclaré — et le
  /// sous-domaine est cherché sur une ÉTIQUETTE entière, jamais sur une fin de
  /// chaîne quelconque (`pire-tailnet.ts.net` n'est pas un sous-domaine de
  /// `tailnet.ts.net`).
  public static func autoriseLeClair(vers hote: String, _ plist: [String: Any]?) -> Bool {
    if autoriseTout(plist) { return true }
    let cible = hote.lowercased()
    guard !cible.isEmpty else { return false }
    for declaration in declarations(plist) where declaration.autoriseLeClair {
      if cible == declaration.domaine { return true }
      if declaration.inclutLesSousDomaines, cible.hasSuffix("." + declaration.domaine) { return true }
    }
    return false
  }

  /// L'hôte d'une adresse : sans schéma, sans port, sans chemin, sans
  /// identifiants. `nil` quand il n'y a rien à juger (adresse vide).
  public static func hote(_ adresse: String) -> String? {
    let complete = RemoteClient.normaliser(adresse)
    guard !complete.isEmpty else { return nil }
    guard let composants = URLComponents(string: complete), let hote = composants.host,
      !hote.isEmpty
    else { return nil }
    return hote
  }

  /// L'adresse est-elle en CLAIR (donc soumise à ATS) ?
  ///
  /// Seul `http` l'est : `https` est ce qu'ATS veut, et une adresse sans schéma
  /// reçoit `http` de `RemoteClient.normaliser`.
  public static func estEnClair(_ adresse: String) -> Bool {
    RemoteClient.normaliser(adresse).lowercased().hasPrefix("http://")
  }

  /// Un nom qualifié, par opposition à une IP littérale ou à un nom local.
  ///
  /// POURQUOI LA DISTINCTION COMPTE ICI : ATS n'impose TLS qu'aux NOMS. Une
  /// adresse IP littérale (`http://100.x.y.z:3080`) et `localhost` en sont
  /// exemptés — les avertir ferait douter d'une adresse qui marche.
  public static func estUnNomQualifie(_ hote: String) -> Bool {
    let nom = hote.lowercased()
    if nom == "localhost" || nom.hasPrefix("localhost.") { return false }
    if nom.contains(":") { return false }  // IPv6 littérale
    if estUneIPv4(nom) { return false }
    return nom.contains(".")
  }

  private static func estUneIPv4(_ hote: String) -> Bool {
    let morceaux = hote.split(separator: ".", omittingEmptySubsequences: false)
    guard morceaux.count == 4 else { return false }
    return morceaux.allSatisfy { morceau in
      !morceau.isEmpty && morceau.count <= 3 && morceau.allSatisfy(\.isNumber)
    }
  }

  /// Les exceptions du paquet QUI EXÉCUTE CE CODE.
  public static var duBuildCourant: [Declaration] {
    declarations(Bundle.main.infoDictionary)
  }

  /// Ce code est-il SOUMIS à App Transport Security ?
  ///
  /// Sur iOS, toujours. Sur macOS, seulement dans une application empaquetée —
  /// et c'est une mesure, pas une supposition : lancé nu (binaire SwiftPM, donc
  /// sans Info.plist), `dsh-remote-ctl` joint le tailnet en clair et rend sa
  /// santé, là où le même code dans un `.app` sans exception échoue en `-1022`.
  /// Avertir un outil de développement d'un refus qui ne le concerne pas serait
  /// un faux positif, et un écran qui crie au loup n'est plus cru.
  public static var sousATS: Bool {
    #if os(macOS)
      return Bundle.main.bundleIdentifier != nil || Bundle.main.bundlePath.hasSuffix(".app")
    #else
      return true
    #endif
  }

  /// Le clair vers cet hôte sera-t-il refusé par ce paquet, SANS MÊME ESSAYER ?
  ///
  /// C'est la question à laquelle l'écran doit répondre avant la tentative :
  /// elle est faite pour ne pas envoyer l'utilisateur chercher une panne réseau
  /// là où le refus est déjà certain.
  public static func seraRefuse(_ adresse: String, _ plist: [String: Any]?) -> Bool {
    guard estEnClair(adresse), let hote = hote(adresse), estUnNomQualifie(hote) else {
      return false
    }
    return !autoriseLeClair(vers: hote, plist)
  }
}
