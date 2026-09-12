import Foundation
import Testing

@testable import DSHRemoteKit

// Tests des rappels de fin — la règle qui allume la pastille verte.
//
// Ces tests couvrent ce qui ne se voit PAS en regardant l'écran une fois : l'ordre
// des observations, la première observation, le retour en travail, et la
// disparition d'une session de la liste. Une régression sur l'un de ces points
// donne soit une liste de faux rappels au chargement, soit un rappel qui ne
// s'efface jamais.

private func observation(_ identifiant: String, _ enCours: Bool) -> EtatObserve {
  EtatObserve(identifiant: identifiant, enCours: enCours)
}

@Test("La première observation ne produit aucun rappel")
func premiereObservationSilencieuse() {
  // Sinon, ouvrir l'application afficherait un point vert sur TOUTES les
  // sessions au repos : un rappel qui ne veut rien dire.
  var rappels = RappelsDeFin()
  let rendus = rappels.observer(
    [observation("a", false), observation("b", false)], regardee: nil)
  #expect(rendus.isEmpty)
}

@Test("Une session qui travaille à la première observation n'annonce rien non plus")
func premiereObservationEnCours() {
  var rappels = RappelsDeFin()
  #expect(rappels.observer([observation("a", true)], regardee: nil).isEmpty)
  // …mais sa fin, observée ensuite, EST un rappel.
  #expect(rappels.observer([observation("a", false)], regardee: nil) == ["a"])
}

@Test("La transition travail → repos arme le rappel")
func transitionArmeLeRappel() {
  var rappels = RappelsDeFin()
  rappels.observer([observation("a", true)], regardee: nil)
  let rendus = rappels.observer([observation("a", false)], regardee: nil)
  #expect(rendus == ["a"])
  #expect(rappels.affiches == ["a"])
}

@Test("Une fin de tour sur la session REGARDÉE ne produit pas de rappel")
func sessionRegardeeSansRappel() {
  var rappels = RappelsDeFin()
  rappels.observer([observation("a", true)], regardee: "a")
  #expect(rappels.observer([observation("a", false)], regardee: "a").isEmpty)
  // La même fin, une fois la session quittée, produirait un rappel : la règle
  // dépend de ce que l'utilisateur regarde AU MOMENT de la fin.
  var autre = RappelsDeFin()
  autre.observer([observation("b", true)], regardee: nil)
  #expect(autre.observer([observation("b", false)], regardee: nil) == ["b"])
}

@Test("Ouvrir une session efface son rappel")
func ouvrirEffaceLeRappel() {
  var rappels = RappelsDeFin()
  rappels.observer([observation("a", true)], regardee: nil)
  #expect(rappels.observer([observation("a", false)], regardee: nil) == ["a"])
  rappels.oublier("a")
  #expect(rappels.affiches.isEmpty)
  // Et la fin suivante, si la session retravaille puis s'arrête, en produit un
  // nouveau : le rappel se réarme à chaque fin.
  rappels.observer([observation("a", true)], regardee: nil)
  #expect(rappels.observer([observation("a", false)], regardee: nil) == ["a"])
}

@Test("Repasser en travail désarme le rappel")
func retourEnTravailDesarme() {
  var rappels = RappelsDeFin()
  rappels.observer([observation("a", true)], regardee: nil)
  rappels.observer([observation("a", false)], regardee: nil)
  #expect(rappels.affiches == ["a"])
  // Elle retravaille : il n'y a plus de fin à annoncer.
  #expect(rappels.observer([observation("a", true)], regardee: nil).isEmpty)
}

@Test("Une session qui quitte la liste perd son rappel")
func sessionDisparue() {
  var rappels = RappelsDeFin()
  rappels.observer([observation("a", true)], regardee: nil)
  rappels.observer([observation("a", false)], regardee: nil)
  #expect(rappels.affiches == ["a"])
  // Le filtre « chargées en mémoire seulement » peut la masquer : un rappel
  // affiché pour une session absente de la liste serait invisible ET gênant.
  #expect(rappels.observer([observation("b", false)], regardee: nil).isEmpty)
}

@Test("Un état inconnu après une fin ne vaut pas un nouveau rappel")
func inconnuApresFin() {
  var rappels = RappelsDeFin()
  rappels.observer([observation("a", true)], regardee: nil)
  #expect(rappels.observer([observation("a", false)], regardee: nil) == ["a"])
  // La session n'est plus ouverte dans le processus : elle reste listée, sans
  // statut. Rien de nouveau ne s'annonce, et le rappel déjà armé demeure.
  #expect(rappels.observer([observation("a", false)], regardee: nil) == ["a"])
}

@Test("L'état affiché donne la priorité au travail en cours")
func prioriteDeLEtatAffiche() {
  // Un rappel armé ne doit jamais masquer une session qui retravaille : la
  // pastille orange est une information plus récente que la verte.
  #expect(EtatSession(statut: "en_cours", vivante: true, rappelDeFin: true) == .enCours)
  #expect(EtatSession(statut: "inactif", vivante: true, rappelDeFin: true) == .terminee)
  #expect(EtatSession(statut: "inactif", vivante: true, rappelDeFin: false) == .inactive)
  #expect(EtatSession(statut: nil, vivante: false, rappelDeFin: false) == .inconnue)
}
