---
id: WM-098
title: 'Water: whitecaps that look natural from every camera (sparse, non-repeating)'
status: In Progress
assignee:
  - '@sea-look'
created_date: '2026-10-05 15:27'
updated_date: '2026-10-15 18:21'
labels:
  - front-end
  - visuals
dependencies: []
priority: medium
ordinal: 131000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner (2026-10-05): the WM-083 whitecaps are bad: far too many, and they follow a uniform, repeating pattern; really terrible from the helicopter camera; better without them than as is. They are off by default since 2026-10-05 (water_render.md §4.4; --caps=on and the look panel still show them). Redo: cover that matches real seas (about 0.2 % at 15 kn, 1.4 % at 20 kn, 2.5 % at 25 kn) and reads sparse; no visible periodicity or repeated pattern at any camera height (chase to helicopter: check for tiling and for the components' regular crest pattern), irregular sizes and shapes, fading with distance; cost at or below today's on tier M. Show the owner chase and helicopter views at 12, 18 and 24 kn before turning them on by default.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No visible repetition or regular pattern from the chase, aerial and helicopter cameras at 12, 18, 24 kn
- [x] #2 Cover within the measured whitecap fractions
- [x] #3 Tier M frame time unchanged on the M1
- [ ] #4 Owner approves; then on by default
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
sea-look: cover drawn as area by Monahan's law, thresholds calibrated per sea, wave-group envelope breaks the lattice (autocorrelation excess 0.15, was 0.8). Cost on the heli view +0.11/+0.14/+0.13 ms L/M/H (was +0.10/+0.14/+0.10, noise). Still off by default: needs the owner's look (chase and heli previews whitecaps_{12,18,24}kn_{chase,heli}.jpg).
<!-- SECTION:NOTES:END -->
