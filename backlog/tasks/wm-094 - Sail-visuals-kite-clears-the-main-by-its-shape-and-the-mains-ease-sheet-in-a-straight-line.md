---
id: WM-094
title: >-
  Sail visuals: kite clears the main by its shape and the main's ease, sheet in
  a straight line
status: In Progress
assignee:
  - '@sail-shape'
created_date: '2026-10-05 09:07'
updated_date: '2026-10-11 11:59'
labels:
  - game
  - sails
dependencies: []
priority: high
ordinal: 126000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner (2026-10-05): the kite no longer passes through the main, but the fix bends the kite sheet around the main (WM-089), which is unrealistic: a loaded sheet runs straight from clew to block. The proper fix is the kite's flying shape and how far the main is eased with a kite up, so the clearance comes out naturally, as on real boats. Revisit the 2026-09-30 decision in WM-016.30 (main angle unchanged, local push): decide whether the main's ease with a kite is visual only or also physics/VPP. Related: WM-016.30, WM-090, WM-089.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Spec (sail_visuals.md, and boat.md/sails.md if the main trim changes) says how the main is eased with a kite and the kite's set shape
- [x] #2 Kite sheets run straight from clew to lead block; no flying sail or sheet passes through the main, the jib or the rig in any config and trim (tested)
- [ ] #3 Owner looks at the kite set on both boats and approves
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-10 (@sail-shape): research in sail_visuals.md 14.6 (ORC certificates and class rules: J/70, Melges 24, J/80, Viper 640, RS21, Melges 32, IC37, J/111, J/122E, ClubSwan 36/50; trim guides). Kite planform mid girth 0.88 -> 0.95 SF (references 0.93-1.02); areas wm7 48.5 -> 52.5, wm12 142.5 -> 153.5 m2 (A/SLU2 0.41); data/perf regenerated. 7.5 clew on its sheet: the cloth round the clew turns 0.6 of the way toward the sheet (was 17-50 deg off the corner's bisector, now 4-27). 11.3 lead block on the rail 0.35 s aft of its winch (wm7 1.55 m, wm12 2.75 m forward of the transom; J/70 'outboard of primary winches and aft', Viper 2 m forward of the transom corner). 7.6 the drawn main stops c off the straight kite sheet (presentation only; core angle unchanged): reaching with the main trimmed to the kite nothing stops, running with the main at 51.5 deg (main-trim rule) it is held at about 40 deg (wm7) / 39 (wm12), let fly it never reaches the sheet. 7.4 ease threshold P_e 3c -> 2c (deep pushes against the stopped main popped). Sheets: boom obstacle is the spar only (the vang slab is gone). Test 23 (sail_visuals_test): 648 cases per kite up to let-fly, the straight sheet 0.36 m (wm7) / 0.48 m (wm12) off the main, 0.31 / 0.44 off the boom, no crossings, main never past the core angle, main moves smoothly through a kite sweep with the main let fly. Tests 18-21 pass. Previews: game/tests/previews/kite_set_*_{before,after}.png, kite_letfly_*_{before,after}.png.
<!-- SECTION:NOTES:END -->
