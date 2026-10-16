---
id: WM-140
title: >-
  Rules: close-hauled and running angles from a per-class table (no polar scan
  per tick)
status: To Do
assignee: []
created_date: '2026-10-16 19:22'
labels:
  - rules
  - perf
dependencies: []
priority: low
ordinal: 167000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner (2026-10-16): the rules engine scans the polar (polar_vmg) for every boat on every tick the wind speed at the boat changes, about a fifth of the core tick (PERFORMANCE.md, WM-130 profile). Build a table per class when the performance file loads (best VMG up and down over every config, every 0.05 m/s or finer, 0 to the polar's top wind) and interpolate. rules.md first: say the angles come from the table and the interpolation. Deterministic on every machine.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 rules.md describes the table and interpolation
- [ ] #2 Core tick before and after measured (windmark_race_bench, 16 and 24 boats), recorded in PERFORMANCE.md; max angle difference against the full scan reported
- [ ] #3 Core tests including ai_long, determinism and snapshot tests green; GDExtension rebuilt and run_core_sim_test passes
<!-- AC:END -->
