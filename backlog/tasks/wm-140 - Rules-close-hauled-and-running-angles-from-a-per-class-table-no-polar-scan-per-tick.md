---
id: WM-140
title: >-
  Rules: close-hauled and running angles from a per-class table (no polar scan
  per tick)
status: Done
assignee:
  - '@claude'
created_date: '2026-10-16 19:22'
updated_date: '2026-10-16 19:51'
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
- [x] #1 rules.md describes the table and interpolation
- [x] #2 Core tick before and after measured (windmark_race_bench, 16 and 24 boats), recorded in PERFORMANCE.md; max angle difference against the full scan reported
- [x] #3 Core tests including ai_long, determinism and snapshot tests green; GDExtension rebuilt and run_core_sim_test passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Table per class built at load (data/vmg_table.cpp): the scan's winner as a staircase in TWS, switches found by float bisection, near ties (1e-5) kept as candidates, index every 0.05 m/s. Lookup equals the full scan bit for bit (max angle and speed difference 0 for wm7 and wm12 over a 1 mm/s sweep and odd floats), so races are unchanged (bench checksums identical). RAM wm7 3.9 KB, wm12 2.6 KB; build 3 / 13 ms; lookup ~0.1 us vs 9 us. Core tick seed 7: 16 boats 92.5 -> 69.3 us, 24 boats 154.3 -> 119.1 us (PERFORMANCE.md). Rules, race (projected finishes), course_scale and the C API all use the table; PolarVmgCache removed; snapshot format unchanged. ctest 8/8 incl. ai_long, run_core_sim_test passed.
<!-- SECTION:NOTES:END -->
