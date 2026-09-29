# boatgen: parametric boat generator

Builds a complete racing-yacht model from a boat-class file (`data/classes/<id>.boat.json`, schema
`windmark.boatclass/1`, see `docs/specs/data_format.md` §3): a faired hull, deck with cockpit and cabin top,
keel fin and bulb, rudder, mast, boom, spreaders and standing rigging, flat two-layer sails in their standard
hoisted shape, and rule-placed deck hardware. It also writes the physics sidecar (hydrostatics, waterline,
buoyancy samples, collision shapes, rig and sail data) and renders preview images headless.

Status: proof of concept. See "Limits and next steps" at the end.

## Running

```
cd tools/boatgen
python3 -m boatgen ../../data/classes/wm12.boat.json ../../data/classes/wm7.boat.json
```

Options: `--out DIR` (default `tools/boatgen/out/`, not committed), `--previews DIR` (default
`tools/boatgen/previews/`), `--no-previews`, `--no-textures` (PBR factors only), `--no-bake` (no baked AO),
`--size 1600x1000`, `--quiet`. About 15 s per boat on an M-series Mac.

Dependencies: Python 3.9+, `numpy`, `Pillow`, `moderngl` (`pip3 install --user moderngl`) for the AO bake and the
previews, which opens a headless OpenGL 4.1 context (no window); `--no-bake --no-previews` runs without it.
Nothing else: the GLB writer, triangulation, lofting and hydrostatics are in this package.

## Outputs (per class, in `--out`)

