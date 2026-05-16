#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=load-env.sh
source "$ROOT/scripts/load-env.sh"

LC_DIR="$REMI_LC_DIR"

[[ -d "$LC_DIR" ]] || _remi_die "librechat/ not found."

remi_ensure_env_file
remi_sync_librechat_config
remi_link_librechat_env
remi_export_compose_env

cd "$LC_DIR"

COMPOSE_FILES=(-f docker-compose.yml -f "$REMI_ROOT/config/docker-compose.remi.yaml")

mkdir -p "$LC_DIR/meili_data_v1.35.1"

echo "Starting MongoDB, Meilisearch, and RAG (Docker)..."
remi_docker_compose "${COMPOSE_FILES[@]}" up -d mongodb meilisearch vectordb rag_api

echo ""
echo "Native dev — run in two terminals from librechat/:"
echo "  npm run build:client     # first time only (creates client/dist)"
echo "  npm run backend:dev"
echo "  npm run frontend:dev  → http://localhost:3090"
echo ""
echo "Using env from: $REMI_ENV_FILE (linked to librechat/.env)"
