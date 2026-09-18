import Foundation
import Testing

@testable import DSHRemoteKit

// L'ACCESSIBILITÉ SE VÉRIFIE ICI, PAS À L'ŒIL.
//
// POURQUOI CES TESTS EXISTENT. Six réviseurs indépendants ont relevé, sans se
// concerter, le même manque : l'information la plus actionnable de
// l'application — « cette session vous attend », « cette étape n'est pas
// franchie » — était portée par une FORME et une COULEUR, jamais par un mot. Un
// lecteur d'écran annonçait donc une liste de sessions sans dire laquelle
// l'attendait.
//
// Ce qui peut être éprouvé sans appareil, c'est le VOCABULAIRE et les RÈGLES :
// le libellé donné à VoiceOver, et la décision de replier une méthode plutôt que
// de la cacher. Ce qui demande un appareil — l'ordre de lecture réel, les
// contrastes — reste à mesurer, et n'est pas affirmé ici.

@Test("Chaque état de session a son mot, et aucun ne ressemble à un autre")
func libellesDesEtats() {
  #expect(EtatSession.rien.libelle == L("au repos"))
  #expect(EtatSession.enCours.libelle == L("tour en cours"))
  #expect(EtatSession.attendReponse.libelle == L("attend votre réponse"))
  #expect(EtatSession.terminee.libelle == L("terminée, pas encore lue"))
  #expect(EtatSession.inconnue.libelle == L("état inconnu"))

  // LES CINQ SONT DISTINCTS, et c'est le fond du sujet : deux états qui se
  // disent pareil sont deux états qu'un lecteur d'écran ne sépare pas — le
  // défaut visuel qu'on répare, transposé tel quel.
  let libelles = Set([
    EtatSession.rien.libelle, EtatSession.enCours.libelle, EtatSession.attendReponse.libelle,
    EtatSession.terminee.libelle, EtatSession.inconnue.libelle,
  ])
  #expect(libelles.count == 5)
}

@Test("Seul « en cours » s'anime — c'est la règle que la vue applique")
func animationReserveeAuTravail() {
  #expect(EtatSession.enCours.anime)
  for etat in [EtatSession.rien, .attendReponse, .terminee, .inconnue] {
    #expect(!etat.anime, "« \(etat.libelle) » ne doit pas tourner en boucle")
  }
}

// MARK: - La ligne d'une session

private func sessionDeTest(
  titre: String, statut: String?, vivante: Bool?, attendReponse: Bool? = nil,
  evenements: Int = 1, quand: Int = 1_700_000_000_000, illisible: String? = nil
) -> SessionListee {
  let attendJSON = attendReponse.map { "\"attendReponse\":\($0)," } ?? ""
  let vivanteJSON = vivante.map { "\($0)" } ?? "null"
  let statutJSON = statut.map { "\"\($0)\"" } ?? "null"
  let illisibleJSON = illisible.map { "\"\($0)\"" } ?? "null"
  let json = """
    {"protocole":1,"total":1,"sessions":[
      {"projet":"--x--","dossier":"/d","fichier":"/f","octets":2048,"modifieLe":1,"vivante":\(vivanteJSON),
       "id":"s1","creeLe":1,"preset":"standard","profondeurDelegation":0,\(attendJSON)
       "seme":false,"titre":"\(titre)","dernierEvenementLe":\(quand),"dernierSeq":1,
       "nbEnregistrements":\(evenements),"tronque":false,"statut":\(statutJSON),
       "illisible":\(illisibleJSON)}]}
    """.data(using: .utf8)!
  return try! JSONDecoder().decode(ListeSessions.self, from: json).sessions[0]
}

@Test("Une ligne annonce son titre, son état, sa matière et son âge")
func libelleDuneLigne() {
  let affiche = AfficheLigneSession(
    session: sessionDeTest(titre: "Corriger le portail", statut: "en_cours", vivante: true),
    rappelDeFin: false)

  #expect(affiche.etat == .enCours)
  let libelle = affiche.libelleAccessible
  #expect(libelle.hasPrefix("Corriger le portail"), "le titre vient en premier : c'est ce qu'on cherche")
  #expect(libelle.contains(L("tour en cours")))
  #expect(libelle.contains("1 événement"))
  #expect(!libelle.contains("événements"), "un seul événement ne se dit pas au pluriel")
}

