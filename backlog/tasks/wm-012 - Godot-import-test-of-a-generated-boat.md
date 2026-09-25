---
id: WM-012
title: Godot import test of a generated boat
status: Done
assignee:
  - '@claude'
created_date: '2026-09-25 13:31'
updated_date: '2026-09-25 13:43'
labels:
  - game
  - boats
dependencies: []
priority: medium
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Load a boatgen GLB in Godot, check materials, moving parts and scale; headless import only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Import report with any fixes needed in boatgen
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Headless import of wm12 and wm7 is clean (no import errors or warnings). Axes, scale, node set, pivots, materials (StandardMaterial3D, shared per slot, tiling_m kept as metadata), collision (-convcolonly gives StaticBody3D + ConvexPolygonShape3D) and triangle counts all pass: game/tests/run_boat_import_test.sh. Godot re-indexes mesh vertices on import, so the sail grid order is recovered from uv1 (game/scripts/sail_grid.gd). Boatgen fixes: WM-017 (pointed-head sails leave the head corner unreferenced, Godot drops it), WM-018 (document the re-indexing and the uv1 key).
<!-- SECTION:NOTES:END -->
