# Downwind and code zero check against ORC (2026-10)

Question: is the boat too slow downwind, are the kite and code zero too close to the jib, and why does the code
zero win at angles where no real crew would fly it? The investigation below changed nothing; the fixes the owner
approved (WM-138, WM-127) and their result are in "Result" at the end.

Scripts (run from `tools/vpp`):

- `analysis/downwind_table.py <perf.json>`: speeds per config at ORC rows, run and beat VMG, from a perf file.
- `analysis/downwind_variants.py [variant ...]`: re-solves both classes with patched model constants (planing
  gate, kite limits, code zero coefficients, main slot); `base` is the shipped model.
- `analysis/fit_code0.py [62.5|73] [sheet_max]`: fits the code zero's sail parameters to the ORC flying-headsail
  table.

## References

ORC velocity predictions (best sail in each cell, flat water). The 2019 one-design certificates are at
`https://data.orc.org/public/od/2019/<class>.od.pdf` (j70, melg24, j80, farr40). The 2026 certificates come from
the ORC public feed `https://data.orc.org/public/WPub.dll?action=DownRMS&CountryId=<ISO>&ext=json`, where
speed = 3600 / allowance; run speed = run VMG / |cos gybe angle|. Sail coefficients come from the ORC VPP
Documentation 2023 (`https://orc2.orc.org/rules/ORC%20VPP%20Documentation%202023.pdf`), Tables 5.1 to 5.9.

| boat | sailing mass (kg) | main + jib (m²) | kite (m²) | nearest Windmark class |
| --- | --- | --- | --- | --- |
| J/70 OD 2019 | 811 + 347 crew | 25.5 | 45.6 asym | wm7 (900 + 340, 37.0, 53.5) |
| Melges 24 OD 2019 | 821 + 393 | 33.5 | 56.2 asym | wm7 (same sail area per tonne) |
| Farr 40 OD 2019 | 4967 + 777 | 106.4 | 162.0 sym | wm12 (5000 + 680, 96.0, 155.5) |
| J/111 2026 (USA 04560004U8S) | 5165 sailing | 72.7 | 129.9 asym | wm12, lighter rig |
| J/122 2026 (USA 04560004Q4B) | 7865 sailing | 91.5 | 154.4 asym | wm12, 40 % heavier |

## Comparison (kn; TWS 6 / 8 / 10 / 12 / 16 / 20 kn)

### wm7 against J/70 and Melges 24

| | wm7 | J/70 | Melges 24 |
| --- | --- | --- | --- |
| run VMG | 3.55 / 4.45 / 5.14 / 5.61 / 8.33 / 11.60 | 3.54 / 4.46 / 5.11 / 5.52 / 6.67 / 9.13 | 3.74 / 4.73 / 5.42 / 5.97 / 7.57 / 10.64 |
| kite 150° | 4.06 / 5.14 / 5.93 / 6.48 / 8.68 / 12.62 | 4.09 / 5.15 / 5.90 / 6.37 / 7.70 / 10.55 | 4.32 / 5.46 / 6.26 / 6.90 / 8.74 / 12.29 |
| kite 135° | 4.80 / 5.80 / 6.51 / 7.36 / 11.62 / 14.72 | 4.81 / 5.85 / 6.46 / 7.14 / 9.03 / 12.62 | 5.12 / 6.21 / 6.95 / 7.89 / 10.46 / 13.33 |
| best 110° | 5.38 / 6.27 / 6.83 / 7.87 / **11.26 jib** / **13.42 jib** | 5.53 / 6.32 / 7.04 / 7.82 / 8.76 / 9.89 | 5.88 / 6.73 / 7.66 / 8.29 / 9.45 / 11.14 |
| best 90° | 5.37 / 6.14 / 6.65 / 7.61 / 9.44 / 10.83 | 5.46 / 6.22 / 6.76 / 7.06 / 8.01 / 9.01 | 5.79 / 6.59 / 7.05 / 7.68 / 9.11 / 9.60 |
| beat VMG | 3.00 / 3.57 / 3.89 / 4.12 / 4.30 / 4.28 | 3.03 / 3.70 / 4.20 / 4.53 / 4.66 / 4.63 | 3.36 / 4.10 / 4.59 / 4.77 / 4.83 / 4.87 |

