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

// ── `connecter()` LUI-MÊME — la même garde, étendue au réseau ────────────────
//
// Les deux tests ci-dessus éprouvent `appliquerSessions`, déjà gardée. Mais
// `connecter()` écrivait `self.client` et `self.connexion = .jointe(...)` SANS
// AUCUNE garde : la génération n'y était capturée qu'APRÈS l'appel réseau, ce
// qui ne gardait rien (elle valait alors, par construction, la génération
// COURANTE). Un utilisateur qui choisit une machine lente puis, avant sa
// réponse, une machine rapide voyait la réponse tardive de la première écraser
// l'état de la seconde — le même défaut que ces tests corrigent pour les
// sessions, mais pour la connexion elle-même.

/// Une porte à deux temps : elle signale qu'on est ENTRÉ (pour que le test sache
/// que `connecter()` a bien capturé sa génération et atteint le réseau), puis
/// bloque jusqu'à ce qu'on l'OUVRE — sans ça, rien ne garantit que la tentative
/// lente n'atteigne son point de garde qu'après la rapide.
private actor Porte {
  private var estEntre = false
  private var estOuverte = false
  private var continuationEntree: CheckedContinuation<Void, Never>?
  private var continuationSortie: CheckedContinuation<Void, Never>?

  func entrer() async {
    estEntre = true
    continuationEntree?.resume()
    continuationEntree = nil
    guard !estOuverte else { return }
    await withCheckedContinuation { continuationSortie = $0 }
  }

  func attendreEntree() async {
    guard !estEntre else { return }
    await withCheckedContinuation { continuationEntree = $0 }
  }

  func ouvrir() {
    estOuverte = true
    continuationSortie?.resume()
    continuationSortie = nil
  }
}

/// Un client factice dont `verifierSante()` peut être retenue à une porte — le
/// reste échoue franchement, comme dans `TransportFactice` (aucun de ces tests
/// n'a besoin des autres routes).
private struct ClientDeGeneration: ClientDSH {
  let porte: Porte?
  let reponses: Int

  func verifierSante() async throws -> Sante {
    if let porte { await porte.entrer() }
    let json = """
      {"protocole":1,"nom":"dsh-remote","hote":"essai",
       "capacites":{"sessions":true,"journal":true,"flux":true,"ecriture":true,
                    "approbations":true,"decouverte":true,"espaces":true}}
      """
    return try! JSONDecoder().decode(Sante.self, from: Data(json.utf8))
  }

  func listerSessions(limite: Int?) async throws -> ListeSessions {
    ListeSessions(protocole: 1, racine: nil, total: reponses, sessions: [], erreur: nil)
  }

  func listerServeurs() async throws -> ListeServeurs { throw ErreurRemote.reponseInattendue(code: 500) }
  func listerEspaces() async throws -> ListeEspaces { throw ErreurRemote.reponseInattendue(code: 500) }
  func lireSession(_ identifiant: String, demande: DemandeJournal) async throws -> JournalSession {
    throw ErreurRemote.reponseInattendue(code: 500)
  }
  func envoyerPrompt(_ identifiant: String, demande: DemandePrompt) async throws -> ReponsePrompt {
    throw ErreurRemote.reponseInattendue(code: 500)
  }
  func annuler(_ identifiant: String) async throws -> ReponseAnnulation {
    throw ErreurRemote.reponseInattendue(code: 500)
  }
  func echangerAppairage(nom: String) async throws -> AppareilAppaire {
    throw ErreurRemote.reponseInattendue(code: 500)
  }
}

@MainActor
@Test("Une connexion en retard n'écrase pas celle qui a suivi")
func connexionEnRetardNecrasePasLaSuivante() async {
  let lente = ServeurMac(nom: "Lent", nomDNS: "lent.exemple.test", enLigne: true)
  let rapide = ServeurMac(nom: "Rapide", nomDNS: "rapide.exemple.test", enLigne: true)
  let porte = Porte()

  let transport = Connexion(fabrique: { adresse, _, _ in
    adresse.contains("lent")
      ? ClientDeGeneration(porte: porte, reponses: 1)
      : ClientDeGeneration(porte: nil, reponses: 2)
  })

  let gardien = GardienEnMemoire()
  gardien.ecrire(String(repeating: "a", count: 43), pour: IdentiteHote.cle(lente.adresse))
  gardien.ecrire(String(repeating: "b", count: 43), pour: IdentiteHote.cle(rapide.adresse))

  let modele = ModeleApp(gardien: gardien, persistance: persistanceDeTest(), transport: transport)
  modele.remplacerServeursPourEssai([lente, rapide])

  // La machine lente part en premier, et se bloque à la porte — APRÈS avoir
  // capturé sa génération (`connecter()` la capture avant tout `await`).
  modele.choisir(lente)
  let tacheLente = Task { await modele.connecter() }
  await porte.attendreEntree()

  // L'utilisateur change d'avis avant que la réponse lente n'arrive.
  modele.choisir(rapide)
  await modele.connecter()

  guard case .jointe(_, let reponsesApresRapide) = modele.connexion else {
    Issue.record("la machine rapide devait être jointe")
    return
  }
  #expect(reponsesApresRapide == 2)

  // La réponse lente arrive enfin — pour une machine qu'on a quittée.
  await porte.ouvrir()
  await tacheLente.value

  // Elle ne doit RIEN avoir écrasé : ni le client, ni l'état de connexion.
  guard case .jointe(_, let reponsesFinal) = modele.connexion else {
    Issue.record("une réponse périmée a écrasé l'état de la machine rapide")
    return
  }
  #expect(reponsesFinal == 2, "la réponse tardive de la machine lente ne doit pas s'écrire sous la machine rapide")
}
