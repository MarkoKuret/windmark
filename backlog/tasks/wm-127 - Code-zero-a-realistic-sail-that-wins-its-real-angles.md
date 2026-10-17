---
id: WM-127
title: 'Code zero: a realistic sail that wins its real angles'
status: In Progress
assignee:
  - '@downwind'
created_date: '2026-10-15 16:45'
updated_date: '2026-10-16 21:12'
labels:
  - physics
  - vpp
  - sails
dependencies: []
priority: medium
ordinal: 160000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner (2026-10-15): the code zero is broken and works at no angle in a realistic way (wm12 VMG diagnostics even pick it dead downwind at 8-10 m/s). Real code zeros are tight-reaching sails: roughly TWA 50-100 in light to medium air, beaten by the A2 deeper and by the jib upwind in breeze. Fix the model (aero coefficients, sheet range, depowering, heel limit) from sourced data so the crossover chart looks like a real racer's.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Spec and VPP README give the code zero's coefficients and crossover with sources
- [x] #2 wm12 crossover: code zero best only on tight reaches in light/medium air, never dead downwind; tests green
<!-- AC:END -->
