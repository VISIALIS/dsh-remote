import Foundation
import Testing

@testable import DSHRemoteKit

// « IL DOIT TOUJOURS Y AVOIR UN SERVEUR SÉLECTIONNÉ. »
//
// LA RÈGLE, DITE PAR LE PROPRIÉTAIRE : la coche en haut à gauche de la vignette,
// et sous elle les espaces de travail de CE serveur. Le défaut mesuré sur iPhone :
// l'application se connecte d'abord à l'adresse mémorisée, la liste des machines
// n'arrive qu'après (publiée par cet hôte), et rien ne rattachait la machine
// jointe à la cible — aucune coche, aucun espace de travail.
//
// Ces tests portent sur la DÉCISION, qui doit être juste sans réseau.

private func machine(_ nom: String, _ hote: String, enLigne: Bool = true) -> ServeurMac {
  ServeurMac(nom: nom, nomDNS: hote, enLigne: enLigne)
}

private let portable = machine("Portable Un", "portable-un.exemple.ts.net")
private let mini = machine("MacMini", "macmini.exemple.ts.net")
private let bureau = machine("Bureau", "bureau.exemple.ts.net", enLigne: false)
/// L'HÔTE INTERROGÉ, tel qu'il se publie LUI-MÊME dans sa propre liste : c'est
/// la marque `local: true` du plugin, décodée en `estLocal`.
private let hote = ServeurMac(
  nom: "MacBook Air", nomDNS: "macbook-air.exemple.ts.net", enLigne: true, estLocal: true)

@Test("La machine JOINTE est reconnue par son adresse, quelle que soit l'écriture")
func laMachineJointeEstReconnue() throws {
  // C'est le cas d'usage : on vient de se connecter à cette adresse, et la liste
  // publiée par l'hôte la contient. La coche doit tomber sur ELLE, pas sur la
  // première venue.
  let trouvee = try #require(
    SelectionParDefaut.machineJointe(
      parmi: [mini, portable, bureau], adresse: "http://portable-un.exemple.ts.net"))
  #expect(trouvee.id == portable.id)
  // Même machine, deux écritures : sans schéma, et avec une barre finale.
  #expect(
    SelectionParDefaut.machineJointe(parmi: [portable], adresse: "portable-un.exemple.ts.net/")?.id
      == portable.id)
}

@Test("Une adresse vide ne désigne personne")
func adresseVideNeDesignePersonne() {
  // Au premier lancement, l'adresse n'est pas encore connue : il n'y a pas de
  // « machine jointe », et c'est la règle suivante qui décide.
  #expect(SelectionParDefaut.machineJointe(parmi: [portable, mini], adresse: "") == nil)
}

@Test("Au lancement, sans correspondance, c'est la PREMIÈRE de la liste")
func auLancementLaPremiere() throws {
  // « Par défaut c'est le premier serveur de la liste qui doit être sélectionné. »
  // La liste reçue est celle de l'AFFICHAGE : joignables d'abord.
  let choisie = try #require(
    SelectionParDefaut.aSelectionner(
      parmi: [portable, mini, bureau], adresse: "http://127.0.0.1:3080", listeVientDeLHote: false,
      remplacerFauteDeMieux: true))
  #expect(choisie == .premiere(portable), "un CHOIX par défaut, pas une reconnaissance")
}

@Test("APRÈS une réponse de l'hôte, on ne change pas de cible faute de mieux")
func apresUneReponseOnNeRemplacePas() {
  // LA DIFFÉRENCE QUI COMPTE, ET QUI A COÛTÉ UNE SESSION DE MISE AU POINT. Sur
  // iPhone la liste arrive après la connexion : remplacer la cible à cet instant
  // viderait les sessions et les espaces de travail qui viennent d'être chargés.
  // Rattacher, oui ; remplacer, non.
  #expect(
    SelectionParDefaut.aSelectionner(
      parmi: [portable, mini], adresse: "http://127.0.0.1:3080", listeVientDeLHote: false,
      remplacerFauteDeMieux: false)
      == nil)
}

@Test("La correspondance l'emporte, même quand on pourrait remplacer")
func laCorrespondanceLEmporte() throws {
  let choisie = try #require(
    SelectionParDefaut.aSelectionner(
      parmi: [mini, portable], adresse: "http://portable-un.exemple.ts.net", listeVientDeLHote: false,
      remplacerFauteDeMieux: true))
  #expect(choisie == .jointe(portable), "la machine jointe, pas la première de la liste")
}

@Test("Sans aucune machine, il n'y a rien à sélectionner")
func listeVide() {
  // C'est le cas où la vignette « Ajouter » prend la place : il n'y a pas de
  // serveur, donc pas de sélection à assurer.
  #expect(
    SelectionParDefaut.aSelectionner(parmi: [], adresse: "http://x.exemple.ts.net", listeVientDeLHote: false,
      remplacerFauteDeMieux: true)
      == nil)
}

// ── L'INVARIANT, VU DU MODÈLE ────────────────────────────────────────────────

