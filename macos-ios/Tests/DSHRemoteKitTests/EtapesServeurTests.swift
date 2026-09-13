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
  #expect(etapes[0].titre.contains("cet appareil"))
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
  #expect(avecTailscale[1].titre.contains("à ajouter"))
}
