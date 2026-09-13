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

  public init(fabrique: @escaping Fabrique = Connexion.fabriqueParDefaut) {
    self.fabrique = fabrique
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
    let court = try fabrique(adresse, jeton, Self.delaiSante)
    let sante = try await court.verifierSante()
    let patient = try fabrique(adresse, jeton, Self.delaiListe)
    let liste = try await patient.listerSessions(limite: 200)
    return Jonction(
      sante: sante,
      sessions: liste.sessions,
      reponses: liste.total ?? liste.sessions.count,
      client: patient)
  }

  /// La liste des machines du tailnet, publiée par l'hôte déjà joint.
  ///
  /// Rend la RÉPONSE ENTIÈRE, et non le seul tableau : elle porte un
  /// `diagnostic` qui dit POURQUOI la liste est vide — tailnet vide, Tailscale
  /// arrêté sur l'hôte, binaire introuvable. Trois causes qui ne se corrigent pas
  /// de la même façon, et les perdre laisserait l'utilisateur devant une liste
  /// vide sans explication.
  public func serveursDeLhote(adresse: String, jeton: String) async throws -> ListeServeurs {
    let client = try fabrique(adresse, jeton, Self.delaiHote)
    return try await client.listerServeurs()
  }

  /// Les espaces déclarés par le registre de l'hôte.
  public func espacesDeLhote(adresse: String, jeton: String) async throws -> [EspaceHote] {
    let client = try fabrique(adresse, jeton, Self.delaiHote)
    return try await client.listerEspaces().espaces
  }
}
