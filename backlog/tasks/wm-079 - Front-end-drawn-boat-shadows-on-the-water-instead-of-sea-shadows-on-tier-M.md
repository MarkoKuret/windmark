---
id: WM-079
title: 'Front end: drawn boat shadows on the water instead of sea shadows on tier M'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-01 10:17'
updated_date: '2026-10-01 10:46'
labels:
  - front-end
  - performance
dependencies: []
ordinal: 109000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Letting the sea receive sun shadows costs about 4 ms per frame on tier M (owner's M1, 2880x1800, 10 boats), whatever the shadow distance or filter. Owner decision 2026-10-01: on tier M the sea takes no real shadows (as tier L); a cheap drawn shadow of each nearby boat is drawn on the water instead (water_render.md §4.6, §4.7). Tier H keeps real sea shadows.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Spec: water_render.md §4.6, §4.7, §7 and §9 describe the drawn shadows and the tiers
- [x] #2 Tier M sea takes no shadows (water_m defines WM_NO_SHADOWS, tier table sea_shadows false)
- [x] #3 Drawn shadow per boat: hull, mast and sails projected along the sun, soft-edged, darkening matched to the real shadows, not over the hull
- [x] #4 Per-boat geometry native (BoatShadowShape) with the GDScript reference; well under 0.3 ms CPU for 10 boats
- [x] #5 Headless test: own boat shadow at tier M lies on the water, away from the sun, covers hull and sails within tolerance; none at tier H
- [x] #6 run_water_test.sh, run_ui_tests.sh and run_sail_visuals_test.sh pass
- [x] #7 Run-only measuring switch --no-drawn-shadows in the sail scene, documented in game/README.md
- [x] #8 Offline preview renders tier H real against tier M drawn shadows
- [x] #9 Tier M drops the per-pixel slope of faded waves (WM_FADED_SLOPE on water_h only, spec §7), before/after preview
<!-- AC:END -->
