import Foundation
import Testing

@testable import DSHRemoteKit

// LA POLITIQUE DE RECONNEXION, ÉPROUVÉE SANS RÉSEAU.
//
// POURQUOI ELLE MÉRITE DES TESTS À ELLE SEULE. C'est une règle de TEMPS : un délai
// qui double, un plafond, un quota, et une remise à zéro qui ne doit PAS se
// produire au mauvais moment. La vérifier « en vrai » demanderait de couper un
// réseau, d'attendre, et de compter — c'est-à-dire de ne rien pouvoir rejouer.
//
// LES TROIS ERREURS QUE CES TESTS EMPÊCHENT :
//
//   1. réinitialiser le compteur à l'OUVERTURE de la socket — une socket qui
//      s'ouvre et se referme aussitôt (hôte qui refuse, session inconnue) ferait
//      alors boucler à une seconde POUR TOUJOURS ;
//   2. un délai qui croît sans plafond, donc un flux qui ne revient jamais ;
//   3. un quota absent, donc un `401` (jeton révoqué) qui clignote indéfiniment.

@Test("Le délai double, puis plafonne, et ne dépasse jamais le maximum")
func leDelaiDoublePuisPlafonne() {
  var politique = Reconnexion()
  var delais: [TimeInterval] = []
  for _ in 0..<10 {
    guard let delai = politique.echec() else { break }
    delais.append(delai)
  }

  #expect(delais.first == Reconnexion.delaiInitial, "la première attente est d'une seconde")
  #expect(delais.prefix(5) == [1, 2, 4, 8, 16])
  #expect(delais.allSatisfy { $0 <= Reconnexion.delaiMaximal }, "aucun délai ne dépasse le plafond")
  #expect(delais.last == Reconnexion.delaiMaximal, "le plafond finit par être atteint")
  // La suite est CONSTANTE : c'est ce qui fait qu'une panne longue ne martèle pas.
  #expect(delais.suffix(4).allSatisfy { $0 == Reconnexion.delaiMaximal })
}

@Test("Un contenu reçu remet le compteur à ZÉRO, et pas une socket ouverte")
func seuleUneReussiteRemetAZero() {
  var politique = Reconnexion()
  _ = politique.echec()
  _ = politique.echec()
  #expect(politique.echecs == 2)

  // LA RÈGLE QUI COMPTE : c'est `reussite()` — appelée sur un `base` ou un
  // `evenement`, donc sur un CONTENU — qui remet à zéro. Rien dans cette politique
  // ne se réinitialise à l'ouverture d'une socket, et c'est délibéré : une socket
  // acceptée puis refermée ne prouve rien.
  politique.reussite()
  #expect(politique.echecs == 0)
  #expect(politique.echec() == Reconnexion.delaiInitial, "après une réussite, on repart d'une seconde")
}

@Test("Le quota est BORNÉ : on cesse d'insister, et on le dit")
func leQuotaEstBorne() {
  var politique = Reconnexion()
  var tentatives = 0
  while politique.echec() != nil {
    tentatives += 1
    #expect(tentatives <= Reconnexion.tentativesMaximales + 1, "la boucle doit se terminer")
  }

  #expect(tentatives == Reconnexion.tentativesMaximales)
  #expect(politique.epuisee, "le quota epuise doit se lire sur l'etat")
  #expect(politique.libelle == nil, "un suivi arrete n'annonce pas de reconnexion")
}

@Test("Le libellé dit le rang, et rien quand tout va bien")
func leLibelleDitLeRang() {
  var politique = Reconnexion()
  #expect(politique.libelle == nil, "aucun echec : aucun libelle")
  _ = politique.echec()
  #expect(politique.libelle == "Reconnexion…")
  _ = politique.echec()
  _ = politique.echec()
  #expect(politique.libelle == "Reconnexion 3/\(Reconnexion.tentativesMaximales)…")
}

@Test("Le quota couvre une panne RÉELLE, et pas une éternité")
func leQuotaCouvreUnePanneReelle() {
  // POURQUOI CE TEST EXISTE, ALORS QUE LES AUTRES TIENNENT DÉJÀ LA RÈGLE : le
  // produit « délai × quota » est une DÉCISION, pas un détail. Trop court, une
  // coupure de réseau normale arrêterait le suivi ; trop long, un jeton révoqué
  // ferait clignoter l'écran pendant une heure. On vérifie donc l'ordre de
  // grandeur, et on l'écrit ici pour qu'il soit modifié sciemment.
  var politique = Reconnexion()
  var total: TimeInterval = 0
  while let delai = politique.echec() { total += delai }

  #expect(total > 300, "le quota doit couvrir plus de cinq minutes de panne (\(total) s)")
  #expect(total < 900, "et pas un quart d'heure (\(total) s)")
}
