---
id: WM-154
title: >-
  HUD: no target speed; optimum VMG angle on the TWA dial with a coloured
  pointer
status: Done
assignee:
  - '@hudux2'
created_date: '2026-10-16 20:13'
updated_date: '2026-10-16 20:28'
labels:
  - hud
dependencies: []
ordinal: 179000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Drop the speed / target speed metric everywhere in the HUD (keep plain boat speed). On the TWA dial make the upwind and downwind polar VMG optima for the present TWS clearly visible and colour the true wind pointer by how close the TWA is to the optimum, a smooth gradient from green to red. Replaces the knots-against-targets rule.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 hud.md §4, §16.1, §16.3 and hud_direction.md updated
- [x] #2 No target speed text or cell anywhere in the HUD
- [x] #3 The dial marks both optima and the TWA pointer goes green on the optimum to red far off
- [x] #4 race_hud_test checks it; render
<!-- AC:END -->
