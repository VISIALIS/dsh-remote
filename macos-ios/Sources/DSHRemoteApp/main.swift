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
      // LE MODÈLE VIENT DE L'APPLICATION, et non de la vue : la scène `Settings`
      // et les commandes de menu doivent parler à celui de la fenêtre. Un ⌘R qui
      // rafraîchirait une seconde instance, que personne ne voit, serait un
      // raccourci qui ne fait rien ; un écran de réglages qui lirait un autre
      // appareil que celui affiché serait pire encore.
      VuePrincipale(modele: modele)
        .frame(minWidth: 900, minHeight: 600)
    }
    .defaultSize(width: 1100, height: 720)
    .commands { CommandesDeDSHRemote(modele: modele) }

    // LA SCÈNE RÉGLAGES, ET LE ⌘, QUI VA AVEC.
    //
    // POURQUOI ELLE EST ICI ET NON DANS UNE FEUILLE. La directive macOS est
    // explicite : les réglages d'une application s'ouvrent par l'élément
    // « Réglages… » du menu, avec le raccourci standard ⌘, — une scène `Settings`
    // les déclare tous les deux d'un coup. La feuille que portait la barre
    // d'outils n'existe donc plus que sur iPhone, où elle est le lieu prévu.
    //
    // ELLE MONTRE LE MÊME ÉCRAN que la feuille iOS : deux écrans de réglages
    // auraient divergé sur ce qu'ils disent de l'appareil.
    Settings {
      FeuilleReglages(modele: modele)
    }
  }

  /// LE MODÈLE DE L'APPLICATION, tenu au niveau de la scène.
  ///
  /// POURQUOI IL N'EST PLUS DANS LA VUE. Il l'était, et c'était juste tant que la
  /// fenêtre était la seule à en avoir besoin. Dès qu'une scène `Settings` et des
  /// commandes de menu sont déclarées, elles doivent viser le MÊME modèle — et
  /// SwiftUI ne permet pas de le leur passer autrement qu'en le tenant ici.
  @State private var modele = ModeleApp()
}

/// LES RACCOURCIS DE MENU DE L'APPLICATION macOS.
///
/// POURQUOI UN TYPE `Commands` À PART, ET NON DES BOUTONS DANS LA SCÈNE.
/// `@FocusedValue` ne se lit que dans un type `Commands` : c'est lui qui sait
/// quelle fenêtre est au premier plan. Déclarer les boutons dans la scène
/// obligerait à viser une fenêtre en particulier — ce qu'un menu d'application ne
/// fait jamais.
///
/// CE QUI EST DÉCLARÉ, ET RIEN DE PLUS. ⌘R rafraîchit les sessions et les
/// machines ; ⌘F donne le focus à la recherche. Les deux manquaient : sans eux,
/// l'application macOS ne se pilotait qu'à la souris. Le ⌘, des réglages, lui,
/// vient de la scène `Settings` — il n'est pas à redéclarer ici.
struct CommandesDeDSHRemote: Commands {
  let modele: ModeleApp
  /// Publié par la barre de recherche de la fenêtre active.
  @FocusedValue(\.focusRecherche) private var focusRecherche
  /// Publié par le composeur, quand une session ouverte sait écrire.
  @FocusedValue(\.envoyerMessage) private var envoyerMessage

  var body: some Commands {
    CommandGroup(after: .toolbar) {
      // LES LIBELLÉS PASSENT PAR `L` : un menu resté en français serait le seul
      // endroit non traduit d'une application anglaise.
      Button(L("Rafraîchir")) {
        Task { await modele.rafraichir() }
      }
      .keyboardShortcut("r", modifiers: .command)

      Button(L("Rechercher une session")) {
        focusRecherche?()
      }
      .keyboardShortcut("f", modifiers: .command)
      // DÉSACTIVÉ QUAND AUCUNE FENÊTRE NE PUBLIE L'ACTION — au lieu de ne rien
      // faire en silence. Un raccourci qui ne répond pas laisse croire à une
      // panne ; un élément grisé dit que l'action n'est pas disponible ici.
      .disabled(focusRecherche == nil)

      Divider()

      // ⌘↩ ENVOIE LE MESSAGE, et n'est actif que si un composeur est à l'écran :
      // c'est le composeur qui publie l'action. Sans lui, l'entrée est GRISÉE —
      // un raccourci qui ne peut rien faire doit le dire, pas échouer en silence.
      Button(L("Envoyer le message")) {
        envoyerMessage?()
      }
      .keyboardShortcut(.return, modifiers: .command)
      .disabled(envoyerMessage == nil)
    }
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
