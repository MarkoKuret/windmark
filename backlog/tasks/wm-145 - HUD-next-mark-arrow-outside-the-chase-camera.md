---
id: WM-145
title: 'HUD: next-mark arrow outside the chase camera'
status: In Progress
assignee:
  - '@hudux'
created_date: '2026-10-16 19:42'
labels:
  - hud
dependencies: []
ordinal: 170000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
In the onboard, aerial and free cameras the player loses where the next mark is. Add a clean screen-space arrow, fixed above the helm strip, that points to the next mark in the camera's view (up = the camera's forward direction on the water) with the mark's name and distance (§1 format). Hidden in the chase camera (the mark tag and the edge pointer do the job there); in the other cameras it replaces the mark's edge pointer.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 hud.md §7 and §16.4 specify the arrow: cameras, placement, direction, text, assist/density rules
- [ ] #2 The arrow is drawn in onboard, aerial and free cameras and not in chase; it points to the mark (tested for a mark ahead, to the right and behind)
- [ ] #3 Outside chase the mark's off-screen edge pointer is not drawn (the arrow replaces it)
- [ ] #4 race_hud_test passes; headless renders in chase and one other camera
<!-- AC:END -->
