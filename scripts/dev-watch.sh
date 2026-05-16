#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/MagicPointer.xcodeproj"
SCHEME="MagicPointer"
CONFIGURATION="Debug"
BUILD_LOG="/tmp/mp-build.log"
APP_NAME="MagicPointer"

cleanup() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

build() {
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    build >"$BUILD_LOG" 2>&1
}

app_binary_path() {
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null \
    | awk '
      /TARGET_BUILD_DIR = / { t=$3 }
      /EXECUTABLE_PATH = / { e=$3 }
      END { if (t != "" && e != "") print t "/" e }
    '
}

run_app() {
  local bin
  bin="$(app_binary_path)"
  if [[ -z "$bin" || ! -x "$bin" ]]; then
    echo "Unable to find app binary. See $BUILD_LOG"
    return 1
  fi
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  "$bin" >/tmp/magicpointer-runtime.log 2>&1 &
}

trap cleanup EXIT INT TERM

cd "$ROOT_DIR"
echo "Building $APP_NAME..."
build
echo "Launching $APP_NAME..."
run_app
if ! command -v fswatch >/dev/null 2>&1; then
  echo "fswatch not found — install with: brew install fswatch"
  echo "$APP_NAME is running (no auto-rebuild). Logs: /tmp/magicpointer-runtime.log"
  wait
fi

echo "Watching UI/MagicPointer.swift and UI/main.swift"

fswatch -o "UI/MagicPointer.swift" "UI/main.swift" | while read -r _; do
  echo "Change detected. Rebuilding..."
  if build; then
    echo "Build succeeded. Relaunching..."
    run_app
  else
    echo "Build failed. See $BUILD_LOG"
  fi
done
