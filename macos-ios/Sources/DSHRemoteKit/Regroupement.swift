import Foundation

/// Un espace de travail et les sessions qu'il contient.
///
/// Reproduit l'arbre de l'interface web : un dossier par espace de travail, ses
/// sessions dessous, et les sous-agents imbriqués sous leur session parente.
public struct EspaceDeTravail: Sendable, Identifiable, Hashable {
  /// Nom affiché — le dernier segment du chemin de travail.
  public let nom: String
  /// Chemin complet, pour lever toute ambiguïté entre deux dossiers homonymes.
  public let chemin: String
  public let sessions: [SessionListee]

  public var id: String { chemin }
  public var nbSessions: Int { sessions.count }
  public var nbVivantes: Int { sessions.filter { $0.vivante == true }.count }
}

/// Regroupe des sessions en espaces de travail.
///
/// POURQUOI UN REGROUPEMENT PLUTÔT QU'UN TRI. Une liste plate de 106 sessions
/// mêlant dix projets est illisible : on ne cherche pas « une session », on
/// cherche « la session de ce projet ». L'interface web le fait déjà ; s'en
/// écarter ferait deux outils qui ne se ressemblent plus.
public enum Regroupement {
  /// Nom d'espace de travail d'une session.
  ///
  /// On préfère `cwd`, qui vient du journal et est exact. Le nom du dossier de
  /// projet ne sert que de repli : DSH y remplace les `/` par des `-`, ce qui
  /// rend « dsh-plugins » indiscernable de « dsh/plugins ». Un libellé déduit
  /// d'un encodage perdant ne doit jamais primer sur une valeur exacte.
  public static func nomEspace(_ session: SessionListee) -> (nom: String, chemin: String) {
    if let cwd = session.resume.cwd, !cwd.isEmpty {
      let nom = (cwd as NSString).lastPathComponent
      return (nom.isEmpty ? cwd : nom, cwd)
    }
    if let indicatif = session.cwdIndicatif, !indicatif.isEmpty {
      let nom = (indicatif as NSString).lastPathComponent
      return (nom.isEmpty ? indicatif : nom, indicatif)
    }
    return ("Sans projet", "?")
  }

  /// Vrai si la session est un sous-agent délégué.
  ///
  /// `profondeurDelegation` vient de l'en-tête du journal ; une session de
  /// profondeur supérieure à zéro a été créée par une autre.
  public static func estSousAgent(_ session: SessionListee) -> Bool {
    (session.resume.profondeurDelegation ?? 0) > 0
  }

  /// Construit l'arbre : espaces de travail triés, sessions récentes d'abord.
  ///
  /// Les espaces de travail sont ordonnés par activité la plus récente, comme
  /// dans l'interface web : le projet sur lequel on travaille remonte en haut,
  /// sans avoir à le chercher.
  public static func espaces(_ sessions: [SessionListee]) -> [EspaceDeTravail] {
    var parChemin: [String: (nom: String, sessions: [SessionListee])] = [:]
    var ordre: [String] = []

    for session in sessions {
      let (nom, chemin) = nomEspace(session)
      if parChemin[chemin] == nil {
        parChemin[chemin] = (nom, [])
        ordre.append(chemin)
      }
      parChemin[chemin]?.sessions.append(session)
    }

    let espaces = ordre.compactMap { chemin -> EspaceDeTravail? in
      guard let entree = parChemin[chemin] else { return nil }
      // Sous-agents d'abord écartés du niveau supérieur : ils seront imbriqués.
      let racines = entree.sessions.filter { !estSousAgent($0) }
      let enfants = entree.sessions.filter { estSousAgent($0) }
      let triees = (racines + enfants).sorted { gauche, droite in
        dateEffective(gauche) > dateEffective(droite)
      }
      return EspaceDeTravail(nom: entree.nom, chemin: chemin, sessions: triees)
    }

    return espaces.sorted { gauche, droite in
      dateEspace(gauche) > dateEspace(droite)
    }
  }

  /// Sous-agents rattachés à une session, pour l'imbrication.
  ///
  /// Le rattachement est INDICATIF : l'en-tête d'un sous-agent ne nomme pas son
  /// parent. On les place donc sous la session racine la plus récente de leur
  /// espace, ce qui correspond à l'usage réel — un sous-agent est lancé par la
  /// session en cours — sans prétendre à une exactitude que la donnée n'a pas.
  public static func sousAgents(de session: SessionListee, dans espace: EspaceDeTravail) -> [SessionListee] {
    guard !estSousAgent(session) else { return [] }
    return espace.sessions.filter { estSousAgent($0) }
  }

  static func dateEffective(_ session: SessionListee) -> Double {
    Double(session.resume.dernierEvenementLe ?? 0) / 1000
  }

  static func dateEspace(_ espace: EspaceDeTravail) -> Double {
    espace.sessions.map(dateEffective).max() ?? 0
  }
}

/// Formate une date en âge court, comme l'interface web : « 1min », « 6h », « 3j ».
public enum AgeLisible {
  public static func texte(_ millisecondes: Int?, maintenant: Date = Date()) -> String {
    guard let millisecondes, millisecondes > 0 else { return "" }
    let secondes = maintenant.timeIntervalSince1970 - Double(millisecondes) / 1000
    guard secondes > 0 else { return "à l'instant" }
    if secondes < 60 { return "\(Int(secondes))s" }
    if secondes < 3600 { return "\(Int(secondes / 60))min" }
    if secondes < 86400 { return "\(Int(secondes / 3600))h" }
    if secondes < 86400 * 30 { return "\(Int(secondes / 86400))j" }
    return "\(Int(secondes / (86400 * 30)))mois"
  }
}
