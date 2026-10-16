---
id: WM-129
title: Cockpit camera further aft with a wider view
status: Done
assignee:
  - '@camera'
created_date: '2026-10-15 17:28'
updated_date: '2026-10-15 17:35'
labels:
  - game
  - cameras
dependencies: []
priority: high
ordinal: 162000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-10-15: place the cockpit (onboard) camera further back on less zoom so more is seen. Move the helmsman eye aft toward the transom at a natural eye height, scaled per class, clear of the wheel, tiller, backstay and lifelines, and widen the default field of view so the foredeck, both luffs, the bow and some water ahead are in view. Level and stable as specced (cameras.md §3).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 cameras.md §3 updated first: new eye position rule (aft, per class, clear of wheel/tiller/backstay/lifelines) and wider default fov
- [x] #2 BoatGeometry and OnboardCamera follow the spec on wm7 and wm12; eye never inside geometry
- [x] #3 Cameras, controls and UI game tests pass
- [x] #4 Before/after offscreen stills from the cockpit camera on wm7 and wm12 (upwind jib, downwind kite) in game/tests/previews/cockpit_cam_<boat>_before/after.png
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Eye: wm7 x -3.04 -> -3.39 (0.05 loa from transom), z 1.58 -> 1.62 (sitting 1.0 m); wm12 x -4.61 -> -5.12 (0.08 loa aft of wheel hub), z 2.61 -> 2.60. Default fov 65 -> 75 (old saved 65 migrates). Clearance on generated models: side >= 0.99 m, crossing >= 0.35 m. hud_test 'the boat sails' on the core fails on the base commit too (sim, not cameras).
<!-- SECTION:NOTES:END -->
