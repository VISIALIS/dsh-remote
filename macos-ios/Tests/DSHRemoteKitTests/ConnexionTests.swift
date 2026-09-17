import Foundation
import Testing

@testable import DSHRemoteKit

// LA POLITIQUE DE CONNEXION, ÉPROUVÉE SANS RÉSEAU.
//
// POURQUOI CES TESTS EXISTENT. Deux règles de cette politique ont coûté cher, et
// aucune n'était vérifiable autrement qu'avec un vrai serveur en face :
//
//   - un plafond UNIQUE de huit secondes a refusé une connexion valide après
//     8055 ms, parce que la liste des sessions prend 4 secondes à froid ;
//   - l'ordre des deux questions décide de ce qu'on attend : une machine muette
//     doit échouer en cinq secondes, PAS en trente-cinq.
//
// La fabrique de clients étant injectable, on vérifie le délai DEMANDÉ pour
// chaque appel — ce que le réseau ne permettait pas d'observer.

/// Une réponse de santé VALIDE, décodée comme en production.
///
/// POURQUOI PAR JSON, ET NON PAR UN INITIALISEUR. `Sante` est un modèle de
/// décodage : il n'a pas d'initialiseur public, et lui en ajouter un « pour les
/// tests » ouvrirait une porte que personne ne veut dans le code livré. Décoder
/// une vraie charge utile éprouve AUSSI la forme attendue.
private func santeValide() -> Sante {
  let json = """
    {"protocole":1,"nom":"dsh-remote","hote":"portable",
     "capacites":{"sessions":true,"journal":true,"flux":true,"ecriture":true,
                  "approbations":true,"decouverte":true,"espaces":true}}
    """
  return try! JSONDecoder().decode(Sante.self, from: Data(json.utf8))
}

/// Un client factice : il rend ce qu'on lui dit de rendre, et retient les appels.
private final class ClientFactice: ClientDSH, @unchecked Sendable {
  private let verrou = NSLock()
  private(set) var appels: [String] = []

  var sante: Result<Sante, Error>
  var sessions: Result<ListeSessions, Error>
  var serveurs: Result<ListeServeurs, Error>

  init(
    sante: Result<Sante, Error> = .success(santeValide()),
    sessions: Result<ListeSessions, Error> = .success(
      ListeSessions(protocole: 1, racine: nil, total: 117, sessions: [], erreur: nil)),
    serveurs: Result<ListeServeurs, Error> = .success(
      ListeServeurs(protocole: 1, serveurs: [], diagnostic: nil))
  ) {
    self.sante = sante
    self.sessions = sessions
    self.serveurs = serveurs
  }

  private func noter(_ nom: String) {
    verrou.lock()
    defer { verrou.unlock() }
    appels.append(nom)
  }

  func verifierSante() async throws -> Sante {
    noter("sante")
    return try sante.get()
  }

  func listerSessions(limite: Int?) async throws -> ListeSessions {
    noter("sessions")
    return try sessions.get()
  }

  func listerServeurs() async throws -> ListeServeurs {
    noter("serveurs")
    return try serveurs.get()
  }

  func listerEspaces() async throws -> ListeEspaces {
    noter("espaces")
    let json = #"{"protocole":1,"espaces":[]}"#
    return try! JSONDecoder().decode(ListeEspaces.self, from: Data(json.utf8))
  }

  func lireSession(_ identifiant: String, demande: DemandeJournal) async throws -> JournalSession {
    noter("lireSession")
    throw ErreurRemote.reponseInattendue(code: 500)
  }

  func envoyerPrompt(_ identifiant: String, demande: DemandePrompt) async throws -> ReponsePrompt {
    noter("prompt")
    throw ErreurRemote.reponseInattendue(code: 500)
  }

  func annuler(_ identifiant: String) async throws -> ReponseAnnulation {
    noter("annuler")
    throw ErreurRemote.reponseInattendue(code: 500)
  }
  func echangerAppairage(nom: String) async throws -> AppareilAppaire {
    noter("echanger:" + nom)
    throw ErreurRemote.reponseInattendue(code: 500)
  }
}

