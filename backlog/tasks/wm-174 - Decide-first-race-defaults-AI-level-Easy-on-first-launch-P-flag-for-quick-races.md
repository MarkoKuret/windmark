---
id: WM-174
title: >-
  Decide: first-race defaults (AI level Easy on first launch, P flag for quick
  races)
status: Done
assignee:
  - '@claude'
created_date: '2026-10-17 14:33'
updated_date: '2026-11-07 17:56'
labels:
  - decide-later
dependencies: []
priority: medium
ordinal: 198000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Quick races start against Intermediate AI and every course sets the I flag, so a dip over in the last minute means rounding an end. Proposal from the 2026-10-17 playability review: AI Easy on a fresh profile, P flag for quick races (course files keep their own flag for events).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Owner decides; the chosen defaults are in menus.md and race.md
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decided 2026-11-07 (owner delegated): AI level defaults to Easy (GameSetup.ai_level, so the setup rows start on Easy on a fresh profile; the pick is remembered after that), and an offline quick race flies the P flag whatever the course file says (sail scene core settings, prep_flag 0, next to finish_window off). Reason: a first race should be winnable and a dip over the line in the last minute should cost a dip back, not a trip round an end. Course files keep their own flag for events. Specs: menus.md §1, race.md §2.
<!-- SECTION:NOTES:END -->
