import Foundation
import Testing

@testable import DSHRemoteKit

// LA LISTE DES SESSIONS, ÉPROUVÉE SUR LE FIL.
//
// POURQUOI CES TESTS EXISTENT. Le suivi relit la liste toutes les trois secondes.
// Mesuré sur l'installation du propriétaire : 172 sessions, ~685 octets chacune,
// donc **~115 Kio par appel** — vingt fois par minute, pour un contenu qui ne
// bouge presque jamais. Le client envoie désormais `If-None-Match`, et l'hôte
// répond `304` sans corps.
//
// CE QU'UN TEST DE MODÈLE N'AURAIT PAS VU : ces trois propriétés vivent dans la
// REQUÊTE qui part. Un `ClientDSH` bouchonné à la main dirait seulement ce que le
// client fait de la réponse ; il ne dirait pas si l'en-tête conditionnel est
// réellement posé, ni si le corps d'un `304` est bien vide. Ici, un protocole
// d'URL bouchonné regarde ce qui sort et décide de ce qui rentre.
//
// ET LA PROPRIÉTÉ QUI COMPTE VRAIMENT : après un `304`, l'appelant reçoit la
// MÊME liste que celle qu'il avait déjà. Un `304` mal géré rendrait une liste
// vide — c'est-à-dire « aucune session » à l'écran, ou pire, un écran vidé.

/// LE PROTOCOLE BOUCHONNÉ : il répond ce qu'on lui dit, et RETIENT ce qui part.
///
/// POURQUOI UN VERROU. `URLProtocol` est appelé sur un fil de `URLSession`, et le
/// test lit le journal depuis le sien : sans verrou, le journal serait lu pendant
/// qu'il s'écrit. Le verrou protège les DEUX, et l'état partagé vit dans une
/// instance — pas dans une variable statique, qui serait un état global partagé
/// entre tests.
private final class URLProtocolEspion: URLProtocol, @unchecked Sendable {
  /// Ce que le serveur simulé fait d'une requête : un statut, des en-têtes, un corps.
  struct Reponse {
    var statut: Int
    var entetes: [String: String]
    var corps: Data
  }

  private static let verrou = NSLock()
  private nonisolated(unsafe) static var _requetes: [URLRequest] = []
  private nonisolated(unsafe) static var _reponses: [Reponse] = []

  static func installer(_ reponses: [Reponse]) {
    verrou.lock()
    defer { verrou.unlock() }
    _requetes = []
    _reponses = reponses
  }

  static var requetes: [URLRequest] {
    verrou.lock()
    defer { verrou.unlock() }
    return _requetes
  }

  private static func reponseSuivante() -> Reponse {
    verrou.lock()
    defer { verrou.unlock() }
    // La dernière reponse se repete : un test qui interroge trois fois n'a pas a
    // decrire trois fois la meme chose.
    return _reponses.count > 1 ? _reponses.removeFirst() : (_reponses.first ?? Reponse(statut: 500, entetes: [:], corps: Data()))
  }

