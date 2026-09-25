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
#   Scripts/empaqueter-app-macos.sh [--ouvrir] [--installer]
#
#   --ouvrir     ouvre le paquet construit (celui du dépôt)
#   --installer  remplace la copie de /Applications par ce paquet, vérifie son
#                empreinte, puis l'ouvre. C'est le seul chemin qui garantit que
#                l'application LANCÉE est bien celle qu'on vient de construire.
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
# `--icns-seul`, ET C'EST UN CORRECTIF MESURÉ. Le générateur réécrivait AUSSI les
# trois PNG de 1024 px du catalogue iOS, qui appartiennent à Xcode : chaque
# empaquetage macOS salissait donc trois fichiers VERSIONNÉS, avec un diff que
# personne ne peut juger (encodage de Pillow ; et 42 pixels d'anti-aliasing sur un
# million pour la variante sombre, mesuré le 18 septembre 2026). Un diff qu'on ne
# peut pas juger est un diff qu'on apprend à ignorer — et le jour où l'icône change
# vraiment, on ne le voit plus. Le catalogue iOS se régénère donc explicitement,
# quand l'icône change, jamais comme effet de bord d'une compilation du Mac.
python_cmd="python3"
if ! "$python_cmd" -c "import PIL" >/dev/null 2>&1 && /usr/bin/python3 -c "import PIL" >/dev/null 2>&1; then
  python_cmd="/usr/bin/python3"
fi
"$python_cmd" "$racine/Scripts/generer-icone.py" --icns-seul --icns "$icns" >/dev/null

echo "[macos] assemblage du paquet"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binaire" "$bundle/Contents/MacOS/DSHRemoteMac"
cp "$icns" "$bundle/Contents/Resources/DSHRemote.icns"

# ── LES TABLES DE TRADUCTION, SANS LESQUELLES L'ANGLAIS EST MORT ──────────────
#
# DÉFAUT RÉEL, TROUVÉ EN VÉRIFIANT LE PAQUET INSTALLÉ : il ne contenait AUCUN
# `Localizable.strings`. L'anglais ne tenait donc qu'à un CHEMIN ABSOLU du
# dossier de construction, que l'accesseur engendré par SwiftPM utilise en repli
# (« /Users/<qui-a-compile>/.build/… ») : sur cette machine, tout allait bien ;
# ailleurs, `L()` et `T()` retombaient sur la clé, donc sur le français, sans
# erreur ni trace.
#
# ET SANS CE PAQUET, L'APPLICATION NE SE CONTENTE PAS DE PARLER FRANÇAIS : ELLE
# MEURT. Mesuré le 14 septembre 2026 sur ce même paquet, avant cette copie —
# `Fatal error: unable to find bundle named DSHRemote_DSHRemoteKit`, au premier
# mot traduit, alors que le script venait d'annoncer « paquet pret », empreinte
# bonne et signature valide. Trois rapports de plantage ont été produits avant
# que la cause soit lue.
#
# POURQUOI `Contents/Resources/` ET NON LA RACINE. L'accesseur de SwiftPM cherche
# à la racine du `.app` — et `codesign` REFUSE alors le paquet : « unsealed
# contents present in the bundle root », mesuré. Un paquet signé ne tolère que
# `Contents/` à sa racine. Côté code, `Traduction` cherche donc lui-même, en
# commençant par `Contents/Resources/` (voir `paquetDeRessources`), et c'est ce
# candidat-là qui rend le paquet vivant.
#
# La copie a lieu AVANT la signature, plus bas, pour qu'elle couvre les tables.
ressources="$(dirname "$binaire")/DSHRemote_DSHRemoteKit.bundle"
if [[ -d "$ressources" ]]; then
  cp -R "$ressources" "$bundle/Contents/Resources/DSHRemote_DSHRemoteKit.bundle"
  echo "[macos] tables de traduction : $(find "$bundle/Contents/Resources/DSHRemote_DSHRemoteKit.bundle" -name '*.strings' | wc -l | tr -d ' ') fichier(s)"
else
  echo "[macos] ATTENTION : paquet de ressources introuvable ($ressources)" >&2
  echo "[macos]   l'application s'affichera en francais seulement (repli sur les cles)" >&2
fi

