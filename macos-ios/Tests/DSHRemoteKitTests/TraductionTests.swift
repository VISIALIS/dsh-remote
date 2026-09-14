import Foundation
import Testing

@testable import DSHRemoteKit

// LES DEUX TABLES, ET LEUR PARITÉ.
//
// Le défaut que ces tests empêchent n'est pas visible à la compilation, ni en
// français : une clé qui existe dans la table française mais pas dans
// l'anglaise s'affiche **en français** dans une interface anglaise, et personne
// ne s'en aperçoit avant qu'un utilisateur anglophone ouvre l'écran concerné.
//
// Ils ne disent pas si la traduction est BONNE — cela se juge en lisant —, mais
// ils disent qu'elle est COMPLÈTE et qu'aucune valeur n'est vide.

@Test("Les tables française et anglaise existent, et sont lisibles depuis le paquet")
func tablesLisibles() throws {
  for langue in Traduction.langues {
    let cles = try #require(Traduction.cles(langue), "table introuvable : \(langue)")
    #expect(!cles.isEmpty, "la table \(langue) est vide")
  }
}

@Test("Les deux tables portent EXACTEMENT les mêmes clés")
func pariteDesCles() throws {
  let francais = try #require(Traduction.cles("fr"))
  let anglais = try #require(Traduction.cles("en"))

  let manquantesEnAnglais = francais.subtracting(anglais).sorted()
  let orphelinesEnAnglais = anglais.subtracting(francais).sorted()

  #expect(
    manquantesEnAnglais.isEmpty,
    "clés françaises sans traduction anglaise (\(manquantesEnAnglais.count)) : \(manquantesEnAnglais.prefix(12).joined(separator: " | "))"
  )
  #expect(
    orphelinesEnAnglais.isEmpty,
    "clés anglaises sans original français (\(orphelinesEnAnglais.count)) : \(orphelinesEnAnglais.prefix(12).joined(separator: " | "))"
  )
}

@Test("Aucune traduction n'est vide, et aucune clé n'est blanche")
func valeursRenseignees() throws {
  for langue in Traduction.langues {
    let cles = try #require(Traduction.cles(langue))
    for cle in cles {
      #expect(!cle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      let valeur = try #require(Traduction.texte(cle, langue: langue))
      #expect(
        !valeur.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        "traduction vide pour « \(cle) » en \(langue)")
    }
  }
}

@Test("Une clé absente rend nil, plutôt que la clé elle-même")
func cleAbsente() {
  // C'est la différence entre « pas de traduction » et « traduction identique » :
  // le test de parité s'appuie dessus pour nommer ce qui manque.
  #expect(Traduction.texte("cette clé n'existe pas", langue: "en") == nil)
  #expect(Traduction.texte("cette clé n'existe pas", langue: "fr") == nil)
  #expect(Traduction.texte("Ajouter", langue: "xx") == nil)
}