@MainActor
@Test("Le modèle attache la machine jointe dès que la liste arrive — la coche existe")
func leModeleAttacheLaMachineJointe() throws {
  // L'ORDRE RÉEL DU LANCEMENT SUR IPHONE : connecté à une adresse, puis la liste
  // arrive. On reproduit cet ordre exactement : adresse connue, liste posée
  // ensuite, invariant appelé comme le fait `appliquerServeursDeLhote`.
  let modele = modeleDeTest()
  modele.definirAdresse("http://portable-un.exemple.ts.net")
  modele.remplacerServeursPourEssai([mini, portable])
  #expect(modele.serveurChoisi == nil, "au départ, aucune machine n'est sélectionnée")

  modele.assurerUneSelectionPourEssai(auLancement: false)

  let choisie = try #require(modele.serveurChoisi)
  #expect(choisie.id == portable.id, "la machine JOINTE, pas la première de la liste")
}

@MainActor
@Test("Au lancement sans adresse, le modèle sélectionne la PREMIÈRE VIGNETTE")
func leModeleSelectionneLaPremiere() throws {
  // « Il doit toujours y avoir un serveur sélectionné » : sur macOS, la
  // découverte arrive avant la connexion, et la machine cochée doit être celle de
  // la PREMIÈRE VIGNETTE — donc de la liste AFFICHÉE, joignables d'abord, et non
  // de la liste brute. Le premier essai de ce test attendait « Bureau », qui est
  // hors ligne : c'est la liste brute qui parlait, pas l'écran.
  let modele = modeleDeTest()
  modele.definirAdresse("")
  modele.remplacerServeursPourEssai([bureau, mini, portable])

  modele.assurerUneSelectionPourEssai(auLancement: true)

  let premiere = try #require(modele.serveursAffiches.first)
  #expect(premiere.id == mini.id, "la première vignette est la machine JOIGNABLE")
  #expect(modele.serveurChoisi?.id == premiere.id, "et c'est elle qui est cochée")
}

@MainActor
@Test("Un choix DÉJÀ fait n'est jamais écrasé par l'invariant")
func unChoixDejaFaitSurvit() throws {
  // La règle ne remplit qu'un VIDE : elle ne défait pas un choix de
  // l'utilisateur, et ne touche pas non plus à la cible d'une bascule.
  let modele = modeleDeTest()
  modele.definirAdresse("http://macmini.exemple.ts.net")
  modele.remplacerServeursPourEssai([mini, portable])
  modele.assurerUneSelectionPourEssai(auLancement: false)
  #expect(modele.serveurChoisi?.id == mini.id)

  modele.assurerUneSelectionPourEssai(auLancement: true)

  #expect(modele.serveurChoisi?.id == mini.id, "le choix de l'utilisateur reste")
}

@Test("LA LISTE DE L'HÔTE, QUI SE DÉSIGNE LUI-MÊME — le cas mesuré sur simulateur")
func lHoteSeDesigneLuiMeme() throws {
  // CE QUE LE SIMULATEUR A MONTRÉ : connecté à `127.0.0.1:3080`, la liste publiée
  // par cet hôte, les espaces de travail chargés — et AUCUNE coche, parce que
  // l'adresse de l'hôte dans SA liste est son nom de tailnet, pas la boucle
  // locale. L'hôte se marque pourtant lui-même (`local: true`) : c'est un fait,
  // et c'est celui qu'on utilise.
  let choisie = try #require(
    SelectionParDefaut.aSelectionner(
      parmi: [hote, mini, portable], adresse: "http://127.0.0.1:3080", listeVientDeLHote: true,
      remplacerFauteDeMieux: false))
  #expect(choisie == .hote(hote), "l'hôte interrogé, pas la première de la liste")
}

@Test("Le marqueur `local` d'une découverte LOCALE n'est pas l'hôte interrogé")
func leMarqueurLocalNeTrompePas() {
  // SUR macOS, la découverte locale marque CETTE machine — pas celle à qui l'on
  // parle. La traiter comme l'hôte attacherait la coche à un Mac qu'on ne joint
  // pas : le drapeau `listeVientDeLHote` est ce qui l'empêche, et c'est pour ça
  // qu'il existe plutôt qu'un simple « prends le premier `estLocal` ».
  #expect(
    SelectionParDefaut.aSelectionner(
      parmi: [hote, mini], adresse: "http://127.0.0.1:3080", listeVientDeLHote: false,
      remplacerFauteDeMieux: false) == nil)
}

@MainActor
@Test("Le modèle coche l'hôte dès que SA liste arrive — le défaut du simulateur")
func leModeleCocheLHote() throws {
  // L'ORDRE EXACT DU LANCEMENT SUR IPHONE, reproduit : adresse de boucle locale,
  // puis la liste publiée par l'hôte (qui s'y marque lui-même). Avant ce
  // correctif, cette suite d'appels laissait `serveurChoisi` à `nil`.
  let modele = modeleDeTest()
  modele.definirAdresse("http://127.0.0.1:3080")
  modele.remplacerServeursPourEssai([hote, mini])

  modele.assurerUneSelectionPourEssai(auLancement: false, listeVientDeLHote: true)

  let choisie = try #require(modele.serveurChoisi)
  #expect(choisie.id == hote.id)
  #expect(choisie.estLocal, "et c'est bien l'hôte qui est coché")
}