# ── L'EXTENSION WIDGETKIT (macOS) ─────────────────────────────────────────────
#
# Assemble le paquet d'extension WidgetKit pour macOS dans `Contents/PlugIns/`.
# Permet au Centre de Notifications et au Bureau de macOS de proposer les
# widgets DSH Remote (formats Small et Medium).
# Le groupe est celui du xcconfig local s'il existe, sinon le placeholder du
# dépôt. On ne l'écrit pas dans le journal : un groupe personnel n'a pas à y
# figurer (RÈGLE #0).
groupe_app="group.org.example.DSHRemote"
bundle_id="org.example.DSHRemote"
if [[ -f "$racine/Config/Local.xcconfig" ]]; then
  lu="$(sed -n 's/^[[:space:]]*DSH_APP_GROUP[[:space:]]*=[[:space:]]*//p' "$racine/Config/Local.xcconfig" | head -1)"
  lu="${lu%%#*}"
  lu="$(printf '%s' "$lu" | tr -d '[:space:]')"
  if [[ "$lu" =~ ^[A-Za-z0-9._-]+$ ]]; then
    groupe_app="$lu"
  fi
  lu_bid="$(sed -n 's/^[[:space:]]*DSH_BUNDLE_ID[[:space:]]*=[[:space:]]*//p' "$racine/Config/Local.xcconfig" | head -1)"
  lu_bid="${lu_bid%%#*}"
  lu_bid="$(printf '%s' "$lu_bid" | tr -d '[:space:]')"
  if [[ "$lu_bid" =~ ^[A-Za-z0-9._-]+$ ]]; then
    bundle_id="$lu_bid"
  fi
fi
entitlements_groupe="$(mktemp)"
cat >"$entitlements_groupe" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>${groupe_app}</string>
  </array>
</dict>
</plist>
EOF

entitlements_widget="$(mktemp)"
cat >"$entitlements_widget" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>${groupe_app}</string>
  </array>
</dict>
</plist>
EOF

echo "[macos] compilation de l'extension widget (WidgetKit)"
dir_bin="$(dirname "$binaire")"
appex="$bundle/Contents/PlugIns/DSHRemoteWidgets.appex"
mkdir -p "$appex/Contents/MacOS" "$appex/Contents/Resources"

arch="$(uname -m)"
swiftc \
  -target "${arch}-apple-macos14.0" \
  -I "$dir_bin" \
  -L "$dir_bin" \
  -lDSHRemoteKit \
  -framework WidgetKit -framework SwiftUI \
  "$racine/Widgets/DSHRemoteWidgetsBundle.swift" \
  "$racine/Widgets/DSHRemoteWidget.swift" \
  "$racine/Widgets/FournisseurTimeline.swift" \
  -o "$appex/Contents/MacOS/DSHRemoteWidgets"

cat >"$appex/Contents/Info.plist" <<'PLIST_WIDGET'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleDisplayName</key><string>DSH Remote Widgets</string>
	<key>CFBundleLocalizations</key>
	<array>
		<string>en</string>
		<string>fr</string>
	</array>
	<key>CFBundleExecutable</key><string>DSHRemoteWidgets</string>
	<key>CFBundleIdentifier</key><string>IDENTIFIANT_WIDGET</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>DSHRemoteWidgets</string>
	<key>CFBundlePackageType</key><string>XPC!</string>
	<key>CFBundleShortVersionString</key><string>0.2</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>MacOSX</string>
	</array>
	<key>CFBundleVersion</key><string>3</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>DSHAppGroup</key><string>GROUPE_APP</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.widgetkit-extension</string>
	</dict>
</dict>
</plist>
PLIST_WIDGET

# Le heredoc ci-dessus est quoté : les identifiants sont posés après, sans les imprimer.
sed -i '' "s/GROUPE_APP/${groupe_app}/" "$appex/Contents/Info.plist"
sed -i '' "s/IDENTIFIANT_WIDGET/${bundle_id}.Widgets/" "$appex/Contents/Info.plist"

if [[ -d "$ressources" ]]; then
  cp -R "$ressources" "$appex/Contents/Resources/DSHRemote_DSHRemoteKit.bundle"
fi

codesign --force --sign - --entitlements "$entitlements_widget" "$appex" 2>/dev/null || true
rm -f "$entitlements_widget"
echo "[macos] extension widget prete : PlugIns/DSHRemoteWidgets.appex"


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
  <key>CFBundleIdentifier</key><string>IDENTIFIANT_APP</string>
  <key>CFBundleIconFile</key><string>DSHRemote</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <!--
    LES LANGUES SERVIES : l'anglais est la langue principale (en),
    avec le français (fr) comme langue localisée si c'est la langue de l'OS.
  -->
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>fr</string>
  </array>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>DSHAppGroup</key><string>GROUPE_APP</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>IDENTIFIANT_APP</string>
      <key>CFBundleURLSchemes</key>
      <array><string>dshremote</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

