# Course files

A course file says where the marks are, which lines start and finish the race, in which order and on which side the
marks are rounded, how many laps, and where boats may sail. It is Windmark's own format (`windmark-course/1`),
JSON, one course per file, under `game/data/courses/<venue>/<id>.json` (the data-file conventions of
`data_format.md` apply where they say more). The race layer that uses it is `race.md`; frames and units follow
`race.md` §0.

A course can be laid in two ways:

- **fixed**: marks at map positions (a course around real islands, a harbour race);
- **wind-relative**: marks given relative to the wind and a reference point, laid when the race is created from
  the race's wind (what a race committee does every day, and what online quick races use so every race is a
  proper beat whatever the weather seed).

## 1. Top level

```json
{
  "format": "windmark-course/1",
  "id": "bay-wl-2",
  "name": "Bay windward-leeward, 2 laps",
  "venue": "bay",
  "classes": ["wm30", "wm40"],
  "frame": "wind",
  "reference": { "x": 1200.0, "y": -300.0 },
  "wind_default": { "twd_deg": 225, "tws_kn": 12 },
  "marks": [ ... ],
  "start": { ... },
  "finish": { ... },
  "sequence": [ ... ],
  "area": { ... },
  "race": { ... },
  "display": { ... }
}
```

| Key | Type | Required | Meaning |
| --- | --- | --- | --- |
| `format` | string | yes | `"windmark-course/1"`. A reader rejects any other major version. |
| `id` | string | yes | `[a-z0-9-]+`, unique within the venue. |
| `name` | string | yes | Display name (English; translations in `display`). |
| `venue` | string | yes | Venue id: land, depth, local wind effects, scenery (`wind.md`, `sea.md`). |
| `classes` | string[] | no | Boat classes the course is designed for; empty = any. |
| `frame` | `"world"` / `"wind"` | yes | How mark positions are given (§3). |
| `reference` | point | wind frame | Origin of wind-relative positions, world coordinates (m). |
| `wind_default` | object | no | Default wind for offline races and previews; the weather model has the final word (`wind.md`). |
| `marks` | array | yes | Every physical course object (§2). |
| `start` / `finish` | object | yes | The start and finish lines (§4.2). |
| `sequence` | array | yes | The course: marks, gates and lap blocks between start and finish (§4.4). |
| `area` | object | no | Race area boundary, exclusion zones, spawn area (§5). |
| `race` | object | no | Race defaults the lobby may override (§5.2). |
| `display` | object | no | Translations and map hints (§8). |

Points are `{"x": east_m, "y": north_m}` in the venue's world frame (`race.md` §0), or wind-relative polar
coordinates (§3.2).

## 2. Marks

```json
{ "id": "RC",  "type": "committee_boat", "at": { "x": 0, "y": 0 }, "heading_deg": null },
{ "id": "PIN", "type": "buoy", "style": "pin",  "at": { "x": -250, "y": 0 } },
{ "id": "W",   "type": "buoy", "style": "tall", "at": { "bearing_deg": 0, "dist_m": 900 } },
{ "id": "L1",  "type": "buoy", "style": "tall", "at": { "bearing_deg": 180, "dist_m": 60, "from": "GATE-CENTRE" } }
```

| Key | Meaning |
| --- | --- |
| `id` | Unique within the file, `[A-Za-z0-9_-]+`. Shown in the HUD when `display.labels` has no name for it. |
| `type` | `buoy`, `committee_boat`, `mark_boat` (a small boat used as a finish or gate end), `virtual` (a point that exists only for the course geometry: no object, no collision; used for a line end on a shore transit or as a construction point). |
| `style` | Visual/physical preset of a buoy: `pin` (small, radius 0.6 m), `tall` (inflatable cylinder, radius 1.0 m), `sphere` (radius 0.8 m), `spar` (radius 0.3 m). Default `tall`. |
| `radius_m` | Overrides the style's collision radius. |
| `at` | Position (§3). |
| `heading_deg` | Committee and mark boats: bow heading. `null` = lie head to wind (the boat swings to the mean wind at race creation and stays; it does not swing during the race). |
| `length_m`, `beam_m` | Committee/mark boat footprint for collisions (defaults 14 m × 4.5 m and 7 m × 2.5 m). The footprint is a rectangle with a pointed bow (the rules hull rule of `race.md` §0 applied to this length and beam). |
| `anchored` | `true` (default): the object does not move in collisions; buoys bob and swing visually only (`collisions.md` owns the contact response). |

Collision shapes: a buoy is a vertical cylinder of `radius_m`; a committee or mark boat is its footprint polygon.
These shapes are used for mark touching (rule 31, `rules.md` §8) and for boat–object contacts (`collisions.md`).
`virtual` marks have no shape.

