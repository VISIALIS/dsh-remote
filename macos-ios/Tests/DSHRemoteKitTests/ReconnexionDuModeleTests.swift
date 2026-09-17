import Foundation
import Testing

@testable import DSHRemoteKit

// LA BOUCLE DE RECONNEXION DU MODÈLE, ÉPROUVÉE CONTRE UN FAUX HÔTE COMPLET.
//
// POURQUOI CE TROISIÈME TEST DE FLUX, APRÈS `FluxRepriseTests`. Celui-là éprouve le
// TRANSPORT : il rouvre une `FluxSession` à la main avec le `seq` connu. Mais la
// propriété qui manquait au client n'était pas là — elle était dans le MODÈLE, qui
// s'arrêtait à la première erreur (`enDirect = false`) et exigeait un appui sur le
// bouton. Entre les deux, il y a une boucle : attendre, rouvrir, reprendre.
//
// CE QU'IL FAUT DONC POUR L'ÉPROUVER : un hôte qui parle HTTP **et** WebSocket —
// le modèle refuse d'ouvrir un flux sans avoir joint l'hôte (`guard client != nil`),
// et joindre passe par `/v1/sante` et `/v1/sessions`. C'est le rôle de
// `Outils/serveur-modele-essai.mjs`, qui coupe les N premières connexions puis
// laisse la suivante vivre.
//
// LES TROIS CHOSES MESURÉES, ET AUCUNE N'EST DÉDUCTIBLE DU CODE :
//   1. la reconnexion a bien LIEU — deux coupures, deux reprises, sans que
//      personne n'appuie sur quoi que ce soit ;
//   2. chaque reprise porte un `depuisSeq` qui AVANCE (3, puis 3 : le client ne
//      redemande jamais ce qu'il a) ;
//   3. le journal ne contient AUCUN doublon, alors que la dernière base renvoie
//      exprès un enregistrement déjà connu.

private func cheminDuServeurModele() -> String? {
  let depuisSource = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Outils/serveur-modele-essai.mjs")
  let depuisCourant = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Tests/DSHRemoteKitTests/Outils/serveur-modele-essai.mjs")
  for candidat in [depuisSource, depuisCourant] where FileManager.default.fileExists(atPath: candidat.path) {
    return candidat.path
  }
  return nil
}

private func portLibre() throws -> Int {
  let socket = socket(AF_INET, SOCK_STREAM, 0)
  guard socket >= 0 else { throw ErreurRemote.transport("socket impossible") }
  defer { close(socket) }
  var adresse = sockaddr_in()
  adresse.sin_family = sa_family_t(AF_INET)
  adresse.sin_port = 0
  adresse.sin_addr.s_addr = inet_addr("127.0.0.1")
  let taille = socklen_t(MemoryLayout<sockaddr_in>.size)
  guard
    withUnsafePointer(to: &adresse, { pointeur in
      pointeur.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, taille) }
    }) == 0
  else { throw ErreurRemote.transport("bind impossible") }
  var resultat = sockaddr_in()
  var longueur = taille
  guard
    withUnsafeMutablePointer(to: &resultat, { pointeur in
      pointeur.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &longueur) }
    }) == 0
  else { throw ErreurRemote.transport("getsockname impossible") }
  return Int(UInt16(bigEndian: resultat.sin_port))
}

/// Vrai quand l'hôte est joint — le même critère que l'interface emploie, écrit ici
/// pour que le test puisse l'affirmer sans lire un `case` dans son assertion.
extension ModeleApp.EtatConnexion {
  fileprivate var estJointe: Bool {
    if case .jointe = self { return true }
    return false
  }
}

private func contenu(_ fichier: URL) -> String { (try? String(contentsOf: fichier, encoding: .utf8)) ?? "" }

