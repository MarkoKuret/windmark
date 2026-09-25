---
id: WM-045
title: 'VPP: model follow-ups from the tack fix'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-25 16:33'
updated_date: '2026-09-25 17:28'
labels:
  - vpp
dependencies: []
priority: medium
ordinal: 56000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From WM-027: the turn-radius offset assumes half the rudder angle reaches the blade in a turn (share 0.5) while rudder drag stalls on the full angle (make them consistent); fall_off rates are spec reference values, not a yaw balance; weather_helm tables are still not generated; the wm12 irons recovery (18.35 s against 20 s) has a thin margin.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Rudder share consistent between turn radius and rudder drag
- [x] #2 weather_helm tables generated
- [x] #3 wm12 irons recovery margin at least 3 s
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Rudder drag on the radius law's blade incidence (share 0.5, stall knee at h_s 0.72/0.69, separation over 5 deg, drag cl_max sin(alpha)). weather_helm from the sail plan's yaw moment about the class's balance point (start config close-hauled in 12 kn), as the turn rate of the helm that holds it. accel_rest (drive at rest over the mass) blends into accel below half the target: irons recovery to 50 % wm7 9.85 s, wm12 16.1 s (was 10.95, 18.35). fall_off rates still the spec reference values.
<!-- SECTION:NOTES:END -->
