---
id: WM-003
title: 'VPP: handling block for feel'
status: To Do
assignee: []
created_date: '2026-09-25 13:31'
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
- [ ] #1 Spec in docs/specs/data_format.md
- [ ] #2 VPP applies and records the multipliers
- [ ] #3 Tests show defaults leave tables unchanged
<!-- AC:END -->
