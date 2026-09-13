import Foundation
import Testing

@testable import DSHRemoteKit

// LA BASCULE DE SERVEUR EXIGE UNE PREUVE.
//
// Défaut constaté sur capture, dans le simulateur : l'application était connectée
// à `http://127.0.0.1:58674`, cette adresse répondait, et l'écran annonçait
// pourtant « http://127.0.0.1:58674 ne répond pas : basculé sur … ». La bascule
// se déclenchait dès que l'adresse courante n'était pas une machine DÉCOUVERte et
// en ligne — sans qu'aucune requête ait échoué. Une adresse saisie à la main, une
// adresse de configuration, une instance locale : toutes étaient déclarées mortes
// par simple ignorance.
//
// Ces tests portent sur la DÉCISION, qui doit être juste sans réseau ni attente.

private let enLigne = ServeurMac(nom: "Portable Un", nomDNS: "portable-un.exemple.ts.net", enLigne: true)
private let eteint = ServeurMac(nom: "Portable Deux", nomDNS: "portable-deux.exemple.ts.net", enLigne: false)

private func echec(
  _ adresse: String, _ raison: ModeleApp.EchecCible.Raison = .injoignable
) -> ModeleApp.EchecCible {
  ModeleApp.EchecCible(adresse: adresse, raison: raison)
}

@Test("Sans preuve d'échec, on ne change PAS la machine de l'utilisateur")
func sansPreuveAucuneBascule() {
  // L'adresse courante n'est pas dans la liste (saisie à la main, configuration,
  // instance locale) et rien n'a échoué : on ne touche à rien, et surtout on
  // n'annonce pas qu'elle ne répond pas.
  #expect(
    ModeleApp.cibleDeBascule(
      serveurs: [enLigne, eteint], choisie: nil, echec: nil,
      adresse: "http://127.0.0.1:58674") == nil)
}

@Test("Une machine choisie et EN LIGNE n'est jamais remplacée")
func cibleSaineIntacte() throws {
  #expect(
    ModeleApp.cibleDeBascule(
      serveurs: [enLigne, eteint], choisie: enLigne, echec: echec(enLigne.adresse, .injoignable),
      adresse: enLigne.adresse) == nil)
}

@Test("La machine hors ligne du tailnet est remplacée, sur un fait constaté")
func basculeDepuisHorsLigne() throws {
  let cible = try #require(
    ModeleApp.cibleDeBascule(
      serveurs: [enLigne, eteint], choisie: eteint, echec: echec(eteint.adresse, .horsLigne),
      adresse: eteint.adresse))
  #expect(cible.nom == "Portable Un")
}

@Test("Une tentative réellement ratée autorise la bascule")
func basculeApresEchecReel() throws {
  // Adresse inconnue de la liste, mais une tentative a échoué : la preuve existe.
  let cible = try #require(
    ModeleApp.cibleDeBascule(
      serveurs: [enLigne], choisie: nil, echec: echec("http://inconnu.exemple.ts.net"),
      adresse: "http://inconnu.exemple.ts.net"))
  #expect(cible.nom == "Portable Un")
}

@Test("Une preuve qui concerne une AUTRE adresse ne fait rien basculer")
func preuveHorsSujet() {
  // L'échec consigné portait sur une adresse qu'on a depuis quittée : il ne dit
  // rien de la cible actuelle, et ne doit donc pas la faire remplacer.
  #expect(
    ModeleApp.cibleDeBascule(
      serveurs: [enLigne], choisie: nil, echec: echec("http://127.0.0.1:9999"),
      adresse: "http://127.0.0.1:58674") == nil)
}

@Test("Une machine qui répond AUTRE CHOSE que DSH est reconnue, sans chercher un code dans un texte")
func repondMaisPasDsh() {
  // Deux formes mesurées. `-1004` : rien n'écoute sur le port 80. Un `404` : le
  // port est occupé par autre chose — `tailscale serve` actif mais ne publiant
  // pas DSH, constaté sur MacMini (`HTTP/1.1 404 Not Found`, sans `Server`).
  // Les deux appellent la même explication et la même commande.
  #expect(ModeleApp.repondMaisPasDsh(.transport("échec de transport : … -1004 … | CAUSE: rien n'ecoute")))
  #expect(ModeleApp.repondMaisPasDsh(.reponseInattendue(code: 404)))
  #expect(ModeleApp.repondMaisPasDsh(.reponseInattendue(code: 500)))

  // Ce qui n'est PAS ce cas : une machine injoignable, un jeton refusé, ou rien.
  #expect(!ModeleApp.repondMaisPasDsh(.transport("… -1001 … délai dépassé")))
  #expect(!ModeleApp.repondMaisPasDsh(.jetonRefuse))
  #expect(!ModeleApp.repondMaisPasDsh(nil))
}

@Test("La machine visée par l'adresse est retrouvée, même écrite autrement")
func cibleRetrouvee() {
  // Sert à décider si l'erreur affichée concerne encore la machine courante —
  // et donc si un verdict de sonde peut la contredire. La comparaison doit donc
  // résister aux trois écritures d'une même adresse.
  let parc = [enLigne, eteint]
  #expect(ModeleApp.serveurA(adresse: "http://portable-un.exemple.ts.net", dans: parc)?.nom == "Portable Un")
  #expect(ModeleApp.serveurA(adresse: "portable-un.exemple.ts.net", dans: parc)?.nom == "Portable Un")
  #expect(ModeleApp.serveurA(adresse: "http://portable-un.exemple.ts.net/", dans: parc)?.nom == "Portable Un")
  #expect(ModeleApp.serveurA(adresse: "http://ailleurs.exemple.ts.net", dans: parc) == nil)
}

@Test("Sans aucune machine en ligne, il n'y a nulle part où basculer")
func aucuneCibleEnLigne() {
  #expect(
    ModeleApp.cibleDeBascule(
      serveurs: [eteint], choisie: eteint, echec: echec(eteint.adresse, .horsLigne),
      adresse: eteint.adresse) == nil)
}

@Test("Une machine qui RÉPOND mais ne publie rien n'est jamais quittée d'office")
func sansServiceNeBasculePas() {
  // `-1004` veut dire « la machine est vivante, son port 80 est vide ». C'est le
  // seul cas où l'application sait exactement quoi dire — et quoi faire faire sur
  // cette machine-là. Basculer effaçait ce message au profit d'un avis de
  // bascule : l'utilisateur perdait l'information utile, et la machine qu'il
  // venait de choisir était remplacée sans qu'il l'ait demandé.
  #expect(
    ModeleApp.cibleDeBascule(
      serveurs: [enLigne, eteint], choisie: nil, echec: echec(eteint.adresse, .sansService),
      adresse: eteint.adresse) == nil)
  // Y compris quand la machine visée est celle qui est EN LIGNE.
  #expect(
    ModeleApp.cibleDeBascule(
      serveurs: [enLigne, eteint], choisie: nil,
      echec: echec(enLigne.adresse, .sansService), adresse: enLigne.adresse) == nil)
}
