import SwiftUI

/// État visuel d'une session dans la liste.
///
/// POURQUOI UN TYPE PLUTÔT QU'UN BOOLÉEN. L'interface web distingue plusieurs
/// situations — un tour en cours, une session inactive, une session dont l'état
/// n'est pas connu — et un simple « vivante » les confondait toutes. Le serveur
/// transporte maintenant le statut d'agent (`en_cours` / `inactif`), et ce type
/// en fait un affichage.
public enum EtatSession: Sendable, Equatable {
  /// Un tour s'exécute : le modèle travaille.
  case enCours
  /// Session chargée dans le processus du harness, sans travail en cours.
  ///
  /// « Chargée » et non « vivante » : être en mémoire signifie que le harness
  /// peut la reprendre instantanément, pas qu'elle travaille. La confusion entre
  /// les deux fait paraître anormale une situation qui ne l'est pas.
  case inactive
  /// Session présente sur disque mais absente du processus : état INCONNU.
  ///
  /// CE CAS NE DOIT PAS RESSEMBLER À UN AUTRE. Il était affiché comme un point
  /// vert, c'est-à-dire comme une session TERMINÉE : l'interface affirmait donc
  /// quelque chose qu'elle ne savait pas. Un état inconnu se montre comme
  /// inconnu — anneau vide — et jamais comme une conclusion.
  case inconnue

  public init(statut: String?, vivante: Bool?) {
    switch statut {
    case "en_cours": self = .enCours
    case "inactif": self = .inactive
    default: self = .inconnue
    }
  }

  /// Vrai si l'indicateur doit s'animer.
  public var anime: Bool { self == .enCours }
}
