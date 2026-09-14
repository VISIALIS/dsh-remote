import Foundation
import Testing

@testable import DSHRemoteKit

// Une machine ÉTEINTE ne doit pas être visée.
//
// Défaut mesuré, sur capture du propriétaire : l'application mémorise le dernier
// serveur utilisé et s'y reconnecte au lancement. Ce Mac-là s'est éteint, et
// chaque ouverture lançait donc une requête vers une machine morte — 21 secondes
// d'attente mesurées — avant d'afficher « échec de transport : délai dépassé,
// hôte injoignable ». Un message technique, pour une machine dont le même écran
// affichait déjà « hors ligne ».
//
// Ces tests portent sur la DÉCISION, pas sur le réseau : c'est elle qui doit être
// juste, et elle doit l'être sans rien attendre.

private let enLigne = ServeurMac(nom: "Portable Un", nomDNS: "portable-un.exemple.ts.net", enLigne: true)
private let eteint = ServeurMac(nom: "Portable Deux", nomDNS: "portable-deux.exemple.ts.net", enLigne: false)

@Test("Une cible connue hors ligne est reconnue, avec ou sans protocole")
func cibleHorsLigneReconnue() throws {
  let parc = [enLigne, eteint]

  // L'adresse mémorisée est écrite AVEC protocole par `choisir`…
  #expect(ModeleApp.serveurHorsLigne(adresse: "http://portable-deux.exemple.ts.net", dans: parc)?.nom == "Portable Deux")
  // …mais elle peut aussi être saisie à la main SANS protocole : le client la
  // complète, la comparaison doit faire de même.
  #expect(ModeleApp.serveurHorsLigne(adresse: "portable-deux.exemple.ts.net", dans: parc)?.nom == "Portable Deux")
  // Une barre finale ne doit pas non plus faire échouer la reconnaissance.
  #expect(ModeleApp.serveurHorsLigne(adresse: "http://portable-deux.exemple.ts.net/", dans: parc)?.nom == "Portable Deux")
}

@Test("Une machine EN LIGNE, ou inconnue, n'est jamais écartée")
func cibleEnLigneOuInconnue() {
  let parc = [enLigne, eteint]

  // En ligne : on tente, c'est le but.
  #expect(ModeleApp.serveurHorsLigne(adresse: "http://portable-un.exemple.ts.net", dans: parc) == nil)
  // Adresse saisie à la main, absente de la liste : on ne peut rien affirmer
  // d'une machine qu'on n'a pas vue — une vraie tentative s'impose.
  #expect(ModeleApp.serveurHorsLigne(adresse: "http://inconnu.exemple.ts.net", dans: parc) == nil)
  // Liste vide (découverte pas encore rendue) : aucune conclusion hâtive.
  #expect(ModeleApp.serveurHorsLigne(adresse: "http://portable-deux.exemple.ts.net", dans: []) == nil)
}

@Test("Le message d'une machine éteinte dit l'état et l'action, pas le réseau")
func messageDEtat() {
  let message = ModeleApp.messageHorsLigne(eteint)
  #expect(message.contains("Portable Deux"))
  #expect(message.contains("hors ligne"))
  // Ce qu'on ne veut PLUS lire : un diagnostic de transport, qui décrit ce que
  // le réseau a fait au lieu de ce que l'utilisateur peut faire.
  #expect(!message.contains("délai"))
  #expect(!message.contains("-1001"))
  #expect(!message.contains("transport"))
}

@MainActor
@Test("Le modèle vise la machine éteinte de sa liste, et rien d'autre")
func modeleVise() {
  // On vérifie le contrat public du modèle, sans réseau : c'est `connecter()`
  // qui s'en sert pour refuser une tentative inutile.
  let modele = modeleDeTest()
  modele.definirAdresse("http://portable-deux.exemple.ts.net")
  // Sans liste, aucune conclusion : le modèle tenterait (comportement d'avant,
  // conservé pour une adresse saisie à la main).
  #expect(modele.serveurViseHorsLigne == nil)
}
