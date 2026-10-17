---
id: WM-150
title: 'HUD: penalty deadline bar'
status: Done
assignee:
  - '@hudux2'
created_date: '2026-10-16 20:09'
updated_date: '2026-10-16 20:28'
labels:
  - hud
dependencies: []
ordinal: 175000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A thin bar beside the penalty deadline countdown, shrinking towards 0:00, broadcast style.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 hud.md §12.1 specifies the bar
- [x] #2 The bar's length is the time left over 120 s, in the deadline's colour
- [x] #3 race_hud_test checks the bar length; render
<!-- AC:END -->
