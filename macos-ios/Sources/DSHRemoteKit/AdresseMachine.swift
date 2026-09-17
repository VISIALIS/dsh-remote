import Foundation

/// L'ADRESSE À VISER POUR UNE MACHINE — décidée par ce que le paquet AUTORISE.
///
/// POURQUOI CETTE PIÈCE EXISTE. Trois endroits fabriquaient une adresse en
/// écrivant `"http://" + hote` : le QR d'appairage, la liste des machines
/// découvertes, et la saisie manuelle. Or App Transport Security REFUSE le clair
/// vers un nom de domaine qualifié, et il ne l'autorise que si le paquet construit
/// porte une exception — posée depuis `Config/DomaineTailnet`, un fichier local
/// absent de tout clone. Conséquence mesurée, et c'était le plus gros obstacle à
/// la distribution : **un clone se construisait sans erreur et refusait tout le
/// tailnet en `-1022`**, y compris pour s'appairer.
///
/// LA RÈGLE EST DONC UNE SEULE LIGNE, ET C'EST LA BONNE : si ce paquet refuse le
/// clair vers cet hôte, viser `https` ; sinon `http`. Elle n'invente rien — elle
/// LIT ce que `ExceptionATS` constate déjà dans l'Info.plist du paquet en cours
/// d'exécution, la même source que le conseil affiché à l'écran.
///
/// POURQUOI PAS DANS `RemoteClient.normaliser`. `normaliser` est PUR et ne
/// connaît que la forme d'une adresse ; `ExceptionATS` l'appelle
/// (`ExceptionATS.hote`), donc l'y faire lire le paquet créerait un cycle. La
/// décision vit ici, et les trois appelants la lisent.
///
/// CE QUI RESTE EN CLAIR, ET POURQUOI C'EST CORRECT : une adresse IP littérale et
/// `localhost` ne sont pas soumis à ATS, donc `seraRefuse` rend `false` et ils
/// restent en `http` — c'est le cas mesuré de `http://100.x.y.z:3080` et de la
/// boucle locale, qui n'ont aucune raison de payer un certificat.
public enum AdresseMachine {

  /// L'adresse à donner au client pour ce nom d'hôte.
  ///
  /// - Parameters:
  ///   - hote: un nom MagicDNS, une IP littérale, ou `localhost` — sans schéma.
  ///   - plist: l'Info.plist à interroger. Par défaut celui du paquet EN COURS
  ///     D'EXÉCUTION, parce que la question est « que ce paquet autorise-t-il ? »
  ///     et que la réponse est un fait constatable, jamais une déduction sur la
  ///     façon dont l'application a été construite. Les tests passent le leur.
  /// - Returns: l'adresse complète, ou une chaîne vide si l'hôte est vide (il n'y
  ///   a alors rien à viser, et `http://` tout seul serait un mensonge).
  public static func pour(hote: String, plist: [String: Any]? = Bundle.main.infoDictionary) -> String {
    let propre = hote.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !propre.isEmpty else { return "" }
    // Un hôte qui porte DÉJÀ un schéma n'est pas re-préfixé : c'est le cas d'une
    // adresse saisie à la main, et « https://https://… » ne mènerait nulle part.
    if propre.contains("://") { return propre }
    let clair = "http://" + propre
    return ExceptionATS.seraRefuse(clair, plist) ? "https://" + propre : clair
  }

  /// L'adresse d'un hôte dont le SCHÉMA EST CONNU — celui qu'un hôte publie.
  ///
  /// POURQUOI CETTE SECONDE PORTE. Le QR d'appairage transporte, depuis le lot
  /// HTTPS, le schéma sous lequel le Mac se publie : c'est un FAIT annoncé par la
  /// machine elle-même, et il vaut mieux que toute déduction. Mais un paquet qui
  /// refuse le clair ne peut pas l'honorer : on ne renvoie donc `http` que si le
  /// paquet l'autorise, et `https` dans tous les autres cas.
  public static func pour(hote: String, schemaAnnonce: String, plist: [String: Any]? = Bundle.main.infoDictionary) -> String {
    let propre = hote.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !propre.isEmpty else { return "" }
    if schemaAnnonce.lowercased() == "https" { return "https://" + propre }
    return pour(hote: propre, plist: plist)
  }
}
