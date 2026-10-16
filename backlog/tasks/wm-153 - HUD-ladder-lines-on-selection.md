---
id: WM-153
title: 'HUD: ladder lines on selection'
status: Done
assignee:
  - '@hudux2'
created_date: '2026-10-16 20:09'
updated_date: '2026-10-16 20:28'
labels:
  - hud
dependencies: []
ordinal: 178000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
With a boat selected, draw the viewed boat's ladder line and the selected boat's (perpendicular to the wind for the leg) on the water: own in yellow, hers neutral; the gain or loss in boat lengths. Hidden with nothing selected.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 hud.md specifies the ladder lines (no ladder lines existed before)
- [x] #2 Two lines through the boats perpendicular to the wind, own in mark, hers in paper, with the distance between them; none without a selection
- [x] #3 race_hud_test checks the lines' direction and the gap
<!-- AC:END -->
