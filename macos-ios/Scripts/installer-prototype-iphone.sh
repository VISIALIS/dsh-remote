#!/usr/bin/env bash
# Construit le prototype d'interface et l'installe sur l'IPHONE RÉEL.
#
# C'est l'étape « regarder sur l'appareil » : le simulateur dit la mise en page,
# l'appareil dit la densité, la taille réelle, le pouce et le verre. Il ne
# remplace pas l'un par l'autre.
#
# POURQUOI UN IDENTIFIANT DISTINCT. Le prototype s'installe sous
# `org.example.DSHRemotePrototype`, jamais sous `org.example.DSHRemote` :
# l'application qui fonctionne reste en place, et une maquette ne peut pas
# écraser l'outil qu'on utilise tous les jours. Le nom affiché est « Prototype
# UI », donc les deux se distinguent sur l'écran d'accueil.
#
# POURQUOI UNE SIGNATURE MANUELLE PLUTÔT QU'AUTOMATIQUE. La machine a DÉJÀ un
# profil de développement `iOS Team Provisioning Profile: org.example.*`, qui
# couvre tout identifiant `org.example.*` et contient l'UDID de l'iPhone. Le
# réutiliser ne demande aucun aller-retour avec le portail Apple, et ne crée
# aucun identifiant d'application nouveau. On signe donc avec ce profil, à la
# main, de façon reproductible.
#
# Usage :
#   Scripts/installer-prototype-iphone.sh [ecran] [identifiant-appareil]
#
#   ecran  complet (défaut) | carte | sans-mac | reglages
#
# L'identifiant d'appareil est DÉCOUVERT automatiquement quand il n'est pas
# fourni : un identifiant d'appareil est une donnée personnelle, qui n'a rien à
# faire dans l'histoire de ce dépôt (RÈGLE #0, interdits #1 et #6). Le script
# interroge donc CoreDevice et refuse de choisir à la place de l'utilisateur
# quand plusieurs appareils sont branchés.

set -euo pipefail

ecran="${1:-complet}"
appareil="${2:-}"

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_swift="$racine/prototype/PrototypeIOS.swift"
profil="$(ls -t "$HOME"/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision 2>/dev/null | head -1)"
sortie="$racine/.build/prototype-iphone"
bundle="$sortie/DSHPrototype.app"

if [[ ! -f "$source_swift" ]]; then
  echo "[prototype] source introuvable : $source_swift" >&2
  exit 1
fi
if [[ -z "${profil:-}" || ! -f "$profil" ]]; then
  echo "[prototype] aucun profil de developpement trouve." >&2
  echo "[prototype] Ouvrez Xcode > Settings > Accounts, ou branchez l'iPhone une fois." >&2
  exit 1
fi

# Découverte de l'appareil : le premier iPhone appairé et prêt au développement.
#
# On lit la sortie JSON de `devicectl` (`result.devices`), pas son tableau : la
# mise en forme du tableau change d'une version de Xcode à l'autre, les noms de
# champs changent beaucoup moins.
#
# `tunnelState` N'EST PAS un critère : mesuré sur cette machine, il vaut
# « disconnected » pour un iPhone appairé et au repos — le tunnel ne s'ouvre
# qu'au moment de l'installation. Filtrer dessus ne trouverait jamais rien.
if [[ -z "$appareil" ]]; then
  liste_json="$sortie/appareils.json"
  mkdir -p "$sortie"
  xcrun devicectl list devices --json-output "$liste_json" >/dev/null 2>&1 || true
  appareil="$(
    plutil -extract result.devices json -o - "$liste_json" 2>/dev/null \
      | python3 -c '
import json, sys

appareils = json.load(sys.stdin)
iphones = [
    a for a in appareils
    if a.get("hardwareProperties", {}).get("platform") == "iOS"
    and a.get("connectionProperties", {}).get("pairingState") == "paired"
    and a.get("deviceProperties", {}).get("developerModeStatus") == "enabled"
]
if not iphones:
    sys.exit(1)
if len(iphones) > 1:
    noms = ", ".join(a.get("deviceProperties", {}).get("name", "?") for a in iphones)
    print(f"plusieurs iPhone disponibles : {noms}", file=sys.stderr)
    sys.exit(2)
print(iphones[0].get("identifier", ""))
' 2>"$sortie/choix-appareil.txt"
  )" || {
    echo "[prototype] impossible de choisir l'appareil automatiquement." >&2
    if [[ -s "$sortie/choix-appareil.txt" ]]; then
      echo "[prototype] $(cat "$sortie/choix-appareil.txt")" >&2
    fi
    echo "[prototype] Branchez l'iPhone, deveillez-le, ou passez son identifiant :" >&2
    echo "  xcrun devicectl list devices" >&2
    exit 1
  }
fi

if [[ -z "$appareil" ]]; then
  echo "[prototype] aucun iPhone disponible trouve." >&2
  echo "[prototype] Branchez l'iPhone, ou verifiez : xcrun devicectl list devices" >&2
  exit 1
fi

identifiant="org.example.DSHRemotePrototype"

echo "[prototype] compilation pour l'appareil (ecran=$ecran)"
rm -rf "$bundle"
mkdir -p "$bundle"
xcrun --sdk iphoneos swiftc \
  -target arm64-apple-ios17.0 \
  -sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -parse-as-library \
  -O \
  -o "$bundle/DSHPrototype" \
  "$source_swift"
# Le nom affiché distingue les deux applications sur l'écran d'accueil ; le
# schéma `tailscale` est déclaré pour que la carte puisse savoir si
# l'application Tailscale est là (voir `PrototypeIOS.swift`).
cat >"$bundle/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Prototype UI</string>
  <key>CFBundleDisplayName</key><string>Prototype UI</string>
  <key>CFBundleIdentifier</key><string>$identifiant</string>
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

# Les droits viennent DU PROFIL, jamais d'un fichier écrit à la main : c'est ce
# qui garantit que l'application signée correspond exactement à ce qu'Apple
# autorise pour cet appareil.
security cms -D -i "$profil" >"$sortie/profil.plist"
plutil -extract Entitlements xml1 -o "$sortie/droits.plist" "$sortie/profil.plist"

echo "[prototype] signature (profil : $(plutil -extract Name raw "$sortie/profil.plist"))"
codesign --force --sign "Apple Development" \
  --entitlements "$sortie/droits.plist" \
  --generate-entitlement-der \
  "$bundle"

# L'identifiant d'appareil N'EST PAS AFFICHÉ : c'est un identifiant personnel,
# et un terminal se capture, s'enregistre et se colle dans un rapport. Le nom de
# l'appareil suffit à savoir de quoi on parle.
echo "[prototype] installation sur l'iPhone"
xcrun devicectl device install app --device "$appareil" "$bundle"

echo
echo "[prototype] installe. Lancement depuis l'ecran d'accueil, ou :"
echo "  xcrun devicectl device process launch --device <identifiant> $identifiant"
echo "  (<identifiant> : voir « xcrun devicectl list devices »)"
echo
echo "[prototype] l'ecran se change SUR L'IPHONE : un appui sur le titre fait"
echo "  defiler les quatre etats (connecte, a installer, aucun Mac, reglages)."
echo "  Une variable d'environnement ne traverse pas un lancement depuis"
echo "  l'ecran d'accueil : l'ecran demande ici n'est qu'un point de depart."
echo
echo "[prototype] cette version de devicectl n'a PAS de capture d'ecran :"
echo "  la capture de l'iPhone se fait par AirDrop ou par Capture d'ecran."
