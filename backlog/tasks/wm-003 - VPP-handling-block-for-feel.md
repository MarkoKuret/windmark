---
id: WM-003
title: 'VPP: handling block for feel'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-25 13:31'
updated_date: '2026-09-25 14:08'
labels:
  - vpp
  - spec
dependencies: []
priority: high
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Optional per-class handling multipliers (accel, decel, turn_rate, heel, tack_time; default 1.0) applied when the VPP writes the tables and recorded in the perf file. Feel only, never top speed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Spec in docs/specs/data_format.md
- [x] #2 VPP applies and records the multipliers
- [x] #3 Tests show defaults leave tables unchanged
<!-- AC:END -->
