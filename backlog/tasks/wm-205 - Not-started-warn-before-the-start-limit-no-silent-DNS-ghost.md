---
id: WM-205
title: 'Not started: warn before the start limit, no silent DNS ghost'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07 18:47'
updated_date: '2026-11-07 19:53'
labels:
  - playability
dependencies:
  - WM-201
priority: medium
ordinal: 221000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A boat that never starts becomes a DNS ghost at +4:00 with no banner (the GHOSTED event has no branch in race_hud_values.gd ~967) and the race closes early. Show 'Start within 1:00 or you are out' style warnings at 2:00 and 1:00 before the limit and a banner at the limit. The results title now says DID NOT START (fixed 2026-11-07).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Warnings before the limit and a banner at it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
hud.md 9.4: the viewed boat not started gets a yellow 4 s banner at 2:00 and 1:00 before the start limit ('Start within 2:00 or you are out (DNS)', OCS: 'Return within 2:00 or you score OCS'); her Ghosted DNS event gives the red full-width 'DID NOT START: no start within 4:00' (another boat's: feed line '<boat> did not start'); a released OCS boat gets 'Not returned: you score OCS'. The start limit comes from the race record (start_limit_s added to wm_race_info and CoreSim.race()). Tests: race_hud_test 'start limit'; the core race in race_hud_test shows both warnings for a late starter.
<!-- SECTION:NOTES:END -->
