#!/usr/bin/env bash
# ci_post_clone.sh — Script de post-clonage pour Xcode Cloud
#
# Exécuté automatiquement par Xcode Cloud immédiatement après le clone du dépôt.
# 1. Contrôle des secrets du dépôt (RÈGLE #0).
# 2. Exécution de la suite de tests unitaires Swift (swift test).
# 3. Génération de Local.xcconfig à partir des variables d'environnement configurées
#    dans App Store Connect (Xcode Cloud Workflow).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../Config"
LOCAL_XCCONFIG="$CONFIG_DIR/Local.xcconfig"

echo "=== [Xcode Cloud] Début de ci_post_clone.sh ==="

# 1. Contrôle de sécurité (RÈGLE #0)
echo "--- Contrôle de sécurité du dépôt ---"
bash "$REPO_ROOT/scripts/check-secrets.sh"

# 2. Exécution des tests unitaires Swift
echo "--- Exécution des tests Swift (DSHRemoteKitTests) ---"
(cd "$SCRIPT_DIR/.." && swift test)

# 3. Injection dynamique de la signature
echo "--- Configuration de la signature ---"
TEAM_VAL="${DSH_CLOUD_TEAM:-${DSH_TEAM_ID:-${CI_DSH_TEAM:-}}}"
BUNDLE_VAL="${DSH_CLOUD_BUNDLE_ID:-${CI_DSH_BUNDLE_ID:-org.example.DSHRemote}}"
APP_GROUP_VAL="${DSH_CLOUD_APP_GROUP:-${CI_DSH_APP_GROUP:-group.org.example.DSHRemote}}"

if [[ -n "$TEAM_VAL" ]]; then
  echo "Équipe de signature détectée via variables d'environnement."
  cat <<EOF > "$LOCAL_XCCONFIG"
// Fichier généré automatiquement par ci_post_clone.sh (Xcode Cloud)
DSH_TEAM = $TEAM_VAL
DSH_BUNDLE_ID = $BUNDLE_VAL
DSH_APP_GROUP = $APP_GROUP_VAL
EOF
  echo "Local.xcconfig écrit avec succès."
else
  echo "NOTE : DSH_CLOUD_TEAM non configurée dans Xcode Cloud. Le build continuera avec les valeurs par défaut."
fi

echo "=== [Xcode Cloud] ci_post_clone.sh terminé avec succès ==="
