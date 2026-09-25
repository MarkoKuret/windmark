---
id: WM-055
title: 'Race: projected finishes use performance_scale'
status: To Do
assignee: []
created_date: '2026-09-25 19:18'
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
- [ ] #1 race.md 7.2 and the race layer scale the projected speed by performance_scale
<!-- AC:END -->
