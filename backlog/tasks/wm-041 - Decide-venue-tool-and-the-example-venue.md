---
id: WM-041
title: 'Decide: venue tool and the example venue'
status: Done
assignee: []
created_date: '2026-09-25 15:52'
updated_date: '2026-10-06 10:00'
labels:
  - decide-later
dependencies:
  - WM-016.08
priority: low
ordinal: 37000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
data/venues/example_bay.venue.json was made with a throwaway script (not committed). Replace it with generated output once a venue tool exists, and should a generator script be committed now? Owner question from WM-026, set aside on 2026-09-25: answer once the game runs (after WM-016.08, sail one boat).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Owner decided; spec and code updated to match
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Outcome (WM-105): the venue tool exists as tools/venuegen. example_bay is now generated from the committed source data/venue_sources/example_bay.venuesrc.json (same island, pier and rock; fields from the land shape) and the tool's tests check every committed venue equals its regenerated output. Model and source format: docs/specs/venues.md §5.
<!-- SECTION:NOTES:END -->
