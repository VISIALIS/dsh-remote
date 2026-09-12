// swift-tools-version: 6.0
import PackageDescription

// Paquet multiplateforme « DSH Remote ».
//
// `DSHRemoteKit` porte TOUT le code réutilisable : protocole, transport,
// modèles, flux temps réel, et l'interface SwiftUI elle-même.
//
// POURQUOI L'INTERFACE EST DANS LA BIBLIOTHÈQUE. Parce qu'une cible
// d'application Xcode ne peut pas lier un exécutable : pour qu'une app iOS
// puisse afficher ces vues, elles doivent vivre dans une bibliothèque. C'est
// cette contrainte, et non un choix esthétique, qui a déplacé le code.
//
// Les points d'entrée sont donc séparés : `dsh-remote-ctl` (tool de validation
// en ligne de commande, macOS), `DSHRemote` (application macOS, pour REGARDER
// l'interface sur le Mac) et le projet Xcode `DSHRemote.xcodeproj`, qui produit
// l'application installable sur iPhone.
let package = Package(
  name: "DSHRemote",
  platforms: [
    .macOS(.v14),
    .iOS(.v17),
  ],
  products: [
    .library(name: "DSHRemoteKit", targets: ["DSHRemoteKit"]),
    .executable(name: "dsh-remote-ctl", targets: ["DSHRemoteCtl"]),
    .executable(name: "DSHRemote", targets: ["DSHRemoteApp"]),
  ],
  targets: [
    .target(
      name: "DSHRemoteKit",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .executableTarget(
      name: "DSHRemoteCtl",
      dependencies: ["DSHRemoteKit"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    // macOS UNIQUEMENT : c'est la seule plateforme où ce paquet produit une
    // application. iOS passe par le projet Xcode, dont le binaire de simulateur
    // ne doit jamais être lancé comme un programme macOS — dyld le refuse
    // (`DYLD_ROOT_PATH not set for simulator program`), et ce refus ressemble à
    // s'y méprendre à un plantage de l'application.
    .executableTarget(
      name: "DSHRemoteApp",
      dependencies: ["DSHRemoteKit"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "DSHRemoteKitTests",
      dependencies: ["DSHRemoteKit"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
  ]
)
