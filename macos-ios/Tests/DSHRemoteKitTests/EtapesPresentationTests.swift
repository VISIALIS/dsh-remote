import Foundation
import Testing

@testable import DSHRemoteKit

// CE QUI EST ATTEIGNABLE DANS UN PARCOURS D'ÉTAPES.
//
// POURQUOI CES TESTS EXISTENT. Sur la page « Ajouter un serveur », les étapes 2
// à 4 sont déclarées « à faire » PAR CONSTRUCTION — on ne juge pas une machine
// qu'on n'a pas encore. La frontière ne pouvait donc jamais avancer, et les
// étapes 3 et 4, verrouillées à perpétuité, n'affichaient ni leur explication ni
// leur méthode : « publier le port » et « installer le plugin » étaient
// inatteignables depuis la seule page qui existe pour les enseigner.
//
// La règle vit dans `EtapesServeur.presentation` — une fonction pure, donc
// éprouvable ici sans rendre une vue.

// MARK: - Les méthodes des étapes

@Test("Aucune étape d'une liste de travail n'est un cul-de-sac")
func aucuneEtapeSansMethode() {
  // LE DÉFAUT RÉPARÉ, ET IL ÉTAIT BLOQUANT. Sur « Ajouter un serveur », les
  // étapes 2 à 4 sont « à faire » par construction — on ne juge pas une machine
  // qu'on n'a pas encore —, donc la frontière ne pouvait jamais avancer : les
  // étapes 3 et 4 restaient verrouillées à perpétuité, et n'affichaient NI leur
  // explication NI leur méthode. « Publier le port » et « installer le plugin »
  // étaient inatteignables depuis la seule page qui existe pour les enseigner.
  for tailnet in [true, false, nil] as [Bool?] {
    let etapes = EtapesServeur.etapesDAjout(tailnetDeLAppareil: tailnet)
    for etape in etapes where etape.etat != .franchie {
      #expect(
        EtapesServeur.presentation(etape, dans: etapes, mode: .objectifs) != .rien,
        "tailnet=\(String(describing: tailnet)) : l'étape \(etape.numero) n'offre aucune méthode")
    }
  }
}

@Test("Le verrou reste un repère d'ordre : il replie, il ne ferme pas")
func verrouReplieMaisLisible() {
  let etapes = EtapesServeur.etapesDAjout(tailnetDeLAppareil: true)
  // La frontière est ouverte — c'est elle qu'on exécute maintenant.
  #expect(EtapesServeur.presentation(etapes[1], dans: etapes, mode: .objectifs) == .ouverte)
  // Les suivantes sont repliées : lisibles, pas dépliées d'office.
  #expect(EtapesServeur.presentation(etapes[2], dans: etapes, mode: .objectifs) == .repliee)
  #expect(EtapesServeur.presentation(etapes[3], dans: etapes, mode: .objectifs) == .repliee)
  // Et une étape franchie n'a rien à offrir.
  #expect(EtapesServeur.presentation(etapes[0], dans: etapes, mode: .objectifs) == .rien)
}

@Test("Un diagnostic n'ouvre que la méthode de l'étape qui bloque")
func diagnosticUneSeuleMethodeOuverte() {
  // Une machine visible dont le port est fermé : l'étape 3 est la frontière.
  let etapes = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: true, sertDsh: false, cause: .rienNEcoute)

  #expect(EtapesServeur.presentation(etapes[2], dans: etapes, mode: .diagnostic) == .ouverte)
  #expect(EtapesServeur.presentation(etapes[3], dans: etapes, mode: .diagnostic) == .repliee)
  // Un diagnostic ne cache rien, mais il n'outille qu'une chose à la fois.
  #expect(EtapesServeur.presentation(etapes[0], dans: etapes, mode: .diagnostic) == .rien)
  #expect(EtapesServeur.presentation(etapes[1], dans: etapes, mode: .diagnostic) == .rien)
}
