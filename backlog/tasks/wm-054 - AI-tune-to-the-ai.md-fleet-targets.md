---
id: WM-054
title: 'AI: tune to the ai.md fleet targets'
status: To Do
assignee: []
created_date: '2026-09-25 19:18'
updated_date: '2026-09-26 14:10'
labels:
  - core
dependencies: []
priority: high
ordinal: 71000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From WM-010: measured on the default course, 11 kn, 10 boats: penalties 0.5 to 1.0 per boat (target 0.4 or less), contacts 0.5 to 4.5 per race (target 1 or less), mean start delay 13 to 25 s (Pro target under 2 s), mixed-fleet order not strict (Intermediate beats Expert: 3.8 vs 4.2 mean place). Most penalties come from the windward mark in a crowd. Also add the ai.md mark-room scenario as its own test. ai.md 15.1 records the measured values; ai_races assertions are set to them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ai.md 15 targets met, or restated by owner decision
- [ ] #2 Mark-room scenario test
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Rounding robustness pass (branch ai-round), ai.md 6.1, 6.4, 5.6, 7.2, 7.4, 7.6 and 8 updated first:
- Causes found: keep-clear candidates and the mark-collision check steered boats onto the wrong side of the rounding mark (the collision check passed the mark on the side it happened to be on, then the rounding turned them into it); pinching and letting fly at the mark drifted into it; rule 17 limits cut rounding turns; start brake assumed let fly stops a boat (it coasts: decel law down to let_fly_drive); runs and beats laying the mark skipped the bad-air check; penalty turns were started with boats about to sail into the circle (22.2), and penalties near the windward and offset marks waited in the zones until 44.1-late.
- Changes: wrong-side cost (+30) for avoidance candidates; rounding mark passed on the rounding side only (tack or gybe away, else past on the other side, pinch only as last resort); predicted-track touch check of the rounding heading and tangent with re-plan away from the mark; rho uses the reaction time (yaw_time + half helm travel) and is at least the smooth-turn radius; no rule-17 limit while rounding; let-fly coast brake at the start on the planned heading; bad-air check on the lay-the-mark branch; penalty circle checked against the other boats' motion over 6 s; sail clear of the zones before the turn.
- Measured (dev runs AI_SCENE: 24 scene seeds, 16 Intermediate, 8 Pro, 8 mixed wm7/wm12 seeds), before -> after: touches 59 -> 24, penalties 370 -> 339, DSQ 47 -> 35, finished 417 -> 428 of 464, first mark rounded 443 -> 450. ai_long: bad air 1.44 -> 1.66, Expert OCS 5 -> 1 of 20.
- Tried and dropped (measured worse): irons recovery outside tacks, a reaction delay in all own-track predictions.
- Open: 44.1-late is still the largest penalty code; penalty and contact targets of 15 not met.
<!-- SECTION:NOTES:END -->
