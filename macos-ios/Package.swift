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
// en ligne de commande, macOS) et le projet Xcode `DSHRemote.xcodeproj`, qui
// produit l'application installable sur iPhone et sur Mac.
let package = Package(
  name: "DSHRemote",
  platforms: [
    .macOS(.v14),
    .iOS(.v17),
  ],
  products: [
    .library(name: "DSHRemoteKit", targets: ["DSHRemoteKit"]),
    .executable(name: "dsh-remote-ctl", targets: ["DSHRemoteCtl"]),
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
    .testTarget(
      name: "DSHRemoteKitTests",
      dependencies: ["DSHRemoteKit"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
  ]
)
