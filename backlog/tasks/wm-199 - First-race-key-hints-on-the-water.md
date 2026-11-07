---
id: WM-199
title: First-race key hints on the water
status: To Do
assignee: []
created_date: '2026-11-07 18:05'
labels:
  - playability
  - hud
dependencies: []
priority: medium
ordinal: 216000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A new player sails off with nothing on screen saying which keys steer, sheet, let fly, toggle auto trim or open the menu (the menus' key line is the only key help). Proposal: during the free sailing before the warning signal of a quick race (and the first minute of a free sail) one quiet line in the helm notes, built from the player's bindings: 'Arrows steer · W S sheets · Space let fly · T auto trim · Esc menu'; gone at the warning signal or on any of those keys; shown until the profile has finished a race (a settings flag), then never. Keep it out of the sail hint's slot and the capture frames.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The hint line shows on a fresh profile before the warning signal and goes at the signal or on a key
- [ ] #2 It reads the player's bindings and never shows once a race has been finished
<!-- AC:END -->