| file | content |
| --- | --- |
| `<id>.glb` | the model (LOD0), flat standard sails |
| `<id>_lod1.glb`, `<id>_lod2.glb` | lower levels of detail, same nodes, pivots and sails (below) |
| `<id>_collision.glb` | low-poly collision meshes (node names carry Godot's `-convcolonly` import suffix) |
| `<id>.physics.json` | physics sidecar (below) |
| `<id>_upwind.glb`, `<id>_downwind.glb` | preview poses only: sails set as the game draws them (below), boom and pole swung, sheets led (node `sheets`) |
| `<id>.sets.json` | the preview poses as drawn (wind, sheet and pole angles, placed sail grids, body frame), for the game's parity test |

Previews in `previews/`: `<id>_upwind.png` (heeled, trimmed, demo livery), `<id>_downwind.png` (spinnaker set),
`<id>_profile.png` (the exported model as is, dry, from starboard), `<id>_deck.png` (cockpit and deck
hardware), close-ups `<id>_cockpit.png` (from aft, looking forward), `<id>_mastbase.png` (mast foot, halyard leads,
chainplates) and `<id>_bow.png` (dry and low: stem, forefoot, bilge turn), `<id>_detail.png` (close on the cabin side and side deck: texture set and baked AO), `<id>_uv.png` (0.25 m checker on uv0 of every surface) and `<id>_lines.png` (lines plan: profile with
buttocks, half-breadths with waterlines, body plan).

## Tests

```
cd tools/boatgen
python3 -m unittest discover -s tests
```

About 30 s. `tests/fixtures/` holds generator test classes for features no shipped class uses yet (a
symmetric spinnaker on a pole); the headless Godot import test (`game/tests/run_boat_import_test.sh`) builds and
checks them too.

## Frames and units

SI units, angles in radians. The class file and the physics sidecar use the boat body frame of
`docs/specs/conventions.md` §3: x forward, y port, z up, origin on the centreline in the DWL plane at mid LWL.
The GLB uses the same origin with glTF axes: `(X, Y, Z) = (y, z, x)`, so +Y is up, +Z is forward and +X is port.
That is a rotation, not a mirror, so triangle winding is preserved. Internally the modules work with x measured
forward from the transom; `classfile.py` converts.

The DWL floats the boat in sailing trim with the crew aboard: the generated hull displaces
`hull.displacement + crew.weight`.

## Class-file fields

All base fields are those of `docs/specs/data_format.md` §3 and are used as specified there:
`hull.{loa, lwl, beam_max, bwl, draft_canoe, displacement, prismatic, section_shape, rocker, freeboard,
transom_width, stem_x, transom_x, max_beam_station, lcb_x, bow_fineness}`, `keel.{type, depth, chord_root,
chord_tip, thickness, sweep, x, fin_mass, bulb_mass, bulb_length, bulb_diameter}`, `rudder.{type, depth,
chord_root, chord_tip, thickness, x}`, `rig.{I, J, P, E, mast_height, mast_x, boom_height, fractional,
bowsprit, pole}`, `sails[].{id, type, area, luff, tack_x}`, `crew.{count, weight}`; on code zeros and
spinnakers also `sails[].{leech, foot, mid_girth, mid_girth_frac, luff_round, leech_round, foot_round,
luff_round_pos, leech_round_pos, foot_round_pos}` (below).

How the generator reads a few of them:

- `section_shape.type` sets the bottom section family (`v`, `round`, `u`, `flat`, `chined`); `deadrise` bends
  `v` and `chined` bottoms; `chine_height` is the height of the hard chine. `midship_coefficient` is **not**
  imposed: with Cp, LWL, BWL, Tc and the displaced volume all fixed, Cm is already determined
  (V = Cp · Cm · LWL · BWL · Tc). The generator hits the volume and Cp exactly and reports the resulting Cm next
  to the requested one (`hydrostatics.midship` and `midship_requested`).
- `rocker.fwd` below `draft_canoe` gives a forefoot below the DWL (plumb-bow style); `rocker.aft` below
  `draft_canoe` gives an immersed transom and then needs `transom_x = -lwl/2`.
- `lcb_x` is the LCB target (default 53.5 % LWL aft of the forward end when absent).
- `max_beam_station` and `bow_fineness` shape the sheer plan view with the rule of `collisions.md` §2.1, so the
  2-D collision outline and the 3-D deck edge agree.
- `sails[].area` of the main and headsails is matched exactly by the flat outline (mainsail roach, headsail clew
  position). `luff` and `tack_x` override the rig-derived values when given.
- Code zeros and spinnakers are **not** stretched to the class area: they are drawn from the rig with the standard
  proportions of `docs/specs/data_format.md` §3.5, and the class area should be the rule area that planform gives
  (the build logs the measurements and warns when the class area is more than 3 % off). The rule:

  | type | tack | leech | foot | mid girth | edge round (luff share) |
  | --- | --- | --- | --- | --- | --- |
  | `spinnaker_asym` | sprit end | 0.88 luff | 0.56 luff | 0.76 foot | 45 % |
  | `spinnaker_sym` | pole end | = luff | 1.75 pole, at most 0.6 luff | 0.95 foot | 50 % |
  | `code_zero` | sprit end | 0.90 luff | 0.46 luff | 0.56 foot | 20 % |

  The luff is the straight line from the tack to the halyard point (0.12 m below the masthead at the mast front);
  the clew is where the foot from the tack meets the leech from the head. The luff and leech are then bowed
  outward (split by the luff share) until the mid girth, between the mid points of the luff and leech edges,
  reaches its value; the foot has a fixed round (asym 8 %, sym 10 %, code zero 2 % of the foot). Rule area
  `(SLU + SLE) / 2 · (SF + 4 · SHW) / 6` with the edges measured along the curves, as the sidecar's
  `sails.<id>.rule` reports. `luff`, `leech` and `foot` in the class file override the proportions, and the
  shaping keys below override the mid girth and the edge rounds. The clew comes out about a third of the hull
  length forward of the transom, so the set kite's clew flies abreast the cockpit.

### Shaping a kite by hand

The class file stays the only source: set the keys on the sail's entry in `sails[]`, preview, then regenerate.
All keys are optional; with none the sail keeps the standard proportions above (`data_format.md` §3.5).

| key | unit | range | what it does |
| --- | --- | --- | --- |
| `luff`, `leech`, `foot` | m | | straight corner-to-corner lengths; the clew moves to meet `foot` from the tack and `leech` from the head. A shorter `foot` is the main lever for a smaller foot, and it moves the clew forward |
| `mid_girth` | m | > 0 | mid girth target (between the mid points of luff and leech) |
| `mid_girth_frac` | of the foot | 0.3 to 1.2 | the same as a fraction of the foot along its round (default asym 0.76, sym 0.95, code zero 0.56); use one of the two |
| `luff_round`, `leech_round`, `foot_round` | of the edge | -0.1 to 0.3 | greatest depth of the edge's curve over its straight line: luff bows forward, leech aft, foot down; negative is a hollow |
| `luff_round_pos`, `leech_round_pos`, `foot_round_pos` | along the edge | 0.1 to 0.9 | where that depth sits: luff and leech from the bottom corner (0.45 by default, so fullest just below half height), foot from the tack (0.5) |

How the luff and leech rounds and the mid girth interact: with neither round given, both are solved together to
reach the mid girth (the default); with one given, the other is solved; with both given, the mid girth is the
outcome (then `mid_girth` and `mid_girth_frac` are not allowed). The foot round is 0.08 (asym), 0.10 (sym) or
0.02 (code zero) unless set. Out-of-range values and a mid girth the solved edge cannot reach stop the build with
a message that names the key.

Example (smaller foot, slimmer shoulders, leech fullest higher up):

```
{"id": "kite", "type": "spinnaker_asym", "area": 43.0, "foot": 5.4, "mid_girth_frac": 0.72, "leech_round_pos": 0.6}
```

Preview after each edit:

```
cd tools/boatgen
python3 -m boatgen.kite_preview ../../data/classes/wm7.boat.json [--sail kite] [--out DIR] [--no-render]
```

It prints each flying sail's luff, leech, foot, mid girth, edge rounds (depth, position, solved or set), rule
area (and the class `area` it implies: the rule area rounded down to 0.5 m²) and the clew position forward of the
transom and above the DWL, and writes `out/kite/<id>_<sail>.png`: the flat planform with its dimensions and the
previous outline dashed, the sail set on a run (from the leeward quarter) and on a reach (abeam, from leeward),
with the previous run's row underneath. The sets are the game's set shape (below, "Set sails in the previews"),
with the main and the flying sail at the core's optimum sheet angles. The hull, deck and rig are built once and cached in `out/kite/.cache/`
(about 15 s); after that, while only code zero and spinnaker entries change, a run takes about 1 s. Headless, no
window.

When the shape is right:

1. set the sail's `area` to the rule area the preview reports, rounded down to 0.5 m²;
2. regenerate the boat: `python3 -m boatgen ../../data/classes/<id>.boat.json` (GLB, sidecar, previews), and
   run the tests (`python3 -m unittest discover -s tests`, `sh game/tests/run_boat_import_test.sh`);
3. the performance tables in `data/perf` must then be regenerated with the VPP (`tools/vpp/README.md`) from the
   new class file and sidecar, since the spinnaker area and shape feed them. The coordinator does this step.

### `visual` block (generator only, opaque to the core and the VPP)

Every key is optional; defaults scale with LOA.

| key | default | meaning |
| --- | --- | --- |
| `hull.max_bwl_pos` | 0.55 | widest waterline, fraction of LWL aft of the forward end |
| `hull.max_draft_pos` | 0.55 | deepest canoe body, fraction of LWL aft of the forward end |
| `hull.keel_line_exponent` | 2.6 | keel-line fullness (2 = parabolic, larger = flatter bottom) |
| `hull.bilge_height` | 0.18 · mid freeboard | height of the bilge turn above the DWL |
| `hull.topside_flare` | 1.7 | topside curve exponent (1 = straight flare) |
| `hull.transom_bottom_width` | 0.9 · transom_width | width of the hull bottom at the transom |
| `hull.deck_camber` | 0.022 | deck crown as a fraction of the local beam |
| `hull.sheer_spring` | 0 | extra sag of the sheer at mid length (m) |
| `hull.boot_top` | [0.04, 0.10] | antifouling up to [0], boot-top stripe up to [1] (m above the DWL) |
| `hull.stem_radius` | 0.10 (LOA/12)^0.5 | forefoot rounding (m, blend height between keel line and stem) |
| `hull.bilge_fillet` | 0.12 | bilge-turn fairing radius as a fraction of the station depth (keel to sheer); 0 leaves the raw curves |
| `hull.lcb_fraction` | 0.535 | LCB target when `hull.lcb_x` is absent |
| `hull.chine_start` | 0.42 | where a hard chine begins, fraction of LOA aft of the stem |
| `deck.cockpit` | length 0.30 LOA, width 0.62, depth 0.42 (LOA/12)^0.5, open_transom true, aft_deck 0 | cockpit well: width as a fraction of the local half-beam |
| `deck.cabin` | length 0.28 LOA, height 0.26 (LOA/12)^0.6, width 0.58, side_slope 0.22, windows true | coachroof; `null` for a flush deck |
| `deck.nonslip_margin` | 0.05 | smooth gelcoat border around non-slip panels (m) |
| `deck.toe_rail` | 0.035 (LOA/12)^0.4 | toe-rail size (m) |
| `deck.lifelines` | LOA >= 9 m | stanchions, lifelines, pulpit and pushpit |
| `deck.steering` | wheel from 11 m, else tiller | `wheel` or `tiller` |
| `deck.hatches` | 2 from 9 m, else 1 | foredeck hatch, plus one on the cabin top |
| `keel.bulb_flat` | 1.25 | bulb cross-section width / height |
| `rudder.sweep` | 0.10 | rudder quarter-chord sweep (rad) |
| `rig.mast_chord` | 0.0105 · mast_height + 0.02 | mast section fore-and-aft size (m) |
| `rig.mast_width` | 0.62 | mast section width / chord |
| `rig.spreaders` | 2 above 13 m mast height, else 1 | spreader pairs |
| `rig.spreader_sweep` | 0.35 | spreader sweep (rad) |
| `rig.backstay` | fractional > 0.93 | permanent backstay to the transom |
| `sails.<id>.head_width` | 0.28 | mainsail head width as a fraction of E |
| `sails.<id>.clew_height` | 0.35 (LOA/12)^0.5 | headsail clew height above the deck (m) |
| `sails.<id>.luff_frac` | 0.96 | headsail luff as a fraction of the forestay |
| `sails.<id>.look` | per sail type, `docs/specs/sail_visuals.md` §4 | the run-time look of the sail (below) |

`sails.<id>.look` holds any of the look parameters of `sail_visuals.md` §4: `fill_gain`, `fill_curve`,
`flutter_amp`, `flutter_rate`, `flutter_rate_max`, `twist_top`, `camber`, `tack_line_max`, `furl_radius` (numbers
>= 0; an unknown key is an error). The generator copies them into the sidecar's `sails.<id>.look` and fills
every missing key from the defaults of the sail's type: the table of §4 (`camber` 0.12 on a code zero, 0.26 on
both spinnakers), `flutter_rate` and `flutter_rate_max` from the LOA size rules, and `furl_radius` (jib, genoa,
code zero) from the flat sail's chord extent `Sa`. Keys that do not apply to a type (`camber` on a main) are
written only when the class file gives them. The old `depth` key (replaced by `camber`) is still accepted and
not written.

