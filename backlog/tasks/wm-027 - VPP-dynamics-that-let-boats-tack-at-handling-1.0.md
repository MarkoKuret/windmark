---
id: WM-027
title: 'VPP: dynamics that let boats tack at handling 1.0'
status: To Do
assignee: []
created_date: '2026-09-25 14:34'
labels:
  - vpp
dependencies: []
priority: high
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in WM-006. On the boat model of boat.md the shipped wm7 and wm12 cannot tack. wm7 fails at every helm from 0.5 to 1.0 at 6, 10, 16 and 22 kn TWS. wm12 only gets round at 10 kn with full helm (55.7 s back to 90 % speed) and fails at every other helm and wind speed tested. Inside the no-go zone the decel law pulls v toward the negative polar (about -0.12*TWS) at decel_linear, which is 0.278/s on wm7 (S reference 0.15) and 0.190/s on wm12, so the boat loses about 0.85 m/s2 at 10 kn. The half-helm radius is 2*R_full+offset (wm7 11.6 m, wm12 17.7 m). Upwind accel is about half the reference (wm7 jib 0.074 m/s2 at 40 deg and 10 kn against 0.13). The boat stops before the bow is through the 49 deg no-go. Feel multipliers that meet boat.md §10.3 (sweep at 10 kn): accel x2, decel x0.35, turn_rate x2 give wm7 8.9 s at helm 0.5 and 4.3 s at full helm, wm12 10.4 s and 5.7 s. decel x0.5, turn x2, accel x2 give wm7 11.9 s and wm12 13.4 s. Harder helm is always faster with the current rudder_drag tables, while boat.md §7.2 expects a slammed tack to cost more. Recovery from irons for wm12 also misses the 20 s of §10.4 (no fall_off table is written; upwind accel is low). Owner decision: keep handling at 1.0 and fix the VPP derivation of decel, turn radius and upwind accel. core/tests/test_boat.cpp 'boat: tack on the shipped classes' documents the current failure.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 wm7 and wm12 tack at 10 kn with helm 0.5 on handling 1.0 and wm7 is back to 90 % speed within 12 s,A slammed full-helm tack costs more than a helm-0.5 tack,wm12 recovers from irons to 50 % polar speed within 20 s
<!-- AC:END -->
