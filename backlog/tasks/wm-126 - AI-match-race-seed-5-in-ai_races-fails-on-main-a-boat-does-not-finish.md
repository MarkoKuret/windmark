---
id: WM-126
title: 'AI: match race seed 5 in ai_races fails on main (a boat does not finish)'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-11 12:28'
updated_date: '2026-10-15 19:55'
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
- [ ] #1 ai_races passes on main
- [ ] #2 Cause recorded in the task notes
<!-- AC:END -->
