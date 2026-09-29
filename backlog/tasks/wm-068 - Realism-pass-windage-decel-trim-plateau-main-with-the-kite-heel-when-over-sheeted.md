---
id: WM-068
title: >-
  Realism pass: windage decel, trim plateau, main with the kite, heel when
  over-sheeted
status: In Progress
assignee:
  - '@claude'
created_date: '2026-09-29 11:55'
updated_date: '2026-09-29 13:48'
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
- [x] #1 Windage decel scales with apparent wind
- [x] #2 Main sheeted in with the kite up, per-class offset in the class file
- [x] #3 Heel rises when over-sheeting at 90 deg TWA
- [ ] #4 Owner sails it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Item 2 (trim plateau) dropped by the owner 2026-09-29: trim_speed stays the physical table, identical to main. Done on branch realism: windage decel linear in the apparent wind (decel_windage, secant at 3.4 m/s; AI and rules predictions keep decel_const); main kite_sheet_in 0.26 rad on wm7 and wm12; trim_heel at the trimmed state with the stall normal force held, core heel follows the boat's own apparent wind (boat.md 10.10).
<!-- SECTION:NOTES:END -->