  private static func noter(_ requete: URLRequest) {
    verrou.lock()
    defer { verrou.unlock() }
    _requetes.append(requete)
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  override func startLoading() {
    URLProtocolEspion.noter(request)
    let simulee = URLProtocolEspion.reponseSuivante()
    let entetes = ["Content-Type": "application/json"] .merging(simulee.entetes) { _, nouvelle in nouvelle }
    guard
      let reponse = HTTPURLResponse(
        url: request.url ?? URL(string: "http://exemple.test")!, statusCode: simulee.statut,
        httpVersion: "HTTP/1.1", headerFields: entetes)
    else {
      client?.urlProtocol(self, didFailWithError: ErreurRemote.transport("réponse simulée impossible"))
      return
    }
    client?.urlProtocol(self, didReceive: reponse, cacheStoragePolicy: .notAllowed)
    if !simulee.corps.isEmpty { client?.urlProtocol(self, didLoad: simulee.corps) }
    client?.urlProtocolDidFinishLoading(self)
  }
}

private let corpsListe = Data(
  #"{"protocole":1,"racine":"/tmp/sessions","total":2,"sessions":[{"projet":"--tmp-essai--","octets":1024,"modifieLe":1700000001000,"vivante":false,"statut":null,"attendReponse":false,"id":"session-aaa","titre":"Premiere","dernierSeq":4,"nbEnregistrements":5},{"projet":"--tmp-essai--","octets":2048,"modifieLe":1700000002000,"vivante":true,"statut":"en_cours","attendReponse":false,"id":"session-bbb","titre":"Seconde","dernierSeq":9,"nbEnregistrements":10}]}"#
    .utf8)

private let corpsListeModifiee = Data(
  #"{"protocole":1,"racine":"/tmp/sessions","total":2,"sessions":[{"projet":"--tmp-essai--","octets":1024,"modifieLe":1700000001000,"vivante":false,"statut":null,"attendReponse":false,"id":"session-aaa","titre":"Premiere","dernierSeq":4,"nbEnregistrements":5},{"projet":"--tmp-essai--","octets":4096,"modifieLe":1700000003000,"vivante":true,"statut":"inactif","attendReponse":true,"id":"session-bbb","titre":"Seconde","dernierSeq":31,"nbEnregistrements":32}]}"#
    .utf8)

/// Un client dont la session parle au protocole bouchonné.
private func clientEspion() throws -> RemoteClient {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [URLProtocolEspion.self]
  return try RemoteClient(
    adresse: "http://mac-mini-essai.exemple.test", jeton: "JETONFICTIF-0000000000000000000000000000000000",
    delai: 5, configuration: configuration)
}

private func reponse(statut: Int, etag: String?, corps: Data) -> URLProtocolEspion.Reponse {
  URLProtocolEspion.Reponse(statut: statut, entetes: etag.map { ["ETag": $0] } ?? [:], corps: corps)
}

/// LA SUITE EST SÉRIALISÉE, ET CE N'EST PAS UN DÉTAIL DE CONFIGURATION.
///
/// Le protocole bouchonné est un ÉTAT PARTAGÉ : la file des réponses simulées
/// appartient au processus, pas à un test. Swift Testing exécute les tests d'un
/// même fichier EN PARALLÈLE par défaut, et la première tentative de ces cinq
/// tests l'a montré : chaque test consommait la file de ses voisins, si bien
/// qu'un `304` attendu arrivait dans un test qui ne l'avait pas demandé. Les
/// mesures étaient fausses, pas le code.
///
/// `@Suite(.serialized)` rend la file privée à chaque test, sans rien changer à
/// ce qui est éprouvé.
@Suite(.serialized)
struct ListeConditionnelleTests {
  @Test("la première lecture ne porte AUCUN en-tête conditionnel, et retient l'empreinte")
  func premiereLectureSansEnTeteConditionnel() async throws {
    URLProtocolEspion.installer([reponse(statut: 200, etag: "\"v1\"", corps: corpsListe)])
    let client = try clientEspion()

    let liste = try await client.listerSessions(limite: 200)

    #expect(liste.sessions.count == 2)
    #expect(liste.sessions.first?.id == "session-aaa")
    let requetes = URLProtocolEspion.requetes
    #expect(requetes.count == 1)
    // Sans copie locale, il n'y a rien à comparer : envoyer un `If-None-Match`
    // inventé ferait répondre `304` sur une liste que le client n'a pas.
    #expect(requetes.first?.value(forHTTPHeaderField: "If-None-Match") == nil)
    #expect(requetes.first?.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
  }

