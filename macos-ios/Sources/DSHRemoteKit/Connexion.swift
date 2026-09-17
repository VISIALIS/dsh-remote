import Foundation

/// CE QUE L'APPLICATION DEMANDE À UN SERVEUR — sept appels, pas un de plus.
///
/// POURQUOI CE PROTOCOLE EXISTE. La politique de connexion (quel délai pour
/// quelle question, ce qu'un `401` signifie, quand un `404` dit « le plugin n'est
/// pas là ») n'était éprouvable qu'avec un vrai serveur en face. Or c'est cette
/// politique qui a coûté une fausse panne : un plafond unique de huit secondes a
/// refusé une connexion parfaitement valide, parce que la liste des sessions
/// prend 4 secondes à froid. Une règle qui a coûté ça mérite des tests sans
/// réseau.
///
/// CE N'EST PAS UN MIROIR DE `RemoteClient` : c'est la surface que le modèle
/// utilise réellement, et rien d'autre. `RemoteClient` s'y conforme sans une
/// ligne de changement.
public protocol ClientDSH: Sendable {
  func verifierSante() async throws -> Sante
  func listerSessions(limite: Int?) async throws -> ListeSessions
  func listerServeurs() async throws -> ListeServeurs
  func listerEspaces() async throws -> ListeEspaces
  func lireSession(_ identifiant: String, demande: DemandeJournal) async throws -> JournalSession
  func envoyerPrompt(_ identifiant: String, demande: DemandePrompt) async throws -> ReponsePrompt
  func annuler(_ identifiant: String) async throws -> ReponseAnnulation
  /// ÉCHANGER UN CODE D'APPAIRAGE — la seule méthode appelée AVANT d'avoir un
  /// jeton : le client est alors construit avec le CODE comme porteur, et cette
  /// route-là est la seule qui l'accepte.
  func echangerAppairage(nom: String) async throws -> AppareilAppaire
}

extension RemoteClient: ClientDSH {}

/// LA POLITIQUE DE CONNEXION : quels appels, avec quels délais, dans quel ordre.
///
/// ELLE VIT HORS DU MODÈLE. Le modèle garde l'ÉTAT (suis-je joint ? quelle erreur
/// ?) et les transitions ; cette pièce sait comment on parle à une machine, et
/// avec quelle patience. La fabrique de clients s'injecte : les tests vérifient
/// alors la politique — dont les délais — sans serveur et sans réseau.
public struct Connexion: Sendable {

  // MARK: - Les délais, et ce qui les a fixés

  /// Délai de la QUESTION COURTE : « y a-t-il un DSH en face ? »
  ///
  /// `sante` répond en MILLISECONDES — mesuré trois fois : 4,1 ms, 3,2 ms,
  /// 1,6 ms. Cinq secondes laissent mille fois la marge nécessaire, et refusent
  /// d'attendre une machine qui ne répond rien : c'est la question dont la
  /// réponse doit être rapide, parce que c'est elle qui décide si l'on attend.
  public static let delaiSante: TimeInterval = 5

  /// Délai de la LISTE des sessions — une lecture LOURDE, donc patiente.
  ///
  /// POURQUOI ELLE A SON PROPRE PLAFOND, ET POURQUOI IL EST LONG. Mesuré sur un
  /// harness occupé : **4,06 s à froid** (200 sessions à relire), puis 15 à
  /// 27 ms une fois son cache chaud. Un plafond court ne protège de rien : il
  /// transforme une machine occupée en machine en panne — mesuré, une connexion
  /// valide a été refusée après **8055 ms** avec un plafond unique de huit
  /// secondes, et l'application a annoncé un échec pour un serveur qui répondait.
  public static let delaiListe: TimeInterval = 30

  /// Délai des routes qui font travailler l'HÔTE (`/v1/serveurs`).
  ///
  /// POURQUOI PLUS LONG QUE LA CONNEXION : chez lui, la route borne son appel à
  /// `tailscale status` à huit secondes. Un client qui coupe à huit secondes
  /// couperait EXACTEMENT ce que l'hôte s'autorise — une course perdue d'avance
  /// les jours où le CLI est lent.
  public static let delaiHote: TimeInterval = 14

  // MARK: - La fabrique

  /// Comment on fabrique un client. Injectable, pour deux raisons : éprouver la
  /// politique sans réseau, et VOIR le délai demandé pour chaque appel.
  public typealias Fabrique = @Sendable (String, String, TimeInterval) throws -> any ClientDSH

  private let fabrique: Fabrique

