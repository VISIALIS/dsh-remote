import Foundation
import Testing

@testable import DSHRemoteKit

// LE COMPOSEUR DOIT AGIR SUR LA SESSION QU'IL MONTRE.
//
// POURQUOI CES TESTS EXISTENT. Deux défauts trouvés par la revue, tous deux
// invisibles à la compilation :
//
//   - le brouillon était UN SEUL champ pour toutes les sessions : changer de
//     session conservait le texte, qui pouvait donc partir vers une autre ;
//   - l'acquittement faisait `brouillon = ""` APRÈS l'attente réseau, alors que
//     le champ reste modifiable pendant l'envoi : la frappe concurrente — ce que
//     l'utilisateur écrit pendant que son message part — était détruite.
//
// Ce qui se teste ici est la RÈGLE, sans réseau : la clé d'un brouillon, et ce
// qu'un acquittement a le droit de retirer.

@MainActor
private func session(_ identifiant: String) -> SessionListee {
  let json = """
    {"protocole":1,"total":1,"sessions":[
      {"projet":"--x--","dossier":"/d","fichier":"/f","vitesse":1,"vivante":true,
       "id":"\(identifiant)","creeLe":1,"preset":"standard","profondeurDelegation":0,
       "seme":false,"titre":"T","dernierEvenementLe":1,"dernierSeq":1,
       "nbEnregistrements":1,"tronque":false,"statut":"inactif"}]}
    """.data(using: .utf8)!
  return try! JSONDecoder().decode(ListeSessions.self, from: json).sessions[0]
}

@MainActor
@Test("Le brouillon d'une session ne suit pas dans une autre")
func brouillonsSepares() {
  let modele = modeleDeTest()
  modele.definirBrouillon("pour la première", pour: "s1")
  modele.definirBrouillon("pour la seconde", pour: "s2")

  #expect(modele.brouillon(pour: "s1") == "pour la première")
  #expect(modele.brouillon(pour: "s2") == "pour la seconde")
  // Une session jamais écrite n'hérite de PERSONNE : c'est tout l'objet du
  // correctif — un message écrit pour l'une ne doit pas pouvoir partir vers
  // l'autre.
  #expect(modele.brouillon(pour: "s3") == "")
}

@MainActor
@Test("Changer d'hôte ne fait pas hériter d'un brouillon")
func brouillonsParHote() {
  // La clé est le couple HÔTE/session, comme celle du jeton : deux machines
  // peuvent nommer leurs sessions de la même façon, et un texte écrit pour l'une
  // ne doit pas se retrouver sous l'autre.
  let modele = modeleDeTest()
  modele.definirAdresse("http://100.101.102.103:3080")
  modele.definirBrouillon("pour l'hôte A", pour: "s1")

  modele.definirAdresse("http://100.101.102.104:3080")
  #expect(modele.brouillon(pour: "s1") == "")

  // Revenir à l'hôte A retrouve le texte : il n'a pas été perdu, seulement
  // rangé à sa place.
  modele.definirAdresse("http://100.101.102.103:3080")
  #expect(modele.brouillon(pour: "s1") == "pour l'hôte A")
}

@MainActor
@Test("Oublier les messages du composeur ne touche PAS au texte en cours")
func oublierLesMessagesGardeLeTexte() {
  // C'est la régression exacte : `oublierEtatEcriture()` est appelée au
  // changement de session, et elle effaçait le texte — c'est-à-dire le travail
  // de l'utilisateur.
  let modele = modeleDeTest()
  modele.definirBrouillon("un texte en cours", pour: "s1")
  modele.oublierEtatEcriture()
  #expect(modele.brouillon(pour: "s1") == "un texte en cours")
}

@MainActor
@Test("L'acquittement retire ce qui est parti, et RIEN de plus")
func acquittementRetireCeQuiEstParti() {
  let modele = modeleDeTest()
  // 1. Le champ contient encore exactement ce qui est parti : il est vidé.
  modele.definirBrouillon("bonjour", pour: "s1")
  modele.retirerCeQuiEstAcquitte("bonjour", pour: "s1")
  #expect(modele.brouillon(pour: "s1") == "")

  // 2. La frappe a continué pendant l'envoi : seul le préfixe envoyé disparaît,
  //    la suite reste sous les doigts.
  modele.definirBrouillon("bonjour la suite", pour: "s1")
  modele.retirerCeQuiEstAcquitte("bonjour", pour: "s1")
  #expect(modele.brouillon(pour: "s1") == "la suite")

  // 3. Le texte a DIVERGÉ (l'utilisateur a effacé, ou écrit autre chose) : on ne
  //    touche à rien. Effacer reviendrait à détruire un texte que personne n'a
  //    envoyé.
  modele.definirBrouillon("autre chose", pour: "s1")
  modele.retirerCeQuiEstAcquitte("bonjour", pour: "s1")
  #expect(modele.brouillon(pour: "s1") == "autre chose")
}

@MainActor
@Test("Un acquittement ne s'affiche que sous la session qui l'a reçu")
func acquittementScopeALaSession() {
  // Un envoi peut être acquitté APRÈS un changement de session : sans cette
  // règle, le message s'afficherait sous une session qui n'a rien envoyé.
  let modele = modeleDeTest()
  modele.consignerEtatEcriturePourEssai(
    session: "s1", acquittement: "accepté", refus: nil)

  #expect(modele.acquittement(pour: "s1") == "accepté")
  #expect(modele.acquittement(pour: "s2") == nil)

  // Et l'oubli — au changement de session — vaut pour toutes.
  modele.oublierEtatEcriture()
  #expect(modele.acquittement(pour: "s1") == nil)
}

@MainActor
@Test("Un refus ne s'affiche que sous la session qui l'a reçu")
func refusScopeALaSession() {
  let modele = modeleDeTest()
  modele.consignerEtatEcriturePourEssai(
    session: "s2", acquittement: nil, refus: "l'hôte a refusé")

  #expect(modele.refusEcriture(pour: "s2") == "l'hôte a refusé")
  #expect(modele.refusEcriture(pour: "s1") == nil)
}

@MainActor
@Test("« Vide » veut dire « rien qui puisse partir », pas « zéro caractère »")
func videAuxBlancsPres() {
  // Le bouton d'envoi se verrouille sur cette réponse : un champ qui ne contient
  // que des espaces ou un retour à la ligne ne peut rien envoyer, et le laisser
  // actif serait un bouton sans effet.
  let modele = modeleDeTest()
  #expect(modele.brouillonVide(pour: "s1"))
  modele.definirBrouillon("   \n  ", pour: "s1")
  #expect(modele.brouillonVide(pour: "s1"))
  modele.definirBrouillon("a", pour: "s1")
  #expect(!modele.brouillonVide(pour: "s1"))
}

@MainActor
@Test("Un envoi sans texte ne part pas — la règle est vérifiable sans réseau")
func envoiSansTexte() async {
  // Sans texte, `envoyer` rend la main immédiatement : rien n'est tenté, donc
  // rien n'est acquitté ni refusé. C'est le seul cas d'`envoyer` qui puisse être
  // éprouvé sans hôte, et il vaut la peine : c'est celui du bouton verrouillé.
  let modele = modeleDeTest()
  modele.definirBrouillon("   ", pour: "s1")
  await modele.envoyer(session("s1"))
  #expect(modele.acquittement(pour: "s1") == nil)
  #expect(modele.refusEcriture(pour: "s1") == nil)
}
