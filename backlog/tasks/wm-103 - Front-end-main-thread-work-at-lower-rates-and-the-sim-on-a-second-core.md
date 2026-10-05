---
id: WM-103
title: 'Front end: main-thread work at lower rates and the sim on a second core'
status: To Do
assignee: []
created_date: '2026-10-05 17:12'
labels:
  - performance
dependencies: []
priority: high
ordinal: 140000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
docs/PERFORMANCE.md C1, C4, C5, C6, C7, C8 and measured item 4: sails full rate only for near or on-screen boats, the rest 30 Hz or less; wakes and drawn-shadow state only for selected boats, uniforms copied on change; audio voices at 20-30 Hz; one packed pose array per frame; HUD redraws only changed blocks; the core stepped on a worker thread one tick ahead with double-buffered render state.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Main-thread game CPU at 16 boats measured headless before and after (PerfStats), target -1.5 ms on the dev Mac
- [ ] #2 Sim on a worker thread: no frame hitch from a slow tick; determinism and replays unchanged
- [ ] #3 All headless game tests pass
<!-- AC:END -->
