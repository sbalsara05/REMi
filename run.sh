#!/usr/bin/env bash
# Start REMi: LibreChat (Docker) + MagicPointer (macOS overlay).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/load-env.sh
source "$ROOT/scripts/load-env.sh"

APP_NAME="MagicPointer"
PROJECT="$ROOT/MagicPointer.xcodeproj"
SCHEME="MagicPointer"
BUILD_LOG="/tmp/remi-magicpointer-build.log"
RUN_LOG="/tmp/magicpointer-runtime.log"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

  Starts the full REMi stack:
    1. LibreChat API + MongoDB + Meilisearch (Docker)
    2. MagicPointer macOS overlay (build + launch)

Options:
  --no-overlay     Start LibreChat only (skip MagicPointer)
  --rebuild-api    Rebuild client + LibreChat API Docker image before start
  -h, --help       Show this help

Stop:
  cd librechat && docker compose -f docker-compose.yml -f ../config/docker-compose.remi.yaml --env-file ../env.local down
  pkill -x MagicPointer
EOF
}

NO_OVERLAY=0
REBUILD_API=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-overlay) NO_OVERLAY=1; shift ;;
    --rebuild-api) REBUILD_API=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

command -v docker >/dev/null || _remi_die "Docker is required. Install Docker Desktop for Mac."

if ! docker info >/dev/null 2>&1; then
  _remi_die "Docker is not running. Start Docker Desktop and try again."
fi

[[ -d "$REMI_LC_DIR" ]] || _remi_die "librechat/ not found."

remi_ensure_env_file
remi_sync_librechat_config
remi_link_librechat_env
remi_export_compose_env

if [[ -x "$ROOT/scripts/sync-mouse-spritesheet.sh" ]]; then
  "$ROOT/scripts/sync-mouse-spritesheet.sh"
fi

cd "$REMI_LC_DIR"
COMPOSE_FILES=(-f docker-compose.yml -f "$REMI_ROOT/config/docker-compose.remi.yaml")

if [[ "$REBUILD_API" -eq 1 ]]; then
  echo "Building LibreChat client (sprites + UI)..."
  (cd "$REMI_LC_DIR" && npm run build:client)
  echo "Rebuilding LibreChat API image..."
  remi_docker_compose "${COMPOSE_FILES[@]}" build api
fi

echo "Starting MongoDB and Meilisearch..."
remi_docker_compose "${COMPOSE_FILES[@]}" up -d mongodb meilisearch

echo "Starting REMi API (LibreChat + OpenRouter)..."
remi_docker_compose "${COMPOSE_FILES[@]}" up -d api

echo ""
echo "LibreChat: http://localhost:${PORT}"

if [[ "$NO_OVERLAY" -eq 1 ]]; then
  echo "Skipping MagicPointer (--no-overlay)."
  exit 0
fi

command -v xcodebuild >/dev/null || _remi_die "Xcode command-line tools required to build MagicPointer."

echo "Building $APP_NAME..."
if ! xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  build >"$BUILD_LOG" 2>&1; then
  echo "Build failed. See $BUILD_LOG" >&2
  exit 1
fi

app_binary_path() {
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -showBuildSettings 2>/dev/null \
    | awk '
      /TARGET_BUILD_DIR = / { t=$3 }
      /EXECUTABLE_PATH = / { e=$3 }
      END { if (t != "" && e != "") print t "/" e }
    '
}

BIN="$(app_binary_path)"
[[ -n "$BIN" && -x "$BIN" ]] || _remi_die "MagicPointer binary not found after build. See $BUILD_LOG"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
"$BIN" >"$RUN_LOG" 2>&1 &

echo ""
echo "MagicPointer launched (logs: $RUN_LOG)"
echo "Open http://localhost:${PORT} to register / chat."
echo ""
echo "Logs:  cd librechat && docker compose --env-file ../env.local logs -f api"
echo "Stop:  cd librechat && docker compose --env-file ../env.local down && pkill -x $APP_NAME"