wm7 equals the J/70 downwind up to 12 kn and is 5 to 8 % behind the Melges 24, which carries the same sail area
per tonne. From 16 kn it is too fast: run VMG +10 % on the Melges 24 and +25 % on the J/70, and broad reaching
under the jib alone at 110 to 120° it is 20 to 35 % too fast (11.3 kn at 110° in 16 kn; the references make 8.8
to 9.5 with their best sail).

### wm12 against Farr 40 (its near twin), J/111 and J/122

| | wm12 | Farr 40 | J/111 | J/122 |
| --- | --- | --- | --- | --- |
| run VMG | 4.06 / 5.09 / 5.96 / 6.59 / 7.45 / 8.56 | 4.44 / 5.59 / 6.48 / 7.20 / 8.38 / 10.21 | 4.15 / 5.24 / 6.13 / 6.77 / 7.71 / 9.25 | 4.16 / 5.22 / 6.11 / 6.77 / 7.59 / 8.45 |
| kite 150° | 4.57 / 5.84 / 6.88 / 7.61 / 8.56 / 9.41 | 5.13 / 6.45 / 7.48 / 8.19 / 9.64 / 11.79 | 4.79 / 6.05 / 7.07 / 7.77 / 8.90 / 10.68 | 4.80 / 6.03 / 7.05 / 7.77 / 8.68 / 9.76 |
| kite 135° | 5.45 / 6.72 / 7.61 / 8.29 / 9.44 / 11.48 | 6.08 / 7.50 / 8.24 / 9.00 / 10.88 / 12.42 | 5.71 / 7.05 / 7.80 / 8.44 / 9.95 / 11.90 | 5.71 / 7.02 / 7.80 / 8.34 / 9.46 / 11.03 |
| best 90° | 6.42 / 7.37 / 8.06 / 8.41 / 9.04 / 9.45 | 7.16 / 7.95 / 8.46 / 9.00 / 9.71 / 10.03 | 6.58 / 7.49 / 7.90 / 8.15 / 8.70 / 9.10 | 6.64 / 7.54 / 8.01 / 8.35 / 8.81 / 9.09 |
| best 60° | 5.82 / 6.83 / 7.34 / 7.64 / 8.07 / 8.22 | 6.90 / 7.77 / 8.09 / 8.26 / 8.49 / 8.72 | 6.14 / 7.12 / 7.55 / 7.76 / 7.96 / 8.07 | 6.24 / 7.22 / 7.65 / 7.90 / 8.11 / 8.22 |
| beat VMG | 3.50 / 4.19 / 4.62 / 4.87 / 5.18 / 5.26 | 4.27 / 5.16 / 5.55 / 5.72 / 5.98 / 5.99 | 3.84 / 4.70 / 5.19 / 5.39 / 5.56 / 5.61 | 3.84 / 4.68 / 5.22 / 5.47 / 5.68 / 5.75 |

wm12 is slow at every angle, not only downwind. Against the Farr 40 it is 8 to 9 % slower downwind up to 12 kn
and 11 to 16 % slower in 16 to 20 kn, and 12 to 19 % slower upwind. It is also slower than the J/122, which is
40 % heavier, everywhere except run VMG at 20 kn. Downwind in breeze its speed stalls at 8.5 to 9.5 kn (Froude number
0.45), and at 16 kn its best VMG is dead downwind at 178°.

### Kite against jib

| run VMG gain of the kite over the jib | 6 | 8 | 10 | 12 | 16 | 20 kn |
| --- | --- | --- | --- | --- | --- | --- |
| wm7 | +24 % | +17 % | +11 % | +5 % | +29 % | +35 % |
| wm12 | +26 % | +24 % | +18 % | +11 % | +2 % | +3 % |
| ORC Protagonist 750 (same boat, with and without a spinnaker) | | +7 % | | +7 % | +13 % | +17 % |
| ORC Tripp 40 speed guide (headsail alone against best) | | +12 % | | +6 % | +3 % | +4 % |