@Test("Une session au repos ne dit RIEN de son état — le silence est l'information")
func libelleDuneSessionAuRepos() {
  // POURQUOI CE CAS MÉRITE UN TEST. « au repos » est le cas le plus fréquent :
  // l'annoncer sur chaque ligne noierait les deux états qui comptent, et
  // apprendrait à ne plus écouter. La ligne porte donc le titre et la matière,
  // sans état.
  let affiche = AfficheLigneSession(
    session: sessionDeTest(titre: "Veille", statut: "inactif", vivante: true), rappelDeFin: false)

  #expect(affiche.etat == .rien)
  #expect(affiche.libelleAccessible.hasPrefix("Veille"))
  #expect(!affiche.libelleAccessible.contains("au repos"))
}

@Test("Un état INCONNU est annoncé — il ne doit pas passer pour un autre")
func libelleDunEtatInconnu() {
  // `statut: nil` = la session existe sur disque mais pas dans le processus :
  // c'est un « je ne sais pas », qui ne doit ressembler ni à « terminée » ni à
  // « au repos ».
  let affiche = AfficheLigneSession(
    session: sessionDeTest(titre: "Ancienne", statut: nil, vivante: false), rappelDeFin: false)

  #expect(affiche.etat == .inconnue)
  #expect(affiche.libelleAccessible.contains(L("état inconnu")))
}

@Test("Une session qui attend une réponse le DIT, avant tout le reste")
func libelleDuneSessionQuiAttend() {
  let affiche = AfficheLigneSession(
    session: sessionDeTest(
      titre: "Question en attente", statut: "en_cours", vivante: true, attendReponse: true),
    rappelDeFin: false)

  #expect(affiche.etat == .attendReponse)
  #expect(affiche.libelleAccessible.contains(L("attend votre réponse")))
}

@Test("Une ligne illisible le dit aussi à voix haute")
func libelleDuneLigneIllisible() {
  let affiche = AfficheLigneSession(
    session: sessionDeTest(
      titre: "Cassée", statut: "inactif", vivante: true, illisible: "journal illisible"),
    rappelDeFin: false)
  #expect(affiche.libelleAccessible.contains("journal illisible"))
}

// MARK: - La vignette d'une machine

@Test("Une machine annonce le verdict de DSH, pas seulement « en ligne »")
func libelleDuneMachine() {
  // LE DÉFAUT RÉPARÉ : une machine EN LIGNE dont DSH ne répond pas était
  // annoncée « en ligne », c'est-à-dire l'inverse de ce qu'il faut savoir avant
  // d'appuyer — l'appui ne peut rien donner.
  #expect(
    EtatMachine.libelleAccessible(
      nom: "MacMini", enLigne: true, sertDsh: false, estLocal: false, appairage: .absent)
      == "MacMini, " + L("pas de DSH"))
  #expect(
    EtatMachine.libelleAccessible(
      nom: "MacMini", enLigne: true, sertDsh: true, estLocal: false, appairage: .appaire)
      == "MacMini, DSH")
  #expect(
    EtatMachine.libelleAccessible(
      nom: "Mac mini", enLigne: true, sertDsh: true, estLocal: true, appairage: .appaire)
      == "Mac mini, " + L("DSH · hôte interrogé"))
  #expect(
    EtatMachine.libelleAccessible(
      nom: "MacMini", enLigne: false, sertDsh: nil, estLocal: false, appairage: .absent)
      == "MacMini, " + L("hors ligne"))
  #expect(
    EtatMachine.libelleAccessible(
      nom: "MacMini", enLigne: true, sertDsh: nil, estLocal: false, appairage: .absent)
      == "MacMini, " + L("vérification…"))

  // ET L'APPAIRAGE ENTRE DANS LA PHRASE, parce qu'il décide du geste : une
  // machine saine qui n'est pas appairée ne s'annonce plus « pas de DSH » — le
  // mot accusait le Mac d'un manque qui est dans l'appareil.
  #expect(
    EtatMachine.libelleAccessible(
      nom: "MacMini", enLigne: true, sertDsh: true, estLocal: false, appairage: .absent)
      == "MacMini, " + L("à appairer"))
  #expect(
    EtatMachine.libelleAccessible(
      nom: "MacMini", enLigne: true, sertDsh: true, estLocal: false, appairage: .refuse)
      == "MacMini, " + L("jeton refusé"))
}

@Test("Le libellé accessible d'une carte de serveur")
func libelleDeLaCarteDeServeur() {
  let serveur = ServeurMac(nom: "MacMini", nomDNS: "macmini.local", enLigne: true)
  let libelleMachine = EtatMachine.libelleAccessible(
    nom: serveur.nom, enLigne: serveur.enLigne, sertDsh: true, estLocal: false, appairage: .appaire)
  #expect(libelleMachine == "MacMini, DSH")
}
