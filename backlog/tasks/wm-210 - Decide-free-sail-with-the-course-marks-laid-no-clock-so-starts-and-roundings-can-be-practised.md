---
id: WM-210
title: >-
  Decide: free sail with the course marks laid (no clock), so starts and
  roundings can be practised
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07 18:47'
updated_date: '2026-11-07 19:45'
labels:
  - decide-later
dependencies: []
priority: medium
ordinal: 226000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Free sail puts one boat on empty water: no course, no marks, no line (sail_test.gd ~847). Practice Waters says 'Learn the boat and the rules' and 'practise starts', and WM-096 (tutorial) is open. Cheapest step: free sail lays the venue's course (marks, line, committee boat) with no sequence and no results; the mark tag and laylines work as in a race. A 'practice start' (sequence on, no fleet, repeatable) could be a row on the Set sail step.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Owner decides the shape; spec menus.md updated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decided 2026-11-07 (recommendation taken): free sail lays the venue's first course for the class (marks, start line, committee and mark boats), no sequence, no clock, no results; the mark tag and laylines lead round the course in order and wrap to the start after the finish.

Built: specs menus.md §1.1 (Free sail's course, the Set sail summary's Course line), courses.md §6.4 (laying without a race; the free progress: start line, marks and gates by the race's tests, finish, wrap), hud.md §7.2 (what shows), race.md §5 pointer. Core wm_world_lay_course / wm_world_has_course (C API 8); FreeCourse (game/scripts/sim/free_course.gd), CoreSimSource.lay_course, RaceHudValues.free, CourseView free mode, buoy sounds, setup panel and Continue carry the course. Tests: free_sail_test (round the course), menus_test (summary), core world and capi tests.
<!-- SECTION:NOTES:END -->
