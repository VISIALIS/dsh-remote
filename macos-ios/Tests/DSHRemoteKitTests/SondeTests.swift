import Foundation
import Testing

@testable import DSHRemoteKit

// CE QUE LA SONDE AFFIRME, ET CE QU'ELLE REFUSE D'AFFIRMER.
//
// Deux règles de cette pièce viennent de mesures, pas d'intuitions :
//
//   - un `401` PROUVE que DSH est là : le service a répondu, seul le jeton est
//     refusé. Compter ce cas comme « pas de DSH » ferait disparaître une machine
//     parfaitement utilisable une fois le bon jeton collé ;
//   - on RETIENT LA CAUSE de chaque échec, parce que c'est elle qui permet à la
//     page de la machine de dire quoi faire (`404` → installer le plugin,
//     `-1004` → publier le port).

/// Un client qui répond ce qu'on lui dit, pour une adresse donnée.
private final class ClientParAdresse: ClientDSH, @unchecked Sendable {
  private let resultat: Result<Sante, Error>
  init(_ resultat: Result<Sante, Error>) { self.resultat = resultat }

  func verifierSante() async throws -> Sante { try resultat.get() }
  func echangerAppairage(nom: String) async throws -> AppareilAppaire {
    // Cette sonde ne mesure que la poignee de main : l'echange n'a rien a y faire,
    // et le refuser franchement vaut mieux que rendre un faux appareil.
    throw ErreurRemote.reponseInattendue(code: 404)
  }
  func listerSessions(limite: Int?) async throws -> ListeSessions {
    throw ErreurRemote.reponseInattendue(code: 500)
  }
  func listerServeurs() async throws -> ListeServeurs {
    throw ErreurRemote.reponseInattendue(code: 500)
  }
  func listerEspaces() async throws -> ListeEspaces {
    throw ErreurRemote.reponseInattendue(code: 500)
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
}

private let servie = ServeurMac(nom: "Un", nomDNS: "un.exemple.ts.net", enLigne: true)
private let muette = ServeurMac(nom: "Deux", nomDNS: "deux.exemple.ts.net", enLigne: true)
private let sansPlugin = ServeurMac(nom: "Trois", nomDNS: "trois.exemple.ts.net", enLigne: true)
private let refusante = ServeurMac(nom: "Quatre", nomDNS: "quatre.exemple.ts.net", enLigne: true)

private func santeValide() -> Sante {
  let json = """
    {"protocole":1,"nom":"dsh-remote","capacites":{"sessions":true,"journal":true,
     "flux":true,"ecriture":true,"approbations":true}}
    """
  return try! JSONDecoder().decode(Sante.self, from: Data(json.utf8))
}

/// Une fabrique qui répond selon l'ADRESSE, et retient les délais ET les porteurs.
private final class FabriqueParAdresse: @unchecked Sendable {
  private let verrou = NSLock()
  private(set) var delais: [TimeInterval] = []
  private(set) var jetons: [String] = []

