import Foundation
import Testing

@testable import DSHRemoteKit

// LE JOURNAL DOIT DIRE LA VÉRITÉ SUR SA SESSION.
//
// POURQUOI CES TESTS EXISTENT. Trois défauts trouvés par la revue, tous les trois
// visibles à l'écran et aucun à la compilation :
//
//   - une lecture ÉCHOUÉE laissait l'ANCIEN journal sous le titre de la NOUVELLE
//     session : les événements d'une conversation affichés sous le nom d'une
//     autre, sans rien pour le signaler ;
//   - une RÉPONSE EN RETARD (changement de session pendant la lecture) pouvait
//     s'appliquer à la session nouvellement ouverte ;
//   - « Développer » n'apparaissait qu'au-delà de 120 caractères alors que la
//     ligne en montre QUATRE : un message de six lignes courtes était tronqué
//     sans aucun bouton pour lire la suite.

private func evenement(_ type: String, seq: Int, donnees: String? = nil) -> EvenementAffiche {
  DecodeurEvenement.afficher(
    EnregistrementJournal(
      type: type, seq: seq, time: 1, corpsBrut: donnees.map { Data($0.utf8) }))
}

/// Un message d'assistant dont le texte est fourni tel quel.
private func message(_ texte: String, seq: Int = 1) -> EvenementAffiche {
  let echappe = texte
    .replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
    .replacingOccurrences(of: "\n", with: "\\n")
  return evenement(
    "assistant/message", seq: seq,
    donnees: #"{"message":{"role":"assistant","content":[{"type":"text","text":"\#(echappe)"}]}}"#)
}

@MainActor
@Test("Le journal appartient à SA session : une réponse en retard ne s'applique pas")
func journalCloisonneParSession() {
  let modele = ModeleApp()
  // La session A est ouverte et chargée.
  modele.remplacerJournalPourEssai([message("pour A")], de: "s1")
  #expect(modele.journal.count == 1)

  // La réponse de A arrive APRÈS qu'on a ouvert B : elle doit être refusée.
  modele.remplacerJournalPourEssai([], de: "s2")
  modele.appliquerJournal([message("pour A", seq: 1), message("pour A", seq: 2)], de: "s1",
    vu: modele.generationDuDepart())
  #expect(modele.journal.isEmpty, "les événements de A ne doivent pas s'afficher sous B")

  // Et la réponse de la session affichée, elle, s'applique.
  modele.appliquerJournal([message("pour B")], de: "s2", vu: modele.generationDuDepart())
  #expect(modele.journal.count == 1)
  #expect(modele.journalPour == "s2")
}

@MainActor
@Test("L'erreur de lecture du journal ne se montre que sous SA session")
func erreurJournalCloisonnee() {
  // LE DÉFAUT RÉPARÉ : l'échec était invisible — la connexion pouvait aller bien,
  // c'est la lecture de CE journal qui échouait — et l'ancien journal restait
  // affiché sous le nouveau titre.
  let modele = ModeleApp()
  modele.remplacerJournalPourEssai([], de: "s2")
  modele.consignerEchecJournal(ErreurRemote.transport("délai dépassé"), pour: "s2")

  #expect(modele.erreurJournal(pour: "s2")?.contains("délai dépassé") == true)
  #expect(modele.erreurJournal(pour: "s1") == nil)
}

@MainActor
@Test("Une réponse valable efface l'erreur de lecture précédente")
func uneRelectureEffaceLErreur() {
  let modele = ModeleApp()
  modele.remplacerJournalPourEssai([], de: "s1")
  modele.consignerEchecJournal(ErreurRemote.transport("délai dépassé"), pour: "s1")
  #expect(modele.erreurJournal(pour: "s1") != nil)

  modele.appliquerJournal([message("enfin")], de: "s1", vu: modele.generationDuDepart())
  #expect(modele.erreurJournal(pour: "s1") == nil)
  #expect(modele.journal.count == 1)
}

// MARK: - Ce qui mérite un bouton « Développer »

@Test("Six lignes courtes méritent « Développer », même sous 120 caractères")
func lignesCourtesTronquees() {
  // LE DÉFAUT EXACT : six lignes de quinze caractères font quatre-vingt-dix
  // caractères — sous l'ancien seuil de 120 —, mais dépassent les QUATRE lignes
  // que la vue affiche. Le texte était donc tronqué sans aucun moyen de le lire.
  let sixLignes = (1...6).map { "ligne \($0)" }.joined(separator: "\n")
  #expect(sixLignes.count < 120)
  #expect(message(sixLignes).estVolumineux, "le bouton doit être offert")
}

@Test("Un message court ne mérite aucun bouton — un bouton sans effet est un mensonge")
func messageCourtSansBouton() {
  #expect(!message("bonjour").estVolumineux)
  #expect(!message("une seule ligne, courte").estVolumineux)
  // Quatre lignes courtes tiennent exactement dans la limite : rien à déplier.
  #expect(!message((1...4).map { "l\($0)" }.joined(separator: "\n")).estVolumineux)
}

@Test("Une longue ligne unique mérite « Développer »")
func ligneLongue() {
  #expect(message(String(repeating: "a", count: 400)).estVolumineux)
}

@Test("Des arguments d'outil volumineux restent repliables")
func argumentsVolumineux() {
  let longs = String(repeating: "x", count: 200)
  let appel = evenement("tool/call", seq: 3, donnees: #"{"name":"read","arguments":"\#(longs)"}"#)
  #expect(appel.estVolumineux)

  let court = evenement("tool/call", seq: 4, donnees: #"{"name":"read","arguments":"{}"}"#)
  #expect(!court.estVolumineux)
}
