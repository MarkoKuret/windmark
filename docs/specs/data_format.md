# Data formats: boat class, performance tables, venue physics

Three kinds of files feed the simulation core:

| file | schema | written by | read by |
| --- | --- | --- | --- |
| boat class `<class>.boat.json` | `windmark.boatclass/1` | designers (by hand or with tools) | boat generator (`tools/boatgen`), VPP (`tools/vpp`) |
| performance `<class>.perf.json` | `windmark.perf/1` | VPP tool, **generated, never hand-edited** | core, AI, HUD |
| venue physics `<venue>.venue.json` | `windmark.venue/1` | venue tool (`tools/venuegen`, `venues.md`) | core (wind field, current, sea exposure, land, obstacles), race layer (conditions), front end (briefing) |

Courses and marks are defined in `courses.md` (`windmark.course/1`). The core never reads the class file directly: everything it needs is
in the performance file, which carries the hash of the class file it was made from.

The front end also reads the livery files of §8 (`<class>.liveries.json`: colours, names and sail numbers) and
the rules scenario files of §9 (`<id>.scenario.json`); the core never does.

## 1. General rules

- **JSON**, UTF-8, no comments. Top-level `"schema"` names the format and major version; a reader refuses a
  different major version. Unknown keys are ignored (forward compatibility) except inside tables.
- **SI units** everywhere: m, m², kg, s, rad, m/s, m/s², rad/s. No knots or degrees in files; tools display
  them. Field names carry no unit suffix; the unit is fixed by this spec. The one exception is the rules scenario
  file (§9), written by hand: it also takes degrees and knots under keys that name the unit.
- **Numbers**: decimal JSON numbers, parsed to binary32 with correct rounding (`conventions.md` §5 rule 13).
  Writers emit 9 significant digits. `NaN`, `Infinity` are not JSON and never appear.
- **Positions** are in the boat body frame (`conventions.md` §3): `x` forward, `y` to port, `z` up, origin at the
  hull reference point (§2). Venue positions are world ENU metres from the venue origin.
- **Ids** are lowercase ASCII `[a-z0-9_]`, unique within their list.
- **Validation** failures are load errors with the file, the JSON path and the reason. The core never runs with
  partly valid data.
- Snippets below marked *schematic* use `//` notes and `…` for brevity; real files have neither.

## 2. The hull reference point

The body-frame origin: on the centreline, in the plane of the design waterline (DWL, the flotation plane of the
boat in sailing trim with crew aboard, level), at the midpoint of the waterline length. The forward end of the
waterline is at `x = +lwl/2`, the aft end at `−lwl/2`, the DWL at `z = 0`.

## 3. Boat-class file (`windmark.boatclass/1`)

The design description of a class: what the boat generator needs to build the model and what the VPP needs to
compute its performance. Required fields are marked **R**; the rest have the stated default or are omitted.

### 3.1 `hull`

| field | | unit | meaning |
| --- | --- | --- | --- |
| `loa` | R | m | length overall of the hull (stem to transom, excluding sprits) |
| `lwl` | R | m | length of the design waterline |
| `beam_max` | R | m | maximum beam of the hull |
| `bwl` | R | m | maximum beam at the waterline |
| `draft_canoe` | R | m | depth of the canoe body below the DWL (Tc), excluding appendages |
| `displacement` | R | kg | mass of the boat in sailing trim **without crew** (hull, appendages, rig, sails, gear) |
| `prismatic` | R | – | prismatic coefficient Cp of the immersed canoe body |
| `section_shape` | R | object | `{ "type": "round" \| "u" \| "v" \| "flat" \| "chined", "midship_coefficient": Cm, "deadrise": rad, "chine_height": m }`; `deadrise` default 0.2 rad, `chine_height` (above DWL, `chined` only). `midship_coefficient` is optional and only a hint: displacement and Cp win, and the generator reports the resulting Cm |
| `rocker` | R | object | `{ "fwd": m, "aft": m }`: height of the canoe-body keel line above its lowest point at the forward and aft ends of the waterline |
| `freeboard` | R | object | `{ "bow": m, "mid": m, "stern": m }`: sheer height above the DWL at the stem, at mid-length and at the transom |
| `transom_width` | R | m | width of the transom at the sheer |
| `stem_x`, `transom_x` | R | m | body x of the stem head and the transom (so `loa = stem_x − transom_x`) |
| `max_beam_station` | | – | station of maximum beam as a fraction of `loa` from the transom [0.45] |
| `lcb_x` | | m | body x of the centre of buoyancy [VPP estimate from Cp and rocker] |
| `bow_fineness` | | – | exponent of the plan-view entry (`collisions.md` §2.1) [1.8] |
| `hull_mass_z` | | m | vertical centre of gravity of the boat without crew above the DWL [VPP estimate] |
| `type` | | – | `"monohull"` \| `"trimaran"` \| `"catamaran"` [`monohull`]; multihull fields in §3.9 |

### 3.2 `keel`

| field | | unit | meaning |
| --- | --- | --- | --- |
| `type` | | – | `"fin_bulb"` \| `"fin"` [`fin_bulb`] |
| `depth` | R | m | total draft: DWL to the bottom of the keel (bulb) |
| `chord_root`, `chord_tip` | R | m | fin chord at the hull and at the tip |
| `thickness` | | – | thickness/chord ratio [0.10] |
| `sweep` | | rad | sweep of the quarter-chord line [0.1] |
| `x` | R | m | body x of the root quarter-chord point |
| `fin_mass` | R | kg | mass of the fin |
| `bulb_mass` | R | kg | mass of the bulb (0 for `fin`) |
| `bulb_length`, `bulb_diameter` | | m | bulb size [from mass, lead density] |

### 3.3 `rudder`

| field | | unit | meaning |
| --- | --- | --- | --- |
| `type` | | – | `"spade"` \| `"transom"` [`spade`] |
| `depth` | R | m | DWL to the rudder tip |
| `chord_root`, `chord_tip` | R | m | chords at the hull and the tip |
| `thickness` | | – | thickness/chord [0.11] |
| `x` | R | m | body x of the stock |
| `max_angle` | | rad | largest rudder angle [0.61] |
| `count` | | – | rudders in the water at once (drag and lift counted per rudder, e.g. 2 on a catamaran or twin-rudder boat) [1] |

### 3.4 `rig`