## 3. Positions

### 3.1 World frame (`"frame": "world"`)

Every `at` is `{"x", "y"}` in metres in the venue frame.

### 3.2 Wind frame (`"frame": "wind"`)

Every `at` is either a world point `{"x", "y"}` (allowed for objects that do not depend on the wind, such as a
harbour-mouth finish) or a polar offset:

```json
{ "bearing_deg": 0, "dist_m": 900, "from": "RC-PIN-MID" }
```

- `bearing_deg`: direction **relative to the wind axis**: 0 = straight upwind (towards where the wind comes from),
  90 = to the right when looking upwind, 180 = straight downwind, 270 = to the left.
- `dist_m`: distance from the base point.
- `from`: the base point: another mark id, a derived point (below) or omitted = `reference`.
- derived points: `"<A>-<B>-MID"` = the midpoint of marks A and B.

Resolution at race creation, with `TWD_c` = the **course axis** (§6.1):

```
p = base + dist_m · dir(TWD_c + bearing_deg)       # dir(ψ) = (sin ψ, cos ψ), compass angles
```

Marks are resolved in file order; a mark may only reference marks resolved before it, and a derived point only
marks resolved before it. The resolved world positions are what the race, the rules and the network use (the
server sends resolved positions to clients, `networking.md` §7); nobody re-resolves them later, even if the wind
shifts.

### 3.3 Scaling

`dist_m` values in a wind-frame file can be scaled as a whole (§6.3). A `"fixed": true` flag on an `at` excludes
that offset from scaling (used for gate widths and line lengths, which should stay the same in any wind).

## 4. Lines, gates and the sequence

### 4.1 Rounding sides

`"round": "port"` = the boat leaves the mark on her **port** side (she goes anticlockwise around it, seen from above).
`"round": "starboard"` = leaves it to starboard. There are no other values.

### 4.2 Start and finish lines

```json
"start":  { "ends": ["PIN", "RC"] },
"finish": { "ends": ["RC", "FIN"] }
```

- `ends`: two mark ids. The order in the file does not matter: the race orients each line itself (`race.md` §3.3
  and §6.1), with the start line's course side on the side of the first step's reference point and the finish
  line's course side on the side of the last step before it.
- `"finish": "start"`: the finish is the start line (common for short windward–leeward races finishing downwind
  through the start line; the validator checks the geometry, §7).
- `extra_length_m`: optional; if > 0, a `virtual` end is not allowed to be closer than this to the other end. Only
  used by the validator.

### 4.3 Gates

```json
{ "gate": ["L-LEFT", "L-RIGHT"] }
{ "gate": ["L-LEFT", "L-RIGHT"], "round": ["starboard", "port"], "gate_mode": "round" }
```

- `gate`: two buoy ids.
- `round`: optional per-buoy sides. Default: with `P` the previous step's reference point and `m` the gate
  midpoint, the buoy on the left of `P → m` is rounded to **port** and the buoy on the right to **starboard**.
  A boat passing between the buoys has the left one on her port side, so she can turn around it keeping it on her
  port side (or go on past it); the same holds for the right buoy to starboard. This is the rule for U-turn gates
  and for gates the course passes straight through. The validator prints the computed sides.
- `gate_mode`: `"round"` (default: pass between, then round either buoy, `race.md` §5.2) or `"cross"` (passing
  between is enough; training courses only).

### 4.4 Sequence

```json
"sequence": [
  { "mark": "W",  "round": "port" },
  { "mark": "OFFSET", "round": "port" },
  { "repeat": 2, "steps": [
      { "gate": ["L-LEFT", "L-RIGHT"] },
      { "mark": "W", "round": "port" }
  ]},
  { "gate": ["L-LEFT", "L-RIGHT"] }
]
```

Items:

| Item | Meaning |
| --- | --- |
| `{"mark": id, "round": side}` | Round (or pass) one buoy or mark boat on the given side. |
| `{"gate": [id, id], ...}` | A gate (§4.3). |
| `{"repeat": n, "steps": [...]}` | The steps n times (n ≥ 1); blocks may nest one level. |
| `"lap"` | A marker string: starts a new lap for the display count only. If a file has no `"lap"` markers, each `repeat` iteration is a lap and the steps outside repeat blocks belong to lap 1 (before) or the last lap (after). |

The start line is implicitly step 0 and the finish line the last step; they are not listed in `sequence`.

**Expansion**: the race flattens the sequence into the step list of `race.md` §5: start, every item in order with
repeat blocks unrolled, finish. Each expanded step records `{kind, marks, sides, lap, leg_in_lap, source_index}`.
The same physical mark may appear in many steps; each step is its own rounding.

