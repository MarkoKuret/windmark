---
id: WM-122
title: >-
  Trim: main on the centreline upwind (traveller to windward in light air),
  eased only when overpowered; main with a kite trimmed to the apparent wind
status: Done
assignee:
  - '@main-trim'
created_date: '2026-10-09 21:34'
updated_date: '2026-10-15 19:13'
labels:
  - physics
  - sails
dependencies: []
priority: high
ordinal: 155000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner (2026-10-09): fully sheeted the main must reach the centreline; today it never does (VPP main optimum 7-11 deg close hauled at 4-8 m/s, 16-21 deg at 14 m/s, and the manual sheet maps full-in jib to that offset). Upwind VMG trim in light and medium air: boom on the centreline, in light air the traveller carries it a little above (to windward). Only when overpowered can easing and letting the main luff be faster. Downwind with a kite the main is eased far too much (main own optimum saturates at sheet_max from about 90 deg AWA, kite_sheet_in 15 deg gives about 59 deg): it must follow the apparent wind as on real boats (asym reaching/running AWA 60-150).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Spec (sails.md, data_format.md if keys change) gives the main's upwind optimum (centreline or slightly to windward until overpowered) and the main-with-kite angle as a function of AWA, with sources
- [x] #2 VPP tables: main close-hauled optimum about 0 (or to windward) in light and medium air on wm7 and wm12, eased only where the VPP finds it faster; main with kite follows AWA; manual sheet fully in puts the main on the centreline (or windward in light air)
- [x] #3 Core tests and AI tests (incl. ai_long) green with the regenerated performance files
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner approved in the game 2026-10-15 (wm12 8/16 kn, wm7 20 kn).
<!-- SECTION:NOTES:END -->
