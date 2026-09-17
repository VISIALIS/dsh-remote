import Foundation
import Testing

@testable import DSHRemoteKit

// LA SONDE NE REPOSE PAS LA MÊME QUESTION TOUTES LES QUINZE SECONDES.
//
// POURQUOI CE TEST EXISTE. `chargerServeursDeLhote` est appelée par la boucle de
// synchronisation, toutes les quinze secondes, et elle finissait par
// `sonderLesServeurs()` — qui interroge `/v1/sante` sur CHAQUE machine en ligne.
// Sur un iPhone, cela fait une poignée de requêtes toutes les quinze secondes
// pour un verdict qui ne peut pas changer tant que la liste des machines est la
// même. L'empreinte prévue pour l'éviter (`empreinteServeurs`) existait déjà, et
// son commentaire annonçait cette économie : elle n'était vérifiée que par la vue.
//
// CE QUI EST ÉPROUVÉ ICI : le NOMBRE de sondes réellement parties. Ni le réseau
// ni le simulateur ne peuvent le dire — la fabrique de clients de la sonde est
// donc injectée, et elle compte.
//
// Valeurs FICTIVES et reconnaissables (RÈGLE #0, interdit #8) : domaine réservé
// `.test`, jeton qui dit qu'il est faux. Aucune machine réelle n'est nommée.

// ─────────────────────────────────────────────────────────────────────────────
// Les doublures
// ─────────────────────────────────────────────────────────────────────────────

/// Un client factice : il rend la liste de l'hôte qu'on lui a donnée, et échoue
/// FRANCHEMENT sur tout le reste.
///
/// Un faux qui inventerait des valeurs pour les routes qu'on n'attend pas
/// laisserait passer un appel non prévu : ici, une route non prévue est une
/// erreur visible. Les autres méthodes lèvent, et aucun test ne les appelle.
private final class ClientDeListe: ClientDSH, @unchecked Sendable {
  private let verrou = NSLock()
  private var liste: [ServeurMac]

  init(serveurs: [ServeurMac] = []) { self.liste = serveurs }

  /// Change ce que l'hôte publiera au prochain appel.
  func publier(_ serveurs: [ServeurMac]) {
    verrou.lock()
    defer { verrou.unlock() }
    liste = serveurs
  }

  /// LECTURE SYNCHRONE, ET C'EST NÉCESSAIRE : `NSLock.lock()` est interdit dans un
  /// contexte asynchrone — il bloquerait un fil coopératif. On lit donc la liste
  /// dans une fonction synchrone, et la méthode `async` ne fait que l'appeler.
  private func listeCourante() -> [ServeurMac] {
    verrou.lock()
    defer { verrou.unlock() }
    return liste
  }

  func listerServeurs() async throws -> ListeServeurs {
    ListeServeurs(protocole: 1, serveurs: listeCourante(), diagnostic: nil)
  }

  func verifierSante() async throws -> Sante {
    try JSONDecoder().decode(
      Sante.self,
      from: Data(
        #"{"protocole":1,"nom":"dsh-remote","capacites":{"sessions":true,"journal":true,"flux":true,"ecriture":false,"approbations":false,"decouverte":true,"espaces":true}}"#
          .utf8))
  }

