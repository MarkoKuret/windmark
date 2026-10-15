---
id: WM-135
title: Boats roll and pitch with the sea (no wave yaw)
status: In Progress
assignee:
  - '@sea-look'
created_date: '2026-10-15 18:00'
updated_date: '2026-10-15 18:38'
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
- [x] #1 boat.md gives the physical justification for the new values
- [x] #2 VPP regenerates the perf files; generated data not hand-edited
- [x] #3 Full core tests incl. ai_long and the VPP pytest green
- [x] #4 Downwind clip motion stats before/after recorded; wave-induced yaw stays zero
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
wave_roll_gain 0.3 -> 1.0 (both classes, VPP regen; the regen also brings in collision.sprit, which the committed perf files lacked; AI tests green with it). WM7 downwind Fremantle 25 kn, t>=12 s: heel sd 1.76 -> 3.91 deg (range -25.5..-17.2 -> -29.4..-12.6), pitch sd 2.75 -> 2.84, heave sd 0.17 -> 0.18 m, yaw rate identical (waves do not enter yaw), speed and TWA identical.
<!-- SECTION:NOTES:END -->
