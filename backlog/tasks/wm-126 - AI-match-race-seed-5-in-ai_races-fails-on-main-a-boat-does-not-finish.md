---
id: WM-126
title: 'AI: match race seed 5 in ai_races fails on main (a boat does not finish)'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-11 12:28'
updated_date: '2026-10-15 20:20'
labels:
  - ai
dependencies: []
priority: medium
ordinal: 159000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found 2026-10-11 while merging WM-016.20: the long ai_races test (label ai_long) fails on a clean build of main. Match-race check at core/tests/test_ai_race.cpp:347: match seed 5 gives finished "1 0" (one boat does not finish). Likely the same kind of AI stuck-near-a-mark problem as WM-119. Find why the boat does not finish and fix it; ai.md first if behaviour changes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ai_races passes on main
- [x] #2 Cause recorded in the task notes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Cause (branch ai-reliable, ai.md 6.4, 6.5, 7.3, 7.4, 7.6 updated first): after rounding the leeward mark of the match course (60 m below the line) the boat beat up through the start line on port and met the committee boat. The object check bore her away to pass below it, but the hold-course rule (7.4) cut every turn to 5 degrees while the other boat was near, so she sailed into its side; in other seeds she tacked onto starboard just beside it (the tack check only looked at the hull during the tack) and then bore away across its stern into it. Against it with no way on, the old escape (hard helm towards a heading away, a gybe round) could not move her: a stopped boat cannot steer, and her drive and drift wedged her against it.
Fix: hold course does not limit a turn that passes a course object when holding would touch it; no tack or gybe onto a heading that runs at an object close ahead; big turns near objects after the start checked along their track; the rounding check reads the side the mark is on now and falls back to a tack, the present heading or (not into a setting stream) let fly; a new pinned escape (helm steady, sails drawing / let fly / sail away over the ground in turn on no progress) that also blocks rules avoidance and penalty turns until she is off.
Measured (AI_REL sweeps, 400 seeds, winds 8 to 19 kn): match7 finished 777 -> 798 of 800, DNF 20 -> 0, races with a boat pinned over 30 s 51 -> 1; match12 764 -> 781, DNF 18 -> 4, pinned 28 -> 0. ai_races passes (match seed 5: both finish). WM-119 (seed 4, boat short of mark 3, no contacts or penalties) is the same failure: on this course mark 3 is the second windward mark, reached through the line past the committee boat; it no longer reproduces on main, and the sweeps show no such boats.
<!-- SECTION:NOTES:END -->
