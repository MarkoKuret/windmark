---
id: WM-144
title: 'HUD: cleaner course map'
status: Done
assignee:
  - '@hudux'
created_date: '2026-10-16 19:42'
updated_date: '2026-10-16 19:52'
labels:
  - hud
dependencies: []
ordinal: 169000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Make the course map (hud.md §8.1) simpler and clearer: plain buoy symbols with their names, one zone circle (the next step's) instead of one per mark, the own boat clearly apart from the fleet (fleet without a rules relation muted), and less clutter. Next leg highlighted; no new decoration.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 hud.md §8.1 describes the new marks, labels, zone circle and boat styling
- [x] #2 Rounding marks are round buoys with their name beside them; the next step's in mark colour, others in paper
- [x] #3 Only the next step's zone circle is drawn
- [x] #4 Own boat larger in mark colour with an ink outline, fleet boats without a relation muted paper; rules colours unchanged
- [x] #5 race_hud_test course map checks pass; a headless render of the map is made
<!-- AC:END -->
