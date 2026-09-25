---
id: WM-044
title: 'VPP: faster slowdown when luffing or let fly, and downwind windage'
status: To Do
assignee: []
created_date: '2026-09-25 16:33'
labels:
  - vpp
dependencies: []
priority: high
ordinal: 55000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From WM-027: with the new coast law a boat with sails let fly or head to wind slows very slowly (wm7 still 0.57 kn after 20 s from 6.6 kn), which matters for starts (holding position, killing speed) and collision avoidance. Add the drag of flogging sails and windage to the no-drive decel, and the windage push downwind with sails let fly (missing from the trim tables). Spec first (boat.md), then VPP, regenerate data/perf. Check the tack times and irons recovery of WM-027 still hold.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 boat.md defines the luffing/let-fly decel and downwind windage
- [ ] #2 wm7 and wm12 slow from close-hauled speed to under 1 kn within about 10 s with let fly
- [ ] #3 WM-027 tack and irons tests still pass
<!-- AC:END -->
