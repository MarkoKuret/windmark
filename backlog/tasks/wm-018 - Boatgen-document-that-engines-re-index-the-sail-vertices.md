---
id: WM-018
title: 'Boatgen: document that engines re-index the sail vertices'
status: To Do
assignee: []
created_date: '2026-09-25 13:43'
labels:
  - boats
dependencies: []
priority: low
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The sidecar promises row-major sail vertex order. That holds in the GLB file, but Godot re-indexes every mesh on import (vertices in order of first use by the triangles). The game recovers the grid node from uv1 (chord fraction, 1 - height fraction, mirrored on the starboard layer) and the layer side (game/scripts/sail_grid.gd). Make this a documented contract instead of an accident, or write an explicit grid attribute.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 tools/boatgen/README.md and the sidecar vertex_order text say the order holds in the file only, and that uv1 plus the layer side is the stable key (or a TEXCOORD_2 grid attribute is added and documented)
- [ ] #2 uv1 on sails stays exact grid fractions (tested)
<!-- AC:END -->
