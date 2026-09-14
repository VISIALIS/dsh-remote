import Foundation
import Testing

@testable import DSHRemoteKit

// Les espaces publiés par l'HÔTE.
//
// POURQUOI CES TESTS EXISTENT. L'application déduisait ses espaces des sessions :
// un dossier enregistré mais encore vide lui était invisible, alors que
// l'interface web l'affiche. Elle comparait aussi les CHEMINS pour rattacher une
// session à un espace — ce qui se trompe dès qu'un dossier est renommé, que deux
// projets portent le même nom, ou qu'une session a été déplacée. Le registre de
// l'hôte porte ces deux faits ; ces tests vérifient qu'on les suit.

private func sessionDeTest(
  id: String, cwd: String, quand: Int, cree: Int = 1, profondeur: Int = 0
) -> SessionListee {
  let json = """
    {"protocole":1,"total":1,"sessions":[
      {"projet":"--x--","dossier":"/d","fichier":"/f","octets":100,"modifieLe":1,"vivante":true,
       "id":"\(id)","cwd":"\(cwd)","creeLe":\(cree),"preset":"standard","profondeurDelegation":\(profondeur),
       "seme":false,"titre":"\(id)","dernierEvenementLe":\(quand),"dernierSeq":1,
       "nbEnregistrements":1,"tronque":false}]}
    """.data(using: .utf8)!
  return try! JSONDecoder().decode(ListeSessions.self, from: json).sessions[0]
}

private func espaceHote(
  id: String, titre: String, chemin: String, creeLe: Int, sessions: [String]
) -> EspaceHote {
  EspaceHote(id: id, titre: titre, chemin: chemin, creeLe: creeLe, sessions: sessions)
}

@Test("Les espaces de l'hôte sont rendus dans SON ordre, vides compris")
func espacesVidesCompris() {
  let sessions = [sessionDeTest(id: "s1", cwd: "/tmp/utilise", quand: 500)]
  let hotes = [
    // Le registre classe par création décroissante : un espace VIDE mais récent
    // passe donc devant un espace ancien qui travaille — c'est la règle du web.
    espaceHote(id: "w-recent", titre: "Récent", chemin: "/tmp/recent", creeLe: 9_000, sessions: []),
    espaceHote(id: "w-utilise", titre: "Utilisé", chemin: "/tmp/utilise", creeLe: 1_000, sessions: ["s1"]),
  ]
  let espaces = Regroupement.espaces(sessions, hotes: hotes)

  #expect(espaces.map(\.nom) == ["Récent", "Utilisé"])
  #expect(espaces[0].sansSession == true)
  #expect(espaces[0].nbSessions == 0)
  #expect(espaces[1].sansSession == false)
  #expect(espaces[1].sessions.map(\.id) == ["s1"])
  // L'identifiant est celui du registre : c'est lui qui pilote le dépliage, et
  // deux espaces peuvent partager un chemin d'affichage sans être le même.
  #expect(espaces.map(\.id) == ["w-recent", "w-utilise"])
}

@Test("L'appartenance vient du REGISTRE, pas du chemin")
func appartenanceParRegistre() {
  // « dedans » a un cwd qui ne correspond PAS au chemin de son espace : elle y
  // appartient quand même, parce que le registre le dit. Et « dehors », dont le
  // cwd correspond au chemin, n'appartient à aucun espace déclaré.
  let sessions = [
    sessionDeTest(id: "dedans", cwd: "/tmp/ailleurs", quand: 300),
    sessionDeTest(id: "dehors", cwd: "/tmp/utilise", quand: 400),
  ]
  let hotes = [espaceHote(id: "w1", titre: "Espace", chemin: "/tmp/utilise", creeLe: 1_000, sessions: ["dedans"])]
  let espaces = Regroupement.espaces(sessions, hotes: hotes)

  #expect(espaces.count == 2)
  #expect(espaces[0].sessions.map(\.id) == ["dedans"])
  // Les sessions sans espace forment le « Ungrouped » du web, et il vient en
  // dernier : ce n'est pas un projet, c'est ce qui reste.
  #expect(espaces[1].horsEspaces == true)
  #expect(espaces[1].nom == "Sans espace")
  #expect(espaces[1].sessions.map(\.id) == ["dehors"])
}

@Test("Un espace dont les sessions sont filtrées n'est pas « vide » pour autant")
func filtreNeVidePas() {
  // Le filtre de la liste peut masquer toutes les sessions d'un espace. L'icône
  // ne doit pas basculer pour autant : « vide » est un fait du REGISTRE, pas de
  // l'affichage — sinon l'arbre clignoterait pendant une recherche.
  let hotes = [espaceHote(id: "w1", titre: "Espace", chemin: "/tmp/p", creeLe: 1, sessions: ["absente"])]
  let espaces = Regroupement.espaces([], hotes: hotes)

  #expect(espaces.count == 1)
  #expect(espaces[0].sansSession == false)
  #expect(espaces[0].nbSessions == 0)
}

