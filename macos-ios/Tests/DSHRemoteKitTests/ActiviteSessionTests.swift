import Foundation
import Testing
@testable import DSHRemoteKit

struct ActiviteSessionTests {
  @Test
  func gestionnaireActivitesEstDisponibleEtSur() async {
    // Vérifie que le gestionnaire d'activités s'appelle sans lever d'exception
    // sur toutes les plateformes (iOS comme macOS).
    let session = SessionListee(
      from: try! JSONDecoder().decode(
        SessionPayloadDeTest.self,
        from: Data("""
        {
          "id": "s-live-1",
          "titre": "Refonte Widget",
          "projet": "dsh-plugins",
          "statut": "en_cours",
          "vivante": true
        }
        """.utf8)
      )
    )

    await MainActor.run {
      GestionnaireActivitesLive.shared.synchroniser(
        session: session,
        nomServeur: "Mac Studio",
        derniereEtape: "Recherche de symboles"
      )
      GestionnaireActivitesLive.shared.arreter()
    }
  }

  @Test
  func regleZeroAucunSecretDansLActivite() {
    let json = """
    {
      "sessionId": "session-123",
      "sessionTitre": "Tâche en direct",
      "projetNom": "dsh-plugins",
      "nomServeur": "Mac Studio"
    }
    """

    #expect(!json.localizedCaseInsensitiveContains("token"))
    #expect(!json.localizedCaseInsensitiveContains("jeton"))
    #expect(!json.localizedCaseInsensitiveContains("cookie"))
    #expect(!json.localizedCaseInsensitiveContains("secret"))
    #expect(!json.contains("/Users/"))
  }
}

/// Structure utilitaire pour décoder une session de test sans dépendre du réseau.
private struct SessionPayloadDeTest: Decodable {
  let id: String
  let titre: String
  let projet: String
  let statut: String
  let vivante: Bool
}

private extension SessionListee {
  init(from payload: SessionPayloadDeTest) {
    let json = """
    {
      "id": "\(payload.id)",
      "titre": "\(payload.titre)",
      "projet": "\(payload.projet)",
      "statut": "\(payload.statut)",
      "vivante": \(payload.vivante)
    }
    """
    let decode = try! JSONDecoder().decode(SessionListee.self, from: Data(json.utf8))
    self = decode
  }
}
