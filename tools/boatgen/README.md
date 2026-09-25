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
`tools/boatgen/previews/`), `--no-previews`, `--size 1600x1000`, `--quiet`. About 8 s per boat on an M-series Mac.

Dependencies: Python 3.9+, `numpy`, `Pillow`; previews also need `moderngl` (`pip3 install --user moderngl`),
which opens a headless OpenGL 4.1 context (no window). Nothing else: the GLB writer, triangulation, lofting and
hydrostatics are in this package.

## Outputs (per class, in `--out`)

| file | content |
| --- | --- |
| `<id>.glb` | the model, flat standard sails |
| `<id>_collision.glb` | low-poly collision meshes (node names carry Godot's `-convcolonly` import suffix) |
| `<id>.physics.json` | physics sidecar (below) |
| `<id>_upwind.glb`, `<id>_downwind.glb` | preview poses only: sails trimmed with camber and twist, boom swung |

Previews in `previews/`: `<id>_upwind.png` (heeled, trimmed, demo livery), `<id>_downwind.png` (spinnaker set),
`<id>_profile.png` (the exported model as is, dry, from starboard), `<id>_deck.png` (cockpit and deck
hardware), `<id>_uv.png` (0.25 m checker on uv0 of every surface) and `<id>_lines.png` (lines plan: profile with
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
bowsprit, pole}`, `sails[].{id, type, area, luff, tack_x}`, `crew.{count, weight}`.

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
- `sails[].area` is matched exactly by the flat outline (mainsail roach, headsail clew position, spinnaker
  width). `luff` and `tack_x` override the rig-derived values when given; `leech` and `foot` are not used yet.

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
| `hull.stem_radius` | 0.04 | forefoot rounding (m) |
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
`flutter_amp`, `flutter_rate`, `flutter_rate_max`, `twist_top`, `depth`, `tack_line_max`, `furl_radius` (numbers
>= 0; an unknown key is an error). The generator copies them into the sidecar's `sails.<id>.look` and fills
every missing key from the defaults of the sail's type: the table of §4, `flutter_rate` and `flutter_rate_max`
from the LOA size rules, and `furl_radius` (jib, genoa, code zero) from the flat sail's chord extent `Sa`. Keys
that do not apply to a type (`depth` on a main) are written only when the class file gives them.

## How the geometry is made

**Hull** (`hull.py`). Each station is a superellipse bottom from the keel point to the bilge turn, then a topside
curve up to the sheer, meeting with a vertical tangent so the skin is smooth (or creased, aft of the chine
start, for `chined`). Five longitudinal curves drive the stations: the profile (keel line, forefoot and raked
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

**Hardware** (`hardware.py`). A library of parametric parts (self-tailing winch, horn and cam cleats, clutch bank,
block, track and car, stanchion, bent-tube frames, wheel, hatch) placed by rules that read the deck, cockpit and
rig: primaries beside the cockpit, halyard winches and clutches on the cabin top, jib tracks under the clew,
traveller under the boom end with a four-part mainsheet, cleats at bow and quarters, lifelines at about 2 m
spacing.

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

Material slots (glTF material names, PBR factors only, no textures): `gelcoat`, `nonslip`, `antifouling`,
`boottop`, `carbon`, `metal`, `sailcloth`, plus `glass`, `rope` and `rubber`. Each material's `extras.tiling_m`
suggests the size of one tile of its texture.

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
| `rig` | mast step, masthead, hounds, forestay tack, boom pivot and axis, sprit end, rudder stock and axis, wheel hub, spreader tips; with a pole: `pole_pivot`, `pole_axis`, `pole_length` (from the mast front) and `pole_end` (rest position, the spinnaker tack) |
| `sails` | per sail: node, type, grid size, vertex order, flat area and target, centroid, corner vertices (tack, clew, head), `look` (the look parameters above, every applicable key filled) |

## Limits and next steps

- The look relies on geometry and flat PBR factors. A shipped boat needs texture sets for each slot (gelcoat
  with subtle orange peel, non-slip, carbon weave, sailcloth with panels and film), baked ambient occlusion for
  the hull and deck, and livery decals through uv1.
- No crew, running rigging (halyards, sheets other than the mainsheet), instruments or sail numbers yet; the
  organisers at the mast foot are single blocks.
- The flat spinnaker outline is a centreline projection; its flying shape comes from the simulation.
- One LOD. The model is about 50 to 60 k triangles; a game needs two or three LODs (fewer stations, hardware
  dropped or merged) and a draw-call budget per boat.
- Multihulls are not supported (one canoe body, one keel).
- `sails[].leech` and `foot` are not used; the hull fit leaves Cm as an outcome (see above).
