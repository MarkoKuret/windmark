---
id: WM-132
title: 'Water: wind roughness follows the wind (Cox-Munk slope variance)'
status: In Progress
assignee:
  - '@sea-look'
created_date: '2026-10-15 18:00'
updated_date: '2026-10-15 18:12'
labels:
  - front-end
  - visuals
dependencies: []
priority: high
ordinal: 164000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Sea surface reads ~10 kn at 25 kn: glossy, long streaky sky reflections. Scale the small-scale slope (detail normal strength, glint, roughness) with the local wind by the Cox-Munk slope variance (sigma^2 = 0.003 + 0.00512 U), so 25 kn reads rough and 8 kn stays glossy. water_render.md 4.1-4.3. Uniform-level cost only, tiers L/M/H kept.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Spec 4.1-4.3 gives the Cox-Munk law and the mapping to detail strength and roughness
- [x] #2 Shader and CPU mirror follow it on every tier, no extra texture taps
- [x] #3 Before/after previews at 8, 15, 25 kn (chase, aerial) in game/generated/sea_look
- [x] #4 Water tests green, cost proxy unchanged within noise
<!-- AC:END -->
