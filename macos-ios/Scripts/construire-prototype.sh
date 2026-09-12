#!/usr/bin/env bash
# Construit le prototype d'interface iOS, l'installe sur un simulateur et le
# lance. Sert à REGARDER le rendu avant d'écrire quoi que ce soit dans
# `Sources/DSHRemoteKit`.
#
# POURQUOI PAS XCODEGEN NI LE PROJET XCODE. Le prototype est un écran, pas une
# application : il se compile avec `swiftc` contre le SDK simulateur, dans un
# paquet `.app` minimal. Aucun projet n'est créé, aucun réglage n'est modifié,
# et le script n'installe rien sur un appareil réel.
#
# Usage :
#   Scripts/construire-prototype.sh [ecran] [appareil]
#
#   ecran    complet (défaut) | carte | sans-mac | reglages
#   appareil nom du simulateur (défaut : « iPhone 17 Pro »)
#
# Exemple :
#   Scripts/construire-prototype.sh carte

set -euo pipefail

ecran="${1:-complet}"
appareil="${2:-iPhone 17 Pro}"

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_swift="$racine/prototype/PrototypeIOS.swift"
sortie="$racine/.build/prototype"
bundle="$sortie/DSHPrototype.app"

if [[ ! -f "$source_swift" ]]; then
  echo "[prototype] source introuvable : $source_swift" >&2
  exit 1
fi

sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"

mkdir -p "$bundle"

echo "[prototype] compilation (ecran=$ecran)"
# `-Onone` et sans signatures : c'est une maquette, pas une livraison.
# `-parse-as-library` est INDISPENSABLE : sans lui, un fichier unique est traité
# comme du code de premier niveau, et `@main` est refusé à la compilation.
xcrun --sdk iphonesimulator swiftc \
  -target arm64-apple-ios17.0-simulator \
  -sdk "$sdk" \
  -parse-as-library \
  -Onone \
  -o "$bundle/DSHPrototype" \
  "$source_swift"

# Info.plist minimal. DEUX CLÉS NE SONT PAS DÉCORATIVES :
#   - `LSApplicationQueriesSchemes` déclare `tailscale`, sans quoi `canOpenURL`
#     rendrait toujours faux et la carte proposerait d'installer une application
#     déjà présente ;
#   - `UILaunchScreen` évite le mode compatibilité, qui rendrait une fenêtre
#     letterboxée et fausserait toute la mise en page observée.
cat >"$bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>DSHPrototype</string>
  <key>CFBundleDisplayName</key><string>Prototype</string>
  <key>CFBundleIdentifier</key><string>org.example.dsh-prototype</string>
  <key>CFBundleExecutable</key><string>DSHPrototype</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>17.0</string>
  <key>LSApplicationQueriesSchemes</key>
  <array><string>tailscale</string></array>
  <key>UILaunchScreen</key><dict/>
  <key>UISupportedInterfaceOrientations</key>
  <array><string>UIInterfaceOrientationPortrait</string></array>
</dict>
</plist>
PLIST

# Le simulateur doit tourner : `simctl install` échoue sur un appareil éteint.
if ! xcrun simctl list devices booted | grep -q "$appareil"; then
  echo "[prototype] demarrage du simulateur « $appareil »"
  xcrun simctl boot "$appareil"
  # Laisser le temps au printemps (SpringBoard) de se lever : installer avant
  # qu'il ne réponde rend un échec trompeur, « device not ready ».
  xcrun simctl bootstatus "$appareil" -b >/dev/null 2>&1 || true
fi

echo "[prototype] installation"
xcrun simctl install "$appareil" "$bundle"

echo "[prototype] lancement"
xcrun simctl terminate "$appareil" org.example.dsh-prototype >/dev/null 2>&1 || true
SIMCTL_CHILD_DSH_ECRAN="$ecran" xcrun simctl launch "$appareil" org.example.dsh-prototype

echo
echo "[prototype] capture :  xcrun simctl io \"$appareil\" screenshot /tmp/prototype-$ecran.png"
