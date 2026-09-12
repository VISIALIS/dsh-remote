// swift-tools-version: 6.0
import PackageDescription

// Paquet multiplateforme « DSH Remote ».
//
// Une seule bibliothèque partagée (`DSHRemoteKit`) porte le protocole, le
// transport et les modèles ; l'application macOS et l'application iOS la
// consomment telle quelle. Le tool `dsh-remote-ctl` existe pour PROUVER le
// transport en ligne de commande, sans interface : c'est lui qui doit passer au
// vert avant qu'une ligne de SwiftUI soit écrite.
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
