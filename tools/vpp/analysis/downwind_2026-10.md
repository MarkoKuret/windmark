# Downwind and code zero check against ORC (2026-10)

Question: is the boat too slow downwind, are the kite and code zero too close to the jib, and why does the code
zero win at angles where no real crew would fly it? Investigation only; nothing in the model changed.

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
