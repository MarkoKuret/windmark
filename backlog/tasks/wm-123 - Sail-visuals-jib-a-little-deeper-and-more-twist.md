---
id: WM-123
title: 'Sail visuals: jib a little deeper and more twist'
status: In Progress
assignee:
  - '@sail-shape'
created_date: '2026-10-09 21:34'
updated_date: '2026-10-11 11:59'
labels:
  - game
  - sails
dependencies: []
priority: high
ordinal: 156000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner (2026-10-09): the jib's position is good, but it is a bit too flat and lacks twist. Resolves WM-057 (about 5 % camber upwind).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 sail_visuals.md gives the jib's camber and twist with real-sail references
- [ ] #2 Native and reference SailShape and boatgen previews follow; owner approves
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-10 (@sail-shape): sail_visuals.md 6.2 and 14.5. The jib keeps its clew line (the leech and clew where the sheet puts them, so its angle and trim are unchanged) and carries its belly against each row's own chord: camber m = 0.135 tanh(|b| / 0.15), 0.85 at foot and head, 1 at mid height, profile x(1-x)(2-x) with the draft at 0.42 (entry about 32 deg, exit 17 deg). Before: 2-4 % on the foot, under 1 % from mid height up, draft 0.64. After (wm7 and wm12 alike): beta 8 deg 9-10 %, beta 12 deg 10-12 %, eased at most 13.5 %; draft 0.44-0.45. twist_top 6 -> 10 deg: sections open 11.3 deg from foot to 5/6 at beta 12 (was 8.5). Code zero unchanged. Native, reference and boatgen sail_set.py in parity (0.2 mm). Previews: game/tests/previews/jib_upwind_wm7_before_after.png, jib_upwind_wm12_before_after.png; tools/boatgen/previews/*_upwind.png regenerated.
<!-- SECTION:NOTES:END -->
