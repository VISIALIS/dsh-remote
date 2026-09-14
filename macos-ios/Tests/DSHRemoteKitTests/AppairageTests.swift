import Foundation
import Testing

@testable import DSHRemoteKit

// LE CONTRAT D'APPAIRAGE, ÉPROUVÉ CÔTÉ APPAREIL.
//
// POURQUOI CE FICHIER EXISTE. Le même fixture est rejoué par
// `plugins/dsh-remote/tests/appairage.test.js` : les deux moitiés analysent les
// MÊMES chaînes et doivent rendre les MÊMES verdicts. Sans cela, une règle
// ajustée d'un seul côté ne se verrait qu'à l'appairage, chez l'utilisateur.
//
// CE QUI N'EST PAS ICI, ET POURQUOI : aucune construction de charge utile.
// L'application n'en émet JAMAIS — c'est l'hôte qui appaire, l'appareil qui
// scanne ou qui colle. Une fonction d'écriture non utilisée serait du code à
// maintenir sans jamais l'exercer.

/// Le fixture partagé, tel qu'il est écrit.
private struct Vecteurs: Decodable {
  struct Valide: Decodable {
    let charge: String
    let hote: String
    let genre: String
    let version: String
    let secret: String
    let adresse: String
  }

  struct Refuse: Decodable {
    let charge: String
    let motif: String
  }

  struct Seuils: Decodable {
    let jeton: Int
    let code: Int
  }

  struct Limite: Decodable {
    let charge: String
    let accepte: Bool
  }

  let seuils: Seuils
  let valides: [Valide]
  let refuses: [Refuse]
  let limites: [Limite]
}

