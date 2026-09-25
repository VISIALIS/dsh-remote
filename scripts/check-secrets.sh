#!/usr/bin/env bash
#
# Contrôle de sécurité du dépôt DSH Remote — RÈGLE #0.
#
# Vérifie l'absence de secrets, tokens, identifiants réels et données privées,
# tant dans l'arbre de travail que dans l'historique Git complet.
#
# Usage : bash scripts/check-secrets.sh [chemin...]
# Sortie : 0 si conforme, 1 si motif interdit, 2 si pas un dépôt Git.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF_NAME="$(basename "${BASH_SOURCE[0]}")"

if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  printf 'check-secrets : ERREUR - pas un depot git.\n' >&2
  exit 2
fi

status=0
total=0

# 1. Contrôle des identités Git (toute l'histoire)
AUTEURS_NON_CONFORMES="$(git -C "$ROOT" log --all --format='%an <%ae>' | sort -u | grep -vF 'VISIALIS <74245486+VISIALIS@users.noreply.github.com>' | grep -vF 'Sébastien Poulet-Mathis <s.poulet-mathis@visialis.fr>' || true)"
if [ -n "$AUTEURS_NON_CONFORMES" ]; then
  printf '\n[REFUSE] Identite Git non autorisee dans l historique :\n%s\n' "$AUTEURS_NON_CONFORMES"
  status=1
  total=$((total + 1))
fi

# 2. Contrôle des chemins sensibles dans l'histoire Git
CHEMINS_HISTORIQUE="$(git -C "$ROOT" log --all --name-only --format='' | grep -E 'prototype/captures' || true)"
if [ -n "$CHEMINS_HISTORIQUE" ]; then
  printf '\n[REFUSE] Fichiers prototype/captures detectes dans l historique Git.\n'
  status=1
  total=$((total + 1))
fi

# 3. Contrôle des motifs dans les messages de commit
EMAILS_REFUSES="$(git -C "$ROOT" log --all --format='%h %B' | grep -oE '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b' | grep -vF '74245486+VISIALIS@users.noreply.github.com' | grep -vF 'noreply@anthropic.com' | grep -vF 's.poulet-mathis@visialis.fr' || true)"
if [ -n "$EMAILS_REFUSES" ]; then
  printf '\n[REFUSE] Adresse email non autorisee dans les messages de commit :\n%s\n' "$EMAILS_REFUSES"
  status=1
  total=$((total + 1))
fi

TEAMS_REFUSES="$(git -C "$ROOT" log --all --format='%h %B' | grep -E '(DEVELOPMENT_TEAM|TeamIdentifier)[[:space:]]*=[[:space:]]*[A-Z0-9]{10}' || true)"
if [ -n "$TEAMS_REFUSES" ]; then
  printf '\n[REFUSE] Identifiant d equipe Apple dans les messages de commit :\n%s\n' "$TEAMS_REFUSES"
  status=1
  total=$((total + 1))
fi

# 4. Détermination des fichiers à vérifier dans l'arbre de travail
if [ "$#" -eq 0 ]; then
  FILES=()
  while IFS= read -r fichier; do
    if [ -n "$fichier" ]; then
      FILES+=("$ROOT/$fichier")
    fi
  done < <(git -C "$ROOT" ls-files --cached --others --exclude-standard)

  if [ "${#FILES[@]}" -eq 0 ]; then
    printf 'check-secrets : aucun fichier a verifier dans l arbre.\n'
  else
    set -- "${FILES[@]}"
  fi
fi

# Motifs interdits dans le code et les fichiers suivis
PATTERNS=(
  'dsh-auth-[A-Za-z0-9_+/=-]{20,}=v1\.[A-Za-z0-9_-]{20,}|cookie d authentification DSH reel'
  '[?&]token=[A-Za-z0-9_-]{20,}|URL authentifiee portant un jeton'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----|cle privee'
  'gh[pousr]_[A-Za-z0-9]{30,}|jeton GitHub'
  'sk-[A-Za-z0-9_-]{32,}|cle d API de type OpenAI'
  'AKIA[0-9A-Z]{16}|cle AWS'
  'xox[abprs]-[A-Za-z0-9-]{10,}|jeton Slack'
  'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}|JWT'
  '/Users/[A-Za-z0-9._-]+/|chemin absolu local (fuite de nom de compte)'
  '/home/[A-Za-z0-9._-]+/|chemin absolu local (fuite de nom de compte)'
  'macbook-air-de-[a-z0-9-]+|nom de machine local'
  'tail[0-9a-f]{6,}\.ts\.net|nom de tailnet prive'
  'tskey-[A-Za-z0-9]{20,}|cle Tailscale'
  '(DEVELOPMENT_TEAM|DSH_TEAM)[[:space:]]*=[[:space:]]*[A-Z0-9]{10}|identifiant d equipe Apple'
  'TeamIdentifier[[:space:]]*=[[:space:]]*[A-Z0-9]{10}|identifiant d equipe dans une sortie codesign'
  '(^|[^A-Za-z0-9_])[0-9][A-Z0-9]{8}[A-Z]([^A-Za-z0-9_]|$)|jeton de 10 caracteres ressemblant a un identifiant d equipe Apple'
)

