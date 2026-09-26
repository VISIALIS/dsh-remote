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

  /// L'INITIALISEUR QUI MANQUAIT, et pourquoi il est écrit à la main.
  ///
  /// `SessionListee` déclare son propre `init(from:)` — il décode un JSON dont les
  /// clés ne suivent pas la convention Swift —, et une déclaration explicite
  /// SUPPRIME l'initialiseur mémoire que le compilateur aurait synthétisé. Or
  /// `avecStatut` a besoin d'en construire une copie. Il est donc écrit ici, une
  /// fois, `internal` : c'est un détail de construction du module, pas une porte
  /// ouverte pour les appelants.
  init(
    projet: String?, cwdIndicatif: String?, dossier: String?, fichier: String?, octets: Int?,
    modifieLe: Double?, vivante: Bool?, statut: String?, attendReponse: Bool?, illisible: String?,
    resume: ResumeSession
  ) {
    self.projet = projet
    self.cwdIndicatif = cwdIndicatif
    self.dossier = dossier
    self.fichier = fichier
    self.octets = octets
    self.modifieLe = modifieLe
    self.vivante = vivante
    self.statut = statut
    self.attendReponse = attendReponse
    self.illisible = illisible
    self.resume = resume
  }

  public var id: String { resume.id ?? "(inconnu)" }
  public var titreAffiche: String { resume.titre ?? "(sans titre)" }

  /// La même session, avec un statut RAFRAÎCHI par le flux.
  ///
  /// POURQUOI UNE COPIE, ET PAS UNE MUTATION. `SessionListee` est un modèle de
  /// DÉCODAGE : ses champs sont des `let`, et c'est ce qui garantit qu'on ne le
  /// modifie pas à moitié depuis une vue. La liste n'a qu'un écrivain par question
  /// — `appliquerSessions` pour une liste entière, `appliquerStatut` pour le seul
  /// statut poussé par le flux —, et cette copie garde la discipline : on remplace
  /// une entrée par une AUTRE entrée, jamais un champ.
  public func avecStatut(_ nouveau: String?) -> SessionListee {
    SessionListee(
      projet: projet, cwdIndicatif: cwdIndicatif, dossier: dossier, fichier: fichier,
      octets: octets, modifieLe: modifieLe, vivante: vivante, statut: nouveau,
      attendReponse: attendReponse, illisible: illisible, resume: resume)
  }

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
    case is NSNull: try conteneur.encodeNil()
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
/// UN APPAREIL APPAIRÉ, tel que l'hôte le rend après un échange de code.
///
/// POURQUOI CE TYPE EXISTE SÉPARÉMENT DE `Sante`. La poignée de main décrit
/// l'HÔTE ; ceci décrit ce que l'appareil VIENT DE RECEVOIR : un jeton qui lui est
/// propre. Les confondre ferait entrer un secret dans un type qui circule partout
/// — et un type qui circule partout finit dans une trace.
public struct AppareilAppaire: Sendable, Decodable {
  public let protocole: Int
  /// LE JETON DE CET APPAREIL. Il va au trousseau, et nulle part ailleurs.
  public let jeton: String
  public let portee: String?
  public let nom: String?
  public let creeLe: Double?
}

