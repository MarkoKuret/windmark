---
id: WM-091
title: >-
  AI: full fleet race regression after the bigger kites, pinned boats at the
  layline
status: In Progress
assignee: []
created_date: '2026-10-04 23:09'
updated_date: '2026-10-05 15:16'
labels:
  - core
  - ai
dependencies: []
priority: medium
ordinal: 120000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After the sails merge (WM-090: kites 13 % larger, data/perf regenerated) the long test 'full AI race: a fleet with collisions and rules races to the close' (seed 33, 10 boats, wm7 and wm12) finishes 6 of 10 (needs 8). Find the cause with evidence (old vs new perf, same seed and a seed sweep), fix the root cause in the AI or the data, spec first; keep determinism and the float rules; do not weaken the test or change its seed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Cause found with evidence (telemetry of the race, old vs new perf, seed sweep)
- [ ] #2 Root cause fixed, spec updated first (ai.md)
- [x] #3 Full AI race test passes (8 or more of 10 finish), bit-identical twice
- [x] #4 Quick and long core tests and the ai_long fleet runs pass; ai.md 15 measurements recorded before and after
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Cause (evidence: core/tools/race_trace --telemetry, old and new perf in lockstep, 40-seed sweeps):
- The sails merge changed only the kite configs' tables and width_spinnaker. No core code changed. The upwind configs, the AI's theta_up and the kite crossover (11 kn: wm7 102 deg, wm12 107 to 105 deg) are unchanged. No broaching at the test's 11 kn.
- Coupling into the race: courses.md 6.3 scales the course to target_duration with the longest class's (wm12) polar VMG, kite included. Downwind VMG is +1.8 % in both classes, so k goes 0.66782 -> 0.67245 and the marks move about 3 m. With identical boat states, a Pro's corridor tack fires 0.2 s later at t = 120 s (old perf + new kite polar only reproduces this; swapping only the VMG summary does not). From there the race diverges chaotically (WM-054: chaotic under small changes).
- Seed 33 new: boats 8 and 9 miss the finishing window (0.5 x winner time) by 1.6 m and 2.9 m (under 1 s). The old run passed with exactly 8 finishers, boat 0 DNF by 9.4 m.
- The time loss of the three DNF boats: they sailed the second beat as a pack and pinned each other at the port layline in a lull. The rule-13 check refused both tacks (6.5 m apart, gap during the tack under 1 L), so they overstood by 100 to 150 m. The leg type then flipped to reach, and the reach code turned through the wind on the helm alone or looped the long way round.
- 40 seeds, old vs new perf: finished 90.0 % vs 89.5 %, DNF 8 vs 7, DSQ 32 vs 35, seeds under 8 finishers 2 vs 3, penalties/boat 0.81 vs 0.88, contacts/race 5.78 vs 5.62. No systematic regression. Kite area 0.39 SLU^2, inside the 0.38 to 0.46 references (sail_visuals.md 14): not unrealistic.

Fix (commit separate from the telemetry tool so it can be dropped): ai.md 4.2 (racing: tack to reach the other tack, no helm-only tacks or gybe loops) and 7.3 (making room for a tack blocked by a same-tack boat within 3 L).
- Fix A alone deadlocked a pinned pair: 800 m past the mark.
- Gated to racing, because the start relies on the long way round. The first version raised pre-start penalties 2.60 -> 3.38 per race.
- 40 seeds with the fix: finished 89.5 %, DNF 6, DSQ 36, seeds under 8 finishers 2 (23, 29), penalties/boat 0.88, contacts 5.65, mark touches 0.60 -> 0.97 per race.
- Without make_room in roundings: touches 0.55, but DNF 8 and seed 33 at 7 of 10.
- Aggregate effect within noise: seed 33 passing (9 of 10) is a reroll, not proof.
- Tests with the fix: quick, long (full AI race 9/10, twice identical), ai_long all pass.

Owner decision open: keep the AI fix (the pinned-pair behaviour is a real defect, also WM-054), and/or make the full race test robust to chaos (several seeds), which changes the test.

Owner decision (2026-10-05): the AI fix (commit e5fbf79) is NOT merged; it is parked on branch park/ai-pinned-tack (also on origin) and listed in WM-054. The full-race test stays a single race (seed 33). Consequence: on main, the long test 'full AI race' fails with 6 of 10 finishers since the WM-090 sails merge (a re-rolled chaotic race, no systematic regression over 40 seeds: 90.0 % vs 89.5 % finished). The telemetry tool (race_trace --telemetry) is merged.

2026-10-05: after merging the rules update to the RRS 2025-2028 (one 360 within 120 s, etc.), the single-race full AI test passes again on main (re-rolled race); ai_races and core_long pass. The parked fix stays on park/ai-pinned-tack.
<!-- SECTION:NOTES:END -->
