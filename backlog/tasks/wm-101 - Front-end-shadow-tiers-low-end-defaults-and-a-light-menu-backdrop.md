---
id: WM-101
title: 'Front end: shadow tiers, low-end defaults and a light menu backdrop'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-05 17:12'
updated_date: '2026-10-05 17:28'
labels:
  - performance
dependencies: []
priority: high
ordinal: 138000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
docs/PERFORMANCE.md G1, G7, M1, A9b and measured items 1 and 5: fewer cascades and shorter shadow distance on L and M, hard filter on L, 2048 atlas on M; integrated GPU detected at first launch starts on tier L at 67 % render scale; menu backdrop at 30 fps and 2 boats on L.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Tier L/M shadow settings reduced per the doc; spec water_render.md 7 updated first
- [x] #2 First launch on an integrated GPU picks tier L and 67 % render scale; settings tests cover it
- [x] #3 Menu backdrop lighter on L; menus tests pass
<!-- AC:END -->
