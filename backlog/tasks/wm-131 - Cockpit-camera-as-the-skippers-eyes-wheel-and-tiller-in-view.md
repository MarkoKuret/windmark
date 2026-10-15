---
id: WM-131
title: Cockpit camera as the skipper's eyes (wheel and tiller in view)
status: Done
assignee:
  - '@camera'
created_date: '2026-10-15 17:38'
updated_date: '2026-10-15 17:44'
labels:
  - game
  - cameras
dependencies: []
priority: high
ordinal: 163000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-10-15 follow-up to WM-129: on wm12 see the steering wheel in the cockpit cam; on both boats show what the skipper would see. wm12: helmsman at the wheel on the windward side, just behind or beside the rim, looking forward past it. wm7: helmsman sitting on the windward side deck just forward of the tiller end, holding the extension.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 cameras.md §3 updated first: helmsman positions and eye heights per steering type
- [x] #2 wm12 wheel rim and top in the lower part of the frame; wm7 at the tiller end on the windward deck; view level, clear of geometry
- [x] #3 Own wheel and tiller are drawn for the onboard camera (near plane, layers, LOD checked)
- [x] #4 cameras_test (5b) and UI tests pass
- [x] #5 Before/after stills game/tests/previews/cockpit_cam_<boat>_skipper_before/after.png, upwind and downwind
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
wm7: eye x -3.39 -> -2.79 (tiller tip + 0.15), y 0.95 -> 1.06 (0.9 half-beam), z 1.62 -> 1.43 (seated 0.80); look_down 4 deg. wm12: x -5.12 -> -4.77 (hub - 0.7 R, R 0.88), y 1.34 -> 0.49 (0.55 R), z 2.60 -> 2.15 (standing 1.60 on cockpit floor); look_down 8 deg. fov 75 kept. Nothing hid the wheel/tiller (near 0.1 m, no layers, LOD0 at the eye): they were out of frame. hud_test 'the boat sails' fails on the base too.
<!-- SECTION:NOTES:END -->
