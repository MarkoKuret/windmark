---
id: WM-148
title: 'HUD: course map uses the full width in landscape'
status: In Progress
assignee:
  - '@hudux2'
created_date: '2026-10-16 20:09'
labels:
  - hud
dependencies: []
ordinal: 173000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
In landscape the course map is squeezed into the right half because the alert column keeps the left. Let the course use the full width; move the alert lane out of the way.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 hud.md §8.1 updated
- [ ] #2 In landscape the frame fits the whole width when the alert lane is empty and is not squeezed by it otherwise as specified
- [ ] #3 race_hud_test checks the frame; landscape map render
<!-- AC:END -->
