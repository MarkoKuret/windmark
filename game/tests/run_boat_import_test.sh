#!/bin/sh
# Generates the example boats (and the boatgen test fixtures) with tools/boatgen into game/generated/boats (gitignored build output), stages the baked livery textures, imports
# them headless and runs tests/boat_import_test.gd, tests/boat_materials_test.gd and tests/livery_test.gd. Fails on any import error or warning, script error or
# failed check. Options: --no-gen reuses the GLBs already staged.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
repo=$(cd "$here/.." && pwd)
out="$here/generated/boats"
godot=${GODOT:-godot}
classes="wm12 wm7 wm9"
# generator test classes (features no shipped class uses yet, such as a spinnaker pole)
fixtures="$repo/tools/boatgen/tests/fixtures"

if [ "${1:-}" != "--no-gen" ]; then
    mkdir -p "$out"
    args=""
    for c in $classes; do args="$args $repo/data/classes/$c.boat.json"; done
    for f in "$fixtures"/*.boat.json; do args="$args $f"; done
    (cd "$repo/tools/boatgen" && python3 -m boatgen $args --out "$out" --no-previews --quiet)
fi

# the baked livery textures (data/liveries/<class>/), staged for import (tools/liverybake, game/README.md "Liveries")
(cd "$repo/tools/liverybake" && python3 -m liverybake --stage-only --quiet)

log="$here/generated/import.log"
sh "$here/native/register.sh"  # a built GDExtension loads at start-up (native/build.sh)
"$godot" --headless --path "$here" --import >"$log" 2>&1 || { cat "$log"; echo "import failed"; exit 1; }
if grep -E "ERROR|WARNING|SCRIPT ERROR" "$log"; then
    echo "import reported errors or warnings (full log: $log)"
    exit 1
fi
echo "import clean"

log="$here/generated/boat_import_test.log"
set +e
"$godot" --headless --path "$here" -s res://tests/boat_import_test.gd >"$log" 2>&1
rc=$?
set -e
cat "$log"
if [ $rc -ne 0 ] || grep -qE "SCRIPT ERROR|^ERROR" "$log"; then
    echo "boat import test failed"
    exit 1
fi
echo "boat import test passed"

log="$here/generated/boat_materials_test.log"
set +e
"$godot" --headless --path "$here" -s res://tests/boat_materials_test.gd >"$log" 2>&1
rc=$?
set -e
cat "$log"
if [ $rc -ne 0 ] || grep -qE "SCRIPT ERROR|^ERROR" "$log"; then
    echo "boat materials test failed"
    exit 1
fi
echo "boat materials test passed"

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