| field | | unit | meaning |
| --- | --- | --- | --- |
| `I` | R | m | height of the forestay (or gennaker halyard for asymmetric-only rigs) above the sheer at the mast |
| `J` | R | m | base of the fore-triangle: mast front to the forestay tack |
| `P` | R | m | mainsail hoist |
| `E` | R | m | mainsail foot (boom length to the black band) |
| `mast_height` | R | m | masthead above the DWL |
| `mast_x` | R | m | body x of the mast front at the deck |
| `boom_height` | | m | boom above the DWL [default: `mast_height - P - 0.25·s`, s = (L/12 m)^0.6 with L the generator's hull length; shared by the generator and the VPP] |
| `fractional` | | – | forestay height / mast height above the sheer; 1 = masthead [0.8] |
| `bowsprit` | | m | bowsprit (tack point) length forward of the stem, 0 = none [0] |
| `pole` | | m | spinnaker pole length (symmetric spinnakers) [0] |
| `rig_mass` | | kg | mass of mast, boom and rigging (part of `displacement`) [estimate] |

### 3.5 `sails`

An array; exactly one entry of type `main`, any number of front sails. Its order is the class's **sail order**
(§4.4).

| field | | unit | meaning |
| --- | --- | --- | --- |
| `id` | R | – | unique id (e.g. `main`, `jib`, `a2`) |
| `type` | R | – | `main`, `jib`, `genoa`, `code_zero`, `spinnaker_sym`, `spinnaker_asym` (`sails.md` §1) |
| `area` | R | m² | sail area (spinnakers: the rule area) |
| `luff`, `leech`, `foot` | | m | edge lengths [main and headsails: from the rig and the area; flying sails: from the rig, below] |
| `tack_x` | | m | body x of the tack [from the rig: mast for the main, forestay for jibs, sprit or pole] |
| `mid_girth` | | m | flying sails: mid girth `SHW` [from the table below]; exclusive with `mid_girth_frac` |
| `mid_girth_frac` | | – | flying sails: mid girth as a fraction of `SF`, 0.3 to 1.2 [from the table below] |
| `luff_round`, `leech_round`, `foot_round` | | – | flying sails: edge round depth as a fraction of the straight edge, -0.1 to 0.3 [below] |
| `luff_round_pos`, `leech_round_pos`, `foot_round_pos` | | – | flying sails: where along the edge the round is deepest, 0.1 to 0.9 [below] |
| `furling` | | bool | headsail on a furler (hoist animation, and faster handling) [false] |
| `kite_sheet_in` | | rad | main only: how far the main is sheeted in from its own optimum while a spinnaker or code zero is set, 0 to 0.7 (`sails.md` §5.1) [0] |
| `handling` | | object | overrides of the handling block the VPP writes (§4.4) |

Sail areas of the main, jib, genoa, code zero and spinnakers (symmetric or asymmetric) are `sails[].area` with the
matching `type`.

**Flying-sail planform.** A code zero or spinnaker is drawn from the rig with standard proportions, and its `area`
is the rule area of that planform (the class file takes the value the generator reports, rounded down to 0.5 m²;
the generator warns when they differ by more than 3 %). The corners, in the centreline plane:

- **tack**: the sprit end (code zero, asymmetric spinnaker), or the pole end one pole length ahead of the mast front
  (symmetric spinnaker, or an asymmetric one on a class with a pole and no sprit); `tack_x` moves it;
- **head**: the halyard point, just below the masthead at the mast front;
- **luff** `SLU` = the straight tack-to-head distance (`luff` shortens it along the same line);
- **clew**: `foot` `SF` from the tack and `leech` `SLE` from the head, aft of the luff line.

| type | `SLE` | `SF` | mid girth `SHW` |
| --- | --- | --- | --- |
| `spinnaker_asym` | 0.82 `SLU` (0.85 along the rounded edges) | 0.57 `SLU` | 0.88 `SF` (real asymmetrics: 0.93 to 1.0, ORC's usual case above 0.85, `sail_visuals.md` §14.1; a little under them so the reaching clew stays aft of the mast) |
| `spinnaker_sym` | `SLU` (equal luffs) | 1.75 × pole length, at most 0.6 `SLU` | 0.95 `SF` |
| `code_zero` | 0.90 `SLU` | 0.46 `SLU` | 0.56 `SF` (below the 0.75 `SF` spinnaker line: flatter and narrower) |

`leech` and `foot` in the class file override the table. The edges are rounded (luff and leech outward, foot
downward) so the mid girth, measured between the mid points of the luff and leech edges, hits `SHW`. The rule area
is `(SLU + SLE) / 2 · (SF + 4 · SHW) / 6` with `SLU`, `SLE`, `SF` measured along the rounded edges.

**Shaping keys** (code zeros and spinnakers only; an error on any other sail type). Each edge is a smooth bump over
the straight line between its corners: `<edge>_round` is the bump's greatest depth as a fraction of that straight
edge (positive outward: luff forward, leech aft, foot down; negative is a hollow), and `<edge>_round_pos` is where
the greatest depth sits, as a fraction of the edge from its lower or forward corner (luff: tack 0, head 1; leech:
clew 0, head 1; foot: tack 0, clew 1). The mid girth target is `mid_girth` (m) or `mid_girth_frac` (of `SF` along
the rounded foot), else the table's value.

| edge | round when absent | round position when absent |
| --- | --- | --- |
| foot | asym 0.08, sym 0.10, code zero 0.02 | 0.5 |
| luff, leech | solved: the mid girth target is met by bowing luff and leech together, the luff taking a fixed share of the bow (asym 45 %, sym 50 %, code zero 20 %) | asym 0.55 (broad shoulders: 0.53 `SF` wide at three quarters of the height, real 0.59 to 0.62), others 0.45 |

- neither `luff_round` nor `leech_round` given: both are solved together as in the table (the shape with no keys);
- one of them given: it is fixed and the other one is solved to meet the mid girth target;
- both given: the mid girth is an outcome, and giving `mid_girth` or `mid_girth_frac` as well is an error.

A mid girth target the solved edge cannot reach (its round would leave -0.1 to 0.3) is an error. Any change to
these keys changes the rule area: the class `area` and the performance tables are then regenerated (§4). With these
proportions the clew sits about a third of the hull length forward of the transom on the flat sail, so set it flies
abreast the cockpit and the sheet leads aft to the quarter.

### 3.6 `crew`

| field | | unit | meaning |
| --- | --- | --- | --- |
| `count` | R | – | crew number |
| `weight` | R | kg | total crew mass |
| `hiking_arm` | | m | mean crew righting arm from the centreline when hiked [0.45 · `beam_max`] |

### 3.7 Other blocks

| block | owner | meaning |
| --- | --- | --- |
| `start` | designer | `{ "front_sail": id \| null }`: sail up at a race start unless the race says otherwise |
| `handling` | designer | feel multipliers and `dynamics` overrides (§3.7.1) |
| `boards` | designer | daggerboards of a multihull, in place of `keel` (§3.9) |
| `vpp` | designer | VPP settings (§3.10) |
| `visual` | boat generator | deck layout (the coachroof: §3.7.2), hardware, and per sail `sails.<id>.look` (the front-end sail look of `sail_visuals.md` §4, copied into the physics sidecar with the defaults filled in); keys in `tools/boatgen/README.md`; opaque to the core and the VPP |

Top level: `"schema": "windmark.boatclass/1"`, `"id"`, `"name"`, `"version"` (integer, bumped on every change).

The generated model follows two look rules whatever the `visual` block says: every fitting touches what it is
fitted to (no gap over 5 mm between a part and its host on the meshes as built: the tiller in the rudder head, the
mainsheet blocks on the boom and the traveller car, each shroud and stay on a rigging screw standing on its
chainplate or stemhead, all deck hardware on the deck), and each material slot reads as its real material with a
mean linear albedo of at most 0.8 (gelcoat, non-slip, metal, rope; `tools/boatgen/README.md` "Materials and UVs").
The running rigging on deck lies on what it crosses: a halyard or control line led from the mast foot to its clutch
or winch runs a few millimetres above the deck and the coachroof, following their curvature between the fittings it
passes (turning blocks, organisers, clutches), and never passes through the cabin or floats clear of it. Lifelines run
from the pushpit to the pulpit through every stanchion top and the eye of each stanchion for the lower tier, each
segment ending on a stanchion, the pushpit or the pulpit (no gap); stanchions stand between the pushpit's and the
pulpit's ends, never doubling one of their legs, at most 2.2 m apart.

#### 3.7.1 `handling`

Optional. Tunes how a class **feels** without touching how fast it is: the VPP computes the physical tables and
then applies these multipliers when it writes the performance file. None of them changes a `polar`, `trim_speed`
or any other speed target, so a class's speeds (and the AI's and HUD's view of them) stay physical.

| field | | unit | default | range | scales in the performance file |
| --- | --- | --- | --- | --- | --- |
| `accel` | | – | 1.0 | 0.2 to 5 | every config's `accel` table (how fast the boat builds speed towards the polar) |
| `decel` | | – | 1.0 | 0.2 to 5 | `dynamics.decel_linear`, `decel_const` and `decel_windage` (how fast it slows above its target, coasting, in irons) |
| `turn_rate` | | – | 1.0 | 0.2 to 5 | yaw rate at every helm and speed: `dynamics.turn_radius_full` and `turn_radius_offset` are divided by it (`boat.md` §5.9); `rudder_drag_*` unchanged |
| `heel` | | – | 1.0 | 0.2 to 5 | every config's `heel` table (clamped to π/2) and `dynamics.heel_max` (kept below `heel_limit`); `heel_speed_factor` and the main's `sheet_max_by_heel` are stretched along their heel axes by the same factor, so the speed at the scaled heel is what it was at the physical heel |
| `tack_time` | | – | 1.0 | 0.2 to 5 | crew and helm speed in manoeuvres (> 1 is slower): `dynamics.helm_rate` and every sail's `rate_in`, `rate_out` and `pole_rate` are divided by it |

The multipliers used are recorded in the performance file's `handling` block (§4.1), all five, defaults included;
with every multiplier 1.0 the tables are exactly the physical ones.

Any other key of `handling` names a `dynamics` value (§4.2) and overrides it absolutely: the VPP writes it as
given, after the multipliers, unscaled. Unknown keys are reported and ignored.

#### 3.7.2 `visual.deck.cabin`: the coachroof

The coachroof of a performance cruiser-racer (generator only, like the rest of `visual`): a low top over the
companionway that slopes down forward and fairs into the deck, with radiused edges and sides raked inward that follow
the sheer in plan. There is no vertical front: forward the top's height runs smoothly to zero, tangent to the deck,
where the coachroof meets the deck at or just aft of the mast. Only its aft face, over the cockpit, is upright (with
the companionway). `null` gives a flush deck. Every key is optional; `s = (loa / 12)^0.5`.

| key | unit | default | range | meaning |
| --- | --- | --- | --- | --- |
| `height` | m | 0.26 (loa/12)^0.6 | 0.05 to 0.6 | height of the top above the deck's centreline at the aft end (the companionway) |
| `meet_aft_of_mast` | m | 0.05 s | 0 to 1.5 | where the top meets the deck: this far aft of the mast's aft face at the deck (the partners) |
| `length` | m | | > 0.5 | instead of `meet_aft_of_mast`: from the cockpit's forward end to where the top meets the deck (one of the two) |
| `slope_from` | of the length | 0.3 | 0 to 0.8 | the top keeps its height aft of this point, then slopes down to the deck along a smooth curve tangent at both ends (a half cosine); the build logs the steepest slope |
| `width` | of the half-beam | 0.58 | 0.2 to 0.85 | half-width of the coachroof's base as a fraction of the local half-beam, so its sides follow the sheer (at most the cockpit's width; where it is narrower the deck steps in from the cockpit's edge to it); it rounds in to the centreline over the last fifth of its length |
| `side_rake` | rad | 0.35 | 0 to 0.8 | inward lean of the sides from the vertical |
| `edge_radius` | m | 0.05 s | 0.01 to 0.15 | radius of the edge between the sides (and the aft face) and the top; the foot of each side has a fillet of 0.4 of it into the deck; both shrink with the height where the top runs down |
| `windows` | | true | | dark glazing along the sides where the top is at least 0.15 m high |

Hatches on the coachroof are flush, their frames following the top's curve; the companionway's sliding hatch lies on
the top aft. The deck's uv1 (the plan view, §8.5) covers the coachroof like every other deck surface: its sides take
the texels of their narrow footprint between the base and the roof edge.

### 3.8 Example (sportsboat)

```json
{
  "schema": "windmark.boatclass/1",
  "id": "sb7", "name": "Sportsboat 7", "version": 1,
  "hull": {
    "loa": 7.32, "lwl": 6.40, "beam_max": 2.49, "bwl": 2.05, "draft_canoe": 0.28,
    "displacement": 810, "prismatic": 0.54,
    "section_shape": { "type": "round", "midship_coefficient": 0.72 },
    "rocker": { "fwd": 0.20, "aft": 0.05 },
    "freeboard": { "bow": 0.78, "mid": 0.60, "stern": 0.50 },
    "transom_width": 1.90, "stem_x": 3.72, "transom_x": -3.60, "max_beam_station": 0.40
  },
  "keel": { "depth": 1.52, "chord_root": 0.60, "chord_tip": 0.45, "x": 0.15,
            "fin_mass": 50, "bulb_mass": 290 },
  "rudder": { "depth": 1.10, "chord_root": 0.33, "chord_tip": 0.22, "x": -3.10 },
  "rig": { "I": 8.40, "J": 2.80, "P": 9.20, "E": 3.60, "mast_height": 10.50, "mast_x": 0.55,
           "fractional": 0.80, "bowsprit": 1.70 },
  "sails": [
    { "id": "main", "type": "main", "area": 17.0 },
    { "id": "jib",  "type": "jib", "area": 11.0, "furling": true },
    { "id": "kite", "type": "spinnaker_asym", "area": 42.0 }
  ],
  "crew": { "count": 3, "weight": 245 },
  "start": { "front_sail": "jib" }
}
```

### 3.9 Multihulls

`hull.type` selects the hull arrangement. The VPP reads all three; the boat generator builds monohulls only.

- **Trimaran**: the `hull` fields describe the main (centre) hull, which displaces the whole sailing mass at rest;
  `hull.floats` (required) describes one float, mirrored to both sides.
- **Catamaran**: the `hull` fields describe one of the two identical hulls, each displacing half the sailing mass;
  `hull.hull_spacing` (required) places them.
- For both, `hull.beam_max` is the overall beam; it is taken as at least the span of the hulls.

`hull.floats`:

| field | | unit | meaning |
| --- | --- | --- | --- |
| `lwl`, `bwl` | R | m | float waterline length and beam at its own design waterline |
| `draft` | R | m | float canoe-body depth below its design waterline (`draft_canoe` is accepted too) |
| `prismatic` | R | – | float prismatic coefficient |
| `section_shape` | | object | as `hull.section_shape`; its `midship_coefficient` is used as given [0.70] |
| `freeboard` | | object or m | `{ "bow", "mid", "stern" }` or one height for all three [0.09 · float `lwl` at mid-length, 1.3× bow, 0.85× stern] |
| `beam_max` | | m | float beam at the sheer [1.15 · float `bwl`] |
| `transom_width` | | m | float transom width at the sheer [0.5 · float `beam_max`] |
| `rocker` | | object | `{ "fwd", "aft" }` as `hull.rocker`, of the float [fwd = `draft`, aft = 0.6 · `draft`] |
| `spacing` | R | m | distance of each float's centreline from the boat centreline |
| `clearance` | | m | height of the float keel above the DWL with the boat upright at rest (0 = touching) [0] |
| `x` | | m | body x of the float's mid-waterline [−0.05 · `hull.lwl`] |

`hull.hull_spacing` (catamaran, R, m): distance between the two hull centrelines.

`boards` (multihulls, instead of `keel`; if absent the VPP reads `keel` the same way): the lifting foils that
carry the side force.

| field | | unit | meaning |
| --- | --- | --- | --- |
| `depth` | R | m | DWL to the board tip, board down |
| `chord_root`, `chord_tip` | R | m | chords at the hull and at the tip [`chord_tip` = `chord_root`] |
| `thickness` | | – | thickness/chord [0.12] |
| `x` | | m | body x of the quarter chord [0] |
| `count` | | – | boards in the water at once [1] |

Multihull defaults elsewhere: `crew.hiking_arm` [0.3 · `beam_max`], `vpp.max_heel` [0.28 rad].

### 3.10 `vpp`

Settings of the VPP's equilibrium; ignored by the boat generator and not copied into the performance file (whose
own `vpp` blocks are VPP diagnostics, §4.1).

| field | | unit | meaning |
| --- | --- | --- | --- |
| `max_heel` | | rad | heel the VPP equilibrium may not exceed; where no depowering keeps a config below it the VPP writes a broached speed (§4.3). The limit used is the lower of this and the heel of the maximum righting moment. [0.56 monohull, 0.28 multihull] |

## 4. Performance file (`windmark.perf/1`)

Everything the core needs to sail a class: dynamics constants, per-sail parameters and the per-config tables.
Generated by the VPP tool from the class file; regenerated, never edited.

### 4.1 Header

Schematic:
```json
{
  "schema": "windmark.perf/1",
  "class_id": "sb7", "class_version": 1,
  "class_sha256": "…",          // hash of the class file bytes it was generated from
  "generator": { "tool": "vpp", "version": "…" },
  "handling": { "accel": 1.0, "decel": 1.0, "turn_rate": 1.0, "heel": 1.0, "tack_time": 1.0 },   // §3.7.1, record only
  "dynamics": { … },            // §4.2
  "sails":    { … },            // §4.4, keyed by sail id
  "configs":  [ … ],            // §4.3
  "start":    { "front_sail": "jib" },   // optional
  "vpp":      { … }             // optional, VPP diagnostics, informational
}
```
`handling` records the feel multipliers the tables were written with (§3.7.1); the core does not apply them again.
`start` is optional: absent, or `front_sail` absent or `null`, means no front sail at the start; otherwise
`front_sail` names a front sail of `sails`. `vpp` (top level, and in each config, §4.3) holds VPP diagnostics
(notes, VMG, righting moment, per-config tables): informational only, the core ignores it and does not
validate it.
In online play the server announces `(class_id, class_version, sha256 of the perf file)` for every class in the
race; a client with a different file does not join (`networking.md`).

### 4.2 `dynamics`

Scalars and small tables of `boat.md` §4, plus the collision and wind-shadow blocks. Every value is required;
reference values are in the owning spec.

| key | type | spec |
| --- | --- | --- |
| `helm_rate`, `rudder_max`, `turn_radius_full`, `turn_radius_offset` | float | boat.md §4 |
| `yaw_time` | float, s, 0 to 2 | boat.md §4, §5.9 |
| `decel_linear`, `decel_const`, `decel_windage` | float | boat.md §4 |
| `heel_speed_factor` | Table1D(`heel_abs`) | boat.md §4 |
| `rudder_drag_luff`, `rudder_drag_bear` | Table2D(`boat_speed_abs`, `helm_abs`), m/s² | boat.md §4 |
| `heel_max`, `heel_limit`, `heel_freq`, `heel_damping` | float | boat.md §4 |
| `pitch_freq`, `pitch_damping`, `wave_roll_gain`, `wave_pitch_gain` | float | boat.md §4 |
| `wobble_heel`, `wobble_pitch`, `wobble_freq` | float | boat.md §6.5 |
| `heave_time`, `waterline_offset`, `surf_gain` | float | boat.md §4 |
| `drift_grip`, `drift_length` | optional float, ≥ 0 and > 0 | boat.md §4, §6.4; absent: no sideways drift (both or neither) |
| `full_leeway` | optional bool [false] | boat.md §6.4; true needs `drift_grip` and a `leeway` table in every config |
| `hull_points` | optional `[[x, y], …]` | sea.md §5.1 (default from `lwl`, `bwl`) |
| `lwl`, `bwl`, `loa` | float | copied from the class (hull points, AI, HUD) |
| `collision` | `{ "outline": [[x, y], …], "mass": kg, "yaw_gyration": m, "sprit": m }`; `sprit` optional, ≥ 0 [0]: the bowsprit's reach ahead of the outline's bow point (the class's `rig.bowsprit` when a sail is tacked to it, else 0), used only for the rules' overlap (`rules.md` §3.2) | collisions.md §2.1 |
| `wind_shadow` | object with every key of `wind_shadow.md` §2 | wind_shadow.md §2 |

Ranges checked at load (besides those of the owning specs): `decel_linear`, `decel_const`, `decel_windage` ≥ 0;
`turn_radius_offset` any finite value (negative for a rudder that stalls short of full helm) with
`turn_radius_full + turn_radius_offset > 0`; `rudder_drag_luff`, `rudder_drag_bear` any finite value (§5);
`hull_points`, if present, 1 to 64 points; `drift_grip` and `drift_length` both present or both absent.

`collision.mass` = `displacement + crew.weight`. The VPP derives the dynamics values from the design where it can
(turn radius from the rudder and hull length and the radius law's offset from the rudder's stall, the
deceleration from the hull coasting with the drive gone, heel spring from roll inertia and righting moment, shadow
geometry from the rig) and uses the reference values of the owning spec otherwise; then the class file's `handling`
multipliers are applied and its `handling` overrides win (§3.7.1).

### 4.3 `configs`

One entry per sail combination the boat can fly: main only (`"front_sail": null`) and main + each front sail.
Schematic:
```json
{
  "front_sail": "jib",
  "polar":        { table },       // Table2D(tws, twa_abs) -> m/s
  "heel":         { table },       // Table2D(tws, twa_abs) -> rad
  "accel":        { table },       // Table2D(tws, twa_abs) -> m/s²
  "accel_rest":   { table },       // Table2D(tws, twa_abs) -> m/s², optional
  "trim_speed":   { table },       // Table3D(tws, awa_abs, trim_error) -> 1, optional
  "trim_heel":    { table },       // Table3D(tws, awa_abs, trim_error) -> 1, optional
  "weather_helm": { table },       // Table2D(tws, twa_abs) -> rad/s, optional
  "fall_off":     { table },       // Table2D(boat_speed, twa_abs) -> rad/s, optional
  "flog_drag":    { table },       // Table2D(aws, awa_abs) -> m/s², optional
  "drift":        { table },       // Table2D(tws, twa_abs) -> m/s, optional
  "drift_flog":   { table },       // Table2D(tws, twa_abs) -> m/s, optional
  "leeway":       { table },       // Table2D(tws, twa_abs) -> rad, only with dynamics.full_leeway
  "optimal_angle": { "main": { table }, "jib": { table } }   // Table2D(tws, awa_abs) -> rad
}
```
Semantics in `sails.md` §6. `front_sail` is `null` or the id of a front sail in `sails` (never the main); there
is exactly one main-only config and exactly one config per front sail.

**Coverage** (config tables only: `polar`, `heel`, `accel`, `accel_rest`, `trim_*`, `weather_helm`, `fall_off`,
`flog_drag`, `drift`, `drift_flog`, `leeway`, `optimal_angle`; the `dynamics` and `sails` tables are not checked): every `tws` axis has its first
point exactly 0 and its last point ≥ `20.6f` m/s (40 kn, rounded up); every `twa_abs` and `awa_abs` axis has its
first point exactly 0 and its last point exactly the binary32 π (`PI`, `conventions.md` §6); every `aws` axis has
its first point exactly 0. Other axes are not constrained.

`optimal_angle` is keyed by sail id and holds exactly the main and the config's front sail (only the main for
main-only). `weather_helm` values may be any finite number (signed); `accel_rest`, `fall_off`, `flog_drag`,
`drift` and `drift_flog` ≥ 0, `leeway` in [0, 0.5] rad (§5). `leeway` is required in every config when
`dynamics.full_leeway` is true and ignored otherwise; the VPP writes it only then. The VPP writes every table for every config (`sails.md` §6): `trim_heel` 0 with the driving sail on the
wind line and `trim_speed` there 0 up to 90° AWA and the let-fly share beyond. Absent optional tables: `accel_rest`
= `accel`, `weather_helm`, `flog_drag`, `drift` and `drift_flog` 0 (`drift_flog` absent: the flogging boat drifts
at the `drift` rate).

Above the no-go step the `polar` is never 0. Where no depowering holds a config (heel beyond the limit, or no way
made at that angle) the VPP writes a low **broached speed**, with the `heel` at the limit and the `accel` of the
last wind strength the config still holds at that angle (`tools/vpp/README.md`, "Broached speed"): the boat
wallows rather than stops. A config may carry a `vpp` block of diagnostic tables; the core ignores it.

### 4.4 `sails`

Keyed by sail id, with the members in the class's **sail order** (the order of the class file's `sails[]`,
§3.5); the VPP writes them in that order and a reader keeps it. A **sail index** (`sails.md` §3, `networking.md`)
is the position of a sail in this order, **counting the main**: a front-sail index is the index of that front
sail in the full list, so it is never the main's index (with the main first, the first front sail is index 1).
Exactly one sail has type `main`.

