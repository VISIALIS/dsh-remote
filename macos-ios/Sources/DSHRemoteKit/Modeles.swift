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

  /// Résumé vide, employé quand le serveur n'a pas pu atteindre l'en-tête du
  /// journal : mieux vaut un résumé vide qu'un flux refusé.
  public init() {
    self.id = nil
    self.cwd = nil
    self.creeLe = nil
    self.preset = nil
    self.profondeurDelegation = nil
    self.seme = nil
    self.titre = nil
    self.dernierEvenementLe = nil
    self.dernierSeq = nil
    self.nbEnregistrements = nil
    self.tronque = nil
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
  /// Statut d'agent transporté par le serveur : `en_cours`, `inactif`, ou `nil`
  /// quand la session n'est pas ouverte dans le processus du harness — auquel
  /// cas l'état est INCONNU, et non « inactif ».
  public let statut: String?
  /// Le harness attend-il une DÉCISION de l'utilisateur pour cette session
  /// (question d'un tool, ou autorisation) ?
  ///
  /// Optionnel À DESSEIN : un hôte plus ancien ne renvoie pas ce champ, et `nil`
  /// signifie « ne sait pas », pas « non ». Une session bloquée sur une question
  /// ne repartira pas toute seule — c'est l'information la plus actionnable de la
  /// liste, et l'annoncer à tort serait pire que de l'ignorer.
  public let attendReponse: Bool?
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
    case projet, dossier, fichier, octets, vivante, illisible, statut
    case cwdIndicatif = "cwdIndicatif"
    case modifieLe = "modifieLe"
    case attendReponse = "attendReponse"
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
    self.statut = try conteneur.decodeIfPresent(String.self, forKey: .statut)
    self.attendReponse = try conteneur.decodeIfPresent(Bool.self, forKey: .attendReponse)
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

/// Réponse de `GET /v1/serveurs` — la découverte faite par l'HÔTE.
///
/// C'est la voie retenue pour l'iPhone : l'application ne découvre rien
/// elle-même (iOS interdit d'exécuter un processus), elle lit la découverte
/// faite par un Mac qui a Tailscale.
public struct ListeServeurs: Sendable, Decodable {
  public let protocole: Int
  public let serveurs: [ServeurMac]
  /// Pourquoi la liste est vide, quand elle l'est. `nil` sinon.
  ///
  /// Sans ce champ, une liste vide ne dit pas si le tailnet est vide, si
  /// Tailscale est arrêté sur l'hôte ou si son binaire est introuvable — trois
  /// causes qui ne se corrigent pas de la même façon.
  public let diagnostic: String?
}

/// Réponse de `GET /v1/espaces` — les espaces de travail de l'hôte.
///
/// POURQUOI L'HÔTE LES PUBLIE. L'application déduisait ses espaces des sessions :
/// un espace **sans session** lui était donc invisible, alors que l'interface web
/// les affiche tous — un espace s'enregistre dès qu'on choisit un dossier, avant
/// même d'y ouvrir une session. L'hôte tient ce registre ; il le publie.
public struct ListeEspaces: Sendable, Decodable {
  public let protocole: Int
  public let espaces: [EspaceHote]
}

/// Un espace de travail tel que le registre de l'hôte le connaît.
public struct EspaceHote: Sendable, Decodable, Hashable {
  /// Identifiant du registre — c'est l'APPARTENANCE des sessions.
  public let id: String
  /// Titre donné par l'utilisateur, ou déduit du chemin par l'hôte.
  public let titre: String
  /// Chemin du dossier.
  public let chemin: String
  /// Création, en millisecondes epoch. `nil` si l'hôte n'a pas su la lire.
  public let creeLe: Int?
  /// Identifiants des sessions rattachées à cet espace.
  ///
  /// C'est un FAIT du registre, et non une déduction : on ne recompte donc pas
  /// les sessions en comparant des chemins, ce qui se tromperait sur un dossier
  /// renommé, deux projets homonymes, ou un sous-agent.
  public let sessions: [String]
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

  /// Construit un enregistrement de toutes pièces — employé par le flux, qui
  /// reçoit la charge utile en JSON déjà encodé.
  public init(type: String?, seq: Int?, time: Int?, corpsBrut: Data?) {
    self.type = type
    self.seq = seq
    self.time = time
    self.corpsBrut = corpsBrut
  }

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
    /// L'hôte sait-il publier la liste des Macs du tailnet (`/v1/serveurs`) ?
    ///
    /// Optionnel À DESSEIN : un hôte plus ancien ne renvoie pas ce champ, et le
    /// client doit alors garder la saisie manuelle au lieu d'attendre une liste
    /// qui ne viendra jamais. `nil` signifie « ne sait pas », pas « non ».
    public let decouverte: Bool?
    /// L'hôte publie-t-il ses espaces de travail (`/v1/espaces`), y compris ceux
    /// qui n'ont AUCUNE session ? Sans cette capacité, le client déduit ses
    /// espaces des sessions — le comportement d'avant.
    public let espaces: Bool?
    /// L'hôte sait-il INTERROMPRE le tour en cours (`/v1/session/<id>/annuler`) ?
    ///
    /// Optionnel pour la même raison que `decouverte` : un hôte plus ancien ne
    /// le dit pas. Sans ce champ, l'application proposerait un bouton
    /// « Arrêter » qui ne ferait rien — un mensonge d'interface.
    public let annulation: Bool?
    /// L'hôte sait-il SIGNALER qu'une session attend une décision humaine ?
    ///
    /// À ne pas confondre avec `approbations` : ici l'hôte annonce seulement
    /// l'attente, il ne permet pas d'y répondre.
    public let questions: Bool?
  }
}

