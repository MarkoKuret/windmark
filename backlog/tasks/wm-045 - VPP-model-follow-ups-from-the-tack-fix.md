---
id: WM-045
title: 'VPP: model follow-ups from the tack fix'
status: To Do
assignee: []
created_date: '2026-09-25 16:33'
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
- [ ] #1 Rudder share consistent between turn radius and rudder drag
- [ ] #2 weather_helm tables generated
- [ ] #3 wm12 irons recovery margin at least 3 s
<!-- AC:END -->
