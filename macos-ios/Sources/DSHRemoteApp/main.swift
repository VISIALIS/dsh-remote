import DSHRemoteKit
import SwiftUI

// Point d'entrée macOS de l'application.
//
// POURQUOI IL EXISTE — et pourquoi il manquait. Les vues vivent dans la
// bibliothèque `DSHRemoteKit` depuis la restructuration imposée par la cible
// d'application iOS : une cible d'application ne peut pas lier un exécutable, et
// l'ancien point d'entrée `DSHRemoteApp` a donc disparu. Il ne restait, pour
// REGARDER l'application sur le Mac, que le projet Xcode — qui ne produit qu'une
// application iOS.
//
// Conséquence observée : lancer le binaire d'un build SIMULATEUR comme un
// programme macOS. dyld refuse alors avant la moindre ligne de notre code :
//
//     dyld: DYLD_ROOT_PATH not set for simulator program
//
// Vérifié sur les deux architectures du binaire universel. Ce n'est pas un
// plantage de l'application : c'est un binaire iOS-simulateur exécuté hors du
// simulateur. Ce fichier donne le chemin qui fonctionne :
//
//     swift run DSHRemote
//
// Il ne duplique aucune vue et aucune logique : il ouvre `VuePrincipale`, la
// même que l'application iOS.
@main
struct DSHRemoteMac: App {
  // ACTIVATION AU LANCEMENT, et ce n'est pas un détail de confort.
  //
  // Mesuré : lancée depuis un terminal (`swift run DSHRemote`), l'application
  // crée bien sa fenêtre — 1100×720, titre « DSH Remote » — mais celle-ci reste
  // DERRIÈRE les autres, `isOnScreen=false`. Sans icône dans le Dock (le produit
  // n'est pas un paquet), rien ne permet de la rappeler : on croit que rien ne
  // s'est ouvert. Ce délégué la met au premier plan une fois le lancement fini.
  @NSApplicationDelegateAdaptor(Activation.self) private var activation

  final class Activation: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
      // `.regular` d'abord : un exécutable SANS paquet macOS n'est pas traité
      // comme une application à part entière, et sa fenêtre reste alors non
      // ordonnée (`isOnScreen=false`). Mesuré avant cette ligne : fenêtre créée,
      // jamais affichée, et aucun moyen de la rappeler puisqu'il n'y a pas
      // d'icône dans le Dock.
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  var body: some Scene {
    WindowGroup("DSH Remote") {
      VuePrincipale()
        .frame(minWidth: 900, minHeight: 600)
    }
    .defaultSize(width: 1100, height: 720)
  }
}
