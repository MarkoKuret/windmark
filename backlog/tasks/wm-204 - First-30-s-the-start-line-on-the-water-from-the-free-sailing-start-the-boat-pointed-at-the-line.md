---
id: WM-204
title: >-
  First 30 s: the start line on the water from the free-sailing start, the boat
  pointed at the line
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07 18:47'
updated_date: '2026-11-07 19:53'
labels:
  - playability
dependencies: []
priority: high
ordinal: 220000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The race opens with 30 s of 'WARNING IN' and nothing else: the start line is drawn only from the warning signal (course_view.gd ~455), no next mark, and the boat spawns reaching away from the line at TWA 100 (world.cpp ~46). A new player has no idea where the line is. Draw the line from the first frame and spawn with the bow towards the line area (or show the line marker). Pairs with WM-199 key hints.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The start line and the committee boat are visible from the first frame of a quick race
- [x] #2 The player's boat spawns with the line in view of the chase camera
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Start line drawn white from the first frame (free sailing included, course_view.gd, hud.md 9.3); committee boat and pin on the water from bind. Spawn (race.md 3.5, world.cpp, race.cpp): port tack at TWA -60 (30 deg towards the line, along it towards the starboard end B), slots from beyond the port end A towards B, none beyond B, so every boat has the line ahead. Starboard-tack variants were tried: with the old slot order (from beyond A) the line is behind the boat. AI fleet stats (15 seeds, 10 Intermediate): contacts/race 1.47 -> 2.47, penalties/boat 0.24 -> 0.44, start delay 15.7 -> 11.3 s; all ai_races targets pass. Scripted full race (test_full_race) seed 20260925 -> 20260926 (the old seed's scripted collisions changed with the spawn). Tests: test_world (heading towards the line), test_race (no slot beyond B), course_land_test (first frame: line white, committee boat, boat behind the line heading to it, line in the 16:9 chase frustum; every boat of the 6-boat race heading to the line).
<!-- SECTION:NOTES:END -->
