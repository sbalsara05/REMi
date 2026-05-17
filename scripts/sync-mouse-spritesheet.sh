#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/librechat/client/public/assets/mouse-spritesheet.png"
DST="$ROOT/UI/Resources/mouse-spritesheet.png"

if [[ ! -f "$SRC" ]]; then
  echo "Missing source spritesheet: $SRC" >&2
  exit 1
fi

mkdir -p "$(dirname "$DST")"
cp "$SRC" "$DST"
echo "Synced mouse-spritesheet.png → UI/Resources/"
