import Foundation
import Testing

@testable import DSHRemoteKit

// LE CYCLE DE VIE DE L'APPLICATION, ET LA CADENCE DU SUIVI.
//
// POURQUOI CES TESTS EXISTENT. Deux règles sont nées de mesures sur iPhone, et
// aucune des deux ne se lit dans une capture d'écran :
//
//   1. **la cadence de 3 s était FIXE.** C'est la bonne réponse à « qu'est-ce qui
//      tourne ? » — ce n'est pas une raison pour la poser en boucle quand rien ne
//      tourne et que personne ne regarde. Chaque tour réveille la radio : c'est le
//      poste de dépense le plus visible de l'application sur un téléphone ;
//   2. **rien ne s'arrêtait en arrière-plan.** Trois boucles et une socket
//      continuaient jusqu'à ce qu'iOS gèle le processus, et la temporisation de
//      reconnexion reprenait au réveil avec un quota entamé — le cas « l'app a
//      dormi dix minutes et le flux affiche un échec ».
//
// La cadence est une FONCTION PURE (`ModeleApp.cadence`), donc éprouvée sans
// réseau. Le cycle de vie, lui, se prouve sur le modèle complet, avec un client
// factice : ce qui compte est ce qui PART sur le réseau, et ce qui ne part plus.

// ── Les pièces factices ───────────────────────────────────────────────────────

/// Un client qui compte ses appels, et sert une session « en cours ».
///
/// La session est `en_cours` À DESSEIN : c'est ce qui met la boucle en cadence
/// RAPIDE (3 s). Sans cela, le test « rien ne part en arrière-plan » attendrait
/// quinze secondes pour ne rien voir — et ne prouverait donc rien.
private final class ClientEspion: ClientDSH, @unchecked Sendable {
  private let verrou = NSLock()
  private var listages = 0

  /// Le verrou vit dans une méthode SYNCHRONE : `NSLock.lock()` est interdit dans
  /// un contexte asynchrone (Swift 6), et c'est exactement ce que les appels
  /// ci-dessous sont. Même forme que le compteur de `ConnexionTests`.
  private func compterUnListage() {
    verrou.lock()
    defer { verrou.unlock() }
    listages += 1
  }

  var nombreDeListages: Int {
    verrou.lock()
    defer { verrou.unlock() }
    return listages
  }

  private static func decoder<T: Decodable>(_ json: String) -> T {
    try! JSONDecoder().decode(T.self, from: Data(json.utf8))
  }

  func verifierSante() async throws -> Sante {
    Self.decoder(
      """
      {"protocole":1,"nom":"dsh-remote","hote":"portable",
       "capacites":{"sessions":true,"journal":true,"flux":true,"ecriture":true,
                    "approbations":true,"decouverte":true,"espaces":true}}
      """)
  }

  func listerSessions(limite: Int?) async throws -> ListeSessions {
    compterUnListage()
    return Self.decoder(
      """
      {"protocole":1,"total":1,"sessions":[
        {"projet":"--x--","dossier":"/d","fichier":"/f","octets":1,"modifieLe":1,"vivante":true,
         "id":"session-aaa","creeLe":1,"preset":"standard","profondeurDelegation":0,"attendReponse":false,
         "seme":false,"titre":"Essai","dernierEvenementLe":1,"dernierSeq":1,
         "nbEnregistrements":1,"tronque":false,"statut":"en_cours"}]}
      """)
  }

  func lireSession(_ identifiant: String, demande: DemandeJournal) async throws -> JournalSession {
    Self.decoder(
      """
      {"protocole":1,"depuis":0,"limite":400,"total":1,"tronque":false,
       "session":{"id":"session-aaa","titre":"Essai","dernierSeq":1,"creeLe":1,"preset":"standard",
                  "profondeurDelegation":0,"seme":false,"nbEnregistrements":1,"tronque":false},
       "enregistrements":[{"type":"assistant/message","seq":1,"time":1,"data":{"texte":"bonjour"}}]}
      """)
  }

