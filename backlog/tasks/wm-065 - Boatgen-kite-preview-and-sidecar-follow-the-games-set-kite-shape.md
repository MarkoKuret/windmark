---
id: WM-065
title: 'Boatgen: kite preview and sidecar follow the game''s set kite shape'
status: To Do
assignee: []
created_date: '2026-09-26 12:30'
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
- [ ] #1 Sidecar look blocks write camber per sail_visuals.md 4
- [ ] #2 kite_preview and boatgen previews match the game's set kite within a small tolerance
<!-- AC:END -->
