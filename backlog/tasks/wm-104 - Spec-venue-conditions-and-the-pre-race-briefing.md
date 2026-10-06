---
id: WM-104
title: 'Spec: venue conditions and the pre-race briefing'
status: In Progress
assignee:
  - '@venues-spec'
created_date: '2026-10-06 08:27'
updated_date: '2026-10-06 08:30'
labels:
  - venues
dependencies: []
priority: high
ordinal: 141000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Each venue carries its own conditions instead of the race layer's generic defaults: wind speed range and typical directions, shift preset and trend, puff parameters, current and tide, swell, fetch. The quick race card shows a short standardized briefing built from that data (Wind, Shifts, Gusts, Current, Sea, with fixed rating words and thresholds) plus one hand-written Tip line. Owner decisions 2026-10-06: real venues, briefing on the quick race card only. Also choose the coastline data source (permissive licence, recorded in docs/THIRD_PARTY.md).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 data_format.md §6 has a conditions block and briefing fields; wind.md, sea.md, race.md and menus.md say how the race layer and the card use them
- [ ] #2 Rating words and thresholds for each briefing line are defined in the spec, so the text follows from the numbers
- [ ] #3 Coastline data source picked and recorded
- [ ] #4 Performance budget per venue in the spec: land as few meshes with one shared material and LODs, simplified coastline (vertex cap), grid sizes capped, wind and current lookups no costlier than example_bay; no per-frame work added
<!-- AC:END -->
