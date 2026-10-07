---
id: WM-113
title: 'Measure: before and after the performance work on the M1'
status: To Do
assignee: []
created_date: '2026-10-06 10:56'
labels:
  - performance
dependencies: []
priority: medium
ordinal: 150000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Compare tags perf-before and perf-after on the owner's M1 MacBook. Steps in docs/PERFORMANCE.md, section 'Before and after on another machine': clone, check out each tag into its own folder, build the native plugin and the boats in each, then run the 60 s measured race (16 boats, seed 7) at the start (--skip=185) and on the open leg (--skip=330), tiers M and L, three times each, on AC power with Low Power Mode off. Compare median fps, main_ms and draw calls; add the table to PERFORMANCE.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Both tags built and run on the M1 with the same settings
- [ ] #2 Before/after table (fps, main_ms, draws; start and leg; tiers M and L) added to docs/PERFORMANCE.md
<!-- AC:END -->