ORC's non-spinnaker configuration adds a "jib downwind" pseudo-sail (asymmetric coefficients on 1.064 × the jib
area, VPP Documentation §5.2.2), so ORC understates what a kite gains over a plain jib. Even so, in light air the
Windmark kite already gains more than ORC shows. The small gap on wm12 in breeze comes from the hull wall, which
caps both configs at the same speed. Reaching from 90 to 110°, ORC shows the kite gaining nothing or losing a
little, as Windmark does.

## Causes

1. **The planing switch on the dry displacement-length ratio (`hydro.PLANING_DLR_FULL/NONE`, 100 to 106).**
   wm7 and wm12 have nearly the same hull in Froude terms (∇^(1/3)/LWL 0.155 and 0.159, the same Delft curve).
   The DLR of the boat without crew still puts wm7 at 82 (planes fully) and wm12 at 108 (never planes; its
   resistance climbs a wall growing as Fn^2.8 past the Delft peak). ORC treats the J/70 and the Farr 40 as
   Froude-similar: at 10 kn TWS and 150° both reach Fn 0.37 to 0.38, and at Froude-equivalent breeze both make
   about Fn 0.6 at 135°. Windmark gives wm7 Fn 0.73 and wm12 0.47. This one cliff makes wm7 too fast and wm12
   too slow in breeze. The planing branch (drag/lift 0.055, from lift share 0.3) is also too generous for wm7,
   most visibly under the jib alone on a broad reach.
