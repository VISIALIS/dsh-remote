import Foundation
import Testing

@testable import DSHRemoteKit

// LES ALERTES, ÉPROUVÉES DES DEUX CÔTÉS.
//
// D'un côté la DÉCISION — ce qui mérite une alerte, ce qu'on regroupe, ce qu'on
// tait —, qui est une fonction pure et se relit. De l'autre l'ENVOI, avec un
// canal espion : « aucune alerte quand elles sont éteintes » est une propriété
// qui se vérifie, pas qui se suppose.
//
// Ce qui n'est PAS éprouvé ici, et qui est écrit dans le README : la
// notification réelle du système. Elle demande un paquet signé et une
// autorisation ; un test ne peut ni l'accorder ni la refuser.

// ── La décision ───────────────────────────────────────────────────────────────

@Test("Une attente NOUVELLE alerte ; une attente qui dure ne réalerte pas")
func attenteNouvelleSeulement() {
  // Le défaut que ce test empêche : la liste est rafraîchie toutes les trois
  // secondes, et une session bloquée le reste. Alerter sur l'ÉTAT enverrait
  // vingt notifications par minute.
  #expect(
    Alerte.aEnvoyer(
      attendent: ["s1"], attendaientAvant: ["s1"], terminees: [], termineesAvant: [],
      regardee: nil
    ).isEmpty)

  let nouvelles = Alerte.aEnvoyer(
    attendent: ["s1", "s2"], attendaientAvant: ["s1"], terminees: [], termineesAvant: [],
    regardee: nil)
  #expect(nouvelles.count == 1)
  #expect(nouvelles[0].titre == L("Une session attend votre réponse"))
}

@Test("Plusieurs attentes ensemble font UNE alerte, avec leur compte")
func attentesRegroupees() {
  let alertes = Alerte.aEnvoyer(
    attendent: ["s1", "s2", "s3"], attendaientAvant: [], terminees: [], termineesAvant: [],
    regardee: nil)

  // Cinq notifications identiques apprennent à être ignorées : on en fait une.
  #expect(alertes.count == 1)
  #expect(alertes[0].titre == "3 sessions attendent votre réponse")
}

@Test("On n'alerte pas sur ce qu'on REGARDE")
func sessionRegardeeTaire() {
  // Même règle que le rappel de fin : une notification pour un écran qu'on a sous
  // les yeux est du bruit.
  let alertes = Alerte.aEnvoyer(
    attendent: ["s1"], attendaientAvant: [], terminees: [], termineesAvant: [],
    regardee: "s1")
  #expect(alertes.isEmpty)

  // Mais les AUTRES sessions continuent d'alerter.
  let melange = Alerte.aEnvoyer(
    attendent: ["s1", "s2"], attendaientAvant: [], terminees: [], termineesAvant: [],
    regardee: "s1")
  #expect(melange.count == 1)
  #expect(melange[0].titre == L("Une session attend votre réponse"))
}

@Test("Une fin de tour nouvelle alerte, et l'attente passe AVANT elle")
func finDeTourEtOrdre() {
  let seulementFin = Alerte.aEnvoyer(
    attendent: [], attendaientAvant: [], terminees: ["s1"], termineesAvant: [], regardee: nil)
  #expect(seulementFin.count == 1)
  #expect(seulementFin[0].titre == L("Un tour vient de se terminer"))

  // L'ordre est une décision : l'attente demande une ACTION, la fin est une
  // bonne nouvelle à lire. La première doit se voir en haut de la pile.
  let deux = Alerte.aEnvoyer(
    attendent: ["a"], attendaientAvant: [], terminees: ["b"], termineesAvant: [], regardee: nil)
  #expect(deux.count == 2)
  #expect(deux[0].titre == L("Une session attend votre réponse"))
  #expect(deux[1].titre == L("Un tour vient de se terminer"))
}

@Test("Rien qui change, rien à dire")
func rienAlerter() {
  #expect(
    Alerte.aEnvoyer(
      attendent: [], attendaientAvant: [], terminees: [], termineesAvant: [], regardee: nil
    ).isEmpty)
  // Une fin DÉJÀ connue ne réalerte pas — c'est le rappel de fin, qui se consomme
  // en ouvrant la session.
  #expect(
    Alerte.aEnvoyer(
      attendent: [], attendaientAvant: [], terminees: ["s1"], termineesAvant: ["s1"], regardee: nil
    ).isEmpty)
}

// ── L'envoi ───────────────────────────────────────────────────────────────────

/// Un canal qui retient ce qu'on lui donne, et accorde ce qu'on lui demande.
actor EspionAlerteur: Alerteur {
  private var recues: [Alerte] = []
  private let accorde: Bool

  init(accorde: Bool = true) { self.accorde = accorde }

  func prevenir(_ alerte: Alerte) async { recues.append(alerte) }
  func demanderAutorisation() async -> Bool { accorde }
  func alertes() -> [Alerte] { recues }
}

