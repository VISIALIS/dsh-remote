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
//     swift run DSHRemoteMac
//
// Il ne duplique aucune vue et aucune logique : il ouvre `VuePrincipale`, la
// même que l'application iOS.
@main
struct DSHRemoteMac: App {
  // ACTIVATION AU LANCEMENT, et ce n'est pas un détail de confort.
  //
  // Mesuré : lancée depuis un terminal (`swift run DSHRemoteMac`), l'application
  // crée bien sa fenêtre — 1100×720, titre « DSH Remote » — mais celle-ci reste
  // DERRIÈRE les autres, `isOnScreen=false`. Sans icône dans le Dock (le produit
  // n'est pas un paquet), rien ne permet de la rappeler : on croit que rien ne
  // s'est ouvert. Ce délégué la met au premier plan une fois le lancement fini.
  @NSApplicationDelegateAdaptor(Activation.self) private var activation

  /// Arguments de sondage, s'il y en a.
  ///
  /// L'application étant lancée comme un PAQUET par le système, elle n'écrit
  /// rien sur la sortie standard : un `print` y est invisible. `--sonder` la
  /// lance donc comme un simple exécutable, dans un terminal, où la sortie se
  /// lit — c'est le seul moyen de diagnostiquer la sonde de découverte.
  static var adressesASonder: [String] {
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: "--sonder") else { return [] }
    return Array(arguments.dropFirst(index + 1))
  }

  init() {
    let adresses = Self.adressesASonder
    guard !adresses.isEmpty else { return }
    Task {
      await SondeLigneDeCommande.executer(adresses)
      exit(0)
    }
  }

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

/// Sonde de diagnostic en ligne de commande : `DSHRemoteMac --sonder <adresse>…`
///
/// POURQUOI ELLE EST ICI. La sonde de découverte — celle qui dit quels Macs
/// servent DSH — ne rendait aucun verdict dans l'application, et rien ne
/// permettait de savoir pourquoi : lancée comme un paquet, l'application
/// n'écrit RIEN sur la sortie standard. Mesuré : `stdout` vide, aucune trace.
///
/// Cette commande rejoue donc la MÊME logique, sur les adresses données, dans un
/// processus dont la sortie se lit. C'est ce qui distingue « la sonde est
/// fautive » de « la sonde n'est pas lancée ».
enum SondeLigneDeCommande {
  @MainActor
  static func executer(_ adresses: [String]) async {
    let modele = ModeleApp()
    let saisi = modele.jetonSaisi
    let jeton = saisi.isEmpty ? (CoffreDuHarness.jetonDeLaMachine() ?? "") : saisi
    print("[sonde] jeton : \(jeton.count) caracteres")
    for adresse in adresses {
      guard let client = try? RemoteClient(adresse: adresse, jeton: jeton, delai: 3) else {
        print("[sonde] \(adresse) -> adresse invalide")
        continue
      }
      do {
        _ = try await client.verifierSante()
        print("[sonde] \(adresse) -> DSH PRESENT")
      } catch ErreurRemote.jetonRefuse {
        print("[sonde] \(adresse) -> DSH PRESENT (jeton refuse)")
      } catch {
        print("[sonde] \(adresse) -> \(error)")
      }
    }
  }
}
