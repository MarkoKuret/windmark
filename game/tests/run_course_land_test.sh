#!/bin/sh
# Headless checks of the venue land, the camera land avoidance, the reset key and the course in race mode
# (tests/course_land_test.gd, WM-016.21 and WM-016.10). Builds the GDExtension when game/bin has none; needs the
# generated boats (runs run_boat_import_test.sh when missing). Nothing opens a window.
#   game/tests/run_course_land_test.sh [--preview]   (--preview: also the offline previews,
#   tests/course_preview_dump.gd then tests/course_preview.py, into game/generated/course_preview)
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
"$godot" --headless --path "$here" --import >"$here/generated/course_land_import.log" 2>&1 || {
    cat "$here/generated/course_land_import.log"; echo "import failed"; exit 1; }
log="$here/generated/course_land_test.log"
set +e
"$godot" --headless --path "$here" -s res://tests/course_land_test.gd >"$log" 2>&1
rc=$?
set -e
grep -E "^- |FAIL|checks" "$log" || true
if [ $rc -ne 0 ] || grep -qE "SCRIPT ERROR|^ERROR|^WARNING" "$log"; then
    grep -E "SCRIPT ERROR|^ERROR|^WARNING" -A2 "$log" | head -20 || true
    echo "course land test failed (full log: $log)"
    exit 1
fi
echo "course land test passed"
if [ "${1:-}" = "--preview" ]; then
    "$godot" --headless --path "$here" -s res://tests/course_preview_dump.gd
    python3 "$here/tests/course_preview.py"
fi
