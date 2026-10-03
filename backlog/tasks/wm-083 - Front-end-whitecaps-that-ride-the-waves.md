---
id: WM-083
title: 'Front end: whitecaps that ride the waves'
status: To Do
assignee: []
created_date: '2026-10-03 17:10'
labels:
  - front-end
  - look
dependencies: []
priority: medium
ordinal: 113000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Whitecaps were removed on 2026-10-03: a scrolling noise texture thresholded on crest height made hard white blotches that popped on and off and slid over the waves. Bring them back with foam that belongs to the waves: a foam value carried per wave component (so it travels with its crest, builds and fades with the crest's steepness), the components' foam combined at the pixel, and a soft graded look from a few density levels of a proper foam texture instead of one hard threshold. Cover should follow the wind (none under about 8 kn, more in puffs). Spec first in water_render.md §4.4.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 water_render.md §4.4 specifies the per-component foam, its combination and the density levels, with constants
- [ ] #2 Caps move with their crests and fade in and out, no popping or sliding in a 60 s headless preview sequence
- [ ] #3 Cover rises with the wind and with the puffs; no caps under 8 kn
- [ ] #4 Cost on tier M stays within the GPU budget (tests/livery_cost.py style proxy or measured)
<!-- AC:END -->
