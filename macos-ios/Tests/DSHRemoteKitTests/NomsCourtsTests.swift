import Foundation
import Testing

@testable import DSHRemoteKit

// LE LIBELLÉ D'UNE VIGNETTE, ÉPROUVÉ.
//
// Le défaut qui a fait écrire ce type est dans les données d'essai de ce dépôt :
// « Portable Un » et « Portable Deux » s'affichaient toutes deux « Portable »,
// alors que l'appui sur une vignette change la connexion. Ces tests tiennent les
// trois propriétés qui comptent : un nom unique reste court, un nom partagé
// s'allonge, et deux vrais homonymes ne sont pas inventés.

private func machine(_ nom: String, _ dns: String) -> ServeurMac {
  ServeurMac(nom: nom, nomDNS: dns, enLigne: true)
}

@Test("Un nom déjà unique garde UN mot, même composé")
func nomUniqueResteCourt() {
  let serveurs = [machine("MacMini", "macmini.exemple.ts.net"), machine("MacStudio Atelier", "studio.exemple.ts.net")]
  let libelles = NomsCourts.libelles(pour: serveurs)

  // « MacMini » n'a qu'un mot : il est rendu tel quel, sans allongement inutile.
  #expect(libelles["macmini.exemple.ts.net"] == "MacMini")
  // « MacStudio » est unique en un mot : la vignette n'affiche pas « MacStudio
  // Atelier », qui serait tronqué à l'écran.
  #expect(libelles["studio.exemple.ts.net"] == "MacStudio")
}

@Test("Deux machines qui partagent leur premier mot s'allongent d'un mot")
func nomPartageSAllonge() {
  let serveurs = [
    machine("Portable Un", "portable-un.exemple.ts.net"),
    machine("Portable Deux", "portable-deux.exemple.ts.net"),
    machine("MacMini", "macmini.exemple.ts.net"),
  ]
  let libelles = NomsCourts.libelles(pour: serveurs)

  // C'est le défaut d'origine, et c'est ce que ce test empêche : deux vignettes
  // identiques alors que l'appui change la connexion.
  #expect(libelles["portable-un.exemple.ts.net"] == "Portable Un")
  #expect(libelles["portable-deux.exemple.ts.net"] == "Portable Deux")
  #expect(libelles["portable-un.exemple.ts.net"] != libelles["portable-deux.exemple.ts.net"])
  // La machine non concernée n'est pas allongée par la collision des autres.
  #expect(libelles["macmini.exemple.ts.net"] == "MacMini")
}

@Test("Deux homonymes stricts gardent le même libellé : on n'invente pas de différence")
func homonymesStricts() {
  let serveurs = [
    machine("MacBook Pro", "macbook-a.exemple.ts.net"),
    machine("MacBook Pro", "macbook-b.exemple.ts.net"),
  ]
  let libelles = NomsCourts.libelles(pour: serveurs)

  // Le tailnet contient réellement deux machines du même nom : la vignette le dit
  // — c'est la vérité —, et c'est VoiceOver qui les distingue par leur nom DNS.
  #expect(libelles["macbook-a.exemple.ts.net"] == "MacBook Pro")
  #expect(libelles["macbook-b.exemple.ts.net"] == "MacBook Pro")
}

@Test("Trois machines, dont deux partagent un mot : seul le groupe concerné s'allonge")
func troisMachinesUnGroupe() {
  let serveurs = [
    machine("Portable Un", "p1.exemple.ts.net"),
    machine("Portable Deux", "p2.exemple.ts.net"),
    machine("Portable", "p3.exemple.ts.net"),
  ]
  let libelles = NomsCourts.libelles(pour: serveurs)

  // Les trois commencent par « Portable » : les deux premiers s'allongent, le
  // troisième n'a rien de plus à donner et garde son mot — il reste ambigu, et
  // c'est bien ce que le tailnet raconte.
  #expect(libelles["p1.exemple.ts.net"] == "Portable Un")
  #expect(libelles["p2.exemple.ts.net"] == "Portable Deux")
  #expect(libelles["p3.exemple.ts.net"] == "Portable")
}

@Test("Une liste vide, ou une seule machine, ne produit rien d'inventé")
func casLimites() {
  #expect(NomsCourts.libelles(pour: []).isEmpty)

  // UNE MACHINE SEULE GARDE UN MOT : rien ne justifie de l'allonger, et c'est la
  // contrainte de place qui commande. Le test a d'abord été écrit avec l'attente
  // inverse — c'est le test qui avait tort, pas la règle.
  let seule = [machine("MacBook Air de Camille", "air.exemple.ts.net")]
  #expect(NomsCourts.libelles(pour: seule)["air.exemple.ts.net"] == "MacBook")

  // Un nom d'un seul mot ne peut pas s'allonger : il est rendu tel quel.
  #expect(NomsCourts.raccourci("MacMini", mots: 2) == "MacMini")
  // Les espaces multiples d'un nom saisi à la main ne créent pas de mot vide.
  #expect(NomsCourts.raccourci("MacBook   Air  de Camille", mots: 2) == "MacBook Air")
}
