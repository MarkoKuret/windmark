---
id: WM-019
title: 'Spec: fixes found in core setup'
status: To Do
assignee: []
created_date: '2026-09-25 13:55'
labels:
  - spec
dependencies: []
priority: high
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From WM-005: stiffness bound on heel_k1*DT and pitch_k1*DT in (0,1]; sail order = class file sails[] order (make perf sails an array or state it) and whether a front-sail index counts the main; optimal_angle keyed by sail id; value ranges for pole_angle, shiver_angle, sheet_max_by_heel, slow_*, decel_*, rudder_drag_*, hull_points, optional start block, required front-sail handling keys and pole_rate; coverage rule wording; list the vpp block as informational in data_format.md section 4; add the extra check values atan(2)=3F8DB70D, asin(0.9)=3F8F549C, exp(1)=402DF854.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 boat.md stiffness rule fixed
- [ ] #2 data_format.md covers order, keys and ranges
- [ ] #3 conventions.md has the extra check values
<!-- AC:END -->