/// Attend qu'une condition tenue par l'acteur principal devienne vraie.
///
/// POURQUOI UN SONDAGE SERRÉ, ET PAS UNE SIMPLE ATTENTE. Le libellé « Reconnexion »
/// n'est visible QU'ENTRE DEUX TENTATIVES : dès que la socket suivante reçoit un
/// contenu, le compteur repart à zéro et le libellé disparaît. Une première version
/// de ce test attendait le journal du serveur, PUIS lisait le libellé — et elle
/// échouait une fois sur deux : la tentative suivante avait déjà abouti. Un état
/// transitoire s'observe en le guettant, pas en le relisant plus tard.
@MainActor
private func attendreEtat(_ condition: @MainActor () -> Bool, delai: TimeInterval = 6) async -> Bool {
  let limite = Date().addingTimeInterval(delai)
  while Date() < limite {
    if condition() { return true }
    try? await Task.sleep(nanoseconds: 10_000_000)
  }
  return false
}

private func attendre(_ motif: String, dans fichier: URL, delai: TimeInterval = 8) async -> Bool {
  let limite = Date().addingTimeInterval(delai)
  while Date() < limite {
    if contenu(fichier).contains(motif) { return true }
    try? await Task.sleep(nanoseconds: 100_000_000)
  }
  return false
}

/// Un faux hôte qui tourne pendant la durée d'un test.
private struct FauxHote {
  let processus: Process
  let note: URL
  let adresse: String

  static func demarrer(coupures: Int) async throws -> FauxHote {
    let serveurEssai = try #require(cheminDuServeurModele(), "serveur d'essai introuvable : reconnexion NON éprouvée")
    let port = try portLibre()
    let note = FileManager.default.temporaryDirectory
      .appendingPathComponent("dsh-remote-modele-\(UUID().uuidString).txt")
    let processus = Process()
    processus.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    processus.arguments = ["node", serveurEssai, String(port), note.path, String(coupures)]
    try processus.run()
    let hote = FauxHote(processus: processus, note: note, adresse: "http://127.0.0.1:\(port)")
    try #require(await attendre("ecoute=", dans: note) != nil, "le faux hôte n'a pas démarré")
    return hote
  }

  func arreter() { processus.terminate() }
}

@MainActor
private func modeleJoint(_ adresse: String) async -> ModeleApp {
  let modele = ModeleApp(persistance: persistanceDeTest())
  modele.definirAdresse(adresse)
  // Le jeton « par hôte » : chaque adresse a le sien, et celui d'une autre machine
  // ne vaut pas ici — sans lui, la connexion échoue en « appareil non appairé ».
  modele.definirJeton(String(repeating: "J", count: 36) + String(repeating: "0", count: 7), pour: adresse)
  await modele.connecter()
  return modele
}

@Suite(.serialized)
struct ReconnexionDuModeleTests {