2. **The code zero has made-up coefficients, and the solver treats it as "main alone".** Its parameters
   (`sails.COEFFS["code0"]`) give a cl_max of 1.25 (ORC flying headsail: 1.48 at 62.5 % HHW/HLP, 1.31 at 73 %)
   and a downwind drag of 0.70 to 0.80 with no blanketing (ORC: 0.37 to 0.45). The result is the opposite of a
   code zero: underpowered reaching, overpowered running. On top of that, `Rig.forces` cuts the main's lift by
   28 % close-hauled whenever no jib or genoa is set (`MAIN_ALONE_CL`), and a code zero is not on that list.
   That is a plain bug, because a code zero is a headsail in front of the main. The ORC VPP has a full
   flying-headsail table (Table 5.9, six HHW/HLP sets). Fitted to the 62.5 % set (`fit_code0.py`), with the main
   in its slot (variant `c0_orc`), the wm12 code zero wins 52 to 110° at 6 to 8 kn, 75 to 110° at 10 kn and only
   about 110° from 12 kn. It no longer wins dead downwind (run VMG 7.26 against the A2's 7.45 at 16 kn). This
   matches North Sails (55 to 90° AWA), UK Sailmakers (50 to 125° TWA) and the ORC Tripp 40 speed guide, where
   the flying headsail is best from 60 to 90° in every wind.
3. **Not the cause: the kite's heel limit (21.5°) and flat floor (0.42).** Freeing both (variant `kite_free`)
   changes kite speeds by under 0.3 kn except in broached cells (90° in 20 kn). The kite's aero coefficients
   follow the ORC centreline asymmetric table within the test tolerance, and the jib downwind follows the ORC jib
   table (Cd 0.90 to 0.95 from 150°).
4. **Minor findings.**
   - The main's slot loss (`MAIN_ALONE_CL`) also applies under a kite. The ORC main coefficients are the same
     with a spinnaker. Lifting it (variant `slot_all`) adds 3 to 10 % to the kite from 52 to 90° and almost
     nothing deeper.
   - Downwind the depowering optimiser picks flat 0.1 in some cells because of a 0.04 % speed difference, which
     beats the 2e-4 tie bonus. It does not change the speeds, but it shows up in `vpp.flat`.
5. **A general deficit at low speed, open.** The model's speeds at equal sail area per tonne sit 5 to 15 % under
   ORC (wm7 against the Melges 24, wm12 against the Farr 40 and J/122, upwind and downwind). The Delft residuary
   already exceeds friction from Fn 0.34. The best next check is to run the VPP on class files of the reference
   boats themselves and compare against their certificates, which separates model error from design differences.

## Proposed fixes (general, not per boat)

1. Replace the DLR switch with one continuous resistance law that does not set similar hulls apart. Hold the
   Delft curve past its peak with no wall, and set a planing blend whose onset and drag/lift are calibrated on
   the four ORC references at Fn 0.4 to 0.8. Variant `hull_a` (gate to DLR 140, drag/lift 0.075) is a first cut:
   wm7 run VMG becomes 7.63 / 10.80 at 16 / 20 kn (Melges 24 7.57 / 10.64), and wm12 becomes 7.45 / 10.49
   (Farr 40 8.38 / 10.21). The Fn 0.45 to 0.55 hump still holds wm12 back at 16 kn, and wm12 at 135° in 20 kn
   overshoots (14.4 against 12.4), so the curve needs a real fit, not just these two constants.
2. Code zero (WM-127): fit the coefficients to ORC Table 5.9 (62.5 % or 73 % HHW/HLP), keep the main in its slot
   behind it, and keep ORC's minimum reef of 0.91 (no reefing). Expected crossover as in variant `c0_orc` above.
3. Apply `MAIN_ALONE_CL` to the main-alone config only.
4. After 1 to 3, look into the general low-speed deficit (item 5 above) by running the VPP on modelled reference
   boats.

## Result (WM-138, WM-127)

What changed in the model (spec: `tools/vpp/README.md` "Hydrodynamics", "Aerodynamics", "Calibration against ORC";
`docs/specs/sails.md` §6):

1. **Planing.** The blend towards a drag/lift of 0.055 (gated from DLR 100 to 106) is gone. A hull that can plane
   takes the Delft residuary at the effective Froude number `Fn_e = 0.38 + 0.4 (Fn - 0.38)` (its hump stretched over
   a wider speed range, as the ORC VPP's dynamic length does) and holds it where it levels off; the planing ability
   gate runs from DLR 100 to 200, so wm7 (82, ability 1) and wm12 (108, ability 0.98) are treated alike. A hull
   heavier than DLR 200 keeps the towed curve and its wave wall. The constants were fitted with grid runs
   of the two classes against the Melges 24, J/70 and Farr 40 (best sail in each cell, 12 to 20 kn, run VMG, 135 and
   150°); the gate's far end so that wm12 made 40 % heavier keeps its light-air offset to the J/122 in a breeze.
   The stretch starts at Fn 0.38 so close-hauled speeds keep the towed curve: starting at 0.35 fitted downwind as
   well but widened wm7's best beat in 16 to 20 kn from 40 to 45°.
2. **Code zero.** Coefficients fitted to ORC Table 5.9 at HHW/HLP 62.5 % (`analysis/fit_code0.py`), blanketed
   downwind like the gennaker; its sheet runs from 18° (was 12°: with 12° it beat the jib close-hauled in light air,
   below the table's first angle of 27° AWA; the fit is as good with 18°). With a code zero set the reef goes no
   lower than 0.91 (ORC §5.2.5) and the code zero itself is not reefed.
3. **The main's slot.** `MAIN_ALONE_CL` (0.72) applies to the main-only config; behind a jib, genoa or code zero
   the main keeps its full ORC coefficients (this fixes `Rig.forces`, which listed only jib and genoa). Under a kite
   the loss fades out from 28 to 41° effective AWA, where the ORC spinnaker tables start to draw: with no loss at
   all the kite configs sailed on the main alone at 34 to 38° TWA, an island of speeds ahead of their no-go edge.
4. **Jib alone downwind** keeps the ORC jib coefficients; with the new hull law wm7's jib at 110° in 16 to 20 kn
   (9.9 and 11.5 kn) is within 5 % of the best-sail ORC speeds, down from 20 to 35 % over.

### Before / after / ORC

#### wm7 (best sail per cell; old / new / ORC M24 / J70, % of new off the first reference)

| | 6 kn | 8 kn | 10 kn | 12 kn | 16 kn | 20 kn |
| --- | --- | --- | --- | --- | --- | --- |
| run VMG | 3.54 / **3.57** / 3.74/3.54 (-5 %) | 4.44 / **4.44** / 4.73/4.46 (-6 %) | 5.13 / **5.18** / 5.42/5.11 (-4 %) | 5.62 / **6.02** / 5.97/5.52 (+1 %) | 8.25 / **7.60** / 7.57/6.67 (+0 %) | 11.42 / **9.84** / 10.64/9.13 (-7 %) |
| 150° | 4.06 / **4.06** / 4.32/4.09 (-6 %) | 5.12 / **5.12** / 5.46/5.15 (-6 %) | 5.93 / **5.98** / 6.26/5.90 (-4 %) | 6.48 / **6.95** / 6.90/6.37 (+1 %) | 8.67 / **8.62** / 8.74/7.70 (-1 %) | 12.62 / **10.82** / 12.29/10.55 (-12 %) |
| 135° | 4.78 / **4.89** / 5.12/4.81 (-5 %) | 5.80 / **5.91** / 6.21/5.85 (-5 %) | 6.52 / **7.04** / 6.95/6.46 (+1 %) | 7.37 / **8.05** / 7.89/7.14 (+2 %) | 11.57 / **10.45** / 10.46/9.03 (-0 %) | 14.63 / **13.32** / 13.33/12.62 (-0 %) |
| best 110° | 5.35 / **5.56** / 5.88/5.53 (-5 %) | 6.24 / **6.66** / 6.73/6.32 (-1 %) | 6.89 / **7.58** / 7.66/7.04 (-1 %) | 7.86 / **8.26** / 8.29/7.82 (-0 %) | 11.20 / **9.88** / 9.45/8.76 (+5 %) | 13.41 / **11.47** / 11.14/9.89 (+3 %) |
| best 90° | 5.34 / **5.40** / 5.79/5.46 (-7 %) | 6.11 / **6.21** / 6.59/6.22 (-6 %) | 6.70 / **7.31** / 7.05/6.76 (+4 %) | 7.52 / **8.07** / 7.68/7.06 (+5 %) | 9.44 / **9.02** / 9.11/8.01 (-1 %) | 10.80 / **9.71** / 9.60/9.01 (+1 %) |
| beat VMG | 3.00 / **3.00** / 3.36/3.03 (-11 %) | 3.57 / **3.57** / 4.10/3.70 (-13 %) | 3.89 / **3.89** / 4.59/4.20 (-15 %) | 4.12 / **4.12** / 4.77/4.53 (-14 %) | 4.30 / **4.30** / 4.83/4.66 (-11 %) | 4.28 / **4.28** / 4.87/4.63 (-12 %) |

#### wm12 (best sail per cell; old / new / ORC F40, % of new off the first reference)

| | 6 kn | 8 kn | 10 kn | 12 kn | 16 kn | 20 kn |
| --- | --- | --- | --- | --- | --- | --- |
| run VMG | 4.04 / **4.10** / 4.44 (-8 %) | 5.08 / **5.10** / 5.59 (-9 %) | 5.93 / **5.93** / 6.48 (-9 %) | 6.59 / **6.65** / 7.20 (-8 %) | 7.53 / **8.26** / 8.38 (-1 %) | 8.53 / **10.11** / 10.21 (-1 %) |
| 150° | 4.56 / **4.56** / 5.13 (-11 %) | 5.82 / **5.82** / 6.45 (-10 %) | 6.84 / **6.84** / 7.48 (-8 %) | 7.60 / **7.68** / 8.19 (-6 %) | 8.57 / **9.53** / 9.64 (-1 %) | 9.44 / **11.36** / 11.79 (-4 %) |
| 135° | 5.44 / **5.58** / 6.08 (-8 %) | 6.69 / **6.82** / 7.50 (-9 %) | 7.59 / **7.75** / 8.24 (-6 %) | 8.30 / **8.98** / 9.00 (-0 %) | 9.45 / **11.10** / 10.88 (+2 %) | 11.39 / **13.47** / 12.42 (+8 %) |
| best 90° | 6.41 / **6.77** / 7.16 (-5 %) | 7.38 / **7.67** / 7.95 (-4 %) | 8.04 / **8.68** / 8.46 (+3 %) | 8.40 / **9.20** / 9.00 (+2 %) | 9.03 / **10.17** / 9.71 (+5 %) | 9.45 / **10.96** / 10.03 (+9 %) |
| best 60° | 5.79 / **6.16** / 6.90 (-11 %) | 6.79 / **6.94** / 7.77 (-11 %) | 7.34 / **7.34** / 8.09 (-9 %) | 7.64 / **7.67** / 8.26 (-7 %) | 8.07 / **8.38** / 8.49 (-1 %) | 8.22 / **8.75** / 8.72 (+0 %) |
| beat VMG | 3.50 / **3.53** / 4.27 (-17 %) | 4.19 / **4.19** / 5.16 (-19 %) | 4.62 / **4.62** / 5.55 (-17 %) | 4.87 / **4.87** / 5.72 (-15 %) | 5.18 / **5.18** / 5.98 (-13 %) | 5.26 / **5.26** / 5.99 (-12 %) |

Before: `old`, the tables on main before WM-138. 12 to 20 kn (the target): wm7 lies between the J/70 and the
Melges 24 everywhere (at the Melges 24 within 2 % except 150° and run VMG in 20 kn, at the J/70); wm12 is within
5 % of the Farr 40 from 16 kn except 135° in 20 kn (+8 %, larger righting moment and an asymmetric kite against the
Farr 40's symmetric one) and 6 to 8 % slow at 12 kn running, the level of the light-air deficit (WM-139). Under
12 kn nothing got slower. Reaching under the jib in breeze wm12 is 5 to 9 % over the Farr 40 at 90°.

### Upwind

The jib's beat VMG is unchanged on both classes at every wind (0.0 %), and wm7's best beating angles are unchanged
(42° to 12 kn, 39 to 40° from 14 kn). The best-of-configs beat VMG of wm12 in 6 kn rises 0.9 % (3.50 to 3.53 kn):
the code zero, at 45° TWA, edges out the jib there. Close reaching under the jib got faster in breeze (wm7 at 60°:
+5 to +10 % from 12 kn; wm12 at 60°: +2 to +6 % from 16 kn), towards ORC (wm12 best 60° now within 1 % of the
Farr 40 from 16 kn).

### Code zero crossover (wm12, best config per TWA)

| TWS | jib | code zero | A2 |
| --- | --- | --- | --- |
| 6 kn | to 44° | 45 to 112° | from 112° |
| 8 kn | to 48° | 49 to 108° | from 108° |
| 10 kn | to 54° (and at 58°) | 55 to 110° (a near tie with the jib to 59°) | from 110° |
| 12 kn | to 82° | 82 to 114° | from 114° |
| 16 kn | to 102° | 102 to 120° | from 120° |
| 20 kn | to 111° | 112 to 124° | from 124° |

Before, the code zero won from 62° in 6 kn to 106° in 20 kn and again dead downwind (168 to 180°) in every wind.
Now it never wins running; in light air it is the tight-reaching sail (North Sails 55 to 90° AWA, UK Sailmakers 50
to 125° TWA, ORC Tripp 40 guide 60 to 90° TWA), and from 12 kn the jib takes the tight reach and the code zero only
the narrow broad reach where the A2 is overpowered.

### Tests

VPP pytest, core (`-LE ai_long`) and the game suites pass (the known hud_test "the boat sails" failure aside). The
core irons-recovery margin went from 17 to 17.5 s (spec `boat.md` §10.4; the 20 s target holds): wm12 needs 17.1 s
to half its polar speed at 80°, which is 5 % higher. The `ai_long` AI races do not pass with the new tables (they
pass with the old ones): the match-race cover count (leader covers in 3 or 4 of 5 seeds) and the Solent ebb
overstand (8 to 18 s per windward approach against a limit of 8). Neither expectation encodes a speed; both move
with every variant of the new tables tried, so they are AI behaviour to look at (in one of the failing match seeds
the outside boat at the leeward mark does not give the inside boat room, rule 18.2), not a reason to loosen them.

