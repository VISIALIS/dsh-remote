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
///
/// `Hashable` est requis par `List(selection:)` et `onChange(of:)` de SwiftUI : une
/// session doit pouvoir être comparée et identifiée par sa valeur.
public struct SessionListee: Sendable, Decodable, Hashable {
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

  /// L'identité d'une session est son identifiant, PAS le contenu de son résumé :
  /// un journal qui grandit change son résumé à chaque écriture, et une sélection
  /// qui se perdrait à chaque rafraîchissement serait inutilisable.
  public static func == (gauche: SessionListee, droite: SessionListee) -> Bool {
    gauche.projet == droite.projet && gauche.id == droite.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(projet)
    hasher.combine(id)
  }

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

/// Un enregistrement brut du journal.
///
/// On décode `type`, `seq` et `time` — les trois seuls champs dont le TRANSPORT a
/// besoin — et on conserve la charge utile d'origine telle quelle. La forme des
/// événements appartient au harness et change avec lui : la transporter sans
/// l'interpréter est ce qui rend le client robuste à ces changements.
///
/// La charge utile est conservée en OCTETS (`corpsBrut`) et non en objet JSON :
/// `Any` n'est pas `Sendable`, et un journal traverse des frontières d'acteur.
public struct EnregistrementJournal: Sendable, Decodable {
  public let type: String?
  public let seq: Int?
  public let time: Int?
  /// Charge utile `data`, ré-encodée en JSON, ou `nil` si l'enregistrement n'en porte pas.
  public let corpsBrut: Data?

  enum CodingKeys: String, CodingKey {
    case type, seq, time, data
  }

  public init(from decoder: any Decoder) throws {
    let conteneur = try decoder.container(keyedBy: CodingKeys.self)
    self.type = try conteneur.decodeIfPresent(String.self, forKey: .type)
    self.seq = try conteneur.decodeIfPresent(Int.self, forKey: .seq)
    self.time = try conteneur.decodeIfPresent(Int.self, forKey: .time)
    if conteneur.contains(.data) {
      let brut = try conteneur.decode(JSONBrut.self, forKey: .data)
      // On repasse par un étage d'encodage : l'enregistrement redevient une
      // charge utile neutre, sans objet Swift vivant à conserver.
      let tampon = try JSONEncoder().encode(brut)
      self.corpsBrut = tampon == Data("null".utf8) ? nil : tampon
    } else {
      self.corpsBrut = nil
    }
  }
}

/// Valeur JSON quelconque, gardée pour être RÉ-ENCODÉE plus tard, sans être
/// interprétée ici.
private struct JSONBrut: Codable {
  let valeur: Any

  init(from decoder: any Decoder) throws {
    let conteneur = try decoder.singleValueContainer()
    if conteneur.decodeNil() {
      self.valeur = NSNull()
    } else if let valeur = try? conteneur.decode(Bool.self) {
      self.valeur = valeur
    } else if let valeur = try? conteneur.decode(Int.self) {
      self.valeur = valeur
    } else if let valeur = try? conteneur.decode(Double.self) {
      self.valeur = valeur
    } else if let valeur = try? conteneur.decode(String.self) {
      self.valeur = valeur
    } else if let valeur = try? conteneur.decode([JSONBrut].self) {
      self.valeur = valeur.map(\.valeur)
    } else if let valeur = try? conteneur.decode([String: JSONBrut].self) {
      self.valeur = valeur.mapValues(\.valeur)
    } else {
      self.valeur = NSNull()
    }
  }

  func encode(to encoder: any Encoder) throws {
    var conteneur = encoder.singleValueContainer()
    switch valeur {
    case let valeur as NSNull: try conteneur.encodeNil()
    case let valeur as Bool: try conteneur.encode(valeur)
    case let valeur as Int: try conteneur.encode(valeur)
    case let valeur as Double: try conteneur.encode(valeur)
    case let valeur as String: try conteneur.encode(valeur)
    case let valeur as [Any]: try conteneur.encode(valeur.map { JSONBrut(valeur: $0) })
    case let valeur as [String: Any]: try conteneur.encode(valeur.mapValues { JSONBrut(valeur: $0) })
    default: try conteneur.encodeNil()
    }
  }

  init(valeur: Any) { self.valeur = valeur }
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
