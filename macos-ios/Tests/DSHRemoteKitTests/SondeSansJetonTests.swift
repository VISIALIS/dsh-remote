import Foundation
import Testing

@testable import DSHRemoteKit

// LA SONDE PART MÊME SANS JETON — et c'est ce qui rend le diagnostic honnête.
//
// POURQUOI CE FICHIER EXISTE, ET CE QU'IL EMPÊCHE. Il y avait, dans
// `sonderLesServeurs`, une garde : `guard jeton.count == 43`, avec pour raison
// « sans jeton, aucune sonde n'est possible ». La raison était FAUSSE :
// `Sonde.interroger` compte déjà un `401` comme « DSH est là », puisqu'un jeton
// refusé PROUVE que le service a répondu.
//
// Le prix de cette garde était le pire mensonge de l'application : un appareil
// non appairé ne sondait rien, publiait un verdict VIDE, et la vignette en
// concluait « pas de DSH » — donc envoyait installer un plugin DÉJÀ INSTALLÉ sur
// une machine parfaitement prête. C'est le cas le plus fréquent : on installe
// l'application sur un téléphone, le Mac tourne depuis longtemps.
//
// LE TEST MONTE LE VRAI MODÈLE, avec une sonde dont la fabrique rend un `401`
// pour toutes les adresses — exactement ce que répond un hôte prêt à un appareil
// qui n'a pas encore son jeton. Ce n'est donc pas la sonde qui est éprouvée ici
// (elle a ses tests) mais le CHEMIN COMPLET : le modèle, son verdict, et la
// conclusion que la page en tire.

/// Un client qui refuse le jeton, comme le fait un hôte sain devant un inconnu.
private struct ClientQuiRefuseLeJeton: ClientDSH {
  func verifierSante() async throws -> Sante { throw ErreurRemote.jetonRefuse }
  func echangerAppairage(nom: String) async throws -> AppareilAppaire {
    throw ErreurRemote.jetonRefuse
  }
  func listerSessions(limite: Int?) async throws -> ListeSessions { throw ErreurRemote.jetonRefuse }
  func listerServeurs() async throws -> ListeServeurs { throw ErreurRemote.jetonRefuse }
  func listerEspaces() async throws -> ListeEspaces { throw ErreurRemote.jetonRefuse }
  func lireSession(_ identifiant: String, demande: DemandeJournal) async throws -> JournalSession {
    throw ErreurRemote.jetonRefuse
  }
  func envoyerPrompt(_ identifiant: String, demande: DemandePrompt) async throws -> ReponsePrompt {
    throw ErreurRemote.jetonRefuse
  }
  func annuler(_ identifiant: String) async throws -> ReponseAnnulation {
    throw ErreurRemote.jetonRefuse
  }
}

private let macSansJeton = ServeurMac(
  nom: "MacMini", nomDNS: "macmini.exemple.ts.net", enLigne: true)

@MainActor
@Test("Sans jeton rangé, la sonde part quand même : un 401 prouve que DSH est là")
func laSondePartSansJeton() async {
  let modele = ModeleApp(
    gardien: GardienEnMemoire(),
    persistance: persistanceDeTest(),
    sondeur: Sonde(fabrique: { _, _, _ in ClientQuiRefuseLeJeton() }))
  modele.remplacerServeursPourEssai([macSansJeton])
  // LA CIBLE DOIT ÊTRE CETTE MACHINE-LÀ, ET PAS CELLE PAR DÉFAUT. Le modèle part
  // sur l'adresse par défaut (`127.0.0.1`), donc sur la BOUCLE LOCALE : depuis que
  // le coffre ne répond QUE pour la machine qui exécute l'application
  // (`ModeleApp.estHoteLocal`, et `HoteLocalTests`), la boucle locale rend
  // légitimement le jeton du coffre — et le cas « sans jeton » n'était plus
  // éprouvé. Viser la machine distante du test rétablit la prémisse.
  modele.definirAdresse(macSansJeton.adresse)

  #expect(
    modele.jetonDeLaCible().isEmpty,
    "le cas éprouvé est celui d'un appareil SANS jeton : sinon le test ne prouve rien")
  await modele.sonderLesServeurs()

  // LE VERDICT EXISTE, ET IL EST JUSTE : la machine sert DSH.
  #expect(modele.sertDsh(macSansJeton) == true, "un 401 prouve que le service a répondu")
  // ET L'APPAIRAGE EST UN AUTRE FAIT, dit à part.
  #expect(modele.etatAppairage(pour: macSansJeton) == .absent)

  // CE QUE LA PAGE EN CONCLUT — la chaîne complète, jusqu'à la phrase affichée :
  // la machine est prête, et ce qui manque est nommé.
  let etapes = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: macSansJeton.enLigne,
    sertDsh: modele.sertDsh(macSansJeton), cause: nil,
    appairage: modele.etatAppairage(pour: macSansJeton))
  #expect(
    EtapesServeur.resume(etapes)
      == L("Il reste une étape :") + " « \(L("Cet appareil est appairé")) ».")
  // Et surtout PAS « pas de DSH », qui était le mot affiché avant.
  #expect(
    EtatMachine.decrire(
      enLigne: true, sertDsh: modele.sertDsh(macSansJeton), estLocal: false,
      appairage: modele.etatAppairage(pour: macSansJeton), court: true
    ).texte == L("à appairer"))
}

@MainActor
@Test("Un jeton rangé mais refusé se dit « jeton refusé », pas « non appairé »")
func jetonRefuseSeDitRefuse() async {
  // POURQUOI LA DISTINCTION EST DANS LE MODÈLE. Les deux cas mènent au même
  // endroit — le panneau d'appairage —, mais pas avec le même message : le
  // premier dit « prenez un jeton », le second « celui que vous avez n'est pas
  // celui de cette machine ». Confondre les deux ferait recoller un secret
  // étranger en croyant réparer une saisie.
  let modele = ModeleApp(
    gardien: GardienEnMemoire(), persistance: persistanceDeTest(),
    transport: Connexion(fabrique: { _, _, _ in ClientQuiRefuseLeJeton() }))
  modele.remplacerServeursPourEssai([macSansJeton])

  // Un jeton BIEN FORMÉ, celui d'une autre machine : c'est le cas mesuré.
  modele.definirJeton(String(repeating: "a", count: 43), pour: macSansJeton.adresse)
  #expect(modele.etatAppairage(pour: macSansJeton) == .appaire)

  // La connexion le fait refuser — et c'est CE refus qui change le verdict.
  await modele.choisirEtConnecter(macSansJeton)
  #expect(modele.jetonRefuseParLeService)
  #expect(modele.etatAppairage(pour: macSansJeton) == .refuse)
}
