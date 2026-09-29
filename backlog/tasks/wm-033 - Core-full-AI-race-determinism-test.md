---
id: WM-033
title: 'Core: full AI race determinism test'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-25 15:24'
updated_date: '2026-09-29 21:50'
labels:
  - core
dependencies:
  - WM-009
  - WM-008
  - WM-010
priority: high
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Phase 2 gate item (ROADMAP.md): a headless full race with the AI fleet, collisions and rules; same seed and inputs give identical checksums every tick, also across a second architecture (x86_64 under Rosetta). Also profile a 20-boat fleet bunched at a mark (WM-009 measured about 0.2 ms per close pair per tick for the mark-room and escape tests).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Full AI race finishes headless
- [x] #2 Two runs and a second-architecture run give identical per-tick checksums
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Test: core/tests/test_ai_full_race.cpp (doctest suite long, ctest core_long): the fleet of core/tests/ai_fleet_race.h (10 AI skippers, levels easy to pro in turn, every third a wm12, example course two laps, 11 kn oscillating shifts with puffs, seed 33) races headless to the close with collisions and rules (3 boat contacts, 5 penalties, 10 of 10 finished, 21438 ticks), twice: same checksum every tick, same results.

Second architecture: core/tools/cross_arch_check.sh builds core/build-x86_64 (-DCMAKE_OSX_ARCHITECTURES=x86_64), runs its quick tests under Rosetta (math and env vector files included: pass), and compares the per-tick checksum files of windmark_race_trace (core/tools/race_trace.cpp) from both builds. First run: the scripted full race matched, the AI race differed from tick 8205. Cause: std::acos in the AI mark-rounding guide (ai_course.cpp, the tangent point angle), a platform libm call against conventions.md §5 rule 7. Replaced by wm_acos; new test core_no_libm fails on any libm transcendental symbol in the core library (it flags the old _acosf). After the fix every tick matches: scripted full race (15477 ticks) and AI fleet seeds 33, 1, 2, 3, 7 (20873 to 22774 ticks each). Remaining libm use: cbrt in double for the server-side wind-sea period (sea.md §2 writes chi^(1/3), load-time), allowed by the check; it matched on both builds.

Profile, 20 boats (windmark_race_trace ai --boats 20 --profile, seed 33, dev Mac under heavy load from other jobs, load average 10 on 8 cores, so these are upper bounds): per-tick step cost by boats within 4 L_max (48 m) of a mark: fewer than 5: 1.59 ms (AI 0.51); 5 to 9: 1.96 ms (AI 0.79); 10 to 14: 4.27 ms (AI 2.18, 42 close pairs); 15 or more: 6.66 ms (AI 3.72, 57 close pairs); worst single tick 29 ms (15 boats at the mark, 58 pairs; likely includes scheduling noise). Hot spots at the mark: point_polygon_edge_dist and the separating-axis max_separation (rules predictions and AI checks per close pair), then the polar lookups. Well inside the 50 ms tick on average; the bunched worst case is worth watching for 40-boat rooms.
<!-- SECTION:NOTES:END -->