  /// LES CLIENTS DÉJÀ CONSTRUITS, PAR `(adresse, délai)`.
  ///
  /// POURQUOI CE PETIT REGISTRE. Chaque `RemoteClient` porte SA `URLSession`,
  /// donc son propre pool de connexions : en fabriquer un neuf pour chaque appel
  /// reperd le handshake TCP à chaque fois. C'était le cas de `/v1/serveurs` et
  /// `/v1/espaces`, redemandés **toutes les quinze secondes** par la boucle de
  /// synchronisation : deux connexions neuves par cycle, à côté d'une session de
  /// trois secondes déjà chaude.
  ///
  /// LA CLÉ PORTE LE DÉLAI, ET C'EST ESSENTIEL : la politique de patience est
  /// partie intégrante du client (`timeoutIntervalForRequest`). Deux appels qui
  /// n'ont pas la même patience ne peuvent pas partager le même objet — les
  /// fusionner rendrait la question courte aussi patiente que la lecture lourde,
  /// c'est-à-dire ferait attendre trente secondes pour apprendre qu'une machine
  /// est muette. Le registre ne change donc AUCUN délai : il évite seulement de
  /// reconstruire ce qui existe déjà.
  ///
  /// LA CLÉ PORTE AUSSI L'ADRESSE ET LE JETON — et le jeton y est sous forme
  /// d'EMPREINTE, jamais en clair.
  ///
  /// POURQUOI LE JETON Y EST, ALORS QU'UN COMMENTAIRE AFFIRMAIT LE CONTRAIRE. Il
  /// était écrit ici qu'un jeton ne change qu'en se ré-appairant, « et cela passe
  /// par un changement de cible ». C'est FAUX pour le cas le plus courant : on se
  /// ré-appaire sur la MÊME machine — jeton révoqué, réinstallation, second scan
  /// du même QR. L'adresse ne bouge pas, donc la clé non plus, donc le client
  /// gardé rendait l'ANCIEN porteur : `401` sur toutes les routes jusqu'à
  /// éviction du registre ou redémarrage de l'application, sans qu'aucun écran ne
  /// dise pourquoi. La clé doit donc distinguer deux jetons pour une même adresse.
  ///
  /// L'EMPREINTE SUFFIT, ET LE JETON EN CLAIR SERAIT UN DÉFAUT : la clé d'un
  /// registre se retrouve dans une trace, un vidage mémoire ou un test qui
  /// échoue. `Empreinte.de` est déjà là pour ça — comparer deux jetons sans
  /// jamais les écrire — et une collision ne donnerait pas accès à un secret :
  /// elle réutiliserait un client dont le porteur est refusé, donc un `401`
  /// visible, jamais un accès.
  ///
  /// Le registre est BORNÉ : au-delà de trois entrées, la plus ancienne est
  /// oubliée, sinon un usage long accumulerait des sessions ouvertes pour des
  /// adresses qu'on ne vise plus.
  private let registre = RegistreDeClients()

  public init(fabrique: @escaping Fabrique = Connexion.fabriqueParDefaut) {
    self.fabrique = fabrique
  }

  /// Fabrique un client, ou rend celui qui existe déjà pour ce couple.
  private func client(_ adresse: String, _ jeton: String, delai: TimeInterval) throws -> any ClientDSH {
    if let connu = registre.client(adresse: adresse, empreinteDuJeton: Empreinte.de(jeton), delai: delai) {
      return connu
    }
    let neuf = try fabrique(adresse, jeton, delai)
    registre.poser(neuf, adresse: adresse, empreinteDuJeton: Empreinte.de(jeton), delai: delai)
    return neuf
  }

  public static let fabriqueParDefaut: Fabrique = { adresse, jeton, delai in
    try RemoteClient(adresse: adresse, jeton: jeton, delai: delai)
  }

  // MARK: - Les appels

  /// Ce qu'une connexion réussie rapporte.
  public struct Jonction: Sendable {
    public let sante: Sante
    public let sessions: [SessionListee]
    /// Le nombre de sessions que le serveur dit détenir — c'est ce que le test
    /// d'adresse annonce, et il peut dépasser ce qu'on a demandé.
    public let reponses: Int
    /// Le client au délai LONG, à garder : c'est lui qui sert ensuite pour les
    /// rafraîchissements et les lectures.
    public let client: any ClientDSH
  }

  /// Joint une cible : la question courte d'abord, la lecture lourde ensuite.
  ///
  /// L'ORDRE EST LA RÈGLE. Une machine muette doit échouer en cinq secondes, sans
  /// qu'on aille lui demander sa liste : c'est ce qui distingue « cette machine
  /// ne répond pas » de « cette machine est lente ». Inverser les deux ferait
  /// attendre trente secondes pour apprendre qu'il n'y a personne.
  public func joindre(adresse: String, jeton: String) async throws -> Jonction {
    let court = try client(adresse, jeton, delai: Self.delaiSante)
    let sante = try await court.verifierSante()
    let patient = try client(adresse, jeton, delai: Self.delaiListe)
    let liste = try await patient.listerSessions(limite: 200)
    return Jonction(
      sante: sante,
      sessions: liste.sessions,
      reponses: liste.total ?? liste.sessions.count,
      client: patient)
  }

