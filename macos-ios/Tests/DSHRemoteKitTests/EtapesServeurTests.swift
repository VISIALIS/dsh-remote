import Foundation
import Testing

@testable import DSHRemoteKit

// LE PARCOURS D'UN SERVEUR, ÉPROUVÉ ÉTAPE PAR ÉTAPE.
//
// Ces trois étapes remplacent un diagnostic : elles disent OÙ l'on en est, et
// donc quoi faire ensuite. Une étape affirmée à tort envoie chercher au mauvais
// endroit — publier un port sur un Mac éteint, installer un plugin dont le port
// sera fermé. Les tests tiennent donc surtout les cas où l'on NE SAIT PAS.

private func etat(_ etapes: [EtapesServeur.Etape], _ numero: Int) -> EtapesServeur.Etat? {
  etapes.first { $0.numero == numero }?.etat
}

@Test("Un Mac hors ligne : la première étape reste à franchir, les autres sont INCONNUES")
func macHorsLigne() {
  let etapes = EtapesServeur.etapes(enLigne: false, sertDsh: nil, cause: nil)

  #expect(etat(etapes, 1) == .aFaire)
  // On ne sait RIEN de son port ni de son plugin : une machine éteinte ne dit
  // rien d'elle-même, et l'affirmer enverrait publier un port pour rien.
  #expect(etat(etapes, 2) == .inconnue)
  #expect(etat(etapes, 3) == .inconnue)
  #expect(EtapesServeur.premiereAEtapesFranchir(etapes) == 1)
}

@Test("Port fermé : la deuxième étape est à franchir, la troisième est inconnue")
func portFerme() {
  // `-1004` : la machine répond, mais rien n'écoute sur son port 80.
  let etapes = EtapesServeur.etapes(enLigne: true, sertDsh: false, cause: .rienNEcoute)

  #expect(etat(etapes, 1) == .franchie)
  #expect(etat(etapes, 2) == .aFaire)
  // Le plugin ne peut pas répondre si le port est fermé : on ne l'accuse pas.
  #expect(etat(etapes, 3) == .aFaire)
  #expect(EtapesServeur.premiereAEtapesFranchir(etapes) == 2)
}

@Test("Port ouvert sans plugin : les deux premières sont franchies, la troisième reste")
func portOuvertSansPlugin() {
  // `404` : quelque chose a répondu. C'est la mesure faite sur MacMini, dont le
  // port 80 est publié mais où le plugin n'est pas chargé.
  let etapes = EtapesServeur.etapes(enLigne: true, sertDsh: false, cause: .pluginAbsent)

  #expect(etat(etapes, 1) == .franchie)
  #expect(etat(etapes, 2) == .franchie)
  #expect(etat(etapes, 3) == .aFaire)
  #expect(EtapesServeur.premiereAEtapesFranchir(etapes) == 3)
}

@Test("DSH répond : les trois étapes sont franchies")
func serveurPret() {
  let etapes = EtapesServeur.etapes(enLigne: true, sertDsh: true, cause: nil)

  #expect(etapes.allSatisfy { $0.etat == .franchie })
  #expect(EtapesServeur.premiereAEtapesFranchir(etapes) == nil)
}

@Test("Sonde pas encore rendue : on ne conclut NI sur le port NI sur le plugin")
func sondeEnCours() {
  let etapes = EtapesServeur.etapes(enLigne: true, sertDsh: nil, cause: nil)

  #expect(etat(etapes, 1) == .franchie, "en ligne est un fait de Tailscale, déjà connu")
  #expect(etat(etapes, 2) == .inconnue)
  #expect(etat(etapes, 3) == .inconnue)
  #expect(EtapesServeur.premiereAEtapesFranchir(etapes) == 2)
}

@Test("Une erreur qui n'explique rien ne fait pas conclure sur le port")
func erreurSansCause() {
  // Délai, DNS, ou tout autre échec : la machine ne répond pas, mais on ne sait
  // pas si c'est le port ou le réseau. Dire « le port est fermé » enverrait
  // publier un port qui l'est peut-être déjà — et l'utilisateur ne comprendrait
  // pas que rien ne change.
  let etapes = EtapesServeur.etapes(enLigne: true, sertDsh: false, cause: nil)

  #expect(etat(etapes, 1) == .franchie)
  #expect(etat(etapes, 2) == .inconnue)
  #expect(etat(etapes, 3) == .aFaire, "DSH ne répond pas : le plugin manque, ou n'est pas joignable")
}

@Test("Les étapes sont numérotées dans l'ordre où elles se franchissent")
func ordreDesEtapes() {
  let etapes = EtapesServeur.etapes(enLigne: true, sertDsh: nil, cause: nil)
  #expect(etapes.map(\.numero) == [1, 2, 3])
  #expect(etapes.allSatisfy { !$0.titre.isEmpty && !$0.explication.isEmpty })
}
