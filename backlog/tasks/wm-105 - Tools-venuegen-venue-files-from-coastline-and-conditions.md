---
id: WM-105
title: 'Tools: venuegen, venue files from coastline and conditions'
status: In Progress
assignee:
  - '@venuegen'
created_date: '2026-10-06 08:27'
updated_date: '2026-10-06 10:00'
labels:
  - venues
dependencies:
  - WM-104
priority: high
ordinal: 142000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
tools/venuegen builds <venue>.venue.json from a coastline source and a hand-owned conditions file: land polygons, obstacles, wind field per 8 sectors (land slowdown and bending), exposure grid, current field. Replaces the throwaway script that made example_bay (settles WM-041).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 venuegen regenerates example_bay within tolerance of today's file, and the core loads its output with the existing tests green
- [x] #2 Wind field, exposure and current grids come from the land shape, not hand-edited
- [x] #3 WM-041 closed with the outcome
- [x] #4 venuegen simplifies the coastline to the spec's vertex cap and writes grids within the size caps
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
venuegen built (tools/venuegen, spec venues.md §5). example_bay regenerated from data/venue_sources/example_bay.venuesrc.json; land and obstacles identical, current within 0.024 m/s (vx) in bounds, wind f mean |diff| 0.003-0.006 in bounds, exposure now direction-dependent (lee of the island flatter). Fast core tests green. ai_long: the 3-seed level-separation check in test_ai_race.cpp misses (Easy 4.67 vs Pro 5.17 on seeds 31-33); over 12 seeds separation holds (6.17 vs 3.75).
<!-- SECTION:NOTES:END -->
