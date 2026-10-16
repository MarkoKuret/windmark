---
id: WM-147
title: 'HUD: next-mark arrow only when the mark is off screen'
status: In Progress
assignee:
  - '@hudux2'
created_date: '2026-10-16 20:09'
labels:
  - hud
dependencies: []
ordinal: 172000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
In the onboard, aerial and free cameras the next-mark arrow shows only while the next mark is off screen; with the mark on screen it is hidden (the mark tag is on it).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 hud.md §7.1 updated
- [ ] #2 Arrow hidden with the mark on screen and shown with it off screen in onboard, aerial and free; never in chase
- [ ] #3 race_hud_test checks both cases; render of the off-screen case
<!-- AC:END -->
