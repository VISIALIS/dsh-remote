import Foundation
import Testing

@testable import DSHRemoteKit

// LE PARCOURS D'UN SERVEUR, ÉPROUVÉ ÉTAPE PAR ÉTAPE.
//
// Ces étapes remplacent un diagnostic : elles disent OÙ l'on en est, donc quoi
// faire ensuite. Une étape affirmée à tort envoie chercher au mauvais endroit —
// publier un port sur un Mac éteint, installer un plugin derrière un port fermé.
// Les tests tiennent donc surtout les cas où l'on NE SAIT PAS.

private func etat(_ etapes: [EtapesServeur.Etape], _ numero: Int) -> EtapesServeur.Etat? {
  etapes.first { $0.numero == numero }?.etat
}

@Test("Sans Tailscale sur CET APPAREIL, rien en aval ne se conclut")
func appareilHorsTailnet() {
  // Le propriétaire a demandé cette étape après coup, et elle manquait : sur un
  // iPhone sans Tailscale, les trois autres ne peuvent pas être franchies.
  let etapes = EtapesServeur.etapes(
    tailnetDeLAppareil: false, enLigne: true, sertDsh: true, cause: nil)

  #expect(etat(etapes, 1) == .aFaire)
  // MÊME SI la liste dit une machine en ligne et que la sonde a répondu : depuis
  // un appareil qui ne peut plus rien joindre, ces mesures parlent du passé.
  #expect(etat(etapes, 2) == .inconnue)
  #expect(etat(etapes, 3) == .inconnue)
  #expect(etat(etapes, 4) == .inconnue)
  #expect(EtapesServeur.premiereAEtapesFranchir(etapes) == 1)
}

@Test("Un Mac hors ligne : la deuxième étape reste à franchir, les suivantes sont INCONNUES")
func macHorsLigne() {
  let etapes = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: false, sertDsh: nil, cause: nil)

  #expect(etat(etapes, 1) == .franchie)
  #expect(etat(etapes, 2) == .aFaire)
  // Une machine éteinte ne dit rien de son port ni de son plugin.
  #expect(etat(etapes, 3) == .inconnue)
  #expect(etat(etapes, 4) == .inconnue)
  #expect(EtapesServeur.premiereAEtapesFranchir(etapes) == 2)
}

@Test("L'explication de l'étape 2 SUIT son état — hors ligne ne se dit pas « en ligne »")
func explicationDeLaVisibilite() {
  // Défaut constaté sur capture, sur un Mac éteint : l'étape 2 était déclarée
  // « à faire » et s'expliquait pourtant par « Il est en ligne sur le tailnet,
  // donc la découverte le propose ». Une explication qui contredit son propre
  // titre fait douter du diagnostic entier, et envoie chercher au mauvais
  // endroit : ici, l'utilisateur croyait la machine joignable.
  let horsLigne = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: false, sertDsh: nil, cause: nil)
  let visibilite = horsLigne.first { $0.numero == 2 }
  #expect(visibilite?.etat == .aFaire)
  #expect(visibilite?.explication.contains(L("hors ligne")) == true)
  // La phrase de l'étape franchie ne doit plus pouvoir s'afficher ici.
  #expect(visibilite?.explication.contains("est en ligne") == false)

  // Le cas symétrique reste dit comme avant.
  let enLigne = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: true, sertDsh: nil, cause: nil)
  #expect(enLigne.first { $0.numero == 2 }?.explication == L("Il est en ligne sur le tailnet, donc la découverte le propose."))

  // Et depuis un appareil hors tailnet, on ne peut RIEN dire de la visibilité de
  // ce Mac-là : l'explication le dit, au lieu d'affirmer qu'il est en ligne.
  // C'était le second endroit où la phrase de l'étape franchie s'affichait pour
  // une étape inconnue.
  let dAilleurs = EtapesServeur.etapes(
    tailnetDeLAppareil: false, enLigne: true, sertDsh: true, cause: nil)
  let inconnue = dAilleurs.first { $0.numero == 2 }
  #expect(inconnue?.etat == .inconnue)
  #expect(inconnue?.explication.contains("est en ligne") == false)
}

@Test("Aucune explication n'affirme l'inverse de son état")
func explicationsCoherentesAvecLEtat() {
  // Même règle pour les deux étapes que la sonde juge : une étape « à faire »
  // décrit ce qui EST constaté, pas ce que l'étape franchie voulait dire.
  let portFerme = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: true, sertDsh: false, cause: .rienNEcoute)
  let port = portFerme.first { $0.numero == 3 }
  #expect(port?.etat == .aFaire)
  #expect(port?.explication == L("Rien ne répond sur son port 80 : `tailscale serve` ne le publie pas."))
  #expect(port?.explication.contains("est publié") == false)

  let sansPlugin = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: true, sertDsh: false, cause: .pluginAbsent)
  let plugin = sansPlugin.first { $0.numero == 4 }
  #expect(plugin?.etat == .aFaire)
  #expect(plugin?.explication == L("DSH Remote n'y répond pas : la machine ne peut pas servir l'application."))
  #expect(plugin?.explication.contains("y répond :") == false)
}

