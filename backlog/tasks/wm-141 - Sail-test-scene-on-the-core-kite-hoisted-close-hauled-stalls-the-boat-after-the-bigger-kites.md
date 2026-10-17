---
id: WM-141
title: >-
  Sail test scene on the core: kite hoisted close-hauled stalls the boat after
  the bigger kites
status: Done
assignee:
  - '@claude'
created_date: '2026-10-16 19:28'
updated_date: '2026-10-16 19:35'
labels: []
dependencies: []
priority: medium
ordinal: 165000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
game/tests/hud_test.gd (sail test scene on the core) ends at 0.25 m/s instead of > 1 m/s since the sail-shape merge (cdb680f). Find whether it is a gameplay regression or the scripted sequence, fix the cause.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Root cause traced over the 800 ticks before and after the merge
- [x] #2 Cause fixed (core/data) or the test's sequence adjusted with the reason in the commit
- [x] #3 hud_test and run_ui_tests.sh pass; ctest -LE long, run_core_sim_test.sh and run_sail_visuals_test.sh pass
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Trace (wm7, practice_waters, ~14.6 kn TWS): both runs tack and settle close-hauled at TWA -44 by frame ~900; the kite is hoisted at frame 1080 on that course.
Before (1912597): kite no-go edge 42.5 deg, so TWA 44 is a sailing cell with kite lee helm -0.145 rad/s; the kite bears the boat away (heel 11 -> 25 deg, TWA -44 -> -88) and it ends at 3.38 m/s.
After (cdb680f, main): kite 48.5 -> 52.5/53.5 m2, the VPP finds it overpowered at TWA 44 from 4 m/s TWS, so the no-go edge moves one 2 deg grid step to 44.5 deg. At TWA 44 the polar is the in-irons drift (-0.92 m/s), heel 0, no helm balance; the boat coasts from 2.3 to 0.25 m/s, the fall-off swings it to TWA 46, an overpowered broached cell (polar ~0.45, weather helm +0.12 rad/s), where the round-up balances even full helm at the broached speed (sails.md 6). Let fly or dropping the kite recovers (let fly + full helm: reaching at 3.3 m/s within 10 s).
Verdict: designed behaviour (data change from the bigger kite), not a regression; the scripted kite hoist close-hauled sat 1.5 deg outside the old edge. Test now bears away (set-and-hold, centred past TWA -100) while the kite goes up: ends at 4.8 m/s, TWA -110. The boom check now allows the stop on the kite sheet (sail_visuals.md 7.6): 71 frames, up to 14 deg, while the kite fills with the main still at jib trim.
<!-- SECTION:NOTES:END -->
