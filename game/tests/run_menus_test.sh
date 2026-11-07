#!/bin/sh
# Headless tests of the menus (docs/specs/menus.md, WM-016.13): the lists from the data on disk, quick race and
# free sail writing GameSetup, keyboard navigation, the settings file round trip, the apply calls, and the pause
# menu over scenes/sail_test.tscn on FakeSim; then the race history file (menus.md §6, tests/history_test.gd).
# Needs the generated boats (runs run_boat_import_test.sh when game/generated/boats has no wm7.glb). Fails on any
# failed check, script error or engine error. Nothing opens a window.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
godot=${GODOT:-godot}
export GODOT="$godot"

if [ ! -f "$here/generated/boats/wm7.glb" ]; then
    "$here/tests/run_boat_import_test.sh"
fi
if ls "$here"/bin/libwindmark_godot.* >/dev/null 2>&1; then
    sh "$here/native/register.sh"
fi
mkdir -p "$here/generated"
"$godot" --headless --path "$here" --import >"$here/generated/menus_import.log" 2>&1 || {
    cat "$here/generated/menus_import.log"; echo "import failed"; exit 1; }

log="$here/generated/menus_test.log"
set +e
"$godot" --headless --path "$here" -s res://tests/menus_test.gd >"$log" 2>&1
rc=$?
set -e
grep -E "^- |FAIL|checks" "$log" || true
if [ $rc -ne 0 ] || grep -qE "SCRIPT ERROR|^ERROR|^WARNING" "$log"; then
    grep -E "SCRIPT ERROR|^ERROR|^WARNING" -A2 "$log" | head -30 || true
    echo "menus test failed (full log: $log)"
    exit 1
fi
echo "menus test passed"

# the race history (menus.md §6, tests/history_test.gd) on a temporary file; its corrupt-file check makes the
# engine report one ConfigFile parse error on that file, which is expected
log="$here/generated/history_test.log"
set +e
"$godot" --headless --path "$here" -s res://tests/history_test.gd >"$log" 2>&1
rc=$?
set -e
grep -E "^- |FAIL|checks" "$log" || true
errors=$(grep -E "SCRIPT ERROR|^ERROR|^WARNING" "$log" | grep -v "ConfigFile parse error at user://history_test.cfg" || true)
if [ $rc -ne 0 ] || [ -n "$errors" ]; then
    echo "$errors" | head -30
    echo "history test failed (full log: $log)"
    exit 1
fi
echo "history test passed"