  func fabrique() -> Connexion.Fabrique {
    { [self] adresse, jeton, delai in
      verrou.lock()
      delais.append(delai)
      jetons.append(jeton)
      verrou.unlock()
      switch adresse {
      case servie.adresse: return ClientParAdresse(.success(santeValide()))
      case refusante.adresse: return ClientParAdresse(.failure(ErreurRemote.jetonRefuse))
      case sansPlugin.adresse:
        return ClientParAdresse(.failure(ErreurRemote.reponseInattendue(code: 404)))
      default:
        return ClientParAdresse(.failure(ErreurRemote.transport("rien n'écoute (-1004)")))
      }
    }
  }
}

@Test("Un 401 compte comme « DSH est là » — un jeton refusé prouve que le service répond")
func jetonRefuseCompteCommeServi() async {
  let espion = FabriqueParAdresse()
  let sonde = Sonde(fabrique: espion.fabrique())

  let verdict = await sonde.interroger([servie, refusante])

  #expect(verdict.serventDsh.contains(servie.id))
  #expect(verdict.serventDsh.contains(refusante.id), "un 401 prouve que DSH est installé")
  #expect(verdict.causes.isEmpty, "aucune cause : ces deux machines servent DSH")
}

@Test("La sonde n'apporte AUCUN porteur aux machines qu'elle interroge")
func sondeSansPorteur() async {
  // POURQUOI CE TEST EXISTE. La sonde interroge les machines d'un tailnet qui ne
  // sont PAS la cible : leur présenter le jeton de la cible faisait voyager un
  // secret vers des hôtes qui n'en ont aucun besoin, et chacun d'eux pouvait le
  // rejouer. Le porteur est donc VIDE — ce que `RemoteClient` traduit par
  // « aucun en-tête Authorization ». Un `401` suffit à la question posée : le
  // service a répondu.
  let espion = FabriqueParAdresse()
  let sonde = Sonde(fabrique: espion.fabrique())

  _ = await sonde.interroger([servie, muette, sansPlugin, refusante])

  #expect(espion.jetons.count == 4)
  // La valeur est calculée AVANT l'assertion : `allSatisfy` est `rethrows`, et la
  // macro `#expect` ne peut pas l'appeler dans une expression qu'elle réécrit.
  let tousVides = espion.jetons.allSatisfy(\.isEmpty)
  #expect(tousVides, "un porteur a ete transmis a une machine qui n'est pas la cible")
}

@Test("Chaque échec laisse sa CAUSE, qui dit quoi réparer")
func causesDesEchecs() async {
  let sonde = Sonde(fabrique: FabriqueParAdresse().fabrique())

  let verdict = await sonde.interroger([sansPlugin, muette])

  #expect(verdict.serventDsh.isEmpty)
  // 404 : la machine répond, mais pas DSH Remote → le plugin n'y est pas chargé.
  #expect(verdict.causes[sansPlugin.id] == .pluginAbsent)
  // -1004 : rien n'écoute sur le port 80 → c'est la publication qui manque.
  #expect(verdict.causes[muette.id] == .rienNEcoute)
}

@Test("La sonde est brève : elle ne fait pas attendre une machine muette")
func delaiCourtEtParallele() async {
  let espion = FabriqueParAdresse()
  let sonde = Sonde(fabrique: espion.fabrique())

  _ = await sonde.interroger([servie, muette, sansPlugin, refusante])

  // TOUTES les machines sont interrogées, et chacune avec le délai court : une
  // machine éteinte ne doit pas retarder les autres, et un Mac muet ne mérite
  // pas qu'on l'attende.
  #expect(espion.delais.count == 4)
  #expect(espion.delais.allSatisfy { $0 == Sonde.delai })
  #expect(Sonde.delai < Connexion.delaiSante, "la sonde est la question la plus brève")
}

@Test("Aucun candidat : la sonde ne ment pas, elle rend un verdict vide")
func aucunCandidat() async {
  let sonde = Sonde(fabrique: FabriqueParAdresse().fabrique())
  let verdict = await sonde.interroger([])
  #expect(verdict.serventDsh.isEmpty)
  #expect(verdict.causes.isEmpty)
}

/// Un client qui ne répond JAMAIS — la configuration réseau réelle
/// (`waitsForConnectivity` + un plancher de 120 s sur `timeoutIntervalForResource`,
/// voir `ConfigurationReseau.pourRequetes`) peut laisser une machine sortie du
/// tailnet dans cet état pendant deux minutes. `Task.sleep` répond à
/// l'annulation, comme `URLSession.data(for:)` le fait pour une vraie requête —
/// c'est ce que la course de `sonderUnCandidat` doit couper.
private struct ClientQuiNeRepondJamais: ClientDSH {
  func verifierSante() async throws -> Sante {
    try await Task.sleep(for: .seconds(999))
    fatalError("annulée avant d'arriver ici")
  }
  func echangerAppairage(nom: String) async throws -> AppareilAppaire {
    throw ErreurRemote.reponseInattendue(code: 500)
  }
  func listerSessions(limite: Int?) async throws -> ListeSessions {
    throw ErreurRemote.reponseInattendue(code: 500)
  }
  func listerServeurs() async throws -> ListeServeurs {
    throw ErreurRemote.reponseInattendue(code: 500)
  }
  func listerEspaces() async throws -> ListeEspaces {
    throw ErreurRemote.reponseInattendue(code: 500)
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
}

private let muetteSansFin = ServeurMac(nom: "Cinq", nomDNS: "cinq.exemple.ts.net", enLigne: true)

@Test(
  "Un candidat qui ne répond jamais ne retient pas le verdict des autres au-delà du délai promis")
func candidatSansFinNeRetientPasLesAutres() async {
  let fabrique: Connexion.Fabrique = { adresse, _, _ in
    adresse == servie.adresse ? ClientParAdresse(.success(santeValide())) : ClientQuiNeRepondJamais()
  }
  let sonde = Sonde(fabrique: fabrique)

  let depart = ContinuousClock.now
  let verdict = await sonde.interroger([servie, muetteSansFin])
  let duree = depart.duration(to: ContinuousClock.now)

  #expect(
    duree < .seconds(Sonde.delai * 2),
    "le candidat muet a retenu le verdict bien au-delà des \(Sonde.delai) s promises")
  #expect(verdict.serventDsh.contains(servie.id), "le candidat qui répond ne doit pas pâtir de l'autre")
  #expect(!verdict.serventDsh.contains(muetteSansFin.id))
  #expect(verdict.causes[muetteSansFin.id] == nil, "le silence n'est pas une cause connue")
}
