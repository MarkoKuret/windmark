---
id: WM-068
title: >-
  Realism pass: windage decel, trim plateau, main with the kite, heel when
  over-sheeted
status: To Do
assignee: []
created_date: '2026-09-29 11:55'
labels:
  - vpp
dependencies: []
priority: high
ordinal: 95000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner (2026-09-29), keeping the realistic feel: (1) windage deceleration uses the apparent wind instead of a fixed 5 m/s (decel_const; WM-051 point); (2) widen the trim_speed plateau (full speed within about +-3 to 4 deg of trim error instead of +-2) without a minimum floor and keeping the drop to zero when the sail fully luffs; (3) main with a kite up: a simple per-class offset in the class file that sheets the main in when a spinnaker or code zero is set (VPP writes the kite configs' main optimal angle with it); the main stays trimmed by apparent wind; (4) over-sheeting on a reach must raise the heel: today trim_heel rises only to 1.21 and the heel is looked up for the slower boat, so the net heel drops; build the heel effect for the boat's actual speed and apparent wind (check whether a stronger sail normal-force coefficient is also needed). Spec first (boat.md, sails.md, data_format.md), then VPP, data/perf regenerated with the tool, core if needed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Windage decel scales with apparent wind
- [ ] #2 Trim plateau +-3 to 4 deg, no floor
- [ ] #3 Main sheeted in with the kite up, per-class offset in the class file
- [ ] #4 Heel rises when over-sheeting at 90 deg TWA
- [ ] #5 Owner sails it
<!-- AC:END -->