Schematic:
```json
"jib": {
  "type": "jib",
  "sheet_min": 0.244, "sheet_max": 1.22,
  "sheet_max_by_heel": { table },          // optional, Table1D(heel_abs) -> rad
  "rate_in": 0.5, "rate_out": 0.9,
  "pole_angle": { table }, "pole_rate": 0.3,   // optional (spinnakers)
  "shiver_angle": { table }, "shiver_free": false,
  "handling": {                             // front sails only
    "prepare_hoist_time": 0.5, "hoist_time": 2.5 | { table },
    "prepare_drop_time": 2.0,  "drop_time": 4.0 | { table },
    "slow_prepare_hoist": 1.0, "slow_hoist": 0.9, "slow_prepare_drop": 1.0, "slow_drop": 0.9
  }
}
```
Durations are numbers or Table2D(`tws`, `twa_abs`) → s (`sails.md` §4.4). The main has no `handling` (a
`handling` block on the main is a load error); every front sail has one with all eight keys: the four durations
(≥ 0) and `slow_prepare_hoist`, `slow_hoist`, `slow_prepare_drop`, `slow_drop` (≥ 0).

Other values: `sheet_min`, `sheet_max` in [0, π] with `sheet_min ≤ sheet_max`; `rate_in`, `rate_out` > 0;
`sheet_max_by_heel`, `pole_angle` and `shiver_angle` values in [0, π]; `pole_rate` > 0, required when `pole_angle`
is present (optional otherwise); `shiver_angle` and `shiver_free` required.

