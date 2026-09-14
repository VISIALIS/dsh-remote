#!/usr/bin/env bash
# Construit l'application iOS **avec l'exception ATS**, puis laisse la source
# propre.
#
# LE PROBLÈME QUE CE SCRIPT RÉSOUT. L'exception App Transport Security est
# nécessaire pour joindre le Mac en HTTP : sans elle, iOS refuse le clair vers un
# nom qualifié et l'application échoue en `-1022`. Or elle exige d'écrire le nom
# du tailnet dans un fichier — et ce nom ne doit pas entrer dans l'histoire du
# dépôt (RÈGLE #0).
#
# TROIS MÉTHODES ONT ÉTÉ ESSAYÉES ; CE SCRIPT EMPLOIE LA TROISIÈME, LA PLUS SÛRE.
#
#   1. **la phase de script du projet Xcode** (`injecter-exception-ats.sh`) :
#      elle s'exécute APRÈS le traitement de l'Info.plist, et l'injection tient.
#      MESURE DU 13 SEPTEMBRE, Xcode 26.6, DerivedData neuf, Info.plist source
#      propre : l'exception est PRÉSENTE dans le paquet produit, en Debug ET en
#      Release pour le simulateur. Une mesure ANTÉRIEURE (Xcode 26.2, quatre
#      paquets : Debug/Release × simulateur/appareil) donnait ZÉRO exception et
#      avait fait écrire ce script ; elle n'est plus reproductible ici en
#      simulateur, et la configuration « appareil » n'a pas été remesurée.
#      CE QUI RESTE VRAI, ET QUI SUFFIT À JUSTIFIER CE SCRIPT : sans
#      `Config/DomaineTailnet`, le paquet se construit SANS exception et SANS
#      erreur — mesuré également. Un clone produit donc une application qui
#      refuse le tailnet en `-1022`, ce que l'écran d'adresse annonce désormais
#      AVANT l'essai (`ConseilAdresse`) ;
#   2. **injecter dans le paquet puis RE-SIGNER à la main** : la signature est
#      valide (« satisfies its Designated Requirement ») et iOS REFUSE quand même
#      l'installation (IXUserPresentableErrorDomain, sans raison exploitable).
#      La signature automatique d'Xcode n'est pas reproductible à la main ;
#   3. **injecter dans la source, laisser Xcode signer, puis retirer** : c'est
#      celle que fait ce script. Elle reste la plus SÛRE des trois, et c'est ce
#      qui la justifie même quand la phase fonctionne : l'exception est écrite
#      dans l'Info.plist que Xcode lit, donc rien ne peut la réécrire après coup.
#
# La source est nettoyée même si le build échoue (trap), pour qu'aucun commit
# accidentel n'emporte le nom du tailnet.
#
# ATTENTION PENDANT LA CONSTRUCTION : le domaine est alors ÉCRIT dans
# `App/Info.plist`, et `scripts/check-secrets.sh` le refuse — à juste titre, c'est
# le motif « nom de tailnet privé ». MESURÉ : une vérification du dépôt lancée
# pendant ce script échoue sur ce fichier, puis passe dès qu'il a rendu la main.
# Ce n'est pas une fuite, c'est une course : lancez la vérification APRÈS.
#
# Usage : Scripts/construire-app-ios.sh [--simulateur]

set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_plist="$racine/App/Info.plist"
fichier_domaine="$racine/Config/DomaineTailnet"
PB=/usr/libexec/PlistBuddy

if [[ "${1:-}" == "--simulateur" ]]; then
  destination='platform=iOS Simulator,name=iPhone 17 Pro'
  configuration=Debug
  paquet="$racine/.build/iphone/Build/Products/Debug-iphonesimulator/DSHRemote.app"
else
  destination='generic/platform=iOS'
  configuration=Release
  paquet="$racine/.build/iphone/Build/Products/Release-iphoneos/DSHRemote.app"
fi

construire() {
  xcodebuild -project "$racine/DSHRemote.xcodeproj" -scheme DSHRemote \
    -destination "$destination" -configuration "$configuration" \
    -derivedDataPath "$racine/.build/iphone" build 2>&1 |
    grep -E "^/.*error:|BUILD SUCCEEDED|BUILD FAILED" | head -5
}

if [[ ! -f "$fichier_domaine" ]]; then
  echo "[ios] Config/DomaineTailnet absent : construction SANS exception ATS."
  echo "[ios]   publier en HTTPS (tailscale serve --https 443) supprime ce besoin."
  construire
  exit 0
fi

domaine="$(head -n 1 "$fichier_domaine" | tr -d '[:space:]')"
sauvegarde="$(mktemp)"
cp "$source_plist" "$sauvegarde"
nettoyer() {
  cp "$sauvegarde" "$source_plist"
  rm -f "$sauvegarde"
  echo "[ios] source restauree (le domaine n'y figure plus)"
}
trap nettoyer EXIT

$PB -c "Delete :NSAppTransportSecurity" "$source_plist" 2>/dev/null || true
$PB -c "Add :NSAppTransportSecurity dict" "$source_plist"
$PB -c "Add :NSAppTransportSecurity:NSExceptionDomains dict" "$source_plist"
# Le domaine ET son nom court : Tailscale repond aux deux, mais App Transport
# Security apparie les domaines LITTERALEMENT.
for nom in "$domaine" "${domaine%%.*}"; do
  $PB -c "Add :NSAppTransportSecurity:NSExceptionDomains:$nom dict" "$source_plist" 2>/dev/null || true
  $PB -c "Add :NSAppTransportSecurity:NSExceptionDomains:$nom:NSExceptionAllowsInsecureHTTPLoads bool true" "$source_plist" 2>/dev/null || true
done
$PB -c "Add :NSAppTransportSecurity:NSExceptionDomains:$domaine:NSIncludesSubdomains bool true" "$source_plist" 2>/dev/null || true
# Le domaine n'est JAMAIS affiche : un journal de build peut etre partage.

echo "[ios] exception ATS posee dans la source (le temps du build)"
construire

# On VERIFIE le paquet : une exception absente ne se voit qu'a la connexion, en
# -1022, loin de la cause.
if [[ -f "$paquet/Info.plist" ]]; then
  if $PB -c "Print :NSAppTransportSecurity" "$paquet/Info.plist" >/dev/null 2>&1; then
    echo "[ios] exception ATS PRESENTE dans le paquet construit"
  else
    echo "[ios] ATTENTION : le paquet n'a PAS l'exception." >&2
    exit 1
  fi
fi
