---
id: WM-191
title: >-
  Kite shape from measured America's Cup surfaces (AC33 asymmetric, IACC
  symmetric series)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-06 21:29'
updated_date: '2026-11-07 19:15'
labels:
  - kite
  - visuals
dependencies: []
ordinal: 212000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The kite's fixed flying shape taken from complete measured 3D surfaces instead of lofted from section numbers: the AC33 benchmark asymmetric (wind-tunnel photogrammetry, AWA 55, Edinburgh DataShare) and the Moore / Lasher-Richards parametric IACC symmetric series (Peart 2022, appendix A). The surface is resampled onto the sail grid by (uc, h) and mapped onto the class corners; the run-time placement (fixed shape, turned whole about the luff) stays. wm7 (asym) and wm21 (sym) only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Spec first: sail_visuals.md 6.5, 4.1 and data_format.md describe the surface source type and its data files; sources cited in 14
- [x] #2 Raw-data check: the AC33 asym and the five symmetric sails rendered alone (three angles, plain shaded) and judged to look like kites before use
- [x] #3 Generator: surface source resampled by (uc, h) onto the class grid with a gentle corner map, depth scaled with chord; measured outline kept; asym run = the reach shape eased; sym series blended by AWA
- [x] #4 Native SailShape and the GDScript reference stay in parity; GDExtension rebuilt
- [x] #5 wm7 (asym) and wm21 (sym) use the surface model; every other class unchanged
- [x] #6 Green: sail visuals tests, parity test, kite tuner test, boatgen pytest, run_ui_tests.sh
- [x] #7 DataShare licence checked; source and licence recorded in docs/THIRD_PARTY.md
- [x] #8 Previews in docs/design/kite_ac_2026-11-06: wm7 AWA 60/95/130 and wm21 TWA 150/180, side, stern and bow quarter, main model left, new right
- [x] #9 Image check of luff, leech, foot and corners (no crease, fold, clew bowl or pinch, no cloth through main or forestay, sheet off the clew sensibly); findings reported honestly
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Third pass (2026-11-07): the pole kite's run rise and eased head taken out; the run sits at the TWA 150 height; the 15 deg forestay turn stays and the forestay clips the lower kite at a dead run on wm9 and wm21.
<!-- SECTION:NOTES:END -->
