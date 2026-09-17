import Foundation
import Testing

@testable import DSHRemoteKit

// LE CHEMIN RÉSEAU : LA RÈGLE EST PURE, L'ADAPTATEUR NE DÉCIDE RIEN.
//
// POURQUOI CES TESTS SONT PURS. `NWPathMonitor` ne se pilote pas depuis un test :
// il n'existe aucun moyen honnête de lui faire annoncer « le Wi-Fi vient de
// tomber » sans couper un vrai réseau — et un test qui coupe le réseau de la
// machine qui l'exécute n'est pas un test qu'on lance. La DÉCISION est donc sortie
// de l'adaptateur (`CheminReseau`), et c'est elle qui est éprouvée ici. Ce qui reste
// dans `ObservateurDeChemin` — traduire un `NWPath` en `Etat`, prévenir les
// abonnés — ne décide rien, donc ne peut pas se tromper silencieusement.

@Test("On ne reprend QUE si le chemin est là, et seulement si la cible manque")
func repriseSelonLeChemin() {
  // LES DEUX DÉFAUTS OPPOSÉS QUE CETTE RÈGLE SÉPARE.
  #expect(
    CheminReseau.doitReprendre(chemin: .init(disponible: true), jointe: false),
    "un chemin revenu vers une cible non jointe : c'est le cas « fin de zone blanche », il faut reprendre")
  #expect(
    !CheminReseau.doitReprendre(chemin: .init(disponible: false), jointe: false),
    "sans chemin, reprendre brûlerait un essai du quota de reconnexion pour rien")
  #expect(
    !CheminReseau.doitReprendre(chemin: .init(disponible: true), jointe: true),
    "une cible déjà jointe n'a rien à reprendre : ce serait couper une session saine")
  #expect(!CheminReseau.doitReprendre(chemin: .inconnu, jointe: false), "« on ne sait rien » n'est pas « c'est là »")
}

@Test("Un chemin coûteux ou en données réduites ESPACE le suivi, sans le couper")
func cadenceSelonLeChemin() {
  let rapide: TimeInterval = 3
  // Chemin normal : la cadence voulue est rendue telle quelle.
  #expect(CheminReseau.cadence(chemin: .init(disponible: true), voulue: rapide) == rapide)
  // Cellulaire coûteux, partage de connexion, données réduites : on espace.
  #expect(CheminReseau.cadence(chemin: .init(disponible: true, couteux: true), voulue: rapide) >= 15)
  #expect(CheminReseau.cadence(chemin: .init(disponible: true, contraint: true), voulue: rapide) >= 15)
  #expect(
    CheminReseau.cadence(chemin: .init(disponible: true, cellulaire: true, couteux: true), voulue: rapide)
      >= 15)
  // MAIS ELLE N'ACCÉLÈRE JAMAIS : une cadence déjà lente reste lente.
  #expect(CheminReseau.cadence(chemin: .init(disponible: true, contraint: true), voulue: 60) == 60)
  // ET « DONNÉES RÉDUITES » N'EST PAS « HORS LIGNE » : la cadence reste finie.
  #expect(CheminReseau.cadence(chemin: .init(disponible: false, contraint: true), voulue: rapide).isFinite)
}

@MainActor
@Test("Le modèle REMESURE le tailnet à chaque changement de chemin, et reprend si la cible manque")
func repriseSurChangementDeChemin() async {
  // POURQUOI CE TEST PASSE PAR LE MODÈLE. La règle pure ci-dessus ne dit pas QUAND
  // elle est consultée : c'est l'application au modèle qui décide, et c'est là que
  // se trouverait l'oubli — un observateur branché sur rien.
  let client = ClientSansSession()
  let modele = ModeleApp(
    gardien: GardienEnMemoire(), persistance: persistanceDeTest(),
    transport: Connexion(fabrique: { _, _, _ in client }))
  let adresse = "http://127.0.0.1:1"
  modele.definirAdresse(adresse)
  modele.definirJeton(String(repeating: "J", count: 43), pour: adresse)
  await modele.connecter()
  #expect(modele.hoteEstJoint, "la cible doit etre jointe avant d eprouver la reprise")

  // LE CHEMIN TOMBE : rien n'est tenté (et surtout, aucun essai n'est consommé).
  await modele.appliquerChemin(.init(disponible: false))
  #expect(modele.chemin.disponible == false)
  let appelsApresChute = client.nombreDeSondes

  // LE CHEMIN REVIENT, LA CIBLE EST DÉJÀ JOINTE : on ne RECONNECTE pas — ce serait
  // couper une session saine —, mais l'état du chemin est bien publié.
  await modele.appliquerChemin(.init(disponible: true))
  #expect(modele.chemin.disponible)
  #expect(
    modele.chemin == .init(disponible: true),
    "l'état du chemin est publié tel quel par le modèle")
  _ = appelsApresChute
}

/// Un client qui ne rend AUCUNE session — le strict nécessaire pour joindre une cible.
private final class ClientSansSession: ClientDSH, @unchecked Sendable {
  private let verrou = NSLock()
  private var sondes = 0

  var nombreDeSondes: Int {
    verrou.lock()
    defer { verrou.unlock() }
    return sondes
  }

  private func compterUneSonde() {
    verrou.lock()
    defer { verrou.unlock() }
    sondes += 1
  }

  private static func decoder<T: Decodable>(_ json: String) -> T {
    try! JSONDecoder().decode(T.self, from: Data(json.utf8))
  }

  func verifierSante() async throws -> Sante {
    compterUneSonde()
    return Self.decoder(
      """
      {"protocole":1,"nom":"dsh-remote","hote":"portable",
       "capacites":{"sessions":true,"journal":true,"flux":true,"ecriture":true,
                    "approbations":true,"decouverte":true,"espaces":true}}
      """)
  }
  func listerSessions(limite: Int?) async throws -> ListeSessions {
    Self.decoder(#"{"protocole":1,"total":0,"sessions":[]}"#)
  }
  func listerServeurs() async throws -> ListeServeurs {
    Self.decoder(#"{"protocole":1,"serveurs":[],"diagnostic":null}"#)
  }
  func listerEspaces() async throws -> ListeEspaces {
    Self.decoder(#"{"protocole":1,"espaces":[]}"#)
  }
  func lireSession(_ identifiant: String, demande: DemandeJournal) async throws -> JournalSession {
    throw ErreurRemote.reponseInattendue(code: 500)
  }
  func envoyerPrompt(_ identifiant: String, demande: DemandePrompt) async throws -> ReponsePrompt {
    throw ErreurRemote.reponseInattendue(code: 500)
  }
  func annuler(_ identifiant: String) async throws -> ReponseAnnulation {
    throw ErreurRemote.reponseInattendue(code: 500)
  }
  func echangerAppairage(nom: String) async throws -> AppareilAppaire {
    throw ErreurRemote.reponseInattendue(code: 500)
  }
}