@Test("Dans un espace, les sessions restent classées par activité")
func sessionsParActivite() {
  let sessions = [
    sessionDeTest(id: "vieille", cwd: "/tmp/p", quand: 100, cree: 9_000),
    sessionDeTest(id: "recente", cwd: "/tmp/p", quand: 900, cree: 10),
    sessionDeTest(id: "sous-agent", cwd: "/tmp/p", quand: 950, cree: 10, profondeur: 1),
  ]
  let hotes = [espaceHote(id: "w1", titre: "Espace", chemin: "/tmp/p", creeLe: 1, sessions: ["vieille", "recente", "sous-agent"])]
  let espace = Regroupement.espaces(sessions, hotes: hotes)[0]

  // La LIGNÉE n'entre pas dans l'ordre : un sous-agent se classe par son
  // activité, et c'est le rendu qui l'indente. Le tri « racines puis enfants »
  // ferait dépendre la position d'une session de sa parenté.
  #expect(espace.sessions.map(\.id) == ["sous-agent", "recente", "vieille"])
}

@Test("Un titre d'espace vide retombe sur le nom du dossier, jamais sur rien")
func titreDeRepli() {
  #expect(Regroupement.nomAffiche(titre: "   ", chemin: "/tmp/mon-projet") == "mon-projet")
  #expect(Regroupement.nomAffiche(titre: "Mon titre", chemin: "/tmp/autre") == "Mon titre")
}

@Test("Sans registre publié, l'arbre reste déduit des sessions")
func repliSansRegistre() {
  // Hôte plus ancien, ou route indisponible : on retrouve le comportement
  // d'avant, et aucun espace n'est déclaré vide.
  let sessions = [sessionDeTest(id: "a", cwd: "/tmp/p", quand: 1)]
  let espaces = Regroupement.espaces(sessions, hotes: [])

  #expect(espaces.count == 1)
  #expect(espaces[0].sansSession == false)
  #expect(espaces[0].horsEspaces == false)
}

// ── LES ESPACES SUIVENT LE SERVEUR CHOISI ─────────────────────────────────────
//
// POURQUOI CES TESTS EXISTENT. Les espaces de travail viennent du REGISTRE DE
// L'HÔTE : ils décrivent une machine, pas l'application. Or ils survivaient au
// changement de serveur — la liste latérale montrait donc les dossiers de
// l'ancien, mêlés aux sessions du nouveau, ou seuls si la connexion au nouveau
// échouait. Constaté à l'usage : « workspaces / Espace de travail dépend du
// serveur, il faut actualiser en fonction du serveur choisi ».
//
// CE QUI N'EST PAS TOUCHÉ, ET QUI DOIT LE RESTER : ouvrir la PAGE d'une machine
// n'est pas changer de cible (une page peut s'ouvrir sur un hôte auquel on n'est
// pas connecté), et re-choisir la machine DÉJÀ visée ne doit rien vider — sinon
// l'arbre clignoterait à chaque appui sur la vignette courante.

@MainActor
@Test("Changer de serveur efface les espaces de l'ancien")
func espacesEffacesAuChangement() {
  let modele = modeleDeTest()
  modele.definirAdresse("http://premier.exemple.test")
  modele.appliquerEspaces(
    [espaceHote(id: "e1", titre: "dsh-plugins", chemin: "/x/dsh-plugins", creeLe: 1, sessions: [])],
    vu: modele.generationDuDepart())
  #expect(modele.espacesHote.count == 1)

  modele.choisir(ServeurMac(nom: "Second", nomDNS: "second.exemple.test", enLigne: true))

  #expect(modele.adresse == "http://second.exemple.test")
  #expect(modele.espacesHote.isEmpty, "les espaces de l'ancien serveur ne doivent pas survivre")
}

@MainActor
@Test("Re-choisir la machine DÉJÀ visée ne vide rien")
func espacesConservesSiMemeCible() {
  // Sinon l'arbre clignoterait à chaque appui sur la vignette du serveur courant —
  // et c'est le geste qu'on fait pour revenir à la liste.
  let modele = modeleDeTest()
  modele.definirAdresse("http://premier.exemple.test")
  modele.appliquerEspaces(
    [espaceHote(id: "e1", titre: "dsh-plugins", chemin: "/x/dsh-plugins", creeLe: 1, sessions: [])],
    vu: modele.generationDuDepart())

  modele.choisir(ServeurMac(nom: "Premier", nomDNS: "premier.exemple.test", enLigne: true))

  #expect(modele.espacesHote.count == 1, "même adresse : rien à effacer")
}

@MainActor
@Test("Ouvrir la page d'une autre machine ne touche pas aux espaces")
func espacesIntactsSurUnePage() {
  // UNE PAGE N'EST PAS UNE CIBLE. On peut consulter la fiche d'une machine sans
  // être connecté à elle : effacer l'arbre à ce moment-là ferait disparaître ce
  // qu'on est en train de lire.
  let modele = modeleDeTest()
  modele.definirAdresse("http://premier.exemple.test")
  modele.appliquerEspaces(
    [espaceHote(id: "e1", titre: "dsh-plugins", chemin: "/x/dsh-plugins", creeLe: 1, sessions: [])],
    vu: modele.generationDuDepart())

  modele.ouvrirPage(ServeurMac(nom: "Second", nomDNS: "second.exemple.test", enLigne: true))

  #expect(modele.adresse == "http://premier.exemple.test", "la cible n'a pas bougé")
  #expect(modele.espacesHote.count == 1)
}
