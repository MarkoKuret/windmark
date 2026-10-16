---
id: WM-146
title: 'HUD: small turn ring back inside the penalty panel'
status: Done
assignee:
  - '@hudux2'
created_date: '2026-10-16 20:09'
updated_date: '2026-10-16 20:28'
labels:
  - hud
dependencies: []
ordinal: 171000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bring back a small ring gauge for the penalty turn progress inside the penalty panel, with the degrees, cleanly. Nothing on the water: the ring round the boat stays removed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 hud.md §12.1 specifies the in-panel ring
- [x] #2 The panel draws a small ring with the turn progress and the degrees; nothing drawn round the boat in any camera
- [x] #3 race_hud_test checks the ring; render of the panel
<!-- AC:END -->
