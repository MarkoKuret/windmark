#!/bin/sh
# Lists res://bin/windmark.gdextension in game/.godot/extension_list.cfg when the library is built and the entry
# is missing, so Godot loads the extension at start-up (see build.sh). Safe to run any number of times.
set -eu
game=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$game/bin/windmark.gdextension" ] || exit 0
list="$game/.godot/extension_list.cfg"
mkdir -p "$game/.godot"
if ! grep -qx "res://bin/windmark.gdextension" "$list" 2>/dev/null; then
    echo "res://bin/windmark.gdextension" >> "$list"
fi
