---
id: WM-196
title: 'Quirks: penalty sound in free sail and other wrong-mode events'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07 17:44'
updated_date: '2026-11-07 18:01'
labels: []
dependencies: []
priority: high
ordinal: 213000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
In solo free sail the penalty sound plays although there is no race. Sweep every race event (sounds, toasts, flags, HUD feed, rumble) for firing outside a race or at the wrong time, and fix the causes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No race sound, toast or flag fires in free sail (headless test). A written list of quirks found and fixed, with any that remain open filed as tasks.
<!-- AC:END -->
