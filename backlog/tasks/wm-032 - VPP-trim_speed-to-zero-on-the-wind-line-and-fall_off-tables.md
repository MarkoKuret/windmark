---
id: WM-032
title: 'VPP: trim_speed to zero on the wind line and fall_off tables'
status: To Do
assignee: []
created_date: '2026-09-25 15:24'
labels:
  - vpp
dependencies:
  - WM-027
priority: high
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Known issues from WM-006 not covered by WM-027 acceptance: trim_speed levels off at about 0.41 on the wind line (should reach 0), and the VPP writes no fall_off tables, so recovery from irons has no table to use. Fix in tools/vpp and regenerate data/perf.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 trim_speed is 0 on the wind line in wm7 and wm12 tables
- [ ] #2 fall_off tables written for both classes and loaded by the core
<!-- AC:END -->
