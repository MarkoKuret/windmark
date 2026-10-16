---
id: WM-073
title: 'Marketing: Who''s wrong? quiz scenarios 1 to 4 with checked answers'
status: In Progress
assignee:
  - '@quiz'
created_date: '2026-09-29 22:17'
updated_date: '2026-10-16 20:39'
labels:
  - marketing
dependencies: []
priority: high
ordinal: 100000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Social plan 5, 6. Four incidents for the weekly rules quiz: port/starboard (rule 10), clear astern (rule 12), mark-room at the zone (rule 18.2), tacking in the zone (rule 18.3). For each: the set-up (positions, headings, wind), the freeze frame, the engine's call and the HUD rule text, and the answer in plain words checked by the owner against docs/specs/rules.md and the RRS. A wrong call in public undermines the premise.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Four scenarios written with set-up, freeze-frame moment and answer text
- [ ] #2 Owner has checked each answer against rules.md and the RRS
- [x] #3 Each reproduced in the game with the engine giving the expected call
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Scenarios: port_starboard, clear_astern, mark_room, tack_in_zone (game/data/scenarios); doc docs/marketing/quiz_scenarios.md; verified by game/tests/run_scenario_test.sh. New scenario key boats[].turns (data_format.md §9.2, race.md §14) for scripted tacks and bear-aways.

Engine notes for the owner (not fixed here):
- Rule 18.2 status dropped too early (core/src/rules/rules.cpp mark_rules, 'End statuses'): the status ends when the entitled boat is not in the zone (!e_zone), so when the OUTSIDE boat reaches the zone first, the inside boat's entitlement is deleted on the next tick (she has not entered yet, she has not left). RRS 18.2(b) ends it only when she leaves the zone. Seen in mark_room with Petrel 2.5 m ahead: the call became rule 11 instead of 18.2 (same boat, here harmless); at a leeward mark with a windward inside boat it would penalise the wrong boat. Fix idea: end on leaving only (keep a 'reached' flag per status; snapshot field).
- Rule 14 on the right-of-way boat never fires on a hard contact: the 'acted' check reads the speed history including the tick of the contact, and the collision impulse itself cuts her speed by more than 10 %. port_starboard: 3.9 m/s contact, Kestrel held course, no rule 14. rules.md §5.1 intends the 2 s before the contact.
- rules.md §7.3 item 4: RRS 18.2(d) switches off 18.2(a) and (c); the engine applies the (d) exemption to the (c) case only.
<!-- SECTION:NOTES:END -->
