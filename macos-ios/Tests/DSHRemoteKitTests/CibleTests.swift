import Foundation
import Testing

@testable import DSHRemoteKit

// LA CIBLE SE REMPLACE EN UN POINT.
//
// Défaut mesuré avant ce travail : le journal d'un démarrage réel montrait
// l'adresse OSCILLER entre deux machines en vingt secondes — `macmini` à 1,4 s,
// `macbook-air` à 5,3 s, `macmini` à 19,1 s — parce que la bascule, la
// mémorisation et la reconnexion écrivaient chacune la sienne dans cinq champs
// séparés, sans que personne ne voie l'ensemble.
//
// Ces tests éprouvent les transitions, et surtout la règle qui a coûté le plus :
// **un échec ne change jamais la machine de l'utilisateur**.

private let enLigne = ServeurMac(nom: "Portable Un", nomDNS: "portable-un.exemple.ts.net", enLigne: true)
private let eteint = ServeurMac(nom: "Portable Deux", nomDNS: "portable-deux.exemple.ts.net", enLigne: false)

@MainActor
@Test("Consigner un échec ne change PAS la cible")
func echecNeChangePasLaCible() async {
  let modele = ModeleApp()
  modele.remplacerServeursPourEssai([enLigne, eteint])
  modele.choisir(eteint)
  #expect(modele.adresse == eteint.adresse)

  // La machine est hors ligne : `connecter()` refuse SANS émettre de requête
  // (c'est le garde qui évite les 21 secondes d'attente mesurées).
  await modele.connecter()

  #expect(modele.adresse == eteint.adresse, "un échec ne doit pas déplacer la cible")
  #expect(modele.serveurChoisi == eteint)
  #expect(modele.echecCible?.raison == .horsLigne)
}

@MainActor
@Test("La bascule remplace la machine ENTIÈRE, et laisse un avis")
func basculeComplete() async {
  let modele = ModeleApp()
  modele.remplacerServeursPourEssai([enLigne, eteint])
  modele.choisir(eteint)
  await modele.connecter()

  // La preuve d'échec existe : la bascule est autorisée.
  await modele.ajusterAuParc()

  // Adresse, nom ET machine changent ensemble — c'est tout l'intérêt d'une
  // valeur unique : impossible d'en oublier une.
  #expect(modele.adresse == enLigne.adresse)
  #expect(modele.nomServeur == enLigne.nom)
  #expect(modele.serveurChoisi == enLigne)
  #expect(modele.choixAjuste?.contains("hors ligne") == true)
}

@MainActor
@Test("Un choix de l'utilisateur efface l'avis de bascule")
func avisEffaceParUnChoix() async {
  let modele = ModeleApp()
  modele.remplacerServeursPourEssai([enLigne, eteint])
  modele.choisir(eteint)
  await modele.connecter()
  await modele.ajusterAuParc()
  #expect(modele.choixAjuste != nil)

  // L'avis racontait ce que l'APPLICATION avait décidé ; un choix explicite le
  // rend caduc — il restait affiché sinon, sous une liste chargée.
  modele.choisir(enLigne)
  #expect(modele.choixAjuste == nil)
  #expect(modele.adresse == enLigne.adresse)
}

@MainActor
@Test("Oublier le serveur vide la cible d'un coup")
func oublierVideTout() {
  let modele = ModeleApp()
  modele.remplacerServeursPourEssai([enLigne])
  modele.choisir(enLigne)
  modele.oublierServeur()

  // Adresse, nom, machine : les trois viennent de la MÊME valeur, donc les
  // trois partent ensemble.
  #expect(modele.adresse.isEmpty)
  #expect(modele.nomServeur == nil)
  #expect(modele.serveurChoisi == nil)
  #expect(modele.echecCible == nil)
  #expect(modele.choixAjuste == nil)
}

@MainActor
@Test("Écrire une adresse ne prétend pas connaître la machine")
func adresseEcriteSansMachine() {
  let modele = ModeleApp()
  modele.remplacerServeursPourEssai([enLigne])

  // Une adresse qui correspond à une machine découverte la reconnaît…
  modele.definirAdresse(enLigne.adresse)
  #expect(modele.serveurChoisi == enLigne)
  #expect(modele.nomServeur == enLigne.nom)

  // …et une adresse inconnue ne s'invente ni nom ni machine.
  modele.definirAdresse("http://ailleurs.exemple.ts.net")
  #expect(modele.serveurChoisi == nil)
  #expect(modele.nomServeur == nil)
  #expect(modele.adresse == "http://ailleurs.exemple.ts.net")
}
