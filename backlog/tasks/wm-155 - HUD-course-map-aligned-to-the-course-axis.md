---
id: WM-155
title: 'HUD: course map aligned to the course axis'
status: In Progress
assignee:
  - '@hudux2'
created_date: '2026-10-16 20:13'
labels:
  - hud
dependencies: []
ordinal: 180000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The course map is not north up: the course axis (start to the first windward mark) points up the screen, fixed for the race.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 hud.md §8.1 updated
- [ ] #2 The map's up is the course axis; the north tick and the wind arrow turn with it
- [ ] #3 race_hud_test checks the orientation; render
<!-- AC:END -->
