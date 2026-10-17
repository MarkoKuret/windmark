#!/bin/sh
# Headless test of the rules scenarios (tests/scenario_test.gd, WM-016.33, race.md §14): the scenario files load,
# the port/starboard scenario calls rule 10 on the port boat in every run with the same checksums, the
# windward/leeward one calls rule 11, the "Who's wrong?" quiz scenarios give their calls (rules 10, 12, 18.2,
# 18.3), and the sail scene runs a scenario to its pause and restarts it. Builds the
# GDExtension when game/bin has none; needs the generated boats (runs run_boat_import_test.sh when missing).
# Nothing opens a window.
#   game/tests/run_scenario_test.sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
godot=${GODOT:-godot}
export GODOT="$godot"
if [ ! -f "$here/generated/boats/wm7.glb" ]; then
    "$here/tests/run_boat_import_test.sh"
fi
if ! ls "$here"/bin/libwindmark_godot.* >/dev/null 2>&1; then
    sh "$here/native/build.sh" >/dev/null
fi
sh "$here/native/register.sh"
mkdir -p "$here/generated"
"$godot" --headless --path "$here" --import >"$here/generated/scenario_import.log" 2>&1 || {
    cat "$here/generated/scenario_import.log"; echo "import failed"; exit 1; }
log="$here/generated/scenario_test.log"
set +e
"$godot" --headless --path "$here" -s res://tests/scenario_test.gd >"$log" 2>&1
rc=$?
set -e
grep -E "^- |FAIL|checks|penalty|^quiz" "$log" || true
if [ $rc -ne 0 ] || grep -qE "SCRIPT ERROR|^ERROR|^WARNING" "$log"; then
    grep -E "SCRIPT ERROR|^ERROR|^WARNING" -A2 "$log" | head -20 || true
    echo "scenario test failed (full log: $log)"
    exit 1
fi
echo "scenario test passed"