## 5. Table encoding

Schematic:
```json
{
  "axes": [
    { "q": "tws",     "points": [0, 2.06, 3.09, 4.12, 5.14, 6.17, 7.20, 8.23, 10.29, 12.35, 15.43, 20.6] },
    { "q": "twa_abs", "points": [0, 0.122, 0.2618, 0.2618, 0.349, 0.524, 0.698, 0.785, …, 3.14159274] }
  ],
  "unit": "m/s",
  "values": [ … ]                      // row-major, last axis fastest: 12 × n values
}
```
- `q` names the quantity of the axis, which fixes its unit and range:

  | `q` | unit | range | meaning |
  | --- | --- | --- | --- |
  | `tws` | m/s | ≥ 0 | true wind speed (water-relative, 10 m) |
  | `twa_abs`, `awa_abs` | rad | [0, π] | absolute true / apparent wind angle |
  | `trim_error` | rad | any | `eps` of `sails.md` §5.6 |
  | `boat_speed` | m/s | any | signed boat speed |
  | `boat_speed_abs` | m/s | ≥ 0 | absolute boat speed |
  | `helm_abs` | – | [0, 1] | absolute normalised helm |
  | `heel_abs` | rad | [0, π/2] | absolute heel |
  | `aws` | m/s | ≥ 0 | apparent wind speed (over the moving boat, 10 m reference height) |

- `unit` of the values: one of `m/s`, `rad`, `m/s2`, `rad/s`, `s`, `1`; it must be the unit this spec gives for
  that table.
- Axes: 1 to 3, each with 1 to 256 points, non-decreasing, at most two equal points in a row (a step,
  `conventions.md` §8.1). The number of values is the product of the axis lengths.
- Every value finite. Range checks per table: `polar` in [−5, 40], `heel` in [0, π/2], `accel`, `accel_rest`,
  `fall_off`, `flog_drag` and durations ≥ 0, `trim_*` and `heel_speed_factor` in [0, 3], `optimal_angle`,
  `sheet_max_by_heel`, `pole_angle`, `shiver_angle` in [0, π], `rudder_drag_*` and `weather_helm` any finite value.
- Lookup and interpolation: `conventions.md` §8.

Recommended axes for the VPP (fine where the tables bend):
- `tws`: 0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 20.6 m/s;
- `twa_abs`: 0°, 7°, the no-go edge twice (the step, reference 15°), then 20° to 60° every 2°, 60° to 180° every
  5°;
- `trim_error`: −60°, −20°, −10°, −5°, −2°, −0.5°, 0, 0.5°, 2°, then every 5° from 5° to 130°, 150°, 180° (fine
  enough that the trim tables can reach 0 on the wind line at each `awa_abs` without cutting the drive early,
  `sails.md` §6);
- `fall_off`: `boat_speed` −6, 0, `v_f`/2, `v_f` m/s; `twa_abs` 0°, 10°, 20°, 60°, 90°, 180° (`sails.md` §6);
- `flog_drag`: `aws` 0 to 10 m/s every 1 m/s, then 12, 14, 16, 18, 20, 23, 26, 30, 35, 40 m/s (the drag grows with
  its square); `awa_abs` as the trim tables;
- `rudder_drag_*`: `helm_abs` 0, 0.2, 0.3, then every 0.1 to 1 (the stall knee near 70 % helm).

## 6. Venue physics file (`windmark.venue/1`)

The physical environment of a sailing area, `data/venues/<venue>.venue.json`. Everything is optional except the
header; an empty venue is open water with uniform wind. The core loads it once per race and points the wind,
current and sea settings at it (`wind.md` §1, §7, §8; `sea.md` §2, §6). The venue's typical weather (§6.7) and its
briefing text (§6.8) are in the same file; the venues, their sources and their performance budget are in
`venues.md`.

The **look** of a venue (terrain, scenery, sky, water colours, placed sound sources such as surf and harbour noise,
`audio.md` §7) is not in this file: it lives in a front-end look file next to it, `<venue>.look.json`, whose format
belongs to the front end (`water_render.md`, `audio.md`). The core never reads it; a look file never changes
physics.

### 6.1 Header
Schematic (likewise §6.2–§6.5):
```json
{
  "schema": "windmark.venue/1", "id": "bay", "name": "…", "version": 1,
  "origin": { "lat": 45.5, "lon": 13.6 },       // geo-reference of world (0, 0), display only
  "bounds": [xmin, ymin, xmax, ymax],            // racing area, m; within ±8000
  "fetch": 12000,                                // m, for the wind-sea growth law (sea.md §2)
  "exposure_default": 1.0,
  "source": "…"                                  // provenance note written by venuegen, not shown
}
```
Required: `schema`, `id`, `name`, `version` (integer ≥ 1, bumped on every change) and `bounds` (`xmin < xmax`,
`ymin < ymax`, every value in [−8000, 8000]). Optional: `origin` (`lat` in [−90, 90], `lon` in [−180, 180]),
`fetch` (> 0) [10000], `exposure_default` (in [0, 1]) [1], `source` (string: coastline and terrain sources with
version and download date, `venues.md` §3). `name` is player-facing: no em dashes. `fetch` is the fetch for the
venue's typical wind direction (§6.7), since the sea follows one fetch per race.

### 6.2 `wind_field`
```json
"wind_field": {
  "grid": { "x0": -3000, "y0": -3000, "dx": 100, "dy": 100, "nx": 61, "ny": 61 },
  "sectors": [ { "f": [ … nx*ny … ], "d": [ … nx*ny … ] }, … 8 entries: from N, NE, E, SE, S, SW, W, NW … ]
}
```
Exactly 8 sectors. `f` speed factor ≥ 0, `d` direction offset (rad, + = veer) in [−π, π]. Border nodes must be
exactly `f = 1, d = 0` (validated). Grids: §6.6. Sampling: `wind.md` §8.

