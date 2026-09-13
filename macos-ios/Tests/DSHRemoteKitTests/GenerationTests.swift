import Foundation
import Testing

@testable import DSHRemoteKit

// UNE RÉPONSE EN VOL N'ÉCRIT PAS DANS UNE AUTRE CIBLE.
//
// Trois boucles (suivi 3 s, serveurs 15 s, flux) et les actions de l'utilisateur
// écrivaient dans le modèle sans que rien ne relie une réponse à la cible qui
// l'avait demandée. Une réponse partie vers l'ANCIENNE machine peut arriver
// APRÈS une bascule : l'écran afficherait les sessions d'un serveur sous le nom
// d'un autre — et rien ne le signalerait.
//
// La règle : chaque départ retient une génération, chaque écriture la vérifie.

private let un = ServeurMac(nom: "Portable Un", nomDNS: "portable-un.exemple.ts.net", enLigne: true)
private let deux = ServeurMac(nom: "Portable Deux", nomDNS: "portable-deux.exemple.ts.net", enLigne: true)

/// Une liste minimale mais COMPLÈTE : les modèles décodent des champs
/// obligatoires (`protocole`, `resume`), et un raccourci de test qui ne les
/// fournit pas échoue à la décodabilité, pas à ce qu'on veut éprouver.
private func liste(_ identifiants: [String]) -> ListeSessions {
  // LE RÉSUMÉ EST APLATI dans l'objet de session par le plugin (`ResumeSession`
  // se décode depuis le MÊME conteneur) : `{"id": …}` au premier niveau, pas
  // `{"resume": {"id": …}}`. Une fixture imbriquée décodait un résumé vide, et
  // l'identifiant devenait « (inconnu) » — c'est le test qui l'a montré.
  let sessions = identifiants.map { #"{"id":"\#($0)"}"# }.joined(separator: ",")
  let json = #"{"protocole":1,"sessions":[\#(sessions)]}"#
  return try! JSONDecoder().decode(ListeSessions.self, from: Data(json.utf8))
}

@MainActor
@Test("Changer de cible invalide les réponses déjà parties")
func laBasculeInvalideLeVol() {
  let modele = ModeleApp(gardien: GardienEnMemoire())
  modele.remplacerServeursPourEssai([un, deux])

  let depart = modele.generationDuDepart()
  #expect(modele.reponseEncoreValable(depart))

  // L'utilisateur change de machine pendant que la réponse voyage.
  modele.choisir(deux)

  #expect(!modele.reponseEncoreValable(depart), "la réponse décrit l'ancienne machine")
}

@MainActor
@Test("Une liste arrivée en retard n'écrase PAS la nouvelle")
func reponseEnRetardRefusee() {
  let modele = ModeleApp(gardien: GardienEnMemoire())
  modele.remplacerServeursPourEssai([un, deux])

  // Une réponse part vers la première machine…
  let depart = modele.generationDuDepart()
  // …et la cible change avant qu'elle n'arrive.
  modele.choisir(deux)

  // Elle arrive : elle ne doit RIEN écrire.
  modele.appliquerSessions(liste(["session-de-un"]), vu: depart)
  #expect(modele.sessions.isEmpty)

  // Une réponse partie APRÈS le changement, elle, écrit normalement.
  modele.appliquerSessions(liste(["session-de-deux"]), vu: modele.generationDuDepart())
  #expect(modele.sessions.map(\.id) == ["session-de-deux"])
}
