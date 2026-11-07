---
id: WM-217
title: >-
  Decide: what persists between sessions (race history, personal bests, a player
  name)
status: To Do
assignee: []
created_date: '2026-11-07 18:47'
updated_date: '2026-11-07 19:09'
labels:
  - decide-later
dependencies: []
priority: low
ordinal: 233000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nothing persists but settings: no race history, personal best per venue and class, stats, player name or profile. Opponents are redrawn every race, so there are no recurring rivals. For an early-access single-player loop a small local history (last 20 results, best time per course and class, races and wins per class) gives the results screen a second line ('Your best here: 23:12') and the main menu a reason to come back. Networking will bring a profile; decide whether a local one comes first.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Owner decides scope and timing
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decided 2026-11-07 (recommendation taken): a small local history in user://history.cfg: the last 50 results, the best finishing time per course and class, races and wins per class. The results screen shows 'Your best here' and a new best; no player name or profile until networking.
<!-- SECTION:NOTES:END -->
