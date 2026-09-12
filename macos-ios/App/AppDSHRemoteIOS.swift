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
  var body: some Scene {
    WindowGroup {
      VuePrincipale()
    }
  }
}
