---
id: WM-143
title: 'HUD: no penalty turn ring on the water; the panel turn as plain numbers'
status: Done
assignee:
  - '@hudux'
created_date: '2026-10-16 19:42'
updated_date: '2026-10-16 19:52'
labels:
  - hud
dependencies: []
ordinal: 168000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The owner finds the ring drawn round the boat on the water during a penalty turn ugly. Remove it (hud.md §12.1, §16.4) in every camera; the penalty panel keeps the cue as plain text: the turn in degrees and the tack and gybe marks, no ring graphic.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 hud.md §12.1, §16.1, §16.4 and §15 no longer have the turn on the water; the panel's turn cue is described as plain text
- [x] #2 No ring is drawn round the boat in any camera while a penalty is pending or being sailed
- [x] #3 The penalty panel shows the turn as a number (degrees of 360) with TACK and GYBE marks, no ring
- [x] #4 hud_test and race_hud_test pass (any failure that was there before noted)
<!-- AC:END -->