/// Erreur de transport ou de protocole, avec assez de contexte pour agir.
public enum ErreurRemote: Error, CustomStringConvertible {
  case jetonRefuse
  case origineRefusee
  case versionIncompatible(recue: Int, supportee: Int)
  case reponseInattendue(code: Int)
  /// Refus EXPLICITE de l'hôte, avec le motif qu'il a donné.
  ///
  /// `reponseInattendue` ne suffisait pas pour l'écriture : l'hôte refuse une
  /// demande pour des raisons qui se corrigent différemment (session disparue,
  /// modèle non choisi, agent occupé). Rendre « HTTP 409 » sans le motif
  /// obligerait l'interface à deviner, ou à afficher un code au lieu d'une
  /// phrase.
  case refusServeur(statut: Int, motif: String, code: String?)
  case adresseInvalide(String)
  case transport(String)
  case decodage(String)

  public var description: String {
    switch self {
    case .jetonRefuse:
      // Le message DIT QUOI FAIRE, parce que les trois causes possibles se
      // corrigent de la même façon et qu'aucune n'est devinable depuis l'écran :
      // le trousseau ne contient pas de jeton (première installation), il en
      // contient un devenu faux (le coffre du harness a été tourné depuis), ou
      // le jeton a été tronqué au collage.
      return
        "jeton refusé (401) — le jeton d'appareil est absent, révoqué ou faux. Recopiez le jeton affiché par le harness, puis collez-le dans Réglages."
    case .origineRefusee:
      return "origine refusée (403) — un client natif ne doit jamais envoyer d'en-tête Origin"
    case let .versionIncompatible(recue, supportee):
      return "protocole incompatible : le serveur annonce la version \(recue), ce client sait lire la \(supportee)"
    case let .reponseInattendue(code):
      return "réponse inattendue (HTTP \(code))"
    case let .refusServeur(statut, motif, code):
      let marque = code.map { " [\($0)]" } ?? ""
      return "refus de l'hôte\(marque) : \(motif) (HTTP \(statut))"
    case let .adresseInvalide(detail):
      return "adresse invalide : \(detail)"
    case let .transport(detail):
      return "échec de transport : \(detail)"
    case let .decodage(detail):
      return "réponse illisible : \(detail)"
    }
  }
}
