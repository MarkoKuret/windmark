---
id: WM-135
title: Boats roll and pitch with the sea (no wave yaw)
status: In Progress
assignee:
  - '@sea-look'
created_date: '2026-10-15 18:00'
labels:
  - core
  - physics
dependencies: []
priority: high
ordinal: 167000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WM7 at 25 kn in swell is dead steady (heel 30 +-3 deg, pitch +-5). Raise the wave response of roll, pitch and heave toward physical values (boat.md 5.6, VPP dynamics: wave_roll_gain 0.3 and the attitude springs), justified in the spec. Waves must never change heading (owner).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 boat.md gives the physical justification for the new values
- [ ] #2 VPP regenerates the perf files; generated data not hand-edited
- [ ] #3 Full core tests incl. ai_long and the VPP pytest green
- [ ] #4 Downwind clip motion stats before/after recorded; wave-induced yaw stays zero
<!-- AC:END -->
