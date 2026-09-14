import Foundation
import Testing

@testable import DSHRemoteKit

// LE JETON DU COFFRE NE VA QU'À CETTE MACHINE.
//
// LE DÉFAUT, MESURÉ SUR L'APPLICATION INSTALLÉE. Sur macOS, sélectionner MacMini
// répondait `401` en ayant PRÉSENTÉ un jeton de 43 caractères — empreinte
// `cacde495` dans le diagnostic de l'application. Ce jeton était celui du coffre
// LOCAL : MacMini n'en a jamais eu la moitié.
//
// LA CAUSE, ET POURQUOI ELLE ÉTAIT INVISIBLE. La liste publiée par un hôte marque
// SA machine `local: true` — c'est ainsi que l'interface dit « hôte interrogé ».
// `estHoteLocal` lisait ce marqueur dans la liste courante pour décider si
// l'adresse était CELLE DE CET APPAREIL, et le coffre local fait autorité dans ce
// cas seulement. MacMini se marquant lui-même, l'application a conclu que MacMini
// était sa propre machine, et lui a envoyé le secret du coffre.
//
// CONSÉQUENCE : un jeton porteur partait vers un pair du tailnet qui n'aurait
// jamais dû le voir. Il répondait `401` — donc rien n'était cassé en apparence —,
// mais le secret avait voyagé.
//
// CES TESTS PORTENT SUR LA DÉCISION, sans coffre, sans réseau et sans secret.

private func machine(_ nom: String, _ hote: String, local: Bool = false) -> ServeurMac {
  ServeurMac(nom: nom, nomDNS: hote, enLigne: true, estLocal: local)
}

/// Cet appareil, tel que la découverte LOCALE le voit.
private let cetAppareil = machine("MacBook Air", "macbook-air.exemple.ts.net", local: true)
private let macmini = machine("MacMini", "macmini.exemple.ts.net")

@MainActor
@Test("Le marqueur `local` d'une liste REÇUE ne fait pas de l'hôte notre machine")
func leMarqueurRecuNeTrompePlus() {
  // LE CŒUR DU DÉFAUT. La liste vient de MacMini, et MacMini s'y marque `local`
  // (c'est LUI l'hôte interrogé). L'application ne doit pas en conclure que son
  // adresse est la nôtre : c'est faux, et c'est ce qui a fait partir le jeton du
  // coffre local vers un autre Mac.
  let modele = modeleDeTest()
  modele.remplacerServeursPourEssai([machine("MacMini", "macmini.exemple.ts.net", local: true)])

  #expect(modele.estHoteLocal("http://macmini.exemple.ts.net") == false)
  // ET LA CONSÉQUENCE DIRECTE : aucun jeton n'est proposé pour lui — donc aucun
  // n'est envoyé. `jeton(pour:)` ne lit le coffre QUE si `estHoteLocal` est vrai.
  #expect(modele.jeton(pour: "http://macmini.exemple.ts.net").isEmpty)
}

@MainActor
@Test("Les adresses de CET appareil viennent de la découverte LOCALE")
func leFaitLocalVientDeLaDecouverteLocale() {
  // Le seul endroit d'où ce fait peut venir : la découverte locale, qui interroge
  // Tailscale SUR cette machine. Là, et là seulement, `local` veut dire « c'est
  // moi ».
  let modele = modeleDeTest()
  modele.appliquerServeursDuTailnetPourEssai([cetAppareil, macmini])

  #expect(modele.estHoteLocal("http://macbook-air.exemple.ts.net"))
  #expect(modele.estHoteLocal("macbook-air.exemple.ts.net/"), "même adresse, autre écriture")
  #expect(modele.estHoteLocal("http://macmini.exemple.ts.net") == false)
}

@MainActor
@Test("La boucle locale est toujours notre machine, même sans découverte")
func laBoucleLocaleResteLocale() {
  // Sur une machine sans Tailscale, `127.0.0.1` reste le harness de CETTE
  // machine : le jeton du coffre y est légitime.
  let modele = modeleDeTest()
  #expect(modele.estHoteLocal("http://127.0.0.1:3080"))
  #expect(modele.estHoteLocal("localhost:3080"))
  #expect(modele.estHoteLocal("http://[::1]:3080"))
  #expect(modele.estHoteLocal("http://autre.exemple.ts.net") == false)
}

@MainActor
@Test("Une liste d'hôte qui ARRIVE APRÈS ne retire pas le fait local")
func leFaitLocalSurvitALaListeDeLHote() {
  // L'ORDRE RÉEL SUR macOS : on découvre localement (le fait est appris), PUIS on
  // se connecte et l'hôte publie sa liste, qui remplace `serveurs`. Le fait local
  // ne doit pas disparaître avec elle — sans quoi l'application cesserait de
  // reconnaître sa propre machine dès la première réponse de l'hôte, et le Mac ne
  // pourrait plus se connecter à son propre harness.
  let modele = modeleDeTest()
  modele.appliquerServeursDuTailnetPourEssai([cetAppareil, macmini])
  modele.remplacerServeursPourEssai([machine("MacMini", "macmini.exemple.ts.net", local: true)])

  #expect(
    modele.estHoteLocal("http://macbook-air.exemple.ts.net"),
    "notre adresse reste la nôtre, même absente de la liste reçue")
}

@MainActor
@Test("Aucun jeton du coffre n'est PROPOSÉ pour un hôte distant — le remède faux")
func aucunRemedeFauxPourUnHoteDistant() {
  // LA CONSÉQUENCE VISIBLE DU DÉFAUT, ET CE QUE LE PROPRIÉTAIRE A VU. Sur la page
  // de MacMini, l'application annonçait « Le coffre du harness de cette machine
  // contient un AUTRE jeton » et proposait de l'essayer. C'est FAUX : ce coffre est
  // celui de CE Mac. Le bouton copiait donc le jeton local dans le champ de
  // MacMini, qui le refusait en `401` — le secret avait voyagé pour rien.
  //
  // Ce test tient les deux bords SANS coffre et SANS secret : la proposition
  // n'existe pas, et l'adoption ne change rien.
  let modele = modeleDeTest()
  modele.remplacerServeursPourEssai([machine("MacMini", "macmini.exemple.ts.net", local: true)])
  let jetonFictif = "JETONFICTIF-de-macmini-00000000000000000000"
  modele.enregistrerJeton(jetonFictif, pour: "http://macmini.exemple.ts.net")

  #expect(
    modele.jetonDuCoffreDiffert(pour: "http://macmini.exemple.ts.net") == false,
    "aucun coffre de CE Mac ne fait autorité pour un autre Mac")
  modele.adopterLeJetonDuCoffre(pour: "http://macmini.exemple.ts.net")
  #expect(
    modele.jeton(pour: "http://macmini.exemple.ts.net") == jetonFictif,
    "le jeton de l'hôte distant n'est pas remplacé par un secret local")
}
