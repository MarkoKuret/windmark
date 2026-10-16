---
id: WM-151
title: 'HUD: one clean cue for a sail hoist'
status: In Progress
assignee:
  - '@hudux2'
created_date: '2026-10-16 20:09'
labels:
  - hud
dependencies: []
ordinal: 176000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When the kite is hoisting, HUD words overlap. Find exactly what overlaps and make that moment simpler and more visible: one clear cue, no overlapping text.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The overlap is identified and recorded in the task notes
- [ ] #2 hud.md §2 and §5 specify the hoist cue
- [ ] #3 During a hoist no two HUD texts overlap at 1280 x 720 and 1280 x 800, and one cue shows the sail and its progress
- [ ] #4 race_hud_test or hud_test checks it; render
<!-- AC:END -->
