#!/bin/sh
# Runs tests/livery_test.gd headless (data_format.md §8, sail_visuals.md §11.2): the livery files, the fleet rule
# and a painted fleet of both classes. Needs the generated boats (runs run_boat_import_test.sh when they are
# missing). Fails on any script error or failed check.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
godot=${GODOT:-godot}
if [ ! -f "$here/generated/boats/wm7.glb" ] || [ ! -f "$here/generated/boats/wm12.glb" ]; then
    sh "$here/tests/run_boat_import_test.sh"
fi
log="$here/generated/livery_test.log"
set +e
"$godot" --headless --path "$here" -s res://tests/livery_test.gd >"$log" 2>&1
rc=$?
set -e
cat "$log"
if [ $rc -ne 0 ] || grep -qE "SCRIPT ERROR|SHADER ERROR|^ERROR" "$log"; then
    echo "livery test failed"
    exit 1
fi
echo "livery test passed"