public struct Sante: Sendable, Decodable {
  public let protocole: Int
  public let nom: String?
  public let hote: String?
  public let acces: String?
  public let versionDsh: String?
  /// La portée du jeton de CETTE application, telle que l'hôte la connaît.
  ///
  /// Optionnelle À DESSEIN : un hôte antérieur à la portée ne l'envoie pas, et
  /// `nil` doit se lire « ne sait pas », jamais « lecture seule ». C'est ce qui
  /// permet à l'écran d'expliquer l'absence d'écriture sans l'inventer.
  public let portee: String?
  /// COMBIEN D'APPAREILS SONT APPAIRÉS — un compte, jamais une liste.
  ///
  /// Optionnel À DESSEIN, comme `portee` : un hôte antérieur à l'appairage ne
  /// l'envoie pas, et `nil` doit se lire « ne sait pas », jamais « zéro ». La
  /// LISTE des appareils, elle, n'est pas exposée aux porteurs de jeton : elle vit
  /// dans le panneau du Mac, sous session navigateur (voir le README du plugin).
  public let appareils: Int?
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
/// POURQUOI UNE MACHINE NE SERT PAS DSH — la cause, pas le symptôme.
///
/// POURQUOI CE TYPE EXISTE. La page d'une machine affichait le remède de la
/// CONNEXION EN COURS, pas celui de la machine REGARDÉE : sur la page de
/// MacMini, quand l'application était connectée ailleurs, il n'y avait donc
/// aucun remède — et quand elle y était connectée, le remède parlait de la
/// mauvaise cause si les deux différaient. La cause est maintenant une valeur
/// attachée à la machine, tirée de ce qu'on a MESURÉ sur elle.
public enum CauseSansDsh: Equatable, Sendable {
  /// La machine répond, mais pas DSH Remote : le plugin n'y est pas chargé.
  /// C'est le cas mesuré sur MacMini — port 80 publié, `/dsh-remote/v1/sante`
  /// en `404`.
  case pluginAbsent
  /// Rien n'écoute sur le port 80 : c'est la publication qui manque.
  case rienNEcoute
}

public enum ErreurRemote: Error, CustomStringConvertible {
  case jetonRefuse
  case origineRefusee
  /// Le jeton est VALIDE, mais il ne porte que la portée `lecture`.
  ///
  /// POURQUOI CE CAS EXISTE SÉPARÉMENT. L'hôte refuse l'écriture en 403, comme il
  /// refuse une requête portant `Origin` — deux causes qui n'ont ni le même sens
  /// ni le même remède. Les confondre affichait « un client natif ne doit jamais
  /// envoyer d'en-tête Origin » à quelqu'un dont le jeton lit simplement sans
  /// écrire.
  case ecritureRefusee
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
  /// L'ÉCHANGE D'UN CODE D'APPAIRAGE A ÉTÉ REFUSÉ, avec le motif de l'hôte.
  ///
  /// POURQUOI CE CAS EXISTE SÉPARÉMENT, alors qu'un `403` est déjà `origineRefusee`
  /// ou `ecritureRefusee`. Le troisième `403` du protocole est celui de l'échange :
  /// « code inconnu ou déjà utilisé », « code expiré ». Le confondre afficherait
  /// « un client natif ne doit jamais envoyer d'en-tête Origin » à quelqu'un dont
  /// le code a simplement expiré — le même défaut que la portée avait déjà coûté,
  /// une troisième fois.
  case appairageRefuse(motif: String, detail: String?)
  /// L'hôte ne connaît PAS la route d'échange : son plugin est plus ancien que
  /// cette application. Cela se dit — sans quoi on chercherait une panne de code.
  case appairageNonSupporte
  case adresseInvalide(String)
  case transport(String)
  case decodage(String)
  /// L'hôte répond `304` — « cette liste n'a pas bougé » — alors que CE client
  /// n'a rien à réutiliser : il vient d'être construit, ou sa mémoire a été
  /// perdue. Cela ne devrait pas arriver, puisque c'est le client lui-même qui
  /// envoie l'empreinte ; si cela arrive, le dire vaut mieux que rendre une liste
  /// vide, qui se lirait « aucune session ».
  case nonModifie

  /// La CAUSE de l'absence de DSH, quand cette erreur l'explique.
  ///
  /// Rend `nil` pour les erreurs qui ne disent rien de l'installation : un jeton
  /// refusé, une origine refusée ou une version incompatible signifient que le
  /// service EST là. Ne pas conclure est ici la bonne réponse.
  public var causeSansDsh: CauseSansDsh? {
    switch self {
    case .reponseInattendue: return .pluginAbsent
    case let .transport(detail): return detail.contains("-1004") ? .rienNEcoute : nil
    default: return nil
    }
  }

  /// La raison que l'hôte écrit dans son corps de refus quand la portée manque.
  ///
  /// ELLE EST ICI, ET PAS DANS LE CLIENT SEUL : c'est un terme du CONTRAT entre
  /// les deux moitiés — le plugin l'écrit, l'application la reconnaît —, et un
  /// test de chaque côté la tient. Une chaîne recopiée deux fois aurait fini par
  /// diverger, et le refus de portée serait redevenu un refus d'origine.
  public static let raisonLectureSeule = "jeton en lecture seule"

  /// LES DEUX MOTIFS DE REFUS D'UN CODE D'APPAIRAGE, tels que l'hôte les écrit.
  ///
  /// MÊME RÈGLE QUE `raisonLectureSeule` : ce sont des termes du CONTRAT entre les
  /// deux moitiés. Le plugin les écrit (`dynamic/host.js`), l'application les
  /// reconnaît pour les TRADUIRE au lieu de les afficher bruts — et un test de
  /// chaque côté les tient.
  public static let motifCodeExpire = "code expire"
  public static let motifCodeInconnu = "code inconnu ou deja utilise"

