# Windmark VPP

Velocity prediction program: turns a boat-class file (`windmark.boatclass/1`, `docs/specs/data_format.md` §3)
into the performance file the simulation core loads (`windmark.perf/1`, §4): speed, heel, acceleration, trim and
optimal sail angle tables per sail configuration, plus the `dynamics` and per-sail blocks. The core is table
driven (`docs/specs/boat.md`, `sails.md`); this tool is where the physics lives.

It is a classic, simple VPP: sail force coefficients against the apparent wind, a published hull resistance
regression, induced drag from the keel and rudder, heel from the righting moment of the lofted hull, and a
surge/roll force and moment equilibrium solved for speed and heel with the depowering optimised. It runs in
15 to 60 s per class on a laptop, fully vectorised in NumPy.

## Running

```
cd tools/vpp
uv venv .venv && uv pip install --python .venv/bin/python -e ".[test]"     # or: pip install -e ".[test]"
.venv/bin/python -m windmark_vpp ../../data/classes/wm7.boat.json -o wm7.perf.json --plots plots/
.venv/bin/python -m pytest
```

Options: `-o FILE` (one class) or `-o DIR` (several classes, `<id>.perf.json` each); `--plots DIR` writes four
PNGs per class; `--physics FILE_OR_DIR` copies the boat generator's `perf_inputs` (collision outline, hull
points, wind-shadow geometry) from `<id>.physics.json`; `--thin-ship` uses the thin-ship wave resistance for a
monohull too (for comparison). Every run validates its output against the table rules of `data_format.md` §5
and prints the assumptions it made.

Dependencies: Python 3.9+, NumPy, SciPy, Matplotlib (plots), pytest (tests).

## Files

