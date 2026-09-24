import Foundation

/// Un bloc de contenu à l'intérieur d'un message d'assistant ou d'un résultat d'outil.
///
/// Le harness emploie `camelCase` ; on décode donc avec
/// `convertFromSnakeCase` (qui laisse `camelCase` intact) plutôt qu'en énumérant
/// des dizaines de clés — c'est la forme la moins susceptible de casser.
public struct BlocContenu: Sendable, Decodable {
  public let type: String?
  public let text: String?
  public let toolCallId: String?
  public let toolName: String?
  public let content: [BlocContenu]?

  /// Le texte affichable d'un bloc, ou `nil` si le bloc n'en porte pas.
  public var texteAffiche: String? {
    if let text, !text.isEmpty { return text }
    if let content, !content.isEmpty {
      let morceaux = content.compactMap(\.texteAffiche)
      if !morceaux.isEmpty { return morceaux.joined(separator: "\n") }
    }
    return nil
  }
}

/// Le message porté par un enregistrement de journal.
public struct MessageJournal: Sendable, Decodable {
  public let role: String?
  public let source: SourceJournal?
  public let content: [BlocContenu]?

  public struct SourceJournal: Sendable, Decodable {
    public let kind: String?
    public let callId: String?
  }
}

/// La partie `data` d'un enregistrement, quand elle est lisible.
public struct DonneesJournal: Sendable, Decodable {
  public let turn: Int?
  public let step: Int?
  public let name: String?
  public let arguments: String?
  public let callId: String?
  public let message: MessageJournal?
  public let preset: String?
  public let mode: String?
  public let policy: String?
  public let title: String?
  public let objective: String?
}

/// Un enregistrement de journal suffisamment décodé pour être affiché.
///
/// Les champs inconnus sont ignorés, jamais devinés : un type d'événement que
/// cette version ne connaît pas s'affiche par son nom, pas par une erreur.
public struct EvenementAffiche: Sendable, Identifiable {
  public let enregistrement: EnregistrementJournal
  public let donnees: DonneesJournal?

  public var id: Int { enregistrement.seq ?? -1 }
  public var type: String { enregistrement.type ?? "inconnu" }

  /// Un titre court et lisible pour la ligne de liste.
  public var resume: String {
    switch type {
    case "user/message":
      return premierTexte(role: "user") ?? "(message utilisateur)"
    case "assistant/message":
      let reflexion = blocs(de: "reasoning").first
      let reponse = blocs(de: "text").first
      return reponse ?? reflexion.map { L("réflexion :") + " " + $0 } ?? L("(message assistant)")
    case "tool/call":
      let nom = donnees?.name ?? "?"
      return L("outil") + " \(nom)"
    case "tool/result":
      return premierTexte(role: nil) ?? L("(résultat d'outil)")
    case "session/title":
      return donnees?.title ?? L("(titre)")
    case "goal/change":
      return donnees?.objective ?? L("(objectif)")
    case "permission/preset":
      return L("preset :") + " \(donnees?.preset ?? "?")"
    case "sandbox/mode":
      return L("bac à sable :") + " \(donnees?.mode ?? "?")"
    default:
      return type
    }
  }

  /// Vrai si l'enregistrement porte du contenu long, donc repliable.
  ///
  /// POURQUOI CE N'EST PLUS UN SEUIL DE CARACTÈRES. La ligne montre QUATRE lignes
  /// de texte (`lineLimit(4)`) et n'offrait le bouton « Développer » qu'au-delà de
  /// 120 caractères : un message de six lignes COURTES — quatre-vingt-dix
  /// caractères — était donc tronqué à l'écran sans aucun moyen de lire la suite.
  /// Un texte caché ET rien pour l'ouvrir est le pire des deux mondes.
  ///
  /// Le compte des lignes est un fait du texte ; le nombre de caractères n'en est
  /// qu'une approximation. Comme la largeur de la vue n'est pas connue ici, une
  /// ligne longue est estimée à quarante caractères — la mesure d'un iPhone
  /// étroit, donc du cas qui tronque le plus tôt : mieux vaut offrir le bouton
  /// pour rien que de cacher un texte.
  public var estVolumineux: Bool {
    if (donnees?.arguments?.count ?? 0) > 120 { return true }
    let lignes = resume.split(separator: "\n", omittingEmptySubsequences: false)
    let estimees = lignes.reduce(0) { total, ligne in
      total + max(1, (ligne.count + 39) / 40)
    }
    return estimees > 4
  }

  private func blocs(de typeCherche: String) -> [String] {
    guard let contenu = donnees?.message?.content else { return [] }
    return contenu.filter { $0.type == typeCherche }.compactMap(\.texteAffiche)
  }

  private func premierTexte(role: String?) -> String? {
    guard let contenu = donnees?.message?.content else { return nil }
    if let role, donnees?.message?.role != role { return nil }
    return contenu.compactMap(\.texteAffiche).first
  }
}

/// Décode la partie `data` d'un enregistrement brut.
///
/// On repasse par `JSONSerialization` parce que le client transporte les
/// enregistrements sans les interpréter (`EnregistrementJournal` ne garde que
/// `type`, `seq`, `time`). C'est volontaire : le transport ne dépend pas de la
/// forme des événements, seule la présentation en dépend.
public enum DecodeurEvenement {
  public static func afficher(_ brut: EnregistrementJournal) -> EvenementAffiche {
    var donnees: DonneesJournal?
    if let corps = brut.corpsBrut,
      let decode = try? decodeur.decode(DonneesJournal.self, from: corps)
    {
      donnees = decode
    }
    return EvenementAffiche(enregistrement: brut, donnees: donnees)
  }

  private static let decodeur: JSONDecoder = {
    let decodeur = JSONDecoder()
    decodeur.keyDecodingStrategy = .convertFromSnakeCase
    return decodeur
  }()
}
