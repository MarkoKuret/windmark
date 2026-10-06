---
id: WM-099
title: 'Front end: sea drawn inside open cockpits when heeled'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-05 15:44'
updated_date: '2026-10-06 13:30'
labels: []
dependencies: []
ordinal: 137000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The sea surface is drawn through the hull, so with an open transom the leeward cockpit floor corner shows water whenever it sits below the sea. A headless probe showed the cause is heel (15 to 29 deg puts the leeward cockpit corner at the transom 0.25 to 0.35 m lower), waves only add to it; without heel the cockpit floor stays dry. Fix in rendering only: the water is not drawn inside the cockpit well of nearby boats. Boat motion is unchanged.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 water_render.md describes the dry cockpit mask and its test
- [x] #2 boatgen writes the cockpit well (body frame) into the physics sidecar
- [x] #3 the sea shaders of every tier skip water inside the cockpit well of up to 8 nearby boats
- [x] #4 headless tests cover the mask (CPU mirror, shader parse) and the boat motion is unchanged
- [x] #5 heeled hulls float: the generator computes rise and trim per heel from the drawn hull, the VPP copies them, the core adds them to the heave and pitch targets (boat.md 5.6)
- [x] #6 cockpit floor wet at most 2 % of the time in 25 kn (probe), heel and speed unchanged; the water mask off by default (--dry-cockpits)
<!-- AC:END -->