@Test("Port fermé : on n'accuse PAS le plugin, qui est peut-être installé")
func portFerme() {
  // `-1004` : la machine répond, mais rien n'écoute sur son port 80.
  let etapes = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: true, sertDsh: false, cause: .rienNEcoute)

  #expect(etat(etapes, 1) == .franchie)
  #expect(etat(etapes, 2) == .franchie)
  #expect(etat(etapes, 3) == .aFaire)
  // Un port fermé ne dit RIEN du plugin : l'envoyer installer derrière un port
  // fermé ferait faire un travail inutile, dans le mauvais ordre.
  #expect(etat(etapes, 4) == .inconnue)
  #expect(EtapesServeur.premiereAEtapesFranchir(etapes) == 3)
}

@Test("Port ouvert sans plugin : seule la quatrième reste")
func portOuvertSansPlugin() {
  // `404` : quelque chose a répondu. C'est la mesure faite sur MacMini, dont le
  // port 80 est publié mais où le plugin n'est pas chargé.
  let etapes = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: true, sertDsh: false, cause: .pluginAbsent)

  #expect(etat(etapes, 1) == .franchie)
  #expect(etat(etapes, 2) == .franchie)
  #expect(etat(etapes, 3) == .franchie)
  #expect(etat(etapes, 4) == .aFaire)
  #expect(EtapesServeur.premiereAEtapesFranchir(etapes) == 4)
}

@Test("DSH répond : les quatre étapes sont franchies")
func serveurPret() {
  let etapes = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: true, sertDsh: true, cause: nil)

  #expect(etapes.allSatisfy { $0.etat == .franchie })
  #expect(EtapesServeur.premiereAEtapesFranchir(etapes) == nil)
}

@Test("Sonde pas encore rendue : on ne conclut NI sur le port NI sur le plugin")
func sondeEnCours() {
  let etapes = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: true, sertDsh: nil, cause: nil)

  #expect(etat(etapes, 1) == .franchie, "constaté localement, déjà connu")
  #expect(etat(etapes, 2) == .franchie, "en ligne est un fait de Tailscale, déjà connu")
  #expect(etat(etapes, 3) == .inconnue)
  #expect(etat(etapes, 4) == .inconnue)
  #expect(EtapesServeur.premiereAEtapesFranchir(etapes) == 3)
}

@Test("Une erreur qui n'explique rien ne fait conclure sur le port")
func erreurSansCause() {
  // Délai, DNS, ou tout autre échec : la machine ne répond pas, mais on ne sait
  // pas si c'est le port ou le réseau. Dire « le port est fermé » enverrait
  // publier un port qui l'est peut-être déjà.
  let etapes = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: true, sertDsh: false, cause: nil)

  #expect(etat(etapes, 2) == .franchie)
  #expect(etat(etapes, 3) == .inconnue)
  #expect(etat(etapes, 4) == .inconnue)
}

@Test("Tant qu'on n'a pas MESURÉ, la première étape est inconnue — pas « à faire »")
func reseauNonMesure() {
  // Défaut corrigé : `false` par défaut affichait « à faire » pour une étape que
  // personne n'avait constatée. Une capture l'a montré — l'ancre de vérification
  // court-circuite le démarrage, donc rien n'était mesuré, et le parcours
  // affirmait que Tailscale n'était pas connecté alors que le Mac l'était.
  let etapes = EtapesServeur.etapes(
    tailnetDeLAppareil: nil, enLigne: true, sertDsh: true, cause: nil)
  #expect(etat(etapes, 1) == .inconnue)
  #expect(EtapesServeur.premiereAEtapesFranchir(etapes) == 1)

  let ajout = EtapesServeur.etapesDAjout(tailnetDeLAppareil: nil)
  #expect(ajout[0].etat == .inconnue)
}

@Test("Les étapes sont numérotées dans l'ordre où elles se franchissent")
func ordreDesEtapes() {
  let etapes = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: true, sertDsh: nil, cause: nil)
  #expect(etapes.map(\.numero) == [1, 2, 3, 4])
  #expect(etapes.allSatisfy { !$0.titre.isEmpty && !$0.explication.isEmpty })
  // Et la première parle bien de l'appareil, pas du Mac visé.
  #expect(etapes[0].titre == L("Tailscale est connecté sur cet appareil"))
}

