#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$SCRIPT_DIR/.godot-data}"

LOCAL_GODOT="$SCRIPT_DIR/.tools/godot/usr/bin/godot3"
if [[ -x "$LOCAL_GODOT" ]]; then
	export LD_LIBRARY_PATH="$SCRIPT_DIR/.tools/godot/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
	exec "$LOCAL_GODOT" --path "$SCRIPT_DIR" "$@"
elif command -v godot3 >/dev/null 2>&1; then
	exec godot3 --path "$SCRIPT_DIR" "$@"
elif command -v godot >/dev/null 2>&1; then
	exec godot --path "$SCRIPT_DIR" "$@"
else
	echo "Godot 3 was not found. Install it with: sudo apt install godot3" >&2
	exit 1
fi
