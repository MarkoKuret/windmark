---
id: WM-105
title: 'Tools: venuegen, venue files from coastline and conditions'
status: To Do
assignee: []
created_date: '2026-10-06 08:27'
updated_date: '2026-10-06 08:27'
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
- [ ] #1 venuegen regenerates example_bay within tolerance of today's file, and the core loads its output with the existing tests green
- [ ] #2 Wind field, exposure and current grids come from the land shape, not hand-edited
- [ ] #3 WM-041 closed with the outcome
- [ ] #4 venuegen simplifies the coastline to the spec's vertex cap and writes grids within the size caps
<!-- AC:END -->
