import Foundation
import Testing

@testable import DSHRemoteKit

// CE QUE LE VOLET DE DÉTAIL MONTRE — la règle, éprouvée sans interface.
//
// POURQUOI CES TESTS EXISTENT. La règle vivait dans la vue, en cinq branches
// enchaînées qui finissaient sur « Aucune session ouverte » : au lancement, sur
// macOS comme sur iPad, l'écran de droite restait donc VIDE alors qu'une machine
// était sélectionnée. Deux règles ont été demandées, et elles sont ici :
//
//   1. par défaut, le PREMIER serveur de la liste est sélectionné, et sa page
//      s'affiche — jusqu'à ce qu'une session soit choisie ;
//   2. s'il n'y a AUCUN serveur, c'est la page d'ajout qui s'affiche.

private func machine(_ nom: String, enLigne: Bool = true) -> ServeurMac {
  ServeurMac(nom: nom, nomDNS: nom.lowercased() + ".exemple.test", enLigne: enLigne)
}

private let un = machine("Un")
private let deux = machine("Deux")
private let trois = machine("Trois", enLigne: false)

@Test("Une session choisie passe avant tout le reste")
func laSessionDAbord() {
  // Le journal est ce qu'on vient lire : une page de machine ne doit jamais
  // s'afficher par-dessus une session ouverte.
  let detail = DetailAffiche.pour(
    session: "session-1", ajout: true, pageOuverte: un, cibleEnErreur: deux, vise: trois,
    serveursAffiches: [un, deux, trois])
  #expect(detail == .journal("session-1"))
}

@Test("La page d'ajout ouverte passe avant les machines")
func lAjoutEnsuite() {
  let detail = DetailAffiche.pour(
    session: nil, ajout: true, pageOuverte: un, cibleEnErreur: nil, vise: deux, serveursAffiches: [un, deux])
  #expect(detail == .ajout)
}

@Test("La page ouverte, puis l'erreur, puis la cible — dans cet ordre")
func lOrdreDesMachines() {
  // LA PAGE EXPLICITEMENT OUVERTE GAGNE : on peut consulter une fiche sans être
  // connecté à elle, et la remplacer par la cible ferait disparaître ce qu'on lit.
  let page = DetailAffiche.pour(
    session: nil, ajout: false, pageOuverte: un, cibleEnErreur: deux, vise: trois, serveursAffiches: [un, deux, trois])
  #expect(page == .serveur(un))

  // Sans page ouverte, une ERREUR désigne sa machine : sans cette branche, un
  // échec de connexion au lancement ne s'afficherait nulle part.
  let erreur = DetailAffiche.pour(
    session: nil, ajout: false, pageOuverte: nil, cibleEnErreur: deux, vise: trois, serveursAffiches: [un, deux, trois])
  #expect(erreur == .serveur(deux))

  // Sinon la cible — la machine à laquelle l'application se connecte.
  let cible = DetailAffiche.pour(
    session: nil, ajout: false, pageOuverte: nil, cibleEnErreur: nil, vise: deux, serveursAffiches: [un, deux, trois])
  #expect(cible == .serveur(deux))
}

@Test("Sans cible, c'est le PREMIER serveur de la liste qui s'affiche")
func lePremierParDefaut() {
  // C'EST LA RÈGLE DEMANDÉE, et le cas se présente quand AUCUNE machine n'est en
  // ligne : il n'y a alors aucune cible, et c'est la page de la première qui
  // explique pourquoi. Avant, l'écran restait vide.
  let detail = DetailAffiche.pour(
    session: nil, ajout: false, pageOuverte: nil, cibleEnErreur: nil, vise: nil,
    serveursAffiches: [un, deux, trois])
  #expect(detail == .serveur(un), "le premier de la liste, pas le premier en ligne")
}

@Test("C'est la PREMIÈRE VIGNETTE qui s'affiche, pas le premier de la découverte")
func laPremiereVignette() {
  // LE PARAMÈTRE S'APPELLE `serveursAffiches` POUR CETTE RAISON : le carrousel
  // montre les machines dans un autre ordre que la découverte (joignables
  // d'abord), et la page du volet de détail doit être celle de la vignette mise
  // en avant. Ici la liste arrive DANS L'ORDRE AFFICHÉ — « trois » (hors ligne
  // dans la découverte) est passée devant —, et c'est bien elle qui est rendue.
  // Deux listes différentes feraient parler l'écran de droite d'une autre machine
  // que celle qui est entourée à gauche.
  let detail = DetailAffiche.pour(
    session: nil, ajout: false, pageOuverte: nil, cibleEnErreur: nil, vise: nil,
    serveursAffiches: [trois, un, deux])
  #expect(detail == .serveur(trois), "la première de l'ordre affiché")
}

@Test("Sans aucun serveur, c'est la page d'ajout")
func lAjoutParDefaut() {
  // « S'il n'y a pas de serveur, c'est l'icône ajouté » : la seule chose utile à
  // montrer est comment en ajouter un.
  let detail = DetailAffiche.pour(
    session: nil, ajout: false, pageOuverte: nil, cibleEnErreur: nil, vise: nil, serveursAffiches: [])
  #expect(detail == .ajout)
}

@Test("Un serveur hors ligne est affiché comme les autres")
func leHorsLigneCompte() {
  // La liste ne contient que des machines hors ligne : la première s'affiche, et
  // sa page dit l'état. La retirer de la règle rendrait l'écran vide au moment
  // précis où l'utilisateur a besoin de comprendre.
  let detail = DetailAffiche.pour(
    session: nil, ajout: false, pageOuverte: nil, cibleEnErreur: nil, vise: nil, serveursAffiches: [trois])
  #expect(detail == .serveur(trois))
}
