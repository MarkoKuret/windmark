---
id: WM-065
title: 'Boatgen: kite preview and sidecar follow the game''s set kite shape'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-26 12:30'
updated_date: '2026-09-29 21:40'
labels:
  - boats
dependencies:
  - WM-064
priority: high
ordinal: 91000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From WM-016.30 phase 1: the game now uses the look key camber (0.26 kites, 0.12 code zero, height profile, chord shortened to keep the cloth length) and a clearance rule (sail_visuals.md 7.4: margin 0.042 LOA, ease about the luff, then a smooth push-off). boatgen still writes depth: 0.3 in the sidecar look blocks, and kite_preview and the boatgen preview poses still draw the old deep kite. Write camber, and make the preview poses and kite_preview use the same shape and clearance (shared formulas or a parity check against game/scripts/sail_shape_ref.gd).

Note from WM-063 (2026-09-26): the VPP's kite optimum (wm7, 10 kn: 15 deg to AWA 60, 22 at 70, 32 at 80, 42 at 90, 64 from 120) is measured from the sprit-end tack, about 4.2 m ahead of the mast, while the main pivots at the gooseneck; at 18 deg the clew is still about 0.5 m outboard of the main. The drawn kite should pivot about the sprit-end tack; check whether the game's clearance ease (40 to 47 deg) is partly compensating a wrong pivot in the drawing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Sidecar look blocks write camber per sail_visuals.md 4
- [x] #2 kite_preview and boatgen previews match the game's set kite within a small tolerance
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-09-29: sidecar look blocks write camber (0.12 code zero, 0.26 spinnakers; an old depth key is read and dropped). New tools/boatgen/boatgen/sail_set.py ports the game's up shapes, placement and 7.4 clearance; the build's preview poses and kite_preview use it at the core's optimum angles, and the build writes <id>.sets.json. sail_visuals.md 12 test 19 (game/tests/sail_visuals_test.gd): BoatView native and reference within 0.4 mm of the generator on wm7, wm12 and test_sym (tolerance 10 mm). Pivot checked: the kite already turns about its luff through the sprit-end tack (documented in 7.3). The large reach ease (31 deg wm7, 35 deg wm12 at AWA 80) comes from the main at 53 deg pushing the kite's upper leech (0.27 m through the main); it swings the clew 1 m forward of the mast and 4.4 m outboard, a likely next fix for the owner's 'can be better'. Previews rendered at 4x MSAA (this GL context allows 4, the renderer asks for 8).
<!-- SECTION:NOTES:END -->