| Path | Role |
| --- | --- |
| `windmark_vpp/boatclass.py` | class-file reader: fields, defaults, validation, derived masses and heights |
| `windmark_vpp/geometry.py` | lofted canoe bodies and large-angle hydrostatics (righting moment at any heel) |
| `windmark_vpp/hydro.py` | hull, appendage, heel and induced resistance; thin-ship wave resistance |
| `windmark_vpp/sails.py` | sail coefficients against angle of attack, best-trim envelopes |
| `windmark_vpp/solver.py` | rig forces, apparent wind, the vectorised speed/heel equilibrium |
| `windmark_vpp/perf.py` | performance-file generation, `dynamics` block, validation |
| `windmark_vpp/plots.py` | polar, per-config, sail crossover, heel and trim plots |
| `boats/*.boat.json` | example classes (original designs): `dart7` sportsboat, `coastal40` offshore racer, `cup22` grand-prix monohull, `tri18` ocean trimaran |
| `../../data/perf/` | generated performance files and plots of the game classes in `data/classes` (built with the boat generator's physics sidecar) |
| `tests/` | unit and integration tests |

## Input: class file

All fields of `data_format.md` §3 are read as specified there. How the VPP uses some of them:

- `hull.displacement` + `crew.weight` is the sailing mass; the canoe body displaces it less the volume of the
  fin, bulb and rudder. `section_shape.midship_coefficient` is a hint: the canoe body is lofted to hit the
  displaced volume and `prismatic` exactly, and Cm follows (a note is printed when the hint differs).
- `lcb_x` (default 53.5 % of LWL aft of the forward end), `boom_height` (default
  `mast_height − P − 0.25 (loa/12)^0.6`) and the mast section size (`0.0105 mast_height + 0.02`) are the same
  defaults the boat generator uses.
- `hull_mass_z` (VCG) and `rig.rig_mass` are estimated when absent: bulb and fin at their depths, rig at 0.45
  of the mast height, the rest of the boat at a quarter of the freeboard.
- `crew.hiking_arm` [0.45 `beam_max`]: the crew hikes as the heel asks, from a quarter of the arm upright to the
  full arm at 14° heel, so a light-air boat still heels a little.
- `handling` (`data_format.md` §3.7.1): the five feel multipliers (`accel`, `decel`, `turn_rate`, `heel`,
  `tack_time`, default 1.0) are applied to the physical tables as the file is written (`perf.apply_handling`) and
  recorded in the performance file's `handling` block; they never change a speed table. Any other key overrides
  that `dynamics` value as given. `sails[].handling` overrides the sail's handling block.
- `sails[main].kite_sheet_in` [0]: the kite configs' main `optimal_angle` is the main's own best angle less this
  (never below `sheet_min`): with a spinnaker or code zero set the main is sailed well inside the shrouds
  (`sails.md` §5.1). The equilibrium itself keeps the main at its own best angle, so the polars do not change;
  with a front sail up only its trim drives the core's speed. wm7 and wm12 use 0.26 rad (15°).
- Multihulls (`hull.type`, `hull.floats`, `hull.hull_spacing`, `boards`, `rudder.count`) and the `vpp` block
  (`max_heel`) are specified in `data_format.md` §3.9 and §3.10, with their units and defaults. The float
  bodies are extra polygons of the same hydrostatics; the boards are read like a keel fin without a bulb.

## Output: performance file

`windmark.perf/1` exactly as `data_format.md` §4 and §5 define it: header with the class hash and the
`handling` multipliers used, `dynamics`, `sails`, one entry per config (main alone, main + each front sail) with
`polar`, `heel`, `accel`, `accel_rest`, `trim_speed`, `trim_heel`, `weather_helm`, `fall_off`, `flog_drag`,
`drift`, `drift_flog` (and `leeway` with `full_leeway` on), `optimal_angle`, and `start`. Axes follow the spec's recommendation: TWS 0 to 20.6 m/s (40 kn), TWA 0°, 7°, the
no-go edge twice, then 2° steps to 60° and 5° steps to 180°; AWA every 5°; trim error −60° to +2° fine, then
every 5° to 130°, 150° and 180°; apparent wind speed 0 to 40 m/s (fine below 10 m/s).

What each table holds:

- `polar`: equilibrium speed at the best depowering and trim. Below the no-go edge (1.5° below the first TWA
  where the config makes way at 8 kn or more) the steady sternway the windage drives, capped at 0.15 TWS, with
  the spec's step to +0.1 m/s at the edge. Above the edge the polar is never 0: see "Broached speed".
- `heel`: equilibrium heel. `accel`: the constant acceleration that reproduces the time to build speed from 50 %
  to 90 % of the polar (the speeds a boat rebuilds through after a tack or a gybe; the tack test measures 90 %),
  integrating (drive − resistance)/(mass + added mass) with the heel in equilibrium at each speed (8-point
  Gauss-Legendre); floor 0.005 m/s².
- `accel_rest`: the acceleration from rest: the drive of the trimmed sail plan in the true wind (with the heel it
  raises) over mass plus added mass; the hull has no resistance ahead at rest (the keel's side force is taken by
  the boat sliding to leeward until it has way on). The core blends from it to `accel` below half the target
  speed. Same no-go, broached and floor rules as `accel`.
- `trim_speed`: equilibrium speed with every sail of the config sheeted `eps` away from its optimum (the single
  manual sheet of `sails.md` §5.2), clamped to the sheet limits and the wind line, relative to the trimmed speed;
  `trim_heel`: the roll equilibrium of the same mistrimmed sails at the trimmed boat's speed and apparent wind,
  relative to the trimmed heel there (the core looks it up at the boat's own apparent wind, so an over-sheeted
  boat heels by what its stalled sails push at the speed it makes; sails sheeted in past the stall keep their stall
  normal force, `solver.over_sheeted`); both resampled from TWA onto AWA per TWS row. With the driving sail (the front sail,
  else the main) on the wind line the flogging sails give no drive: from the `eps` point at or below the smallest
  wind-line error `AWA − m_opt` of the neighbouring (TWS, AWA) points `trim_heel` is 0 and `trim_speed` holds the
  let-fly share (see "Luffing and let-fly"), which is exactly 0 up to 90° AWA, so the core's interpolated lookup
  at the wind line is 0 there.
- `weather_helm`: the helm balance, from the yaw moment of the sail plan (see "Helm balance").
- `flog_drag`: the brake of the sails flogging on free sheets (see "Luffing and let-fly").
- `fall_off`: turning away from the wind with no way on (`boat.md` §7.4), the same for every config: the
  reference rate of the owning spec by waterline length (S 8°/s, L 5°/s) from 20° to 60° TWA, fading out by
  90° (a stopped boat lies beam on), none below 10° (a boat right head to wind stays in irons); full in sternway
  and at rest, fading as `1 − (v/v_f)²` to 0 at `v_f = 0.05 sqrt(g LWL)` ahead (Froude number 0.05: the keel
  holds the heading; light-air sailing speeds are above it).
- `drift`, `drift_flog`: the sideways drift of the boat at rest (see "Sideways drift").
- `optimal_angle`: best sheet angle of each sail against AWA (resampled the same way).

### Luffing and let-fly

A sail on the wind line with its sheet in (a tack, a luff head to wind, in irons) lies in the wind and shivers:
drag coefficient `CD_luff` 0.06 on its area, part of the windage `decel_windage` and the sternway drift use. Let fly
(or eased on a free sheet) it flogs: the cloth, the clew and the sheets whip in the wind like a heavy flag, with a
drag an order of magnitude above a taut cloth's (flag drag grows with the cloth's weight and the flutter; Hoerner
1965, flags). Windmark takes `CD_flog` 0.30 on the sail area, an estimate at the heavy end of flag drag, not a
measurement. Two tables carry it:

