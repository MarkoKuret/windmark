# liverybake: livery textures for the boat classes

Bakes the starting textures of a class's livery from its livery file (`data/liveries/<class>.liveries.json`,
`docs/specs/data_format.md` §8): the hull, the keel and the class sail set, as plain PNG images the owner then edits
by hand in any paint program (and the transom and deck of the livery). Once written they are **hand-owned assets, not generated tables**: the tool never
overwrites them unless asked (§8.6 and "Ownership" below). It also stages them for the game.

## Running

```
cd tools/liverybake
python3 -m liverybake                      # bake what is missing (every class), then stage for the game
python3 -m liverybake wm12 --only main     # rebake one sail of one class (overwrites those files)
python3 -m liverybake wm7 --only hull --only keel
python3 -m liverybake wm7 --only deck      # rebake the deck set (overwrites its hand edits)
python3 -m liverybake wm7 --force          # rebake everything of wm7 (overwrites hand edits)
python3 -m liverybake --stage-only         # only copy the current files to the game (after a hand edit)
```

Options: `--livery ID` (one livery of the file), `--only PART` (repeatable: `hull`, `keel`, `transom`, `deck`,
`sails`, `ropes` or a sail id such as `main`, `jib`, `kite`, `code0`, `a2`), `--force`, `--no-stage`, `--stage-only`,
`--out DIR` (bake somewhere else, for trying things), `--hull-size` (4096), `--transom-size` (2048), `--deck-size`
(4096), `--sail-size` (2048), `--keel-size` (1024), `--rope-size` (512), `--quiet`. A full bake takes about 4 minutes per class on an
M-series Mac (the deck about 30 s, the transom 4 s); the first run per class also builds
the boat with `tools/boatgen` (about 15 s, cached in `.cache/`).

Dependencies: Python 3.9+, NumPy, Pillow, SciPy, and `tools/boatgen` (imported, for the hull, keel, deck and sail
geometry). No GPU, no window.

Tests (about 10 s with small images):

```
cd tools/liverybake
uv run --no-project --with pytest --with numpy --with pillow --with scipy --with moderngl python -m pytest -q tests
```

## Which file is which

```
data/liveries/<class>.liveries.json     the source: class livery, class sail set, insignia, boats
data/liveries/<class>/<livery id>/      the livery worn by every boat (today the only one, "navy")
    hull_albedo.png   4096 x 2048  colour, sRGB
    hull_normal.png   4096 x 2048  relief, linear
    hull_orm.png      4096 x 2048  R occlusion, G roughness, B metallic; linear
    keel_albedo.png   1024 longest colour of keel fin and bulb, sRGB
    transom_albedo.png  2048 x ~550   the transom seen from astern, sRGB
    transom_normal.png  2048 x ~550   relief, linear
    transom_orm.png     2048 x ~550   R occlusion, G roughness, B unused (0); linear
    deck_albedo.png     4096 x ~1400  the deck seen from above, sRGB
    deck_normal.png     4096 x ~1400  relief, linear
    deck_orm.png        4096 x ~1400  R occlusion, G roughness, B the non-slip mask; linear
    layout.json                    where the keel sits on the model; the transom's and deck's frames for reference
data/liveries/<class>/sails/            the class sail set, shared by the fleet
    <sail>_port_albedo.png  2048 longest  the sail seen from port, sRGB
    <sail>_stbd_albedo.png  2048 longest  the sail seen from starboard, sRGB
    <sail>_normal.png       2048 longest  relief (both sides), linear
    <sail>_orm.png          2048 longest  R occlusion, G roughness, B light through the cloth; linear
    layout.json                         the sails' plan rectangles, cloth, and the number slots
data/liveries/<class>/rig/              the class rope set (data_format.md §8.7), shared by the fleet
    rope_<function>_albedo.png  512 x 512  one braid tile in the function's colours, sRGB: mainsheet, sheet,
                                           kite_sheet, halyard, control
    rope_normal.png             512 x 512  the braid's relief, linear, shared by every function
    rope_orm.png                512 x 512  R occlusion, G roughness, B metallic (0); linear
```

A rope tile runs along the rope left to right (0.05 m, one lay length) and once round it top to bottom; it must
tile seamlessly both ways. Each carrier of the 16-carrier braid is a diagonal ribbon of three yarns; recolouring a
carrier (a fleck, a tracer) is a matter of painting along its diagonal.

How the images lie:

- **Hull**: the top half is the starboard side as you see it from outside (bow to the right, sheer at the top),
  the bottom half the port side (bow to the left, sheer at the top of that half). Left and right edges are the
  stern and the stem, the lower edge of each half is the keel line. Texels outside the hull (above the sheer near
  the ends) carry the nearest colour so mipmaps do not bleed; painting there has no effect. Leave the two
  **name and number panels** clear (aft and forward on the topsides, `livery_panels` in the boat GLB): the game
  sets each boat's name and number there. The waterline (DWL) is 4 cm below the antifouling's top edge.
