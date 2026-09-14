import Foundation
import Testing

@testable import DSHRemoteKit

// Tests de l'ÉCRITURE — la seule partie du protocole qui mute l'hôte.
//
// Les charges utiles de ces tests sont des COPIES de réponses réellement
// observées au `curl` contre une instance de test, jamais des exemples inventés.
// C'est ce qui leur donne le pouvoir d'attraper une dérive du protocole : ce
// dépôt a déjà payé une fois une divergence `camelCase` / `snake_case` que des
// tests écrits contre la même hypothèse fausse avaient laissée passer.

@Test("Une demande de prompt s'encode avec les noms de champs du fil")
func encodageDemandePrompt() throws {
  let demande = DemandePrompt(
    texte: "bonjour", mode: .steer, requestId: "essai-ecriture-0001", fuseau: "Europe/Paris")
  let donnees = try JSONEncoder().encode(demande)
  let objet = try #require(try JSONSerialization.jsonObject(with: donnees) as? [String: Any])

  // Les noms sont ceux que le plugin hôte lit : `texte`, `mode`, `requestId`,
  // `fuseau`. Un renommage ici produit un `400` côté hôte sans autre explication.
  #expect(objet["texte"] as? String == "bonjour")
  #expect(objet["mode"] as? String == "steer")
  #expect(objet["requestId"] as? String == "essai-ecriture-0001")
  #expect(objet["fuseau"] as? String == "Europe/Paris")
  #expect(objet.keys.count == 4)
}

@Test("Le mode par défaut est la file d'attente, pas l'interruption")
func modeParDefaut() {
  // L'interruption est intrusive : elle s'insère dans un tour EN COURS. Un défaut
  // qui interrompt ferait perdre du travail sans que l'utilisateur l'ait demandé.
  #expect(DemandePrompt(texte: "x", requestId: "abcdefgh").mode == .queue)
}

@Test("Une acceptation d'écriture réelle se décode")
func decodageAcceptation() throws {
  // Réponse observée : session FROIDE reprise par l'hôte.
  let json = """
    {"protocole":1,"accepte":true,"mode":"queue","requestId":"essai-ecriture-0001","reprise":true}
    """.data(using: .utf8)!

  let reponse = try JSONDecoder().decode(ReponsePrompt.self, from: json)
  #expect(reponse.accepte)
  #expect(reponse.mode == "queue")
  #expect(reponse.requestId == "essai-ecriture-0001")
  #expect(reponse.reprise == true)
}

@Test("Une annulation réelle se décode")
func decodageAnnulation() throws {
  let json = #"{"protocole":1,"annule":true}"#.data(using: .utf8)!
  let reponse = try JSONDecoder().decode(ReponseAnnulation.self, from: json)
  #expect(reponse.annule)
}

@Test("Un refus d'écriture est traduit, jamais affiché en code")
func refusTraduit() throws {
  // Refus réel : session inconnue.
  let json = """
    {"erreur":"envoi refuse","code":"session/not-found","detail":"session \\"session-0\\" not found"}
    """.data(using: .utf8)!

  let refus = try JSONDecoder().decode(RefusEcriture.self, from: json)
  #expect(refus.code == "session/not-found")
  let explication = refus.explication
  #expect(explication == L("cette session n'existe plus sur l'hôte"))
  // Ni le code du protocole, ni le mot « session/not-found » ne doivent
  // atteindre l'utilisateur : il ne peut rien en faire.
  #expect(!explication.contains("session/"))
}

@Test("Un refus sans code connu garde le motif de l'hôte")
func refusSansCodeConnu() {
  let explication = RefusEcriture.expliquer(
    code: "session/inattendu", detail: "le modèle a refusé la demande", erreur: "envoi refuse")
  #expect(explication == "le modèle a refusé la demande")
}

@Test("Un hôte sans annulation ne fait pas afficher de bouton Arrêter")
func capacitesSansAnnulation() throws {
  // Hôte plus ANCIEN que cette fonctionnalité : le champ est absent.
  let ancien = #"{"protocole":1,"capacites":{"sessions":true,"journal":true,"flux":true,"ecriture":true,"approbations":false}}"#
    .data(using: .utf8)!
  let sante = try JSONDecoder().decode(Sante.self, from: ancien)
  // `nil` signifie « ne sait pas », et l'interface s'abstient : proposer un
  // bouton « Arrêter » qui ne ferait rien serait un mensonge d'interface.
  #expect(sante.capacites.annulation == nil)
  #expect(sante.capacites.ecriture)
}

