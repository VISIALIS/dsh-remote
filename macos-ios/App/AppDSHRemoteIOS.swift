// Point d'entrée de l'application iOS « DSH Remote ».
//
// La vue et toute la logique viennent de `DSHRemoteKit` et de la cible
// `DSHRemoteApp` du paquet local : cette cible Xcode n'existe QUE pour produire
// un paquet `.app` installable. Un exécutable SwiftPM donne un binaire Mach-O nu,
// sans bundle ni Info.plist, et iOS n'installe que des `.app` signés — c'est la
// seule raison de ce projet Xcode.

import DSHRemoteKit
import SwiftUI

@main
struct AppDSHRemoteIOS: App {
  /// L'état de l'application, pour tenir l'écran éveillé tant qu'on s'en sert.
  ///
  /// POURQUOI CE VERROU EXISTE ICI. Une session d'agent se SUIT : on lance un
  /// tour, on regarde le journal avancer. Sans verrou, iOS éteint l'écran au
  /// bout du délai de verrouillage automatique, l'application passe en
  /// arrière-plan — donc est suspendue — et le suivi s'arrête. Le `-1001`
  /// observé sur l'iPhone (délai dépassé) est la conséquence visible de cette
  /// mise en sommeil : la radio Wi-Fi de l'appareil s'endort entre deux
  /// échanges, et la première requête qui suit part en timeout.
  ///
  /// CE QUI EST POSSIBLE ET CE QUI NE L'EST PAS. `isIdleTimerDisabled` empêche
  /// l'écran de s'assombrir et l'appareil de se verrouiller tant que
  /// l'application est AU PREMIER PLAN. Il ne protège pas d'une mise en
  /// arrière-plan : iOS y suspend l'application, et aucune API ne le contourne.
  /// On le relâche donc en quittant le premier plan — garder l'écran allumé
  /// dans une poche serait un défaut, pas un service.
  @State private var modele = ModeleApp()
  @Environment(\.scenePhase) private var phase

  var body: some Scene {
    WindowGroup {
      VuePrincipale(modele: modele)
        .onOpenURL { url in
          modele.recevoirLien(url)
        }
    }
    // `initial: true` est nécessaire : la première valeur de `phase` est
    // `active` sans transition, donc un `onChange` ordinaire ne verrait jamais
    // le démarrage et le verrou ne serait posé qu'après un aller-retour en
    // arrière-plan.
    .onChange(of: phase, initial: true) { _, nouvelle in
      appliquerVerrouDEcran(premierPlan: nouvelle == .active)
    }
  }

}

/// Active ou relâche le verrou d'écran, sur iOS seulement.
///
/// `UIApplication` n'existe pas sur macOS : ce fichier n'est compilé que par la
/// cible iOS, mais la cible Mac construit le même paquet `DSHRemoteKit`, et le
/// `#if` garde la fonction compilable partout sans importer UIKit ailleurs.
///
/// `@MainActor` : `UIApplication.shared` est isolé au fil principal. Sans
/// l'annotation, Swift 6 refuse la mutation depuis un contexte non isolé
/// (simple avertissement sur Xcode 27, erreur sur les versions antérieures).
@MainActor
private func appliquerVerrouDEcran(premierPlan: Bool) {
  #if os(iOS)
    UIApplication.shared.isIdleTimerDisabled = premierPlan
  #endif
}
