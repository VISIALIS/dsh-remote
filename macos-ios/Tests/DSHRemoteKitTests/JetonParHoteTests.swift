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
  // LA LISTE PASSE PAR LA VOIE LOCALE, ET C'EST LE POINT. Depuis que « cette
  // machine » ne se décide plus sur un marqueur REÇU (`ModeleApp.estHoteLocal`),
  // une liste posée à la main ne peut plus déclarer qui est l'hôte local : c'est
  // la découverte LOCALE qui l'apprend, et elle seule. Ce test-ci décrit un Mac
  // dressé sur lui-même, donc il emprunte cette voie.
  modele.appliquerServeursDuTailnetPourEssai([distant, local])

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

// MARK: - Ce qu'on détient pour une machine est LE SIEN

@MainActor
@Test("Ce qu'on détient pour une machine AFFICHÉE n'est pas le jeton de la cible")
func jetonDeLaMachineAffichee() {
  // LE DÉFAUT, ET CE QU'IL EST DEVENU. La page d'un serveur peut être ouverte sur
  // un hôte auquel on n'est PAS connecté, et son champ de jeton annonçait « jeton
  // de cet hôte » tout en lisant `jetonSaisi`, qui ne décrit que la cible : le
  // secret d'une machine s'affichait donc sous le nom d'une autre.
  //
  // LE CHAMP A ÉTÉ RETIRÉ (demande du propriétaire), mais la règle qu'il avait
  // fallu corriger reste VRAIE et c'est elle que ce test tient : la lecture par
  // adresse ne rend jamais le secret d'une autre machine. C'est `jetonDetenu`, et
  // elle sert désormais à l'étape d'appairage — donc à ce que la fiche AFFICHE.
  let gardien = GardienEnMemoire()
  let modele = ModeleApp(gardien: gardien)
  modele.remplacerServeursPourEssai([distant, autreDistant])

  modele.choisir(distant)
  modele.definirJeton(jetonUn)  // le jeton de la CIBLE

  // L'AUTRE machine ne doit pas montrer ce secret.
  #expect(modele.jetonDetenu(pour: autreDistant.adresse).isEmpty)

  // Et la cible, elle, le détient — c'est bien le même secret.
  #expect(modele.jetonDetenu(pour: distant.adresse) == jetonUn)
}

@MainActor
@Test("Écrire le jeton d'une autre machine ne touche pas le champ de la cible")
func ecrirePourUneAutreMachine() {
  // LE SECOND VISAGE DU MÊME DÉFAUT : coller un jeton sur la fiche d'un Mac
  // l'envoyait vers `cible.adresse`. Le jeton doit aller à la machine dont on
  // voit la page, et à elle seule.
  let gardien = GardienEnMemoire()
  let modele = ModeleApp(gardien: gardien)
  modele.remplacerServeursPourEssai([distant, autreDistant])

  modele.choisir(distant)
  modele.definirJeton(jetonUn)
  modele.definirJeton(jetonDeux, pour: autreDistant.adresse)

  #expect(gardien.lire(pour: IdentiteHote.cle(autreDistant.adresse)) == jetonDeux)
  // Le champ en mémoire décrit la CIBLE : il n'a pas bougé.
  #expect(modele.jetonSaisi == jetonUn)
  #expect(modele.jetonDeLaCible() == jetonUn)
}

@MainActor
@Test("Effacer le jeton d'une autre machine ne vide pas le champ de la cible")
func effacerPourUneAutreMachine() {
  let gardien = GardienEnMemoire()
  let modele = ModeleApp(gardien: gardien)
  modele.remplacerServeursPourEssai([distant, autreDistant])

  modele.choisir(distant)
  modele.definirJeton(jetonUn)
  modele.definirJeton(jetonDeux, pour: autreDistant.adresse)

  modele.effacerJeton(pour: autreDistant.adresse)

  #expect(gardien.lire(pour: IdentiteHote.cle(autreDistant.adresse)) == nil)
  #expect(modele.jetonDetenu(pour: distant.adresse) == jetonUn, "le jeton de la cible reste")
  #expect(modele.jetonSaisi == jetonUn)
}

@MainActor
@Test("Le jeton de l'hôte local n'est jamais recopié, même écrit par son adresse")
func localJamaisRecopieParAdresse() {
  // La règle existait pour la cible ; elle doit tenir pour une écriture
  // ADRESSÉE, sinon la fiche du Mac local deviendrait un chemin de copie du
  // secret du coffre vers le trousseau.
  let gardien = GardienEnMemoire()
  let modele = ModeleApp(gardien: gardien)
  // Même raison que ci-dessus : la voie LOCALE, parce qu'une liste reçue ne
  // déclare plus qui est cette machine.
  modele.appliquerServeursDuTailnetPourEssai([distant, local])

  modele.definirJeton(jetonUn, pour: local.adresse)
  #expect(gardien.lire(pour: IdentiteHote.cle(local.adresse)) == nil)
}

@Test("La boucle locale se reconnaît, et rien d'autre")
func boucleLocale() {
  // MESURÉ : sur macOS, la découverte est locale et laisse `estLocal` faux pour
  // tout le monde — la machine locale s'y reconnaît par son adresse, puisque le
  // harness n'écoute que sur la boucle locale.
  #expect(ModeleApp.estBoucleLocale("http://127.0.0.1:3080"))
  #expect(ModeleApp.estBoucleLocale("localhost:3080"))
  #expect(ModeleApp.estBoucleLocale("http://[::1]:3080"))
  #expect(!ModeleApp.estBoucleLocale("http://100.101.102.103:3080"))
  #expect(!ModeleApp.estBoucleLocale("http://macmini.exemple.ts.net"))
  #expect(!ModeleApp.estBoucleLocale(""))
}
