import Foundation
import Testing

@testable import DSHRemoteKit

// LE JETON EST PAR HÔTE — et il ne voyage pas d'une machine à l'autre.
//
// Le jeton d'appareil est tiré par CHAQUE hôte (mesuré). Le client n'en gardait
// qu'un, sous un compte de trousseau unique : il fallait donc le recopier à
// chaque bascule, et l'oublier revenait à envoyer à une machine le secret d'une
// autre. Ces tests tiennent la règle : un jeton par hôte, et le coffre local ne
// répond QUE pour la machine locale.

// Le gardien des tests est celui de l'application (`GardienEnMemoire`) : les
// tests n'écrivent donc JAMAIS dans un vrai trousseau, et la pièce testée est
// celle qui sert.

private let distant = ServeurMac(
  nom: "MacMini", nomDNS: "macmini.exemple.ts.net", enLigne: true, estLocal: false)
private let autreDistant = ServeurMac(
  nom: "MacStudio", nomDNS: "macstudio.exemple.ts.net", enLigne: true, estLocal: false)
private let local = ServeurMac(
  nom: "Ce Mac", nomDNS: "ce-mac.exemple.ts.net", enLigne: true, estLocal: true)

private let jetonUn = String(repeating: "a", count: 43)
private let jetonDeux = String(repeating: "b", count: 43)

@MainActor
@Test("Chaque hôte a SON jeton, et changer de machine change le jeton")
func unJetonParHote() {
  // DEUX hôtes DISTANTS : ce sont eux dont le jeton doit être retenu. Celui de
  // l'hôte local vient du coffre, et n'est jamais recopié (test suivant).
  let gardien = GardienEnMemoire()
  let modele = ModeleApp(gardien: gardien)
  modele.remplacerServeursPourEssai([distant, autreDistant, local])

  modele.choisir(distant)
  modele.definirJeton(jetonUn)
  modele.choisir(autreDistant)
  modele.definirJeton(jetonDeux)

  // Revenir au premier doit RAPPELER son jeton — sans le recoller : c'est tout
  // l'objet du travail.
  modele.choisir(distant)
  #expect(modele.jetonSaisi == jetonUn)
  modele.choisir(autreDistant)
  #expect(modele.jetonSaisi == jetonDeux)
}

@MainActor
@Test("Le jeton d'un hôte distant est gardé ; celui de l'hôte local n'est pas recopié")
func leLocalNestPasRecopie() {
  let gardien = GardienEnMemoire()
  let modele = ModeleApp(gardien: gardien)
  modele.remplacerServeursPourEssai([distant, local])

  // Distant : gardé, parce que rien d'autre ne peut le retrouver.
  modele.choisir(distant)
  modele.definirJeton(jetonUn)
  #expect(gardien.lire(pour: IdentiteHote.cle(distant.adresse)) == jetonUn)

  // Local : PAS recopié — le coffre du harness est sa source, et une seconde
  // copie d'un secret est une occasion de fuite de plus.
  modele.choisir(local)
  modele.definirJeton(jetonDeux)
  #expect(gardien.lire(pour: IdentiteHote.cle(local.adresse)) == nil)
}

@MainActor
@Test("Effacer le jeton n'efface que celui de l'hôte visé")
func effacerUnSeul() {
  let gardien = GardienEnMemoire()
  let modele = ModeleApp(gardien: gardien)
  modele.remplacerServeursPourEssai([distant, autreDistant])

  modele.choisir(distant)
  modele.definirJeton(jetonUn)
  modele.effacerJeton()

  #expect(modele.jetonSaisi.isEmpty)
  #expect(gardien.lire(pour: IdentiteHote.cle(distant.adresse)) == nil)

  // Le jeton de l'AUTRE hôte, lui, reste intact : effacer ne déborde pas.
  modele.choisir(autreDistant)
  modele.definirJeton(jetonDeux)
  modele.choisir(distant)
  #expect(modele.jetonSaisi.isEmpty, "le jeton effacé ne doit pas revenir")
  modele.choisir(autreDistant)
  #expect(modele.jetonSaisi == jetonDeux, "effacer l'un ne doit pas toucher l'autre")
}

@MainActor
@Test("Le jeton DU CHAMP est utilisé, même sans liste de machines ni gardien")
func leJetonDuChampCompte() {
  // RÉGRESSION MESURÉE, ET CORRIGÉE. En rendant le jeton « par hôte », la
  // fonction qui choisit le jeton à envoyer ne consultait plus le champ : ni le
  // gardien ni le coffre ne connaissaient la valeur, et l'application démarrait
  // en 0 ms sans rien tenter — « aucun jeton » alors que le champ en contenait
  // un. C'est le cas d'un fichier d'amorçage (simulateur) et de toute saisie
  // qui n'a pas encore été soumise.
  let modele = ModeleApp(gardien: GardienEnMemoire())
  modele.definirAdresse("http://127.0.0.1:59999")
  modele.jetonSaisi = jetonUn

  #expect(modele.jetonDeLaCible() == jetonUn)
}
