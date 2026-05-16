#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=load-env.sh
source "$ROOT/scripts/load-env.sh"

LC_DIR="$REMI_LC_DIR"

command -v docker >/dev/null || _remi_die "Docker is required. Install Docker Desktop for Mac: https://docs.docker.com/desktop/install/mac-install/"

if ! docker info >/dev/null 2>&1; then
  _remi_die "Docker is not running. Start Docker Desktop and try again."
fi

[[ -d "$LC_DIR" ]] || _remi_die "librechat/ not found."

remi_ensure_env_file
remi_export_compose_env
remi_sync_librechat_config

cd "$LC_DIR"

echo "Starting MongoDB and Meilisearch..."
docker compose --env-file "$REMI_ENV_FILE" up -d mongodb meilisearch

echo "Starting REMi (LibreChat + OpenRouter)..."
docker compose --env-file "$REMI_ENV_FILE" up -d api

echo ""
echo "REMi is starting at http://localhost:${PORT}"
echo "Env file: $REMI_ENV_FILE"
echo "Register an account on first visit, then choose OpenRouter models."
echo ""
echo "Logs:  cd librechat && docker compose --env-file ../env.local logs -f api"
echo "Stop:  cd librechat && docker compose --env-file ../env.local down"