  public var description: String {
    switch self {
    case .jetonRefuse:
      // Le message DIT QUOI FAIRE, parce que les trois causes possibles se
      // corrigent de la même façon et qu'aucune n'est devinable depuis l'écran :
      // le trousseau ne contient pas de jeton (première installation), il en
      // contient un devenu faux (le coffre du harness a été tourné depuis), ou
      // le jeton a été tronqué au collage.
      //
      // LE RENVOI A ÉTÉ CORRIGÉ, ET C'ÉTAIT LE DÉFAUT. Il disait « collez-le
      // dans Réglages » — une feuille qui ne contient plus AUCUN champ de jeton
      // depuis que chaque hôte a le sien. Le remède prescrit menait donc à un
      // écran vide, sur un iPhone neuf où c'était le seul remède écrit. Les deux
      // endroits qui portent réellement le champ sont nommés, et le premier est
      // celui qu'on a sous les yeux quand on lit ce message.
      return L("jeton refusé (401) — le jeton d'appareil est absent, révoqué ou faux. Recopiez celui qu'affiche le harness, puis collez-le dans le champ « Jeton d'appareil » : sur la page de cette machine, ou dans la feuille « Adresse » quand vous saisissez une adresse à la main.")
    case .origineRefusee:
      return L("origine refusée (403) — un client natif ne doit jamais envoyer d'en-tête Origin")
    case let .appairageRefuse(motif, detail):
      // LES DEUX MOTIFS CONNUS SONT TRADUITS, pas affichés tels quels : l'hôte
      // écrit ses refus en ASCII sans accent (ils finissent dans un journal de
      // terminal), et les montrer bruts à l'utilisateur donnerait « code expire »
      // dans une interface française soignée. Un motif INCONNU, lui, est montré
      // tel quel : l'inventer serait pire que l'afficher.
      //
      // DEUX CLÉS PLUTÔT QU'UNE AVEC DES ESPACES DE BORD : une clé qui commence ou
      // finit par une espace est invisible à la relecture, et le test de parité
      // des tables ne la distinguerait pas de sa voisine.
      let geste = L("demandez un nouveau code dans le panneau « Appairer un appareil » du Mac.")
      switch motif {
      case Self.motifCodeExpire:
        return L("Ce code d'appairage a expiré.") + " " + geste
      case Self.motifCodeInconnu:
        return L("Ce code d'appairage n'est plus valable : il a déjà servi, ou il n'a jamais été émis.") + " " + geste
      default:
        let brut = detail?.isEmpty == false ? detail! : motif
        return L("appairage refusé :") + " " + brut + " — " + geste
      }
    case .appairageNonSupporte:
      return L("cet hôte ne sait pas échanger un code d'appairage : son plugin dsh-remote est plus ancien que cette application. Mettez le plugin à jour, ou collez le jeton d'appareil à la main.")
    case .ecritureRefusee:
      // LE REMÈDE EST NOMMÉ, ET IL EST AILLEURS : la portée se change sur la
      // MACHINE qui héberge le harness, pas dans l'application. Un message qui
      // laisserait chercher un réglage ici serait un faux remède.
      return L("écriture refusée (403) — ce jeton autorise la lecture, pas l'écriture. Le harness a tiré un jeton en lecture seule : relancez-le avec DSH_REMOTE_PORTEE=ecriture, puis saisissez le nouveau jeton.")
    case let .versionIncompatible(recue, supportee):
      return String(
        format: L("protocole incompatible : le serveur annonce la version %d, ce client sait lire la %d"),
        recue, supportee)
    case let .reponseInattendue(code):
      return String(format: L("réponse inattendue (HTTP %d)"), code)
    case let .refusServeur(statut, motif, code):
      let marque = code.map { " [\($0)]" } ?? ""
      return String(format: L("refus de l'hôte%@ : %@ (HTTP %d)"), marque, motif, statut)
    case let .adresseInvalide(detail):
      return L("adresse invalide :") + " " + detail
    case let .transport(detail):
      return L("échec de transport :") + " " + detail
    case let .decodage(detail):
      return L("réponse illisible :") + " " + detail
    case .nonModifie:
      return L("l'hôte n'a rien renvoyé : la liste était marquée inchangée, et ce client n'en a pas de copie")
    }
  }
}
