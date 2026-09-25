#!/bin/sh
# Headless tests of the controls (controls.md §8), cameras (cameras.md §10) and minimal HUD (hud.md), including
# a run of scenes/sail_test.tscn with scripted input. Needs the generated boats: when game/generated/boats has
# no wm7.glb, runs run_boat_import_test.sh first. Fails on any failed check, script error or engine error.
# Nothing opens a window.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
godot=${GODOT:-godot}
export GODOT="$godot"

if [ ! -f "$here/generated/boats/wm7.glb" ]; then
    "$here/tests/run_boat_import_test.sh"
fi

# refresh the script class cache and the imports
"$godot" --headless --path "$here" --import >"$here/generated/ui_import.log" 2>&1 || {
    cat "$here/generated/ui_import.log"; echo "import failed"; exit 1; }

failed=0
for t in controls_test cameras_test hud_test; do
    log="$here/generated/$t.log"
    set +e
    "$godot" --headless --path "$here" -s "res://tests/$t.gd" >"$log" 2>&1
    rc=$?
    set -e
    grep -E "^- |FAIL|checks|HUD:" "$log" || true
    if [ $rc -ne 0 ] || grep -qE "SCRIPT ERROR|^ERROR|^WARNING" "$log"; then
        grep -E "SCRIPT ERROR|^ERROR|^WARNING" -A2 "$log" | head -20 || true
        echo "$t failed (full log: $log)"
        failed=1
    fi
done
if [ $failed -ne 0 ]; then
    echo "ui tests failed"
    exit 1
fi
echo "ui tests passed"
