---
id: WM-084
title: 'Front end: anti-aliasing and distance haze'
status: To Do
assignee: []
created_date: '2026-10-03 17:16'
labels:
  - front-end
  - look
dependencies: []
priority: high
ordinal: 114000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two cheap look gaps found 2026-10-03. (1) No anti-aliasing is set anywhere (project.godot has no MSAA, TAA or FXAA, so Godot's defaults leave it off): masts, stays, sheets, sail edges and the horizon stair-step and shimmer. Owner decision 2026-10-03: keep it simple, SMAA on every tier, no per-tier choice (fall back to FXAA only if SMAA does not fit tier L). (2) The fair preset's exponential fog (4e-5 /m) is about 4 % at 1 km and 33 % at 10 km, so the race area has almost no aerial perspective and reads flat. Try a depth haze that starts a few hundred metres out and reaches about 60 % at the horizon, horizon coloured, keeping the WM-080 sky and sea colours. Spec first (water_render.md §4.5 and §7).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Spec sets SMAA on every tier and the haze curve per weather preset, with constants
- [ ] #2 Rigging and sail edges stop shimmering in a moving headless preview on every tier
- [ ] #3 Before/after preview renders at the chase camera and at 1, 3 and 10 km show the added depth; the owner approves the look
- [ ] #4 Frame cost per tier measured; tier M stays within the Deck budget
<!-- AC:END -->
