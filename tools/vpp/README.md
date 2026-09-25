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
- Multihulls (`hull.type`, `hull.floats`, `hull.hull_spacing`, `boards`, `rudder.count`) and the `vpp` block
  (`max_heel`) are specified in `data_format.md` §3.9 and §3.10, with their units and defaults. The float
  bodies are extra polygons of the same hydrostatics; the boards are read like a keel fin without a bulb.

## Output: performance file

`windmark.perf/1` exactly as `data_format.md` §4 and §5 define it: header with the class hash and the
`handling` multipliers used, `dynamics`, `sails`, one entry per config (main alone, main + each front sail) with
`polar`, `heel`, `accel`, `trim_speed`, `trim_heel`, `optimal_angle`, and `start`. Axes follow the spec's recommendation: TWS 0 to
20.6 m/s (40 kn), TWA 0°, 7°, the no-go edge twice, then 2° steps to 60° and 5° steps to 180°; AWA every 5°;
trim error −60° to +120°. `weather_helm` and `fall_off` (optional) are not written yet.

What each table holds:

- `polar`: equilibrium speed at the best depowering and trim. Below the no-go edge (1.5° below the first TWA
  where the config makes way at 8 kn or more) the steady sternway the windage drives, capped at 0.15 TWS, with
  the spec's step to +0.1 m/s at the edge. Above the edge the polar is never 0: see "Broached speed".
- `heel`: equilibrium heel. `accel`: the constant acceleration that reproduces the time to build speed from 50 %
  to 95 % of the polar, integrating (drive − resistance)/(mass + added mass) with the heel in equilibrium at
  each speed (8-point Gauss-Legendre); floor 0.005 m/s².
- `trim_speed`, `trim_heel`: equilibrium speed and heel with every sail of the config sheeted `eps` away from
  its optimum (the single manual sheet of `sails.md` §5.2), clamped to the sheet limits and the wind line,
  relative to the trimmed values; resampled from TWA onto AWA per TWS row.
- `optimal_angle`: best sheet angle of each sail against AWA (resampled the same way).

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
| `decel_linear` | median of `d(resistance − drive)/dV / (m + m_a)` at the polar, 6 to 16 kn TWS, 40° to 150° TWA |
| `decel_const` | deceleration in irons: windage at 5 m/s apparent wind plus the hull at 1 m/s, over the mass |
| `heel_speed_factor` | 1 up to `vpp.max_heel`; beyond, the surge equilibrium with the heel held there, relative to the limit |
| `rudder_drag_luff`, `_bear` | rudder lift-line drag with stall, plus the keel's induced drag carrying the turn's centripetal force at the turn radius of that helm, over the mass; the bear-away table is the same evaluated 0.75 m/s slower |
| `heel_max` | heel of the maximum righting moment, at most 65° |
| `heel_freq`, `heel_damping` | roll stiffness (righting-moment slope) over roll inertia (hull, rig, bulb, crew, +20 % added); aerodynamic roll damping of the sail plan |
| `pitch_freq` | waterplane pitch stiffness over pitch inertia (+80 % added) |
| `collision`, `hull_points`, `wind_shadow` geometry | the generator's `perf_inputs` when given, else the reference constructions of `collisions.md` §2.1 and `wind_shadow.md` §2 |

The rest (`helm_rate`, `pitch_damping`, `heave_time`, `surf_gain`, wobble, wave gains, sail rates, handling
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

- `weather_helm` and `fall_off` tables are not generated (the core treats them as 0). They need a yaw balance
  model (centre of effort against centre of lateral resistance with heel) tuned for gameplay.
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
