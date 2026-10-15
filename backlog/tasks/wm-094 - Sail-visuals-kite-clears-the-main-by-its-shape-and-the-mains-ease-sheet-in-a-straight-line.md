---
id: WM-094
title: >-
  Sail visuals: kite clears the main by its shape and the main's ease, sheet in
  a straight line
status: Done
assignee:
  - '@clew'
created_date: '2026-10-05 09:07'
updated_date: '2026-10-15 19:13'
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
- [x] #3 Owner looks at the kite set on both boats and approves
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-10 (@sail-shape): research in sail_visuals.md 14.6 (ORC certificates and class rules: J/70, Melges 24, J/80, Viper 640, RS21, Melges 32, IC37, J/111, J/122E, ClubSwan 36/50; trim guides). Kite planform mid girth 0.88 -> 0.95 SF (references 0.93-1.02); areas wm7 48.5 -> 52.5, wm12 142.5 -> 153.5 m2 (A/SLU2 0.41); data/perf regenerated. 7.5 clew on its sheet: the cloth round the clew turns 0.6 of the way toward the sheet (was 17-50 deg off the corner's bisector, now 4-27). 11.3 lead block on the rail 0.35 s aft of its winch (wm7 1.55 m, wm12 2.75 m forward of the transom; J/70 'outboard of primary winches and aft', Viper 2 m forward of the transom corner). 7.6 the drawn main stops c off the straight kite sheet (presentation only; core angle unchanged): reaching with the main trimmed to the kite nothing stops, running with the main at 51.5 deg (main-trim rule) it is held at about 40 deg (wm7) / 39 (wm12), let fly it never reaches the sheet. 7.4 ease threshold P_e 3c -> 2c (deep pushes against the stopped main popped). Sheets: boom obstacle is the spar only (the vang slab is gone). Test 23 (sail_visuals_test): 648 cases per kite up to let-fly, the straight sheet 0.36 m (wm7) / 0.48 m (wm12) off the main, 0.31 / 0.44 off the boom, no crossings, main never past the core angle, main moves smoothly through a kite sweep with the main let fly. Tests 18-21 pass. Previews: game/tests/previews/kite_set_*_{before,after}.png, kite_letfly_*_{before,after}.png.

2026-10-12 (@sail-shape), after the owner sailed cdb680f: (1) the leech bulge was the 7.5 clew turn (renders with it on and off, mid girth 0.88 and 0.95, P_e 2c and 3c: only the turn bulges); removed. (2) The tack sat 0.12 m above the sprit end and swung on its tack line (tack_line_max 0.04); the rest tack is now the sprit end, tack_line_max 0, the hoist and drop offset of the tack corner is taken out of the cloth round it and the clearance margin fades at the tack: test 24, tack within 0.0000 m of bowsprit_end over trims, hoist, drop and a gybe, native and reference. Areas with the lower tack: wm7 53.5, wm12 a2 155.5, code0 82.0 m2; data/perf regenerated (sprit collision key stripped). (3) Test 18 sweep jump (0.607 m): kite cloth behind the main's leech reached the end of the 2c run-on and flipped round it; run-on 6c, sweep now 0.279 m (limit 0.327; the rest is the kite squeezed between the eased jib and the main). Previews: game/tests/previews/kite_tack_leeward_wm7.png, kite_tack_leeward_wm12.png, kite_set_*_after.png and kite_letfly_*_after.png with the merged main angles.

2026-10-15 (@clew), owner: 'clew angle is bad'. Cause: the set shape's clew corner faced the wind while the sheet runs down and inboard to the quarter block, so the sheet left the corner 10-47 deg (wm7) and 26-53 deg (wm12) off its bisector, mostly out of the cloth's plane; plus a 12-24 deg kink in the leech at the first row (sqrt twist profile). Fix (sail_visuals.md 7.7, 7.3, 7.4): the sheet sets the clew through the shape, solved every update (two Newton steps): draw-in (low rows' chord shortened, the cloth kept as foot camber, the leech leaning out to the shoulder) and draw-down (clew end of the low rows pulled down), faded up to 0.3 of the height, out round the bow (75-105 deg) and in from AWA 45-65; twist profile 1-(1-h)^2.5 (Deparday fit, no kink); obstacle bounds now cover the 6c run-on (a jump in test 18); stale obstacle sections cleared. Result: the sheet within 3.6 deg (wm7) and 6.1 deg (wm12) of the bisector over AWA 60-160, kite 60-130 %, main optimum to let fly. Test 25 (angle <= 12 deg; foot and lower leech fair: turn step <= 3 deg, at most one sign change). Test 20 bound: clew at most 0.05 LOA forward of the mast (wm7 now 0.03 m forward at AWA 89). Kite area unchanged (no perf regeneration). Previews: game/tests/previews/kite_clew_{wm7,wm12}_{before,after}.png.

Owner approved in the game 2026-10-15 (wm12 8/16 kn, wm7 20 kn).
<!-- SECTION:NOTES:END -->
