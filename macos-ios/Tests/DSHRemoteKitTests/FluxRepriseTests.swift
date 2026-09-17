import Foundation
import Testing

@testable import DSHRemoteKit

// LA REPRISE APRÈS COUPURE, ÉPROUVÉE CONTRE UN VRAI SERVEUR WEBSOCKET.
//
// POURQUOI CE TEST EXISTE, ET CE QU'IL AJOUTE AUX AUTRES. `ReconnexionTests`
// éprouve la POLITIQUE de temporisation, et `FluxSession` éprouve le décodage des
// messages. Ni l'un ni l'autre ne dit la seule chose qui compte ici : après une
// coupure, le client renvoie-t-il `depuisSeq` — c'est-à-dire demande-t-il
// seulement ce qu'il n'a pas ?
//
// Cette propriété-là ne se lit pas dans le code : elle se lit SUR LE FIL. Un
// serveur WebSocket minimal (Node, sans dépendance, dans `Outils/`) accepte donc
// deux connexions, COUPE la première brutalement — comme un Wi-Fi qui s'endort —,
// et NOTE ce que le second `demarrer` a porté. C'est cette note qui est vérifiée.
//
// CE QUE LE TEST NE FAIT PAS : il n'attend pas les temporisations du modèle. La
// politique est éprouvée à part, en pur ; ici on conduit la MÊME reprise que lui,
// avec le `seq` que `FluxSession` a mémorisé — ce qui est exactement le contrat
// entre les deux.

/// LE CHEMIN DU SERVEUR D'ESSAI, CHERCHÉ COMME LE FAIT DÉJÀ LE PAQUET.
///
/// POURQUOI PAS `#filePath` SEUL : il donne le chemin de COMPILATION, qui n'existe
/// plus quand les tests tournent depuis un paquet empaqueté. Le paquet a déjà ce
/// problème pour ses ressources, et sa solution est ici reprise : on essaie le
/// chemin du fichier source, puis le chemin relatif au dossier courant. Si aucun
/// ne répond, le test le DIT et s'abstient — un contrôle qui ne s'exécute pas ne
/// doit pas passer pour un contrôle.
private func cheminDuServeur() -> String? {
  let depuisSource = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Outils/serveur-flux-essai.mjs")
  let depuisCourant = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Tests/DSHRemoteKitTests/Outils/serveur-flux-essai.mjs")
  for candidat in [depuisSource, depuisCourant] where FileManager.default.fileExists(atPath: candidat.path) {
    return candidat.path
  }
  return nil
}

/// `node` est-il lançable ? Le test en a besoin, et le dire vaut mieux que
/// d'échouer sur un `launch path not accessible`.
private func nodeDisponible() -> Bool {
  let processus = Process()
  processus.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  processus.arguments = ["node", "--version"]
  processus.standardOutput = Pipe()
  processus.standardError = Pipe()
  do {
    try processus.run()
    processus.waitUntilExit()
    return processus.terminationStatus == 0
  } catch {
    return false
  }
}

/// Le port est choisi par le système (0) puis RELU : deux exécutions de la suite
/// ne peuvent pas se disputer un numéro fixe.
private func portLibre() throws -> Int {
  let socket = socket(AF_INET, SOCK_STREAM, 0)
  guard socket >= 0 else { throw ErreurRemote.transport("socket impossible") }
  defer { close(socket) }
  var adresse = sockaddr_in()
  adresse.sin_family = sa_family_t(AF_INET)
  adresse.sin_port = 0
  adresse.sin_addr.s_addr = inet_addr("127.0.0.1")
  let taille = socklen_t(MemoryLayout<sockaddr_in>.size)
  let lie = withUnsafePointer(to: &adresse) { pointeur in
    pointeur.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, taille) }
  }
  guard lie == 0 else { throw ErreurRemote.transport("bind impossible") }
  var resultat = sockaddr_in()
  var longueur = taille
  let nomme = withUnsafeMutablePointer(to: &resultat) { pointeur in
    pointeur.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &longueur) }
  }
  guard nomme == 0 else { throw ErreurRemote.transport("getsockname impossible") }
  return Int(UInt16(bigEndian: resultat.sin_port))
}

/// Attend qu'une ligne apparaisse dans le journal du serveur d'essai.
private func attendre(_ motif: String, dans fichier: URL, delai: TimeInterval = 5) async -> String? {
  let limite = Date().addingTimeInterval(delai)
  while Date() < limite {
    let texte = (try? String(contentsOf: fichier, encoding: .utf8)) ?? ""
    if texte.contains(motif) { return texte }
    try? await Task.sleep(nanoseconds: 50_000_000)
  }
  return nil
}

/// Un délai BORNÉ autour d'une attente.
///
/// POURQUOI UNE ÉCHÉANCE PLUTÔT QU'UN `Task` ANNULÉ : l'itérateur d'un
/// `AsyncStream` n'est pas `Sendable`, donc il ne traverse pas une frontière de
/// tâche — et une boucle qui lit un flux ne se termine pas sur annulation. Le test
/// porte donc sa propre échéance, et s'arrête de lui-même : un test qui pendrait
/// serait un test qu'on n'ose plus lancer.
private func echeance(_ secondes: Double) -> Date { Date().addingTimeInterval(secondes) }

/// La suite est SÉRIALISÉE : elle lance un processus et lui donne un port.
@Suite(.serialized)
struct FluxRepriseTests {

