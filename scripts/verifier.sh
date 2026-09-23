#!/usr/bin/env bash
#
# Suite complète de vérification pour DSH Remote.
#
# Exécute :
# 1. Contrôle des secrets et de l'historique (RÈGLE #0)
# 2. Tests unitaires et d'intégration du plugin hôte
# 3. Tests unitaires et d'intégration de l'application macOS/iOS (DSHRemoteKit)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

printf '=== 1/3 Contrôle des secrets et de l historique ===\n'
bash "$ROOT/scripts/check-secrets.sh"

printf '\n=== 2/3 Tests du plugin hôte ===\n'
(cd "$ROOT" && node --test plugin/tests/)

printf '\n=== 3/3 Tests de l application Swift (macOS & iOS) ===\n'
(cd "$ROOT/macos-ios" && swift test)

printf '\n✓ Toutes les vérifications ont réussi.\n'
