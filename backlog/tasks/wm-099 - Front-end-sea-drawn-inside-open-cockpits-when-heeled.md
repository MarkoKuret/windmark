---
id: WM-099
title: 'Boats: sea in open cockpits when heeled'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-05 15:44'
updated_date: '2026-10-07 13:28'
labels: []
dependencies: []
ordinal: 137000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The sea showed in the leeward corner of the open cockpits whenever the boat heeled hard. Cause: the hull turned about a fixed axis, while a real heeled hull rises and trims bow down as its flared leeward quarter immerses. Fix in the physics (boat.md 5.6): the generator computes heel rise and trim from the drawn hull, the VPP copies them, the core adds them to the heave and pitch targets. Also new sterns (wm7 rounder bilge and U-shaped transom, wm12 transom 2.45 m and rounder bilge). A sea mask for the cockpits was built, then dropped as unneeded (owner, 2026-10-07).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 heeled hulls float: the generator computes rise and trim per heel from the drawn hull, the VPP copies them, the core adds them to the heave and pitch targets (boat.md 5.6)
- [x] #2 the sea reaches the cockpit floor only now and then in a breeze (probe: at most 4.2 % in 25 kn), heel and speed unchanged, no cockpit mask; owner retest good
- [x] #3 stern shapes as chosen by the owner; hull, transom and deck textures rebaked; the generator keeps the keel and sheer in place
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Probe numbers in boat.md 5.6. Found on the way: WM-118 (bowsprit overlap), WM-119 (AI stuck at mark 3 in match seed 4, fails the long ai_races test). The GDExtension in game/bin is rebuilt only by run_core_sim_test.sh --rebuild: rebuild it after core changes.
<!-- SECTION:NOTES:END -->
