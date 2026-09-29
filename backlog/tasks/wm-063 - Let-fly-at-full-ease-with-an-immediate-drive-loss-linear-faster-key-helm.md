---
id: WM-063
title: 'Let-fly at full ease with an immediate drive loss; linear, faster key helm'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-26 12:19'
updated_date: '2026-09-29 17:27'
labels:
  - vpp
dependencies: []
priority: high
ordinal: 89000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner (2026-09-26): (1) letting the sails fly must never take a sail past its fully eased position (today let-fly releases past sheet_max to the wind line, so the boom can go forward of the mast); (2) let-fly should put the sheets at fully eased at once and apply the drive of the regular trim table for that position immediately, so e.g. downwind with the sheets flying the boat still moves significantly, upwind it loses drive at once; (3) the key helm should move linearly (no ramp), a bit faster than the old 0.6/s. Spec first (sails.md 5.3/5.4, boat.md 5.8, controls.md 5.2), then VPP if a table changes, core, front end, AI.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No sail angle beyond sheet_max with let-fly, in the core and drawn
- [x] #2 Let-fly drive from the regular trim table at full ease, applied at once; flog drag only where the table says the sail luffs
- [x] #3 Key helm linear at a fixed rate, centring at the same rate
- [x] #4 Owner sails it and approves
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner (2026-09-29): let-fly approved.
<!-- SECTION:NOTES:END -->
