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
# POURQUOI `--provisionnement` EXISTE, ET POURQUOI IL EST OPT-IN. Construire pour
# un APPAREIL réclame deux choses que le simulateur ignore : une équipe (lue par
# `Config/Base.xcconfig` dans `Config/Local.xcconfig`, gitignoré) et un profil de
# provisionnement. Sans les deux drapeaux de provisionnement, `xcodebuild`
# s'arrête — et le message change à chaque pièce posée. MESURÉ le 18 septembre
# 2026, dans cet ordre :
#
#   équipe absente  → « Signing for "DSHRemote" requires a development team. »
#   équipe présente → « No profiles for 'org.example.DSHRemote' were found. »
#   les deux drapeaux → BUILD SUCCEEDED, paquet signé, installé sur l'iPhone.
#
# Les drapeaux ne sont PAS posés par défaut : `-allowProvisioningUpdates` fait
# PARLER XCODE À APPLE pendant la construction — émission ou renouvellement du
# certificat de développement, création du profil, enregistrement de l'appareil.
# Une construction ne doit pas ouvrir cette conversation sans qu'on la demande,
# et le simulateur, qui ne signe pas, n'en a jamais besoin.
#
# Usage :
#   Scripts/construire-app-ios.sh [--simulateur] [--provisionnement]
#
#   --simulateur       construit pour le simulateur (Debug ; ne signe pas)
#   --provisionnement  construit pour un APPAREIL, en laissant Xcode créer ou
#                      renouveler certificat et profil. Refusé avec
#                      `--simulateur`, qui ne signe pas.

set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_plist="$racine/App/Info.plist"
fichier_domaine="$racine/Config/DomaineTailnet"
PB=/usr/libexec/PlistBuddy

simulateur=0
provisionnement=0
for argument in "$@"; do
  case "$argument" in
    --simulateur) simulateur=1 ;;
    --provisionnement) provisionnement=1 ;;
    *)
      echo "[ios] argument inconnu : $argument" >&2
      echo "[ios] usage : Scripts/construire-app-ios.sh [--simulateur] [--provisionnement]" >&2
      exit 2
      ;;
  esac
done

# Le simulateur ne signe pas : demander le provisionnement avec lui serait une
# demande sans objet. La refuser vaut mieux que la faire taire — un drapeau
# ignore en silence laisse croire qu'il a agi.
if [[ $simulateur -eq 1 && $provisionnement -eq 1 ]]; then
  echo "[ios] --provisionnement ne s'applique qu'a un appareil reel :" >&2
  echo "[ios]   le simulateur ne signe pas, il n'a donc pas de profil." >&2
  exit 2
fi

if [[ $simulateur -eq 1 ]]; then
  # LA DESTINATION EST GÉNÉRIQUE, ET C'EST UNE MESURE. Elle nommait un appareil
  # précis (« iPhone 17 Pro »), et ce nom a cessé de résoudre quand les runtimes
  # installés ont changé : `xcodebuild` refusait la construction avec « Unable to
  # find a device matching the provided destination specifier », en listant des
  # destinations macOS et watchOS — un message qui n'oriente vers rien. Le script
  # ne fait que CONSTRUIRE (l'installation sur un simulateur précis est un autre
  # geste) : la destination générique suffit et ne périme pas.
  destination='generic/platform=iOS Simulator'
  configuration=Debug
  paquet="$racine/.build/iphone/Build/Products/Debug-iphonesimulator/DSHRemote.app"
else
  destination='generic/platform=iOS'
  configuration=Release
  paquet="$racine/.build/iphone/Build/Products/Release-iphoneos/DSHRemote.app"
fi

construire() {
  # La commande est bâtie en tableau, et ce tableau n'est JAMAIS vide : sous
  # `set -u`, bash 3.2 — celui de macOS — refuse `"${tableau[@]}"` quand il l'est,
  # et l'affectation est donc séparée de la déclaration.
  local commande
  commande=(
    xcodebuild -project "$racine/DSHRemote.xcodeproj" -scheme DSHRemote
    -destination "$destination" -configuration "$configuration"
    -derivedDataPath "$racine/.build/iphone"
  )
  if [[ $provisionnement -eq 1 ]]; then
    echo "[ios] provisionnement automatique : Xcode peut contacter Apple"
    commande+=(-allowProvisioningUpdates -allowProvisioningDeviceRegistration)
  fi
  "${commande[@]}" build 2>&1 |
    grep -E "^/.*error:|BUILD SUCCEEDED|BUILD FAILED" | head -5
}

# L'installation n'est PAS faite ici : ce script construit. L'identifiant de
# l'appareil n'est jamais affiché — c'est une donnée personnelle (RÈGLE #0) — et
# l'identifiant de l'application est LU dans le paquet, jamais supposé, puisque
# `Config/Local.xcconfig` peut le remplacer (`DSH_BUNDLE_ID`).
indiquer_installation() {
  if [[ $simulateur -eq 1 ]]; then
    return 0
  fi
  local identifiant cible
  identifiant="$($PB -c 'Print :CFBundleIdentifier' "$paquet/Info.plist" 2>/dev/null || true)"
  # Le repli est construit par un `if`, et NON par `${identifiant:-<…>}` : une
  # apostrophe dans la forme courte fait parser le reste de la ligne comme une
  # chaîne entre apostrophes, et `bash -n` échoue — mesuré, pas supposé.
  if [[ -n "$identifiant" ]]; then
    cible="$identifiant"
  else
    cible="<identifiant d'application>"
  fi
  echo
  echo "[ios] paquet pour appareil : $paquet"
  echo "[ios] installation (identifiant d'appareil : xcrun devicectl list devices)"
  echo "  xcrun devicectl device install app --device <identifiant> \"$paquet\""
  echo "[ios] lancement : iPhone DEVERROUILLE et joignable, sinon :"
  echo "  ecran verrouille  -> 'Locked'          (mesure du 18 septembre 2026)"
  echo "  tunnel coupe      -> 'The peer is no longer reachable'"
  echo "  xcrun devicectl device process launch --device <identifiant> $cible"
}

if [[ ! -f "$fichier_domaine" ]]; then
  echo "[ios] Config/DomaineTailnet absent : construction SANS exception ATS."
  echo "[ios]   publier en HTTPS (tailscale serve --https 443) supprime ce besoin."
  construire
  indiquer_installation
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

indiquer_installation
