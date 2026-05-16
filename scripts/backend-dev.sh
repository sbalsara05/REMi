#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=load-env.sh
source "$ROOT/scripts/load-env.sh"

remi_ensure_env_file
remi_link_librechat_env

AUTH_JSON="$REMI_LC_DIR/api/data/auth.json"
if [[ ! -f "$AUTH_JSON" ]]; then
  mkdir -p "$(dirname "$AUTH_JSON")"
  cp "$REMI_LC_DIR/api/test/__mocks__/auth.mock.json" "$AUTH_JSON"
  echo "Created placeholder $AUTH_JSON (OpenRouter-only dev; not used unless you enable Google/Vertex)"
fi

DIST_INDEX="$REMI_LC_DIR/client/dist/index.html"
if [[ ! -f "$DIST_INDEX" ]]; then
  echo "Missing $DIST_INDEX — run once from librechat/: npm run build:client"
  echo "Then use: npm run backend:dev  (not npm run backend)"
  exit 1
fi

cd "$REMI_LC_DIR"
exec npm run backend:dev
