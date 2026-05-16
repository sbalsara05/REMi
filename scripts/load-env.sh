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
  # Do not assign UID/GID in the shell — macOS defines UID as readonly.
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "$line" =~ ^UID= ]] && continue
    [[ "$line" =~ ^GID= ]] && continue
    export "$line"
  done <"$REMI_ENV_FILE"
  set +a
  export PORT="${PORT:-3080}"
}

# Run docker compose with UID/GID for volume permissions (macOS UID is readonly in zsh/bash).
remi_docker_compose() {
  env UID="$(id -u)" GID="$(id -g)" docker compose --env-file "$REMI_ENV_FILE" "$@"
}

remi_link_librechat_env() {
  ln -sf "$REMI_ENV_FILE" "$REMI_LC_DIR/.env"
  # Absolute path for compose (avoids wrong ../env.local resolution across duplicate REMi folders)
  export REMI_ENV_FILE_ABS="$(cd "$(dirname "$REMI_ENV_FILE")" && pwd)/$(basename "$REMI_ENV_FILE")"
}

remi_sync_librechat_config() {
  cp "$REMI_ROOT/config/librechat.yaml" "$REMI_LC_DIR/librechat.yaml"
}
