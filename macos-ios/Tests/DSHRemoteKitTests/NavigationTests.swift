import Foundation
import Testing

@testable import DSHRemoteKit

// L'ÉTAT DE NAVIGATION, ÉPROUVÉ COMME LE RESTE DE LA PERSISTANCE.
//
// POURQUOI CE FICHIER EXISTE. Ces deux tests ont d'abord été ajoutés à la fin de
// `PersistanceTests` : le compilateur y refusait la référence au domaine d'essai
// du fichier — « cannot find 'domaineDEssai' in scope » — alors que le MÊME appel
// passait dans le test voisin, vingt-neuf lignes plus haut. Le déplacement n'a pas
// suffi : l'échec suit le SECOND `@Test` du fichier, quel qu'il soit, et il
// disparaît dès que le domaine jetable est construit SUR PLACE plutôt que par un
// helper de fichier.
//
// C'est constaté, pas expliqué : quatre lignes dupliquées valent mieux qu'un
// contournement dont personne ne saurait dire s'il tient encore dans six mois.
//
// CE QUI SE RETIENT : les espaces dépliés, le mode d'envoi, la session consultée.
// CE QUI NE SE RETIENT PAS, et qui compte autant : aucune donnée de session — ni
// titre, ni journal, ni projet.

@MainActor
@Test("L'état de navigation fait un aller-retour, et les espaces sont TRIÉS")
func navigationAllerRetour() {
  // Un domaine de préférences à nous, jamais celui de la machine.
  let nom = UUID().uuidString
  let defaults = UserDefaults(suiteName: nom) ?? .standard
  defaults.removePersistentDomain(forName: nom)

  let modele = ModeleApp(persistance: Persistance(defaults: defaults, documents: nil))

  // Rien de mémorisé : des valeurs par défaut, pas des inventions.
  #expect(modele.navigation.espacesDeplies.isEmpty)
  #expect(modele.navigation.modeEnvoi == .queue)
  #expect(modele.navigation.sessionConsultee == nil)

  // L'ORDRE D'INSERTION NE DOIT RIEN CHANGER À CE QUI EST ÉCRIT : deux ensembles
  // identiques produisent le même enregistrement, sans quoi un test de
  // persistance échouerait au hasard de l'itération d'un `Set`.
  modele.definirEspacesDeplies(["zeta", "alpha"])
  #expect(modele.navigation.espacesDeplies == ["alpha", "zeta"])

  modele.definirModeEnvoi(.steer)
  modele.definirSessionConsultee("session-42")

  // Un AUTRE modèle, sur le même domaine : c'est la relecture au lancement.
  let relu = ModeleApp(persistance: Persistance(defaults: defaults, documents: nil))
  #expect(relu.navigation.espacesDeplies == ["alpha", "zeta"])
  #expect(relu.navigation.espacesDepliesEnsemble == ["alpha", "zeta"])
  #expect(relu.navigation.modeEnvoi == .steer)
  #expect(relu.navigation.sessionConsultee == "session-42")
}

@MainActor
@Test("Une session mémorisée n'est rouverte que si l'hôte la nomme encore")
func sessionARouvrirEstRevalidee() {
  let nom = UUID().uuidString
  let defaults = UserDefaults(suiteName: nom) ?? .standard
  defaults.removePersistentDomain(forName: nom)

  let modele = ModeleApp(persistance: Persistance(defaults: defaults, documents: nil))

  // Aucune session reçue : rien à rouvrir, même avec un identifiant mémorisé.
  // C'est le point qui évite d'ouvrir un journal disparu sous un titre oublié.
  modele.definirSessionConsultee("session-qui-n-existe-plus")
  #expect(modele.sessionARouvrir == nil)

  // Et sans identifiant mémorisé, il n'y a rien à rouvrir non plus.
  modele.definirSessionConsultee(String?.none)
  #expect(modele.sessionARouvrir == nil)
  #expect(modele.navigation.sessionConsultee == nil)
}
