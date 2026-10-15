---
id: WM-129
title: Cockpit camera further aft with a wider view
status: In Progress
assignee:
  - '@camera'
created_date: '2026-10-15 17:28'
updated_date: '2026-10-15 17:28'
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
- [ ] #1 cameras.md §3 updated first: new eye position rule (aft, per class, clear of wheel/tiller/backstay/lifelines) and wider default fov
- [ ] #2 BoatGeometry and OnboardCamera follow the spec on wm7 and wm12; eye never inside geometry
- [ ] #3 Cameras, controls and UI game tests pass
- [ ] #4 Before/after offscreen stills from the cockpit camera on wm7 and wm12 (upwind jib, downwind kite) in game/tests/previews/cockpit_cam_<boat>_before/after.png
<!-- AC:END -->
