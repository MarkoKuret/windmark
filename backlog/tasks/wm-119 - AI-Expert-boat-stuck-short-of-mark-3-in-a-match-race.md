---
id: WM-119
title: 'AI: Expert boat stuck short of mark 3 in a match race'
status: Done
assignee: []
created_date: '2026-10-06 14:29'
updated_date: '2026-10-15 20:20'
labels: []
dependencies: []
ordinal: 139000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
On the stern-clearance branch (2026-10-06, WM7 hull with the rounder stern, which changes dynamics.bwl and hull_points by fractions of a millimetre) the long ai_races test fails: 'the match race leader covers', seed 4 (two Expert WM7s, ai_match_course, oscillating shifts): boat 0 rounds mark 2 at 576 s right behind boat 1 (582 s), then never rounds mark 3 and is scored DNF at 2044 s; boat 1 finishes at 1156 s. No penalties, no contacts. With the old hull data the race finishes normally, so the hull change only exposes the AI getting stuck. Find why boat 0 cannot round mark 3 (in irons, circling, a tactic loop) and fix it.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-15 (WM-126, branch ai-reliable): does not reproduce on main (match seed 4 finishes). Same failure class as WM-126: on the match course mark 3 is the second windward mark, reached by beating up from the leeward mark through the line past the committee boat; base sweeps (400 seeds each, wm7 and wm12) had 79 races with a boat pinned there over 30 s, after the WM-126 fixes 1. Closed with WM-126.
<!-- SECTION:NOTES:END -->
