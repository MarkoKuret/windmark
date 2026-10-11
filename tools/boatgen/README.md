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
| `<id>.glb` | the game model (below), flat standard sails |
| `_tex/` | the shared tiling atlas (`tiles_color.png`, `tiles_mr.png`, `tiles_normal.png`) and the sails' weave set, referenced by URI from every GLB, with Godot import settings (VRAM-compressed); written once per output folder |
| `*.glb.import` | Godot import settings for each GLB: the engine's automatic levels of detail on, no shadow meshes |
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
  | `spinnaker_asym` | sprit end | 0.82 luff | 0.57 luff | 0.95 foot | 45 % |
  | `spinnaker_sym` | pole end | = luff | 1.75 pole, at most 0.6 luff | 0.95 foot | 50 % |
  | `code_zero` | sprit end | 0.90 luff | 0.46 luff | 0.56 foot | 20 % |

  The luff is the straight line from the tack to the halyard point (0.12 m below the masthead at the mast front);
  the clew is where the foot from the tack meets the leech from the head. The luff and leech are then bowed
  outward (split by the luff share) until the mid girth, between the mid points of the luff and leech edges,
  reaches its value (deepest at 0.55 of the edge on an asymmetric spinnaker, for its broad shoulders, at 0.45
  on the others; real asymmetrics measured in `docs/specs/sail_visuals.md` §14.1); the foot has a fixed round (asym 8 %, sym 10 %, code zero 2 % of the foot). Rule area
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
| `deck.cabin` | height 0.26 (LOA/12)^0.6, meet_aft_of_mast 0.05 (LOA/12)^0.5, slope_from 0.3, width 0.58, side_rake 0.35, edge_radius 0.05 (LOA/12)^0.5, windows true | the coachroof (`docs/specs/data_format.md` §3.7.2: height aft, where the top meets the deck, where it starts to slope, base width, side rake, edge radius; `length` instead of `meet_aft_of_mast`); `null` for a flush deck |
| `deck.nonslip_margin` | 0.05 | smooth gelcoat border around non-slip panels (m) |
| `deck.toe_rail` | 0.035 (LOA/12)^0.4 | toe-rail size (m) |
| `deck.lifelines` | LOA >= 9 m | stanchions, lifelines, pulpit and pushpit |
| `deck.steering` | wheel from 11 m, else tiller | `wheel` or `tiller` |
| `deck.wheel` | diameter min(0.855 cockpit width, 1.35 (LOA/12)^0.7), well false, hub_height (well) 0.62 (LOA/12)^0.5 else diameter/2 + 0.12 | the helm of a wheel boat (`docs/specs/data_format.md` §3.7.3): with `well` the wheel's lower part runs through a slot in the cockpit floor |
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
every missing key from the defaults of the sail's type: the table of §4 (`camber` 0.12 on a code zero, 0.27 on
an asymmetric and 0.26 on a symmetric spinnaker; `twist_top` 0.45 on an asymmetric spinnaker), `flutter_rate` and `flutter_rate_max` from the LOA size rules, and `furl_radius` (jib, genoa,
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
cockpit and coachroof base, with gelcoat margins around non-slip panels. The cockpit is a well running aft to an
open transom. The coachroof (`data_format.md` §3.7.2) is a height field over the deck in the style of a modern
cruiser-racer: low, level over the companionway, then sloping down forward along a half cosine until it meets the
deck tangentially just aft of the mast; per station a section of a fillet at the foot, a side raked inward, an edge
radius and the cambered top, all shrinking with the height, so there is no front face; in plan its sides follow the
sheer and round in to the centreline over the last fifth. It is meshed on the deck's stations from base to base, so
the deck strips and it share their edge. Only the aft face is upright, with the companionway; the sliding hatch is a
low lid draped on the top, and slim side windows run where the top is at least 0.15 m high. The transom face, toe
rail and rub strake close it off. `Deck.surface` and `Deck.surface_z` give the walking surface (the coachroof with
its sides, the cockpit floor, the deck) that the hardware and the rope leads sit on.

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
hinges and handles, stanchions, bent-tube pulpit and pushpit, a regatta helm (the wheel with its grip on a slim
pedestal with a small head round its shaft, no guard or instrument pod; with `deck.wheel.well` a big wheel whose lower part runs through a slot in the cockpit floor), gudgeons or the rudder bearing cap, rigging screws. Placement: primaries beside the cockpit,
halyard winches (wm12), clutches and organisers on the coachroof clear of the sliding hatch, flush hatches bent
to the top's slope and crown (`on_surface(..., conform=True)`), the halyards themselves from their exits low on the
mast round the sheave of their turning block at the mast foot, then along the deck and up the sloping top lying on
it (`hardware.lead_path`: a span between two surface points follows the surface 2 mm above it, a span to a fitting
runs straight and never dips into it), through the organiser at its sheave height and the clutch's jaws, to tails
flaked on the top (wm12) or over the top's aft edge and down its aft face into the cockpit (wm7); jib tracks under
the clew, outboard of the coachroof's foot, the traveller under the boom end with its control lines and a
four-part mainsheet with its tail, cleats at bow and quarters. Lifelines as on a real boat of the size: the
pushpit wraps the quarters to 0.9 s forward of the transom, the pulpit's aft legs stand 1.3 s aft of the stem, the
stanchions only between them, evenly at most 2.1 m apart (OSR 3.14: 2.2 m), raked slightly outboard; the end legs
of the pushpit and pulpit stand in the stanchions' line, and both tiers run fitting to fitting (upper through the
tops, lower through the eyes at 0.55 of the height).

