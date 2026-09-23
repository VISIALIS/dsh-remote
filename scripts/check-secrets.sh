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
AUTEURS_NON_CONFORMES="$(git -C "$ROOT" log --all --format='%an <%ae>' | sort -u | grep -vF 'VISIALIS <74245486+VISIALIS@users.noreply.github.com>' || true)"
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
MESSAGES_REFUSES="$(git -C "$ROOT" log --all --format='%h %B' | grep -iE 'adresse-privee|fr\.exemple\.|espace-prive' || true)"
if [ -n "$MESSAGES_REFUSES" ]; then
  printf '\n[REFUSE] Donnee privee detectee dans les messages de commit :\n%s\n' "$MESSAGES_REFUSES"
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
  'tail[0-9a-f]{6,}\.ts\.net|nom de tailnet prive'
  'tskey-[A-Za-z0-9]{20,}|cle Tailscale'
  '(DEVELOPMENT_TEAM|DSH_TEAM)[[:space:]]*=[[:space:]]*[A-Z0-9]{10}|identifiant d equipe Apple'
  'TeamIdentifier[[:space:]]*=[[:space:]]*[A-Z0-9]{10}|identifiant d equipe dans une sortie codesign'
  'fr\.exemple\.|domaine personnel dans identifiant de paquet'
  'adresse-privee|adresse email privee'
  'espace-prive|nom d espace de travail reel'
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
  'fr\.exemple\.'
  'adresse-privee'
  'espace-prive'
)

for pat in "${PATTERNS_HISTO[@]}"; do
  commits="$(git -C "$ROOT" log -G"$pat" --oneline -- ":(exclude)scripts/$SELF_NAME" || true)"
  if [ -n "$commits" ]; then
    total=$((total + 1))
    printf '\n[REFUSE] Motif interdit "%s" trouve dans l histoire des diffs :\n%s\n' "$pat" "$commits"
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  printf 'check-secrets : aucun motif interdit detecte (arbre et histoire conformes).\n'
else
  printf '\ncheck-secrets : %d probleme(s) detecte(s).\n' "$total"
fi

exit "$status"
