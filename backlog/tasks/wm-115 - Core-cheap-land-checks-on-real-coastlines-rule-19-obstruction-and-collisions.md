---
id: WM-115
title: >-
  Core: cheap land checks on real coastlines (rule 19 obstruction and
  collisions)
status: In Progress
assignee:
  - '@land-cull'
created_date: '2026-10-06 11:37'
updated_date: '2026-10-06 11:37'
labels:
  - venues
  - perf
dependencies: []
priority: high
ordinal: 152000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the Fremantle venue (WM-108): the rule 19 obstruction check skips land only by each polygon's bounding circle; a mainland polygon's circle covers the whole course, so every check walks all its edges. Core tick 60 us -> 1800 us with 10 boats, 1.5 -> 18.7 ms with 40. Every real venue hits this. Fix with identical results (e.g. distance-to-edges cull or a per-venue edge grid built at load); check collisions and any other per-tick land query too.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Core tick at Fremantle within 10% of example_bay with 10 and 40 boats (same wind)
- [ ] #2 Results bit-identical: determinism and checksum tests unchanged
- [ ] #3 venues.md §4 budget says how land queries stay constant cost
<!-- AC:END -->
