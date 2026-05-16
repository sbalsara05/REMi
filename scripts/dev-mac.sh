#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=load-env.sh
source "$ROOT/scripts/load-env.sh"

LC_DIR="$REMI_LC_DIR"

[[ -d "$LC_DIR" ]] || _remi_die "librechat/ not found."

remi_ensure_env_file
remi_export_compose_env
remi_sync_librechat_config
remi_link_librechat_env

cd "$LC_DIR"

echo "Starting MongoDB and Meilisearch (Docker)..."
docker compose --env-file "$REMI_ENV_FILE" up -d mongodb meilisearch

echo ""
echo "Native dev — run in two terminals from librechat/:"
echo "  npm run backend:dev"
echo "  npm run frontend:dev  → http://localhost:3090"
echo ""
echo "Using env from: $REMI_ENV_FILE (linked to librechat/.env)"