/// Une fabrique qui retient le délai demandé pour chaque client, et le porteur.
private final class FabriqueEspionne: @unchecked Sendable {
  private let verrou = NSLock()
  private(set) var delais: [TimeInterval] = []
  private(set) var jetons: [String] = []
  let client: ClientFactice

  init(client: ClientFactice) { self.client = client }

  func fabrique() -> Connexion.Fabrique {
    { [self] _, jeton, delai in
      verrou.lock()
      delais.append(delai)
      jetons.append(jeton)
      verrou.unlock()
      return client
    }
  }
}

@Test("La question brève a un délai COURT, la lecture lourde un délai LONG")
func deuxDelaisDeuxQuestions() async throws {
  let client = ClientFactice()
  let espion = FabriqueEspionne(client: client)
  let connexion = Connexion(fabrique: espion.fabrique())

  let jonction = try await connexion.joindre(adresse: "http://portable.exemple.ts.net", jeton: "x")

  // C'est LA règle qui a coûté une fausse panne : un plafond unique refusait une
  // connexion valide parce que la liste dépasse le délai de la question courte.
  #expect(espion.delais == [Connexion.delaiSante, Connexion.delaiListe])
  #expect(Connexion.delaiListe > Connexion.delaiSante, "la lecture lourde doit être plus patiente")
  // Et le nombre annoncé est celui du SERVEUR (117), pas celui des sessions
  // rendues (0 dans cette réponse) : c'est ce que le test d'adresse affiche.
  #expect(jonction.reponses == 117)
}

@Test("Une machine muette échoue SANS qu'on lui demande sa liste")
func machineMuetteEchoueVite() async {
  let client = ClientFactice(sante: .failure(ErreurRemote.transport("rien n'écoute (-1004)")))
  let espion = FabriqueEspionne(client: client)
  let connexion = Connexion(fabrique: espion.fabrique())

  await #expect(throws: (any Error).self) {
    try await connexion.joindre(adresse: "http://portable.exemple.ts.net", jeton: "x")
  }

  // L'ORDRE est la règle : on ne va pas demander 200 sessions à une machine dont
  // on vient d'apprendre qu'elle ne répond pas. Inverser les deux ferait attendre
  // trente secondes pour apprendre qu'il n'y a personne.
  #expect(client.appels == ["sante"])
  #expect(espion.delais == [Connexion.delaiSante], "un seul client doit avoir été construit")
}

@Test("L'erreur du serveur remonte TELLE QUELLE, sans être réinterprétée")
func erreurRemonteeTelleQuelle() async {
  // Un 404 sur la route de santé : c'est « la machine répond, mais pas DSH
  // Remote ». La classification vit dans `ErreurRemote.causeSansDsh`, pas ici —
  // la politique transporte, elle n'interprète pas.
  let client = ClientFactice(sante: .failure(ErreurRemote.reponseInattendue(code: 404)))
  let connexion = Connexion(fabrique: FabriqueEspionne(client: client).fabrique())

  do {
    _ = try await connexion.joindre(adresse: "http://portable.exemple.ts.net", jeton: "x")
    Issue.record("une erreur était attendue")
  } catch let erreur as ErreurRemote {
    #expect(erreur.causeSansDsh == .pluginAbsent, "404 veut dire « le plugin n'est pas là »")
  } catch {
    Issue.record("l'erreur doit rester typée : \(error)")
  }
}

@Test("Les routes de l'hôte ont leur propre délai, plus long que son propre plafond")
func delaiDeLhote() async throws {
  let client = ClientFactice()
  let espion = FabriqueEspionne(client: client)
  let connexion = Connexion(fabrique: espion.fabrique())

  _ = try await connexion.serveursDeLhote(adresse: "http://portable.exemple.ts.net", jeton: "x")

  // Chez lui, la route borne son appel à `tailscale status` à huit secondes :
  // couper à huit serait une course perdue d'avance les jours où le CLI est lent.
  #expect(espion.delais == [Connexion.delaiHote])
  #expect(Connexion.delaiHote > 8, "le client doit laisser à l'hôte plus que ses huit secondes")
  #expect(client.appels == ["serveurs"])
}

