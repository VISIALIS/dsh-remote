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
  // LA LANGUE SOURCE DU PAQUET, ET ELLE EST OBLIGATOIRE : SwiftPM refuse un
  // paquet qui porte des ressources localisées sans dire laquelle fait référence.
  // C'est le français — le code, les commentaires et les clés le sont (RÈGLE #1) ;
  // l'anglais est une TRADUCTION ajoutée, pas une seconde source.
  defaultLocalization: "fr",
  platforms: [
    .macOS(.v14),
    .iOS(.v17),
  ],
  products: [
    .library(name: "DSHRemoteKit", targets: ["DSHRemoteKit"]),
    .executable(name: "dsh-remote-ctl", targets: ["DSHRemoteCtl"]),
    // POURQUOI « DSHRemoteMac » ET NON « DSHRemote ».
    //
    // Le produit s'appelait `DSHRemote`, comme la CIBLE D'APPLICATION iOS du
    // projet Xcode. Tant que le projet n'avait aucune phase de ressources, la
    // collision restait invisible ; dès qu'on y ajoute le catalogue d'assets de
    // l'icône, Xcode résout le schéma `DSHRemote` vers le PRODUIT DU PAQUET au
    // lieu de la cible d'application, compile `Sources/DSHRemoteApp/main.swift`
    // (code macOS : `NSApplicationDelegateAdaptor`) pour iOS, et le build
    // échoue. Mesuré, et isolé : la seule phase de ressources suffit à
    // déclencher la bascule.
    //
    // Deux noms identiques pour deux choses différentes n'étaient pas tenables :
    // on renomme côté paquet, et `swift run DSHRemoteMac` remplace
    // `swift run DSHRemote` sur le Mac.
    .executable(name: "DSHRemoteMac", targets: ["DSHRemoteApp"]),
  ],
  targets: [
    .target(
      name: "DSHRemoteKit",
      // LES TABLES DE TRADUCTION SONT DES RESSOURCES DE LA BIBLIOTHÈQUE, et c'est
      // une contrainte mesurée, pas un choix. Les vues vivent ici, donc leurs
      // chaînes aussi : une table posée dans la cible d'application iOS ne serait
      // pas vue par l'application macOS, qui est un binaire SwiftPM sans cible
      // Xcode.
      //
      // POURQUOI DES `.lproj/Localizable.strings` ET NON UN CATALOGUE `.xcstrings`,
      // ET C'EST UNE MESURE : SwiftPM *recopie* un `.xcstrings` tel quel, sans le
      // compiler — le paquet de ressources ne contenait alors aucun `.lproj`, et
      // l'interface restait en français même lancée en anglais. Le format
      // classique, lui, est copié tel quel par SwiftPM **et** par Xcode, et il est
      // lu par `Bundle.module` sur les deux plateformes.
      resources: [.process("Ressources")],
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