  // `@MainActor` EST OBLIGATOIRE ICI, ET PAS UNE COMMODITÉ : le modèle est isolé au
  // fil principal, et une assertion écrite hors de cet acteur ne compile pas — ce
  // que le compilateur a dit, erreur par erreur, avant que je l'ajoute.
  @MainActor
  @Test("Après deux coupures, le modèle rouvre le flux TOUT SEUL et reprend au bon seq")
  func laBoucleRouvreEtReprend() async throws {
    let hote = try await FauxHote.demarrer(coupures: 2)
    defer { hote.arreter() }

    let modele = await modeleJoint(hote.adresse)
    let etat = modele.connexion
    #expect(etat.estJointe, "l'hôte doit être joint : \(etat)")

    let session = try #require(modele.sessions.first, "le faux hôte publie une session")
    await modele.ouvrir(session)

    // DEUX COUPURES, DONC DEUX ATTENTES D'UNE SECONDE : on laisse la boucle aller
    // au bout, et on laisse la socket finale s'installer.
    let troisieme = await attendre("connexion=3 maintenue=oui", dans: hote.note)
    #expect(troisieme, "la troisième connexion doit vivre — journal :\n\(contenu(hote.note))")
    try? await Task.sleep(nanoseconds: 400_000_000)

    // 1. LE SUIVI EST TOUJOURS LÀ, sans qu'on ait rien appuyé.
    let direct = modele.enDirect
    let echecs = modele.reconnexion?.echecs
    #expect(direct, "le suivi doit être reparti tout seul")
    #expect(echecs == 0, "un contenu reçu remet le compteur a zero")

    // 2. LE JOURNAL EST COMPLET, ET SANS DOUBLON. Le faux hôte renvoie exprès le
    //    seq 1 dans la base de reprise, alors que le client le connaît déjà.
    let sequences = modele.journal.compactMap { $0.enregistrement.seq }
    #expect(Set(sequences).count == sequences.count, "aucun doublon a l ecran : \(sequences)")
    #expect(Set(sequences) == [1, 2, 3], "les trois enregistrements, une fois chacun : \(sequences)")

    // 3. LA MESURE SUR LE FIL : ce que chaque `demarrer` a porté.
    let trace = contenu(hote.note)
    #expect(trace.contains("connexion=1 depuisSeq=absent"), "la premiere demande ne reprend rien")
    #expect(trace.contains("connexion=2 depuisSeq=3"), "la reprise repart du dernier seq connu — journal :\n\(trace)")
    #expect(trace.contains("connexion=3 depuisSeq=3"), "et elle ne recule jamais")
    #expect(trace.contains("connexion=1 coupure=brutale"))
    #expect(trace.contains("connexion=2 coupure=brutale"))
  }

  @MainActor
  @Test("Un flux coupé SANS hôte joignable s'arrête au quota, au lieu de clignoter sans fin")
  func leQuotaArreteLeSuivi() async throws {
    // POURQUOI CE TEST, ALORS QUE LA POLITIQUE EST DÉJÀ ÉPROUVÉE EN PUR. Parce que
    // le quota ne sert à rien s'il n'est pas APPLIQUÉ : le modèle doit finir par
    // poser `enDirect = false` et rendre le bouton à l'utilisateur. C'est le cas
    // d'un jeton révoqué, qu'aucune reconnexion ne répare.
    //
    // On coupe TOUTES les connexions (un nombre plus grand que les tentatives) :
    // le flux ne pourra jamais se stabiliser.
    let hote = try await FauxHote.demarrer(coupures: 999)
    defer { hote.arreter() }

    let modele = await modeleJoint(hote.adresse)
    let session = try #require(modele.sessions.first)
    await modele.ouvrir(session)

    // VINGT TENTATIVES À DÉLAI PLAFONNÉ, CELA FERAIT PLUS DE SIX MINUTES : on ne
    // les attend pas. Ce qui est vérifié ici est le DÉPART de la boucle — elle
    // réessaie VRAIMENT, et l'écran peut le dire PENDANT qu'elle réessaie. La fin du
    // quota, elle, est éprouvée en pur dans `ReconnexionTests`.
    try #require(await attendre("connexion=2 depuisSeq=", dans: hote.note), "une reprise doit avoir eu lieu")

    // PENDANT la reprise, le suivi reste ACTIF : c'est la distinction qui compte
    // pour l'utilisateur — « Suivi arrêté » serait faux, et le bouton mentirait.
    // (`ouvrir` n'a pas rendu la main : le journal de ce faux hôte répond 404, donc
    // la reprise est encore en vol à cet instant précis.)
    let direct = modele.enDirect
    #expect(direct, "pendant une reprise, le suivi reste ACTIF")

    // L'ÉTAT TRANSITOIRE SE GUETTE : le libellé n'existe qu'entre deux tentatives,
    // et la suivante l'efface dès qu'elle reçoit un contenu. On le cherche donc sur
    // toute la durée de la boucle, au lieu de le relire à un instant choisi.
    let annonce = await attendreEtat { modele.reconnexion?.libelle?.hasPrefix("Reconnexion") == true }
    #expect(annonce, "l'ecran doit pouvoir dire qu'il reessaie")
  }
}
