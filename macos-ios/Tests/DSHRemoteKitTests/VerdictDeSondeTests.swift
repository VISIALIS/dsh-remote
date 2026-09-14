import Foundation
import Testing

@testable import DSHRemoteKit

// LE VERDICT DE SONDE DÉCRIT LES MACHINES, PAS LA CIBLE.
//
// LE DÉFAUT, DIT PAR LE PROPRIÉTAIRE : « si je sélectionne le premier serveur, il
// m'affiche bien le nombre de joignables. Par contre dès que je prends les autres
// serveurs, il y a marqué vérification… »
//
// LA CAUSE, ET POURQUOI ELLE ÉTAIT DÉFINITIVE. Choisir une machine remettait le
// verdict à `.inconnue` — au motif que « la liste a changé de source ». C'est faux :
// choisir ne change pas la LISTE, les autres Macs sont toujours là. Or la sonde
// n'est relancée que lorsque l'IDENTITÉ de la liste change
// (`Vues.swift`, `.task(id: empreinteServeurs)`). Le verdict effacé n'était donc
// jamais recalculé : il fallait qu'une machine apparaisse ou disparaisse sur le
// tailnet pour que les vignettes ressortent de « vérification… ».
//
// Ces tests tiennent la règle sans réseau et sans sonde : le verdict posé doit
// survivre à un changement de machine.

private func machine(_ nom: String, _ hote: String, enLigne: Bool = true) -> ServeurMac {
  ServeurMac(nom: nom, nomDNS: hote, enLigne: enLigne)
}

private let air = machine("MacBook Air", "macbook-air.exemple.ts.net")
private let mini = machine("MacMini", "macmini.exemple.ts.net")

@MainActor
@Test("Changer de machine ne POSE PAS les vignettes en « vérification… »")
func leVerdictSurvitAuChangementDeMachine() throws {
  // Le verdict est posé (la sonde a répondu), puis l'utilisateur choisit une autre
  // machine : les légendes doivent RESTER celles du verdict.
  let modele = modeleDeTest()
  modele.remplacerServeursPourEssai([air, mini])
  modele.remplacerSondePourEssai(.connue(Sonde.Verdict(serventDsh: [air.id, mini.id])))
  #expect(modele.sertDsh(air) == true)
  #expect(modele.sertDsh(mini) == true)

  modele.choisir(mini)

  #expect(modele.sertDsh(air) == true, "le verdict d'une AUTRE machine n'a pas à être effacé")
  #expect(modele.sertDsh(mini) == true)
}

@MainActor
@Test("Un verdict VIDE est un verdict : il survit aussi")
func unVerdictVideSurvit() throws {
  // « Aucun Mac ne sert DSH » est une réponse. La remettre à « inconnue » ferait
  // repasser les vignettes à « vérification… » alors que la sonde a conclu — et
  // c'est précisément ce que l'absence de verdict ne doit pas faire.
  let modele = modeleDeTest()
  modele.remplacerServeursPourEssai([air, mini])
  modele.remplacerSondePourEssai(.connue(Sonde.Verdict()))

  modele.choisir(air)

  #expect(modele.sertDsh(mini) == false, "« pas de DSH » reste un verdict, pas un doute")
}

@MainActor
@Test("Sans verdict, la vignette dit bien qu'elle ne sait pas encore")
func sansVerdictOnNeSaitPas() throws {
  // L'AUTRE BORD, et il compte : ce correctif ne doit pas transformer un doute en
  // affirmation. Une sonde qui n'a pas encore répondu rend `nil`.
  let modele = modeleDeTest()
  modele.remplacerServeursPourEssai([air, mini])
  #expect(modele.sertDsh(air) == nil)
  #expect(modele.sertDsh(mini) == nil)
}
