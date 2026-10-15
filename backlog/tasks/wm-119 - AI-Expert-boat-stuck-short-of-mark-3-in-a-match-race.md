---
id: WM-119
title: 'AI: Expert boat stuck short of mark 3 in a match race'
status: Done
assignee: []
created_date: '2026-10-06 14:29'
updated_date: '2026-10-15 18:02'
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
Fixed by heel-fix (c8483c8): committee-boat hold-course bug; merged 2026-10-15.
<!-- SECTION:NOTES:END -->
