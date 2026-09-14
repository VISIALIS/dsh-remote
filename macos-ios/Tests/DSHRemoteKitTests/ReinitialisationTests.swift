import Foundation
import Testing

@testable import DSHRemoteKit

// LA RÉINITIALISATION — ce qu'elle efface, et ce qu'elle NE TOUCHE PAS.
//
// POURQUOI CES TESTS EXISTENT. C'est le seul geste IRRÉVERSIBLE de l'application.
// Deux façons de le rater, et les deux sont silencieuses :
//
//   1. il efface MOINS qu'annoncé — par exemple en oubliant le jeton d'une machine
//      qu'on ne visite plus, qui resterait vivant dans le trousseau. L'écran dirait
//      « tout est effacé » en gardant un accès ;
//   2. il efface PLUS qu'annoncé — le fichier d'amorçage, déposé à la main par
//      l'utilisateur, qui n'appartient pas à l'application.
//
// Les tests ci-dessous tiennent les deux bords, et ils éprouvent le COMPTE RENDU :
// un nombre faux est un mensonge affiché.

/// Un dossier de documents jetable, avec ce qu'on veut y trouver.
private func documentsDeTest(amorcage: Bool, diagnostic: Bool) throws -> URL {
  let dossier = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("reset-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
  if amorcage {
    try Data(#"{"adresse":"http://exemple.test","jeton":"faux"}"#.utf8)
      .write(to: dossier.appendingPathComponent(Persistance.nomDuFichierDAmorcage))
  }
  if diagnostic {
    try Data(#"{"message":"essai"}"#.utf8)
      .write(to: dossier.appendingPathComponent(Persistance.nomDuDiagnostic))
  }
  return dossier
}

@MainActor
private func modeleEtGardien(documents: URL) -> (ModeleApp, GardienEnMemoire, Persistance) {
  let gardien = GardienEnMemoire()
  let persistance = persistanceDeTest(documents: documents)
  return (ModeleApp(gardien: gardien, persistance: persistance), gardien, persistance)
}

/// L'état d'un appareil qui a servi : deux machines, des préférences, une session.
@MainActor
private func remplir(_ modele: ModeleApp, _ gardien: GardienEnMemoire, _ persistance: Persistance) {
  gardien.ecrire("JETONFICTIF-un-0000000000000000000000000000000", pour: IdentiteHote.cle("http://un.exemple.test"))
  gardien.ecrire("JETONFICTIF-deux-000000000000000000000000000000", pour: IdentiteHote.cle("http://deux.exemple.test"))
  modele.definirAdresse("http://un.exemple.test")
  modele.enregistrerJeton("JETONFICTIF-un-0000000000000000000000000000000")
  modele.definirModeEnvoi(.steer)
  modele.definirSessionConsultee("session-1")
  persistance.memoriserAlertes(true)
}

@MainActor
@Test("La réinitialisation efface TOUS les jetons, y compris d'hôtes oubliés")
func tousLesJetons() async throws {
  let documents = try documentsDeTest(amorcage: false, diagnostic: false)
  let (modele, gardien, persistance) = modeleEtGardien(documents: documents)
  remplir(modele, gardien, persistance)

  let rapport = await modele.reinitialiser()

  // LE SECOND JETON EST CELUI D'UNE MACHINE QU'ON NE VISITE PLUS : c'est
  // précisément celui qu'une remise à zéro « par hôte connu » laisserait vivre.
  #expect(rapport.jetonsEffaces == 2)
  #expect(gardien.lire(pour: IdentiteHote.cle("http://un.exemple.test")) == nil)
  #expect(gardien.lire(pour: IdentiteHote.cle("http://deux.exemple.test")) == nil)
}

@MainActor
@Test("Elle ramène le modèle à l'état d'un appareil neuf")
func modelePropre() async throws {
  let documents = try documentsDeTest(amorcage: false, diagnostic: false)
  let (modele, gardien, persistance) = modeleEtGardien(documents: documents)
  remplir(modele, gardien, persistance)

  _ = await modele.reinitialiser()

  #expect(modele.adresse.isEmpty, "l'adresse mémorisée part")
  #expect(modele.jetonSaisi.isEmpty, "le champ du jeton aussi")
  #expect(modele.sessions.isEmpty)
  #expect(modele.espacesHote.isEmpty)
  #expect(modele.alertesActives == false)
  // LES PRÉFÉRENCES SONT RELUES DEPUIS LE DOMAINE : elles doivent avoir disparu.
  // `lireAdresse` et `lireNavigation` ne rendent jamais `nil` — un domaine vidé se
  // lit comme une valeur vide, et c'est exactement ce qu'on attend ici.
  #expect(persistance.lireAdresse().adresse.isEmpty)
  #expect(persistance.lireNavigation() == EtatDeNavigation())
  #expect(persistance.lireAlertes() == false)
  // ET LES MIROIRS EN MÉMOIRE DU MODÈLE. Eux seuls décident de ce qui sera
  // réécrit : un modèle qui les garderait remettrait les réglages d'avant sur le
  // disque à la première écriture venue.
  #expect(modele.navigation == EtatDeNavigation())
  #expect(modele.preferences.isEmpty)
}

@MainActor
@Test("Après elle, la première écriture ne ramène PAS les réglages d'avant")
func lesMiroirsNeReviennentPas() async throws {
  // LE DÉFAUT QUE CE TEST TIENT. `toutOublier` retire les clés du disque ; si le
  // modèle garde en mémoire l'état qu'il avait lu, la première écriture — ici un
  // simple espace déplié — réécrit mode d'envoi et session consultée. L'appareil
  // se dit vierge et se réveille avec les réglages d'hier.
  let documents = try documentsDeTest(amorcage: false, diagnostic: false)
  let (modele, gardien, persistance) = modeleEtGardien(documents: documents)
  remplir(modele, gardien, persistance)

  _ = await modele.reinitialiser()
  modele.definirEspacesDeplies(["un/chemin"])

  let relu = persistance.lireNavigation()
  #expect(relu.modeEnvoi == .queue, "le mode d'envoi d'avant ne doit pas revenir")
  #expect(relu.sessionConsultee == nil, "la session consultée d'avant non plus")
  #expect(relu.espacesDeplies == ["un/chemin"], "seule la nouvelle écriture est là")
}

@MainActor
@Test("Elle efface le diagnostic, et le dit")
func diagnosticEfface() async throws {
  let documents = try documentsDeTest(amorcage: false, diagnostic: true)
  let (modele, gardien, persistance) = modeleEtGardien(documents: documents)
  remplir(modele, gardien, persistance)

  let rapport = await modele.reinitialiser()

  #expect(rapport.diagnosticEfface)
  #expect(
    !FileManager.default.fileExists(
      atPath: documents.appendingPathComponent(Persistance.nomDuDiagnostic).path))
}

@MainActor
@Test("Le fichier d'amorçage N'EST PAS effacé — et le compte rendu le dit")
func amorcageConserve() async throws {
  // C'EST LE BORD LE PLUS IMPORTANT DU GESTE. L'application ne crée jamais ce
  // fichier : il a été déposé à la main, et le supprimer serait effacer le travail
  // de quelqu'un d'autre. Mais il RÉ-AMORCERA au lancement suivant — donc une
  // réinitialisation qui se tairait serait un mensonge par omission.
  let documents = try documentsDeTest(amorcage: true, diagnostic: false)
  let (modele, gardien, persistance) = modeleEtGardien(documents: documents)
  remplir(modele, gardien, persistance)

  let rapport = await modele.reinitialiser()

  #expect(rapport.amorcageRestant)
  #expect(
    FileManager.default.fileExists(
      atPath: documents.appendingPathComponent(Persistance.nomDuFichierDAmorcage).path),
    "le fichier d'amorçage ne doit pas être effacé par l'application")
  let texte = modele.texteDuRapport(rapport)
  // LA PHRASE ENTIÈRE, PAS UN MOT : la suite tourne sous un hôte en anglais, donc
  // une chaîne française codée en dur ici ne prouverait rien. On demande à `L` la
  // même clé que le modèle, dans la langue du moment.
  let phrase = L(
    "le fichier d'amorçage est TOUJOURS LÀ : il ramènera l'adresse et le jeton au prochain lancement. Supprimez-le depuis le Mac si vous voulez une remise à zéro complète."
  )
  #expect(texte.contains(phrase), "le compte rendu doit nommer le fichier restant : \(texte)")
}

@MainActor
@Test("Le compte rendu dit les nombres RÉELS, et rien quand il n'y a rien")
func compteRenduHonnête() async throws {
  let documents = try documentsDeTest(amorcage: false, diagnostic: false)
  let (modele, gardien, persistance) = modeleEtGardien(documents: documents)
  remplir(modele, gardien, persistance)

  let premier = await modele.reinitialiser()
  let texte = modele.texteDuRapport(premier)
  // LE NOMBRE EST DANS LA PHRASE TRADUITE : on recompose donc l'attendu avec `L`,
  // comme le fait le modèle, plutôt que de chercher un « 2 » qui pourrait venir
  // d'ailleurs dans le texte.
  #expect(
    texte.contains(String(format: L("%d jeton(s) d'appareil effacé(s)"), 2)),
    "deux jetons effacés : \(texte)")

  // UNE SECONDE FOIS, SUR UN APPAREIL DÉJÀ PROPRE : le compte rendu doit dire
  // qu'il n'y avait rien, pas afficher « 0 jeton » comme un échec — ni annoncer un
  // effacement qui n'a pas eu lieu.
  let second = await modele.reinitialiser()
  #expect(second.jetonsEffaces == 0)
  #expect(second.clesOubliees == 0)
  #expect(second.diagnosticEfface == false)
  let texte2 = modele.texteDuRapport(second)
  #expect(
    texte2.contains(L("aucun jeton n'était gardé")),
    "un appareil propre se dit tel quel : \(texte2)")
}
