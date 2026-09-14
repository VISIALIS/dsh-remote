import Foundation
import Testing

@testable import DSHRemoteKit

// L'APPUI SUR UNE MACHINE — deux temps, et une règle.
//
// POURQUOI CES TESTS EXISTENT. La vignette faisait « OUVRIR ET CONNECTER » en un
// seul geste. Le raisonnement se tenait — « toucher une machine, c'est vouloir s'y
// connecter » —, mais il manquait une conséquence : sur iPhone, l'appui EMPILE la
// page de la machine, si bien que quelqu'un qui voulait seulement passer sur un
// autre serveur pour voir ses sessions se retrouvait sur une fiche et devait
// revenir en arrière.
//
// La règle demandée est donc : un appui SÉLECTIONNE (la cible change, ses sessions
// et ses espaces se rechargent), un SECOND ouvre la page de détail.

private let air = ServeurMac(nom: "MacBook Air", nomDNS: "air.exemple.test", enLigne: true)
private let mini = ServeurMac(nom: "MacMini", nomDNS: "mini.exemple.test", enLigne: true)

@Test("Toucher une machine qui n'est pas la cible la SÉLECTIONNE")
func lePremierAppuiSelectionne() {
  #expect(GesteSurServeur.pour(mini, choisi: air) == .selectionner)
  #expect(GesteSurServeur.pour(mini, choisi: nil) == .selectionner)
}

@Test("Retoucher la machine déjà sélectionnée ouvre sa page")
func leSecondAppuiOuvreLaPage() {
  #expect(GesteSurServeur.pour(mini, choisi: mini) == .ouvrirLaPage)
}

@Test("La reconnaissance se fait sur l'IDENTITÉ, pas sur les valeurs")
func identiteEtPasValeurs() {
  // LA CIBLE ET LA LISTE NE SONT PAS LA MÊME INSTANCE : `enLigne` change avec la
  // découverte, le nom peut être relu. Comparer les valeurs entières ferait
  // échouer la reconnaissance, et un second appui sélectionnerait au lieu
  // d'ouvrir — un défaut qui ne se voit qu'à l'usage, et par intermittence.
  let memeHoteAutreEtat = ServeurMac(
    nom: "MacMini", nomDNS: "mini.exemple.test", enLigne: false, estLocal: true)
  #expect(GesteSurServeur.pour(memeHoteAutreEtat, choisi: mini) == .ouvrirLaPage)
}

// ── Et ce que le modèle en fait ───────────────────────────────────────────────

/// Un transport qui échoue TOUT DE SUITE : la règle s'éprouve sans réseau, et
/// sans attendre un délai qui n'a rien à voir avec ce qu'on mesure.
private struct ClientQuiEchoue: ClientDSH {
  func verifierSante() async throws -> Sante { throw ErreurRemote.reponseInattendue(code: 500) }
  func listerSessions(limite: Int?) async throws -> ListeSessions { throw ErreurRemote.reponseInattendue(code: 500) }
  func listerServeurs() async throws -> ListeServeurs { throw ErreurRemote.reponseInattendue(code: 500) }
  func listerEspaces() async throws -> ListeEspaces { throw ErreurRemote.reponseInattendue(code: 500) }
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
private func modeleSansReseau() -> ModeleApp {
  ModeleApp(
    gardien: GardienEnMemoire(), persistance: persistanceDeTest(),
    transport: Connexion(fabrique: { _, _, _ in ClientQuiEchoue() }))
}

@MainActor
@Test("Un appui sur une autre machine change la cible, et ferme la page de l'ancienne")
func changerDeMachineFermeLAnciennePage() async {
  let modele = modeleSansReseau()
  modele.choisir(air)
  modele.ouvrirPage(air)
  #expect(modele.serveurOuvert == air.id)

  await modele.toucher(mini)

  // LA CIBLE A CHANGÉ : c'est ce qui fait recharger les sessions et les espaces de
  // travail de la nouvelle machine (le défaut « les espaces ne suivaient pas » a
  // été corrigé juste avant celui-ci).
  #expect(modele.adresse == mini.adresse)
  #expect(modele.serveurChoisi?.id == mini.id)
  // ET LA PAGE DE L'ANCIENNE EST FERMÉE : sans cela, le volet de détail montrerait
  // une machine qui n'est plus visée.
  #expect(modele.serveurOuvert == nil)
}

@MainActor
@Test("Un appui sur la machine courante ouvre sa page, sans changer de cible")
func retoucherOuvreLaPage() async {
  let modele = modeleSansReseau()
  modele.choisir(mini)
  modele.fermerPage()
  #expect(modele.serveurOuvert == nil)

  await modele.toucher(mini)

  #expect(modele.serveurOuvert == mini.id)
  #expect(modele.adresse == mini.adresse, "la cible ne bouge pas : c'est déjà elle")
}
