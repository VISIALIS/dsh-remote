import Foundation

/// LE CONTRAT D'APPAIRAGE, CÔTÉ APPAREIL — miroir de `dynamic/appairage.js`.
///
/// POURQUOI CE TYPE EXISTE. La charge utile est CONSTRUITE par l'hôte, en
/// JavaScript, et ANALYSÉE ici, en Swift. Les deux moitiés ne partagent aucun
/// code et ne tournent jamais en même temps : sans un contrat écrit noir sur
/// blanc, une divergence ne se verrait qu'au moment de l'appairage, chez
/// l'utilisateur, sous la forme d'un refus qui n'explique rien.
///
/// CE QUI TIENT LES DEUX MOITIÉS ENSEMBLE : le fixture
/// `Fixtures/vecteurs-appairage.json`, rejoué par `AppairageTests.swift` (ici)
/// et par `plugins/dsh-remote/tests/appairage.test.js` (là-bas). Ajouter un
/// vecteur d'un côté sans l'autre ne casse rien — mais une règle qui change
/// d'un côté casse le test de l'autre, et c'est tout ce qu'on demande.
///
/// LA FORME, ET POURQUOI ELLE EST AUSSI COURTES :
///
///     dshremote://<hote>/<genre>/v1/<secret>
///
/// Elle doit tenir dans un QR d'écran, donc dans peu d'octets : pas de
/// pourcent-encodage, pas de paramètre facultatif sauf UN — le schéma de
/// publication, omis quand il vaut `http`. Le genre et la version sont des
/// segments, et le secret est en base64url, donc sans `/` : le découpage n'est
/// jamais ambigu.
public enum Appairage {

  /// Le schéma de la charge utile. Un seul, jamais négocié.
  public static let schema = "dshremote"

  /// Les transports qui peuvent être ANNONCÉS dans une charge utile.
  ///
  /// POURQUOI UNE LISTE BLANCHE. Le cinquième segment est écrit par une AUTRE
  /// machine : `ftp://`, `file://` ou `javascript:` n'ont rien à y faire, et une
  /// application qui ferait confiance à ce segment construirait une adresse
  /// qu'elle n'a pas choisie. Le miroir JS porte la même liste (`SCHEMAS`), et le
  /// fixture partagé rejoue les deux.
  public static let transportsAnnoncables = ["http", "https"]

  /// Ce que le secret EST, selon le genre.
  ///
  /// POURQUOI LE GENRE EST DANS LA CHARGE UTILE, et pas deviné à la longueur :
  /// un jeton d'appareil et un code d'appairage ne se traitent pas pareil — le
  /// premier se garde, le second s'échange et expire. Les confondre donnerait
  /// une application qui envoie un code comme jeton porteur, et qui reçoit un
  /// `401` incompréhensible au lieu d'un message juste.
  public enum Genre: String, Sendable, CaseIterable {
    case jeton
    case code
  }

  /// Une charge utile acceptée.
  public struct Charge: Equatable, Sendable {
    public let hote: String
    public let genre: Genre
    public let version: String
    public let secret: String
    /// Le transport ANNONCÉ par la machine, s'il y en a un. `nil` veut dire
    /// « http implicite » — la forme à quatre segments, et le cas le plus courant.
    public let transport: String?

    /// L'adresse que l'application doit viser, POUR UN PAQUET DONNÉ.
    ///
    /// DEUX SOURCES, ET LA PLUS SÉVÈRE GAGNE. Le transport annoncé dit sous quel
    /// schéma la machine se publie ; ce que le paquet autorise (`AdresseMachine`)
    /// dit ce qui est seulement possible. Une adresse en clair annoncée par un
    /// hôte n'est donc jamais suivie par un paquet qui refuse le clair vers un nom
    /// qualifié : ATS la refuserait avant qu'elle ne parte, et le message parlerait
    /// de transport au lieu du vrai problème.
    ///
    /// POURQUOI UNE FONCTION, ET PAS SEULEMENT LA PROPRIÉTÉ. C'est ce qui rend la
    /// règle ÉPROUVABLE : un test donne l'Info.plist qu'il veut, au lieu de
    /// dépendre de celui du paquet de test — qui n'a, lui, aucune exception.
    public func adresse(pour plist: [String: Any]?) -> String {
      AdresseMachine.pour(hote: hote, schemaAnnonce: transport ?? "http", plist: plist)
    }