@Test("La liste d'ajout : seule la première étape se constate d'ici")
func etapesDAjout() {
  // Il n'y a pas encore de machine : les étapes 2 à 4 sont une LISTE de travail,
  // pas un verdict. Seule la première — Tailscale sur cet appareil — se constate.
  let sansTailscale = EtapesServeur.etapesDAjout(tailnetDeLAppareil: false)
  #expect(sansTailscale.map(\.numero) == [1, 2, 3, 4])
  #expect(sansTailscale[0].etat == .aFaire)
  #expect(sansTailscale.dropFirst().allSatisfy { $0.etat == .aFaire })
  #expect(EtapesServeur.premiereAEtapesFranchir(sansTailscale) == 1)

  let avecTailscale = EtapesServeur.etapesDAjout(tailnetDeLAppareil: true)
  #expect(avecTailscale[0].etat == .franchie)
  #expect(EtapesServeur.premiereAEtapesFranchir(avecTailscale) == 2)
  // Les étapes parlent du Mac À AJOUTER, pas d'une machine connue.
  #expect(avecTailscale[1].titre == L("La machine à ajouter est sur le tailnet"))
}

@Test("Les étapes SUIVANT la frontière sont verrouillées")
func verrouDesEtapes() {
  // Demande du propriétaire : « si une étape de goal n'est pas réalisée, les
  // goals suivants sont grisés ». On ne publie pas un port sur un Mac qui n'est
  // pas sur le réseau, et on n'installe pas un plugin derrière un port fermé.
  let portFerme = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: true, sertDsh: false, cause: .rienNEcoute)
  #expect(!EtapesServeur.estVerrouillee(portFerme[0], dans: portFerme), "franchie")
  #expect(!EtapesServeur.estVerrouillee(portFerme[1], dans: portFerme), "franchie")
  #expect(!EtapesServeur.estVerrouillee(portFerme[2], dans: portFerme), "c'est LA frontière")
  #expect(EtapesServeur.estVerrouillee(portFerme[3], dans: portFerme), "après la frontière")

  // Sans frontière — tout est franchi —, plus rien n'est verrouillé.
  let pret = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: true, sertDsh: true, cause: nil)
  #expect(pret.allSatisfy { !EtapesServeur.estVerrouillee($0, dans: pret) })

  // Et le verrou suit la PREMIÈRE non franchie, pas la première « à faire » : une
  // étape inconnue bloque aussi ce qui la suit.
  let inconnu = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: true, sertDsh: nil, cause: nil)
  #expect(!EtapesServeur.estVerrouillee(inconnu[2], dans: inconnu))
  #expect(EtapesServeur.estVerrouillee(inconnu[3], dans: inconnu))
}

@Test("La conclusion du diagnostic distingue prêt, reste à faire, et pas encore su")
func resumeDuDiagnostic() {
  // Un diagnostic se lit par sa conclusion : « ce serveur est-il utilisable ? »
  // est la question, les quatre étapes sont la démonstration.
  let pret = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: true, sertDsh: true, cause: nil)
  #expect(EtapesServeur.resume(pret) == "Ce serveur est prêt.")

  // UNE seule étape : on la NOMME — c'est l'information la plus utile, et elle
  // évite d'avoir à lire la liste pour savoir laquelle.
  let uneSeule = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: true, sertDsh: false, cause: .pluginAbsent)
  #expect(EtapesServeur.resume(uneSeule).contains("une étape"))
  #expect(EtapesServeur.resume(uneSeule).contains("plugin"))

  // PLUSIEURS ÉTAPES À FAIRE : la dérivation n'en produit QU'UNE à la fois — les
  // suivantes sont « inconnue », jamais « à faire » (on ne sait pas encore).
  // Cette liste est donc construite à la main, pour couvrir la branche le jour où
  // les règles changeraient.
  let plusieurs = [
    EtapesServeur.Etape(numero: 1, titre: "a", explication: "a", etat: .franchie),
    EtapesServeur.Etape(numero: 2, titre: "b", explication: "b", etat: .aFaire),
    EtapesServeur.Etape(numero: 3, titre: "c", explication: "c", etat: .aFaire),
    EtapesServeur.Etape(numero: 4, titre: "d", explication: "d", etat: .inconnue),
  ]
  #expect(EtapesServeur.resume(plusieurs) == "Il reste 2 étapes sur 4.")

  // Et la dérivation réelle, elle, ne nomme qu'une étape — c'est la propriété
  // qu'on vient de découvrir en écrivant ce test.
  let uneSeuleAFaire = EtapesServeur.etapes(
    tailnetDeLAppareil: false, enLigne: false, sertDsh: nil, cause: nil)
  #expect(uneSeuleAFaire.filter { $0.etat == .aFaire }.count == 1)

  // Rien de « à faire » mais rien de franchi : on ne sait pas encore. Annoncer
  // « prêt » serait faux, annoncer du travail aussi.
  let enCours = EtapesServeur.etapes(
    tailnetDeLAppareil: nil, enLigne: true, sertDsh: nil, cause: nil)
  #expect(EtapesServeur.resume(enCours) == "Vérification en cours…")
}
