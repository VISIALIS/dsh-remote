import Foundation
import Testing

@testable import DSHRemoteKit

// CE QUI ATTEND L'UTILISATEUR DOIT REMONTER EN TÊTE.
//
// POURQUOI CES TESTS EXISTENT. La revue a relevé que l'information la plus
// actionnable de l'application était ENTERRÉE : pour savoir quelle session
// attendait une décision, il fallait déplier dix espaces et lire des pastilles
// de huit points. La liste trie maintenant par urgence dans une section dédiée,
// et l'en-tête d'un espace replié dit ce qui y attend — deux règles pures, donc
// éprouvables ici sans interface.

private func session(
  _ identifiant: String, titre: String = "T", statut: String? = "inactif",
  vivante: Bool? = true, attendReponse: Bool? = nil, quand: Int = 1_700_000_000_000
) -> SessionListee {
  let attendJSON = attendReponse.map { "\"attendReponse\":\($0)," } ?? ""
  let statutJSON = statut.map { "\"\($0)\"" } ?? "null"
  let vivanteJSON = vivante.map { "\($0)" } ?? "null"
  let json = """
    {"protocole":1,"total":1,"sessions":[
      {"projet":"--x--","dossier":"/d","fichier":"/f","octets":1,"modifieLe":1,"vivante":\(vivanteJSON),
       "id":"\(identifiant)","creeLe":1,"preset":"standard","profondeurDelegation":0,\(attendJSON)
       "seme":false,"titre":"\(titre)","dernierEvenementLe":\(quand),"dernierSeq":1,
       "nbEnregistrements":1,"tronque":false,"statut":\(statutJSON)}]}
    """.data(using: .utf8)!
  return try! JSONDecoder().decode(ListeSessions.self, from: json).sessions[0]
}

@Test("Un espace replié dit ce qui y attend, pas seulement combien il compte")
func resumeDEspace() {
  let sessions = [
    session("bloquee", attendReponse: true),
    session("finie"),
    session("calme"),
    session("calme2"),
  ]
  // « finie » a un rappel de fin non vu : c'est le second cas actionnable.
  let resume = Regroupement.resume(sessions, terminees: ["finie"])

  #expect(resume.total == 4)
  #expect(resume.enAttente == 1)
  #expect(resume.terminees == 1)
  #expect(resume.texte == "4 · 1 en attente · 1 terminée")
}

@Test("Quand rien n'attend, l'en-tête reste court")
func resumeSansUrgence() {
  // Le nombre seul : c'est le cas le plus fréquent, et une ligne d'en-tête
  // chargée se lit moins vite.
  let resume = Regroupement.resume([session("a"), session("b")])
  #expect(resume.texte == "2")
  #expect(resume.enAttente == 0)
}

@Test("Le pluriel des fins non lues est juste")
func plurielDesTerminees() {
  let resume = Regroupement.resume(
    [session("a"), session("b")], terminees: ["a", "b"])
  #expect(resume.texte == "2 · 2 terminées")
}

@MainActor
@Test("La liste d'attention ne garde que ce qui demande quelque chose")
func listeDAttention() {
  let modele = ModeleApp()
  let liste = """
    {"protocole":1,"total":4,"sessions":[
      {"projet":"--x--","dossier":"/d","fichier":"/f","octets":1,"modifieLe":1,"vivante":true,
       "id":"bloquee","creeLe":1,"preset":"standard","profondeurDelegation":0,"attendReponse":true,
       "seme":false,"titre":"Bloquée","dernierEvenementLe":100,"dernierSeq":1,"nbEnregistrements":1,
       "tronque":false,"statut":"en_cours"},
      {"projet":"--x--","dossier":"/d","fichier":"/f","octets":1,"modifieLe":1,"vivante":true,
       "id":"bloquee2","creeLe":1,"preset":"standard","profondeurDelegation":0,"attendReponse":true,
       "seme":false,"titre":"Bloquée aussi","dernierEvenementLe":900,"dernierSeq":1,"nbEnregistrements":1,
       "tronque":false,"statut":"en_cours"},
      {"projet":"--x--","dossier":"/d","fichier":"/f","octets":1,"modifieLe":1,"vivante":true,
       "id":"travaille","creeLe":1,"preset":"standard","profondeurDelegation":0,
       "seme":false,"titre":"Travaille","dernierEvenementLe":500,"dernierSeq":1,"nbEnregistrements":1,
       "tronque":false,"statut":"en_cours"},
      {"projet":"--x--","dossier":"/d","fichier":"/f","octets":1,"modifieLe":1,"vivante":true,
       "id":"dort","creeLe":1,"preset":"standard","profondeurDelegation":0,
       "seme":false,"titre":"Dort","dernierEvenementLe":600,"dernierSeq":1,"nbEnregistrements":1,
       "tronque":false,"statut":"inactif"}]}
    """.data(using: .utf8)!
  modele.appliquerSessions(
    try! JSONDecoder().decode(ListeSessions.self, from: liste),
    vu: modele.generationDuDepart())

  let attendues = modele.sessionsQuiAttendent
  #expect(attendues.count == 2)
  // « en_cours » sans question n'y est PAS : travailler n'est pas attendre.
  #expect(!attendues.contains { $0.id == "travaille" })
  #expect(!attendues.contains { $0.id == "dort" })
  // À urgence égale, la plus récente d'abord.
  #expect(attendues.map(\.id) == ["bloquee2", "bloquee"])
}

@MainActor
@Test("Une session qui attend passe avant une fin de tour non lue")
func urgenceAvantInformation() {
  // L'ordre suit celui d'`EtatSession` : l'une est bloquée SUR vous, l'autre vous
  // informe. Les confondre ferait passer un rappel avant une décision à prendre.
  let etatAttente = EtatSession.de(session("a", attendReponse: true), rappelDeFin: true)
  let etatFinie = EtatSession.de(session("b"), rappelDeFin: true)
  #expect(etatAttente == .attendReponse)
  #expect(etatFinie == .terminee)
}