@Test("Deux appels à l'hôte RÉUTILISENT le client : une session, pas deux")
func leClientDeLhoteEstReutilise() async throws {
  // POURQUOI CETTE RÈGLE EXISTE. Chaque client porte SA `URLSession`, donc son
  // pool de connexions. La boucle de synchronisation demande `/v1/serveurs` ET
  // `/v1/espaces` toutes les quinze secondes : fabriquer un client par appel
  // refaisait deux handshakes TCP par cycle, à côté d'une session de trois
  // secondes déjà chaude.
  let client = ClientFactice()
  let espion = FabriqueEspionne(client: client)
  let connexion = Connexion(fabrique: espion.fabrique())
  let adresse = "http://portable.exemple.ts.net"

  _ = try await connexion.serveursDeLhote(adresse: adresse, jeton: "x")
  _ = try await connexion.espacesDeLhote(adresse: adresse, jeton: "x")
  _ = try await connexion.serveursDeLhote(adresse: adresse, jeton: "x")

  #expect(espion.delais == [Connexion.delaiHote], "un seul client pour les trois appels")
  #expect(client.appels == ["serveurs", "espaces", "serveurs"])
}

@Test("Le registre de clients ne confond PAS deux machines")
func leRegistreDistingueLesAdresses() async throws {
  // Un client vise UNE machine. Réutiliser celui d'une autre serait le défaut le
  // plus coûteux de cette famille : l'écran afficherait les sessions d'un serveur
  // sous le nom d'un autre — le même que la « génération » a corrigé ailleurs.
  let client = ClientFactice()
  let espion = FabriqueEspionne(client: client)
  let connexion = Connexion(fabrique: espion.fabrique())

  _ = try await connexion.serveursDeLhote(adresse: "http://portable.exemple.ts.net", jeton: "x")
  _ = try await connexion.serveursDeLhote(adresse: "http://bureau.exemple.ts.net", jeton: "x")

  #expect(espion.delais == [Connexion.delaiHote, Connexion.delaiHote], "une fabrication par machine")
}

@Test("Un jeton RENOUVELÉ refait un client, même adresse — sinon 401 jusqu'au redémarrage")
func leRegistreDistingueLesJetons() async throws {
  // LE DÉFAUT QUE CE TEST FIXE, ET IL ÉTAIT SILENCIEUX. La clé du registre ne
  // portait que `(adresse, délai)`, avec ce raisonnement écrit dans le code :
  // « un jeton change en se ré-appairant, et cela passe par un changement de
  // cible ». C'est faux pour le cas le plus courant — on se ré-appaire sur la
  // MÊME machine (jeton révoqué, réinstallation, second scan du même QR).
  // L'adresse ne bouge pas, le client gardé rendait donc l'ANCIEN porteur :
  // `401` sur toutes les routes, sans qu'aucun écran ne dise pourquoi, jusqu'à
  // éviction du registre (trois entrées) ou redémarrage de l'application.
  let client = ClientFactice()
  let espion = FabriqueEspionne(client: client)
  let connexion = Connexion(fabrique: espion.fabrique())
  let adresse = "http://portable.exemple.ts.net"

  _ = try await connexion.serveursDeLhote(adresse: adresse, jeton: "jeton-initial")
  _ = try await connexion.serveursDeLhote(adresse: adresse, jeton: "jeton-initial")
  #expect(espion.jetons == ["jeton-initial"], "le MÊME jeton doit réutiliser le client")

  _ = try await connexion.serveursDeLhote(adresse: adresse, jeton: "jeton-renouvele")
  #expect(
    espion.jetons == ["jeton-initial", "jeton-renouvele"],
    "un jeton renouvelé doit FABRIQUER un client neuf, pas rendre l'ancien")
}
