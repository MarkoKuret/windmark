---
id: WM-047
title: 'Decide: sea grid fade rule'
status: To Do
assignee: []
created_date: '2026-09-25 17:14'
labels:
  - decide-later
dependencies:
  - WM-016.08
priority: low
ordinal: 62000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From WM-016.02: the spec rule (removed height under 0.05 Hs) can't hold for 1 to 10 m wind-sea waves beyond 25 to 100 m, so water_render.md 9.2 now limits the fade error in screen pixels (at most 2.8 px near the camera, under 1 px beyond 200 m). Keep it, or add a fine grid patch near the camera on tier H? Owner question, set aside on 2026-09-25: answer once the game runs (after WM-016.08, sail one boat).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Owner decided; spec and code updated to match
<!-- AC:END -->
