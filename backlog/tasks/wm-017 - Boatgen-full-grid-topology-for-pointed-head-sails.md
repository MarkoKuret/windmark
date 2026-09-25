---
id: WM-017
title: 'Boatgen: full grid topology for pointed-head sails'
status: To Do
assignee: []
created_date: '2026-09-25 13:43'
labels:
  - boats
dependencies: []
priority: medium
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jib, code zero and spinnaker heads are collapsed to one point, and the degenerate head triangles are left out of the index buffer. That leaves the head corner vertex (row rows-1, col 0, on both layers) unreferenced, with the fallback (0, 1, 0) normal from the GLB writer. Godot's glTF importer drops unreferenced vertices, so the head corner named in the physics sidecar does not exist in the engine mesh (see game/tests/boat_import_test.gd WARN lines).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every sail grid vertex is referenced by the index buffer (keep the full (rows-1) x (cols-1) x 2 triangles per layer, or reference the head corner)
- [ ] #2 Collapsed head vertices carry the sail layer normal, never the fallback
- [ ] #3 game/tests/run_boat_import_test.sh shows no sail WARN lines
<!-- AC:END -->
