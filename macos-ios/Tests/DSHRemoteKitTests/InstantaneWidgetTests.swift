import Foundation
import Testing
@testable import DSHRemoteKit

struct InstantaneWidgetTests {
  @Test
  func allerRetourCodable() throws {
    let source = InstantaneWidget(
      dateMiseAJour: Date(timeIntervalSince1970: 1727125000),
      nomServeur: "Mac Studio",
      adresseServeur: "100.64.0.1",
      estConnecte: true,
      nombreSessionsActives: 4,
      nombreSessionsAuTravail: 2,
      derniereSession: SommaireSessionWidget(
        identifiant: "sess-42",
        titre: "Écriture de code",
        espaceNom: "projet-x",
        etat: "en_cours",
        derniereEtape: "Lecture de fichier",
        dateDerniereActivite: Date(timeIntervalSince1970: 1727125000)
      )
    )

    let encodeur = JSONEncoder()
    let decodeur = JSONDecoder()

    let donnees = try encodeur.encode(source)
    let relu = try decodeur.decode(InstantaneWidget.self, from: donnees)

    #expect(relu == source)
    #expect(relu.nomServeur == "Mac Studio")
    #expect(relu.adresseServeur == "100.64.0.1")
    #expect(relu.estConnecte == true)
    #expect(relu.nombreSessionsActives == 4)
    #expect(relu.nombreSessionsAuTravail == 2)
    #expect(relu.derniereSession?.identifiant == "sess-42")
    #expect(relu.derniereSession?.urlDeepLink?.absoluteString == "dshremote://session/sess-42")
  }

  @Test
  func persistanceInstantaneIsolee() {
    let nomSuite = "test-widget-\(UUID().uuidString)"
    guard let suite = UserDefaults(suiteName: nomSuite) else {
      #expect(Bool(false), "Impossible de créer la suite UserDefaults de test")
      return
    }
    defer { suite.removePersistentDomain(forName: nomSuite) }

    let persistance = Persistance(defaults: suite, appGroupDefaults: suite, documents: nil)

    #expect(persistance.lireInstantaneWidget() == nil)

    let instantane = InstantaneWidget.apercu
    persistance.memoriserInstantaneWidget(instantane)

    let relu = persistance.lireInstantaneWidget()
    #expect(relu != nil)
    #expect(relu?.nomServeur == instantane.nomServeur)
    #expect(relu?.nombreSessionsActives == instantane.nombreSessionsActives)

    persistance.toutOublier()
    #expect(persistance.lireInstantaneWidget() == nil)
  }

  @Test
  func regleZeroAucunSecretDansLInstantane() throws {
    // RÈGLE #0 : L'instantané ne doit porter aucun secret, aucun jeton, ni chemin local.
    let instantane = InstantaneWidget(
      dateMiseAJour: Date(),
      nomServeur: "MacBook",
      adresseServeur: "mac.local:8080",
      estConnecte: true,
      nombreSessionsActives: 1,
      nombreSessionsAuTravail: 0,
      derniereSession: SommaireSessionWidget(
        identifiant: "s1",
        titre: "Session test",
        espaceNom: "espace",
        etat: "actif"
      )
    )

    let donnees = try JSONEncoder().encode(instantane)
    guard let jsonTexte = String(data: donnees, encoding: .utf8) else {
      #expect(Bool(false), "JSON invalide")
      return
    }

    #expect(!jsonTexte.localizedCaseInsensitiveContains("token"))
    #expect(!jsonTexte.localizedCaseInsensitiveContains("jeton"))
    #expect(!jsonTexte.localizedCaseInsensitiveContains("cookie"))
    #expect(!jsonTexte.localizedCaseInsensitiveContains("secret"))
    #expect(!jsonTexte.contains("/Users/"))
  }
}