if [ "$#" -gt 0 ]; then
  for entry in "${PATTERNS[@]}"; do
    pattern="${entry%|*}"
    label="${entry##*|}"
    hits="$(grep -rInE \
        --binary-files=without-match \
        --exclude-dir=.git \
        --exclude-dir=node_modules \
        --exclude-dir=.build \
        --exclude="$SELF_NAME" \
        -- "$pattern" "$@" 2>/dev/null || true)"
    if [ -n "$hits" ]; then
      total=$((total + 1))
      printf '\n[REFUSE] %s\n' "$label"
      printf '%s\n' "$hits" | sed "s|^$ROOT/|  |"
      status=1
    fi
  done
fi

# 5. Contrôle des motifs dans l'historique complet des diffs (git log -G)
PATTERNS_HISTO=(
  '(DEVELOPMENT_TEAM|DSH_TEAM)[[:space:]]*=[[:space:]]*[A-Z0-9]{10}'
  'TeamIdentifier[[:space:]]*=[[:space:]]*[A-Z0-9]{10}'
  '(^|[^A-Za-z0-9_])[0-9][A-Z0-9]{8}[A-Z]([^A-Za-z0-9_]|$)'
)

for pat in "${PATTERNS_HISTO[@]}"; do
  commits="$(git -C "$ROOT" log -G"$pat" --oneline -- ":(exclude)scripts/$SELF_NAME" || true)"
  if [ -n "$commits" ]; then
    total=$((total + 1))
    printf '\n[REFUSE] Motif interdit "%s" trouve dans l histoire des diffs :\n%s\n' "$pat" "$commits"
    status=1
  fi
done

# 6. Noms d'appareils personnels (« MacBook Air de <Prénom> »), arbre et histoire.
# Les prénoms de fixtures synthétiques sont tolérés via APPAREILS_AUTORISES.
APPAREILS='(iPhone|iPad|MacBook( Air| Pro)?|Mac mini|Mac Studio|iMac)[[:space:]]+(de[[:space:]]+|d['"'"'’])[[:upper:]]'
APPAREILS_AUTORISES='(de[[:space:]]+|d['"'"'’])(Camille|Quelqu)'

APPAREILS_ARBRE=""
if [ "$#" -gt 0 ]; then
  APPAREILS_ARBRE="$(grep -rInE \
      --binary-files=without-match \
      --exclude-dir=.git \
      --exclude-dir=node_modules \
      --exclude-dir=.build \
      --exclude="$SELF_NAME" \
      -- "$APPAREILS" "$@" 2>/dev/null | grep -vE "$APPAREILS_AUTORISES" || true)"
fi
if [ -n "$APPAREILS_ARBRE" ]; then
  total=$((total + 1))
  printf '\n[REFUSE] nom d appareil personnel\n'
  printf '%s\n' "$APPAREILS_ARBRE" | sed "s|^$ROOT/|  |"
  status=1
fi

APPAREILS_HISTO="$(git -C "$ROOT" log --all -p --no-color --format='@@ %h' -- ":(exclude)scripts/$SELF_NAME" \
    | awk '/^@@ [0-9a-f]+$/ { c = $2; next } /^[+-]/ { print c ": " $0 }' \
    | grep -E "$APPAREILS" | grep -vE "$APPAREILS_AUTORISES" | sort -u || true)"
if [ -n "$APPAREILS_HISTO" ]; then
  total=$((total + 1))
  printf '\n[REFUSE] Nom d appareil personnel dans l histoire des diffs :\n%s\n' "$APPAREILS_HISTO"
  status=1
fi

if [ "$status" -eq 0 ]; then
  printf 'check-secrets : aucun motif interdit detecte (arbre et histoire conformes).\n'
else
  printf '\ncheck-secrets : %d probleme(s) detecte(s).\n' "$total"
fi

exit "$status"
