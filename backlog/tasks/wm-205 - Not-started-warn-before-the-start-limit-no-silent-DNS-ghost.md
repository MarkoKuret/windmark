---
id: WM-205
title: 'Not started: warn before the start limit, no silent DNS ghost'
status: To Do
assignee: []
created_date: '2026-11-07 18:47'
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
- [ ] #1 Warnings before the limit and a banner at it
<!-- AC:END -->
