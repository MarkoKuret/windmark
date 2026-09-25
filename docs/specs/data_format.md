# Data formats: boat class, performance tables, venue physics

Three kinds of files feed the simulation core:

| file | schema | written by | read by |
| --- | --- | --- | --- |
| boat class `<class>.boat.json` | `windmark.boatclass/1` | designers (by hand or with tools) | boat generator (`tools/boatgen`), VPP (`tools/vpp`) |
| performance `<class>.perf.json` | `windmark.perf/1` | VPP tool, **generated, never hand-edited** | core, AI, HUD |
| venue physics `<venue>.venue.json` | `windmark.venue/1` | venue tools | core (wind field, current, sea exposure, land, obstacles) |

Courses and marks are defined in `courses.md` (`windmark.course/1`). The core never reads the class file directly: everything it needs is
in the performance file, which carries the hash of the class file it was made from.

## 1. General rules

- **JSON**, UTF-8, no comments. Top-level `"schema"` names the format and major version; a reader refuses a
  different major version. Unknown keys are ignored (forward compatibility) except inside tables.
- **SI units** everywhere: m, m², kg, s, rad, m/s, m/s², rad/s. No knots or degrees in files; tools display
  them. Field names carry no unit suffix; the unit is fixed by this spec.
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
| `luff`, `leech`, `foot` | | m | edge lengths [from the rig and the area] |
| `tack_x` | | m | body x of the tack [from the rig: mast for the main, forestay for jibs, sprit or pole] |
| `furling` | | bool | headsail on a furler (hoist animation, and faster handling) [false] |
| `handling` | | object | overrides of the handling block the VPP writes (§4.4) |

Sail areas of the main, jib, genoa, code zero and spinnakers (symmetric or asymmetric) are `sails[].area` with the
matching `type`.

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
| `visual` | boat generator | liveries, deck layout, hardware, and per sail `sails.<id>.look` (the front-end sail look of `sail_visuals.md` §4, copied into the physics sidecar with the defaults filled in); keys in `tools/boatgen/README.md`; opaque to the core and the VPP |

Top level: `"schema": "windmark.boatclass/1"`, `"id"`, `"name"`, `"version"` (integer, bumped on every change).

#### 3.7.1 `handling`

Optional. Tunes how a class **feels** without touching how fast it is: the VPP computes the physical tables and
then applies these multipliers when it writes the performance file. None of them changes a `polar`, `trim_speed`
or any other speed target, so a class's speeds (and the AI's and HUD's view of them) stay physical.

| field | | unit | default | range | scales in the performance file |
| --- | --- | --- | --- | --- | --- |
| `accel` | | – | 1.0 | 0.2 to 5 | every config's `accel` table (how fast the boat builds speed towards the polar) |
| `decel` | | – | 1.0 | 0.2 to 5 | `dynamics.decel_linear` and `decel_const` (how fast it slows above its target, coasting, in irons) |
| `turn_rate` | | – | 1.0 | 0.2 to 5 | yaw rate at every helm and speed: `dynamics.turn_radius_full` and `turn_radius_offset` are divided by it (`boat.md` §5.9); `rudder_drag_*` unchanged |
| `heel` | | – | 1.0 | 0.2 to 5 | every config's `heel` table (clamped to π/2) and `dynamics.heel_max` (kept below `heel_limit`); `heel_speed_factor` and the main's `sheet_max_by_heel` are stretched along their heel axes by the same factor, so the speed at the scaled heel is what it was at the physical heel |
| `tack_time` | | – | 1.0 | 0.2 to 5 | crew and helm speed in manoeuvres (> 1 is slower): `dynamics.helm_rate` and every sail's `rate_in`, `rate_out` and `pole_rate` are divided by it |

The multipliers used are recorded in the performance file's `handling` block (§4.1), all five, defaults included;
with every multiplier 1.0 the tables are exactly the physical ones.

Any other key of `handling` names a `dynamics` value (§4.2) and overrides it absolutely: the VPP writes it as
given, after the multipliers, unscaled. Unknown keys are reported and ignored.

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
| `decel_linear`, `decel_const` | float | boat.md §4 |
| `heel_speed_factor` | Table1D(`heel_abs`) | boat.md §4 |
| `rudder_drag_luff`, `rudder_drag_bear` | Table2D(`boat_speed_abs`, `helm_abs`), m/s² | boat.md §4 |
| `heel_max`, `heel_limit`, `heel_freq`, `heel_damping` | float | boat.md §4 |
| `pitch_freq`, `pitch_damping`, `wave_roll_gain`, `wave_pitch_gain` | float | boat.md §4 |
| `wobble_heel`, `wobble_pitch`, `wobble_freq` | float | boat.md §6.5 |
| `heave_time`, `waterline_offset`, `surf_gain` | float | boat.md §4 |
| `hull_points` | optional `[[x, y], …]` | sea.md §5.1 (default from `lwl`, `bwl`) |
| `lwl`, `bwl`, `loa` | float | copied from the class (hull points, AI, HUD) |
| `collision` | `{ "outline": [[x, y], …], "mass": kg, "yaw_gyration": m }` | collisions.md §2.1 |
| `wind_shadow` | object with every key of `wind_shadow.md` §2 | wind_shadow.md §2 |

