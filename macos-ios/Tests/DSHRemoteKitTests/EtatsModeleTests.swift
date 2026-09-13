import Foundation
import Testing

@testable import DSHRemoteKit

// INVARIANTS DES DEUX ÉTATS DU MODÈLE.
//
// POURQUOI CES TESTS EXISTENT. Le modèle stockait ces faits dans des champs
// CORRÉLÉS — `sondageEffectue` + `serveursAvecDsh`, `erreur` + `erreurType` +
// `capacites` + `etatAdresse` + `serveurJoint` — dont les combinaisons invalides
// étaient représentables. Deux bugs réels en sont sortis :
//
//   - une sonde ANNULÉE écrivait un verdict vide, effaçant le bon (le journal
//     montrait `fin : 1 DSH` puis `fin : 0 DSH` sans qu'aucune machine change) ;
//   - le TEXTE et le TYPE de l'erreur pouvaient diverger, et la classification
//     par texte a raté le `404` de MacMini.
//
// Ces tests tiennent les invariants qui rendent ces deux-là impossibles.

private let enLigne = ServeurMac(nom: "Portable Un", nomDNS: "portable-un.exemple.ts.net", enLigne: true)

@MainActor
@Test("Une sonde jamais lancée ne dit ni oui ni non")
func sondeInconnue() {
  let modele = ModeleApp()
  #expect(modele.sonde == .inconnue)
  // « Je ne sais pas » n'est pas « non » : c'est tout l'intérêt du troisième cas.
  #expect(modele.sertDsh(enLigne) == nil)
}

@MainActor
@Test("Un verdict CONNU survit à un rafraîchissement en cours")
func verdictConservePendantLeRafraichissement() {
  // C'est l'invariant qui empêche le clignotement : pendant une nouvelle sonde,
  // l'ancien verdict reste lisible. Il était remis à zéro à chaque essai, et les
  // légendes repartaient à « vérification… » toutes les quinze secondes.
  let modele = ModeleApp()
  modele.remplacerSondePourEssai(.connue(ModeleApp.VerdictSonde(serventDsh: [enLigne.id])))

  #expect(modele.sertDsh(enLigne) == true)
  // Une sonde qui démarre sans verdict connu passe par « en cours »…
  let autre = ModeleApp()
  #expect(autre.sonde == .inconnue)
  // …et « en cours » ne conclut pas.
  autre.remplacerSondePourEssai(.enCours)
  #expect(autre.sertDsh(enLigne) == nil)
}

@MainActor
@Test("Un verdict VIDE est un verdict, pas une ignorance")
func verdictVide() {
  // « Personne ne sert DSH » est une conclusion, et elle doit être distinguable
  // de « on ne sait pas » — sinon une liste sans serveur restait en attente.
  let modele = ModeleApp()
  modele.remplacerSondePourEssai(.connue(ModeleApp.VerdictSonde()))
  #expect(modele.sertDsh(enLigne) == false)
}

@MainActor
@Test("Le texte de l'erreur est DÉRIVÉ de son type : ils ne peuvent plus diverger")
func erreurEtSonTexte() {
  let modele = ModeleApp()

  // Une erreur typée porte son texte.
  modele.remplacerConnexionPourEssai(.echec(.reponseInattendue(code: 404)))
  #expect(modele.erreurType != nil)
  #expect(modele.erreur?.contains("404") == true)
  // Et c'est le TYPE qui décide des conséquences — plus jamais le texte.
  #expect(ModeleApp.repondMaisPasDsh(modele.erreurType))
  #expect(modele.serveurJoint == false)

  // Un refus local n'est pas une panne réseau, et il porte son texte aussi.
  modele.remplacerConnexionPourEssai(.incomplete("jeton incomplet : 12 caractères"))
  #expect(modele.erreur == "jeton incomplet : 12 caractères")
  #expect(modele.erreurType == nil)
  #expect(modele.jetonRefuse)

  // Une connexion réussie n'a NI erreur NI texte résiduel.
  modele.remplacerConnexionPourEssai(.inconnue)
  #expect(modele.erreur == nil)
  #expect(modele.erreurType == nil)
  #expect(modele.serveurJoint == false)
}

@MainActor
@Test("Le résultat du test d'adresse est une VUE de la connexion")
func etatAdresseDerive() {
  // Deux stockages pour un même fait, c'était deux occasions de se contredire :
  // l'écran pouvait annoncer « joignable » avec une erreur affichée à côté.
  let modele = ModeleApp()
  modele.remplacerConnexionPourEssai(.enCours)
  #expect(modele.etatAdresse == .enCours)

  modele.remplacerConnexionPourEssai(.echec(.jetonRefuse))
  if case .injoignable = modele.etatAdresse {} else {
    Issue.record("une erreur typée doit se lire « injoignable » dans le test d'adresse")
  }
  #expect(modele.jetonRefuse)
}
