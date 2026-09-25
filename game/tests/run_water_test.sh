#!/bin/sh
# Water renderer checks (docs/specs/water_render.md §9), all headless:
#   1. builds the core's sample writer (core/tools/gen_sea_render_samples.cpp) and writes the core's sea
#      components, heights, exposure and puff samples to game/generated/sea/sea_render_samples.json;
#   2. imports the project and fails on any error or warning;
#   3. runs tests/water_test.gd: shaders parse, height, slope, puff and exposure parity with the core,
#      far-field fade, wake geometry, and the test scene on every quality tier.
# Options: --preview also renders the offline previews (tests/water_preview_dump.gd, then
# tests/water_preview.py; needs numpy, Pillow, moderngl) into game/generated/water_preview.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
repo=$(cd "$here/.." && pwd)
godot=${GODOT:-godot}
build="$repo/core/build"

if [ ! -f "$build/build.ninja" ]; then
    cmake -S "$repo/core" -B "$build" -G Ninja >/dev/null
fi
cmake --build "$build" --target windmark_gen_sea_render_samples >/dev/null
mkdir -p "$here/generated/sea"
"$build/tests/windmark_gen_sea_render_samples" "$repo/data/venues/example_bay.venue.json" \
    > "$here/generated/sea/sea_render_samples.json"
echo "core samples written"

log="$here/generated/water_import.log"
"$godot" --headless --path "$here" --import >"$log" 2>&1 || { cat "$log"; echo "import failed"; exit 1; }
if grep -E "ERROR|WARNING" "$log"; then
    echo "import reported errors or warnings (full log: $log)"
    exit 1
fi
echo "import clean"

log="$here/generated/water_test.log"
set +e
"$godot" --headless --path "$here" -s res://tests/water_test.gd >"$log" 2>&1
rc=$?
set -e
cat "$log"
if [ $rc -ne 0 ] || grep -qE "SCRIPT ERROR|SHADER ERROR|^ERROR" "$log"; then
    echo "water test failed"
    exit 1
fi
echo "water test passed"

if [ "${1:-}" = "--preview" ]; then
    "$godot" --headless --path "$here" -s res://tests/water_preview_dump.gd
    python3 "$here/tests/water_preview.py"
fi