@Test("Seule la PREMIÈRE venue remplace la cible : les deux autres attachent")
func seuleLaPremiereRemplace() {
  // LA DISTINCTION QUI A COÛTÉ SIX SESSIONS. Mesuré sur simulateur : attacher
  // l'hôte en passant par `choisir` changeait l'adresse de boucle locale en
  // adresse de tailnet, donc vidait sessions et espaces de travail — pour la
  // seule raison qu'on changeait d'ÉCRITURE d'adresse. Le type le dit, et la vue
  // ne peut plus se tromper de conséquence.
  let faits = [
    SelectionParDefaut.aSelectionner(
      parmi: [hote, mini], adresse: "http://macmini.exemple.ts.net", listeVientDeLHote: false,
      remplacerFauteDeMieux: false),
    SelectionParDefaut.aSelectionner(
      parmi: [hote, mini], adresse: "http://127.0.0.1:3080", listeVientDeLHote: true,
      remplacerFauteDeMieux: false),
  ]
  for cas in faits {
    switch cas {
    case .jointe, .hote: break  // on attache : rien n'est jeté
    default: Issue.record("attendu : une reconnaissance, obtenu : \(String(describing: cas))")
    }
  }
  // Et le troisième cas est bien un CHOIX, celui qui a le droit de remplacer.
  let choix = SelectionParDefaut.aSelectionner(
    parmi: [hote, mini], adresse: "http://127.0.0.1:3080", listeVientDeLHote: false,
    remplacerFauteDeMieux: true)
  #expect(choix == .premiere(hote))
}

@MainActor
@Test("Au LANCEMENT, la page de la machine choisie est ouverte — pas après un appui")
func auLancementLaPageEstOuverte() throws {
  // C'EST LA MOITIÉ DE LA RÈGLE DES DEUX TEMPS QUI SE JOUE ICI. Au lancement,
  // l'écran de droite ne doit pas rester vide : la page de la machine choisie par
  // défaut s'ouvre. Mais un appui sur une AUTRE vignette ne l'ouvre pas — il
  // sélectionne, et c'est le second appui qui ouvre (voir `DetailAffiche`).
  let modele = modeleDeTest()
  modele.definirAdresse("")
  modele.remplacerServeursPourEssai([bureau, mini, portable])
  #expect(modele.serveurOuvert == nil)

  modele.assurerUneSelectionPourEssai(auLancement: true)

  let choisie = try #require(modele.serveurChoisi)
  #expect(modele.serveurOuvert == choisie.id, "la page de la machine choisie est ouverte")
}

@MainActor
@Test("APRÈS une réponse de l'hôte, on n'ouvre AUCUNE page")
func apresUneReponseAucunePage() throws {
  // L'AUTRE MOITIÉ. La liste qui arrive doit donner une coche, pas une fiche :
  // sinon le premier appui sur une autre machine ouvrirait sa page, et le second
  // ne servirait à rien.
  let modele = modeleDeTest()
  modele.definirAdresse("http://127.0.0.1:3080")
  modele.remplacerServeursPourEssai([hote, mini])

  modele.assurerUneSelectionPourEssai(auLancement: false, listeVientDeLHote: true)

  #expect(modele.serveurChoisi?.id == hote.id, "la coche est posée")
  #expect(modele.serveurOuvert == nil, "et AUCUNE page n'est ouverte")
}

@MainActor
@Test("L'ordre du lancement ne change pas le résultat : la page s'ouvre quand même")
func leLancementOuvreQuelQueSoitLOrdre() throws {
  // LE DÉFAUT VU À L'ÉCRAN, ET PAS DÉDUIT. Sur macOS, le chargeur de liste attache
  // la machine AVANT l'appel de lancement : celui-ci trouvait donc une cible déjà
  // choisie, sortait sans rien faire, et le volet de droite affichait l'écran de
  // sélection au lieu de la page. La capture de l'application installée l'a montré.
  let modele = modeleDeTest()
  modele.definirAdresse("http://macbook-air.exemple.ts.net")
  modele.remplacerServeursPourEssai([hote, mini])
  // 1. Le chargeur de liste, comme au démarrage : il attache, il n'ouvre pas.
  modele.assurerUneSelectionPourEssai(auLancement: false)
  #expect(modele.serveurChoisi?.id == hote.id)
  #expect(modele.serveurOuvert == nil)
  // 2. Puis l'étape de lancement, qui doit ouvrir la page de la machine DÉJÀ
  //    sélectionnée.
  modele.assurerUneSelectionPourEssai(auLancement: true)
  #expect(modele.serveurOuvert == hote.id, "la page s'ouvre, quel que soit l'ordre")
}