## How the geometry is made

**Hull** (`hull.py`). Each station is a superellipse bottom from the keel point to the bilge turn, then a topside
curve up to the sheer, meeting with a vertical tangent; both curves have an unbounded curvature at that
point, so the turn is faired: the station is replaced there by its Gaussian average along the girth (radius
`bilge_fillet`), blended back to the raw curve within four radii, and the mesh points are spread by arc length and
turning angle so the turn keeps its shape (a `chined` hull keeps its crease aft of the chine start). Five longitudinal curves drive the stations: the profile (keel line, forefoot and raked
stem), the bilge-turn height and half-breadth, the sheer height (through the three freeboards) and the sheer
half-breadth (the class plan-view rule). A solver then fits the bilge breadth to BWL, the section fullness to the
canoe-body volume (DWL mass over water density, minus the meshed appendages), and the entrance and run fullness
to Cp and LCB with a 2 x 2 Newton step. LWL and Tc are exact by construction.

**Deck** (`deck.py`). A cambered surface between the sheer lines, meshed as two strips from the sheer in to the
cockpit and cabin outline, with gelcoat margins around non-slip panels. The cockpit is a well running aft to an
open transom; the cabin top rounds in to the centreline at its front, with leaning sides, a filleted roof edge,
side windows, companionway and sliding hatch. The transom face, toe rail and rub strake close it off.

