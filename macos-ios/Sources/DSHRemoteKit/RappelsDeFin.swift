import Foundation

// Rappels de fin — la règle qui allume la pastille verte de la liste.
//
// POURQUOI CETTE RÈGLE VIT ICI, ET PAS DANS UNE VUE. Elle n'est pas un simple
// reflet d'un champ : c'est une DÉTECTION DE TRANSITION, avec un état conservé
// entre deux rafraîchissements. Enfermée dans une vue, elle ne se vérifierait
// qu'en regardant l'écran au bon moment ; isolée, elle se teste en quelques
// lignes — et c'est exactement le genre de règle qu'on casse sans le voir.
//
// LA RÈGLE VIENT DE L'INTERFACE WEB, recopiée de son implémentation
// (`syncCompletedNotifications` du contrôleur de sessions) plutôt que devinée :
//
//   1. à la PREMIÈRE observation d'une session, on retient seulement si elle
//      travaille — une session déjà au repos au chargement ne produit AUCUN
//      rappel. Sans cela, ouvrir l'application afficherait une liste de points
//      verts qui ne veulent rien dire ;
//   2. la transition travail → repos arme un rappel, SAUF si c'est la session
//      que l'utilisateur regarde ;
//   3. repasser en travail DÉSARME le rappel : la session retravaille, il n'y a
//      plus de fin à annoncer ;
//   4. une session qui disparaît de la liste perd son état et son rappel ;
//   5. ouvrir la session efface son rappel — c'est la définition de « vu ».
//
// Ce que la règle NE peut pas faire, et qu'il faut savoir : elle n'observe que
// ce que l'application voit. Un tour terminé pendant que l'application était
// fermée, ou entre deux interrogations, ne produit pas de rappel. L'interface
// web a exactement la même limite — son état est en mémoire, comme celui-ci.

/// Ce qu'il faut savoir d'une session pour décider d'un rappel de fin.
public struct EtatObserve: Sendable, Equatable {
  public let identifiant: String
  public let enCours: Bool

  public init(identifiant: String, enCours: Bool) {
    self.identifiant = identifiant
    self.enCours = enCours
  }
}

/// Détecte les fins de tour et retient celles qui n'ont pas été vues.
public struct RappelsDeFin: Sendable, Equatable {
  /// Sessions déjà observées au moins une fois.
  private var connues: Set<String> = []
  /// Sessions observées en train de travailler au dernier passage.
  private var enCours: Set<String> = []
  /// Sessions terminées et non encore regardées.
  private var rappels: Set<String> = []

  public init() {}

  /// Les rappels à afficher : sessions finies que l'utilisateur n'a pas vues.
  public var affiches: Set<String> { rappels }

  /// Enregistre une observation de la liste et rend les rappels à jour.
  ///
  /// - Parameters:
  ///   - sessions: l'état de travail de chaque session listée.
  ///   - regardee: la session ouverte à l'écran, s'il y en a une. Une fin de tour
  ///     sur cette session-là ne produit pas de rappel : l'utilisateur la voit.
  /// - Returns: l'ensemble des rappels après mise à jour.
  @discardableResult
  public mutating func observer(_ sessions: [EtatObserve], regardee: String?) -> Set<String> {
    let presentes = Set(sessions.map(\.identifiant))
    for session in sessions {
      if !connues.contains(session.identifiant) {
        // Première observation : on retient, on n'annonce rien.
        connues.insert(session.identifiant)
        if session.enCours { enCours.insert(session.identifiant) }
        continue
      }
      let travaillait = enCours.contains(session.identifiant)
      if travaillait, !session.enCours {
        if session.identifiant != regardee { rappels.insert(session.identifiant) }
        enCours.remove(session.identifiant)
      } else if session.enCours {
        // Elle retravaille : le rappel de la fin précédente n'a plus lieu d'être.
        rappels.remove(session.identifiant)
        enCours.insert(session.identifiant)
      }
    }
    // Ce qui a quitté la liste n'a plus d'état observable.
    connues.formIntersection(presentes)
    enCours.formIntersection(presentes)
    rappels.formIntersection(presentes)
    return rappels
  }

  /// Efface le rappel d'une session — parce que l'utilisateur l'a ouverte.
  public mutating func oublier(_ identifiant: String) {
    rappels.remove(identifiant)
  }
}
