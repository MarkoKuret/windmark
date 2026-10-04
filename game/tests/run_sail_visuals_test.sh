#!/bin/sh
# Headless tests of the sail visuals (docs/specs/sail_visuals.md §12, WM-016.09): the numbered tests on the
# GDScript reference and the native SailShape, native against reference, the vertex buffer against Godot's own
# encoding, the generated wm7 and wm12 sails in BoatView, the generator's preview poses against BoatView (parity),
# the update rate by distance and the cost per sail; then the running sheets, the levels of detail and the rope
# materials (tests/sheets_lod_test.gd).
# Builds the GDExtension when game/bin has no library and generates the boats when they are missing. Fails on any
# failed check, script error or engine error. Nothing opens a window.
#   game/tests/run_sail_visuals_test.sh [--rebuild] [--preview]
#     --rebuild   run native/build.sh even when the library exists
#     --preview   also render the offline previews (tests/sail_preview_dump.gd, then tests/sail_preview.py;
#                 needs numpy, Pillow, moderngl) into game/generated/sail_preview
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
godot=${GODOT:-godot}
export GODOT="$godot"
rebuild=0
preview=0
for a in "$@"; do
    case "$a" in
        --rebuild) rebuild=1 ;;
        --preview) preview=1 ;;
    esac
done

if [ ! -f "$here/generated/boats/wm7.glb" ] || [ ! -f "$here/generated/boats/wm12.glb" ] \
        || [ ! -f "$here/generated/boats/wm7.sets.json" ]; then
    "$here/tests/run_boat_import_test.sh"
fi
if [ $rebuild -eq 1 ] || ! ls "$here"/bin/libwindmark_godot.* >/dev/null 2>&1; then
    sh "$here/native/build.sh" >/dev/null
fi
sh "$here/native/register.sh"
mkdir -p "$here/generated"
log="$here/generated/sail_visuals_import.log"
"$godot" --headless --path "$here" --import >"$log" 2>&1 || { cat "$log"; echo "import failed"; exit 1; }

log="$here/generated/sail_visuals_test.log"
set +e
"$godot" --headless --path "$here" -s res://tests/sail_visuals_test.gd >"$log" 2>&1
rc=$?
set -e
grep -E "^- |FAIL|checks|native|reference" "$log" || true
if [ $rc -ne 0 ] || grep -qE "SCRIPT ERROR|^ERROR|^WARNING|Parse Error" "$log"; then
    grep -E "SCRIPT ERROR|^ERROR|^WARNING|Parse Error" -A2 "$log" | head -20 || true
    echo "sail visuals test failed (full log: $log)"
    exit 1
fi
echo "sail visuals test passed"

# the running sheets, the levels of detail and the rope materials (sail_visuals.md §11.3, §11.4, tests 21 and 22)
log="$here/generated/sheets_lod_test.log"
set +e
"$godot" --headless --path "$here" -s res://tests/sheets_lod_test.gd >"$log" 2>&1
rc=$?
set -e
grep -E "^- |FAIL|checks|native|reference" "$log" || true
if [ $rc -ne 0 ] || grep -qE "SCRIPT ERROR|^ERROR|^WARNING|Parse Error" "$log"; then
    grep -E "SCRIPT ERROR|^ERROR|^WARNING|Parse Error" -A2 "$log" | head -20 || true
    echo "sheets and LOD test failed (full log: $log)"
    exit 1
fi
echo "sheets and LOD test passed"

if [ $preview -eq 1 ]; then
    "$godot" --headless --path "$here" -s res://tests/sail_preview_dump.gd
    python3 "$here/tests/sail_preview.py"
fi
