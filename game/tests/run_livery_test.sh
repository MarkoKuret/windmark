#!/bin/sh
# Runs tests/livery_test.gd headless (data_format.md §8, sail_visuals.md §11.2): the livery files, the fleet rule,
# the baked textures and a painted fleet of both classes on the baked and the procedural path. Stages the baked
# textures for import first (tools/liverybake --stage-only, then a headless import) and checks the textures'
# ownership rule: a bake never rewrites existing (hand-owned) files without --force or --only. Needs the
# generated boats (runs run_boat_import_test.sh when they are missing). Fails on any script error or failed check.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
repo=$(cd "$here/.." && pwd)
godot=${GODOT:-godot}
if [ ! -f "$here/generated/boats/wm7.glb" ] || [ ! -f "$here/generated/boats/wm12.glb" ]; then
    sh "$here/tests/run_boat_import_test.sh"
fi

# the ownership rule on the committed textures: a plain bake keeps every existing file byte for byte
sums_before=$(find "$repo/data/liveries" -name "*.png" -o -name "layout.json" | sort | xargs shasum | shasum)
(cd "$repo/tools/liverybake" && python3 -m liverybake --no-stage --quiet)
sums_after=$(find "$repo/data/liveries" -name "*.png" -o -name "layout.json" | sort | xargs shasum | shasum)
if [ "$sums_before" != "$sums_after" ]; then
    echo "liverybake rewrote hand-owned textures without --force or --only"
    exit 1
fi
echo "hand-owned textures kept by a plain bake"

# the transom and deck sets: a hand edit survives a plain bake, --only deck rewrites the deck only, --force all
tmp=$(mktemp -d)
small="--no-stage --quiet --out $tmp --hull-size 256 --sail-size 128 --keel-size 64 --transom-size 128 --deck-size 256"
(cd "$repo/tools/liverybake" && python3 -m liverybake wm7 $small)
nav="$tmp/wm7/navy"
python3 -c "from PIL import Image; [Image.new('RGB', (8, 8), (200, 0, 0)).save('$nav/' + f) for f in ('transom_albedo.png', 'deck_albedo.png', 'deck_orm.png')]"
edited=$(shasum "$nav"/transom_*.png "$nav"/deck_*.png)
(cd "$repo/tools/liverybake" && python3 -m liverybake wm7 $small)
if [ "$(shasum "$nav"/transom_*.png "$nav"/deck_*.png)" != "$edited" ]; then
    echo "a plain bake rewrote hand-edited transom or deck textures"; rm -rf "$tmp"; exit 1
fi
t_before=$(shasum "$nav"/transom_albedo.png)
(cd "$repo/tools/liverybake" && python3 -m liverybake wm7 $small --only deck)
if [ "$(shasum "$nav"/transom_albedo.png)" != "$t_before" ] || [ "$(shasum "$nav"/deck_albedo.png)" = "$(echo "$edited" | grep deck_albedo)" ]; then
    echo "--only deck did not rewrite exactly the deck"; rm -rf "$tmp"; exit 1
fi
(cd "$repo/tools/liverybake" && python3 -m liverybake wm7 $small --force)
if [ "$(shasum "$nav"/transom_albedo.png)" = "$t_before" ]; then
    echo "--force did not rewrite the transom"; rm -rf "$tmp"; exit 1
fi
rm -rf "$tmp"
echo "transom and deck textures kept without --force or --only, rewritten with them"

(cd "$repo/tools/liverybake" && python3 -m liverybake --stage-only --quiet)
log="$here/generated/livery_import.log"
"$godot" --headless --path "$here" --import >"$log" 2>&1 || { cat "$log"; echo "import failed"; exit 1; }
if grep -E "ERROR|WARNING" "$log"; then
    echo "import reported errors or warnings (full log: $log)"
    exit 1
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
