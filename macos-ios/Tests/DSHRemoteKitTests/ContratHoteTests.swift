import Foundation
import Testing

@testable import DSHRemoteKit

// LE CONTRAT ENTRE LE PLUGIN ET L'APPLICATION, ÉPROUVÉ DES DEUX CÔTÉS.
//
// POURQUOI CE FICHIER EXISTE. Les formes JSON sont déclarées DEUX FOIS : le
// plugin les produit, l'application les décode. Rien ne vérifiait qu'elles
// s'accordent — et elles ont divergé : le résumé est ÉTALÉ dans l'objet de
// session (pas imbriqué sous `resume`), ce que j'avais supposé de travers dans un
// test, qui lisait « (inconnu) » là où il attendait un identifiant.
//
// La règle tient donc en deux moitiés, et il faut les deux :
//
//   - `plugins/dsh-remote/tests/contrat.test.js` vérifie que le plugin PRODUIT
//     exactement ces clés-là ;
//   - ce fichier vérifie que l'application les DÉCODE.
//
// Un fixture versionné, éprouvé des deux côtés : une dérive d'un côté casse un
// test de l'autre. C'est la seule façon de tenir un contrat entre deux langages
// sans faire tourner les deux en même temps.

/// Le fixture, écrit par le plugin et versionné ici.
private func fixture() throws -> Data {
  // `#filePath` désigne CE fichier : un seul `deletingLastPathComponent()` mène
  // donc à son dossier, et le fixture est à côté.
  let ici = URL(fileURLWithPath: #filePath)
  let fichier = ici.deletingLastPathComponent()
    .appendingPathComponent("Fixtures/sessions-hote.json")
  return try Data(contentsOf: fichier)
}

@Test("L'application décode la réponse de l'hôte, résumé ÉTALÉ compris")
func contratDeLaListe() throws {
  let liste = try JSONDecoder().decode(ListeSessions.self, from: fixture())

  #expect(liste.protocole == 1)
  #expect(liste.total == 117)
  #expect(liste.sessions.count == 2)

  let premiere = try #require(liste.sessions.first)
  // Les champs venus du SYSTÈME DE FICHIERS.
  #expect(premiere.projet == "--srv-projets-dsh-plugins--")
  #expect(premiere.cwdIndicatif == "/srv/projets/dsh/plugins")
  #expect(premiere.octets == 40960)
  #expect(premiere.vivante == true)
  #expect(premiere.statut == "running")
  #expect(premiere.attendReponse == false)

  // Et ceux venus du JOURNAL — ÉTALÉS dans le même objet, pas imbriqués. C'est
  // précisément ce que le contrat vérifie : si le plugin se mettait à les
  // imbriquer sous `resume`, ce test échouerait sur l'identifiant.
  #expect(premiere.id == "2026-09-13T08-12-44-abc")
  #expect(premiere.resume.cwd == "/srv/projets/dsh-plugins")
  #expect(premiere.resume.titre == "Reprise de la découverte des serveurs")
  #expect(premiere.resume.dernierSeq == 412)
  #expect(premiere.resume.nbEnregistrements == 413)
  #expect(premiere.resume.creeLe == 1789000000000)
  #expect(premiere.resume.preset == "danger-full-access")
  #expect(premiere.resume.seme == false)
  #expect(premiere.resume.tronque == false)
}

@Test("Une session sans résumé complet reste décodable — et l'illisible est DIT")
func contratDeLaSessionIllisible() throws {
  let liste = try JSONDecoder().decode(ListeSessions.self, from: fixture())
  let seconde = try #require(liste.sessions.last)

  // Un journal trop volumineux n'est pas résumé : l'hôte le DIT (`illisible`)
  // au lieu de rendre une session vide, et l'application doit le lire.
  #expect(seconde.illisible == "journal trop volumineux (536870912 octets)")
  #expect(seconde.resume.titre == nil)
  #expect(seconde.resume.preset == nil)
  // Une session qui attend une réponse est L'INFORMATION LA PLUS ACTIONNABLE de
  // la liste : elle ne repartira pas toute seule.
  #expect(seconde.attendReponse == true)
  #expect(seconde.vivante == false)
  #expect(seconde.statut == nil)
}

@Test("Les clés que l'application attend sont EXACTEMENT celles du fixture")
func contratDesCles() throws {
  // Table explicite, et non déduite du modèle : c'est le contrat tel qu'il est
  // écrit dans le code du plugin (`entreeDeSession`). La moitié JS vérifie que
  // le plugin produit bien CES clés-là ; ici, on vérifie que l'application ne
  // dépend d'aucune autre.
  let clesAttendues: Set<String> = [
    "projet", "cwdIndicatif", "dossier", "fichier", "octets", "modifieLe",
    "vivante", "statut", "attendReponse",
    "id", "cwd", "creeLe", "preset", "profondeurDelegation", "seme", "titre",
    "dernierEvenementLe", "dernierSeq", "nbEnregistrements", "tronque",
  ]

  let objet = try JSONSerialization.jsonObject(with: fixture()) as? [String: Any]
  let sessions = try #require(objet?["sessions"] as? [[String: Any]])
  let premiere = try #require(sessions.first)

  let cles = Set(premiere.keys)
  #expect(cles == clesAttendues, "clés manquantes : \(clesAttendues.subtracting(cles))")
  #expect(objet?["protocole"] != nil && objet?["total"] != nil)
}
