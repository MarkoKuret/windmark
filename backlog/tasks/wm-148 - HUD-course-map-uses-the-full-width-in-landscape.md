---
id: WM-148
title: 'HUD: course map uses the full width in landscape'
status: Done
assignee:
  - '@hudux2'
created_date: '2026-10-16 20:09'
updated_date: '2026-10-16 20:28'
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
- [x] #1 hud.md §8.1 updated
- [x] #2 In landscape the frame fits the whole width when the alert lane is empty and is not squeezed by it otherwise as specified
- [x] #3 race_hud_test checks the frame; landscape map render
<!-- AC:END -->