- `flog_drag` (per config): the extra drag of the config's sails flogging over luffing, along the heading, per
  apparent wind speed and angle, `0.5 ρ aws² (CD_flog − CD_luff) A_sails cos(awa) / (m + m_a)`, 0 from 90° AWA.
  The core's apparent wind is at the 10 m reference height, so the wind profile factor at the centre of effort is
  applied. The core brakes with it in proportion to the drive the trim has lost, only with free sheets.
- the let-fly share of `trim_speed`: abaft the beam the windage of hull and rig and the flogging sails push the
  boat along. The steady let-fly speed is where that push equals the upright hull's resistance (a bisection,
  `Solver.let_fly_speed`), 0 where the apparent wind is forward of the beam; the share is that speed over the
  polar, resampled per TWS row with the apparent wind angle at the let-fly speed as the abscissa (so the core,
  looking up at its own apparent wind, finds the let-fly speed when it sails at it). Let fly holds every sail at
  its fully eased angle (`sails.md` §5.3), so only a sail whose `sheet_max` lies abaft the beam can reach the
  wind line there; the shipped sails (at most 74°) never do, and running they take the regular trim value of the
  fully eased sail instead.

Results at 10 kn close-hauled, let fly (the drive gone in the first tick): wm7 under 1 kn in 7.9 s (14.7 s with
the hull alone), wm12 in 15.3 s (29.7 s): the heavier boat has about half the sail area per tonne and carries its
way twice as long. Running in 10 kn (150° TWA), let fly costs nothing: the fully eased sheet is the optimum there.

### Sideways drift

A boat with no way on is pushed sideways by its windage until the cross-flow drag of its underwater body balances
the push (`boat.md` §6.4). The VPP writes that steady drift per config on (TWS, TWA every 5°), for the boat at rest:

