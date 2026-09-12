import SwiftUI

// Point d'entree de l'application DSH Remote.
//
// Meme code pour macOS et iOS : la seule difference de plateforme est la
// provenance du jeton (coffre du harness sur le Mac, trousseau sur iPhone),
// traitee dans `ModeleApp`. Une interface separee par plateforme serait deux
// fois plus de code a verifier pour le meme resultat.

@main
struct AppDSHRemote: App {
  var body: some Scene {
    WindowGroup {
      VuePrincipale()
    }
    #if os(macOS)
      .defaultSize(width: 1100, height: 720)
    #endif
  }
}