Ranges checked at load (besides those of the owning specs): `decel_linear`, `decel_const` ≥ 0;
`rudder_drag_luff`, `rudder_drag_bear` any finite value (§5); `hull_points`, if present, at least one point.

`collision.mass` = `displacement + crew.weight`. The VPP derives the dynamics values from the design where it can
(turn radius from the rudder and hull length, heel spring from roll inertia and righting moment, shadow geometry
from the rig) and uses the reference values of the owning spec otherwise; then the class file's `handling`
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
  "trim_speed":   { table },       // Table3D(tws, awa_abs, trim_error) -> 1, optional
  "trim_heel":    { table },       // Table3D(tws, awa_abs, trim_error) -> 1, optional
  "weather_helm": { table },       // Table2D(tws, twa_abs) -> rad/s, optional
  "fall_off":     { table },       // Table2D(boat_speed, twa_abs) -> rad/s, optional
  "optimal_angle": { "main": { table }, "jib": { table } }   // Table2D(tws, awa_abs) -> rad
}
```
Semantics in `sails.md` §6. `front_sail` is `null` or the id of a front sail in `sails` (never the main); there
is exactly one main-only config and exactly one config per front sail.

**Coverage** (config tables only: `polar`, `heel`, `accel`, `trim_*`, `weather_helm`, `fall_off`,
`optimal_angle`; the `dynamics` and `sails` tables are not checked): every `tws` axis has its first point exactly
0 and its last point ≥ `20.6f` m/s (40 kn, rounded up); every `twa_abs` and `awa_abs` axis has its first point
exactly 0 and its last point exactly the binary32 π (`PI`, `conventions.md` §6). Other axes are not constrained.

`optimal_angle` is keyed by sail id and holds exactly the main and the config's front sail (only the main for
main-only). `weather_helm` values may be any finite number (signed); `fall_off` ≥ 0 (§5).

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

- `unit` of the values: one of `m/s`, `rad`, `m/s2`, `rad/s`, `s`, `1`; it must be the unit this spec gives for
  that table.
- Axes: 1 to 3, each with 1 to 256 points, non-decreasing, at most two equal points in a row (a step,
  `conventions.md` §8.1). The number of values is the product of the axis lengths.
- Every value finite. Range checks per table: `polar` in [−5, 40], `heel` in [0, π/2], `accel` ≥ 0, `fall_off` ≥ 0,
  durations ≥ 0, `trim_*` and `heel_speed_factor` in [0, 3], `optimal_angle`, `sheet_max_by_heel`, `pole_angle`,
  `shiver_angle` in [0, π], `rudder_drag_*` and `weather_helm` any finite value.
- Lookup and interpolation: `conventions.md` §8.

Recommended axes for the VPP (fine where the tables bend):
- `tws`: 0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 20.6 m/s;
- `twa_abs`: 0°, 7°, the no-go edge twice (the step, reference 15°), then 20° to 60° every 2°, 60° to 180° every
  5°;
- `trim_error`: −60°, −20°, −10°, −5°, −2°, −0.5°, 0, 0.5°, 2°, 5°, 10°, 20°, 60°, 120° (extended to the wind
  line at each `awa_abs`).

## 6. Venue physics file (`windmark.venue/1`)

The physical environment of a sailing area. Everything is optional except the header; an empty venue is open
water with uniform wind.

### 6.1 Header
Schematic (likewise §6.2–§6.5):
```json
{
  "schema": "windmark.venue/1", "id": "bay", "name": "…", "version": 1,
  "origin": { "lat": 45.5, "lon": 13.6 },       // geo-reference of world (0, 0), display only
  "bounds": [xmin, ymin, xmax, ymax],            // racing area, m; within ±8000
  "fetch": 12000,                                // m, for the wind-sea growth law (sea.md §2)
  "exposure_default": 1.0
}
```

### 6.2 `wind_field`
```json
"wind_field": {
  "grid": { "x0": -3000, "y0": -3000, "dx": 100, "dy": 100, "nx": 61, "ny": 61 },
  "sectors": [ { "f": [ … nx*ny … ], "d": [ … nx*ny … ] }, … 8 entries: from N, NE, E, SE, S, SW, W, NW … ]
}
```
`f` speed factor ≥ 0, `d` direction offset (rad, + = veer), nodes row by row (`j` major). Border nodes must be
`f = 1, d = 0` (validated). Sampling: `wind.md` §8.

### 6.3 `current_field`
```json
"current_field": { "grid": { … }, "vx": [ … ], "vy": [ … ] }     // m/s at tide factor 1, east/north
```
Zero outside the grid. Used as `tide(t) · field` (`wind.md` §7).

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
Validated: polygons simple (no self-intersections), land counter-clockwise, obstacle polygons convex. Collision
use: `collisions.md` §2.2.

## 7. Versioning and consistency

- A change to a class file bumps its `version`; the VPP regenerates the performance file, which records
  `class_version` and `class_sha256`. CI checks that every shipped performance file matches its class file.
- The core loads only the performance and venue files. The race layer names the class and venue by id; the loader
  checks schema, validation rules and, online, the hashes announced by the server.
- Minor schema additions (new optional keys) keep the major version; anything that changes the meaning of an
  existing key bumps it.
