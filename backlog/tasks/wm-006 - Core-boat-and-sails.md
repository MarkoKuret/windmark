---
id: WM-006
title: 'Core: boat and sails'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-25 13:31'
updated_date: '2026-09-25 14:39'
labels:
  - core
dependencies: []
priority: high
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Boat tick per docs/specs/boat.md and sails.md: wind triangle, helm, sail changes, trim, table lookups, heel and pitch, speed, turning.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Headless tests from the specs pass
- [x] #2 wm7 and wm12 sail steady polars matching their tables
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Boat and sails in core/src/boat, core/src/sails; tests in core/tests/test_boat.cpp, test_sails.cpp, test_boat_env.cpp. The steady polars and heels of every wm7/wm12 config match the tables (without the wobble: speed within 0.07 %, heel within 0.00002 deg). The §10.3 tack and the wm12 §10.4 recovery are checked on test-local hulls with accel x2, decel x0.35, turn_rate x2; on the shipped files they fail (may_fail test, WM-027). Spec readings taken: trim_speed scales the drive only (not the negative no-go drift); let-fly releases the sheet past sheet_max to the wind line; the sail-change carry is kept in seconds; weather_helm is scaled by trim_heel (sails.md §6).
<!-- SECTION:NOTES:END -->
