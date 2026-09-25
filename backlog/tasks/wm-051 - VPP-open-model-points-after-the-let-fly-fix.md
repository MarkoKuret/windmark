---
id: WM-051
title: 'VPP: open model points after the let-fly fix'
status: To Do
assignee: []
created_date: '2026-09-25 17:32'
labels:
  - vpp
dependencies: []
priority: low
ordinal: 66000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From WM-044/045: flogging drag coefficient 0.30 is an estimate (find data or calibrate by feel); decel_const charges windage at a fixed 5 m/s (use the apparent wind); fall_off rates are spec reference values, not a yaw balance; accel_rest is a drive-at-rest stand-in because the VPP keel drag blows up near zero speed; the helm balance leaves out hull effects.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each point resolved or documented as a deliberate simplification in tools/vpp/README.md
<!-- AC:END -->