**Appendages** (`appendages.py`). NACA 00xx fin and rudder lofted from root to tip; the bulb is a flattened body
of revolution sized so its volume holds the bulb mass in lead.

**Rig and sails** (`rig.py`, `sails.py`). Tapered mast section, swept spreaders, shrouds with terminals, forestay,
backstay, bobstay, sprit, boom with vang. Sails are Coons patches over their edges on a regular grid (rows from
foot to head, columns from luff to leech), so the simulation can deform them.

**Set sails in the previews** (`sail_set.py`). The preview poses (`Boat.POSES`: upwind, reaching with a code
zero, downwind with a spinnaker) and `kite_preview`'s run and reach bend and place the flat sails exactly as the
game does (`docs/specs/sail_visuals.md` §5.1, §6.1 to §6.4 and §7, including the flying sails' clearance off the
main and the mast): a port of the game's `SailShapeRef`, for the `up` phase with no luff shiver. Each pose names
the apparent wind and the sheet angles (the core's optimum from the wm7 and wm12 tables at 10 kn TWS). The build
writes the poses as drawn to `<id>.sets.json`, and `game/tests/run_sail_visuals_test.sh` (§12, test 19) checks
that BoatView, native and reference, places every vertex within 0.01 m of them.

**Hardware** (`hardware.py`). A library of parametric parts placed by rules that read the deck, cockpit and rig:
self-tailing winches (ribbed drum, tailer, stripper arm, a handle in the starboard primary), rope clutches on a
base plate, deck organisers, turning blocks on padeyes, blocks with cheeks, sheave and swivel, T-tracks with end
stops, cars with a lead block and plunger, cam cleats with fairleads, horn cleats, hatches with frame, lens,
hinges and handles, stanchions, bent-tube pulpit and pushpit, the wheel with its grip and a pedestal guard with
an instrument pod, gudgeons or the rudder bearing cap, rigging screws. Placement: primaries beside the cockpit,
halyard winches (wm12), clutches and organisers on the cabin top, the halyards themselves from their exits low
on the mast through the turning blocks at the mast foot, the organisers and the clutches to flaked tails, jib
tracks under the clew, the traveller under the boom end with its control lines and a four-part mainsheet with its
tail, cleats at bow and quarters, lifelines at about 2 m spacing.

**Rig fittings** (`rig.py`). Mast step plate, gooseneck bracket and pin, vang tang and boom bail, halyard sheave
boxes, masthead crane with sheaves, wind wand, instruments on the mast front, spreader root brackets and tip
boots, chainplate cover plates, rigging screws at the foot of every shroud and stay, outhaul and cheek blocks on
the boom.

**Running rigging** (`running.py`). The posed previews lead the working sheet of each set headsail or flying sail
from the clew through its lead (the jib car block, or a block on the quarter for a kite) to a winch, wrapped on
the drum, with the tail flaked in the cockpit, plus a slack lazy sheet, and for a kite the tack line and the
halyard. The exported model has no headsail or kite sheets (they follow the trimmed sail, so the engine draws them
from `rig.sheet_leads` in the sidecar); the halyard tails and the mainsheet are in the model.

**Livery panels.** A number panel forward and a name panel aft on each topside, given in the GLB root extras
(`livery_panels`: body x range, depth below the sheer, uv1 rectangle on the hull atlas); the previews draw them
in the demo livery. The livery system itself is WM-014.

## Levels of detail

`<id>.glb` is LOD0; `<id>_lod1.glb` and `<id>_lod2.glb` have the same node set, pivots and sails (the sail grids
are the simulation's) with a coarser hull, deck and appendages, fewer segments on every round part, and the small
pieces left out (bounding box under 35 mm at LOD1, 0.3 m at LOD2, plus the handles, coils, halyard tails and
most fittings by rule). The sidecar's `model.lods` lists each file, its triangles and its switch distance.

| level | from | wm7 | wm12 | what goes |
| --- | --- | --- | --- | --- |
| LOD0 | 0 m | ~72 k | ~92 k | full model |
| LOD1 | 30 m | ~26 k | ~34 k | half the segments; handles, halyards, coils, small fittings, rub strake detail |
| LOD2 | 100 m | ~9.5 k | ~11.6 k | quarter segments, 24 hull stations; only hull, deck, appendages, spars, wires, tracks, hatches, pulpit, helm and sails |

Budgets: LOD0 at most 100 k triangles, LOD1 40 k, LOD2 12 k (sails included: about 3.7 k for the set sails of
wm12). `game/tests/boat_import_test.gd` checks the levels and prints the fleet cost of 16 boats per class
(2 at LOD0, 4 at LOD1, 10 at LOD2).

## Model structure

Nodes under the root (named after the class id):

| node | pivot | note |
| --- | --- | --- |
| `hull`, `deck`, `keel`, `mast`, `rigging`, `hardware` | | static |
| `rudder` | rudder stock, turns about the vertical | carries the tiller when steering is `tiller` |
| `wheel` | wheel hub, turns about fore and aft | only with `wheel` steering |
| `boom` | gooseneck, turns about the vertical | carries the upper mainsheet block |
| `mainsheet` | | tackle between boom and traveller; rebuild it as the boom moves |
| `pole` | on the mast axis at the heel height, turns about the vertical | spinnaker pole, only for a class that flies a spinnaker on a pole (below) |
| `sail_<id>` | | one per class sail, flat, two layers |

Pivot nodes store their geometry relative to the pivot and carry the pivot as their translation.

A class flies its spinnaker on a pole when it has a `spinnaker_sym`, or a `spinnaker_asym` with `rig.pole > 0`
and no bowsprit. The pole (length `rig.pole`, default 0.95 J) points forward from the mast front on the
centreline at rest, and its end is the spinnaker's tack. Its pivot is on the mast axis, the axis the spinnaker
swings about (`sail_visuals.md` §7.3), so turning the pole node by the pole angle keeps its end on the swung
tack. The front end shows it only while the spinnaker is not `down`; the preview poses without a spinnaker leave
it out.

## Materials and UVs

Material slots (glTF material names): `gelcoat`, `nonslip`, `antifouling`, `boottop`, `carbon`, `metal`,
`sailcloth`, plus `glass`, `rope` and `rubber`. Each material's `extras.tiling_m` is the size of one tile of its
texture in metres of uv0, and `extras.texture_set` names its set.

**Texture set** (`boatgen/textures.py`, images in `textures/`). Every slot but `glass` has a tiling
`baseColorTexture` (grey detail), `metallicRoughnessTexture` (roughness in G, metallic in B) and, except
`sailcloth`, a `normalTexture` (OpenGL convention), all on uv0 with a `KHR_texture_transform` scale of
`1 / tiling_m`. The textures vary around a fixed mean, and the factors are the slot's mean colour and roughness
divided by that mean, so a slot looks the same on average with or without its textures. Sets are shared between
slots and each image is embedded once per GLB (JPEG, 512 x 512, about 1.2 MB in all):

| set | slots | tile (m) | source (CC0, docs/THIRD_PARTY.md) |
| --- | --- | --- | --- |
| `orange_peel` | gelcoat, boottop | 0.5 | ambientCG Plastic013A |
| `pebble` | nonslip | 0.25 | ambientCG Leather026 |
| `grain` | antifouling, rubber | 0.5, 0.1 | ambientCG Rubber004 |
| `carbon_twill` | carbon | 0.05 | ambientCG Fabric004 |
| `brushed` | metal | 0.2 | ambientCG Metal009 |
| `weave` | sailcloth | 0.5 | ambientCG Fabric062 (no normal map: the run-time sail mesh has no tangents) |
| `braid` | rope | 0.05 | ambientCG Rope002 |

`python3 -m boatgen.textures [--cache DIR]` downloads the 1K sources again and rewrites `textures/`; the build
only reads the processed files.

**Baked ambient occlusion** (`boatgen/bake.py`). Every node except the sails and the mainsheet (deformed or
rebuilt at run time) carries per-vertex AO as `COLOR_0` (unsigned byte, normalised, grey, alpha 1): the
cosine-weighted share of 160 directions over the vertex's hemisphere in which the fixed model (sails excluded)
does not hide it, from GPU depth maps. glTF multiplies the base colour by `COLOR_0`; Godot imports it with
`vertex_color_use_as_albedo` on those slots. The pivoting nodes (rudder, boom, wheel, pole) are baked in their
rest position. Straight swept parts (tubes, wires, tracks) are split into segments of at most 0.5 m so the AO
has vertices to vary on.

- **uv0** is metric everywhere, for tiling PBR textures: hull `u` = x along the length, `v` = girth from the keel
  (both in metres); deck, cabin top and cockpit floor planar (x, y); walls (along, height); sails (distance from
  the luff, height above the foot); swept parts (along the path, around the section).
- **uv1** is normalised, for liveries and decals. Hull: one atlas with the starboard side in `v` 0..0.5 and the
  port side in 0.5..1, sheer at the top of each band, `u` running so text reads bow-first on both sides. Sails:
  (chord fraction, 1 - height fraction), with the starboard layer mirrored in `u` so a decal reads correctly from
  both sides.

### Sail grid

The sails are two layers 2 mm apart, each with its own outward normal (port layer `+y`, starboard `-y` on the
flat sail). Each layer is the full `rows × cols` grid with two triangles per cell, `4 (rows - 1)(cols - 1)`
triangles in all: on a pointed head the whole head row is one point and its zero-area triangles are kept, so every
vertex is referenced and carries the layer normal.

- **In the GLB file** the vertex order is row-major: vertex (row i from the foot, column j from the luff) of layer
  `k` (0 = port) is index `k · rows · cols + i · cols + j`.
- **In an engine** that order is not guaranteed: Godot's glTF importer re-indexes every mesh (vertices in order of
  first use by the triangles). The stable key of a vertex is its **uv1 plus its layer side**: uv1 is exactly
  `(j / (cols - 1), 1 - i / (rows - 1))` (float32), with `u` mirrored (`1 - j / (cols - 1)`) on the starboard
  layer, and the layer is the side of the flat sail's centreline plane the vertex lies on (port `+y`, glTF `+X`).
  `game/scripts/sail_grid.gd` rebuilds the grid index from that key; `tests/test_sail_grid.py` holds it.

## Physics sidecar (`<id>.physics.json`)

Positions in the body frame.

| key | content |
| --- | --- |
| `hydrostatics` | displaced volume at the DWL (canoe body, fin, bulb, immersed rudder) and its error against displacement + crew, LCB (x and % LWL), VCB, LWL, BWL, Tc, waterplane area, LCF, transverse and longitudinal BM, Cp, Cm (with the requested Cm), Cb, Cwp, wetted surface, kg per cm immersion, lightship rise, bulb lead volume and ballast ratio, lateral areas, and the solver's fitted knobs |
| `perf_inputs` | what the performance file takes from the generator: `collision.outline` (convex, counter-clockwise, `collisions.md` §2.1), `hull_points` on the real waterline in the order of `sea.md` §5.1, `wind_shadow` geometry (height, ce_x, stern_x, chord, width_min, width_spinnaker, turb_width), loa, lwl, bwl |
| `waterline` | the DWL contour, port and starboard |
| `buoyancy_samples` | skin samples up to the sheer with outward normal and area, for pressure integration at any heel and trim (`canoe_volume_check_m3` is their immersed volume by the divergence theorem) |
| `collision_meshes` | closed low-poly hull (canoe body to the deck crown), fin, bulb and rudder slabs |
| `rig` | mast step, masthead, hounds, forestay tack, boom pivot and axis, sprit end, rudder stock and axis, wheel hub, spreader tips, `sheet_leads` (headsail and flying-sail sheet lead block and winch, starboard side, with the drum diameter); with a pole: `pole_pivot`, `pole_axis`, `pole_length` (from the mast front) and `pole_end` (rest position, the spinnaker tack) |
| `model` | file, triangles, nodes, pivots, `lods` (file, triangles and switch distance of each level of detail) |
| `sails` | per sail: node, type, grid size, vertex order, flat area and target, centroid, corner vertices (tack, clew, head), `look` (the look parameters above, every applicable key filled); code zeros and spinnakers also `rule` (luff, leech, foot, mid girth and rule area of the planform) |

## Limits and next steps

- Tiling detail textures and per-vertex AO only: no unique-UV (lightmap) set, so no AO or dirt texture maps;
  sail panels, tapes and film are not in the sailcloth texture (the previews draw seams procedurally); livery
  decals through uv1 still need a shader.
- No crew or sail numbers yet; headsail and kite sheets only on the posed previews (the engine draws them from
  `rig.sheet_leads`).
- The flat spinnaker outline is a centreline projection; its flying shape comes from the simulation.
- Surfaces per boat: one per node and material (about 30 to 40); no merging across nodes yet.
- Multihulls are not supported (one canoe body, one keel).
- `sails[].leech` and `foot` are used for code zeros and spinnakers only; the hull fit leaves Cm as an outcome
  (see above).
