---
id: WM-069
title: 'Front end: render scale setting and frame-time overlay'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-29 22:07'
updated_date: '2026-09-29 22:20'
labels:
  - front-end
  - performance
dependencies: []
priority: high
ordinal: 97000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The owner's MacBook Air M1 struggles to run the game. Add a render scale setting (3D rendered below native resolution and upscaled, HUD at native) and a frame-time overlay with a per-second CSV logger, so a windowed run can be measured and the cost found.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 menus.md §3 and water_render.md §7 specify render scale (Auto, 50 to 100 %, the upscaler, Auto's rule)
- [x] #2 Settings stores render_scale and applies it to the root viewport's scaling_3d_mode and scaling_3d_scale; the settings panel has the row
- [x] #3 Menus test: render scale round-trips, applies to the viewport, Auto resolves as specified
- [x] #4 Frame-time overlay (key toggle, --perf) shows FPS, frame time avg and 1 % worst, CPU, GPU render time, draw calls, primitives and the per-section timings
- [x] #5 --perf-log=PATH writes one CSV line per second, --perf-seconds=N quits after N seconds; flags and the Mobile renderer comparison documented in game/README.md
- [x] #6 Headless test runs the overlay and the CSV logger; UI and menus tests pass
<!-- AC:END -->
