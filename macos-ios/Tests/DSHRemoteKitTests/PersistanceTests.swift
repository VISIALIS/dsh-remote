import Foundation
import Testing

@testable import DSHRemoteKit

// LA PERSISTANCE, ÉPROUVÉE SANS TOUCHER AU DISQUE DE LA MACHINE.
//
// POURQUOI CE FICHIER EXISTE. Ces écritures étaient dans `ModeleApp`, mêlées aux
// transitions et au réseau : on ne pouvait les éprouver qu'en écrivant dans les
// préférences réelles de la machine qui exécute les tests. Elles sont maintenant
// derrière un type qui s'injecte — un domaine `UserDefaults` à nous, un dossier
// temporaire — donc on les éprouve pour de vrai, y compris ce qu'elles ne doivent
// JAMAIS écrire.

/// Un domaine de préférences jetable, et son nettoyage.
private func domaineDEssai(_ nom: String = UUID().uuidString) -> UserDefaults {
  let defaults = UserDefaults(suiteName: nom) ?? .standard
  defaults.removePersistentDomain(forName: nom)
  return defaults
}

@Test("L'adresse mémorisée revient, avec son nom")
func adresseMemorisee() {
  let defaults = domaineDEssai()
  let persistance = Persistance(defaults: defaults, documents: nil)

  // Rien de mémorisé : l'adresse est vide, et le nom est inconnu — pas de valeur
  // inventée.
  #expect(persistance.lireAdresse().adresse.isEmpty)
  #expect(persistance.lireAdresse().nom == nil)

  persistance.memoriserAdresse("http://portable.exemple.ts.net", nom: "Portable")
  let relu = Persistance(defaults: defaults, documents: nil).lireAdresse()
  #expect(relu.adresse == "http://portable.exemple.ts.net")
  #expect(relu.nom == "Portable")

  persistance.oublierAdresse()
  #expect(persistance.lireAdresse().adresse.isEmpty)
  #expect(persistance.lireAdresse().nom == nil)
}

@Test("Les préférences par serveur survivent, et ne se mélangent pas")
func preferencesParServeur() {
  let defaults = domaineDEssai()
  let persistance = Persistance(defaults: defaults, documents: nil)

  var preferences: [String: PreferencesServeur] = [:]
  var premier = PreferencesServeur()
  premier.suivi = false
  preferences["portable-un.exemple.ts.net"] = premier

  persistance.memoriserPreferences(preferences)

  let relues = Persistance(defaults: defaults, documents: nil).lirePreferences()
  #expect(relues["portable-un.exemple.ts.net"]?.suivi == false)
  #expect(relues["portable-deux.exemple.ts.net"] == nil, "un serveur inconnu ne doit rien hériter")
}

@Test("Le fichier d'amorçage est lu, et un jeton trop court est refusé")
func fichierDAmorcage() throws {
  let dossier = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("essai-amorcage-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dossier) }

  let fichier = dossier.appendingPathComponent(Persistance.nomDuFichierDAmorcage)
  let persistance = Persistance(defaults: domaineDEssai(), documents: dossier)

  // Sans fichier : rien, et surtout pas une erreur.
  #expect(persistance.lireAmorcage().adresse == nil)
  #expect(persistance.lireAmorcage().jeton == nil)

  try #"{"adresse":"http://portable.exemple.ts.net","jeton":"trop-court"}"#
    .write(to: fichier, atomically: true, encoding: .utf8)
  #expect(persistance.lireAmorcage().adresse == "http://portable.exemple.ts.net")
  // Le jeton d'amorçage n'est accepté que s'il a la taille d'un vrai : un
  // fichier tronqué ne doit pas faire croire à un jeton valide.
  #expect(persistance.lireAmorcage().jeton == nil)
}

@Test("Le diagnostic ne contient JAMAIS le jeton — seulement son empreinte")
func diagnosticSansJeton() throws {
  let dossier = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("essai-diagnostic-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dossier) }

  let persistance = Persistance(defaults: domaineDEssai(), documents: dossier)
  let jeton = String(repeating: "a", count: 43)
  persistance.consignerDiagnostic(
    adresse: "http://portable.exemple.ts.net",
    message: "réponse inattendue (HTTP 404)",
    empreinteJeton: "0123456789abcdef",
    longueurJeton: jeton.count)

  let fichier = dossier.appendingPathComponent(Persistance.nomDuDiagnostic)
  let contenu = try String(contentsOf: fichier, encoding: .utf8)

  // RÈGLE #0 : ce fichier est destiné à être RECOPIÉ depuis un Mac pour lire une
  // cause d'échec. Un jeton qui s'y trouverait sortirait de l'appareil.
  #expect(!contenu.contains(jeton), "le jeton ne doit jamais être écrit sur disque")
  #expect(contenu.contains("réponse inattendue (HTTP 404)"))
  #expect(contenu.contains("0123456789abcdef"))
  #expect(contenu.contains("\"longueurJeton\" : \"43\""))
}
