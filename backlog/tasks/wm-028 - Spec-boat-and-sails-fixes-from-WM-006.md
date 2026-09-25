---
id: WM-028
title: 'Spec: boat and sails fixes from WM-006'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-25 14:41'
updated_date: '2026-09-25 16:30'
labels:
  - spec
dependencies: []
priority: high
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Boat.md 5.8 surfing factor from wave pitch only (not the wobble); trim_speed scales drive only, keeping no-go drift sternway; sails.md 5.3/5.4 let-fly releases past sheet_max to the wind line; sails.md 4.3 carry leftover time in seconds; boat.md 5.5 weather_helm uses trim_heel; 10.1 start at table speed; cog defined from the filtered ground velocity; calm placement uses given wind_from; drop_front() cancels a first hoist; hull_points max 64; peel test 'exactly' means within one tick. Also the tack law proposals in WM-027 (coast before drifting, class-scaled turn offset, reference retune, slammed tacks).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 boat.md and sails.md match the implementation
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
boat.md, sails.md, data_format.md 4 (and the perf axes of 5) updated and the core follows: coast before drifting, trim scales the drive only, surf from wave pitch only (core changed), let-fly past sheet_max, carry in seconds, weather_helm x trim_heel, 10.1 starts at table speed, cog from the filtered ground velocity (core changed), calm placement direction, drop_front() cancels a first hoist (core + test), hull_points 1 to 64 (loader), peel 'exactly' = within one tick, beta_t sail output (core), stall-shaped radius law, retuned decel/accel/tack references, CONTACT_KEEP reference to collisions.md 4.
<!-- SECTION:NOTES:END -->
