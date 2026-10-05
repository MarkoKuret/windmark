# Course files

A course file says where the marks are, which lines start and finish the race, in which order and on which side the
marks are rounded, how many laps, and where boats may sail. It is Windmark's own format, schema
`windmark.course/1`, JSON, one course per file, under `game/data/courses/<venue>/<id>.course.json`. The general
data-file rules of `data_format.md` §1 apply: UTF-8 JSON without comments, a top-level `"schema"`, **SI units only**
(metres, seconds, radians, m/s; no knots or degrees; field names carry no unit suffix), numbers parsed to binary32,
lowercase ids `[a-z0-9_]`, unknown keys ignored, validation failures are load errors. The course tool
(`tools/course`) shows and edits angles in degrees and writes radians. The race layer that uses a course is
`race.md`; frames follow `conventions.md` (ENU world frame of the venue, compass angles clockwise from north).

A course can be laid in two ways:

- **fixed**: marks at world positions (a course around real islands, a harbour race);
- **wind-relative**: marks given relative to the wind and a reference point, laid when the race is created (what a
  race committee does every day, and what online quick races use so every race has a proper beat whatever the
  weather seed).

Snippets marked *schematic* use `…` for brevity; real files have none.

## 1. Top level

Schematic:
```json
{
  "schema": "windmark.course/1",
  "id": "bay_wl_2",
  "name": "Bay windward-leeward, 2 laps",
  "venue": "bay",
  "classes": ["sb7"],
  "frame": "wind",
  "reference": { "x": 1200.0, "y": -300.0 },
  "marks": [ … ],
  "start": { … },
  "finish": { … },
  "sequence": [ … ],
  "area": { … },
  "race": { … },
  "display": { … },
  "ai": { … }
}
```

| Key | Type | Required | Meaning |
| --- | --- | --- | --- |
| `schema` | string | yes | `"windmark.course/1"`. A reader rejects any other major version. |
| `id` | string | yes | Unique within the venue. |
| `name` | string | yes | Display name (English; translations in `display`). No em dashes (player-facing text). |
| `venue` | string | yes | Venue id (`data_format.md` §6): land, obstacles, wind field, current, exposure. |
| `classes` | string[] | no | Boat classes the course is designed for; empty = any. |
| `frame` | `"world"` / `"wind"` | yes | How mark positions are given (§3). |
| `reference` | point | wind frame | Origin of wind-relative positions, world coordinates (m). |
| `marks` | array | yes | Every course object (§2). |
| `start` / `finish` | object | yes | The start and finish lines (§4.2). |
| `sequence` | array | yes | The course: marks, gates and lap blocks between start and finish (§4.4). |
| `area` | object | no | Race area boundary, exclusion zones, spawn area (§5). |
| `race` | object | no | Race defaults the lobby may override (§5.2). |
| `display` | object | no | Translations and map hints (§8). |
| `ai` | object | no | Routing hints for the AI (§8). |

Points are `{"x": east, "y": north}` in metres in the venue's world frame, within the venue `bounds`
(`data_format.md` §6.1), or wind-relative offsets (§3.2).

## 2. Marks

Schematic:
```json
{ "id": "rc",  "type": "committee_boat", "at": { "x": 0, "y": 0 }, "heading": null },
{ "id": "pin", "type": "buoy", "style": "inflatable", "at": { "x": -250, "y": 0 } },
{ "id": "w",   "type": "buoy", "style": "large", "at": { "bearing": 0, "dist": 900 } }
```

