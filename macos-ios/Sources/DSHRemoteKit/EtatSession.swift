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
  /// Un tour vient de se TERMINER et l'utilisateur ne l'a pas encore vu.
  ///
  /// C'est le rappel de fin de l'interface web, et il ne dit PAS la même chose
  /// que l'inactivité : une session au repos depuis toujours est bleue, une
  /// session qui vient de finir est verte. La différence est celle qui compte
  /// quand on a lancé un travail et qu'on attend son résultat — sans elle, il
  /// faut ouvrir chaque session pour savoir laquelle a avancé.
  case terminee
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

  /// - Parameters:
  ///   - statut: `en_cours`, `inactif`, ou `nil` quand la session n'est pas
  ///     ouverte dans le processus du harness.
  ///   - vivante: le harness connaît-il encore cette session ?
  ///   - rappelDeFin: une fin de tour non vue a-t-elle été détectée ?
  ///     Voir `RappelsDeFin` pour la règle, qui est une transition et non un champ.
  public init(statut: String?, vivante: Bool?, rappelDeFin: Bool = false) {
    // L'ordre est délibéré : travailler PRIME sur tout le reste. Une session qui
    // a fini puis repris ne doit pas rester verte — elle est de nouveau orange.
    if statut == "en_cours" {
      self = .enCours
    } else if rappelDeFin {
      self = .terminee
    } else if statut == "inactif" {
      self = .inactive
    } else {
      self = .inconnue
    }
  }

  /// Vrai si l'indicateur doit s'animer.
  public var anime: Bool { self == .enCours }
}
