// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "EssaiDialogue",
  platforms: [.macOS(.v14)],
  targets: [.executableTarget(name: "EssaiDialogue", path: "Sources")]
)