  /// ÉCHANGER UN CODE D'APPAIRAGE CONTRE UN JETON PROPRE À CET APPAREIL.
  ///
  /// POURQUOI CE N'EST PAS `joindre` AVEC UN AUTRE NOM. Les autres appels
  /// supposent un jeton DÉJÀ valide ; celui-ci est le seul qui s'exécute AVANT
  /// d'en avoir un — le code joue le rôle de porteur, et une seule route
  /// l'accepte. Il ne fait donc AUCUNE autre lecture : ni poignée de main, ni
  /// liste de sessions. Appairer n'est pas se connecter, et mélanger les deux
  /// ferait dépendre l'appairage de tout ce qui peut échouer après lui.
  ///
  /// LE DÉLAI EST CELUI DE LA QUESTION COURTE : l'hôte écrit un enregistrement
  /// dans son coffre, ce qui prend quelques millisecondes. Un délai long ici ne
  /// servirait qu'à faire attendre quelqu'un devant un code qui expire.
  public func echangerAppairage(adresse: String, code: String, nom: String) async throws -> AppareilAppaire {
    // LE CLIENT EST FABRIQUÉ ICI, SANS REGISTRE, ET C'EST DÉLIBÉRÉ : son porteur
    // est un CODE à usage unique, pas le jeton de la machine. Le ranger dans le
    // registre le ferait survivre à l'échange, avec un porteur qui n'a plus
    // aucun sens.
    let client = try fabrique(adresse, code, Self.delaiSante)
    return try await client.echangerAppairage(nom: nom)
  }

  /// La liste des machines du tailnet, publiée par l'hôte déjà joint.
  ///
  /// Rend la RÉPONSE ENTIÈRE, et non le seul tableau : elle porte un
  /// `diagnostic` qui dit POURQUOI la liste est vide — tailnet vide, Tailscale
  /// arrêté sur l'hôte, binaire introuvable. Trois causes qui ne se corrigent pas
  /// de la même façon, et les perdre laisserait l'utilisateur devant une liste
  /// vide sans explication.
  public func serveursDeLhote(adresse: String, jeton: String) async throws -> ListeServeurs {
    let client = try self.client(adresse, jeton, delai: Self.delaiHote)
    return try await client.listerServeurs()
  }

  /// Les espaces déclarés par le registre de l'hôte.
  public func espacesDeLhote(adresse: String, jeton: String) async throws -> [EspaceHote] {
    let client = try self.client(adresse, jeton, delai: Self.delaiHote)
    return try await client.listerEspaces().espaces
  }
}

/// LES CLIENTS RÉUTILISABLES, PAR `(adresse, empreinte du jeton, délai)`.
///
/// POURQUOI UNE CLASSE, ET POURQUOI ELLE EST VERROUILLÉE. `Connexion` est une
/// valeur `Sendable` : elle n'a pas de place pour un état modifiable, et lui en
/// donner un sans verrou serait une course entre la boucle de suivi et un geste
/// de l'utilisateur — exactement ce que la règle « un seul écrivain par état » de
/// ce dépôt interdit. L'état vit donc dans cette petite classe, et son accès est
/// sérialisé par un verrou.
///
/// ELLE EST BORNÉE À DESSEIN. Trois entrées suffisent à la politique réelle (les
/// trois délais), et une borne évite qu'un usage long — plusieurs machines
/// visitées, plusieurs jetons — accumule des sessions ouvertes vers des adresses
/// qu'on ne vise plus. Au-delà, la plus ancienne est oubliée : un client oublié
/// n'est pas une panne, c'est une session qui se referme et un handshake à
/// refaire.
private final class RegistreDeClients: @unchecked Sendable {
  private struct Cle: Hashable {
    let adresse: String
    /// L'EMPREINTE du porteur, jamais le porteur — voir la note de `Connexion`.
    let empreinteDuJeton: String
    let delai: TimeInterval
  }

  private let verrou = NSLock()
  /// L'ordre d'insertion est TENU À LA MAIN (`ordre`), parce qu'un dictionnaire
  /// Swift n'en garantit aucun — et « la plus ancienne » doit vouloir dire
  /// quelque chose de stable.
  private var clients: [Cle: any ClientDSH] = [:]
  private var ordre: [Cle] = []
  private let maximum = 3

  func client(adresse: String, empreinteDuJeton: String, delai: TimeInterval) -> (any ClientDSH)? {
    verrou.lock()
    defer { verrou.unlock() }
    return clients[Cle(adresse: adresse, empreinteDuJeton: empreinteDuJeton, delai: delai)]
  }

  func poser(_ client: any ClientDSH, adresse: String, empreinteDuJeton: String, delai: TimeInterval) {
    verrou.lock()
    defer { verrou.unlock() }
    let cle = Cle(adresse: adresse, empreinteDuJeton: empreinteDuJeton, delai: delai)
    if clients[cle] == nil { ordre.append(cle) }
    clients[cle] = client
    while ordre.count > maximum {
      let ancienne = ordre.removeFirst()
      clients.removeValue(forKey: ancienne)
    }
  }
}
