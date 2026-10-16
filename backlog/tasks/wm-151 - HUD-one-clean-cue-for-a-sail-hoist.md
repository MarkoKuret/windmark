---
id: WM-151
title: 'HUD: one clean cue for a sail hoist'
status: Done
assignee:
  - '@hudux2'
created_date: '2026-10-16 20:09'
updated_date: '2026-10-16 20:28'
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
- [x] #1 The overlap is identified and recorded in the task notes
- [x] #2 hud.md §2 and §5 specify the hoist cue
- [x] #3 During a hoist no two HUD texts overlap at 1280 x 720 and 1280 x 800, and one cue shows the sail and its progress
- [x] #4 race_hud_test or hud_test checks it; render
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Overlap found: during a hoist the helm strip's sail value grew to 'JIB, HOISTING CODE ZERO 45 %' (214 px at 13 px, right-aligned in the 360 px strip, from x 146), running into the sheet value centred in the same row ('SHEETS AUTO' 135 to 225, 'SHEET 50 %' 140 to 220); the greyed jib gauge also kept its tell-tale. Now: one HOISTING <SAIL> line with a progress bar over the strip, the strip names the sail up, greyed gauges have no tell-tale, the sail hint waits.
<!-- SECTION:NOTES:END -->
