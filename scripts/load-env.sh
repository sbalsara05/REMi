#!/usr/bin/env bash
# Shared REMi env helpers. Source from other scripts:
#   source "$(dirname "$0")/load-env.sh"

REMI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMI_ENV_FILE="${REMI_ENV_FILE:-$REMI_ROOT/env.local}"
REMI_ENV_TEMPLATE="${REMI_ENV_TEMPLATE:-$REMI_ROOT/env.local.example}"
REMI_LC_DIR="${REMI_LC_DIR:-$REMI_ROOT/librechat}"

_remi_die() {
  echo "error: $*" >&2
  exit 1
}

remi_ensure_env_file() {
  if [[ ! -f "$REMI_ENV_FILE" ]]; then
    cp "$REMI_ENV_TEMPLATE" "$REMI_ENV_FILE"
    echo "Created $REMI_ENV_FILE — set OPENROUTER_KEY, then run again."
    exit 1
  fi

  if ! grep -qE '^OPENROUTER_KEY=.+' "$REMI_ENV_FILE" 2>/dev/null; then
    _remi_die "Set OPENROUTER_KEY in $REMI_ENV_FILE (https://openrouter.ai/keys)"
  fi
}

remi_export_compose_env() {
  set -a
  # shellcheck disable=SC1090
  source "$REMI_ENV_FILE"
  set +a
  export UID="${UID:-$(id -u)}"
  export GID="${GID:-$(id -g)}"
  export PORT="${PORT:-3080}"
}

remi_link_librechat_env() {
  ln -sf "$REMI_ENV_FILE" "$REMI_LC_DIR/.env"
}

remi_sync_librechat_config() {
  cp "$REMI_ROOT/config/librechat.yaml" "$REMI_LC_DIR/librechat.yaml"
}
