---
id: WM-055
title: 'Race: projected finishes use performance_scale'
status: Done
assignee: []
created_date: '2026-09-25 19:18'
updated_date: '2026-09-29 17:38'
labels:
  - core
dependencies: []
priority: medium
ordinal: 72000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From WM-010: the projected finish speed (race.md 7.2) ignores the boat's performance_scale, so Easy AI boats get projected times faster than they would sail. Spec first (race.md 7.2), then core/src/race.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 race.md 7.2 and the race layer scale the projected speed by performance_scale
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
race.md 7.2: V_ref = 0.9 x performance_scale x polar VMG/speed. Race::add_boat takes the entry's performance_scale (clamped as boat.md 2), World passes it; v_ref_time scales by it. Test in test_race.cpp: AI boat at 0.9 projected at d/0.9 of the 1.0 boat. game/: results already show core projected times (proj.), no change; the HUD estimated gap (race.md 8.4, V_ref as 7.2) now also scales by the watched boat's performance_scale (1 for humans). No stored checksums changed.
<!-- SECTION:NOTES:END -->
