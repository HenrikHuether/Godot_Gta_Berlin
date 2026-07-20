#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="$SCRIPT_DIR/.tools/godot/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$SCRIPT_DIR/.godot-data}"
exec "$SCRIPT_DIR/.tools/godot/usr/bin/godot3" --path "$SCRIPT_DIR" "$@"
