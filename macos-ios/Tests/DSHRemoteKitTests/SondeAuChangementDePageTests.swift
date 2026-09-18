import Foundation
import Testing

@testable import DSHRemoteKit

// RECHARGER LA PAGE REPOSE LA QUESTION — ET PAS TROP SOUVENT.
//
// POURQUOI CE FICHIER EXISTE. Demande du propriétaire : « le diagnostic se met à
// jour à chaque fois qu'on recharge la page ? Ce serait nécessaire ». Il ne
// l'était pas. La sonde ne repartait qu'au lancement, au changement d'ENSEMBLE des
// machines en ligne (l'empreinte de sonde), ou sur « Revérifier ». Or le cas qui
// compte le plus est celui où RIEN ne bouge dans la liste : on installe le plugin
// `dsh-remote` sur la machine d'en face, elle reste en ligne, l'empreinte est
// identique — et la page continue d'annoncer « 4. Le plugin est installé : à
// faire ». Ni rouvrir la page, ni changer de machine puis revenir ne relançaient
// la mesure.
//
// CE QUI EST ÉPROUVÉ ICI, EN DEUX FAMILLES :
//
//   1. la RÈGLE DU DÉLAI DE GARDE, en fonction pure (`sondeDoitRepartir`) : elle
//      décide si une re-sonde demandée par l'AFFICHAGE a lieu. Elle se prouve sans
//      réseau, sans horloge simulée et sans machine — il suffit de lui donner une
//      date ;
//   2. la CONSÉQUENCE OBSERVABLE, sur un hôte simulé : le NOMBRE de sondes
//      réellement parties. C'est la même mesure que `SondeConditionnelleTests`,
//      avec la fabrique de clients de la sonde pour compteur.
//
// Valeurs FICTIVES et reconnaissables (RÈGLE #0, interdit #8) : domaine réservé
// `.test`, jeton qui dit qu'il est faux. Aucune machine réelle n'est nommée.

// ─────────────────────────────────────────────────────────────────────────────
// Les doublures
// ─────────────────────────────────────────────────────────────────────────────

/// Un client factice qui échoue FRANCHEMENT sur tout ce qu'on ne lui demande pas :
/// un faux qui inventerait une liste laisserait passer un appel non prévu.
private final class ClientDeListe: ClientDSH, @unchecked Sendable {
  func listerServeurs() async throws -> ListeServeurs {
    ListeServeurs(protocole: 1, serveurs: [], diagnostic: nil)
  }

  func verifierSante() async throws -> Sante {
    try JSONDecoder().decode(
      Sante.self,
      from: Data(
        #"{"protocole":1,"nom":"dsh-remote","capacites":{"sessions":true,"journal":true,"flux":true,"ecriture":false,"approbations":false,"decouverte":true,"espaces":true}}"#
          .utf8))
  }

