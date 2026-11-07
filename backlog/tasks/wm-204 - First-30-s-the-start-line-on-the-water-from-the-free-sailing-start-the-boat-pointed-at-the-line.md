---
id: WM-204
title: >-
  First 30 s: the start line on the water from the free-sailing start, the boat
  pointed at the line
status: To Do
assignee: []
created_date: '2026-11-07 18:47'
labels:
  - playability
dependencies: []
priority: high
ordinal: 220000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The race opens with 30 s of 'WARNING IN' and nothing else: the start line is drawn only from the warning signal (course_view.gd ~455), no next mark, and the boat spawns reaching away from the line at TWA 100 (world.cpp ~46). A new player has no idea where the line is. Draw the line from the first frame and spawn with the bow towards the line area (or show the line marker). Pairs with WM-199 key hints.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The start line and the committee boat are visible from the first frame of a quick race
- [ ] #2 The player's boat spawns with the line in view of the chase camera
<!-- AC:END -->