- **Keel**: the keel seen from starboard, bow to the right, fin on top, bulb below. Port shows the same image.
- **Transom**: seen from astern, port on the left, the transom's top edge (deck edge on the quarters, cockpit floor's
  edge in the opening of an open transom) at the top, its foot at the bottom; the outline is the generator's (texels
  outside it carry the nearest colour). Leave the **name panel** clear: the band under the cockpit opening (wm7: to
  starboard of the rudder's gudgeons, the right of the image; `livery_transom.panel` in the boat GLB): the game sets
  each boat's name there. Paint the stripes' ends, scuffs and streaks where you like.
- **Deck**: the deck in plan, bow to the right, port at the top (the same frame as `deck.rect` in `layout.json`:
  the hull's length and beam with a 1 % margin). Every deck surface takes its colour from the texel straight below
  it, so the cabin top, cockpit sole and side decks are drawn where they lie in plan; the near-vertical coaming and
  cabin sides take the texels of their footprint (keep a few pixels of plain gelcoat along those edges). **The ORM
  blue channel is the non-slip mask**: 255 where the moulded non-slip pattern is, 0 on smooth gelcoat, in between a
  worn pattern; paint it together with the albedo (non-slip grey `deck.nonslip`, gelcoat `deck.gelcoat`) so the
  game's tiling relief matches. Hardware is not in the image, only its traces: pads, sealant beads, scuffs.
- **Sails**: each sail flat, the luff straight up the left edge (the sailmaker's view from port), head at the top.
  The starboard image is the same sail seen from the other side (luff on the right). Cloth, seams and patches must
  match between the two; the insignia and tell-tales are each side's own. Leave the **number slots** clear (below
  the insignia on the main, near the head on genoas, code zeros and spinnakers: `text.rows` in `layout.json`): the
  game sets each boat's nation letters and sail number there. The normal and ORM maps are in the port view.

## Editing by hand (Krita, GIMP, Photoshop)

1. Open the PNG. Work in **8-bit RGB, no alpha**, and keep the size (a new size works but changes the sharpness;
   keep the aspect ratio).
2. Colour maps (`*_albedo.png`) are **sRGB**: paint normally. Keep every channel at or below **231** (a linear
   albedo of 0.8, the look rule of `data_format.md` §3.7): pure white paint is `#e7e7e3` at most; the game clips
   brighter values. Do not paint lighting or shadows into them; the engine lights the boat.
3. Data maps (`*_normal.png`, `*_orm.png`) are **linear**: in Krita set the layer or image to a linear profile or
   "no colour management", in GIMP use "Image > Precision > Linear light" or keep the values as numbers, in Photoshop
   disable colour management for the file (Edit > Assign Profile > Don't Color Manage). Normal maps use the OpenGL
   convention (green up): flat is `#8080ff`; to remove relief fill with that. In an ORM map paint roughness in the
   green channel only (0 mirror, 255 matt: gelcoat about 40, vinyl 64, antifouling 205, deck gelcoat 75, non-slip
   205) and, on a sail, the light through the cloth in blue (dacron about 77, laminate 51, nylon 128; 0 for opaque
   patches); on the deck the blue channel is the non-slip mask (above).
4. Keep layers in your own working file (`.kra`, `.xcf`, `.psd`) outside `data/liveries`, or next to it with a name
   the game ignores, and export the flattened PNG over the file.
5. Commit the PNG. Nothing regenerates it.

To change the colour scheme from scratch instead (new hull colours or graphic, new sail cloth), edit the livery
file and rebake that part with `--only` (this replaces the part's hand edits) or `--force`.

## Ownership

A part (the hull's three images, the keel, the transom's three, the deck's three, one sail's four) is written only
when none of its files exists: a new folder is baked whole, a part added later (as the transom and deck were) is
baked once into the existing folder, and a part with any of its files present is the owner's (delete all of its
files to have it baked again). `--only PART` rewrites just those files, `--force` every file of the selected classes
and liveries. `game/tests/run_livery_test.sh` checks that a
plain bake leaves the committed files byte for byte. The boat generator never touches these files, and a changed
class file does not rebake them: the hull, transom and deck follow their uv1 and each sail keeps its rectangle in
metres, so after a hull, deck or sail plan change decide whether to repaint or rebake (`--only`).

## The game

`python3 -m liverybake` (or `--stage-only`) copies the images and layouts into `game/generated/liveries/` (git-ignored)
with Godot import settings, and writes the shared tiling cloth detail (`_cloth/<cloth>_detail.png`, procedural, not
hand-owned). Godot imports them compressed with mipmaps the next time it imports (the editor on focus, or
`godot --headless --path game --import`); a changed PNG is reimported, an unchanged one is not.
`game/tests/run_boat_import_test.sh` and `run_livery_test.sh` stage and import before testing. See
`game/README.md` "Liveries".

## What the bake draws

Everything is seeded from the class and livery ids, so a bake is repeatable.

- **Ropes** (`liverybake/ropes.py`): per rope function of the file's `ropes` block (defaults in `data_format.md`
  §8.7) a 16-carrier braid, 8 carriers each way, 2 over 2 under, each a flat ribbon of three yarns with fibre streaks;
  `fleck` puts one carrier of each direction in the fleck colour, `tracer` one, `twill` alternate pairs, `solid`
  none. The shared normal and ORM maps carry the carriers' crowns, the dips where they pass under and the grooves
  between yarns.

- **Hull** (`liverybake/hull.py`): the hull point of every texel from the generator's skin (station
  interpolation), so features sit at real heights and lengths. Polished gelcoat or paint with slight batch and sun
  fade variation and long fairing waves (seen only in reflections), polish swirls in the gloss; the graphic as cut
  vinyl with crisp edges, a hairline of dirt along them and a 0.1 mm step in the relief; the boot stripe as vinyl
  tape at constant height; antifouling rolled in 17 cm laps with lap ridges, brushed along the tape line, chalky
  and faded toward the waterline; an olive scum line at the DWL, heavier at the bow and quarters, and a bow-wave
  stain on the boot stripe; spray marks on dark topsides forward; fender smudges amidships near the sheer; fine
  scratches near the sheer, the bow and the transom quarters; faint drip streaks from the stanchion bases.
- **Transom** (`hull.bake_transom`): the topsides' paint, fade and fairing; the stripes return round the quarters at
  their depth below the top edge and end with a slanted cut half way to the cockpit opening (with `from` 0 in the
  livery file); the boot stripe where its height reaches the transom's foot, with the stern wave's stain; boarding
  scuffs and shoe-rubber marks on the lip of the opening and the quarters, fine scratches, faint dried streaks where
  the cockpit drains over the lip, sealant round the gudgeon plates, polish swirls.
- **Deck** (`liverybake/deck.py`), laid out from the generator's deck (outlines, the companionway) and every
  fitting's footprint: moulded non-slip panels on the side decks, foredeck, cabin top and cockpit sole inside smooth
  margins (the class's `nonslip_margin` on the deck, 4 cm on the sole, 5 cm on the cabin top), a smooth strip down
  the foredeck's centreline, smooth pads under every fitting and where the sliding hatch runs; sealant beads round
  every base and a little contact shadow; foot traffic (the sole's pattern worn and dirty down the middle and toward
  the companionway, the walkway to the shrouds, round the mast and beside the hatch); dirt in the sole's corners, at
  the cabin's base and inboard of the toe rail; rope and rubber scuffs round the winches on the sheet's side, along
  the halyard tails aft of the organisers and clutches, round cleats and either side of the traveller; shoe scuffs;
  sun-faded patches; tea-stain specks at the stainless bases.
- **Keel**: antifouling with roller laps and sanded-through fairing patches, chips on the fin's leading edge and the
  bulb's nose down to the grey primer, grounding scratches under the bulb.
- **Sails** (`liverybake/sails.py`, sail_visuals.md §11.1 and §11.2): cross-cut woven polyester, or tri-radial
  laminate with load-path yarns (heavier bundles every fourth), an X-ply scrim and denser load bands from the corners,
  or tri-radial nylon; two-ply seams with two rows of zigzag stitching and the overlap's edge; edge tapes; layered
  corner patches with radial fingers, webbing straps and stainless rings; the main's headboard with rivets and
  four batten pockets with battens and end patches; draft stripes; tell-tales on headsails (red to port, green to
  starboard); the class insignia as stuck-on cloth; panel-to-panel shade and sheen; flaking creases (crumpled on
  spinnakers), stress wrinkles at the clew, head and tack; grime along the foot. The light through the cloth (ORM
  blue) falls with every ply, yarn, ring, webbing and the insignia. The fine weave, film and ripstop are the
  game's tiling detail (`liverybake/cloth.py`).

References used for proportions: racing rules of sailing Appendix G (number height by length, 0.2 h spacing,
starboard numbers uppermost), typical sailmaker layouts (cross-cut panels about 0.9 m, tri-radial fans, 16 to 20 mm
seams, 25 to 45 mm tapes, corner patches about 6 % of the luff, batten pockets 50 to 60 mm). No third-party images
are used; the font is Barlow Semi Condensed Bold (OFL, `docs/THIRD_PARTY.md`).