### 6.3 `current_field`
```json
"current_field": { "grid": { … }, "vx": [ … ], "vy": [ … ],     // m/s at tide factor 1, east/north
                   "ref_speed": 1.29 }                            // m/s, written by venuegen
```
Zero outside the grid. Used as `tide(t) · field` (`wind.md` §7). `ref_speed` (≥ 0; `venuegen` always writes it,
older files may lack it, §6.9) is the 90th percentile of `|(vx, vy)|` over the grid nodes inside `bounds` (edges
included) that are on water (outside every land polygon): the field's typical strong stream, which the briefing
reads (`menus.md` §1.3). The percentile interpolates linearly between the sorted values (position `0.9 · (n − 1)`,
counted from 0); with no such node it is 0. A venue test recomputes it to within 0.001 m/s.

### 6.4 `exposure`
```json
"exposure": { "grid": { … }, "e": [ … ] }                        // [0, 1]
```
Sea height factor (`sea.md` §6); `exposure_default` outside the grid.

### 6.5 `land` and `obstacles`
```json
"land":      [ { "id": "island_n", "points": [[x, y], …] } ],     // counter-clockwise, interior = land, >= 3 points, simple
"obstacles": [ { "id": "pier", "polygon": [[x, y], …] },           // convex, counter-clockwise
               { "id": "rock", "circle": { "c": [x, y], "r": 4.0 } } ]
```
Validated: ids unique within their list; polygons have at least 3 points, no two consecutive points equal and no
self-intersections (simple); land counter-clockwise (positive area); obstacle polygons strictly convex and
counter-clockwise; an obstacle has exactly one of `polygon` and `circle`; circle `r > 0`. Collision use:
`collisions.md` §2.2, in file order.

### 6.6 Grids
Every field of §6.2–§6.4 sits on a grid `{ "x0", "y0", "dx", "dy", "nx", "ny" }` (`wind.md` §8.1): origin finite,
`dx, dy > 0`, `nx`, `ny` integers from 2 to 1024 (a grid is at least one cell). Each value array holds exactly
`nx·ny` finite numbers, row by row (`j` major, `i` fastest).
Shipped venues also keep the tighter caps of the performance budget (`venues.md` §4: grid sizes, land vertices,
file size); `venuegen` writes within them and a venue test checks every file in `data/venues/`, while the loader
keeps the general limits above.

### 6.7 `conditions`
The venue's typical weather, which the race layer turns into one race's settings with the race seed
(`race.md` §2.1). Schematic (SI units, as everywhere in the file):
```json
"conditions": {
  "wind":   { "speed": [5.14, 8.23], "from": 3.927, "from_spread": 0.262 },
  "shift":  { "preset": "stable", "trend_rate": 0.0, "trend_max": 0.0 },
  "oscillation": { "amplitude": 0.0349, "time_scale": 17 },
  "puffs":  { "preset": "light" },
  "current": { "speed": 0.0, "to": 0.0 },
  "tide":   { "scale": 0.6, "period": 44712, "turn": [0.35, 0.65], "turn_to": -1 },
  "sea":    { "scale": 1.0, "swells": [ { "hs": 0.8, "tp": 12.0, "from": 4.19 } ] },
  "random": { "speed": [3.09, 10.29], "from_spread": 0.698, "shift": ["stable", "oscillating", "shifty"],
              "puffs": ["light", "standard"], "tide_scale": [0.5, 1.33], "swell_scale": [0.5, 1.5] }
}
```

