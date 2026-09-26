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
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Sidecar look blocks write camber per sail_visuals.md 4
- [ ] #2 kite_preview and boatgen previews match the game's set kite within a small tolerance
<!-- AC:END -->
