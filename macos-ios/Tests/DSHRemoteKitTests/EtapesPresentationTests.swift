import Foundation
import Testing

@testable import DSHRemoteKit

// CE QUI EST ATTEIGNABLE DANS UN PARCOURS D'ÉTAPES.
//
// POURQUOI CES TESTS EXISTENT. Sur la page « Ajouter un serveur », les étapes du
// Mac sont déclarées « à faire » PAR CONSTRUCTION — on ne juge pas une machine
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

@Test("Sur une liste de travail, la méthode OUVERTE est celle de cet appareil")
func objectifsOuvrentLeGesteDeLAppareil() {
  // LA RÈGLE, ET CE QU'ELLE PROTÈGE. Ici, le Mac n'a même pas encore d'adresse :
  // ses étapes sont une liste, pas un verdict, et elles ne peuvent donc pas
  // précéder le geste que l'appareil a à faire. La méthode ouverte est la sienne
  // — prendre le QR code —, et le travail du Mac reste écrit, replié : on le lit
  // quand on est devant lui.
  let etapes = EtapesServeur.etapesDAjout(tailnetDeLAppareil: true)

  // Le travail du Mac : replié, jamais ouvert d'office.
  #expect(EtapesServeur.presentation(etapes[1], dans: etapes, mode: .objectifs) == .repliee)
  #expect(EtapesServeur.presentation(etapes[2], dans: etapes, mode: .objectifs) == .repliee)
  #expect(EtapesServeur.presentation(etapes[3], dans: etapes, mode: .objectifs) == .repliee)
  // Le geste de l'appareil : ouvert, parce que c'est ce qu'on fait ici.
  #expect(EtapesServeur.presentation(etapes[4], dans: etapes, mode: .objectifs) == .ouverte)
  // Et une étape franchie n'a rien à offrir.
  #expect(EtapesServeur.presentation(etapes[0], dans: etapes, mode: .objectifs) == .rien)

  // SANS TAILSCALE SUR CET APPAREIL, C'EST ELLE QU'ON OUVRE : il n'y a rien à
  // appairer tant que rien n'est joignable.
  let sansReseau = EtapesServeur.etapesDAjout(tailnetDeLAppareil: false)
  #expect(EtapesServeur.presentation(sansReseau[0], dans: sansReseau, mode: .objectifs) == .ouverte)
  #expect(EtapesServeur.presentation(sansReseau[4], dans: sansReseau, mode: .objectifs) == .repliee)
}

@Test("Un diagnostic n'ouvre que la méthode de l'étape qui bloque")
func diagnosticUneSeuleMethodeOuverte() {
  // Une machine visible dont le port est fermé : l'étape 3 est la frontière.
  let etapes = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: true, sertDsh: false, cause: .rienNEcoute,
    appairage: .appaire)

  #expect(EtapesServeur.presentation(etapes[2], dans: etapes, mode: .diagnostic) == .ouverte)
  #expect(EtapesServeur.presentation(etapes[3], dans: etapes, mode: .diagnostic) == .repliee)
  // Un diagnostic ne cache rien, mais il n'outille qu'une chose à la fois.
  #expect(EtapesServeur.presentation(etapes[0], dans: etapes, mode: .diagnostic) == .rien)
  #expect(EtapesServeur.presentation(etapes[1], dans: etapes, mode: .diagnostic) == .rien)
}

@Test("Machine prête, appareil non appairé : c'est l'appairage qui s'ouvre")
func diagnosticOuvreLAppairageQuandToutLeResteEstPret() {
  // LE CAS QUI A MOTIVÉ LA CINQUIÈME ÉTAPE. Rien n'est cassé sur le Mac ; ce qui
  // manque est le jeton de cet appareil. La méthode ouverte doit donc être la
  // sienne — le QR code —, et pas une commande à taper sur une machine saine.
  let etapes = EtapesServeur.etapes(
    tailnetDeLAppareil: true, enLigne: true, sertDsh: true, cause: nil, appairage: .absent)

  #expect(EtapesServeur.presentation(etapes[4], dans: etapes, mode: .diagnostic) == .ouverte)
  #expect(EtapesServeur.presentation(etapes[1], dans: etapes, mode: .diagnostic) == .rien)
  #expect(EtapesServeur.presentation(etapes[2], dans: etapes, mode: .diagnostic) == .rien)
  #expect(EtapesServeur.presentation(etapes[3], dans: etapes, mode: .diagnostic) == .rien)
}
