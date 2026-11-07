---
id: WM-219
title: 'Ropes: rope-like sheets in every situation (no zig-zag, no rigid-rod look)'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07 19:54'
updated_date: '2026-11-07 20:45'
labels: []
dependencies: []
ordinal: 235000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Drawn running rigging (sheets, kite sheet and lazy sheet, tack line and guy, halyard tails) zig-zags and looks like steel rods with joints in edge cases: kite upwind, hoist and drop, gybes. Make them behave like real ropes: taut straight, slack catenary, smooth in time, pay out instead of going rigid. Spec docs/specs/sail_visuals.md §11.3.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Edge cases reproduced headless with per-frame rope metrics (kink angle, jitter, segment stretch, sag)
- [x] #2 Spec §11.3 describes the rope model, formulas and constants
- [x] #3 Native and GDScript reference in parity, GDExtension rebuilt
- [x] #4 Sweep test over every class fails on kinks, per-frame jumps, stretched or squashed segments and NaNs
- [x] #5 Per-frame cost within the spec budget, LOD behaviour kept
- [x] #6 Before/after previews in docs/design/ropes_2026-11-07/
- [x] #7 Sail visuals, sheets and LOD, UI and boat import suites green
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Cause: the analytic sheets were redrawn from scratch each frame: the flogging whip (1.5 m wave) fell between rings 0.5 to 1.3 m apart and drew a zig-zag of metres; the deck clamp turned a sag along the rail into a square wave; every jump of a clew, route or role (pole guy/sheet) jumped the whole line; the drape threw a ring metres up next to a clew under the rail. Now a damped Verlet rope follows a smooth hanging shape (sail_visuals.md 11.3 Rope), test 29 sweeps every class. Pre-existing on main: hud_test 'sail test scene on the core' 4 failures (same with the old ropes).
<!-- SECTION:NOTES:END -->
