import Foundation
import Testing

@testable import DSHRemoteKit

// LES OUTILS COMMUNS DES TESTS — et le défaut qu'ils corrigent.
//
// POURQUOI CE FICHIER EXISTE. Trente-trois tests construisaient `ModeleApp()` sans
// rien injecter : ils lisaient donc `UserDefaults.standard`, c'est-à-dire un
// domaine PARTAGÉ par toute la suite — et par la machine quand le processus de
// test porte son nom. Trois conséquences, toutes mesurées :
//
//   1. **des tests instables.** `swift test` exécute les tests EN PARALLÈLE :
//      deux tests qui écrivent la même clé globale se marchent dessus. Constaté :
//      « Un arbre vide par le filtre ne se confond pas avec un serveur sans
//      session » échouait 12 fois sur 15, sur une préférence qu'un test voisin
//      venait d'écrire ;
//   2. **un test qui modifiait les réglages de l'application installée** — et les
//      effaçait en sortant (`UserDefaults.standard.removeObject`) ;
//   3. **des échecs inexplicables d'une exécution à l'autre**, donc un doute
//      permanent sur la suite entière.
//
// La règle est donc : AUCUN test ne touche au domaine partagé. Chacun construit
// son modèle sur un domaine jetable, et l'y laisse.
//
// POURQUOI LE HELPER EST DANS SON PROPRE FICHIER. Un helper privé à un fichier
// s'est révélé invisible depuis le SECOND `@Test` de ce fichier (constaté deux
// fois, dans `PersistanceTests` puis dans `NavigationTests`) : un helper partagé,
// déclaré une fois, évite la question.

/// Un modèle sur des préférences JETABLES, jamais celles de la machine.
///
/// `@MainActor` PARCE QUE `ModeleApp` L'EST : un helper non isolé ne peut pas
/// construire le modèle.
@MainActor
func modeleDeTest() -> ModeleApp {
  ModeleApp(persistance: persistanceDeTest())
}

/// Un domaine de préférences jetable, pour les tests qui construisent leur
/// `Persistance` eux-mêmes (persistance, navigation).
func persistanceDeTest(documents: URL? = nil) -> Persistance {
  let nom = UUID().uuidString
  let defaults = UserDefaults(suiteName: nom) ?? .standard
  defaults.removePersistentDomain(forName: nom)
  return Persistance(defaults: defaults, documents: documents)
}

/// Un Info.plist qui AUTORISE le clair vers un domaine et ses sous-domaines.
///
/// POURQUOI CE HELPER EST PARTAGÉ. La règle d'adresse (`AdresseMachine`) et le
/// conseil affiché (`ConseilAdresse`) lisent tous deux l'Info.plist du paquet :
/// leurs tests ont donc besoin du MÊME plist — et le paquet de test, lui, n'en a
/// aucun, ce qui est précisément ce qui rend la règle observable dans les deux
/// sens.
///
/// Il est écrit comme le produit le script d'exception
/// (`Scripts/injecter-exception-ats.sh`) : le domaine, sous-domaines inclus.
func plistAvecException(pour domaine: String) -> [String: Any] {
  [
    "NSAppTransportSecurity": [
      "NSExceptionDomains": [
        domaine: [
          "NSExceptionAllowsInsecureHTTPLoads": true,
          "NSIncludesSubdomains": true,
        ]
      ]
    ]
  ]
}
