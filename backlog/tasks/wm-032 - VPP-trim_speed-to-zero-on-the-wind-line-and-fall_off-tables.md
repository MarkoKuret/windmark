---
id: WM-032
title: 'VPP: trim_speed to zero on the wind line and fall_off tables'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-25 15:24'
updated_date: '2026-09-25 16:30'
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
- [x] #1 trim_speed is 0 on the wind line in wm7 and wm12 tables
- [x] #2 fall_off tables written for both classes and loaded by the core
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
trim_speed and trim_heel are exactly 0 with the driving sail on the wind line (VPP zeroes from the eps point at or below the neighbouring wind-line errors; trim_error axis every 5 deg to 130 deg); checked on a fine grid in core/tests/test_sails.cpp. fall_off written for every config (S 8 deg/s, L 5 deg/s by LWL, 20-60 deg TWA, none below 10 deg, fading to 0 at Fn 0.05 ahead) and loaded by the core; wm12 irons recovery 18.35 s.
<!-- SECTION:NOTES:END -->
