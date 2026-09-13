#!/usr/bin/env bash
# Construit l'application macOS et l'empaquette en `.app`, avec son icône.
#
# POURQUOI CE SCRIPT EXISTE. L'application macOS est un exécutable SwiftPM : un
# binaire NU, sans paquet, sans Info.plist et sans icône. macOS ne peut donc rien
# afficher — pas d'image dans le Dock, rien pour la reconnaître. Constaté sur
# capture : la fenêtre s'ouvrait DERRIÈRE les autres et rien ne permettait de la
# rappeler.
#
# Le paquet est assemblé À LA MAIN plutôt que par Xcode, pour la même raison que
# le prototype iOS : le projet Xcode ne produit qu'une application iOS, et un
# second projet macOS doublerait les réglages à tenir. Un `.app` macOS est une
# arborescence de fichiers — `Contents/MacOS/`, `Contents/Resources/`,
# `Contents/Info.plist` — et rien de plus.
#
# Usage :
#   Scripts/empaqueter-app-macos.sh [--ouvrir]
#
# Sortie : .build/macos/DSH Remote.app

set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sortie="$racine/.build/macos"
bundle="$sortie/DSH Remote.app"
icns="$sortie/DSHRemote.icns"

echo "[macos] construction de l'executable"
swift build --package-path "$racine" --product DSHRemoteMac 2>&1 | tail -1

binaire="$(swift build --package-path "$racine" --show-bin-path)/DSHRemoteMac"
if [[ ! -x "$binaire" ]]; then
  echo "[macos] binaire introuvable : $binaire" >&2
  exit 1
fi

echo "[macos] generation de l'icone"
python3 "$racine/Scripts/generer-icone.py" --icns "$icns" >/dev/null

echo "[macos] assemblage du paquet"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binaire" "$bundle/Contents/MacOS/DSHRemoteMac"
cp "$icns" "$bundle/Contents/Resources/DSHRemote.icns"

# Info.plist minimal, mais pas décoratif :
#   - `CFBundleIconFile` est ce qui donne une icône dans le Dock ;
#   - `LSMinimumSystemVersion` évite un lancement sur un système trop ancien ;
#   - `NSHighResolutionCapable` évite un rendu flou sur écran Retina ;
#   - `CFBundleIdentifier` doit être DISTINCT de celui de l'application iOS :
#     deux applications différentes ne partagent pas un identifiant.
cat >"$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>DSH Remote</string>
  <key>CFBundleDisplayName</key><string>DSH Remote</string>
  <key>CFBundleExecutable</key><string>DSHRemoteMac</string>
  <key>CFBundleIdentifier</key><string>org.example.DSHRemote.mac</string>
  <key>CFBundleIconFile</key><string>DSHRemote</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# L'EXCEPTION ATS EST INDISPENSABLE ICI, ET ELLE A ÉTÉ OUBLIÉE.
#
# Mesuré : sans elle, l'application macOS échoue en `-1022` — « App Transport
# Security refuse le clair vers cet hôte » — dès qu'elle vise une adresse
# tailnet, ALORS QUE l'application iOS fonctionne. La raison : le projet Xcode
# injecte l'exception dans le paquet iOS (phase « Exception ATS »), et le paquet
# macOS assemblé ici ne l'avait pas. Même besoin, deux empaquetages.
#
# Le domaine vient de `Config/DomaineTailnet` — fichier LOCAL, ignoré par git,
# écrit une fois par machine. Il n'entre donc jamais dans l'histoire du dépôt
# (RÈGLE #0) : le paquet construit le porte, les sources non.
fichier_domaine="$racine/Config/DomaineTailnet"
if [[ -f "$fichier_domaine" ]]; then
  domaine="$(tr -d '[:space:]' <"$fichier_domaine")"
  if [[ -n "$domaine" ]]; then
    # POURQUOI PAS `plutil -insert`. Le chemin d'une clé y est une liste de
    # composants séparés par des POINTS… et un nom de domaine EN CONTIENT.
    # Mesuré : `plutil -insert NSAppTransportSecurity.NSExceptionDomains.<domaine>`
    # échoue en « Key path not found », et compose une exception VIDE. Le
    # dictionnaire est donc écrit par `plistlib`, qui traite le nom comme une
    # simple chaîne.
    #
    # `NSIncludesSubdomains` : Tailscale sert chaque machine sous
    # `<machine>.<tailnet>.ts.net`, et la découverte propose ces noms-là.
    python3 - "$bundle/Contents/Info.plist" "$domaine" <<'PY'
import plistlib
import sys

chemin, domaine = sys.argv[1], sys.argv[2]
with open(chemin, "rb") as fichier:
    contenu = plistlib.load(fichier)
contenu["NSAppTransportSecurity"] = {
    "NSExceptionDomains": {
        domaine: {
            "NSExceptionAllowsInsecureHTTPLoads": True,
            "NSIncludesSubdomains": True,
        }
    }
}
with open(chemin, "wb") as fichier:
    plistlib.dump(contenu, fichier)
print(f"[macos] exception ATS posee pour {domaine}")
PY
  fi
else
  echo "[macos] pas d'exception ATS (Config/DomaineTailnet absent) :"
  echo "[macos]   l'application ne joindra pas le Mac en HTTP. Publier en HTTPS"
  echo "[macos]   (tailscale serve --https 443) supprime ce besoin."
fi

# Signature ad hoc : sans elle, macOS traite le paquet comme non signé et
# redemande une autorisation à chaque lancement. Ce n'est PAS une signature de
# distribution — elle ne vaut que pour cette machine.
codesign --force --sign - "$bundle" 2>/dev/null || \
  echo "[macos] signature ad hoc impossible ; le paquet fonctionne quand meme"

# Le cache d'icônes de macOS garde l'ancienne image d'un paquet réécrit : sans
# cette invalidation, on croit que la nouvelle icône n'a pas été prise.
touch "$bundle"

echo "[macos] paquet pret : $bundle"

if [[ "${1:-}" == "--ouvrir" ]]; then
  open "$bundle"
fi