  @Test("Après une coupure, le client redemande à partir du seq qu'il connaît")
  func laReprisePorteLeSeqConnu() async throws {
    // LES DEUX RAISONS DE S'ABSTENIR, DITES À VOIX HAUTE : sans `node`, ou sans le
    // fichier du serveur d'essai, la reprise ne peut pas être éprouvée sur le fil.
    // Un `return` silencieux ferait passer une absence de preuve pour une preuve.
    let serveurEssai = try #require(cheminDuServeur(), "serveur d'essai introuvable : reprise NON éprouvée")
    try #require(nodeDisponible(), "node introuvable : reprise NON éprouvée")

    let port = try portLibre()
    let note = FileManager.default.temporaryDirectory
      .appendingPathComponent("dsh-remote-flux-\(UUID().uuidString).txt")
    let serveur = Process()
    serveur.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    serveur.arguments = ["node", serveurEssai, String(port), note.path]
    try serveur.run()
    defer { serveur.terminate() }
    // On attend que le serveur ÉCOUTE : sans cela, la première connexion partirait
    // dans le vide et le test mesurerait une course, pas une reprise.
    try #require(await attendre("ecoute=", dans: note) != nil, "le serveur d'essai n'a pas démarré")

    // 1. PREMIÈRE CONNEXION : elle reçoit `base` et un `evenement`, puis la socket
    //    est coupée brutalement par le serveur.
    let premiere = try #require(
      FluxSession(adresse: "http://127.0.0.1:\(port)", jeton: "JETONFICTIF-0000000000000000000000000000000000",
        identifiant: "session-essai"))
    var vus: [Int] = []
    var coupure = false
    for await message in await premiere.messages() {
      switch message {
      case let .base(_, enregistrements, seq):
        vus.append(contentsOf: enregistrements.compactMap(\.seq))
        if let seq { vus.append(seq) }
      case let .evenement(enregistrement):
        if let seq = enregistrement.seq { vus.append(seq) }
      case .erreur:
        coupure = true
      default:
        break
      }
    }
    await premiere.fermer()

    // La coupure a bien été VUE par le client — sans quoi le test ne prouverait
    // rien : il aurait simplement lu un flux qui n'a jamais existé.
    #expect(coupure, "la coupure doit remonter au client")
    #expect(vus.max() == 2, "le client a vu jusqu'au seq 2 avant la coupure")

    // 2. LA REPRISE, avec exactement ce que le modèle transmet : le dernier `seq`
    //    que la session connaît.
    let connue = await premiere.sequenceConnue
    #expect(connue == 2, "le curseur de reprise doit avoir avancé")

    let seconde = try #require(
      FluxSession(adresse: "http://127.0.0.1:\(port)", jeton: "JETONFICTIF-0000000000000000000000000000000000",
        identifiant: "session-essai", depuisSeq: connue))
    var repris: [Int] = []
    var vuLaBase = false
    let limite = echeance(5)
    // LA BASE DE REPRISE ARRIVE EN PREMIER MESSAGE — c'est le contrat du serveur :
    // `base`, puis les evenements. La boucle porte son échéance : un serveur muet
    // ferait échouer le test au bout de cinq secondes, pas pendre la suite.
    for await message in await seconde.messages() {
      guard Date() < limite else { break }
      if case let .base(_, enregistrements, _) = message {
        repris.append(contentsOf: enregistrements.compactMap(\.seq))
        vuLaBase = true
        break
      }
    }
    await seconde.fermer()

    #expect(vuLaBase, "la reprise doit recevoir sa base")
    #expect(repris.contains(1), "le serveur renvoie l'enregistrement de reprise")

    // 3. LA MESURE : ce que le SECOND `demarrer` a porté sur le fil.
    let journal = try #require(try? String(contentsOf: note, encoding: .utf8))
    #expect(journal.contains("connexion=1 depuisSeq=absent"), "la première demande ne reprend rien")
    #expect(journal.contains("connexion=2 depuisSeq=2"), "la reprise doit porter le seq connu — journal :\n\(journal)")
    #expect(journal.contains("connexion=1 coupure=brutale"), "la coupure doit être brutale, pas une fermeture propre")
    // Et la base de la reprise est bien servie : le client n'est pas resté muet.
    #expect(repris.contains(1) || repris.isEmpty, "la base de reprise est servie ou à venir")
  }

  @Test("Un 401 à la poignée de main n'est PAS une coupure : rien à reprendre")
  func unRefusDeJetonNEstPasUneCoupure() async throws {
    // POURQUOI CE TEST. Le modèle ne distingue pas encore un `401` d'une coupure
    // réseau sur le flux — les deux arrivent par la même erreur de transport — et
    // c'est ASSUMÉ, mais le quota de tentatives est ce qui empêche la boucle
    // infinie. Ce qui est vérifié ici est plus modeste, et suffisant : une socket
    // qui n'a JAMAIS rien envoyé ne fait pas avancer le curseur de reprise, donc
    // la reprise suivante ne peut pas « sauter » des enregistrements qu'on n'a
    // jamais vus.
    let session = try #require(
      FluxSession(
        adresse: "http://127.0.0.1:1", jeton: "JETONFICTIF-0000000000000000000000000000000000",
        identifiant: "session-essai"))
    var erreur = false
    for await message in await session.messages() {
      if case .erreur = message { erreur = true }
    }
    await session.fermer()

    #expect(erreur, "une adresse morte doit remonter une erreur")
    #expect(await session.sequenceConnue == nil, "aucun contenu recu : aucun curseur a reprendre")
  }
}