  @Test("un 304 rend la liste DÉJÀ reçue, sans rien redécoder")
  func le304RendLaCopie() async throws {
    URLProtocolEspion.installer([
      reponse(statut: 200, etag: "\"v1\"", corps: corpsListe),
      reponse(statut: 304, etag: "\"v1\"", corps: Data()),
    ])
    let client = try clientEspion()

    let premiere = try await client.listerSessions(limite: 200)
    let seconde = try await client.listerSessions(limite: 200)

    // LA PROPRIÉTÉ QUI COMPTE : ni liste vide, ni erreur — la même liste.
    #expect(seconde.sessions.map(\.id) == premiere.sessions.map(\.id))
    #expect(seconde.sessions.count == 2)

    let requetes = URLProtocolEspion.requetes
    #expect(requetes.count == 2, "le second appel doit bien avoir été émis, avec son en-tête")
    #expect(requetes[1].value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
    // Un `304` n'est pas une panne : il ne doit pas remonter comme une erreur.
    let inchangees = await client.sessionsInchangees
    #expect(inchangees == 1)
  }

  @Test("une empreinte qui change rend la liste NEUVE, et la nouvelle empreinte est retenue")
  func uneEmpreinteQuiChangeRendLaListeNeuve() async throws {
    URLProtocolEspion.installer([
      reponse(statut: 200, etag: "\"v1\"", corps: corpsListe),
      reponse(statut: 200, etag: "\"v2\"", corps: corpsListeModifiee),
      reponse(statut: 304, etag: "\"v2\"", corps: Data()),
    ])
    let client = try clientEspion()

    _ = try await client.listerSessions(limite: 200)
    let deuxieme = try await client.listerSessions(limite: 200)
    let troisieme = try await client.listerSessions(limite: 200)

    #expect(deuxieme.sessions.last?.statut == "inactif")
    #expect(deuxieme.sessions.last?.attendReponse == true)
    // LE PIÈGE DE CETTE OPTIMISATION, ÉPROUVÉ : après un `200` qui porte une
    // NOUVELLE empreinte, c'est la nouvelle qui doit partir. Garder l'ancienne
    // ferait répondre `304` à côté d'une liste périmée — et l'écran ne verrait plus
    // jamais aucun changement.
    let requetes = URLProtocolEspion.requetes
    #expect(requetes[1].value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
    #expect(requetes[2].value(forHTTPHeaderField: "If-None-Match") == "\"v2\"")
    #expect(troisieme.sessions.last?.resume.dernierSeq == 31)
    let inchangees = await client.sessionsInchangees
    #expect(inchangees == 1)
  }

  @Test("un hôte sans ETag reste servi : aucune empreinte n'est inventée")
  func hoteSansEtag() async throws {
    // Un plugin PLUS ANCIEN ne pose pas d'empreinte. Le client doit continuer de
    // recevoir sa liste entière, et ne pas conserver une copie que plus rien ne
    // valide — sinon il enverrait un `If-None-Match` que l'hôte ignorerait, et
    // croirait ensuite à une économie qui n'existe pas.
    URLProtocolEspion.installer([
      reponse(statut: 200, etag: nil, corps: corpsListe),
      reponse(statut: 200, etag: nil, corps: corpsListeModifiee),
    ])
    let client = try clientEspion()

    _ = try await client.listerSessions(limite: 200)
    let seconde = try await client.listerSessions(limite: 200)

    #expect(seconde.sessions.last?.resume.dernierSeq == 31, "la seconde reponse doit etre servie telle quelle")
    let requetes = URLProtocolEspion.requetes
    #expect(requetes.count == 2)
    #expect(requetes[1].value(forHTTPHeaderField: "If-None-Match") == nil)
    let inchangees = await client.sessionsInchangees
    #expect(inchangees == 0)
  }

  @Test("un 304 sans copie locale est DIT, il ne devient pas une liste vide")
  func un304SansCopieEstDit() async throws {
    // Ce cas ne devrait jamais arriver — c'est le client qui envoie l'empreinte.
    // S'il arrivait (mémoire perdue, réponse d'un intermédiaire), rendre une liste
    // vide se lirait « aucune session » : une panne silencieuse. On la nomme.
    URLProtocolEspion.installer([reponse(statut: 304, etag: "\"v1\"", corps: Data())])
    let client = try clientEspion()

    await #expect(throws: ErreurRemote.self) {
      _ = try await client.listerSessions(limite: 200)
    }
  }
}
