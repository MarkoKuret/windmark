---
id: WM-082
title: 'Core: sideways drift when stalled (leeway option a)'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-03 17:02'
updated_date: '2026-10-03 17:28'
labels:
  - physics
dependencies: []
priority: medium
ordinal: 112000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
decision-001 option (a): a stalled boat (in irons, flogging, badly over-sheeted) drifts to leeward instead of stopping dead. Sway velocity in the boat frame relaxed toward a target (~2-3 s); stalled target from a new VPP drift table (windage vs hull cross-flow drag, by TWS and AWA); blended out by keel grip so leeway is 0 at racing speed. Built so full leeway (b) is a data switch later. Spec boat.md 6.4 first.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 boat.md 6.4 (and sails/data_format where touched) specify the drift; spec updated before code
- [ ] #2 VPP writes the drift table; core reads it; racing-speed tracks, laylines and AI unchanged (existing tests green incl. ai_long)
- [x] #3 New tests: boat in irons and flogging drifts to leeward at the table rate; drift fades out above a few knots; determinism holds
<!-- AC:END -->
