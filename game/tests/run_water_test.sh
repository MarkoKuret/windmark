#!/bin/sh
# Water renderer checks (docs/specs/water_render.md §9), all headless:
#   1. builds the core's sample writer (core/tools/gen_sea_render_samples.cpp) and writes the core's sea
#      components, heights, exposure and puff samples to game/generated/sea/sea_render_samples.json;
#   2. imports the project and fails on any error or warning;
#   3. runs tests/water_test.gd: shaders parse, height, slope, puff and exposure parity with the core,
#      far-field fade, wake geometry, and the test scene on every quality tier;
#   4. runs tests/wakes_native_test.gd: the native wakes (SeaSampler, WakeRibbon, BowWaveSheets, MistCloud) against
#      their GDScript references and Godot's buffer encoding, and the cost per boat of both (passes with a note
#      when the GDExtension is not built);
#   5. runs tests/boat_shadow_test.gd: the drawn boat shadows of tiers L and M on the sail scene (§9.10), the native
#      geometry against the GDScript reference and the cost per boat.
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
"$build/tests/windmark_gen_sea_render_samples" "$repo/data/venues/practice_waters.venue.json" \
    > "$here/generated/sea/sea_render_samples.json"
echo "core samples written"

log="$here/generated/water_import.log"
sh "$here/native/register.sh"  # a built GDExtension loads at start-up (native/build.sh)
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

# the native wakes against their GDScript references (only when the GDExtension is built: native/build.sh)
log="$here/generated/wakes_native_test.log"
set +e
"$godot" --headless --path "$here" -s res://tests/wakes_native_test.gd >"$log" 2>&1
rc=$?
set -e
grep -E "^- |^  |FAIL|checks|native wakes" "$log" || true
if [ $rc -ne 0 ] || grep -qE "SCRIPT ERROR|SHADER ERROR|^ERROR|^WARNING" "$log"; then
    echo "native wakes test failed (full log: $log)"
    exit 1
fi
echo "native wakes test passed"

# the drawn boat shadows (water_render.md §4.7, test §9.10) on the sail scene with the core (needs the generated
# boats and the GDExtension; passes with a note without the extension)
log="$here/generated/boat_shadow_test.log"
set +e
"$godot" --headless --path "$here" -s res://tests/boat_shadow_test.gd >"$log" 2>&1
rc=$?
set -e
grep -E "^- |^  |FAIL|checks|skipped" "$log" || true
if [ $rc -ne 0 ] || grep -qE "SCRIPT ERROR|SHADER ERROR|^ERROR|^WARNING" "$log"; then
    echo "boat shadow test failed (full log: $log)"
    exit 1
fi
echo "boat shadow test passed"

if [ "${1:-}" = "--preview" ]; then
    "$godot" --headless --path "$here" -s res://tests/water_preview_dump.gd
    python3 "$here/tests/water_preview.py"
fi
