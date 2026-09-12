#!/usr/bin/env bash
# Copie le jeton d'appareil courant dans le PRESSE-PAPIER du Mac.
#
# POURQUOI CET OUTIL EXISTE. Le jeton fait 43 caractères en base64url : il ne se
# recopie pas à la main, et le rouvrir dans un terminal pour le sélectionner est
# exactement ce que la RÈGLE #0 interdit de banaliser (un terminal se capture,
# s'enregistre et se colle dans un rapport). Ici, la valeur ne passe QUE par le
# presse-papier : elle n'est jamais affichée, jamais journalisée, et l'outil ne
# rend qu'une longueur et une empreinte — de quoi vérifier que c'est le bon
# jeton, sans le révéler.
#
# Usage :
#   Scripts/copier-jeton-appareil.sh
#
# Ensuite, sur l'iPhone : Réglages (l'engrenage) > Jeton > le bouton presse-papier.
#
# NOTE : le presse-papier du Mac n'est PAS partagé avec l'iPhone. Selon la
# configuration, « Coller » sur l'iPhone peut proposer le presse-papier partagé
# d'Apple (Handoff) ; sinon, lisez la valeur avec `pbpaste` et recopiez-la. Ce
# script supprime une étape, il n'en supprime pas deux.

set -euo pipefail

coffre="${DSH_REMOTE_COFFRE:-$HOME/.dsh/.credentials.yaml}"

if [[ ! -r "$coffre" ]]; then
  echo "[jeton] coffre illisible : $coffre" >&2
  exit 1
fi

# Lecture ciblée sur l'enregistrement `dsh-remote/device-token`.
#
# POURQUOI PAS UN `grep` DU PREMIER JETON. Le coffre contient plusieurs secrets
# de 43 caractères — dont celui qui signe les cookies du navigateur. Prendre le
# premier venu produit un `401` indiscernable d'un jeton tronqué : c'est
# précisément le piège documenté dans le README du plugin.
jeton="$(
  awk '
    /^  dsh-remote\/device-token:/ { dans = 1; next }
    dans && /^  [A-Za-z]/ { dans = 0 }
    dans && /^[[:space:]]+token:/ {
      sub(/^[[:space:]]+token:[[:space:]]*/, "")
      gsub(/["\x27]/, "")
      print
      exit
    }
  ' "$coffre"
)"

if [[ -z "$jeton" ]]; then
  echo "[jeton] aucun enregistrement dsh-remote/device-token dans le coffre." >&2
  echo "[jeton] Le plugin le cree au premier chargement : voir sa sortie terminal." >&2
  exit 1
fi

if [[ ${#jeton} -ne 43 ]]; then
  echo "[jeton] longueur inattendue : ${#jeton} caracteres au lieu de 43." >&2
  exit 1
fi

printf '%s' "$jeton" | pbcopy

# Empreinte FNV-1a tronquee — la meme que l'application calcule et affiche.
# Elle permet de comparer DEUX jetons sans jamais exposer l'un ni l'autre.
empreinte="$(printf '%s' "$jeton" | python3 -c '
import sys
acc = 0xcbf29ce484222325
for octet in sys.stdin.buffer.read():
    acc ^= octet
    acc = (acc * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
print("".join(f"{(acc >> (i * 8)) & 0xFF:02x}" for i in range(8)))
')"

echo "[jeton] copie dans le presse-papier : 43 caracteres, empreinte $empreinte"
echo "[jeton] sur l'iPhone : engrenage > Jeton > bouton presse-papier > Se connecter"
