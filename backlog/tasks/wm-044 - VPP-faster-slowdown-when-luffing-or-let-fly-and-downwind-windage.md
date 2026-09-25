---
id: WM-044
title: 'VPP: faster slowdown when luffing or let fly, and downwind windage'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-25 16:33'
updated_date: '2026-09-25 17:42'
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
- [x] #1 boat.md defines the luffing/let-fly decel and downwind windage
- [x] #2 With let fly from close-hauled at 10 kn, wm7 (S) is under 1 kn within 12 s and wm12 (L) within 20 s (owner accepted the size-dependent target on 2026-09-25: wm7 8.3 s, wm12 15.7 s)
- [x] #3 WM-027 tack and irons tests still pass
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Flogging sails (CD_flog 0.30 vs luffing 0.06) brake the coast with free sheets (let fly or manual sheet eased): flog_drag(aws, awa) x (1 - trim_speed); downwind the let-fly share of trim_speed (running 10 kn with the jib about 0.7 of the polar). Let fly close-hauled at 10 kn, under 1 kn: wm7 8.3 s (was 14.7 s), wm12 15.7 s (was 29.7 s). AC2 open for wm12: a 12 m boat has half the sail area per tonne and carries its way about twice as long; reaching 10 s would need a flogging drag coefficient around 0.6, beyond flag-drag data. Owner decision.
<!-- SECTION:NOTES:END -->