**Rig fittings** (`rig.py`). Mast step plate, gooseneck bracket and pin, vang tang and boom bail, halyard sheave
boxes, masthead crane with sheaves, wind wand, instruments on the mast front, spreader root brackets and tip
boots, chainplate cover plates, rigging screws at the foot of every shroud and stay, outhaul and cheek blocks on
the boom.

**Attachments** (`attach.py`). Every fitting is built from the surface or part it is fitted to, never from a
nominal height: deck hardware stands on `Deck.surface` (deck, cabin roof or cockpit floor), each shroud and stay
starts on top of its own rigging screw, in line with the wire, on a chainplate strap through a cover plate (the
forestay on the stemhead fitting; on an open transom the backstay splits into two legs to plates on the quarters),
the cap shrouds end in the mast wall at its tapered width, the backstay at the crane end, the bobstay on an eye on the
stem as meshed. The mainsheet's upper block hangs from a bail on the boom's real underside (`Rig.boom_bottom`), the
lower block stands on the traveller car, and the tackle runs between the two sheaves. On a transom rudder the tiller
butt sits between the rudder-head cheeks on the head's bolt (`Appendages.tiller_pivot`, cheek gap = blade
thickness), and the pintle straps sit between the gudgeon arms below the transom's top. The builders tag each
piece (`Part.add(..., tag=)`) and record what it is fitted to (`Part.attach(piece, *hosts)`); `Boat.attachment_gaps()`
measures the gap of every attachment on the meshes as built, and `tests/test_attachments.py` holds it at 5 mm or
less for wm7 and wm12. The same test checks the lifelines end by end (`Boat.lifelines`: the last 2 cm of every
segment within 1 mm of its stanchion, pushpit or pulpit; every stanchion's top and eye on its tier, with a segment
ending on it from each side; the spacing between the pushpit, the stanchions and the pulpit 1 to 2.2 m) and the
halyard leads (`Boat.rope_paths`: never inside the deck or coachroof, the spans along the surface within 5 mm of the
deck mesh, through their exit plate, turning block, organiser and clutch).

**Running rigging** (`running.py`). The posed previews lead the working sheet of each set headsail or flying sail
from the clew through its lead (the jib car block, or a block on the quarter for a kite) to a winch, wrapped on
the drum, with the tail flaked in the cockpit, plus a slack lazy sheet, and for a kite the tack line and the
halyard. The exported model has no headsail or kite sheets (they follow the trimmed sail, so the engine draws them
from `rig.sheet_leads` in the sidecar, `docs/specs/sail_visuals.md` §11.3); the halyard tails and the mainsheet are in
the model. Every rope is in the material slot of its function (below, "Materials and UVs").

**Livery panels.** A number panel forward and a name panel aft on each topside, given in the GLB root extras
(`livery_panels`: body x range, depth below the sheer, uv1 rectangle on the hull atlas); the previews draw them
in the demo livery. The transom has a name panel (`livery_transom.panel`: uv1 rectangle on the transom and size in
metres): the band below the cockpit opening, above the boot stripe, or, with a transom-hung rudder, the part of it
to starboard of the gudgeons. The game paints the liveries into them at load (`game/README.md` "Liveries").

