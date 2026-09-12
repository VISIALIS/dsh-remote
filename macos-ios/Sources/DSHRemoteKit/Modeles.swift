import Foundation

/// Version du protocole que ce client sait parler.
///
/// Le plugin hôte annonce la sienne dans `/v1/sante` et dans chaque réponse :
/// un client qui ne sait pas lire une version doit le DIRE, pas deviner.
public let versionProtocoleSupportee = 1

/// Portée d'un journal de session, telle que demandée par le client.
public struct DemandeJournal: Sendable, Encodable {
  public var depuis: Int?
  public var limite: Int?
  public var types: [String]?
  public var inclureVolumineux: Bool?

  public init(depuis: Int? = nil, limite: Int? = nil, types: [String]? = nil, inclureVolumineux: Bool? = nil) {
    self.depuis = depuis
    self.limite = limite
    self.types = types
    self.inclureVolumineux = inclureVolumineux
  }
}

/// Faits saillants d'une session, tels que le journal les porte.
///
/// Le plugin hôte est du JavaScript et émet du `camelCase` ; les propriétés
/// Swift restent en français par convention de ce dépôt. Les `CodingKeys`
/// font donc la correspondance explicitement — et ils sont la SEULE source de
/// vérité du nom des champs sur le fil.
public struct ResumeSession: Sendable, Decodable {
  public let id: String?
  public let cwd: String?
  public let creeLe: Int?
  public let preset: String?
  public let profondeurDelegation: Int?
  public let seme: Bool?
  public let titre: String?
  public let dernierEvenementLe: Int?
  public let dernierSeq: Int?
  public let nbEnregistrements: Int?
  public let tronque: Bool?

  enum CodingKeys: String, CodingKey {
    case id, cwd, preset, titre, seme, tronque
    case creeLe = "creeLe"
    case profondeurDelegation = "profondeurDelegation"
    case dernierEvenementLe = "dernierEvenementLe"
    case dernierSeq = "dernierSeq"
    case nbEnregistrements = "nbEnregistrements"
  }
}

/// Une session telle qu'elle apparaît dans une liste.
public struct SessionListee: Sendable, Decodable {
  public let projet: String?
  public let cwdIndicatif: String?
  public let dossier: String?
  public let fichier: String?
  public let octets: Int?
  public let modifieLe: Double?
  public let vivante: Bool?
  public let illisible: String?
  public let resume: ResumeSession

  public var id: String { resume.id ?? "(inconnu)" }
  public var titreAffiche: String { resume.titre ?? "(sans titre)" }

  enum CodingKeys: String, CodingKey {
    case projet, dossier, fichier, octets, vivante, illisible
    case cwdIndicatif = "cwdIndicatif"
    case modifieLe = "modifieLe"
  }

  public init(from decoder: any Decoder) throws {
    let conteneur = try decoder.container(keyedBy: CodingKeys.self)
    self.projet = try conteneur.decodeIfPresent(String.self, forKey: .projet)
    self.cwdIndicatif = try conteneur.decodeIfPresent(String.self, forKey: .cwdIndicatif)
    self.dossier = try conteneur.decodeIfPresent(String.self, forKey: .dossier)
    self.fichier = try conteneur.decodeIfPresent(String.self, forKey: .fichier)
    self.octets = try conteneur.decodeIfPresent(Int.self, forKey: .octets)
    self.modifieLe = try conteneur.decodeIfPresent(Double.self, forKey: .modifieLe)
    self.vivante = try conteneur.decodeIfPresent(Bool.self, forKey: .vivante)
    self.illisible = try conteneur.decodeIfPresent(String.self, forKey: .illisible)
    // Le résumé est aplati dans l'objet de session par le plugin : on le
    // redécode depuis le même conteneur plutôt que d'exiger une imbrication.
    self.resume = try ResumeSession(from: decoder)
  }
}

/// Réponse de `GET /v1/sessions`.
public struct ListeSessions: Sendable, Decodable {
  public let protocole: Int
  public let racine: String?
  public let total: Int?
  public let sessions: [SessionListee]
  public let erreur: String?
}

/// Un enregistrement brut du journal. On ne l'interprète pas : la forme des
/// événements appartient au harness et change avec lui.
public struct EnregistrementJournal: Sendable, Decodable {
  public let type: String?
  public let seq: Int?
  public let time: Int?
}

/// Réponse de `POST /v1/session/<id>`.
public struct JournalSession: Sendable, Decodable {
  public let protocole: Int
  public let session: ResumeSession
  public let depuis: Int?
  public let limite: Int?
  public let total: Int?
  public let tronque: Bool?
  public let enregistrements: [EnregistrementJournal]
}

/// Réponse de `GET /v1/sante`.
public struct Sante: Sendable, Decodable {
  public let protocole: Int
  public let nom: String?
  public let hote: String?
  public let acces: String?
  public let versionDsh: String?
  public let capacites: Capacites

  public struct Capacites: Sendable, Decodable {
    public let sessions: Bool
    public let journal: Bool
    public let flux: Bool
    public let ecriture: Bool
    public let approbations: Bool
  }
}

/// Erreur de transport ou de protocole, avec assez de contexte pour agir.
public enum ErreurRemote: Error, CustomStringConvertible {
  case jetonRefuse
  case origineRefusee
  case versionIncompatible(recue: Int, supportee: Int)
  case reponseInattendue(code: Int)
  case adresseInvalide(String)
  case transport(String)
  case decodage(String)

  public var description: String {
    switch self {
    case .jetonRefuse:
      return "jeton refusé (401) — le jeton d'appareil est absent, révoqué ou faux"
    case .origineRefusee:
      return "origine refusée (403) — un client natif ne doit jamais envoyer d'en-tête Origin"
    case let .versionIncompatible(recue, supportee):
      return "protocole incompatible : le serveur annonce la version \(recue), ce client sait lire la \(supportee)"
    case let .reponseInattendue(code):
      return "réponse inattendue (HTTP \(code))"
    case let .adresseInvalide(detail):
      return "adresse invalide : \(detail)"
    case let .transport(detail):
      return "échec de transport : \(detail)"
    case let .decodage(detail):
      return "réponse illisible : \(detail)"
    }
  }
}
