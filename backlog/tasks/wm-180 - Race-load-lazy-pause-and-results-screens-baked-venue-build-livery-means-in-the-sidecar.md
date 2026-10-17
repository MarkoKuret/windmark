---
id: WM-180
title: >-
  Race load: lazy pause and results screens, baked venue build, livery means in
  the sidecar
status: To Do
assignee: []
created_date: '2026-10-17 14:33'
labels: []
dependencies: []
priority: low
ordinal: 204000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Measured 2026-10-17 at scene build: pause menu plus results screens 222 ms (load on first open), venue build 192 ms (terrain mesh and trees in GDScript: bake per venue), boat views and liveries 124 ms (texture means from a GPU readback: boatgen or liverybake could write them to the sidecar). Also A9a: cloth tiles to compress mode 2 in liverybake (about 3 MB VRAM).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Race scene build from engine start with 16 boats measured before and after, in PERFORMANCE.md
<!-- AC:END -->
