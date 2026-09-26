import Foundation
import Testing

@testable import DSHRemoteKit

// LA PORTÉE DU JETON, CÔTÉ APPLICATION.
//
// Le plugin refuse l'écriture d'un jeton en lecture seule avec un 403 dont le
// corps porte la raison. Cette moitié-ci tient deux choses :
//
//   1. le statut et le corps deviennent le BON type d'erreur — 403 sert à deux
//      causes (origine refusée, portée insuffisante), et les confondre afficherait
//      un remède faux ;
//   2. l'écran sait DIRE pourquoi il n'y a pas de composeur, au lieu de le laisser
//      disparaître en silence.
//
// La chaîne « jeton en lecture seule » est un terme du CONTRAT entre les deux
// moitiés : le plugin l'écrit (`tests/portee.test.js`), l'application la
// reconnaît ici.

private func corps(_ json: String) -> Data { Data(json.utf8) }

extension Sante.Capacites {
  /// Les capacités telles que l'hôte les ANNONCE — décodées, pas construites.
  ///
  /// POURQUOI ON DÉCODE PLUTÔT QUE DE CONSTRUIRE. Le type n'a pas d'initialiseur
  /// public : il est fait pour être lu d'une charge utile. Un test qui le
  /// fabriquerait à la main n'éprouverait pas le même chemin que l'application.
  static func annoncees(_ json: String) -> Sante.Capacites {
    try! JSONDecoder().decode(Sante.Capacites.self, from: Data(json.utf8))
  }
}

@Test("Un 403 de PORTÉE devient une erreur d'écriture, pas une erreur d'origine")
func refusDePorteeReconnu() {
  let erreur = RemoteClient.erreur(
    pour: 403,
    donnees: corps(#"{"erreur":"jeton en lecture seule","portee":"lecture","detail":"ce jeton autorise la lecture"}"#))

  guard case .ecritureRefusee = erreur else {
    Issue.record("attendu : ecritureRefusee, obtenu : \(erreur)")
    return
  }
  // LE MESSAGE DOIT NOMMER LE REMÈDE, et il est AILLEURS : la portée se change
  // sur la machine qui héberge le harness. Un message qui laisserait chercher un
  // réglage dans l'application serait un faux remède.
  #expect(erreur.description.contains("DSH_REMOTE_PORTEE=ecriture"))
  #expect(erreur.description.contains("lecture") || erreur.description.contains("read"))
}

@Test("Un 403 sans cette raison reste une origine refusée")
func origineRefuseeInchangee() {
  let sansCorps = RemoteClient.erreur(pour: 403, donnees: Data())
  guard case .origineRefusee = sansCorps else {
    Issue.record("un 403 muet doit rester « origine refusée », obtenu : \(sansCorps)")
    return
  }

  // Un corps qui dit AUTRE CHOSE ne doit pas être pris pour un refus de portée.
  let autre = RemoteClient.erreur(pour: 403, donnees: corps(#"{"erreur":"origine refusee"}"#))
  guard case .origineRefusee = autre else {
    Issue.record("attendu : origineRefusee, obtenu : \(autre)")
    return
  }
}

@Test("Les autres statuts ne changent pas de sens")
func autresStatuts() {
  guard case .jetonRefuse = RemoteClient.erreur(pour: 401, donnees: Data()) else {
    Issue.record("401 doit rester « jeton refusé »")
    return
  }
  guard case let .refusServeur(statut, motif, _) = RemoteClient.erreur(
    pour: 409, donnees: corps(#"{"erreur":"refus","code":"session/agent-busy","detail":"l'agent est occupé"}"#))
  else {
    Issue.record("un 409 avec motif doit rester un refus serveur")
    return
  }
  #expect(statut == 409)
  #expect(motif == "l'agent est occupé")
}

@Test("L'écran sait dire POURQUOI il n'y a pas de composeur")
func raisonSansEcriture() {
  // 1. Un jeton en lecture seule : la cause est la portée, et le remède est sur
  //    la machine qui héberge le harness.
  let lecture = Sante.Capacites.annoncees(#"{"sessions":true,"journal":true,"flux":true,"ecriture":false,"approbations":false}"#)
  let raison = ModeleApp.raisonSansEcriture(capacites: lecture, portee: "lecture")
  #expect(raison == L("Ce jeton lit sans écrire : l'écriture demande un jeton de portée « ecriture », tiré par un harness relancé avec DSH_REMOTE_PORTEE=ecriture."))
  #expect(raison?.contains("DSH_REMOTE_PORTEE=ecriture") == true)

  // 2. Portée non dite (hôte antérieur) : on ne l'INVENTE pas — on dit seulement
  //    que l'hôte n'annonce pas l'écriture.
  let muette = ModeleApp.raisonSansEcriture(capacites: lecture, portee: nil)
  #expect(muette == L("Cet hôte n'annonce pas l'écriture : cette composition ne monte pas le service qui permet d'envoyer un message."))

  // 3. L'écriture est possible : aucune raison à donner.
  let ecriture = Sante.Capacites.annoncees(#"{"sessions":true,"journal":true,"flux":true,"ecriture":true,"approbations":false}"#)
  #expect(ModeleApp.raisonSansEcriture(capacites: ecriture, portee: "ecriture") == nil)

  // 4. Rien n'est joint : il n'y a rien à expliquer encore.
  #expect(ModeleApp.raisonSansEcriture(capacites: nil, portee: nil) == nil)
}