- the push: the cross-wind component of `Rig.windage_force` (hull topsides, mast, and the config's sails on the
  wind line: `CD_luff` for `drift`, `CD_flog` for `drift_flog`) at the apparent wind the drifting boat feels (the
  true wind at the rig's centre of effort less the drift), so it is 0 head to wind and dead downwind;
- the drag: `c·drift²` with `c = ½ ρ (1.2 (A_keel + A_rudder) + 0.7 (0.7 LWL Tc + A_bulb))`: the fins as plates
  normal to the flow, the canoe body (its lateral profile taken as 0.7 LWL × Tc) and the bulb as blunt bodies
  (Hoerner 1965, cross-flow drag); a catamaran counts two canoe bodies;
- the balance by bisection.

Two `dynamics` values go with it: `drift_grip = 4c/k`, with `k = ½ ρ (A_keel + A_rudder) · 2π AR/(AR + 2)` the lift
slope of keel and rudder against leeway (the same lift line as the leeway diagnostic, upright), so the grip speed
`drift_grip · drift` is where the keel's lift slope `k·v` reaches twice the cross-flow drag's `2c·drift`; and
`drift_length = m_sway / c`, the sway mass (boat plus the added mass of the fins, `ρ π c²/4` per metre of span,
and of the canoe body, `ρ π Tc²/2` per metre over 0.7 LWL) over `c`, which sets how fast the drift builds.
`full_leeway` is written false; a class file can set it in `handling` (`data_format.md` §3.7.1), and then every
config also gets a `leeway` table (the leeway diagnostic on the polar's axes, 0 in the no-go zone). No `handling`
multiplier touches the drift.

| class | `drift_grip` | `drift_length` | drift beam on, jib config, luffing (flogging), kn, at 6 / 10 / 16 / 22 kn TWS |
| --- | --- | --- | --- |
| wm7 | 1.87 | 1.74 m | 0.35 / 0.58 / 0.93 / 1.28 (0.48 / 0.81 / 1.29 / 1.78) |
| wm12 | 1.95 | 2.98 m | 0.37 / 0.61 / 0.98 / 1.34 (0.51 / 0.85 / 1.36 / 1.87) |

### Helm balance

`weather_helm` is the yaw moment of the sail plan about the centre of lateral resistance (CLR), as a turn rate:

- moment `N = F_x (z_ce sin φ + y_ce) − F_h (x_ce − x_clr)`: the drive `F_x` at the centre of effort, carried out
  to leeward by the heel (`z_ce sin φ`) and by the sheet angles (`y_ce`: each sail's centre of effort swung about
  its luff, the mast, the forestay or the tack, by its optimal sheet angle), luffs the boat; the side force `F_h`
  at a centre of effort ahead of the CLR bears it away. Forces, heel and sheet angles are those of the polar.
- `x_clr`: the class's balance point, where the start config's moment vanishes close-hauled at its VMG angle in
  12 kn (`WH_BALANCE_TWS`), as a racing boat is designed and its rig raked to sail straight upwind with the helm
  centred. One point for every config (the lateral plane does not change with the sails): the main alone has
  weather helm, a kite far forward on its sprit pulls the bow off close reaching, and heel and drive give weather
  helm broad reaching in a breeze (the broach).
- the helm that holds it on a straight course, `h_e = N / (0.5 ρ_w v² A_r n_r C_Lα δ_max (x_clr − x_rudder))` (the
  rudder's yaw moment per unit helm in its linear range; the boat is not turning, so the whole rudder angle
  reaches the blade), held to ±3; the rate is the turn rate that helm gives on the radius law, `v / R(h_e)`, and
  beyond full helm `v h_e / R_full`, so a boat the rudder cannot hold broaches. It is also the rate at which the
  boat turns with the helm centred: in a helm turn the blade loses the share `1 − s` of its angle to the turn's
  cross-flow, and in a free turn at the same rate the centred blade meets that cross-flow and damps it, so the
  moment `N` meets the same yaw damping as the helm turn of `h_e`. Holding a course against it therefore takes
  `h_e` and pays that helm's rudder drag.
- broached cells from 45° TWA where the heel is what failed (`heel_limited`) are overpowered: the boat lies over
  at its heel limit and rounds up at the full-helm turn rate of its broached speed, `v_b / R_full` (a full helm at
  speed can still catch it). The other broached cells (pinching in a strong breeze) take the value of the last
  wind the config holds at that angle; no-go and no-wind cells are 0.

wm7 jib: within ±0.1°/s at the balance point, −0.7°/s at the VMG angle in 6 kn, +1.2 to +1.3°/s from 60 to 110° in
10 kn (a helm of about 0.02, under a degree of rudder), +4.4°/s at 90° in 14 kn and +4.6°/s at 110° in 17 kn
(pressed near its heel limit, a helm of about 0.05). Kite: −5 to −6°/s from 50 to 80° in 10 kn (the wrong sail
there), +3 to +4°/s broad reaching in 17 kn, +5°/s at 130° in 22 kn; overpowered (from 50° in 14 kn, reaching
from about 20 kn) it broaches at +10 to +20°/s. Before the straight-course helm and the linear-range radius law
(below) the same cells read +15°/s (jib, 100° in 16 kn) and −9 to −17°/s (kite close reaching).

### Broached speed

Some cells above the no-go edge have no equilibrium: no depowering keeps the config within the heel limit (a
spinnaker close reaching in a gale), or the boat cannot make way at that angle at all (pinching in a strong
breeze, where the keel stalls before the boat has speed). A real boat there broaches or wallows: it lies over,
sails flogging or stalled, and crawls. The polar holds a low **broached speed** instead of 0, so the core slows
the boat towards it rather than stopping it:

- speed: 0.4 × the speed the config makes at the same TWA in the strongest wind it still holds there (the last
  sailing TWS row below), at least 0.1 m/s (the value at the no-go edge);
- heel: the heel limit (`vpp.max_heel`, or the heel of the maximum righting moment when lower) where it was the
  heel that failed, else the heel of that last sailing row;
- acceleration: that of the last sailing row, so the boat settles to its broached speed about as quickly as it
  sailed there.

The step down where a config stops holding is deliberate: it is the cost of carrying the wrong sail. Broached
cells are marked in the config's `vpp.broached` table (1 = broached) and are left out of the trim and sheet-angle
tables, the VMG optima and the `dynamics` fits.

`dynamics` values derived from the design:

| key | how |
| --- | --- |
| `turn_radius_full` | `0.35 LWL sqrt((A_keel + A_rudder)/A_rudder)` (lateral-plane balance; matches the spec's references) |
| `turn_radius_offset` | `−(1 − h_s) turn_radius_full`: the turn rate grows with the helm until the rudder stalls at `h_s`, where half the rudder angle (the rest is the flow curving round the stern and the drift the turn needs) reaches the stall of the blade's lift line, `h_s = 1.1 / (0.5 · 2π AR/(AR + 2) · rudder_max)`, held in [0.6, 1]; the law then has the slope of the linear-then-stalled rudder at small helm, `R(h) → h_s R_full / h`, where the boat is steered and held against its helm balance (half helm gives 58 %, `h_s` about 80 % of the full-helm rate; wm7, wm12: `h_s` 0.72, 0.69) |
| `decel_linear` | the rate for which `dv/dt = −(k v + decel_const)` coasts from the close-hauled VMG speed to half of it in the time the upright hull does with the drive gone, `dv/dt = −(R(v)/(m + m_a) + decel_const)`; median over 6 to 16 kn TWS (a tack, a luff, let-fly) |
| `decel_const` | the hull at 1 m/s (a crawl), over the mass plus added mass |
| `decel_windage` | windage of hull, mast and the start config's sails luffing on their sheets head to wind per m/s of apparent wind: the square law's secant through `WINDAGE_AWS_REF` 3.4 m/s, with the wind profile factor at the centre of effort (the core's apparent wind is at 10 m), over the mass plus added mass; the core charges it at its own apparent wind, times `max(cos awa, 0)`. The whole square law made a tack in 22 kn lose most of its way (the coast law gives the sails no drive anywhere in the no-go zone) and full-helm tacks cheaper than half-helm ones; the secant keeps the tack targets of `boat.md` §7.2 |
| `heel_speed_factor` | 1 up to `vpp.max_heel`; beyond, the surge equilibrium with the heel held there, relative to the limit |
| `rudder_drag_luff`, `_bear` | rudder lift-line drag with stall, plus the keel's induced drag carrying the turn's centripetal force at the turn radius of that helm (the radius law with the offset above), over the mass. The blade's incidence is the same share (0.5) of the rudder angle the radius law's offset assumes, so the drag's stall knee is the radius law's stall helm `h_s`; past the stall incidence the flow separates over 5° and the blade's force becomes a normal force of about its maximum lift, whose drag is `cl_max sin α`. The bear-away table is the same evaluated 0.75 m/s slower |
| `heel_max` | heel of the maximum righting moment, at most 65° |
| `heel_freq`, `heel_damping` | roll stiffness (righting-moment slope) over roll inertia (hull, rig, bulb, crew, +20 % added); aerodynamic roll damping of the sail plan |
| `pitch_freq` | waterplane pitch stiffness over pitch inertia (+80 % added) |
| `collision`, `hull_points`, `wind_shadow` geometry | the generator's `perf_inputs` when given, else the reference constructions of `collisions.md` §2.1 and `wind_shadow.md` §2 |

The rest (`helm_rate`, `yaw_time` (S 0.35 s, L 0.6 s), `pitch_damping`, `heave_time`, `surf_gain`, wobble, wave gains, sail rates, handling
times, slowdowns) use the reference values of the owning specs, interpolated between the sportsboat and
large-monohull archetypes by waterline length. The `vpp` block (ignored by the core) records the notes, VMG
optima, the righting-moment curve, the added-mass coefficient and diagnostic tables (flat, reef, AWA, leeway,
broached).

## Model

### Geometry and hydrostatics
Each canoe body is lofted from its class parameters: waterline half-breadth and keel-line depth follow power
laws from the maximum section to the ends (forefoot and transom from `rocker`, aft waterline beam from
`transom_width`), sections are superellipses whose area coefficient is the midship coefficient, topsides flare
straight to the sheer (three freeboards). The fore-and-aft exponent is solved for the prismatic coefficient and
the maximum-section station for the LCB. Heeled hydrostatics clip every section polygon at the waterline and
integrate area and moments with Green's theorem (level trim), vectorised over heel; the sinkage is solved for
the displaced volume. Multihull floats are extra polygons, so the same code gives the righting moment of a
trimaran lifting its main hull. Appendage buoyancy sits at its centroid and rolls with the boat.

### Hydrodynamics
- Friction: ITTC-57 correlation line. Monohull canoe body with the Reynolds number on 0.7 LWL and no form factor
  (the convention of the Delft regression), on the heeled lofted wetted area. Fin, rudder: mean chord, Hoerner
  foil form factor `1 + 2t/c + 60(t/c)^4`; bulb: body-of-revolution form factor `1 + 1.5(d/l)^1.5 + 7(d/l)^3`.
- Residuary, monohull: the Delft Systematic Yacht Hull Series bare-hull regression of Keuning and Katgert (2008),
  Fn 0.15 to 0.75, made monotone and fading as Fn⁴ below the range.
- Planing is gated on the hull's weight for its length, the displacement-length ratio
  `DLR = (displacement / 1016 kg) / (LWL / 30.48 m)³` on `hull.displacement` (without crew, the usual
  convention): planing ability 1 up to DLR 100, 0 from DLR 106, smooth in between (wm7: 82, a typical 7 m
  sportsboat about 100, wm12: 108).
  - A hull that can plane holds the regression where it levels off; once the bottom's dynamic lift
    `0.5 ρ V² 0.08 Aw` reaches 30 % of the weight its coefficient blends towards `min(coefficient, 0.055)` (a
    planing hull's residuary drag/lift ratio), fully at 90 % (calibrated, below). The blend is scaled by the
    ability.
  - A hull that cannot plane keeps climbing its wave wall from the point where the monotone regression levels
    off, with the regression's log slope just before it (bounded to 2 to 6), so it never gets over the hump
    however hard it is driven.
  - The total upright resistance (canoe body, appendages) is made to grow at least in proportion to the speed:
    where the planing blend or a levelling regression would make it flatter, the residuary part ahead of the hump
    is lowered to the largest curve that does (the hump is shaved; the planing branch beyond it is kept). The
    drive of a reaching rig grows with the boat's speed, so a flatter resistance curve has two speed roots and the
    polar would jump where the lower one disappears; with this rule a planing boat's speed climbs steeply but
    continuously with the wind, to the same high-wind speeds as before.
- Keel residuary and its heel increment: Keuning and Sonnenberg (1998), on the fin volume (the Delft keel series
  were fins; a deep bulb is charged through its friction and form drag).
- Induced resistance: `Fh² / (π Te² q)` with the effective draft `Te` of Keuning and Sonnenberg (1998) (heel and
  Froude dependent); beyond a lift coefficient of 1.1 on keel plus rudder a quadratic stall term.
- Deck-edge immersion (Windmark term): residuary resistance grows with the square of the heel beyond the angle
  where the sheer meets the water, so the optimiser never settles at a knock-down.
- Multihull bodies are slender (L/B 10 to 20, outside the Delft series): Michell's thin-ship wave resistance
  (Michell 1898; Tuck 1989), integrated numerically on the lofted body at a range of immersions (a transom is
  closed by a virtual run), with ITTC-57 friction on LWL and a slender-body form factor. The floats' immersion
  and wetted area at each heel come from the hydrostatics.
- Added mass in surge: prolate spheroid of the canoe body and its mirror image (Lamb 1932).

### Aerodynamics
The classic VPPs (Hazen 1980; the ORC VPP) give each sail's lift and parasitic drag against the apparent wind
angle with the trim folded in. The game also needs the trim, so each sail has coefficients against its angle of
attack `α = β_e − δ` (sheet angle `δ` from the centreline, limited by the deck layout): luffing below
`alpha_luff`, attached lift rising as a quarter sine to `cl_max` at `alpha_stall` with profile drag
`cd0 + kp Cl²`, then a blend over `blend` into a stalled plate (normal force saturating at `cn_max`), a twist
drag `kt δ²` for eased sheets, and for front sails a blanketing loss behind the main from 110° to 180°. For each
`β_e` and flattening the best sheet angle maximises the drive coefficient; the envelope of these optima is fitted
to the ORC (2023) per-sail coefficient tables (main and jib "high", symmetric and asymmetric spinnaker;
`tests/test_sails.py` re-checks the fit). Code zero has no published table and sits between jib and gennaker.

Rig: coefficients summed by area; induced drag `Cl² (1/(π AR) + 0.005)` with Hazen's effective height (the deck
mirror close-hauled, `1.1 mast_height`, fading to `1.1 (mast_height − freeboard)` off the wind); windage
`1.13 (beam · freeboard + mast height · mast chord)` (Hazen). A main with no jib or genoa in front loses the
slot: its lift is scaled by 0.72 close-hauled, recovering by 110° (calibrated). The true wind is given at 10 m
and scaled to the centre of effort with a logarithmic sea profile (`z0` = 0.2 mm); the rig sees the apparent
wind component normal to the heeled mast (Kerwin 1978).

Depowering: `flat` (0.1 to 1, scales attached lift) and `reef` (0.55 to 1, area × reef², heights × reef;
main and jib or genoa). Every sail is trimmed to its best angle.

### Equilibrium and optimisation
Two degrees of freedom: surge (drive = resistance) and roll (side force × (centre of effort + 0.45 draft) =
righting moment). For each (TWS, TWA, flat, reef) the roll equation is solved for the heel at every probe speed,
so the surge balance is one equation in the speed, solved by a scan up from rest and a bisection, all
combinations at once. The speed is the lowest stable root: a boat that cannot get over a resistance hump stays
below it. The fastest valid combination (heel within `vpp.max_heel` and below the
maximum righting moment) wins, ties going to more power. VMG optima are searched on a 0.5° grid around the table
optimum with the neighbouring controls.

## Calibration

The generic model coefficients were checked against reference performance tables of four archetype classes (a
24 m grand-prix monohull, a 14 m offshore racer, a 7 m sportsboat and an 18 m ocean trimaran), running the VPP on
estimated designs of comparable boats and comparing shapes: speed against TWA per TWS, VMG angles, heel and sail
crossovers. The references are game tables, not measurements, so only shapes and systematic trends were used;
no table was copied. Changes it drove, all generic:

- sail envelopes refitted with physical bounds (gentle stall, luffing margin) so trim errors cost speed smoothly,
  and a blanketing term for front sails dead downwind (asymmetric spinnakers no longer run square);
- the keel regressions on the fin volume only;
- the mainsail-alone slot loss (0.72);
- the planing blend on the bottom's dynamic lift share (start 0.3, full 0.9, drag/lift 0.055), and the lowest
  stable speed root;
- later, on owner decisions: planing gated on the displacement-length ratio, the upright resistance growing at
  least with the speed, and speed and heel solved together (the alternating solution could settle on either of
  two states near the heel limit). The comparison was rerun after these; see the calibration report.

Resulting agreement: shape correlation of speed against TWA per TWS 0.71 to 0.97 per config, mean upwind VMG
angle difference 3 to 8°, downwind 7 to 14°, sail crossovers 65 to 88 % in agreement. The remaining
differences (the references are faster upwind and pointing higher, penalise the main alone more, and heel more)
were judged to be properties of the references, not of the physics, and left alone.

## Sources

- Keuning, J.A., Katgert, M. (2008). A bare hull resistance prediction method derived from the results of the
  Delft Systematic Yacht Hull Series extended to higher speeds. Innovation in High Performance Sailing Yachts,
  Lorient.
- Keuning, J.A., Sonnenberg, U.B. (1998). Approximation of the hydrodynamic forces on a sailing yacht based on the
  Delft Systematic Yacht Hull Series. 15th International Symposium on Yacht Design and Yacht Construction,
  Amsterdam.
- ITTC (1957). Friction correlation line, 8th International Towing Tank Conference, Madrid.
- Hoerner, S.F. (1965). Fluid-Dynamic Drag. Hoerner Fluid Dynamics.
- Michell, J.H. (1898). The wave resistance of a ship. Philosophical Magazine 45, 106 to 123.
- Tuck, E.O. (1989). The wave resistance formula of J.H. Michell (1898) and its significance to recent research
  in ship hydrodynamics. Journal of the Australian Mathematical Society B 30, 365 to 377.
- Hazen, G.S. (1980). A model of sail aerodynamics for diverse rig types. New England Sailing Yacht Symposium,
  SNAME.
- Offshore Racing Congress (2023). ORC VPP Documentation (sail force coefficient tables).
- Kerwin, J.E. (1978). A velocity prediction program for ocean racing yachts. MIT report 78-11.
- Lamb, H. (1932). Hydrodynamics, 6th ed. Cambridge University Press (added mass of a spheroid).
- Larsson, L., Eliasson, R.E., Orych, M. (2014). Principles of Yacht Design, 4th ed. Adlard Coles (general VPP
  structure).

The regression coefficients and sail tables are published numerical data, used with attribution; no third-party
code is included.

## Limits and next steps

- The helm balance has no hull terms (the heeled hull's asymmetry, the Munk moment of the canoe body): their
  value at the balance point is folded into `x_clr`, their change with speed and heel is left out. The balance
  point is a design statement (12 kn, close-hauled), not derived from the lateral plane geometry. The sail plan's
  forces act at its area-weighted centre of effort (a kite far forward on its sprit gives lee helm close
  reaching). The polar is the fastest trim, not a balanced one: a crew easing the main to keep the helm light on
  a breezy reach is not modelled, so near its heel limit the boat carries 4 to 7°/s of weather helm.
- `yaw_time` is a reference value by length, not derived from the yaw inertia and damping.
- `fall_off` uses the spec's reference rate, not a yaw balance of the windage.
- The drift tables take the cross-flow drag coefficients from Hoerner's plates and blunt bodies, not a measurement
  of a hull drifting; the drift is the windage alone (sails on the wind line), so the side force of stalled,
  over-sheeted sails at a crawl is not in it.
- The radius law's offset and the rudder drag rest on an assumed share (0.5) of the rudder angle reaching the
  blade in a turn (the rest is the flow curving round the stern and the drift the turn needs), the same for
  every helm; a manoeuvring model would give it per helm and speed.
- `CD_flog` is an estimate. `decel_windage` is one coefficient for every config (the start config's sails), linear
  in the apparent wind (a calibrated secant of the square law, above), and takes the windage along the heading as
  `cos(awa)` of its head-to-wind value (the topsides' side area is left out).
- The VPP cannot give the build-up from rest physically: its steady keel carries the whole side force, whose
  induced drag grows without bound as the speed goes to 0. `accel_rest` is the drive at rest instead, and the
  core blends it into `accel` below half the target speed.
- Level trim only; no pitch trim with speed, no wave added resistance, no leeway in the apparent wind.
- The planing blend and the mainsail-alone loss are calibrated, not derived; flat-bottomed sportsboats sit at the
  edge of the Delft series.
- Multihull resistance ignores hull interference; the float wave resistance uses the upright shape.
- Sail handling times are reference values scaled by length, not a crew-work model.
- The broached speed is a rule of thumb (a share of the last held speed), not a model of a broach.
- Planing is a gate on the displacement-length ratio and a calibrated blend, not a planing-hull model (no
  dynamic trim, no spray drag); a class near the gate (DLR 100 to 106) planes partly. The gate is
  dimensionless, so it separates hulls by weight for their length, not by size: wm12 sits just past it (a wm12
  some 2 % lighter would start to plane, smoothly).