  func listerServeurs() async throws -> ListeServeurs {
    Self.decoder(#"{"protocole":1,"serveurs":[],"diagnostic":null}"#)
  }

  func listerEspaces() async throws -> ListeEspaces {
    Self.decoder(#"{"protocole":1,"espaces":[]}"#)
  }

  func envoyerPrompt(_ identifiant: String, demande: DemandePrompt) async throws -> ReponsePrompt {
    throw ErreurRemote.reponseInattendue(code: 500)
  }
  func annuler(_ identifiant: String) async throws -> ReponseAnnulation {
    throw ErreurRemote.reponseInattendue(code: 500)
  }
  func echangerAppairage(nom: String) async throws -> AppareilAppaire {
    // Ce faux client n'échange aucun code : l'appairage a ses propres tests, et un
    // faux appareil rendu ici ferait croire à un jeton qui n'existe pas.
    throw ErreurRemote.reponseInattendue(code: 500)
  }
}

// ── La cadence, en pur ───────────────────────────────────────────────────────

private func session(_ identifiant: String, statut: String?, attendReponse: Bool? = false) -> SessionListee {
  let statutJSON = statut.map { "\"\($0)\"" } ?? "null"
  let json = """
    {"protocole":1,"total":1,"sessions":[
      {"projet":"--x--","dossier":"/d","fichier":"/f","octets":1,"modifieLe":1,"vivante":true,
       "id":"\(identifiant)","creeLe":1,"preset":"standard","profondeurDelegation":0,
       "attendReponse":\(attendReponse ?? false),"seme":false,"titre":"T","dernierEvenementLe":1,
       "dernierSeq":1,"nbEnregistrements":1,"tronque":false,"statut":\(statutJSON)}]}
    """.data(using: .utf8)!
  return try! JSONDecoder().decode(ListeSessions.self, from: json).sessions[0]
}

@MainActor
@Test("La cadence est RAPIDE quand ça bouge, LENTE quand rien ne tourne")
func cadenceAdaptative() {
  // RIEN NE TOURNE, PERSONNE NE REGARDE : c'est le cas qui doit cesser de réveiller
  // la radio toutes les trois secondes.
  #expect(ModeleApp.cadence(sessions: [], enDirect: false) == ModeleApp.cadenceDeRepos)
  #expect(
    ModeleApp.cadence(sessions: [session("a", statut: "inactif")], enDirect: false)
      == ModeleApp.cadenceDeRepos)

  // UNE SESSION TRAVAILLE : la pastille doit suivre, donc cadence rapide.
  #expect(
    ModeleApp.cadence(sessions: [session("a", statut: "en_cours")], enDirect: false)
      == ModeleApp.cadenceRapide)
  // UNE SESSION ATTEND UNE DÉCISION : c'est l'information la plus actionnable de
  // la liste, et elle mérite la même cadence.
  #expect(
    ModeleApp.cadence(sessions: [session("a", statut: "inactif", attendReponse: true)], enDirect: false)
      == ModeleApp.cadenceRapide)
  // UN FLUX OUVERT COMPTE AUTANT QUE L'ÉTAT : c'est le cas « l'utilisateur vient
  // d'envoyer un prompt », où la liste doit passer à « en cours » tout de suite.
  #expect(ModeleApp.cadence(sessions: [], enDirect: true) == ModeleApp.cadenceRapide)

  // LE REPOS RESTE UNE CADENCE DE TABLEAU DE BORD : un tour lancé depuis un AUTRE
  // appareil doit apparaître en un quart de minute, pas jamais.
  #expect(ModeleApp.cadenceDeRepos <= 15, "au-delà, la liste devient une photo ancienne")
  #expect(ModeleApp.cadenceRapide < ModeleApp.cadenceDeRepos)
}

// ── Le cycle de vie, sur le modèle complet ───────────────────────────────────

@MainActor
private func modeleEspionne(_ client: ClientEspion) async -> ModeleApp {
  // LE MODÈLE EST CELUI DE PRODUCTION, avec un client factice : c'est la seule
  // façon de vérifier ce qui PART sur le réseau. L'adresse vise la boucle locale
  // sur un port fermé — c'est ce qui rend l'échec du flux immédiat et observable
  // (mesuré dans `FluxRepriseTests` : quelques millisecondes, pas une attente).
  let modele = ModeleApp(
    gardien: GardienEnMemoire(),
    persistance: persistanceDeTest(),
    transport: Connexion(fabrique: { _, _, _ in client }))
  let adresse = "http://127.0.0.1:1"
  modele.definirAdresse(adresse)
  modele.definirJeton(String(repeating: "J", count: 36) + String(repeating: "0", count: 7), pour: adresse)
  await modele.connecter()
  return modele
}

@MainActor
@Test("L'arrière-plan ARRÊTE la boucle rapide, et le retour relit TOUT DE SUITE")
func arrierePlanPuisRetour() async throws {
  let client = ClientEspion()
  let modele = await modeleEspionne(client)

  // LE FLUX EST OUVERT SUR UNE SESSION, comme lorsque l'utilisateur regarde un
  // journal : c'est cet état qui doit être REPRIS au retour, et c'est lui qui
  // donne un quota de reconnexion à remettre à neuf.
  let liste = try await client.listerSessions(limite: nil)
  let suivie = try #require(liste.sessions.first)
  await modele.ouvrir(suivie)
  #expect(modele.journalPour == suivie.id, "le journal est bien celui de cette session")
  #expect(modele.enDirect, "regarder une session ouvre le direct")

  // ON ATTEND QU'UN ESSAI SOIT CONSOMMÉ : le flux vise un port fermé, donc il
  // échoue — c'est ce compteur que le retour au premier plan doit remettre à zéro.
  let limite = Date().addingTimeInterval(8)
  while Date() < limite, (modele.reconnexion?.echecs ?? 0) == 0 {
    try? await Task.sleep(nanoseconds: 50_000_000)
  }
  #expect((modele.reconnexion?.echecs ?? 0) >= 1, "un flux mort doit consommer un essai")

  // 1. L'ARRIÈRE-PLAN ARRÊTE LA BOUCLE.
  await modele.suspendreLeTravailDeFond()
  #expect(modele.enArrierePlan)
  let avant = client.nombreDeListages
  // QUATRE SECONDES POUR UNE CADENCE DE TROIS : c'est la seule preuve honnête que
  // la boucle ne tourne plus. Une attente plus courte passerait même si elle
  // tournait encore, et ne prouverait donc rien.
  try? await Task.sleep(nanoseconds: 4_000_000_000)
  #expect(
    client.nombreDeListages == avant,
    "aucun listage ne doit partir en arrière-plan (attendu \(avant), vu \(client.nombreDeListages))")
  // IDEMPOTENCE : iOS peut annoncer deux fois le même état.
  await modele.suspendreLeTravailDeFond()
  #expect(modele.enArrierePlan)

  // 2. LE RETOUR RELIT IMMÉDIATEMENT, ET REMET LE QUOTA À NEUF.
  await modele.reprendreLeTravailDeFond()
  #expect(!modele.enArrierePlan)
  #expect(
    client.nombreDeListages > avant,
    "le retour au premier plan relit sans attendre le premier tic de la boucle")
  #expect(modele.reconnexion?.echecs == 0, "le sommeil n'est pas une panne : le quota repart à neuf")
  #expect(modele.enDirect, "l'intention de suivi survit à l'arrière-plan")

  modele.arreterFlux()
}
