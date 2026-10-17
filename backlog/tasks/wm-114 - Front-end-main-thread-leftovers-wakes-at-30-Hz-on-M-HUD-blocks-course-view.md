---
id: WM-114
title: >-
  Front end: main-thread leftovers (wakes at 30 Hz on M, HUD blocks, course
  view)
status: To Do
assignee: []
created_date: '2026-10-06 11:17'
updated_date: '2026-10-17 14:16'
labels:
  - performance
dependencies: []
priority: low
ordinal: 151000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Leftovers from WM-103, only if WM-113 (M1 measurement) shows the main thread still matters: other boats' wake ribbons stepped at 30 Hz on tier M (about 0.3 ms on the dev Mac); HUD rebuilding only blocks whose inputs changed (about 0.19 ms); course view marks and lines (about 0.13 ms). About 0.6 ms on the dev Mac, roughly 1.5 ms on a cheap laptop.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Main-thread time measured before and after, clock-matched
- [ ] #2 All headless game tests pass
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-17 (branch lowend): items 1 and 3 done and measured headless, clock-matched, 16 boats: other boats' wake ribbons at most 30 Hz on M and H (wakes 0.483 to 0.230 ms at 145 fps, about half of that at 60 fps; spec water_render.md 5); the course view takes the sea height from the native SeaSampler (course 0.139 to 0.055 ms). Item 2 (HUD blocks) belongs to the HUD work: hud section 0.58 ms of the 1.20 ms main thread on L. All headless suites pass.
<!-- SECTION:NOTES:END -->
