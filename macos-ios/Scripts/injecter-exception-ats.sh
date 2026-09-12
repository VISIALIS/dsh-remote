#!/bin/bash
#
# Injecte l'exception App Transport Security dans le .app CONSTRUIT.
#
# POURQUOI CE SCRIPT EXISTE
#
# L'application joint le Mac par le port 80 du nom MagicDNS publie par
# `tailscale serve`, donc en HTTP. App Transport Security bloque le clair vers
# un nom de domaine qualifie : une exception est necessaire.
#
# Mais cette exception impose d'ECRIRE LE NOM DU DOMAINE dans l'Info.plist, et
# un nom de machine ou de tailnet ne doit pas entrer dans l'histoire du depot
# (REGLE #0). J'ai d'abord tente `$(DSH_ATS_DOMAINE)` depuis un xcconfig :
# MESURE, Xcode n'etend pas les variables de build dans les CLES d'un plist.
#
# Ce script resout le probleme autrement : il modifie le paquet construit, et
# jamais les sources. Le nom du domaine vient de `Config/DomaineTailnet` —
# fichier local, ignore par git, ecrit une fois par machine.
#
# Comportement si le fichier est absent : le script NE fait PAS echouer le
# build. Sans exception, l'application se construit et se lance ; seule la
# connexion en HTTP vers un nom de domaine est refusee par iOS. Un echec de
# build serait plus genant que la cause qu'il signale.
#
# ATTENTION — PIEGE QUI A COUTE DEUX ALLERS-RETOURS.
#
# Un build INCREMENTAL ne relance pas toujours cette phase, et le plist reste
# alors celui du build precedent : l'exception disparait SANS AUCUN SIGNAL, et
# l'application installee echoue en `-1022` (App Transport Security) comme si
# le mecanisme n'avait jamais fonctionne. C'est exactement ce qui s'est produit.
#
# Regle : apres toute modification de ce script ou de Config/DomaineTailnet,
# construire avec `clean build`, et VERIFIER le plist du paquet produit avant
# d'installer :
#
#   plutil -p <app>/Info.plist | grep -A4 NSAppTransportSecurity
#
# Pour retirer ce script du projet : supprimer la phase « Exception ATS » dans
# Xcode. L'application redevient strictement ATS, ce qui suffit si l'on publie
# en HTTPS (`tailscale serve --https 443`).

set -u

FICHIER_DOMAINE="${SRCROOT}/Config/DomaineTailnet"

if [ ! -f "${FICHIER_DOMAINE}" ]; then
  echo "note: pas d'exception ATS — ${FICHIER_DOMAINE} absent."
  echo "note: l'application ne pourra pas joindre le Mac en HTTP ; publier en"
  echo "note: HTTPS (tailscale serve --https 443) ou creer ce fichier."
  exit 0
fi

# Une seule ligne, sans commentaire ni espace superflu. On valide la forme
# plutot que de faire confiance : une valeur erronee produirait une exception
# silencieusement inoperante, exactement le piege que ce script evite.
DOMAINE="$(head -n 1 "${FICHIER_DOMAINE}" | tr -d '[:space:]')"

if ! printf '%s' "${DOMAINE}" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$'; then
  echo "erreur: ${FICHIER_DOMAINE} ne contient pas un nom de domaine valide." >&2
  echo "erreur: attendu une seule ligne, par exemple mon-mac.mon-tailnet.ts.net" >&2
  exit 1
fi

PLIST="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"
if [ ! -f "${PLIST}" ]; then
  echo "erreur: Info.plist construit introuvable: ${PLIST}" >&2
  exit 1
fi

/usr/libexec/PlistBuddy -c "Delete :NSAppTransportSecurity" "${PLIST}" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity dict" "${PLIST}"
/usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains dict" "${PLIST}"

# On declare le domaine ET son nom court. Tailscale repond aux deux — verifie :
# `http://<nom-court>` et `http://<nom-court>.<tailnet>.ts.net` rendent tous
# deux 200 — mais App Transport Security apparie les domaines LITTERALEMENT.
# N'en declarer qu'un laisserait l'autre echouer selon ce que l'utilisateur
# saisit, avec une erreur qui ne dit pas qu'il s'agit d'une exception ATS.
/usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains:${DOMAINE} dict" "${PLIST}"
/usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains:${DOMAINE}:NSExceptionAllowsInsecureHTTPLoads bool true" "${PLIST}"

NOM_COURT="${DOMAINE%%.*}"
if [ "${NOM_COURT}" != "${DOMAINE}" ]; then
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains:${NOM_COURT} dict" "${PLIST}" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains:${NOM_COURT}:NSExceptionAllowsInsecureHTTPLoads bool true" "${PLIST}" 2>/dev/null || true
fi

# Le domaine n'est PAS affiche : il n'a pas a se retrouver dans un journal de
# build, qui peut etre partage ou conserve.
echo "note: exception ATS injectee pour le domaine configure."
