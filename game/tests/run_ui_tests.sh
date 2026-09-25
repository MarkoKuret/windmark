#!/bin/sh
# Headless tests of the controls (controls.md §8), cameras (cameras.md §10) and minimal HUD (hud.md), including
# runs of scenes/sail_test.tscn with scripted input on the core (free sailing on example_bay; the GDExtension is
# built when missing) and on FakeSim with the example bay sea. Needs the generated boats: when
# game/generated/boats has no wm7.glb, runs run_boat_import_test.sh first; when game/generated/sea has no core
# samples, writes them as run_water_test.sh does. Fails on any failed check, script error or engine error.
# Nothing opens a window.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
godot=${GODOT:-godot}
export GODOT="$godot"

if [ ! -f "$here/generated/boats/wm7.glb" ]; then
    "$here/tests/run_boat_import_test.sh"
fi

if [ ! -f "$here/generated/sea/sea_render_samples.json" ]; then
    repo=$(cd "$here/.." && pwd)
    build="$repo/core/build"
    if [ ! -f "$build/build.ninja" ]; then
        cmake -S "$repo/core" -B "$build" -G Ninja >/dev/null
    fi
    cmake --build "$build" --target windmark_gen_sea_render_samples >/dev/null
    mkdir -p "$here/generated/sea"
    "$build/tests/windmark_gen_sea_render_samples" "$repo/data/venues/example_bay.venue.json" \
        > "$here/generated/sea/sea_render_samples.json"
fi

# the sail test scene runs on the core: build the GDExtension when game/bin has no library
if ! ls "$here"/bin/libwindmark_godot.* >/dev/null 2>&1; then
    sh "$here/native/build.sh" >/dev/null
fi

# refresh the script class cache and the imports
sh "$here/native/register.sh"  # a built GDExtension loads at start-up (native/build.sh)
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