@Test("Un hôte qui annonce l'annulation la déclare")
func capacitesAvecAnnulation() throws {
  let actuel = """
    {"protocole":1,"capacites":{"sessions":true,"journal":true,"flux":true,"ecriture":true,"annulation":true,"approbations":false}}
    """.data(using: .utf8)!
  let sante = try JSONDecoder().decode(Sante.self, from: actuel)
  #expect(sante.capacites.annulation == true)
}

@Test(
  "L'écriture atteint réellement l'hôte",
  .enabled(if: ProcessInfo.processInfo.environment["DSH_REMOTE_ESSAI_SESSION"] != nil))
@MainActor
func ecritureReelle() async throws {
  // ESSAI D'INTÉGRATION, désactivé par défaut : il exige une instance DSH
  // joignable ET une session de travail. Marche à suivre (aucun secret en
  // argument : le jeton est lu dans le coffre, comme le fait le tool) :
  //
  //   DSH_REMOTE_ESSAI_ADRESSE=http://127.0.0.1:3099 \
  //   DSH_REMOTE_ESSAI_SESSION=session-…  swift test --filter ecritureReelle
  //
  // La session visée est REPRISE par l'hôte si elle est froide : cet essai écrit
  // donc pour de vrai, et consomme un tour de modèle.
  let environnement = ProcessInfo.processInfo.environment
  let adresse = try #require(environnement["DSH_REMOTE_ESSAI_ADRESSE"])
  let session = try #require(environnement["DSH_REMOTE_ESSAI_SESSION"])
  let jeton = try #require(
    environnement["DSH_REMOTE_TOKEN"] ?? CoffreDuHarness.jetonDeLaMachine(),
    "aucun jeton d'appareil : ni DSH_REMOTE_TOKEN, ni le coffre du harness")

  let client = try RemoteClient(adresse: adresse, jeton: jeton)
  let sante = try await client.verifierSante()
  #expect(sante.capacites.ecriture)

  let identifiant = DemandePrompt.identifiantNeuf()
  let premiere = try await client.envoyerPrompt(
    session,
    demande: DemandePrompt(
      texte: "Reponds exactement: essai d ecriture", mode: .queue, requestId: identifiant))
  #expect(premiere.accepte)
  #expect(premiere.requestId == identifiant)

  // IDEMPOTENCE : rejouer le MÊME identifiant rend l'acceptation d'origine sans
  // insérer un second message. C'est la propriété qui permet à un client mobile
  // de réessayer après une coupure réseau sans polluer la conversation.
  let rejoue = try await client.envoyerPrompt(
    session,
    demande: DemandePrompt(
      texte: "Reponds exactement: essai d ecriture", mode: .queue, requestId: identifiant))
  #expect(rejoue.accepte)
}

@Test("Un envoi rejoué garde le MÊME identifiant")
func identiteEnvoiRejouee() {
  var attente = EnvoiEnAttente()
  let premier = attente.identifiant(pour: "bonjour")
  // Deuxieme appui apres une coupure reseau : meme texte, donc meme identite.
  // C'est ce qui evite le doublon dans la conversation.
  let second = attente.identifiant(pour: "bonjour")
  #expect(premier == second)
  #expect(attente.enAttente)
}

@Test("Un texte différent est un nouvel envoi")
func identiteEnvoiDifferent() {
  var attente = EnvoiEnAttente()
  let premier = attente.identifiant(pour: "bonjour")
  let second = attente.identifiant(pour: "bonsoir")
  #expect(premier != second)
}

@Test("L'acquittement libère l'identité")
func identiteApresAcquittement() {
  var attente = EnvoiEnAttente()
  let premier = attente.identifiant(pour: "bonjour")
  attente.acquitter()
  #expect(!attente.enAttente)
  // Le meme texte renvoye PLUS TARD est un nouveau message : il doit porter un
  // identifiant neuf, sans quoi l'hote le prendrait pour un rejeu et ne
  // l'insererait jamais.
  let apres = attente.identifiant(pour: "bonjour")
  #expect(premier != apres)
}

@Test("L'identifiant d'envoi est accepté par la forme qu'exige l'hôte")
func formeIdentifiantEnvoi() {
  // L'hôte valide `^[A-Za-z0-9_-]{8,64}$` et retombe sur un identifiant tiré
  // par lui si la forme ne convient pas — auquel cas l'idempotence est perdue
  // SANS que rien ne le signale. On vérifie donc la forme ici.
  for _ in 0..<50 {
    let identifiant = DemandePrompt.identifiantNeuf()
    #expect(identifiant.count >= 8 && identifiant.count <= 64)
    #expect(
      identifiant.allSatisfy { $0.isLetter && $0.isASCII || $0.isNumber && $0.isASCII || $0 == "-" || $0 == "_" }
    )
  }
}
