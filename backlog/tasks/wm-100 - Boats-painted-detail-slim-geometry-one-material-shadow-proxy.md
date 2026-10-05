---
id: WM-100
title: 'Boats: painted detail, slim geometry, one material, shadow proxy'
status: To Do
assignee: []
created_date: '2026-10-05 17:12'
labels:
  - performance
dependencies: []
priority: high
ordinal: 137000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
docs/PERFORMANCE.md items B1-B6, G3, A7, A7b, A2, A3 and measured item 1/2. Paint flat detail into the baked deck/hull maps (tracks, hatches, non-skid, screws, cleats, small fittings, with baked shading), model only what changes the outline as low-poly (winch ~250 tris, blocks/cleats 40-80), no geometry under a few pixels (halyards, coils, screws). One material and texture atlas per boat. Budgets: LOD0 20-25k tris, LOD1 6-8k from ~15 m, LOD2 1.5-2k to 250 m with halved sail grids, LOD3 <500 beyond. A cheap shadow proxy (hull, mast, sails) casts shadows; hardware never in the shadow pass. Shared compressed tiling textures instead of copies per GLB.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Boatgen and liverybake: flat hardware baked into the deck maps; LOD0 <=25k, LOD1 <=8k, LOD2 <=2k, LOD3 <=500 triangles; <=12 surfaces per boat LOD0, <=3 on LOD1+
- [ ] #2 Shadow proxy mesh per class cast with shadows-only; boat meshes and hardware do not cast
- [ ] #3 Before/after preview frames at chase distance (20-30 m) and close up; boat import and livery tests pass
- [ ] #4 Owner approves the look
<!-- AC:END -->