| key | meaning | rules [default] |
| --- | --- | --- |
| `wind.speed` | `[min, max]` base wind speed at 10 m, m/s | `min ≤ max`, both in [2.06, 12.87] (the menu's 4 to 25 kn) [7.20, 7.20] |
| `wind.from` | typical direction the wind comes from, rad | [0, 2π) [0] |
| `wind.from_spread` | half-width of the direction draw, rad | [0, 0.349] (at most 20°, so the briefing's compass point stays true within a sector) [0] |
| `shift.preset` | a shift preset of `wind.md` §1 | `steady`, `stable`, `oscillating`, `shifty`, `unstable` [`shifty`] |
| `shift.amplitude`, `shift.hold_max`, `shift.hold_min` | explicit shift instead of the preset, rad and s | replace the preset's values when given; `hold_min ≤ hold_max` [preset; `hold_min = hold_max / 5`] |
| `shift.trend_rate`, `shift.trend_max` | steady rotation, rad/s (+ = veer, − = back) and its bound, rad | `trend_max` in [0, 0.35] [0, 0.35] |
| `oscillation` | `amplitude` (rad, [0, 0.087]) and `time_scale` (s, > 0) of `wind.md` §5 | absent = oscillation off |
| `puffs.preset` | a puff preset of `wind.md` §6.1, `none` = puffs off | [`standard`] |
| `puffs.<key>` | a `wind.md` §6.1 parameter overriding the preset: `puff_tile`, `puff_count`, `lull_count`, `puff_diameter_min`, `puff_diameter_max`, `puff_strength_min`, `puff_strength_max`, `lull_strength_min`, `lull_strength_max`, `puff_life_min`, `puff_life_max` (lifetimes in s here), `puff_cap_up`, `puff_cap_down` | checked as `wind.md` §6; counts whole, at most 64; any other key is a load error |
| `current` | uniform current, `speed` m/s (≥ 0) and `to` rad | [0, 0] |
| `tide` | tidal current on `current_field` (§6.3): `scale` (≥ 0), `period` (integer s, > 0), `turn` (`[a, b]`, fractions of the race, `0 ≤ a ≤ b ≤ 1`, `b − a ≤ 0.4`) and `turn_to` (`+1` or `−1`: the sign of the tide factor after the turn) | requires `current_field`; absent = no tide |
| `sea.scale` | `sea_scale` of `sea.md` §2 | ≥ 0 [1] |
| `sea.swells` | at most 4 swells `{hs (m), tp (s), from (rad)}` of `sea.md` §2 | [none] |
| `random` | the wider range of the Random weather mode (`race.md` §2.1): `speed` (`[min, max]`, m/s, within the menu's range), `from_spread` (rad, [0, 0.785]), `shift` and `puffs` (non-empty lists of preset names), `tide_scale` and `swell_scale` (`[min, max]` multipliers, ≥ 0) | each key missing: widened from the local values as below |

Random defaults, for each key of `random` not given: `speed` = the local range widened by 4 kn each way, clamped to
4 to 25 kn; `from_spread` = twice the local spread, at most 45°; `shift` = the local preset (or the preset whose
band in `menus.md` §1.3 holds an explicit amplitude) and its neighbours in the order `steady, stable, oscillating,
shifty, unstable`; `puffs` = the local preset and its neighbours in `none, light, standard, gusty`, without `none`
unless local is `none`; `tide_scale` = [0.5, 1.2]; `swell_scale` = [0.5, 1.5].

The sea's wind waves are not listed: they follow the drawn wind speed and the header's `fetch` (`sea.md` §2).

### 6.8 `briefing`
The venue's hand-written lines of the pre-race briefing (`menus.md` §1.3); everything else in the briefing is
computed from §6.7. The tag shows in the Local and Custom modes, the tip in Local only. Player-facing: no em dashes (validated: U+2014 is a load error).
```json
"briefing": {
  "tag": "Strong tide",
  "tip": "The stream runs hardest mid-channel; cheat it along the shore.",
  "translations": { "fr": { "name": "…", "tag": "…", "tip": "…" } }
}
```
`tag` at most 24 characters, `tip` at most 80 (counted in the English text; a translation may be up to 25 %
longer). `translations` maps a language code to any of `name`, `tag` and `tip`; a missing one falls back to the
English. The core ignores this block.

### 6.9 Old files
`conditions`, `briefing`, `ref_speed` and `source` are optional additions, so the schema stays `windmark.venue/1`
(§7). A venue without `conditions` offers only the Custom weather mode (`menus.md` §1), on the defaults of
`wind.md` §1 and `sea.md` §2 (the race layer refuses Local and Random there); its card shows the briefing computed from those settings without a Tip line. A venue with a
`current_field` but no `ref_speed` gives the Current line from the uniform current only. Shipped venues have both
blocks (venue test).

## 7. Versioning and consistency

- A change to a class file bumps its `version`; the VPP regenerates the performance file, which records
  `class_version` and `class_sha256`. CI checks that every shipped performance file matches its class file.
- The core loads only the performance and venue files. The race layer names the class and venue by id; the loader
  checks schema, validation rules and, online, the hashes announced by the server.
- Minor schema additions (new optional keys) keep the major version; anything that changes the meaning of an
  existing key bumps it.

## 8. Liveries (`windmark.liveries/2`) and livery textures

How the boats of a class look on the water. **Presentation only**: the core, the VPP and the boat generator never
read any of it, and it changes no model (the front end paints the generated boat at load, `game/README.md`
"Liveries"). Two parts:

- the **livery file** `data/liveries/<class>.liveries.json`, written by hand: the class livery (hull and deck
  colours, a hull graphic), the class sail set (cloth, colours, panel design, number colour), the class insignia and
  the boat identities (name, sail number, nation) the fleet draws from. It is the source data of the textures and
  of the procedural fallback;
- the **livery textures** in `data/liveries/<class>/`: PNG images baked once from the file by `tools/liverybake`
  and owned by hand from then on (§8.6), so they can be painted in any paint program.

What is shared and what differs per boat:

| what | where | shared by |
| --- | --- | --- |
| hull albedo, normal and ORM maps (topsides, graphic, boot stripe, antifouling, waterline, wear), the same three for the transom and for the deck (non-slip, margins, wear, sealant), keel albedo | `<class>/<livery id>/` (§8.5) | every boat wearing the livery: today the whole fleet |
| per sail: port and starboard albedo, normal and ORM maps (cloth, panels, seams, tapes, patches, battens, tell-tales, the class insignia) | `<class>/sails/` (§8.5) | every boat of the class |
| the boat name and sail number on the topsides, the boat name on the transom; the nation letters and sail number on the sails | drawn by the front end over the shared textures from the boat's identity (§8.4), one small text texture per boat | one boat |

The general rules of §1 hold; colours are `"#rrggbb"` sRGB strings. Top level:

| key | | meaning |
| --- | --- | --- |
| `schema` | **R** | `"windmark.liveries/2"` |
| `class` | **R** | the class id |
| `insignia` | **R** | the class insignia on the main: `{ "text": "W7" }` (1 to 4 capital letters and digits, drawn bold italic over a wave mark) |
| `sails` | | the class sail set by role (§8.3): every boat of the class carries the same sails |
| `ropes` | | the class rope set by function (§8.7): every boat of the class carries the same ropes |
| `liveries[]` | **R** | at least one livery (§8.1). Every boat wears the first, the class livery; further entries are kept for later (team liveries) and are not assigned yet |
| `boats[]` | **R** | at least 12 boat identities (§8.4) |

### 8.1 Livery

| key | | default | meaning |
| --- | --- | --- | --- |
| `id` | **R** | | `[a-z0-9_]`, unique in the file; names the texture folder |
| `name` | **R** | | the livery's name |
| `hull.topsides` | **R** | | topsides colour |
| `hull.boot_stripe` | | `#e0e0dc` | boot stripe |
| `hull.antifouling` | | `#1a1d24` | the bottom below the boot stripe |
| `hull.keel` | | `hull.antifouling` | keel fin and bulb, and a rudder painted in antifouling |
| `hull.text` | **R** | | name and number on the topsides |
| `hull.graphic` | | none | one hull graphic (below) |
| `deck.gelcoat` | | `#e2e2dc` | the smooth gelcoat: cabin, coamings, cockpit sides, margins and pads round the hardware |
| `deck.nonslip` | | `#a8a8a0` | the moulded non-slip areas |

The transom wears the hull's colours (`hull.topsides`, the graphic's return, `hull.boot_stripe` where the stripe's
height reaches it).

**Colours.** Every hull, deck and sail colour has each channel at most `#e7` (231, a linear albedo of 0.8), the
look rule of §3.7: a file with a brighter colour is a load error. White is `#e7e7e3` or below. The same cap holds
for the albedo textures (the game clamps them to it).

### 8.2 Hull graphic

`{ "type", "colors": [...], ... }` (where it crosses the name or number panels, its colours
should differ from `hull.text`), in topsides coordinates: `x` the fraction of the hull length
from the stern (0) to the bow (1), and the depth below the sheer either in metres or as the fraction `t` of the
topsides height at that `x` (0 at the sheer, 1 at the top of the boot stripe). The same graphic shows on both sides.

| type | keys (default) | picture |
| --- | --- | --- |
| `none` | | plain topsides |
| `stripes` | `depth` (`[0.08, 0.17]` m), `width` (`[0.05, 0.02]` m), `from` (0.04), `to` (0.96) | one or two stripes along the sheer at those depths below it, in `colors[0]`, `colors[1]`, ending at `from` and `to` with a cut that leans aft. With `from` 0 they run round the quarters onto the transom at the same depth below its top edge and end there with the same cut, half way from the corner to the cockpit opening (a third of the way to the centreline on a closed transom) |
| `two_tone` | `split` (0.45), `rise` (-0.15), `pinstripe` (0.025 m) | `colors[0]` below the line `t = split + rise · (x - 0.5)`, a pinstripe in `colors[1]` on it |
| `swoosh` | `aft` (`[0.04, 0.8]`), `fwd` (`[0.96, 0.1]`) as `[x, t]`, `width` (`[0.24, 0.03]` m at the aft and forward ends) | a band in `colors[0]` from `aft` to `fwd` at the height `t = t_aft + (t_fwd - t_aft) s^2.2` (`s` from 0 aft to 1 forward: low aft, rising ever steeper toward the bow), tapering, edged on its upper side by a line in `colors[1]` |
| `gradient` | `from` (0.25), `to` (0.85), `slant` (0.12) | the topsides blend from their colour aft to `colors[0]` forward between `x = from` and `to`, the blend line leaning aft by `slant` (of the hull length) from the boot stripe up to the sheer |
| `bow` | `at` (0.78), `slant` (0.10), `line` (0.03 m) | the bow forward of a line from `x = at` at the sheer to `at - slant` at the boot stripe in `colors[0]`, with a line in `colors[1]` along its edge |

### 8.3 Sails

The class sail set, `sails.main`, `sails.headsail` (every jib and genoa), `sails.code_zero`, `sails.spinnaker` (both
spinnaker types), each `{ "cloth", "color", "fibre", "number", "design", "colors": [...], ... }`, all optional:

| key | default | meaning |
| --- | --- | --- |
| `cloth` | the style of `sail_visuals.md` §11.1 for the sail type and LOA | `dacron` (woven polyester, cross-cut), `laminate` (tri-radial, with a scrim of load-path fibres), `nylon` (spinnaker cloth, ripstop) |
| `color` | `#e4e4de` | the cloth (the film of a laminate) |
| `fibre` | `#1e1f21` | the laminate's fibres or the nylon's ripstop threads |
| `number` | `#14213d` | sail number, nation letters and insignia |
| `design` | `plain` | panel colours, below, with `colors` |

| design | keys (default) | picture |
| --- | --- | --- |
| `plain` | | the cloth colour |
| `bands` | `stops` (`[0.35, 0.7]`) | horizontal bands by height above the foot (fraction of the sail height): `color` below `stops[0]`, `colors[0]` up to `stops[1]`, `colors[1]` above |
| `head` | `radius` (0.3), `corner` (0) | `colors[0]` within `radius` (fraction of the luff) of the head; `colors[1]` within `corner` of the tack and clew |
| `panels` | | the cloth panels alternate `color`, `colors[0]`, `colors[1]` (as many as given) |
| `diagonal` | `luff` (0.25), `leech` (0.75), `band` (0.25 m) | `colors[0]` above the line from the luff at height `luff` to the leech at height `leech`, a band of `colors[1]` along the line |
| `gores` | `count` (9) | gores radiating from the head, alternating `color`, `colors[0]`, `colors[1]` |

**Numbers and insignia** (racing rules Appendix G): see `sail_visuals.md` §11.2 for where they go. The insignia
is part of the baked main; the nation letters and the sail number are per boat. The topsides show the boat name aft
and the sail number forward (the livery panels of the generated hull), and the transom the boat name in its name
panel (`livery_transom` of the generated model, §8.5).

### 8.4 Boats and the fleet rule

The boat identities, the only thing that differs from boat to boat:

| key | | default | meaning |
| --- | --- | --- | --- |
| `id` | **R** | | `[a-z0-9_]`, unique in the file |
| `boat_name` | **R** | | the boat's name on the topsides aft: 1 to 20 characters of `A-Z a-z 0-9`, space, `'`, `-`, `.` |
| `sail_number` | **R** | | `"1"` to `"999"`, unique in the file; on the topsides forward and on the sails |
| `nation` | | none | 3 capital letters above the sail number on the sails |

**Fleet assignment.** Every boat of a race wears the class livery (`liveries[0]`) and the class sail set, and gets
one identity of its class, the same on every machine from the race seed:

1. Order the class's boats by `fnv1a32("<seed>:<id>")` (32-bit FNV-1a of the UTF-8 text, the seed in decimal),
   ascending, ties in file order. This is the seeded order.
2. Human entries in entry order take their chosen boat (the menu's Sail number row, else the first boat of the
   file); one already taken by an earlier entry gives the first free boat of the seeded order instead.
3. AI entries in entry order take the free boats in the seeded order. When none is left, the order starts again
   from its beginning as repeat 1, then 2, and so on: a repeat's boat name gets `" II"`, `" III"`, ... (repeat + 1
   in Roman numerals) and its sail number becomes `1000 · repeat + number`, so sail numbers stay unique in the fleet.

Offline the seed is the world seed (`GameSetup.seed`, `--seed`). Online the server sends the seed and each
player's choice, and every client runs the same rule.

### 8.5 Livery textures

8-bit RGB PNG images without alpha, in two folders per class. Albedo maps are sRGB; normal and ORM maps are linear
data. Normal maps are tangent-space in the image's own axes, OpenGL convention (red toward the image's right, green
toward its top); the game builds the tangent frame per pixel from the screen-space derivatives of the texture
coordinates, so no mesh needs tangents for them. ORM maps hold occlusion in red (1: none) and roughness in green;
blue is metallic on the hull and the share of sunlight let through the cloth on a sail (0: opaque). Each folder has
a `layout.json` with the mappings the game needs, written with the images.

**Hull folder** `data/liveries/<class>/<livery id>/`:

| file | size | content |
| --- | --- | --- |
| `hull_albedo.png` | 4096 × 2048 | the hull on the generator's uv1 atlas (`tools/boatgen/README.md` "Materials and UVs"): starboard band on top, port band below, the sheer at the top of each band, each side as seen from outside (bow to the right on starboard, to the left on port): topsides colour and graphic, boot stripe, antifouling, waterline and wear. The generator's name and number panels (`livery_panels`) stay clear: the game sets each boat's name and number there |
| `hull_normal.png` | 4096 × 2048 | relief on the same atlas: vinyl edges, tape edges, fairing waviness, roller texture, scratches |
| `hull_orm.png` | 4096 × 2048 | occlusion, roughness (polished gelcoat about 0.15, vinyl 0.25, antifouling 0.8), metallic 0 |
| `keel_albedo.png` | 1024 on the longer side | the keel fin and bulb seen from starboard, bow to the right (from port the same image shows mirrored) |
| `transom_albedo.png` | 2048 wide, square texels | the transom seen from astern on the generator's transom uv1 (port on the left, the transom's top at the top): topsides colour, the graphic's return, the boot stripe where it reaches, light wear (boarding scuffs at the cockpit opening and the quarters, fine scratches, a faint grime streak below the cockpit floor's edge where the cockpit drains, sealant round the rudder fittings). The name panel (`livery_transom.panel`) stays clear: the game sets each boat's name there |
| `transom_normal.png` | the same | relief: vinyl edges, fairing waviness, scratches |
| `transom_orm.png` | the same | occlusion, roughness (as the topsides), metallic 0 |
| `deck_albedo.png` | 4096 wide, square texels | the deck seen from above on the generator's deck uv1 (the plan view: bow to the right, port at the top): smooth gelcoat (`deck.gelcoat`) and moulded non-slip (`deck.nonslip`) areas with gelcoat margins along the sheer, the coamings, the cabin and the cockpit sole, smooth pads under the hardware; foot-traffic wear and dirt on the cockpit sole and toward the companionway, scuffs round the winches and clutches and along the line tails, sun-faded patches, sealant beads round every hardware base. Vertical faces (coaming and cabin sides) take the texels of their footprint, so the margins under them stay plain gelcoat |
| `deck_normal.png` | the same | relief: the moulded non-slip panels' raised edge, sealant beads, scuffs |
| `deck_orm.png` | the same | occlusion, roughness (gelcoat about 0.25, non-slip 0.8, worn sole smoother), and in blue the **non-slip mask** (255 moulded non-slip pattern, 0 smooth gelcoat; in between a worn pattern): the game lays the non-slip's tiling relief where it is set and the gelcoat's elsewhere, whatever the mesh's slots |
| `layout.json` | | `keel`: `rect` = `[forward_min, top, length, height]` of the image in the model frame of the GLB (forward = +Z, up = +Y and port = +X of `tools/boatgen/README.md` "Frames and units"; `top` is the up coordinate of the image's top edge); `deck` and `transom`: the same rectangle of their uv1 frame (for reference: the game reads uv1) and `size` |

**Transom and deck uv1** (written by the generator on every level of detail, `tools/boatgen/README.md` "Materials
and UVs"). The transom is its own material slot `transom` on the `deck` node; its uv1 is `u = (h − X) / 2h`, `v =
(top − Y) / (top − bottom)` over the transom's half width `h` and height (GLB root extras `livery_transom.rect` =
`[h, top, bottom]`). The other deck surfaces (slots `gelcoat`, `nonslip`, `glass`, `rubber` of the `deck` node) have
the plan view as uv1, `u = (Z − forward_min) / length`, `v = (port_top − X) / height` (extras `deck_plan` =
`[forward_min, port_top, length, height]`: the deck's extent with a 1 % margin). The transom's name panel
(`livery_transom.panel`: `uv1` rectangle and `size` in metres) is the band below the cockpit opening (an open
transom) or the middle of the transom (a closed one), clear of a transom-hung rudder's fittings: then the part of
the band to starboard of them (seen from astern, on the right).

**Sails folder** `data/liveries/<class>/sails/`, per class sail `<id>` (`sails[].id` of the class file):

| file | size | content |
| --- | --- | --- |
| `<id>_port_albedo.png` | 2048 on the longer side, square texels | the sail seen from port in its flat cloth plan: luff up the left edge, head at the top, as `sail_visuals.md` §11.2 lists |
| `<id>_stbd_albedo.png` | the same | seen from starboard (luff on the right): the same cloth, the starboard insignia and tell-tales |
| `<id>_normal.png` | the same | relief in the port view (seams, tapes, patches, battens, creases, wrinkles), for both sides |
| `<id>_orm.png` | the same | occlusion, roughness, light through the cloth, in the port view, for both sides |
| `<id>_relief.png` | the same, 8-bit greyscale | the height of the cloth in the port view, the source of `<id>_normal.png`: 128 flat, white raised, black sunk, ±4 mm over the range (`layout.json` `relief_m`); `tools/liverybake` makes the normal map from it whenever it exists (`sail_visuals.md` §11.2) |
| `layout.json` | | per sail: `cloth`, `relief_m` (the relief image's height at white, m), `shear` (`[cos θ, sin θ]` of `sail_visuals.md` §11.1), `rect` = `[x_min, y_max, width, height]` of the images in the flat plan (m), `size`, and `text`: the text frame (`axis`, `up`, `tack` in the plan) and per row (`insignia`, `nation`, `number`) the box of each side, `[centre along, centre up, half width, half height]` in metres from the tack, with the character height `h` |

The flat plan point of uv0 `(a, l)` is `p = (a·sin θ, l + a·cos θ)`; it maps to the port image at
`((p.x − x_min) / width, (y_max − p.y) / height)` and to the starboard image with the first coordinate mirrored.

The game imports the images compressed with mipmaps (albedo in the high-quality format, BPTC or ASTC; ORM in
S3TC or ETC2; normal maps as two-channel RGTC or the equivalent).

**Staged boat atlas** (written by `tools/liverybake` when it stages the textures for the game, generated, never
edited: the hand-owned images above stay the masters). The game draws every opaque surface of a boat with one
material (`sail_visuals.md` §11.4), so per livery the stage packs the hull, deck, transom and keel images into one
atlas per map, at 2048 × 2048 by default (`--hd`: 4096 × 4096, the masters' resolution):

| file | content |
| --- | --- |
| `atlas_albedo.png` | sRGB: the hull image (2:1) across the top half, the deck (its own aspect) below it, then the transom and the keel side by side; each region padded by its edge colour into a 16-texel gutter (8 at 2048 per 4096 of the master), so mipmaps do not bleed |
| `atlas_normal.png` | linear, the same layout; flat (`#8080ff`) in the keel region and the gutters |
| `atlas_orm.png` | linear, the same layout; the keel region R 255, G its roughness, B 0 |
| `atlas.json` | `schema` `"windmark.boatatlas/1"`, `size`, and per region (`hull`, `deck`, `transom`, `keel`) its rectangle `[u0, v0, width, height]` in atlas uv (0..1, v down); a region's own uv (the uv1 of §8.5, or the keel's side view) `t` maps to `rect.xy + t · rect.zw` |

The deck region is the deck images with the **painted fittings** over them: what is flat on the deck and the game
model does not stand up (`sail_visuals.md` §11.4; `tools/boatgen` `Boat.painted_part`: the jib and traveller
tracks, hatches, organisers, cam, horn and traveller cleats, the rudder bearing ring, and the lines lying on the
deck: halyards and their tails, the mainsheet tail and coil, the traveller lines (no halyard coils), only where they lie within 3.5 cm of the surface), drawn from
the generator's full-detail pieces seen from above: their colour by material (stainless, black plastic and rubber,
tinted lens, the rope set's halyard and control colours), their relief in the normal map from the pieces' own
normals, roughness by material, the non-slip mask cleared under them, and baked shading so they read solid without
geometry: a soft contact shadow round each fitting in occlusion and albedo, the lower parts of a fitting darker and
its upper edges lighter. The game reads only the atlas (and the per-boat text texture); the sails are staged at half
the master size (1024 on the longer side; `--hd` keeps 2048).

**Painted lines** are opaque in their own braid's mean colour, roughness and relief (a texel half covered by a line
is the line's), so a line reads the same over gelcoat and non-slip; they clear the non-slip mask and cast only a faint
contact shadow. Where a line runs down the coachroof's aft face (the halyard tails, down into the rope bags on the face) it is painted
on the face's own rectangle of the deck image: the aft face (slot `deck_face`) has its own uv1 into a corner of the
plan the deck does not use, forward of the bow on the port side (`tools/boatgen` `Deck.face_frame`), filled with
the deck's smooth gelcoat; there the face reads its map even though it is upright.

**Baked realism** (generated with the atlas, deterministic per class; subtle, a well-kept race boat): on the deck
region ambient occlusion and contact shadows from a 1 cm height field of everything on the deck (the walking surface,
the toe rail, coamings and hatch boxes, the hardware, the mast foot and the vang's foot; occluders over 0.4 m above
the surface do not count), at 1.5, 5 and 12 cm, into the occlusion and a little into the albedo: under and round
every fitting, along the coachroof's base and the toe rail, in the cockpit's corners; a faint warm grime where it is
occluded; wear on the non-slip in the traffic areas (round the winches, the mast foot and on the cockpit floor: the
pattern a little flatter, lighter and smoother in blotches); a faint low-frequency variation of the gelcoat's colour
(±1.5 %) and roughness (±6 %). On the hull and transom regions a very faint colour (±0.8 %) and roughness (±3 %)
variation, and on the transom faint dried streaks below the cockpit's drain.

**Boat material slots** (written by the generator in the GLB, `tools/boatgen/README.md` "Materials and UVs"): every
vertex of the material `boat` carries its slot in its vertex colour, green = slot id / 255 (red is the baked
ambient occlusion; blue on the merged `body` node the part it comes from / 255: 1 hull, 2 deck, 3 keel, 4 mast, 5
rigging, 6 hardware, GLB root extras `body_parts`). The material's extras list per slot its mean colour, roughness, metallic, tile of the shared
tiling atlas, tile size in metres of uv0 and **livery region**: `hull` (slots `hull_gelcoat`, `hull_boottop`,
`hull_antifouling`: the hull region on uv1), `deck` (`deck_gelcoat`, `deck_nonslip`: the deck region on the plan
uv1, with the non-slip mask; steep faces such as the coamings and the coachroof's sides and aft face take the slot's plain colour, not the map; also the hatches' raised boxes), `transom` (its uv1), `keel` (the keel in side view of the model frame, the layout's
`keel.rect`), `keel_colour` (the rudder blade: the livery's keel colour, no map), or none (spars and the helm in
dark clear-coated `carbon` with no weave pattern, stainless `metal`, black plastic and rubber `rubber`, the ropes by
function, glass, other gelcoat: the slot's own colour). Without a baked livery the regions take the livery file's colours
(§8.1) and the topsides its procedural hull livery.

### 8.6 Who owns the textures

The livery textures and their `layout.json` are **hand-owned assets, not generated tables**: the generator only
makes the starting images, and the files are then edited by hand and committed. `tools/liverybake` writes a part (the
hull's three images, the keel, the transom's three, the deck's three, a sail's five) only when none of its files
exists, so a new folder is baked whole and a part added later is baked once into an existing folder; `--force`
rewrites every part it is asked to bake and `--only <part>` (`hull`, `keel`, `transom`, `deck`, `sails` or a sail
id) rewrites just those files. A sail's normal map is made from its relief image when one exists (§8.5), so the
relief is the hand-owned file and the normal map follows it. No other tool writes there. A changed
class file does not rebake them: the hull follows uv1 and the sails keep their `rect` in metres, so after a hull or
sail plan change the owner decides whether to repaint or rebake (`--only`).

### 8.7 Ropes

The running rigging in braid colours by function, as on a race boat's rope set: each function its own clear colour
(dyed polyester braid, muted and a little sun-faded, never fluorescent) with a contrasting fleck, so the crew (and the player) tells the lines apart at a glance; every boat of the class
carries the same rope set. `ropes.<function>`, each `{ "color", "fleck", "pattern" }`, all optional:

| function | lines | default `color`, `fleck` |
| --- | --- | --- |
| `mainsheet` | the mainsheet tackle, its tail and coil | `#ae7249` orange, `#2d3548` navy fleck |
| `sheet` | jib and genoa sheets (drawn by the front end, `sail_visuals.md` §11.3) | `#3e797b` teal, `#d6d6ce` white fleck |
| `kite_sheet` | spinnaker and code zero sheets, guys and the tack line (front end) | `#91506f` raspberry, `#d6d6ce` white fleck |
| `halyard_main` | the main halyard (inboard of each bank) | `#9c4c4e` red, `#d6d6ce` white fleck |
| `halyard_jib` | the jib halyard | `#486792` blue, `#d6d6ce` white fleck |
| `halyard_kite` | the spinnaker halyard (and the kite's halyard on the posed previews) | `#497551` green, `#d6d6ce` white fleck |
| `halyard_code` | the code zero or spare halyard (a fourth halyard) | `#b79c5a` ochre yellow, `#2a2b2e` black fleck |
| `control` | traveller lines, the outhaul and the other control lines | `#6b5986` purple, `#d6d6ce` white fleck |

Lifelines and the standing rigging stay wire grey (the generator's `rope` and `metal` slots).

| key | default | meaning |
| --- | --- | --- |
| `color` | per function, above | the braid's main colour (each channel at most `#e7`, as §8.1) |
| `fleck` | per function, above | the colour of the fleck carriers |
| `pattern` | `fleck` | `fleck`: two carriers of the sixteen in the fleck colour, one per direction, so the fleck runs as a crossed spiral; `tracer`: one carrier, a single spiral; `twill`: alternate pairs of carriers in the two colours (a chevron braid); `solid`: the main colour only |

**Textures** in `data/liveries/<class>/rig/`, hand-owned like the others (§8.6; `tools/liverybake --only ropes`
rewrites them): one tile of a 16-carrier braid (8 carriers each way, 2 over 2 under, three yarns per carrier), 512 ×
512, covering 0.05 m along the rope (one lay length) and one turn around it. On the ropes uv0 is metres along and
the fraction around times 0.05 m (one tile per turn, seamless round the rope; `tools/boatgen/README.md` "Materials
and UVs").

| file | content |
| --- | --- |
| `rope_<function>_albedo.png` | the braid in the function's colours, sRGB, 8-bit RGB |
| `rope_normal.png` | the braid's relief (carriers, yarns, crossings), linear, OpenGL convention, shared by every function |
| `rope_orm.png` | occlusion (between carriers), roughness (about 0.8, polyester braid), metallic 0; linear, shared |

The game draws a rope slot with these when the class has them (the slot's own tiling texture otherwise, tinted to
`color`); a function without its albedo keeps the generator's look.

## 9. Rules scenarios (`windmark.scenario/1`)

A short set-up for a rules question: a few boats placed on the first beat of an offline race, sailing into an
incident. The front end starts it as `race.md` §14 says. Files live in `game/data/scenarios/<id>.scenario.json`,
written by hand. The general rules of §1 hold (ids, validation); a file that fails validation is refused with the
file, the JSON path and the reason, and nothing starts.

**Units.** Because the files are written by hand, this format is the one exception to the SI rule of §1: each angle
and speed below may be given either under its SI key or under a key that names a hand-friendly unit, and the reader
converts on load (`*_deg` degrees, `* π/180`; `*_kn` knots, `* 1852/3600` m/s). Giving both keys of one field is a
validation error (the JSON path of the unit key, "give one of ..."). Ranges are checked after conversion and quoted
in the unit of the key used. Only these keys have the alternative:

| SI key | hand key |
| --- | --- |
| `wind.speed` (m/s) | `wind.speed_kn` |
| `wind.from` (rad) | `wind.from_deg` |
| `boats[].at.bearing` (rad) | `boats[].at.bearing_deg` |
| `boats[].twa` (rad) | `boats[].twa_deg` |
| `boats[].speed` (m/s) | `boats[].speed_kn` |

Distances stay in metres (`at.dist`) and times in seconds. Every other data format keeps SI only.

### 9.1 Header

| key | | default | meaning |
| --- | --- | --- | --- |
| `schema` | **R** | | `"windmark.scenario/1"` |
| `id` | **R** | | the file name without `.scenario.json` |
| `name` | **R** | | the title, 1 to 60 characters |
| `note` | | `""` | free text for the author (the question and its answer); never shown in the race |
| `class` | **R** | | the class id of every boat (`data/classes/<id>.boat.json`) |
| `course` | **R** | | `"<venue>/<course id>"` (`game/data/courses/<venue>/<id>.course.json`); the world is on that venue |
| `seed` | | 1 | the world seed (`conventions.md` §7): AI skippers, sea, liveries by the fleet rule |
| `wind` | **R** | | `speed` or `speed_kn` **R** (m/s or knots, base speed at 10 m), `from` or `from_deg` **R** (rad or degrees compass, [0, 2π) or [0, 360)), `shifts` (a `wind.md` §1 preset: `steady`, `stable`, `oscillating`, `shifty`, `unstable`; default `steady`), `puffs` (default `false`) |
| `lead` | | 20 | s from clip time 0 (the set-up) to the incident: how far back each boat starts (§9.2) |
| `after` | | 5 | s the clip runs past the incident before the scene pauses |
| `view` | | 0 | the boat the cameras start on |
| `boats` | **R** | | 2 to 8 boats (§9.2); the first is boat 0, the player's boat |

### 9.2 Boats

| key | | default | meaning |
| --- | --- | --- | --- |
| `at` | **R** | | where the boat would be at the incident: a wind-frame offset `{"bearing", "dist", "from"}` as in `courses.md` §3.2 (`bearing_deg` in degrees in place of `bearing`), resolved on the race's course axis `TWD_c`; `from` is a mark id of the course, a derived `"<a>_<b>_mid"`, or omitted for the middle of the start line |
| `tack` | **R** | | `"starboard"` or `"port"` |
| `twa` or `twa_deg` | **R** | | true wind angle on that tack, rad 0 to π, or degrees 0 to 180 |
| `speed` or `speed_kn` | | polar | m/s or knots, ≥ 0; default the polar speed at `twa` in the base wind with her front sail |
| `front_sail` | | class start sail | a sail id of the class's front sails, or `"none"` |
| `auto_trim` | | `true` | the boat's auto trim |
| `helm` | | `"hold"` | `hold` (keeps her set-up heading, `race.md` §14), `ai` (the core's AI skipper), `player` (boat 0 only: the player's controls) |
| `ai_level` | | `intermediate` | `easy`, `intermediate`, `expert`, `pro` (`ai.md` §13), for `helm: ai` |
| `livery` | | fleet rule | a boat id of the class's livery file (§8.4); boats with one take it as human entries do, the rest by the fleet rule |

The set-up pose: heading `ψ = wrap_2pi(TWD_c − s · twa)` with `s = +1` on starboard and `−1` on port (the wind on
the starboard side is a positive TWA, `conventions.md`), and position `p = p_at − speed · lead · dir(ψ)`: the boat
starts `lead` seconds back along her heading, so boats given the same `at` meet there if they hold their course and
speed. Set-up positions must lie on the first beat, on the course side of the start line and short of the first
mark, so that the race sees the jump of `race.md` §14 step 4 as plain track.

Example (`game/data/scenarios/port_starboard.scenario.json`): the starboard boat and the port boat close-hauled,
meeting 300 m up the first beat 20 s after the set-up, written in degrees and knots.

```json
{
  "schema": "windmark.scenario/1",
  "id": "port_starboard",
  "name": "Port meets starboard",
  "class": "wm7",
  "course": "practice_waters/example_wl",
  "wind": { "speed_kn": 12, "from_deg": 0 },
  "lead": 20,
  "boats": [
    { "at": { "bearing_deg": 0, "dist": 300 }, "tack": "starboard", "twa_deg": 45 },
    { "at": { "bearing_deg": 0, "dist": 300 }, "tack": "port", "twa_deg": 45 }
  ]
}
```