    /// L'adresse visée par le paquet QUI EXÉCUTE CE CODE.
    public var adresse: String {
      AdresseMachine.pour(hote: hote, schemaAnnonce: transport ?? "http")
    }

    public init(hote: String, genre: Genre, version: String, secret: String, transport: String? = nil) {
      self.hote = hote
      self.genre = genre
      self.version = version
      self.secret = secret
      self.transport = transport
    }
  }

  /// Pourquoi une charge utile a été refusée.
  ///
  /// Un refus qui ne dit pas POURQUOI laisse l'utilisateur deviner entre « le QR
  /// est abîmé », « c'est l'adresse de ma propre machine » et « mon application
  /// est trop ancienne ». Trois causes, trois remèdes — donc sept motifs.
  public enum Motif: String, Error, Sendable, CaseIterable {
    case forme
    case schema
    case hote
    case hoteLocal = "hote-local"
    case genre
    case version
    case secret

    /// Le message montré à l'utilisateur. Jamais un code, jamais une trace.
    public var message: String {
      switch self {
      case .forme: return L("Ce texte n'est pas une charge utile d'appairage.")
      case .schema: return L("Ce lien n'est pas un appairage DSH.")
      case .hote: return L("Le nom de machine est vide ou mal formé.")
      case .hoteLocal:
        return L("Ce lien vise la boucle locale : un autre appareil ne peut pas la joindre.")
      case .genre: return L("Ce genre d'appairage n'existe pas.")
      case .version: return L("Cette version d'appairage n'est pas connue de cette application.")
      case .secret: return L("Le secret est absent, tronqué ou mal formé.")
      }
    }
  }

  /// Longueur minimale d'un secret, PAR GENRE — la même valeur que côté hôte.
  ///
  /// CE N'EST PAS LA LONGUEUR DU TIRAGE, et c'est délibéré : c'est un FILET
  /// CONTRE LA TRONCATURE (un presse-papiers qui coupe, un scan partiel, une
  /// ligne recopiée à moitié). Un jeton amputé d'un caractère reste donc
  /// « formé » — et c'est l'authentification, qui compare la valeur exacte, qui
  /// le refuse. Exiger ici la longueur exacte casserait l'application le jour où
  /// le tirage grandit.
  public static func minimumSecret(_ genre: Genre) -> Int {
    switch genre {
    case .jeton: return 32
    case .code: return 22
    }
  }

  /// La version du contrat, par genre. Écrite dans la charge utile.
  public static func version(_ genre: Genre) -> String {
    switch genre {
    case .jeton: return "v1"
    case .code: return "v1"
    }
  }

  /// Les adresses qui ne mènent nulle part depuis un AUTRE appareil.
  ///
  /// POURQUOI CE REFUS EXISTE CÔTÉ APPAREIL ALORS QUE L'HÔTE LE FAIT AUSSI : ils
  /// ne protègent pas la même chose. L'hôte refuse d'ÉMETTRE une adresse
  /// injoignable ; ici, on refuse d'ACCEPTER un lien qui vise la boucle locale —
  /// ce qui arrive dès qu'on colle un lien trouvé dans un terminal, ou qu'un QR
  /// a été fabriqué à la main.
  private static let hotesLocaux: Set<String> = [
    "127.0.0.1", "localhost", "0.0.0.0", "::1", "[::1]", "::",
  ]