private func vecteurs() throws -> Vecteurs {
  // `#filePath` désigne CE fichier : un seul `deletingLastPathComponent()` mène
  // à son dossier, et le fixture est à côté — c'est la convention du dépôt pour
  // un contrat entre deux langages (voir `ContratHoteTests.swift`).
  let ici = URL(fileURLWithPath: #filePath)
  let fichier = ici.deletingLastPathComponent()
    .appendingPathComponent("Fixtures/vecteurs-appairage.json")
  return try JSONDecoder().decode(Vecteurs.self, from: Data(contentsOf: fichier))
}

@Test("Les charges utiles valides sont analysées à l'identique")
func chargesValides() throws {
  let fixture = try vecteurs()
  #expect(fixture.valides.count >= 4)

  for attendu in fixture.valides {
    let resultat = Appairage.analyser(attendu.charge)
    guard case .success(let charge) = resultat else {
      Issue.record("charge refusée à tort : \(attendu.charge) — \(resultat)")
      continue
    }
    #expect(charge.hote == attendu.hote)
    #expect(charge.genre.rawValue == attendu.genre)
    #expect(charge.version == attendu.version)
    #expect(charge.secret == attendu.secret)
    // L'adresse n'est pas décorative : c'est elle que l'application visera.
    #expect(charge.adresse == attendu.adresse)
  }
}

@Test("Chaque refus rend le motif attendu, et un message lisible")
func chargesRefusees() throws {
  let fixture = try vecteurs()
  #expect(fixture.refuses.count >= 12)

  for attendu in fixture.refuses {
    let resultat = Appairage.analyser(attendu.charge)
    guard case .failure(let motif) = resultat else {
      Issue.record("charge acceptée à tort : \(attendu.charge)")
      continue
    }
    #expect(motif.rawValue == attendu.motif, "motif inattendu pour « \(attendu.charge) »")
    // UN REFUS DOIT DIRE POURQUOI : c'est ce que lit l'utilisateur.
    #expect(motif.message.count > 15)
  }
}

@Test("Le fixture couvre tous les motifs déclarés")
func motifsCouverts() throws {
  // Un motif ajouté au type sans vecteur serait un refus jamais éprouvé — et
  // c'est exactement le genre de trou qui ne se voit pas.
  let fixture = try vecteurs()
  let couverts = Set(fixture.refuses.compactMap { Appairage.Motif(rawValue: $0.motif) })
  for motif in Appairage.Motif.allCases {
    #expect(couverts.contains(motif), "aucun vecteur ne refuse pour le motif \(motif.rawValue)")
    #expect(motif.message.count > 15)
  }
}

@Test("Les seuils partagés sont ceux du contrat")
func seuilsPartages() throws {
  let fixture = try vecteurs()
  #expect(Appairage.minimumSecret(.jeton) == fixture.seuils.jeton)
  #expect(Appairage.minimumSecret(.code) == fixture.seuils.code)
  #expect(fixture.seuils.jeton == 32)
  #expect(fixture.seuils.code == 22)
}

@Test("L'analyse ne lève jamais, quelle que soit l'entrée")
func analyseTolerante() {
  // ELLE EST APPELÉE À CHAQUE IMAGE DE LA CAMÉRA ET À CHAQUE FRAPPE : lever y
  // serait un défaut d'ergonomie, pas une sécurité.
  let entrees = [
    "", "   ", "dshremote", "dshremote:", "dshremote://",
    "dshremote://" + String(repeating: "a", count: 600),
    "dshremote://hote.exemple.test/jeton/v1/" + String(repeating: "a", count: 43) + "?x=1",
    "bonjour", "http://hote.exemple.test/jeton/v1/" + String(repeating: "A", count: 43),
  ]
  for entree in entrees {
    if case .success = Appairage.analyser(entree) {
      Issue.record("entrée acceptée à tort : \(entree)")
    }
  }
}

@Test("Un texte entouré d'espaces est accepté — un collage en ajoute")
func collageTolerant() throws {
  let fixture = try vecteurs()
  let premier = try #require(fixture.valides.first)
  let resultat = Appairage.analyser("  \(premier.charge)\n")
  guard case .success(let charge) = resultat else {
    Issue.record("un collage entouré d'espaces a été refusé")
    return
  }
  #expect(charge.secret == premier.secret)
}

@Test("La boucle locale est refusée, et dite comme telle")
func boucleLocaleRefusee() {
  // LE MOTIF COMPTE AUTANT QUE LE REFUS : « c'est l'adresse de ta propre
  // machine » se répare, « ce lien est invalide » ne se répare pas.
  for hote in ["127.0.0.1", "localhost", "0.0.0.0", "::1"] {
    let charge = "dshremote://\(hote)/jeton/v1/" + String(repeating: "A", count: 43)
    guard case .failure(let motif) = Appairage.analyser(charge) else {
      Issue.record("boucle locale acceptée : \(hote)")
      continue
    }
    #expect(motif == .hoteLocal, "motif inattendu pour \(hote) : \(motif.rawValue)")
  }
  #expect(Appairage.hoteJoignable("127.0.0.1") == false)
  #expect(Appairage.hoteJoignable("mac-mini-essai.exemple.test"))
}

@Test("Les limites du nom d'hôte sont les mêmes des deux côtés")
func limitesDuNomDHote() throws {
  // POURQUOI CE TEST EXISTE. La règle du nom d'hôte n'est PAS une règle DNS par
  // étiquette : elle exige un premier et un dernier caractère alphanumériques, et
  // rien de plus. Un tiret avant un point passe donc — acceptable, le nom venant
  // de Tailscale. Ce qui ne serait pas acceptable, c'est que le JavaScript et le
  // Swift n'acceptent pas la MÊME chose : ces vecteurs figent la laxité autant
  // que la sévérité, et une dérive d'un côté casse le test de l'autre.
  let fixture = try vecteurs()
  #expect(fixture.limites.count >= 3)
  for limite in fixture.limites {
    let accepte: Bool
    if case .success = Appairage.analyser(limite.charge) { accepte = true } else { accepte = false }
    #expect(accepte == limite.accepte, "désaccord sur « \(limite.charge) »")
  }
}

@Test("Un nom d'hôte n'accepte que l'ASCII du contrat")
func hoteAsciiSeulement() {
  // POURQUOI CE TEST. `isLetter` de Swift accepte l'Unicode ; le JavaScript d'en
  // face teste `[A-Za-z0-9.-]`. Sans cette restriction, une charge utile
  // accentuée passerait ici et serait refusée là-bas — ou l'inverse.
  #expect(Appairage.hoteJoignable("mac-mini-essai.exemple.test"))
  #expect(Appairage.hoteJoignable("mác.exemple.test") == false)
  #expect(Appairage.hoteJoignable("-mauvais.exemple.test") == false)
  #expect(Appairage.hoteJoignable("mauvais.exemple.test-") == false)
  #expect(Appairage.hoteJoignable("mauvais.exemple.test:3080") == false)
  #expect(Appairage.hoteJoignable("") == false)
}
