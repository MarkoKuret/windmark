---
id: WM-219
title: 'Ropes: rope-like sheets in every situation (no zig-zag, no rigid-rod look)'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-07 19:54'
updated_date: '2026-11-07 19:54'
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
- [ ] #1 Edge cases reproduced headless with per-frame rope metrics (kink angle, jitter, segment stretch, sag)
- [ ] #2 Spec §11.3 describes the rope model, formulas and constants
- [ ] #3 Native and GDScript reference in parity, GDExtension rebuilt
- [ ] #4 Sweep test over every class fails on kinks, per-frame jumps, stretched or squashed segments and NaNs
- [ ] #5 Per-frame cost within the spec budget, LOD behaviour kept
- [ ] #6 Before/after previews in docs/design/ropes_2026-11-07/
- [ ] #7 Sail visuals, sheets and LOD, UI and boat import suites green
<!-- AC:END -->