| Key | Meaning |
| --- | --- |
| `id` | Unique within the file. Shown in the HUD when `display.labels` has no name for it. |
| `type` | `buoy`; `committee_boat`; `mark_boat` (a small boat used as a finish or gate end); `virtual` (a construction point only: no object, no collision, not drawn; used as the base of other positions or as a line end on a shore transit). |
| `style` | Buoys: `inflatable` (radius 0.8 m, default), `large` (radius 1.5 m), `tetra` (radius 0.8 m, the small pin-end shape). Visual preset plus collision radius. |
| `radius` | Overrides the style's radius (m). **Minimum 0.8 m**: `collisions.md` §3.5 relies on no shape being smaller than about 1.6 m across. |
| `at` | Position (§3). |
| `heading` | Committee and mark boats: bow heading (rad, compass). `null` = lie head to wind: the boat is placed with its bow to the course axis wind `TWD_c` (§6.1) at race creation and does not swing during the race. |
| `length`, `beam` | Committee/mark boat footprint (m; defaults 14 × 4.5 and 7 × 2.5). |
| `outline` | Committee/mark boats, optional: the body-frame outline as `[[x, y], …]` (m, x forward, y to port), 6–32 vertices, strictly convex, counter-clockwise, around the origin (the boat's position). Absent: the default outline. |

**Default committee and mark boat outline.** The generator construction of `collisions.md` §2.1 with `L = length`,
`B = beam`, transom width `0.8·B` and `s_m = 0.5`, tabulated once so that no power function runs in the core. With
the station table (body `x / L`, half-breadth `/ B`)

| i | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `X_i` | −0.5 | −0.35 | −0.2 | 0 | 0.1 | 0.25 | 0.37 | 0.45 |
| `F_i` | 0.4 | 0.451 | 0.484 | 0.5 | 0.4724054 | 0.3564127 | 0.2092049 | 0.0863752 |

the outline is `(X_i·L, −(F_i·B))` for i = 0…7 (starboard side, stern to bow), the stem `(0.5·L, 0)`, then
`(X_i·L, F_i·B)` for i = 7…0 (port side, bow to stern): 17 vertices, counter-clockwise, binary32 products. The
decimals above are the definition (they are the construction's values rounded to 7 digits).

**Collision objects** (`collisions.md` §2.2). Every mark except `virtual` becomes one static collision object,
numbered by its position in the `marks` array (the index is the `other` field of contact events):

| Mark type | `other_kind` | Shape |
| --- | --- | --- |
| `buoy` | `mark` | circle, `radius` |
| `committee_boat`, `mark_boat` | `course_object` | convex polygon with the heading: `outline` if the mark gives one, else the default outline below |

Whether an object is a mark for rule 31 (touching) depends on the boat's progress (`rules.md` §8), not on its
kind.

## 3. Positions

### 3.1 World frame (`"frame": "world"`)

Every `at` is `{"x", "y"}` in metres.

### 3.2 Wind frame (`"frame": "wind"`)

Every `at` is either a world point `{"x", "y"}` (for objects that do not depend on the wind, such as a harbour-mouth
finish) or an offset:

```json
{ "bearing": 0, "dist": 900, "from": "rc_pin_mid" }
```

- `bearing`: radians **relative to the wind axis**: 0 = straight upwind (towards where the wind comes from),
  π/2 = to the right when looking upwind, π = straight downwind, 3π/2 = to the left.
- `dist`: metres from the base point.
- `from`: the base: another mark id, a derived point, or omitted = `reference`.
- Derived points: `"<a>_<b>_mid"` for marks `a` and `b` = their midpoint (the name is reserved; no mark id may end
  in `_mid`).
- `fixed`: optional `true` = not scaled (§6.3).

Resolution at race creation, with `TWD_c` = the course axis (§6.1):

```
p = base + dist · dir(wrap_2pi(TWD_c + bearing))       // dir(ψ) = (sin ψ, cos ψ); wm_sin, wm_cos
```

Marks are resolved in file order; an offset may only reference marks resolved before it. The resolved world
positions are what the race, the rules, the collisions and the network use; they are never re-resolved during the
race, whatever the wind does.

## 4. Lines, gates and the sequence

### 4.1 Rounding sides

`"round": "port"` = the boat leaves the mark on her **port** side (she goes anticlockwise around it, seen from above).
`"round": "starboard"` = leaves it to starboard.

### 4.2 Start and finish lines

```json
"start":  { "ends": ["pin", "rc"] },
"finish": { "ends": ["rc", "fin"] }
```

- `ends`: two mark ids (any type, `virtual` allowed for a transit line). Order does not matter: the race orients each
  line itself (`race.md` §3.3, §6.1): the start line's course side is the side of the first step's reference point,
  the finish line's course side the side of the step before the finish.
- `"finish": "start"`: the finish is the start line (the validator checks the geometry, §7).
- `bias`: optional, start line only, radians: after resolution the line is rotated about its midpoint by this angle
  (positive = clockwise seen from above; the end that moves upwind becomes favoured). Wind-frame courses only.

### 4.3 Gates

```json
{ "gate": ["g1", "g2"] }
{ "gate": ["g1", "g2"], "round": ["port", "starboard"], "gate_mode": "round" }
```

- `gate`: two buoy ids.
- `round`: optional per-buoy sides. Default: with `P` the previous step's reference point and `m` the gate midpoint,
  the buoy on the left of `P → m` is rounded to **port** and the buoy on the right to **starboard**. A boat passing
  between the buoys has the left one on her port side, so she turns around it keeping it on her port side (or goes on
  past it); likewise the right buoy to starboard. This holds for U-turn gates and for gates the course passes
  straight through. The validator prints the computed sides.
- `gate_mode`: `"round"` (default: pass between, then round either buoy, `race.md` §5.2) or `"cross"` (passing
  between is enough; training courses only).

### 4.4 Sequence

Schematic:
```json
"sequence": [
  { "mark": "w",  "round": "port" },
  { "mark": "off", "round": "port" },
  { "repeat": 2, "steps": [
      { "gate": ["g1", "g2"] },
      { "mark": "w", "round": "port" }
  ]},
  { "gate": ["g1", "g2"] }
]
```

| Item | Meaning |
| --- | --- |
| `{"mark": id, "round": side}` | Round (or pass) one buoy or mark boat on the given side. |
| `{"gate": [id, id], …}` | A gate (§4.3). |
| `{"repeat": n, "steps": […]}` | The steps n times (n ≥ 1); blocks may nest one level. |
| `"lap"` | A marker: starts a new lap for the display count only. Without `"lap"` markers, each `repeat` iteration is a lap and steps outside repeat blocks belong to the first lap (before) or the last lap (after). |

The start line is implicitly step 0 and the finish line the last step; they are not listed in `sequence`.

**Expansion**: the race flattens the sequence into the step list of `race.md` §5: start, every item in order with
repeat blocks unrolled, finish. Each expanded step records `{kind, marks, sides, lap, leg_in_lap, source_index}`.
The same physical mark may appear in many steps; each step is its own rounding.

## 5. Area, spawn and race defaults

### 5.1 Area

Schematic:
```json
"area": {
  "boundary": [ { "x": …, "y": … }, … ],
  "exclusions": [ { "id": "shipping_lane", "polygon": [ … ] } ],
  "spawn": { "polygon": [ … ] }
}
```

- `boundary`: optional simple polygon (either orientation, ≥ 3 points; wind-frame points allowed). A boat whose
  reference point is outside it is **out of bounds**.
- `exclusions`: polygons boats must not enter (a shipping lane, a swimming area): a boat whose reference point is
  inside one is out of bounds too. They are not physical (no collision; land and physical obstacles come from the
  venue file, `data_format.md` §6.5), but the rules treat them as obstructions (`rules.md` §7.8).
- Out of bounds (`rules.md` §8, code `SI-boundary`): a HUD warning at once, a one-turn penalty after 15 s
  continuously out, disqualification after 60 s continuously out.
- `spawn`: optional polygon on the pre-start side in which the automatic grid of `race.md` §3.5 is laid (slots
  outside it are dropped).

### 5.2 Race defaults

```json
"race": {
  "type": "fleet",
  "sequence": "5-4-1-0",
  "prep_flag": "I",
  "time_limit": 1800,
  "target_duration": 720,
  "zone_lengths": 3
}
```

Defaults for the race settings of `race.md` §2 (the lobby may override). `time_limit` and `target_duration` in
seconds; `target_duration` is the expected winner's time used for scaling (§6.3) and for the default time limit.
`zone_lengths` is the mark zone radius in hull lengths, measured from the mark (`rules.md` §7.1; RRS default 3). It
applies to fleet races; a match race always uses 2 (Appendix C).

## 6. Laying a wind-relative course

### 6.1 Course axis

At race creation the server sets the course axis to the wind's **median direction** at the start signal, without
the random shift walk:

```
TWD_c = wrap_2pi(base_from + trend(t_env at the start signal))      // wind.md §1, §3
```

rounded to the nearest 0.01 rad: `TWD_c = wrap_2pi(round_half_even(v · 100) · 0.01)` in binary32. A committee lays the course to the median wind it expects; using the median (and
the deterministic trend) and not the shift walk means the course axis gives no hint of the shifts to come, which
every boat must read from the water.

### 6.2 Start line bias

A wind-frame course usually places the committee boat and the pin at bearings π/2 and 3π/2 from the reference, i.e.
square to the axis. `start.bias` (§4.2) rotates the line on purpose. The HUD computes the actual bias from the
live wind (`hud.md` §9).

### 6.3 Scaling to a target duration

If `race.target_duration` and a class are known, a wind-frame course may be scaled so the expected winning time is
close to the target:

```
T_est = Σ legs ℓ_j / V_j                           // expanded legs, axis lengths (race.md §8.1) with TWD = TWD_c
V_j   = polar VMG upwind (beats), polar VMG downwind (runs), polar speed at the leg's TWA (reaches) of the class's
        best sail at TWS = base_speed (wind.md §1)
k     = clamp(target_duration / T_est, 0.5, 2.0)
dist ← k · dist   for every offset not marked fixed
```

Then the marks are resolved again. `k` (as a binary32) is part of the resolved course, so clients reproduce the
same positions.

## 7. Validation

The loader rejects a file (error) or reports a warning:

| Check | Level |
| --- | --- |
| Schema: required keys, types, id syntax, unique ids, references resolve, no forward references in `from` | error |
| Radius below 0.8 m | error |
| `sequence` expands to at least one step | error |
| Two consecutive expanded steps (including start → first and last → finish) with reference points closer than 20 m | error |
| The first step's reference point is at least 100 m from the start line | error |
| The step before the finish is at least 50 m from the finish line | error |
| A gate's buoys are 3–20 hull lengths of the longest class apart (warning outside; error below 2 L) | warning / error |
| The start line is at least `max(8 L, 1.2 L × max boats)` long (L = longest class hull) | warning |
| Every mark, line end and the spawn polygon lie on water (venue land) with 2 L of clearance, inside the venue `bounds` | error |
| A straight segment between consecutive reference points crosses land | warning (fixed courses around islands do this on purpose; the AI then needs waypoints, §8) |
| The boundary polygon is simple and contains every mark with 3 L of margin | error |
| `"finish": "start"`: the step before the finish lies on the pre-start side of the start line (boats come back to the line from below it and finish crossing it in the same direction as they started) | error |

Wind-frame courses are validated after resolution for every axis direction in steps of π/18 (10°) at scale
`k = 1`: a course that becomes invalid in some wind is an error (such a course must be fixed-frame). The validator
runs in the course tool and when the server loads a course. Race creation checks the course it actually lays (its
`TWD_c` and `k`, §6) with the same rules and refuses to create the race if that fails, so a scale factor that
pushes a mark onto land or out of bounds is caught before any boat spawns. Warnings are reported once each, whatever
the number of axes that raise them.

## 8. Display and AI hints

Schematic:
```json
"display": {
  "names": { "fr": "Baie, 2 tours" },
  "labels": { "w": "Windward", "g1": "Gate left", "fin": "Finish" },
  "map_centre": { "x": 1200, "y": 200 },
  "map_extent": 2500
},
"ai": { "waypoints": { "3": [ { "x": …, "y": … } ] } }
```

- `display.labels` names marks in the HUD (`hud.md` §7). Player-facing: no em dashes.
- `ai.waypoints`: optional intermediate points per expanded step index for fixed courses around land; the AI routes
  through them when the straight line to the next mark crosses land (`ai.md` §4.6). No effect on the race logic.

## 9. Resolved course and hashing

For networking and replays the server builds the **resolved course**: the expanded steps, world positions of every
mark, committee-boat headings, line orientations, gate sides, the area polygons, the scale factor `k` and `TWD_c`,
all as binary32. It is serialised as canonical JSON (keys sorted, floats with 9 significant digits, no whitespace)
and hashed with SHA-256; the hash is part of the race parameters (`networking.md` §7) and of replay headers.
Clients never lay a course themselves; they receive the resolved course.

## 10. Example: two laps, gate, downwind finish

Two laps, a leeward gate after the first lap, a downwind finish beside the gate. The gate width, the offset-mark
distance and the line lengths are `fixed`; the leg length scales. (Angles in radians: π/2 = 1.57079633,
3π/2 = 4.71238898.)

```json
{
  "schema": "windmark.course/1",
  "id": "bay_wl_2",
  "name": "Bay windward-leeward, 2 laps",
  "venue": "bay",
  "frame": "wind",
  "reference": { "x": 1200.0, "y": -300.0 },
  "marks": [
    { "id": "rc",  "type": "committee_boat", "at": { "bearing": 1.57079633, "dist": 125, "fixed": true }, "heading": null },
    { "id": "pin", "type": "buoy", "style": "tetra", "at": { "bearing": 4.71238898, "dist": 125, "fixed": true } },
    { "id": "w",   "type": "buoy", "style": "large", "at": { "bearing": 0, "dist": 1000, "from": "rc_pin_mid" } },
    { "id": "off", "type": "buoy", "at": { "bearing": 4.71238898, "dist": 60, "from": "w", "fixed": true } },
    { "id": "gc",  "type": "virtual", "at": { "bearing": 0, "dist": 150, "from": "rc_pin_mid", "fixed": true } },
    { "id": "g1",  "type": "buoy", "at": { "bearing": 1.57079633, "dist": 40, "from": "gc", "fixed": true } },
    { "id": "g2",  "type": "buoy", "at": { "bearing": 4.71238898, "dist": 40, "from": "gc", "fixed": true } },
    { "id": "fc",  "type": "virtual", "at": { "bearing": 1.57079633, "dist": 180, "from": "gc", "fixed": true } },
    { "id": "fb",  "type": "mark_boat", "at": { "bearing": 1.57079633, "dist": 50, "from": "fc", "fixed": true }, "heading": null },
    { "id": "fp",  "type": "buoy", "style": "tetra", "at": { "bearing": 4.71238898, "dist": 50, "from": "fc", "fixed": true } }
  ],
  "start": { "ends": ["pin", "rc"] },
  "finish": { "ends": ["fp", "fb"] },
  "sequence": [
    { "mark": "w", "round": "port" },
    { "mark": "off", "round": "port" },
    { "gate": ["g1", "g2"] },
    "lap",
    { "mark": "w", "round": "port" },
    { "mark": "off", "round": "port" }
  ],
  "race": { "type": "fleet", "sequence": "3-2-1-0", "prep_flag": "I", "target_duration": 720 }
}
```

Checks: the first step (w) is 1000 m upwind of the start line; the finish line is square to the wind 150 m above the
start line and 130 m to the right of the gate, and the last step (off) is upwind of it, so boats finish running
downwind; the gate is 80 m wide (about 10 hull lengths of an 8 m class). Gate sides (§4.3): coming down from off,
g1 (on the right when looking upwind) is on the boat's left, so g1 is rounded to port and g2 to starboard.

The example files in `game/data/courses/` are the reference and are validated in CI. The shipped example is
`game/data/courses/example_bay/example_wl.course.json` (the course above with a 700 m beat, laid on the
`example_bay` venue); the core test suite loads it and validates it for every axis.