## The game model

One detailed model per class (`docs/specs/sail_visuals.md` §11.4): Godot generates its levels of detail on import
and picks one by size on screen, so there are no hand-made coarser models. `Boat.parts` stays the full model (the
physics, the attachment and lead checks, the posed previews and `tools/liverybake` read it); `Boat.game_parts()`
builds the game model and `Boat.write_game_glb` writes it with the shadow proxy:

- the hull, deck, keel and rig at the full model's detail;
- the hardware low-poly (`hardware.lowpoly`): winches about 450 triangles, clutches about 80 each, blocks about
  120, cars, stanchions, the wheel about 1,100 (a smooth rim near the camera);
- paint what is flat, model what sticks up, drop what is under a pixel (`hardware.PAINTED`, `hardware.DROPPED`, by
  the pieces' tags): the jib and traveller tracks, hatches, organisers, cam, horn and traveller cleats, the rudder
  bearing ring and the mainsheet coil are painted into the livery's deck maps; the halyards, the
  mainsheet tail and the traveller control lines are painted where they lie on surfaces (within 3.5 cm of the deck
  or the coachroof's top, `hardware.ROPE_LIFT_MAX`, and down the coachroof's aft face on its own rectangle of the
  plan, `Boat.line_on_face`) and stay thin rope geometry only where they hang in the air (`Boat.painted_part()`, drawn by `tools/liverybake`); each hatch also
  stands as a plain box about 3 cm proud on the deck node, whose top shows the painted frame and lens. The halyard
  exits, the anemometer, the antenna, the outhaul, sheaves, sheave boxes and bolts go. The mast-foot and traveller
  blocks, the clutches, winches, cars, mast foot, mast instruments, the wind wand, the rope bags (each halyard tail
  runs as straight as it can from its clutch to its place at a low bag on the aft face either side of the
  companionway, past a winch base or hatch on the shorter side, `hardware.route_around`; no halyard coils), stanchions, pulpit, pushpit,
  lifelines, rigging screws and the helm stay modelled;
- one node `body` for every static part (hull, deck, keel, mast, rigging, hardware; each vertex's source part in
  `COLOR_0` blue, GLB root extras `body_parts`) and the moving parts on their own: `rudder` (with the tiller),
  `wheel`, `boom`, `mainsheet`, `pole`.

| | wm7 | wm12 |
| --- | --- | --- |
| nodes drawn without the sails | 4 (body, rudder, boom, mainsheet) | 5 (with the wheel) |
| model triangles without the sails (full model: 72 k, 92 k) | ~51 k | ~60 k |

The sidecar's `model` gives the game model's `triangles` and `surfaces` without the sails, `sail_triangles`, the
node set and `full_triangles` (the full model). `game/tests/boat_import_test.gd` prints the triangles the engine's
levels draw at 25 to 400 m.

**Shadow proxy** (`Boat.shadow_proxy`): about 500 triangles of hull, height-field deck with the coachroof, keel,
rudder and mast (node `shadow`), and the boom (`shadow_boom`, a child of the `boom` node, so it swings with it), in
the material `shadow`. The game casts the sun's shadows from it only; every vertex lies on the full model's
surfaces, so the proxy sits inside the drawn boat.

## Model structure

Nodes under the root (named after the class id):

| node | pivot | note |
| --- | --- | --- |
| `body` | | every static part: hull, deck, keel, mast, rigging, hardware |
| `rudder` | rudder stock, turns about the vertical | carries the tiller when steering is `tiller` |
| `wheel` | wheel hub, turns about fore and aft | only with `wheel` steering |
| `boom` | gooseneck, turns about the vertical | carries the upper mainsheet block |
| `mainsheet` | | tackle between boom and traveller; rebuild it as the boom moves |
| `pole` | on the mast axis at the heel height, turns about the vertical | spinnaker pole, only for a class that flies a spinnaker on a pole (below) |
| `sail_<id>` | | one per class sail, flat, two layers |
| `shadow` (and `shadow_boom` under `boom`) | | the shadow proxy (above), material `shadow` |

Pivot nodes store their geometry relative to the pivot and carry the pivot as their translation.

A class flies its spinnaker on a pole when it has a `spinnaker_sym`, or a `spinnaker_asym` with `rig.pole > 0`
and no bowsprit. The pole (length `rig.pole`, default 0.95 J) points forward from the mast front on the
centreline at rest, and its end is the spinnaker's tack. Its pivot is on the mast axis, the axis the spinnaker
swings about (`sail_visuals.md` §7.3), so turning the pole node by the pole angle keeps its end on the swung
tack. The front end shows it only while the spinnaker is not `down`; the preview poses without a spinnaker leave
it out.

## Materials and UVs

**One material** (`gltf.py`, `data_format.md` §8.5): every opaque surface but the sails is in the glTF material
`boat`, one primitive per node. Each vertex carries its slot in `COLOR_0` (green = slot id / 255, red = the baked
AO). The material's extras hold the slot table (`gltf.ATLAS_SLOTS`: name, mean colour (linear), roughness, metallic,
tile of the atlas, tile size `tiling_m` in metres of uv0, livery region) and the atlas layout. The slots are the
earlier material slots split by where they are: `hull_gelcoat`, `hull_boottop`, `hull_antifouling` (region `hull`),
`deck_gelcoat`, `deck_nonslip` (region `deck`), `transom`, `keel` (region `keel`), `rudder` (region `keel_colour`),
`deck_face` (the coachroof's aft face, region `deck` on its own rectangle of the plan, `Deck.face_frame`), and
`gelcoat`, `carbon` (spars, pedestal, wheel, tiller: dark and slightly glossy, the clear coat's orange peel, no
weave), `metal`, `rubber`,
`glass`, `nonslip`, `antifouling`, `boottop` and the ropes (`rope` for the lifelines and the rope functions
`rope_mainsheet`, `rope_halyard_main`, `rope_halyard_jib`, `rope_halyard_kite`, `rope_halyard_code`, `rope_control`,
`rope_sheet`,
`rope_kite_sheet`, `data_format.md` §8.7) without a region. Each rope slot's mean colour is the braid of the
function's default rope set (`gltf.ROPES`). The sails keep their own material `sailcloth`, and the shadow proxy its
`shadow`. `gltf.read_glb` hands the GLB back per slot (named after its base material) for the previews and tests.

**Texture set** (`boatgen/textures.py`, images in `textures/`). Every slot reads one tile of the shared tiling atlas
(`_tex/tiles_color.png`, `tiles_mr.png` with roughness in G and metallic in B, `tiles_normal.png` in the OpenGL
convention): the sets below but the sails' weave side by side, 4 x 2 tiles of 512 (two free), and a flat tile for the glass. The textures vary
around a fixed mean (`DETAIL_MEAN`, `ROUGH_MEAN`), so a slot looks the same on average with or without them. The game
wraps each tile itself (`shaders/boat_atlas.gdshader`); a plain glTF viewer shows the atlas unwrapped.

| set | slots | tile (m) | source (CC0, docs/THIRD_PARTY.md) |
| --- | --- | --- | --- |
| `orange_peel` | gelcoat, boottop, transom, carbon (its clear coat) | 0.5 | ambientCG Plastic013A |
| `diamond` | nonslip | 0.1 | procedural (textures.py): moulded raised-diamond non-slip, about 6 mm pitch |
| `grain` | antifouling, rubber | 0.5, 0.1 | ambientCG Rubber004 |
| `brushed` | metal | 0.2 | ambientCG Metal009 |
| `weave` | sailcloth | 0.5 | ambientCG Fabric062 (no normal map: the run-time sail mesh has no tangents) |
| `braid` | rope and every `rope_*` slot | 0.05 | ambientCG Rope002 |

`python3 -m boatgen.textures [--cache DIR]` downloads the 1K sources again and rewrites `textures/`; the build
only reads the processed files.

**Baked ambient occlusion** (`boatgen/bake.py`). Every node except the sails, the mainsheet (deformed or rebuilt at
run time, AO 1) and the shadow proxy carries per-vertex AO in the red of `COLOR_0` (unsigned byte, normalised; green
is the slot id, alpha 1): the cosine-weighted share of 160 directions over the vertex's hemisphere in which the
fixed model (sails excluded) does not hide it, from GPU depth maps. The game applies it to
the ambient and reflected light only. The pivoting nodes (rudder, boom, wheel, pole) are baked in their rest
position. Straight swept parts (tubes, wires, tracks) are split into segments of at most 0.5 m so the AO has
vertices to vary on.

- **uv0** is metric everywhere, for tiling PBR textures: hull `u` = x along the length, `v` = girth from the keel
  (both in metres); deck, cabin top and cockpit floor planar (x, y); walls (along, height); sails (distance from
  the luff, height above the foot); swept parts (along the path, around the section). Ropes (`hardware.rope_tube`):
  metres along and the fraction of the turn times 0.05 m round, with a duplicated seam column, so one texture tile
  wraps exactly once round the rope (the rope textures of `data_format.md` §8.7).
- **uv1** is normalised, for liveries and decals. Hull: one atlas with the starboard side in `v` 0..0.5 and the
  port side in 0.5..1, sheer at the top of each band, `u` running so text reads bow-first on both sides. Deck (every
  slot of the `deck` node but `transom`): the plan view, `u = (x - x0) / length` bow to the right, `v = (y_top - y) /
  height` port at the top, over the hull's length and beam with a 1 % margin (`Deck.plan_rect`; GLB root extras
  `deck_plan` = `[forward_min, port_top, length, height]` in the model frame). Transom: seen from astern, `u = (h -
  y) / 2h` port on the left, `v = (top - z) / (top - bottom)` (`Deck.transom_rect`; extras `livery_transom.rect` =
  `[h, top, bottom]`). Both are the same on every level of detail (`data_format.md` §8.5). Sails:
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
| `perf_inputs` | what the performance file takes from the generator: `collision.outline` (convex, counter-clockwise, `collisions.md` §2.1), `hull_points` on the real waterline in the order of `sea.md` §5.1, `wind_shadow` geometry (height, ce_x, stern_x, chord, width_min, width_spinnaker, turb_width), loa, lwl, bwl, `heel_attitude` (`heel`, `rise`, `trim`: at each heel from 0 to 35° the free-floating equilibrium of the skin samples below, the volume and the longitudinal centre of buoyancy held at the upright DWL; `docs/specs/boat.md` §5.6) |
| `waterline` | the DWL contour, port and starboard |
| `buoyancy_samples` | skin samples up to the sheer with outward normal and area, for pressure integration at any heel and trim (`canoe_volume_check_m3` is their immersed volume by the divergence theorem) |
| `collision_meshes` | closed low-poly hull (canoe body to the deck crown), fin, bulb and rudder slabs |
| `rig` | mast step, masthead, hounds, forestay tack, boom pivot and axis, sprit end, rudder stock and axis, wheel hub, spreader tips, `sheet_leads` (headsail and flying-sail sheet lead block and winch, starboard side, with the drum diameter); with a pole: `pole_pivot`, `pole_axis`, `pole_length` (from the mast front) and `pole_end` (rest position, the spinnaker tack) |
| `model` | file, `triangles` and `surfaces` of the game model without the sails, `sail_triangles`, `full_triangles` (the full model), nodes, pivots |
| `sails` | per sail: node, type, grid size, vertex order, flat area and target, centroid, corner vertices (tack, clew, head), `look` (the look parameters above, every applicable key filled); code zeros and spinnakers also `rule` (luff, leech, foot, mid girth and rule area of the planform) |

## Limits and next steps

- Tiling detail textures and per-vertex AO only: no unique-UV (lightmap) set, so no AO or dirt texture maps;
  sail panels, tapes and film are not in the sailcloth texture (the previews draw seams procedurally); the
  liveries are hand-owned textures on uv1 and the sails' flat plan (`tools/liverybake`, `data_format.md` §8.5).
- No crew yet; headsail and kite sheets only on the posed previews (the engine draws them from
  `rig.sheet_leads`).
- The flat spinnaker outline is a centreline projection; its flying shape comes from the simulation.
- Surfaces per boat: one per node (4 or 5, a pole class 6) plus the sails.
- Multihulls are not supported (one canoe body, one keel).
- `sails[].leech` and `foot` are used for code zeros and spinnakers only; the hull fit leaves Cm as an outcome
  (see above).
