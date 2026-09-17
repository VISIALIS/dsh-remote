import Foundation
import Testing

@testable import DSHRemoteKit

// UN STATUT POUSSÉ PAR LE FLUX : LE DÉCODER, ET NE METTRE À JOUR QUE SA SESSION.
//
// POURQUOI CES TESTS EXISTENT. Les pastilles de la liste n'étaient rafraîchies que
// par la boucle HTTP de trois secondes : un tour qui démarre mettait jusqu'à trois
// secondes à s'allumer, et l'utilisateur regardait un écran qui mentait sur ce qui
// travaillait. L'hôte pousse désormais `agent/status` sur le flux de la session
// concernée (voir `tests/hote.test.js`), et ce message arrive par un chemin
// DIFFÉRENT de la liste : il faut donc prouver qu'il ne touche que ce qu'il décrit.

/// Un client qui publie DEUX sessions, dont une seule travaille.
private final class ClientDeuxSessions: ClientDSH, @unchecked Sendable {
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
    Self.decoder(
      """
      {"protocole":1,"total":2,"sessions":[
        {"projet":"--x--","dossier":"/d","fichier":"/f","octets":1,"modifieLe":1,"vivante":true,
         "id":"session-aaa","creeLe":1,"preset":"standard","profondeurDelegation":0,"attendReponse":false,
         "seme":false,"titre":"A","dernierEvenementLe":1,"dernierSeq":1,
         "nbEnregistrements":1,"tronque":false,"statut":"en_cours"},
        {"projet":"--x--","dossier":"/d","fichier":"/f","octets":1,"modifieLe":1,"vivante":true,
         "id":"session-bbb","creeLe":1,"preset":"standard","profondeurDelegation":0,"attendReponse":false,
         "seme":false,"titre":"B","dernierEvenementLe":1,"dernierSeq":1,
         "nbEnregistrements":1,"tronque":false,"statut":"inactif"}]}
      """)
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

@MainActor
private func modeleADeuxSessions() async -> ModeleApp {
  let client = ClientDeuxSessions()
  let modele = ModeleApp(
    gardien: GardienEnMemoire(), persistance: persistanceDeTest(),
    transport: Connexion(fabrique: { _, _, _ in client }))
  let adresse = "http://127.0.0.1:1"
  modele.definirAdresse(adresse)
  modele.definirJeton(String(repeating: "J", count: 43), pour: adresse)
  await modele.connecter()
  return modele
}

@MainActor
@Test("Un statut poussé ne touche QUE sa session, et seulement si la cible est la bonne")
func statutPousse() async {
  let modele = await modeleADeuxSessions()
  let vu = modele.generationDuDepart()
  #expect(modele.sessions.count == 2, "les deux sessions sont là")

  modele.appliquerStatut("inactif", de: "session-aaa", vu: vu)
  #expect(modele.sessions.first { $0.id == "session-aaa" }?.statut == "inactif")
  #expect(modele.sessions.first { $0.id == "session-bbb" }?.statut == "inactif", "l'autre ne bouge pas")

  // UNE SESSION INCONNUE N'EST PAS CRÉÉE. Le flux parle d'une session qui existe
  // dans la liste ; en inventer une ferait apparaître une ligne fantôme, sans
  // titre ni journal — pire qu'une pastille en retard.
  modele.appliquerStatut("en_cours", de: "session-inconnue", vu: vu)
  #expect(modele.sessions.count == 2)

  // UNE GÉNÉRATION PÉRIMÉE EST REFUSÉE, comme pour toute autre réponse : un statut
  // poussé par une machine qu'on vient de quitter décrit une AUTRE cible.
  modele.appliquerStatut("en_cours", de: "session-aaa", vu: vu + 1)
  #expect(
    modele.sessions.first { $0.id == "session-aaa" }?.statut == "inactif",
    "un statut d'une autre cible ne doit pas s'appliquer")

  // ET LE STATUT SUIT LE BON SENS : le même agent qui repart.
  modele.appliquerStatut("en_cours", de: "session-aaa", vu: vu)
  #expect(modele.sessions.first { $0.id == "session-aaa" }?.statut == "en_cours")
}

@Test("Une session copiée avec un statut garde TOUT le reste")
func copieAvecStatut() throws {
  // POURQUOI CE TEST. `avecStatut` reconstruit la session champ par champ : un
  // champ oublié disparaîtrait silencieusement de la liste à la première pastille
  // allumée — titre, espace de travail, nombre d'évènements, tout.
  let json = """
    {"protocole":1,"total":1,"sessions":[
      {"projet":"--x--","cwdIndicatif":"/x","dossier":"/d","fichier":"/f","octets":123,
       "modifieLe":42,"vivante":true,"id":"session-aaa","creeLe":1,"preset":"standard",
       "profondeurDelegation":0,"attendReponse":true,"seme":false,"titre":"Titre",
       "dernierEvenementLe":7,"dernierSeq":9,"nbEnregistrements":3,"tronque":false,
       "statut":"inactif"}]}
    """.data(using: .utf8)!
  let avant = try JSONDecoder().decode(ListeSessions.self, from: json).sessions[0]
  let apres = avant.avecStatut("en_cours")

  #expect(apres.statut == "en_cours")
  #expect(avant.statut == "inactif", "la copie ne modifie pas l'originale")
  #expect(apres.id == avant.id)
  #expect(apres.titreAffiche == avant.titreAffiche)
  #expect(apres.projet == avant.projet)
  #expect(apres.cwdIndicatif == avant.cwdIndicatif)
  #expect(apres.dossier == avant.dossier)
  #expect(apres.fichier == avant.fichier)
  #expect(apres.octets == avant.octets)
  #expect(apres.modifieLe == avant.modifieLe)
  #expect(apres.vivante == avant.vivante)
  #expect(apres.attendReponse == avant.attendReponse)
  #expect(apres.illisible == avant.illisible)
  #expect(apres.resume.dernierSeq == avant.resume.dernierSeq)
}
