---
id: WM-131
title: Cockpit camera as the skipper's eyes (wheel and tiller in view)
status: In Progress
assignee:
  - '@camera'
created_date: '2026-10-15 17:38'
updated_date: '2026-10-15 17:38'
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
- [ ] #1 cameras.md §3 updated first: helmsman positions and eye heights per steering type
- [ ] #2 wm12 wheel rim and top in the lower part of the frame; wm7 at the tiller end on the windward deck; view level, clear of geometry
- [ ] #3 Own wheel and tiller are drawn for the onboard camera (near plane, layers, LOD checked)
- [ ] #4 cameras_test (5b) and UI tests pass
- [ ] #5 Before/after stills game/tests/previews/cockpit_cam_<boat>_skipper_before/after.png, upwind and downwind
<!-- AC:END -->