  func listerSessions(limite: Int?) async throws -> ListeSessions {
    try JSONDecoder().decode(
      ListeSessions.self, from: Data(#"{"protocole":1,"total":0,"sessions":[]}"#.utf8))
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

/// Le compteur de sondes : la fabrique de clients de la sonde incrémente à chaque
/// client fabriqué, donc à chaque machine interrogée.
private final class SondeComptee: @unchecked Sendable {
  private let verrou = NSLock()
  private var fabrications = 0
  private let client = ClientDeListe()

  var sondes: Int {
    verrou.lock()
    defer { verrou.unlock() }
    return fabrications
  }

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
private func machine(_ nom: String, _ nomDNS: String, enLigne: Bool = true) -> ServeurMac {
  let json = #"{"nom":"\#(nom)","nomDNS":"\#(nomDNS)","enLigne":\#(enLigne),"local":false}"#
  return try! JSONDecoder().decode(ServeurMac.self, from: Data(json.utf8))
}

private let bureau = machine("Bureau Mini", "bureau-mini.exemple.test")
private let studio = machine("Studio Deux", "studio-deux.exemple.test")

/// Un modèle qui connaît deux machines EN LIGNE, avec une sonde COMPTÉE.
///
/// Aucune connexion n'est faite : la sonde ne dépend pas d'une cible jointe — elle
/// interroge les machines d'un tailnet qui ne sont justement PAS la cible, et sans
/// porteur (voir la règle de sécurité de `sonderLesServeurs`).
@MainActor
private func modeleAvecParc() -> (ModeleApp, SondeComptee) {
  let compteur = SondeComptee()
  let modele = ModeleApp(persistance: persistanceDeTest(), sondeur: compteur.sondeur())
  modele.remplacerServeursPourEssai([bureau, studio])
  return (modele, compteur)
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. La règle du délai de garde — fonction pure
// ─────────────────────────────────────────────────────────────────────────────

@Test("Sans verdict connu, la question se repose TOUJOURS — même à l'instant même")
func sansVerdictOnReposeLaQuestion() {
  // C'EST LA MOITIÉ DE LA RÈGLE QUI COMPTE LE PLUS. Le délai protège un verdict
  // EXISTANT du gaspillage ; il ne doit jamais retenir une question SANS RÉPONSE.
  // Une sonde annulée, une liste qui n'a pas encore été sondée : dans ces cas, il
  // n'y a rien à protéger, et refuser ici reproduirait exactement le défaut qu'on
  // répare — une page qui n'apprend rien.
  let maintenant = Date()
  #expect(
    ModeleApp.sondeDoitRepartir(
      derniere: maintenant, maintenant: maintenant, verdictConnu: false),
    "une sonde vient de partir sans rendre de verdict : on redemande")
  #expect(
    ModeleApp.sondeDoitRepartir(derniere: nil, maintenant: maintenant, verdictConnu: false))
}

@Test("Sans sonde antérieure, la question se repose — il n'y a rien à garder")
func sansSondeAnterieureOnReposeLaQuestion() {
  #expect(
    ModeleApp.sondeDoitRepartir(derniere: nil, maintenant: Date(), verdictConnu: true),
    "aucune mesure n'a jamais eu lieu : la première doit passer")
}

@Test("Un verdict FRAIS n'est pas redemandé avant le seuil")
func verdictFraisNonRedemande() {
  let maintenant = Date()
  // Trois instants SOUS le seuil, dont celui de la mesure elle-même : c'est le cas
  // d'un aller-retour dans la liste, ou d'une page rouverte aussitôt.
  for ecoule in [0.0, 0.5, 2.0, ModeleApp.seuilDeResondage - 0.1] {
    let derniere = maintenant.addingTimeInterval(-ecoule)
    #expect(
      !ModeleApp.sondeDoitRepartir(
        derniere: derniere, maintenant: maintenant, verdictConnu: true),
      "un verdict vieux de \(ecoule) s ne se redemande pas")
  }
}

@Test("Un verdict PÉRIMÉ se redemande — le seuil franchi")
func verdictPerimeRedemande() {
  let maintenant = Date()
  // Le seuil EXACT, puis au-delà : c'est la frontière, et une frontière se prouve
  // des deux côtés. Mesuré sur cette machine : une sonde coûte 16 ms quand la
  // machine répond, 2,5 s au pire quand elle est muette — le seuil borne le pire
  // cas, il n'est donc pas une optimisation de confort.
  for ecoule in [ModeleApp.seuilDeResondage, ModeleApp.seuilDeResondage + 0.1, 60.0, 3600.0] {
    let derniere = maintenant.addingTimeInterval(-ecoule)
    #expect(
      ModeleApp.sondeDoitRepartir(
        derniere: derniere, maintenant: maintenant, verdictConnu: true),
      "un verdict vieux de \(ecoule) s doit être remesuré")
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. La conséquence observable — sur un hôte simulé
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Test("Recharger la page ne resonde pas dans la foulée — le délai de garde tient")
func rechargerLaPageNeResondePasDansLaFoulee() async {
  let (modele, compteur) = modeleAvecParc()

  // Première apparition : rien n'a jamais été sondé, donc la question passe.
  await modele.sonderSiLeDelaiEstPasse()
  let apresPremiere = compteur.sondes
  #expect(apresPremiere == 2, "deux machines en ligne, donc deux sondes")

  // ON ROUVRE LA PAGE TROIS FOIS, comme un aller-retour dans la liste. Le verdict
  // vient d'être posé : aucune de ces ouvertures ne doit repartir sur le réseau.
  await modele.sonderSiLeDelaiEstPasse()
  await modele.sonderSiLeDelaiEstPasse()
  await modele.sonderSiLeDelaiEstPasse()
  #expect(
    compteur.sondes == apresPremiere,
    "un verdict frais ne se redemande pas parce qu'on a rouvert la page")
}

@MainActor
@Test("Après le seuil, rouvrir la page REMESURE — le cas « j'ai installé le plugin »")
func apresLeSeuilLaPageRemesure() async {
  let (modele, compteur) = modeleAvecParc()
  await modele.sonderSiLeDelaiEstPasse()
  let apresPremiere = compteur.sondes
  #expect(apresPremiere == 2)

  // LE TEMPS PASSE, ET RIEN NE BOUGE DANS LA LISTE : c'est exactement la situation
  // du défaut — le plugin vient d'être installé sur la machine d'en face, elle
  // reste en ligne, l'empreinte de sonde est identique. On recule la date de la
  // dernière sonde au lieu d'attendre cinq secondes réelles : la règle porte sur
  // une durée, pas sur une horloge.
  modele.reculerLaDerniereSondePourEssai(secondes: ModeleApp.seuilDeResondage + 1)

  await modele.sonderSiLeDelaiEstPasse()
  #expect(
    compteur.sondes == apresPremiere + 2,
    "le seuil franchi, les deux machines sont réinterrogées")
}

@MainActor
@Test("Un geste explicite ne connaît pas le délai de garde")
func gesteExpliciteIgnoreLeDelai() async {
  // « Revérifier » et le retour au premier plan SAVENT qu'ils veulent du neuf :
  // leur appliquer le délai ferait exactement le défaut qu'on répare — un verdict
  // vieux de plusieurs minutes présenté comme l'état de maintenant.
  let (modele, compteur) = modeleAvecParc()
  await modele.sonderSiLeDelaiEstPasse()
  let apresPremiere = compteur.sondes

  await modele.sonderLesServeurs(enIgnorantLeDelai: true)
  #expect(compteur.sondes == apresPremiere + 2, "la re-sonde forcée repart aussitôt")
}
