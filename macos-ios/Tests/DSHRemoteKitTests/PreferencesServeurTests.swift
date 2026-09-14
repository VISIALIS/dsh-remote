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
//
// POURQUOI CES TROIS TESTS ONT ÉTÉ RÉÉCRITS — un défaut trouvé en les faisant
// tourner treize fois de suite. Ils construisaient `ModeleApp()` sans rien
// injecter : ils lisaient donc les préférences RÉELLES de la machine, et les
// EFFAÇAIENT en sortant (`UserDefaults.standard.removeObject(forKey:)`). Deux
// conséquences, toutes deux mesurées :
//
//   1. **ils n'étaient pas hermétiques** : la suite de tests modifiait les
//      réglages de l'application installée, et les effaçait ;
//   2. **ils étaient instables** : swift-testing exécute les tests en parallèle,
//      et deux d'entre eux écrivaient puis supprimaient la MÊME clé globale.
//      Constaté : « Régler un serveur ne règle pas les autres » échouait environ
//      une fois sur treize, sur une valeur qu'un test voisin venait d'effacer.
//
// Chaque test construit donc son propre domaine de préférences, jetable — comme
// `PersistanceTests` et `NavigationTests`. Le nettoyage manuel disparaît : il n'y
// a plus rien à nettoyer.

private let premiere = "http://portable-un.exemple.ts.net"
private let seconde = "http://portable-deux.exemple.ts.net"

@Test("Régler un serveur ne règle pas les autres")
@MainActor
func preferencesIndependantes() {
  let modele = modeleDeTest()
  modele.definirPreferences(pour: premiere) { $0.suivi = false }

  #expect(modele.preferences(pour: premiere).suivi == false)
  // L'autre machine garde les valeurs par défaut : rien n'a fuité.
  #expect(modele.preferences(pour: seconde).suivi == true)
  #expect(modele.preferences(pour: seconde).chargeesSeulement == true)

  // Et le filtre se règle séparément du suivi, sur la même machine.
  modele.definirPreferences(pour: seconde) { $0.chargeesSeulement = false }
  #expect(modele.preferences(pour: seconde).suivi == true)
  #expect(modele.preferences(pour: seconde).chargeesSeulement == false)
}

@Test("L'adresse est écrite de plusieurs façons : c'est le même serveur")
@MainActor
func memeServeurMemesPreferences() {
  let modele = modeleDeTest()
  // Avec protocole, sans protocole, avec une barre finale : la clé est la même,
  // sans quoi le réglage se perdrait selon la façon dont l'adresse a été saisie.
  modele.definirPreferences(pour: "portable-un.exemple.ts.net") { $0.suivi = false }
  #expect(modele.preferences(pour: "http://portable-un.exemple.ts.net").suivi == false)
  #expect(modele.preferences(pour: "http://portable-un.exemple.ts.net/").suivi == false)
}

@Test("Après relance, les réglages par serveur sont retrouvés")
@MainActor
func preferencesPersistees() {
  // Le MÊME domaine pour les deux modèles : c'est ce qui éprouve la relecture —
  // et lui seul, puisque rien d'autre n'écrit dedans.
  let persistance = persistanceDeTest()
  let premier = ModeleApp(persistance: persistance)
  premier.definirPreferences(pour: premiere) { $0.suivi = false }

  // Un modèle neuf lit ce qui a été écrit — c'est le contrat des préférences.
  let relu = ModeleApp(persistance: persistance)
  #expect(relu.preferences(pour: premiere).suivi == false)
}
