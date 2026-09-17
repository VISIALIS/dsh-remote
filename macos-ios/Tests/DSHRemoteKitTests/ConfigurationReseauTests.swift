import Foundation
import Testing

@testable import DSHRemoteKit

// LA CONFIGURATION RÉSEAU, ET LA DEMANDE D'OUVERTURE DU FLUX.
//
// POURQUOI CES TESTS SONT PURS. Ni l'une ni l'autre ne demande de réseau : ce sont
// des valeurs qu'on construit et qu'on relit. C'est exactement ce qui rend
// observable ce qui ne l'était pas — le client HTTP et le flux avaient DIVERGÉ
// (l'un portait `waitsForConnectivity` et des délais mesurés, l'autre rien), et
// aucune capture d'écran ne peut montrer un drapeau de `URLSessionConfiguration`.

@Test("Les deux clients partagent l'essentiel : pas de cache, pas de cookie")
func configurationPartagee() {
  let requetes = ConfigurationReseau.pourRequetes(delai: Connexion.delaiListe)
  let flux = ConfigurationReseau.pourFlux()

  for (nom, config) in [("requetes", requetes), ("flux", flux)] {
    #expect(config.httpShouldSetCookies == false, "\(nom) : aucun cookie")
    #expect(config.httpCookieAcceptPolicy == .never, "\(nom) : aucun cookie")
    #expect(config.urlCache == nil, "\(nom) : un journal de session n'a rien à faire sur disque")
    #expect(
      config.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData,
      "\(nom) : une réponse périmée induirait l'utilisateur en erreur")
  }
}

@Test("L'attente du réseau va aux REQUÊTES, jamais au flux — c'est une mesure")
func attenteDuReseauReserveeAuxRequetes() {
  // LE DÉFAUT QUE CE TEST FIXE, ET IL A ÉTÉ TROUVÉ EN ÉPROUVANT. Recopier
  // `waitsForConnectivity` dans la configuration du flux — l'« alignement » qui
  // semblait évident — a fait PENDRER le client : vers `http://127.0.0.1:1`, le
  // test de flux a été tué après 90 secondes alors qu'il passait en quelques
  // millisecondes avant. Sur un flux, l'attente de connectivité du système se
  // substitue au lieu de rendre l'échec, et rien ne la borne : le délai de
  // ressource d'un flux vaut sept jours. Le flux a mieux : un échec rapide, et la
  // politique de reconnexion du modèle.
  #expect(
    ConfigurationReseau.pourRequetes(delai: Connexion.delaiSante).waitsForConnectivity,
    "une requête doit attendre le réveil de la radio (mesuré : 6 ms, 412 ms, 6 ms)")
  #expect(
    ConfigurationReseau.pourFlux().waitsForConnectivity == false,
    "un flux doit ÉCHOUER pour que la reconnexion joue, jamais attendre sans borne")
}

@Test("La patience d'une requête est un paramètre ; celle du flux n'en est pas un")
func patiencesDifferentes() {
  let courte = ConfigurationReseau.pourRequetes(delai: Connexion.delaiSante)
  #expect(courte.timeoutIntervalForRequest == Connexion.delaiSante)
  #expect(courte.timeoutIntervalForResource >= 120, "une lecture lente a le droit d'aller jusqu'à deux minutes")

  let flux = ConfigurationReseau.pourFlux()
  #expect(flux.timeoutIntervalForRequest == ConfigurationReseau.delaiPoigneeDeMainFlux)
}

@Test("Le flux n'est PAS coupé au bout de deux minutes — le piège d'un « alignement » naïf")
func leFluxNeSeCoupePasToutesLesDeuxMinutes() {
  // POURQUOI CE TEST EXISTE. « Aligner la configuration du flux sur celle des
  // requêtes » est exactement ce qui a été demandé, et c'est exactement ce qu'il ne
  // faut PAS faire : `timeoutIntervalForResource` borne la durée TOTALE d'une
  // tâche. Recopié depuis `pourRequetes`, il vaudrait 120 secondes — et un direct
  // se romprait toutes les deux minutes, en boucle, avec une reconnexion pour
  // seule trace. La dissymétrie est donc VOULUE, et ce test la fixe.
  let flux = ConfigurationReseau.pourFlux()
  #expect(
    flux.timeoutIntervalForResource > 3600,
    "un flux doit pouvoir vivre des heures : \(flux.timeoutIntervalForResource) secondes")
}

@Test("La demande d'ouverture est un JSON ENCODÉ, pas une chaîne interpolée")
func laDemandeEstEncodee() throws {
  struct Lue: Decodable {
    let type: String
    let session: String
    let depuisSeq: Int?
  }

  let sansReprise = try JSONDecoder().decode(Lue.self, from: Data(FluxSession.demande(identifiant: "session-aaa", depuisSeq: nil).utf8))
  #expect(sansReprise.type == "demarrer")
  #expect(sansReprise.session == "session-aaa")
  #expect(sansReprise.depuisSeq == nil)

  let avecReprise = try JSONDecoder().decode(Lue.self, from: Data(FluxSession.demande(identifiant: "session-aaa", depuisSeq: 42).utf8))
  #expect(avecReprise.depuisSeq == 42)
}

@Test("Un identifiant hostile ne casse plus le JSON du demarrer")
func identifiantHostileResteValide() throws {
  // L'ANCIENNE FORME INTERPOLAIT : `"session":"\(identifiant)"`. Elle marchait par
  // chance, parce qu'un identifiant de session est un `session-<uuid>`. Un
  // identifiant portant un guillemet produisait un JSON invalide — le serveur
  // répondait « premier message attendu: demarrer », c'est-à-dire une panne qui ne
  // nomme pas sa cause — et une barre oblique inverse ou un saut de ligne
  // produisaient pire : un JSON VALIDE décrivant autre chose.
  struct Lue: Decodable {
    let type: String
    let session: String
  }
  let hostile = "session-\"quote\"\\back\nligne"
  let texte = FluxSession.demande(identifiant: hostile, depuisSeq: nil)
  let lue = try JSONDecoder().decode(Lue.self, from: Data(texte.utf8))
  #expect(lue.type == "demarrer")
  #expect(lue.session == hostile, "l'identifiant doit traverser l'encodage intact")
}