sed -i '' "s/GROUPE_APP/${groupe_app}/" "$bundle/Contents/Info.plist"
sed -i '' "s/IDENTIFIANT_APP/${bundle_id}/" "$bundle/Contents/Info.plist"

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
# Le domaine n'est PAS affiche : un journal de build peut etre partage ou
# conserve, et un nom de tailnet n'a pas a y figurer (REGLE #0). On dit
# seulement combien d'etiquettes il porte, de quoi verifier qu'il est complet.
print(f"[macos] exception ATS posee ({domaine.count('.') + 1} etiquettes, sous-domaines inclus)")
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
codesign --force --sign - --entitlements "$entitlements_groupe" "$bundle" 2>/dev/null || \
  echo "[macos] signature ad hoc impossible ; le paquet fonctionne quand meme"
rm -f "$entitlements_groupe"

# Le cache d'icônes de macOS garde l'ancienne image d'un paquet réécrit : sans
# cette invalidation, on croit que la nouvelle icône n'a pas été prise.
touch "$bundle"

echo "[macos] paquet pret : $bundle"

ouvrir=0
installer=0
for argument in "$@"; do
  case "$argument" in
  --ouvrir) ouvrir=1 ;;
  --installer)
    installer=1
    ouvrir=1
    ;;
  *)
    echo "[macos] option inconnue : $argument" >&2
    exit 2
    ;;
  esac
done

# ── Installation dans /Applications ───────────────────────────────────────────
#
# POURQUOI CETTE OPTION EXISTE. Le paquet construit vit dans `.build/macos/`, et
# rien ne le relie à la copie de `/Applications` que l'utilisateur lance
# réellement. Constaté : une copie installée à 02:16 continuait d'être lancée à
# 08:41 pendant que le dépôt contenait déjà deux correctifs — l'écran montrait
# donc les anciens défauts, et on cherchait la cause dans le code. Deux versions
# du même nom, aucune ne se sachant l'autre.
cible="/Applications/DSH Remote.app"
if [[ "$installer" -eq 1 ]]; then
  # Quitter l'instance en cours AVANT de remplacer : un paquet remplacé sous une
  # application ouverte laisse l'ancien binaire en mémoire, et l'utilisateur
  # croit avoir mis à jour ce qu'il regarde.
  if pgrep -f "$cible/Contents/MacOS/DSHRemoteMac" >/dev/null 2>&1; then
    echo "[macos] fermeture de l'instance en cours"
    pkill -f "$cible/Contents/MacOS/DSHRemoteMac" 2>/dev/null || true
    sleep 1
  fi
  rm -rf "$cible"
  # `ditto` et non `cp -R` : il préserve la structure du paquet et sa signature.
  ditto "$bundle" "$cible"

  # VÉRIFICATION — c'est elle qui rend la dérive impossible. Sans elle, une copie
  # partielle ou refusée passerait inaperçue, et l'écran mentirait de nouveau.
  empreinte_construite="$(shasum -a 256 "$bundle/Contents/MacOS/DSHRemoteMac" | cut -d' ' -f1)"
  empreinte_installee="$(shasum -a 256 "$cible/Contents/MacOS/DSHRemoteMac" | cut -d' ' -f1)"
  if [[ "$empreinte_construite" != "$empreinte_installee" ]]; then
    echo "[macos] ECHEC : la copie installee differe du paquet construit" >&2
    exit 1
  fi
  if ! /usr/libexec/PlistBuddy -c "Print :NSAppTransportSecurity" "$cible/Contents/Info.plist" >/dev/null 2>&1; then
    echo "[macos] ATTENTION : le paquet installe n'a PAS d'exception ATS." >&2
    echo "[macos]   il ne joindra aucun Mac en HTTP (erreur -1022) : voir Config/DomaineTailnet." >&2
  fi

  # Enregistrement auprès de LaunchServices et PluginKit pour les widgets macOS
  lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  if [[ -x "$lsregister" ]]; then
    "$lsregister" -f -R "$cible" >/dev/null 2>&1 || true
    "$lsregister" -f "$cible/Contents/PlugIns/DSHRemoteWidgets.appex" >/dev/null 2>&1 || true
  fi
  pluginkit -a "$cible/Contents/PlugIns/DSHRemoteWidgets.appex" 2>/dev/null || true

  echo "[macos] installe et verifie : $cible"
fi

if [[ "$ouvrir" -eq 1 ]]; then
  if [[ "$installer" -eq 1 ]]; then open "$cible"; else open "$bundle"; fi
fi
