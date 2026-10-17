---
id: WM-165
title: >-
  Boats: wm21 classic 12 Metre style (long overhangs, low freeboard, tall rig,
  symmetric kite)
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-17 09:53'
updated_date: '2026-10-17 11:22'
labels:
  - boats
dependencies: []
priority: medium
ordinal: 189000
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Class file, generated model, perf table and liveries; previews rendered; all suites green; owner approves the look
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
wm21 Windmark Classic 21: 20.8 m LOA, 13.8 m LWL, 3.70 m beam, 2.70 m draft, 25 t (18 t lead in a long fin keel), crew 11. Masthead rig (forestay 0.974 of the mast above deck), pinhead main 84 m2, overlapping genoa 122 m2, deep symmetric spinnaker 294 m2 (mid girth 1.05 of the foot, look camber 0.32) on a 7.2 m pole. Flush deck, long cockpit, big wheel through the floor, counter stern with a small transom.

Boatgen additions (wm7, wm12, test_sym output byte-identical): hull.counter_height (counter stern), flush deck closes over the centreline at the cockpit ends and keeps a foredeck hatch, bulbless fin keel with its tip cap at the draft, rudder stock at least the blade's thickness.

12 kn: beat 40 deg 6.5 kn, VMG 4.97 (wm12 41 deg 6.45 kn, 4.87); run 155 deg 7.4 kn with the kite, VMG 6.68 (wm12 150 deg 7.7 kn, 6.65; wm12 clearly faster from 14 kn). 50-90 % acceleration about twice wm12's time, turn radius 12 m (wm12 7.3 m), 24 deg heel upwind.

Open: the VPP takes the static LWL, so the overhangs give no extra sailing length when heeled; upwind speeds sit about 1 kn under real boats of the type. AI fleet of ten wm21 (core race_trace with wm21 swapped in): 4 to 6 of 10 finish, most of the rest DSQ 44.2-late (penalty turns take 70 to 120 s against the 120 s deadline); wm7/wm12 fleet 9 to 10 of 10. The shared symmetric-kite set shape needs to fly this deep kite far forward of the forestay (being fixed elsewhere).
<!-- SECTION:NOTES:END -->