## 5. Area, spawn and race defaults

### 5.1 Area

```json
"area": {
  "boundary": [ {"x":..,"y":..}, ... ],
  "boundary_rule": "penalty",
  "exclusions": [ { "name": "Shipping lane", "polygon": [ ... ] } ],
  "spawn": { "polygon": [ ... ] }
}
```

- `boundary`: optional simple polygon (clockwise or anticlockwise, ≥ 3 points, may use wind-frame points). Outside
  it is out of bounds.
- `boundary_rule`: what happens to a boat whose centroid is outside the boundary:
  - `"warn"`: HUD warning only;
  - `"penalty"` (default when a boundary exists): warning at once; after 15 s outside continuously a one-turn
    penalty (rule code `SI-boundary`, `rules.md` §9); after 60 s continuously outside the boat is disqualified;
  - `"wall"`: the boundary is an obstruction like land (`collisions.md`).
- `exclusions`: polygons that are obstructions for the rules (rule 19) and the collisions, like land. Land itself
  comes from the venue and is not repeated here.
- `spawn`: optional polygon on the pre-start side in which the automatic grid of `race.md` §3.5 is laid (slots
  outside it are dropped). Without it the grid is laid as in `race.md`.

### 5.2 Race defaults

```json
"race": {
  "type": "fleet",
  "sequence": "5-4-1-0",
  "prep_flag": "I",
  "time_limit_s": 1800,
  "target_duration_s": 720,
  "zone_lengths": 3
}
```

Every key is a default for the race settings of `race.md` §2 (the lobby may override). `target_duration_s` is the
expected winner's time used for scaling (§6.3) and the default time limit. `zone_lengths` is the mark zone radius
in hull lengths (`rules.md` §7.1; RRS default 3).

## 6. Laying a wind-relative course

### 6.1 Course axis

At race creation the server takes the weather model's **mean wind direction over the first 10 minutes after the
start signal** (`wind.md` exposes this deterministically from the seed and settings; if it does not, the mean
direction at the start signal) and rounds it to the nearest 1°: that is `TWD_c`. Real committees set the axis to
the median wind; using the forecast mean keeps the first beat square on average without giving anyone hindsight
during the race (every boat sees the same shifts).

### 6.2 Start line bias

A wind-frame course usually places the committee boat and the pin at bearings 90° and 270° from the reference, i.e.
square to the wind axis. `start.bias_deg` (optional) rotates the whole start line about its midpoint by that angle
after resolution (positive = clockwise seen from above; the end that moves upwind becomes favoured), so a course
can deliberately favour one end. The HUD computes the actual bias from the live wind (`hud.md` §9).

### 6.3 Scaling to a target duration

If `race.target_duration_s` and a class are known, a wind-frame course may be scaled so the expected winning time is
close to the target:

```
T_est = Σ legs ℓ_j / V_j                                            # expanded legs, axis lengths (race.md §8.1)
V_j   = polar VMG upwind (beats), polar VMG downwind (runs), polar speed at the leg's TWA (reaches),
        of the class at the course wind speed TWS_c (the mean speed like §6.1)
k     = clamp(target_duration_s / T_est, 0.5, 2.0)
dist_m ← k · dist_m   for every offset not marked "fixed"
```

Then the marks are resolved again. The scale factor is part of the race parameters so clients reproduce the same
positions. The limits keep a course recognisable; a lobby may disable scaling.

## 7. Validation

The loader rejects a file (error) or reports a warning:

| Check | Level |
| --- | --- |
| JSON schema: required keys, types, id syntax, unique ids, mark references resolve, no forward references in `from` | error |
| `sequence` expands to at least one step | error |
| Two consecutive expanded steps (including start → first and last → finish) with reference points closer than 20 m | error |
| The first step's reference point is at least 100 m from the start line (on its course side by construction) | error |
| The step before the finish lies strictly on one side of the finish line, at least 50 m from it | error |
| A gate's buoys are 3–20 hull lengths of the longest class apart (warning outside; error below 2 L) | warning / error |
| The start line is at least `max(8 L, 1.2 L × max boats)` long (L = longest class hull) | warning |
| Every mark, line end and the spawn polygon lie on water (venue land mask) with 2 L of clearance | error |
| The course crosses land: a straight segment between consecutive reference points crosses land | warning (fixed courses around islands may do this on purpose; the AI then needs waypoints, §8) |
| Boundary polygon is simple and contains every mark with 3 L of margin | error |
| `"finish": "start"`: the last step before the finish is on the pre-start side of the start line (so boats finish in the opposite direction to the start) | error |