/// Deux listes de sessions, la seconde avec une session qui ATTEND une réponse.
private func liste(_ attend: Bool) -> ListeSessions {
  let attente = attend ? "true" : "false"
  let json = """
    {"protocole":1,"total":1,"sessions":[
      {"projet":"--x--","dossier":"/d","fichier":"/f","octets":1,"modifieLe":1,"vivante":true,
       "id":"s1","creeLe":1,"preset":"standard","profondeurDelegation":0,
       "seme":false,"titre":"A","dernierEvenementLe":1,"dernierSeq":1,"nbEnregistrements":1,
       "tronque":false,"statut":"en_cours","attendReponse":\(attente)}]}
    """
  return try! JSONDecoder().decode(ListeSessions.self, from: Data(json.utf8))
}

@MainActor
private func modeleAvecEspion(_ espion: EspionAlerteur) -> ModeleApp {
  let nom = UUID().uuidString
  let defaults = UserDefaults(suiteName: nom) ?? .standard
  defaults.removePersistentDomain(forName: nom)
  return ModeleApp(
    persistance: Persistance(defaults: defaults, documents: nil), alerteur: espion)
}

@Test("Alertes ÉTEINTES par défaut : une transition n'envoie rien")
@MainActor
func eteintesParDefaut() async throws {
  let espion = EspionAlerteur()
  let modele = modeleAvecEspion(espion)

  // L'état initial : personne n'a rien demandé, donc rien ne part.
  #expect(!modele.alertesActives)

  // La PREMIÈRE liste n'alerte jamais, même allumées : au lancement, tout est
  // « nouveau » et l'utilisateur a l'écran sous les yeux.
  modele.appliquerSessions(liste(false), vu: modele.generationDuDepart())
  // La seconde porte une attente NOUVELLE — c'est le cas qui alerterait.
  modele.appliquerSessions(liste(true), vu: modele.generationDuDepart())

  try await Task.sleep(nanoseconds: 60_000_000)
  #expect(await espion.alertes().isEmpty, "éteintes, les alertes ne partent pas")
}

@Test("Alertes ALLUMÉES : la première liste se tait, la transition alerte")
@MainActor
func allumeesAlertentSurTransition() async throws {
  let espion = EspionAlerteur()
  let modele = modeleAvecEspion(espion)

  let accordees = await modele.definirAlertes(true)
  #expect(accordees)
  #expect(modele.alertesActives)

  modele.appliquerSessions(liste(false), vu: modele.generationDuDepart())
  try await Task.sleep(nanoseconds: 40_000_000)
  #expect(await espion.alertes().isEmpty, "la première observation n'alerte pas")

  modele.appliquerSessions(liste(true), vu: modele.generationDuDepart())
  try await Task.sleep(nanoseconds: 60_000_000)

  let recues = await espion.alertes()
  #expect(recues.count == 1)
  #expect(recues.first?.titre == L("Une session attend votre réponse"))

  // Et la TROISIÈME liste, identique à la deuxième, n'ajoute rien : c'est le
  // rafraîchissement de trois secondes, pas un nouvel événement.
  modele.appliquerSessions(liste(true), vu: modele.generationDuDepart())
  try await Task.sleep(nanoseconds: 60_000_000)
  #expect(await espion.alertes().count == 1)
}

@Test("Un refus du système laisse l'interrupteur ÉTEINT, et le dit")
@MainActor
func refusLaisseEteint() async {
  let espion = EspionAlerteur(accorde: false)
  let modele = modeleAvecEspion(espion)

  let accordees = await modele.definirAlertes(true)
  // L'interrupteur suit l'état RÉELLEMENT obtenu : afficher « oui » quand rien ne
  // peut partir serait un mensonge d'interface.
  #expect(!accordees)
  #expect(!modele.alertesActives)
}

@Test("L'interrupteur se retrouve au lancement suivant")
@MainActor
func preferencePersistante() async {
  let nom = UUID().uuidString
  let defaults = UserDefaults(suiteName: nom) ?? .standard
  defaults.removePersistentDomain(forName: nom)
  let persistance = Persistance(defaults: defaults, documents: nil)

  let premier = ModeleApp(persistance: persistance, alerteur: EspionAlerteur())
  #expect(!premier.alertesActives, "éteintes par défaut")
  _ = await premier.definirAlertes(true)

  let relu = ModeleApp(persistance: persistance, alerteur: EspionAlerteur())
  #expect(relu.alertesActives, "l'allumage survit à la fermeture")
}
