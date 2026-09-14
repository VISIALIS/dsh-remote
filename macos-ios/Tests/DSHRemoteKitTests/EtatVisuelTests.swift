import SwiftUI
import Testing

@testable import DSHRemoteKit

// LA TABLE DES ÉTATS — et ce qu'elle garantit.
//
// POURQUOI CES TESTS EXISTENT. Les couleurs d'état étaient choisies sur place :
// `.orange` ici, `.green` là, et deux petites tables locales qui avaient déjà
// commencé à diverger — exactement ce qu'un commentaire du dépôt disait vouloir
// éviter. La règle A5 de `AUDIT-UX-UI.md` ajoute qu'un état ne se dit JAMAIS par
// la couleur seule : il lui faut un mot, et une forme distincte. Une table
// unique ne sert à rien si rien ne vérifie qu'elle est complète.

@Test("Chaque état porte un mot et un symbole, tous distincts")
func tableComplete() {
  #expect(EtatVisuel.allCases.count == 5)
  let symboles = EtatVisuel.allCases.map(\.symbole)
  let mots = EtatVisuel.allCases.map(\.mot)

  // DEUX ÉTATS QUI PARTAGENT UN SYMBOLE SERAIENT INDISTINGUABLES pour qui ne
  // distingue pas les couleurs — exactement ce que A5 interdit.
  #expect(Set(symboles).count == symboles.count, "deux états partagent un symbole")
  #expect(Set(mots).count == mots.count, "deux états partagent un mot")
  #expect(symboles.allSatisfy { !$0.isEmpty })
  // Un mot d'un seul caractère ne dit rien : le seuil écarte un remplissage.
  #expect(mots.allSatisfy { $0.count > 2 }, "un mot d'état est trop court pour être lu")
}

@Test("Les tons d'une machine gardent EXACTEMENT leur sens d'avant")
func correspondanceDesTons() {
  // LE PASSAGE À LA TABLE NE DEVAIT RIEN CHANGER À L'ÉCRAN. L'ancien `Ton`
  // avait trois cas (vert, orange, gris) ; ils sont devenus trois cas de la
  // table, avec les MÊMES couleurs. Ce test est le filet : si quelqu'un rebranche
  // un ton sur le mauvais cas, l'écran change de couleur sans que rien d'autre ne
  // le dise — et les deux mots (`attention` / `attente`) se ressemblent assez
  // pour qu'une relecture ne suffise pas.
  let prete = EtatMachine.decrire(enLigne: true, sertDsh: true, estLocal: false, court: false)
  #expect(prete.ton == .pret)

  let sansDsh = EtatMachine.decrire(enLigne: true, sertDsh: false, estLocal: false, court: false)
  #expect(sansDsh.ton == .attention)

  let horsLigne = EtatMachine.decrire(enLigne: false, sertDsh: nil, estLocal: false, court: false)
  #expect(horsLigne.ton == .attention, "« hors ligne » reste un avertissement, pas une erreur")

  let enCours = EtatMachine.decrire(enLigne: true, sertDsh: nil, estLocal: false, court: false)
  #expect(enCours.ton == .attente, "« on ne sait pas encore » est gris, jamais orange")
}

@Test("Une étape de parcours dit son état dans le vocabulaire commun")
func etatDesEtapes() {
  // `ParcoursDesEtapes` choisissait ses couleurs sur place (une troisième table).
  // Il passe par `EtatVisuel` : franchie = prêt, à faire = avertissement,
  // inconnue = attente. On ne peut pas lire la fonction privée de la vue, alors
  // on vérifie la TABLE — c'est elle qui porte désormais la décision.
  #expect(EtatVisuel.pret.symbole.isEmpty == false)
  #expect(EtatVisuel.attention.couleur != EtatVisuel.attente.couleur)
}
