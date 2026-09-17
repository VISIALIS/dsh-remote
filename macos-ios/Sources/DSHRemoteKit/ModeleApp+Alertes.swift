import Foundation

/// LES ALERTES — ce qu'on signale à l'utilisateur, et à quelle condition.
///
/// POURQUOI CE FICHIER EXISTE. Ce domaine décide de ce qui INTERROMPT quelqu'un : un
/// tour qui se termine, une décision qui attend. Ses règles sont nées de défauts
/// constatés, et trois d'entre elles ne se devinent pas :
///
///   1. **la première observation n'alerte pas.** Au lancement, la liste arrive
///      complète : sans cette règle, trois sessions déjà bloquées produiraient trois
///      alertes pour un état que l'utilisateur a sous les yeux ;
///   2. **la génération fait partie de la comparaison.** Après un changement de
///      machine, la première liste du nouvel hôte ne compare rien — sinon trois
///      sessions déjà en attente ailleurs alerteraient pour un état que personne n'a
///      vu commencer ;
///   3. **rien ne part quand les alertes sont éteintes**, et le réglage n'est pas
///      supposé : il est lu dans les préférences, et la permission système est
///      demandée AVANT, jamais après.
///
/// LA CONTRAINTE, RAPPELÉE ICI : une extension Swift ne porte pas de propriété
/// stockée. L'état — `terminees`, `rappelsDeFin`, `observationPrecedente`,
/// `alertesActives`, `alerteur` — reste dans la classe ; ses méthodes vivent ici.
///
/// CE QUE CE DÉPLACEMENT COÛTE, ET QUI EST ASSUMÉ : cinq membres passent de `private`
/// à `internal` (dont les setters `private(set)` de `terminees` et `alertesActives`).
/// La surface PUBLIQUE ne change pas.
extension ModeleApp {

  public func definirAlertes(_ actives: Bool) async -> Bool {
    guard actives else {
      alertesActives = false
      persistance.memoriserAlertes(false)
      return false
    }
    let accordees = await alerteur.demanderAutorisation()
    alertesActives = accordees
    persistance.memoriserAlertes(accordees)
    if !accordees {
      signaler(
        "Les alertes n'ont pas été autorisées. Autorisez-les dans les réglages du système, puis rallumez cet interrupteur.")
    }
    return accordees
  }

  /// Confronte la liste reçue à la précédente pour détecter les fins de tour.
  ///
  /// Appelé APRÈS chaque mise à jour de `sessions`, et jamais avant : la règle
  /// compare deux observations successives, donc l'ordre compte.
  func observerLesFinsDeTour() {
    let observations = sessions.map {
      EtatObserve(identifiant: $0.id, enCours: $0.statut == "en_cours")
    }
    let termineesAvant = terminees
    terminees = rappelsDeFin.observer(observations, regardee: sessionOuverte?.id)
    prevenirSiNecessaire(termineesAvant: termineesAvant)
  }

  /// LES ALERTES PARTENT D'ICI, et d'ici seulement : c'est le seul endroit qui
  /// voit DEUX observations successives, donc le seul qui puisse dire ce qui a
  /// CHANGÉ.
  ///
  /// POURQUOI LA PREMIÈRE OBSERVATION N'ALERTE PAS. Au lancement, la liste arrive
  /// complète : sans cette règle, trois sessions déjà bloquées produiraient trois
  /// alertes pour un état que l'utilisateur voit à l'écran. `observationPrecedente`
  /// vaut `nil` tant qu'aucune liste n'a été reçue, et c'est ce `nil` qui
  /// distingue « tout est nouveau » de « rien n'a changé ».
  func prevenirSiNecessaire(termineesAvant: Set<String>) {
    let attendent = Set(sessions.filter { $0.attendReponse == true }.map(\.id))
    let precedente = observationPrecedente
    observationPrecedente = (generation: generation, attendent: attendent, terminees: terminees)
    // LA GÉNÉRATION FAIT PARTIE DE LA COMPARAISON. Après un changement de
    // machine, la première liste du nouvel hôte ne compare rien : elle retient.
    // Sans cela, trois sessions déjà bloquées ailleurs produiraient trois alertes
    // pour un état que personne n'a vu commencer.
    guard alertesActives, let precedente, precedente.generation == generation else { return }

    let alertes = Alerte.aEnvoyer(
      attendent: attendent,
      attendaientAvant: precedente.attendent,
      terminees: terminees,
      termineesAvant: termineesAvant,
      regardee: sessionOuverte?.id)
    guard !alertes.isEmpty else { return }
    Task { [alerteur] in
      for alerte in alertes { await alerteur.prevenir(alerte) }
    }
  }

  /// Efface le rappel d'une session, parce que l'utilisateur l'a ouverte.
  ///
  /// PUBLIQUE DEPUIS LES GESTES DE LISTE, et pour une raison précise : le
  /// rappel de fin se consommait uniquement en OUVRANT la session, ce qui était
  /// le seul moyen de dire « j'ai vu ». Le glissement et le menu contextuel
  /// offrent maintenant l'action sans quitter la liste — et sans elle, ils
  /// n'auraient rien à proposer que du copier.
  public func marquerCommeVue(_ identifiant: String) {
    rappelsDeFin.oublier(identifiant)
    terminees.remove(identifiant)
  }
}
