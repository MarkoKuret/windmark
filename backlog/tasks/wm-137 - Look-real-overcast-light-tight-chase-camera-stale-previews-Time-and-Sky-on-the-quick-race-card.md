---
id: WM-137
title: >-
  Look: real overcast light, tight chase camera, stale previews, Time and Sky on
  the quick race card
status: Done
assignee:
  - '@claude'
created_date: '2026-10-16 19:14'
updated_date: '2026-10-16 19:32'
labels:
  - front-end
  - look
dependencies: []
ordinal: 165000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner decisions 2026-10-16: overcast becomes diffuse light (soft faint shadows, grey sea, no glitter); the chase camera follows without lag (no spring, no speed trail); stale previews removed; the quick race card sets GameSetup.light_time and light_conditions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Overcast: sun shadows soft and faint, sea greyer and darker with no glitter, puffs still read; spec in water_render.md, daylight_conditions.jpg re-rendered
- [x] #2 Chase camera follows at least as tightly as before the cinematic pass, no speed trail; cameras.md, F9 row and tests updated
- [x] #3 Stale cine and daylight previews deleted or re-rendered, references removed
- [x] #4 Quick race card has Time and Sky rows (Surprise with Random weather); menus.md and menus_test updated
- [x] #5 run_ui_tests, run_water_test, run_menus_test pass (known hud_test failure aside)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Overcast: sun 0.04 of the hour's behind a diffuse grey deck (cloud_diffuse), grey sky ramp brighter overhead dimmed by the sun's height, exposure x1.6, sun shadow blur x4, drawn shadows 0.10, sea body saturation 0.5 value 0.85, puff factor 2.4 (puff contrast offline: aerial fair -9.4 %, overcast -9.2 %; chase -2.6 / -2.7 %), grade contrast -0.06. Chase camera: first-order heading follow (tau_yaw 0.35 s, lag at most 0.35 s in a steady turn), no trail, no heel lean (it followed a smoothed heel), bank kept; F9 row Chase bank, --chase-bank. Previews: cine_*.jpg deleted, daylight_*.jpg re-rendered. Quick race and free sail cards: Time and Sky rows, Surprise with Random, Light briefing line, Continue keeps the light. Tests: ui (known hud_test failure only), water, menus pass. The engine picture of the overcast needs the owner's windowed check.
<!-- SECTION:NOTES:END -->
