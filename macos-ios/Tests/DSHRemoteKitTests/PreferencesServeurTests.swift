import Foundation
import Testing

@testable import DSHRemoteKit

// LES DEUX INTERRUPTEURS SONT PAR SERVEUR.
//
// Défaut corrigé, signalé par le propriétaire : « normalement, c'est spécifique à
// chaque serveur ». Il a raison, et les deux le sont pour la même raison — ils
// portent sur la CONNEXION à une machine. Le suivi décide si l'on interroge CE
// serveur toutes les trois secondes ; le filtre décide ce qu'on affiche de SA
// liste. Globaux, ils faisaient hériter chaque serveur des choix faits pour le
// précédent : on coupait le suivi pour un Mac endormi, et la machine suivante ne
// se rafraîchissait plus sans qu'on sache pourquoi.

private let premiere = "http://portable-un.exemple.ts.net"
private let seconde = "http://portable-deux.exemple.ts.net"

@Test("Régler un serveur ne règle pas les autres")
@MainActor
func preferencesIndependantes() {
  let modele = ModeleApp()
  modele.definirPreferences(pour: premiere) { $0.suivi = false }

  #expect(modele.preferences(pour: premiere).suivi == false)
  // L'autre machine garde les valeurs par défaut : rien n'a fuité.
  #expect(modele.preferences(pour: seconde).suivi == true)
  #expect(modele.preferences(pour: seconde).chargeesSeulement == true)

  // Et le filtre se règle séparément du suivi, sur la même machine.
  modele.definirPreferences(pour: seconde) { $0.chargeesSeulement = false }
  #expect(modele.preferences(pour: seconde).suivi == true)
  #expect(modele.preferences(pour: seconde).chargeesSeulement == false)

  UserDefaults.standard.removeObject(forKey: Persistance.clePreferences)
}

@Test("L'adresse est écrite de plusieurs façons : c'est le même serveur")
@MainActor
func memeServeurMemesPreferences() {
  let modele = ModeleApp()
  // Avec protocole, sans protocole, avec une barre finale : la clé est la même,
  // sans quoi le réglage se perdrait selon la façon dont l'adresse a été saisie.
  modele.definirPreferences(pour: "portable-un.exemple.ts.net") { $0.suivi = false }
  #expect(modele.preferences(pour: "http://portable-un.exemple.ts.net").suivi == false)
  #expect(modele.preferences(pour: "http://portable-un.exemple.ts.net/").suivi == false)

  UserDefaults.standard.removeObject(forKey: Persistance.clePreferences)
}

@Test("Après relance, les réglages par serveur sont retrouvés")
@MainActor
func preferencesPersistees() {
  let premier = ModeleApp()
  premier.definirPreferences(pour: premiere) { $0.suivi = false }

  // Un modèle neuf lit ce qui a été écrit — c'est le contrat des préférences.
  let relu = ModeleApp()
  #expect(relu.preferences(pour: premiere).suivi == false)

  UserDefaults.standard.removeObject(forKey: Persistance.clePreferences)
}
