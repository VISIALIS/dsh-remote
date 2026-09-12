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
  /// Session ouverte dans le harness, sans travail en cours.
  case inactive
  /// Session présente sur disque mais absente du processus : état INCONNU.
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
