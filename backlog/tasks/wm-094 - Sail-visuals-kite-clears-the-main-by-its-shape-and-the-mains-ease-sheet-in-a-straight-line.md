---
id: WM-094
title: >-
  Sail visuals: kite clears the main by its shape and the main's ease, sheet in
  a straight line
status: To Do
assignee: []
created_date: '2026-10-05 09:07'
updated_date: '2026-10-09 21:34'
labels:
  - game
  - sails
dependencies: []
priority: high
ordinal: 126000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner (2026-10-05): the kite no longer passes through the main, but the fix bends the kite sheet around the main (WM-089), which is unrealistic: a loaded sheet runs straight from clew to block. The proper fix is the kite's flying shape and how far the main is eased with a kite up, so the clearance comes out naturally, as on real boats. Revisit the 2026-09-30 decision in WM-016.30 (main angle unchanged, local push): decide whether the main's ease with a kite is visual only or also physics/VPP. Related: WM-016.30, WM-090, WM-089.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Spec (sail_visuals.md, and boat.md/sails.md if the main trim changes) says how the main is eased with a kite and the kite's set shape
- [ ] #2 Kite sheets run straight from clew to lead block; no flying sail or sheet passes through the main, the jib or the rig in any config and trim (tested)
- [ ] #3 Owner looks at the kite set on both boats and approves
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner (2026-10-09): the kite's sheet corner (clew) sits at a bad angle, mostly because of the kite's shape itself. A bigger kite is fine (overrides the 2026-09-26 complaint) if real data for comparable boats supports it. The kite sheet must never come close to the boom or the main. Main ease with a kite moves to WM-122 (physics); this task keeps the kite's planform, size, set shape, clew position, sheet lead and the clearance.
<!-- SECTION:NOTES:END -->
