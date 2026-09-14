import Foundation
import Testing

@testable import DSHRemoteKit

// LE VOCABULAIRE D'UNE MACHINE, ÉPROUVÉ.
//
// Le panneau latéral et la page disaient le même état avec des mots différents :
// « hors ligne » sous la vignette, « hors ligne sur le tailnet » sous le titre de
// la page. Les mots vivent maintenant dans `EtatMachine`, et ces tests tiennent
// les deux propriétés qui comptent : les deux formes — vignette et page — disent
// la MÊME chose, et la conclusion ne peut pas affirmer le contraire de l'état.

@Test("Les deux formes disent le même état : la vignette abrège, elle ne traduit pas")
func vocabulairePartage() {
  let horsLigne = EtatMachine.decrire(enLigne: false, sertDsh: nil, estLocal: false, court: true)
  #expect(horsLigne.texte == L("hors ligne"))
  // Une machine éteinte n'est pas une panne : c'est une attente, pas un échec.
  #expect(horsLigne.ton == .attente)

  let hote = EtatMachine.decrire(enLigne: true, sertDsh: true, estLocal: true, court: true)
  #expect(hote.texte == L("DSH · hôte"))
  #expect(hote.ton == .pret)

  // La page dit la phrase entière — MÊMES MOTS, et même gravité : la longueur ne
  // change pas le verdict, sinon les deux vues finiraient par se contredire.
  let hoteLong = EtatMachine.decrire(enLigne: true, sertDsh: true, estLocal: true, court: false)
  #expect(hoteLong.texte.contains("DSH"))
  #expect(hoteLong.texte.contains(L("DSH · hôte interrogé")))
  #expect(hoteLong.ton == hote.ton)

  let sansDsh = EtatMachine.decrire(enLigne: true, sertDsh: false, estLocal: false, court: false)
  #expect(sansDsh.texte == L("pas de DSH"))
  #expect(sansDsh.symbole == "exclamationmark.triangle.fill")

  let inconnu = EtatMachine.decrire(enLigne: true, sertDsh: nil, estLocal: false, court: false)
  #expect(inconnu.texte == L("vérification…"))
  #expect(inconnu.ton == .inconnu)
}

@Test("« Revérifier » sait si la page est celle de la machine VISÉE, même saisie à la main")
func adresseVisee() {
  // POURQUOI CETTE COMPARAISON EXISTE. Le bouton « Tester » de la page testait
  // l'adresse du MODÈLE — donc une autre machine quand la page ouverte n'était
  // pas la cible. La page distingue maintenant les deux gestes, et pour cela il
  // lui faut une comparaison qui réponde AUSSI pour une adresse saisie à la
  // main : celle-là n'est dans aucune liste, donc `serveurVise` vaut `nil`.
  let mac = ServeurMac(nom: "MacMini", nomDNS: "macmini.exemple.ts.net", enLigne: true)

  #expect(ModeleApp.vise("http://macmini.exemple.ts.net", mac))
  // La même adresse écrite sans protocole, ou avec une barre finale : c'est la
  // même machine — c'est l'utilisateur qui l'a tapée, pas la découverte.
  #expect(ModeleApp.vise("macmini.exemple.ts.net", mac))
  #expect(ModeleApp.vise("http://macmini.exemple.ts.net/", mac))

  // Une AUTRE machine, et une adresse vide : non. On ne teste pas celle des
  // autres.
  let autre = ServeurMac(nom: "Autre", nomDNS: "autre.exemple.ts.net", enLigne: true)
  #expect(!ModeleApp.vise("http://autre.exemple.ts.net", mac))
  #expect(!ModeleApp.vise("", mac))
  #expect(!ModeleApp.vise("http://macmini.exemple.ts.net", autre))
}

@Test("La conclusion suit l'état, et ne répète pas ce que le titre dit déjà")
func conclusionDuDiagnostic() {
  // HORS LIGNE. La phrase dit le fait ET sa conséquence ; elle ne nomme pas la
  // machine, dont le nom est déjà le titre de la page.
  let horsLigne = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: false, sertDsh: nil, cause: nil)
  let conclusion = EtatMachine.conclusion(enLigne: false, etapes: horsLigne)
  #expect(conclusion.texte.contains(L("hors ligne")))
  #expect(!conclusion.texte.contains("MacBook"))
  #expect(conclusion.ton == .attente)

  // PRÊT : le vert, et la phrase du parcours — une seule vérité pour les deux.
  let pret = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: true, sertDsh: true, cause: nil)
  let conclusionPrete = EtatMachine.conclusion(enLigne: true, etapes: pret)
  #expect(conclusionPrete.texte == EtapesServeur.resume(pret))
  #expect(conclusionPrete.ton == .pret)

  // RIEN DE SU : ni vert ni orange. Annoncer l'un ou l'autre serait affirmer.
  let enCours = EtapesServeur.etapes(
    tailnetDeLAppareil: nil, enLigne: true, sertDsh: nil, cause: nil)
  #expect(EtatMachine.conclusion(enLigne: true, etapes: enCours).ton == .inconnu)
}
