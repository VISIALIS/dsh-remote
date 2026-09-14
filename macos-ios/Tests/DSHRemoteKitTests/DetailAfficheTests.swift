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
    session: "session-1", ajout: true, pageOuverte: un, vise: trois,
    serveursAffiches: [un, deux, trois])
  #expect(detail == .journal("session-1"))
}

@Test("La page d'ajout ouverte passe avant les machines")
func lAjoutEnsuite() {
  let detail = DetailAffiche.pour(
    session: nil, ajout: true, pageOuverte: un, vise: deux, serveursAffiches: [un, deux])
  #expect(detail == .ajout)
}

@Test("Seule la page OUVERTE donne une page — ni la cible, ni une erreur")
func lOrdreDesMachines() {
  // LA PAGE EXPLICITEMENT OUVERTE GAGNE : on peut consulter une fiche sans être
  // connecté à elle, et la remplacer par la cible ferait disparaître ce qu'on lit.
  let page = DetailAffiche.pour(
    session: nil, ajout: false, pageOuverte: un, vise: trois,
    serveursAffiches: [un, deux, trois])
  #expect(page == .serveur(un))

  // LA CIBLE SEULE N'OUVRE PAS LA PAGE — règle des deux temps : le premier appui
  // sélectionne et recharge, le second ouvre.
  //
  // ET L'ERREUR NON PLUS, ce qui a demandé une seconde correction : une machine
  // qui refuse la connexion (un `401` sur un Mac non appairé) rouvrait sa fiche,
  // donc la sélection simple ne tenait que pour les machines qui répondaient. Le
  // propriétaire l'a formulé exactement : « sur macOS, ça ne fonctionne que pour
  // le premier serveur ». La règle ne connaît plus l'erreur du tout : elle est
  // affichée dans l'état de sélection, et en détail sur la page.
  let cible = DetailAffiche.pour(
    session: nil, ajout: false, pageOuverte: nil, vise: deux,
    serveursAffiches: [un, deux, trois])
  #expect(cible == .selection(deux))
  #expect(cible != .serveur(deux), "ni la cible ni son erreur n'ouvrent la page")
}

@Test("Sans cible, c'est le PREMIER serveur de la liste qui est SÉLECTIONNÉ")
func lePremierParDefaut() {
  // Le cas se présente quand AUCUNE machine n'est en ligne : il n'y a alors
  // aucune cible, et c'est la première qui est mise en avant — sa page s'ouvre
  // au second appui, comme pour toute autre sélection.
  let detail = DetailAffiche.pour(
    session: nil, ajout: false, pageOuverte: nil, vise: nil,
    serveursAffiches: [un, deux, trois])
  #expect(detail == .selection(un), "le premier de la liste, pas le premier en ligne")
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
    session: nil, ajout: false, pageOuverte: nil, vise: nil,
    serveursAffiches: [trois, un, deux])
  #expect(detail == .selection(trois), "la première de l'ordre affiché")
}

@Test("Sans aucun serveur, c'est la page d'ajout")
func lAjoutParDefaut() {
  // « S'il n'y a pas de serveur, c'est l'icône ajouté » : la seule chose utile à
  // montrer est comment en ajouter un.
  let detail = DetailAffiche.pour(
    session: nil, ajout: false, pageOuverte: nil, vise: nil, serveursAffiches: [])
  #expect(detail == .ajout)
}

@Test("Un serveur hors ligne est affiché comme les autres")
func leHorsLigneCompte() {
  // La liste ne contient que des machines hors ligne : la première s'affiche, et
  // sa page dit l'état. La retirer de la règle rendrait l'écran vide au moment
  // précis où l'utilisateur a besoin de comprendre.
  let detail = DetailAffiche.pour(
    session: nil, ajout: false, pageOuverte: nil, vise: nil,
    serveursAffiches: [trois])
  #expect(detail == .selection(trois))
}

@Test("LES DEUX TEMPS : sélectionner n'ouvre pas, un second appui ouvre")
func lesDeuxTemps() {
  // LA RÈGLE DU PROPRIÉTAIRE, POUR LES TROIS PLATEFORMES : « sélectionner un autre
  // serveur change la sélection et actualise l'espace de travail ; sélectionner
  // une icône déjà sélectionnée permet d'accéder à la page détail ». Ce test la
  // tient du côté de l'ÉCRAN : la même machine, une fois par son seul état de
  // sélection, une fois par sa page ouverte.
  let selectionne = DetailAffiche.pour(
    session: nil, ajout: false, pageOuverte: nil, vise: un,
    serveursAffiches: [un, deux])
  let ouvert = DetailAffiche.pour(
    session: nil, ajout: false, pageOuverte: un, vise: un,
    serveursAffiches: [un, deux])
  #expect(selectionne == .selection(un))
  #expect(ouvert == .serveur(un))
  #expect(selectionne != ouvert, "les deux temps ne montrent pas la même chose")
}

@Test("Une session ouverte reste prioritaire, même sur une page ouverte")
func laSessionRestePremiere() {
  // Rien de ce qui précède ne doit ramener le journal sous une fiche : c'est la
  // règle qui existait déjà, et la nouvelle ne la déplace pas.
  let detail = DetailAffiche.pour(
    session: "s-1", ajout: false, pageOuverte: un, vise: trois,
    serveursAffiches: [un, deux, trois])
  #expect(detail == .journal("s-1"))
}