  func listerSessions(limite: Int?) async throws -> ListeSessions {
    try JSONDecoder().decode(ListeSessions.self, from: Data(#"{"protocole":1,"total":0,"sessions":[]}"#.utf8))
  }

  func listerEspaces() async throws -> ListeEspaces {
    try JSONDecoder().decode(ListeEspaces.self, from: Data(#"{"protocole":1,"espaces":[]}"#.utf8))
  }

  func lireSession(_ identifiant: String, demande: DemandeJournal) async throws -> JournalSession {
    throw ErreurRemote.transport("route non prévue dans ce test : lireSession")
  }

  func envoyerPrompt(_ identifiant: String, demande: DemandePrompt) async throws -> ReponsePrompt {
    throw ErreurRemote.transport("route non prévue dans ce test : envoyerPrompt")
  }

  func annuler(_ identifiant: String) async throws -> ReponseAnnulation {
    throw ErreurRemote.transport("route non prévue dans ce test : annuler")
  }

  func echangerAppairage(nom: String) async throws -> AppareilAppaire {
    throw ErreurRemote.transport("route non prévue dans ce test : echangerAppairage")
  }
}

/// L'hôte simulé, ET le compteur de sondes.
///
/// POURQUOI LES DEUX SONT ICI. Une même fabrique sert les deux usages, et c'est ce
/// qui permet de tout compter : le transport du modèle (qui appelle
/// `listerServeurs`) et la sonde (qui fabrique un client PAR candidat) passent par
/// le même objet. Compter les fabrications revient donc à compter les requêtes de
/// sonde — la seule mesure qui dise si l'économie est réelle.
private final class HoteSimule: @unchecked Sendable {
  private let verrou = NSLock()
  private var liste: [ServeurMac]
  private var fabrications = 0
  private let client: ClientDeListe

  init(serveurs: [ServeurMac]) {
    self.liste = serveurs
    self.client = ClientDeListe(serveurs: serveurs)
  }

  var sondes: Int {
    verrou.lock()
    defer { verrou.unlock() }
    return fabrications
  }

  func publier(_ serveurs: [ServeurMac]) {
    verrou.lock()
    liste = serveurs
    verrou.unlock()
    client.publier(serveurs)
  }

  /// Le transport du modèle : un client par adresse, qui porte la liste courante.
  func transport() -> Connexion {
    Connexion(fabrique: { [self] _, _, _ in client })
  }

  /// La sonde : elle fabrique un client PAR CANDIDAT, et c'est ce qu'on compte.
  func sondeur() -> Sonde {
    Sonde(fabrique: { [self] _, _, _ in
      verrou.lock()
      fabrications += 1
      verrou.unlock()
      return client
    })
  }
}

/// Un `ServeurMac` se décode depuis la charge utile de l'hôte : on part donc du
/// JSON, jamais d'un initialiseur écrit pour les tests.
private func machine(_ nom: String, _ nomDNS: String, enLigne: Bool, local: Bool = false) -> ServeurMac {
  let json = #"{"nom":"\#(nom)","nomDNS":"\#(nomDNS)","enLigne":\#(enLigne),"local":\#(local)}"#
  return try! JSONDecoder().decode(ServeurMac.self, from: Data(json.utf8))
}

private let portable = machine("Portable Un", "portable-un.exemple.test", enLigne: true, local: true)
private let bureau = machine("Bureau Mini", "bureau-mini.exemple.test", enLigne: true)
private let bureauDeux = machine("Bureau Deux", "bureau-deux.exemple.test", enLigne: true)
private let eteint = machine("Portable Deux", "portable-deux.exemple.test", enLigne: false)

/// Un jeton de 43 caractères, FICTIF et reconnaissable (RÈGLE #0, interdit #8).
/// Le modèle refuse une saisie incomplète : un test qui ne le respecte pas
/// mesurerait un échec de validation, pas ce qu'il annonce.
private let jetonFictif = String(repeating: "J", count: 36) + String(repeating: "0", count: 7)

/// Un dossier de préférences à jeter : `persistanceDeTest()` (OutilsDeTest.swift)
/// pose un domaine `UserDefaults` neuf, et aucun test n'écrit dans le vrai.

/// Un modèle joint à un hôte qui publie `serveurs`, avec une sonde COMPTÉE.
@MainActor
private func modeleJoint(serveurs: [ServeurMac]) async -> (ModeleApp, HoteSimule) {
  let hote = HoteSimule(serveurs: serveurs)
  let modele = ModeleApp(
    persistance: persistanceDeTest(),
    transport: hote.transport(),
    sondeur: hote.sondeur())
  modele.definirAdresse(portable.adresse)
  // Un jeton de 43 caractères : le modèle refuse une saisie incomplète, et un
  // test qui ne le respecte pas mesure un échec de validation, pas une sonde.
  modele.definirJeton(jetonFictif)
  await modele.connecter()
  return (modele, hote)
}

// ─────────────────────────────────────────────────────────────────────────────
// Les règles
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Test("Une liste de machines INCHANGÉE ne relance pas la sonde")
func listeInchangeeNeSondePas() async {
  let (modele, hote) = await modeleJoint(serveurs: [portable, bureau, eteint])
  let apresConnexion = hote.sondes
  // La connexion a sondé les deux machines EN LIGNE — la troisième est éteinte :
  // interroger une machine que Tailscale dit hors ligne, c'est payer un délai pour
  // un verdict déjà connu.
  #expect(apresConnexion == 2, "deux machines en ligne, donc deux sondes")

  // Trois cycles de synchronisation, comme la boucle de quinze secondes, sans
  // qu'aucune machine n'apparaisse ni ne disparaisse.
  await modele.synchroniserServeurs()
  await modele.synchroniserServeurs()
  await modele.synchroniserServeurs()

  #expect(hote.sondes == apresConnexion, "la même liste ne doit pas être resondee")
}

@MainActor
@Test("Une machine EN PLUS relance la sonde, et une machine EN MOINS aussi")
func listeChangeeRelanceLaSonde() async {
  let (modele, hote) = await modeleJoint(serveurs: [portable, bureau])
  #expect(hote.sondes == 2)

  // UNE MACHINE APPARAÎT : c'est le cas qui doit rouvrir la question — sans cela,
  // la nouvelle venue resterait sans verdict, et sa vignette resterait orange.
  hote.publier([portable, bureau, bureauDeux])
  await modele.synchroniserServeurs()
  #expect(hote.sondes == 5, "trois machines en ligne : trois sondes de plus")

  // UNE MACHINE EN MOINS : même règle, dans l'autre sens.
  hote.publier([portable])
  await modele.synchroniserServeurs()
  #expect(hote.sondes == 6)
}

@MainActor
@Test("Changer de cible oublie ce qui a été sondé")
func changerDeCibleOublieLaSonde() async {
  // POURQUOI. Le constat de sonde a été posé pour les machines que l'hôte
  // PRÉCÉDENT voyait. Le garder ferait sauter la sonde sur le nouvel hôte — qui
  // en voit peut-être d'autres — et les vignettes resteraient sur le verdict de
  // l'ancien réseau.
  let (modele, hote) = await modeleJoint(serveurs: [portable, bureau])
  let depart = hote.sondes
  #expect(depart == 2)

  modele.definirAdresse(bureau.adresse)
  // Le jeton est gardé PAR MACHINE (`JetonParHote`) : un jeton posé pour la
  // première ne vaut pas pour la seconde, et sans celui-ci la connexion échoue en
  // « appareil non appairé » — le test mesurerait un refus de jeton, pas une sonde.
  modele.definirJeton(jetonFictif, pour: bureau.adresse)
  await modele.connecter()

  #expect(hote.sondes > depart, "un nouvel hôte doit être resonde")
}

@Test("L'empreinte de sonde ignore l'ORDRE, mais pas une machine en ligne")
func empreinteDeSondeEstStable() {
  // Version PURE de la règle, éprouvée sans modèle ni réseau. Deux propriétés :
  // l'ordre de la liste ne compte pas (un hôte peut la publier autrement), et un
  // libellé qui change ne compte pas non plus — seule l'IDENTITÉ des machines
  // décide si l'on repose la question.
  let bureauRenomme = machine("Bureau Mini (renommé)", "bureau-mini.exemple.test", enLigne: true)
  #expect(
    ModeleApp.empreinteDeSonde([portable, bureau]) == ModeleApp.empreinteDeSonde([bureau, portable]),
    "l'ordre ne doit pas compter")
  #expect(
    ModeleApp.empreinteDeSonde([portable, bureau]) == ModeleApp.empreinteDeSonde([bureauRenomme, portable]),
    "un libellé qui change ne rouvre pas la question")
  #expect(
    ModeleApp.empreinteDeSonde([portable, bureau]) != ModeleApp.empreinteDeSonde([portable]),
    "une machine en moins doit rouvrir la question")
  // Une liste VIDE a une empreinte, et elle est stable : « aucune machine en
  // ligne » est un état qu'on doit pouvoir retenir, sans le confondre avec
  // « on n'a jamais sondé » (qui vaut `nil` côté modèle).
  #expect(ModeleApp.empreinteDeSonde([]) == ModeleApp.empreinteDeSonde([]))
  #expect(ModeleApp.empreinteDeSonde([]) != ModeleApp.empreinteDeSonde([portable]))
}