The validator runs in the tools (`tools/course-check`) and when the server loads a course; wind-frame courses are
validated after resolution for every wind direction in 10° steps (a course that becomes invalid in some wind is an
error: such a course must be fixed-frame).

## 8. Display and AI hints

```json
"display": {
  "names": { "fr": "Baie, 2 tours" },
  "labels": { "W": "Windward", "L-LEFT": "Gate L", "FIN": "Finish" },
  "map_centre": { "x": 1200, "y": 200 },
  "map_zoom_m": 2500
},
"ai": { "waypoints": { "3": [ {"x": ..., "y": ...} ] } }
```

- `display.labels` names marks in the HUD (`hud.md` §7).
- `ai.waypoints`: for fixed courses around land, optional intermediate points per expanded step index that the AI
  routes through when the straight line to the next mark crosses land (`ai.md` §4.6). They have no effect on the
  race logic.

## 9. Canonical form and hashing

For networking and replays the server builds the **resolved course**: expanded steps with world positions of every
mark, line orientations, gate sides, the area polygons, the scale factor and `TWD_c`. It is serialised as
canonical JSON (keys sorted, numbers printed with up to 3 decimals in metres / 0.01° in degrees, no whitespace) and
hashed with SHA-256; the hash is part of the race parameters (`networking.md` §7) and of replay headers.
Clients never lay a course themselves; they receive the resolved course.

## 10. Example: a two-lap windward–leeward with a gate

Two laps, leeward gate after the first lap, downwind finish beside the gate. Positions in metres relative to the
wind axis; the gate width, the offset-mark distance and the line lengths are `fixed`, the leg length scales.

```json
{
  "format": "windmark-course/1",
  "id": "bay-wl-2",
  "name": "Bay windward-leeward, 2 laps",
  "venue": "bay",
  "frame": "wind",
  "reference": { "x": 1200.0, "y": -300.0 },
  "marks": [
    { "id": "RC",  "type": "committee_boat", "at": { "bearing_deg": 90,  "dist_m": 125, "fixed": true } },
    { "id": "PIN", "type": "buoy", "style": "pin", "at": { "bearing_deg": 270, "dist_m": 125, "fixed": true } },
    { "id": "W",   "type": "buoy", "at": { "bearing_deg": 0, "dist_m": 1000, "from": "RC-PIN-MID" } },
    { "id": "OFF", "type": "buoy", "style": "sphere", "at": { "bearing_deg": 270, "dist_m": 60, "from": "W", "fixed": true } },
    { "id": "GC",  "type": "virtual", "at": { "bearing_deg": 0, "dist_m": 150, "from": "RC-PIN-MID", "fixed": true } },
    { "id": "G1",  "type": "buoy", "at": { "bearing_deg": 90,  "dist_m": 40, "from": "GC", "fixed": true } },
    { "id": "G2",  "type": "buoy", "at": { "bearing_deg": 270, "dist_m": 40, "from": "GC", "fixed": true } },
    { "id": "FC",  "type": "virtual", "at": { "bearing_deg": 90, "dist_m": 180, "from": "GC", "fixed": true } },
    { "id": "FB",  "type": "mark_boat", "at": { "bearing_deg": 90,  "dist_m": 50, "from": "FC", "fixed": true } },
    { "id": "FP",  "type": "buoy", "style": "pin", "at": { "bearing_deg": 270, "dist_m": 50, "from": "FC", "fixed": true } }
  ],
  "start": { "ends": ["PIN", "RC"] },
  "finish": { "ends": ["FP", "FB"] },
  "sequence": [
    { "mark": "W", "round": "port" },
    { "mark": "OFF", "round": "port" },
    { "gate": ["G1", "G2"] },
    "lap",
    { "mark": "W", "round": "port" },
    { "mark": "OFF", "round": "port" }
  ],
  "race": { "type": "fleet", "sequence": "3-2-1-0", "prep_flag": "I", "target_duration_s": 720 }
}
```

Checks: the first step (W) is 1000 m upwind of the start line; the finish line is square to the wind 150 m above the
start line and 130 m to the right of the gate, and the last step (OFF) is upwind of it, so boats finish running
downwind; the gate is 80 m wide (about 8 hull lengths of a 10 m class). The gate sides come out of §4.3: coming down
from OFF, G1 (on the right when looking upwind) is on the boat's left, so G1 is rounded to port and G2 to starboard:
a boat passes between them and turns back up around either one, keeping it on the inside of her turn. (This
example has no second pass through the gate: the second lap ends with the downwind finish.)

The example files in `game/data/courses/` are the reference and are validated in CI.
