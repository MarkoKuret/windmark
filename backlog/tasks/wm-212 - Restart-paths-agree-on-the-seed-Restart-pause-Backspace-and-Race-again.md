---
id: WM-212
title: 'Restart paths agree on the seed: Restart (pause), Backspace and Race again'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07 18:47'
updated_date: '2026-11-07 19:29'
labels:
  - playability
dependencies: []
priority: low
ordinal: 228000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Pause Restart reloads GameSetup.next unchanged (same seed after Start race, a new one after Continue or Race again, pause_menu.gd ~233); Backspace keeps world_seed (sail_test.gd ~863); Race again draws a new seed. On the results screen Restart and Race again sit side by side with different meanings. Decide: Restart = the same race again (same seed), Race again = a new day; make all three paths follow it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Restart keeps the seed everywhere; Race again draws a new one; spec says so
<!-- AC:END -->
