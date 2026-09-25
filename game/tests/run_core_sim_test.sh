#!/bin/sh
# Headless test of the core binding (WM-016.01): builds the GDExtension (game/native/build.sh) when game/bin has
# no library, imports the project, runs tests/core_sim_test.gd (CoreSim through CoreSimSource), then runs the
# core's C API example (core/examples/race_example.c, built in core/build) and checks that the free-sailing boat
# of both runs ends in the same place at the same speed. Fails on any failed check, script error or engine
# error. Nothing opens a window.
#   game/tests/run_core_sim_test.sh [--rebuild]    (--rebuild: run build.sh even when the library exists)
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
repo=$(cd "$here/.." && pwd)
godot=${GODOT:-godot}

if [ "${1:-}" = "--rebuild" ] || ! ls "$here"/bin/libwindmark_godot.* >/dev/null 2>&1; then
    sh "$here/native/build.sh" >/dev/null
fi
sh "$here/native/register.sh"
mkdir -p "$here/generated"

log="$here/generated/core_sim_import.log"
"$godot" --headless --path "$here" --import >"$log" 2>&1 || { cat "$log"; echo "import failed"; exit 1; }

log="$here/generated/core_sim_test.log"
set +e
"$godot" --headless --path "$here" -s res://tests/core_sim_test.gd >"$log" 2>&1
rc=$?
set -e
grep -E "^- |FAIL|checks|free sailing:" "$log" || true
if [ $rc -ne 0 ] || grep -qE "SCRIPT ERROR|^ERROR|^WARNING" "$log"; then
    grep -E "SCRIPT ERROR|^ERROR|^WARNING" -A2 "$log" | head -20 || true
    echo "core sim test failed (full log: $log)"
    exit 1
fi

# the same free sail through the C API example
build="$repo/core/build"
if [ ! -f "$build/build.ninja" ]; then
    cmake -S "$repo/core" -B "$build" -G Ninja >/dev/null
fi
cmake --build "$build" --target windmark_race_example >/dev/null
ours=$(grep "^free sailing: 60 s" "$log")
theirs=$("$build/examples/windmark_race_example" "$repo/data" "$repo/game/data/courses" | grep "^free sailing: 60 s")
if [ "$ours" != "$theirs" ]; then
    echo "free sailing differs from the C API example:"
    echo "  godot:   $ours"
    echo "  example: $theirs"
    exit 1
fi
echo "free sailing matches the C API example"
echo "core sim test passed"