  /// Un caractère admis dans un nom d'hôte : ASCII strictement.
  ///
  /// POURQUOI PAS `isLetter` / `isNumber` DE SWIFT : ils acceptent l'Unicode
  /// entier (« é », chiffres arabes). Le JavaScript d'en face, lui, teste
  /// `[A-Za-z0-9.-]`. Deux alphabets différents pour un même champ, c'est une
  /// charge utile acceptée d'un côté et refusée de l'autre.
  private static func estAlphanumerique(_ caractere: Character) -> Bool {
    (caractere >= "a" && caractere <= "z")
      || (caractere >= "A" && caractere <= "Z")
      || (caractere >= "0" && caractere <= "9")
  }

  /// Le nom d'hôte est-il joignable par un autre appareil ?
  public static func hoteJoignable(_ hote: String) -> Bool {
    guard !hote.isEmpty else { return false }
    // Un deux-points, c'est un port ou une adresse IPv6 : hors contrat.
    guard !hote.contains(":") else { return false }
    guard !hotesLocaux.contains(hote.lowercased()) else { return false }
    guard let premier = hote.first, let dernier = hote.last else { return false }
    guard estAlphanumerique(premier), estAlphanumerique(dernier) else { return false }
    return hote.allSatisfy { estAlphanumerique($0) || $0 == "." || $0 == "-" }
  }

  /// Un secret acceptable : base64url, longueur suffisante pour son genre.
  private static func secretAcceptable(_ genre: Genre, _ secret: String) -> Bool {
    guard secret.count >= minimumSecret(genre) else { return false }
    return secret.allSatisfy { estAlphanumerique($0) || $0 == "-" || $0 == "_" }
  }

  /// Analyser une charge utile — le chemin du scan et du collage.
  ///
  /// REFUSER EST UN RÉSULTAT, PAS UNE EXCEPTION : cette fonction est appelée à
  /// chaque image de la caméra et à chaque frappe dans un champ de saisie, où le
  /// texte est incomplet la plupart du temps. Elle ne lève donc jamais.
  public static func analyser(_ texte: String) -> Result<Charge, Motif> {
    let valeur = texte.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !valeur.isEmpty, valeur.count <= 512 else { return .failure(.forme) }

    let prefixe = "\(schema)://"
    guard valeur.hasPrefix(prefixe) else {
      // Deux causes distinctes, que l'utilisateur ne répare pas pareil : un autre
      // schéma (une URL de navigateur, par exemple), ou du texte quelconque.
      return .failure(valeur.contains("://") ? .schema : .forme)
    }

    let reste = String(valeur.dropFirst(prefixe.count))
    let morceaux = reste.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    // QUATRE SEGMENTS — hôte, genre, version, secret — OU CINQ avec le transport
    // annoncé. Aucun autre compte : un secret ne contient pas de `/`, donc un
    // segment de plus est une charge utile MAL FORMÉE, jamais un cas particulier
    // à deviner.
    guard morceaux.count == 4 || morceaux.count == 5 else { return .failure(.forme) }
    let hote = morceaux[0]
    let genreBrut = morceaux[1]
    let versionBrute = morceaux[2]
    let secret = morceaux[3]

    guard !hote.contains("?"), !hote.contains("#") else { return .failure(.forme) }
    guard hoteJoignable(hote) else {
      return .failure(hotesLocaux.contains(hote.lowercased()) ? .hoteLocal : .hote)
    }
    guard let genre = Genre(rawValue: genreBrut) else { return .failure(.genre) }
    guard versionBrute == version(genre) else { return .failure(.version) }
    guard secretAcceptable(genre, secret) else { return .failure(.secret) }
    // Un transport qui n'est pas dans la liste blanche est refusé AVANT d'être
    // utilisé pour construire une adresse — c'est tout l'intérêt de la liste.
    var transport: String?
    if morceaux.count == 5 {
      let annonce = morceaux[4].lowercased()
      guard transportsAnnoncables.contains(annonce) else { return .failure(.forme) }
      transport = annonce
    }

    return .success(
      Charge(hote: hote, genre: genre, version: versionBrute, secret: secret, transport: transport))
  }
}
