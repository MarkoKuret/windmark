---
id: WM-180
title: >-
  Race load: lazy pause and results screens, baked venue build, livery means in
  the sidecar
status: To Do
assignee: []
created_date: '2026-10-17 14:33'
updated_date: '2026-11-07 19:37'
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
- [x] #1 Race scene build from engine start with 16 boats measured before and after, in PERFORMANCE.md
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-07 (branch loading, with WM-206): pause menu card and settings panel, and the results screen's controls, built on first open. Race build before/after in PERFORMANCE.md 'Loading behind the fade': Start race 518 to 468 ms, Race again 466 to 408 ms, cold 1190 to 1108 ms (headless). Left: the venue build baked per venue (about 215 ms), the livery texture means in the sidecar (part of the 105 ms of boat views), the cloth tiles to compress mode 2 (A9a), and the pause and results scripts still compile with the scene on a cold start (120 to 175 ms when nothing loaded them).
<!-- SECTION:NOTES:END -->
