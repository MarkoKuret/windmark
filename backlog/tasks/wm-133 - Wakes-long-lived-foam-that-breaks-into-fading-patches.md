---
id: WM-133
title: 'Wakes: long-lived foam that breaks into fading patches'
status: In Progress
assignee:
  - '@sea-look'
created_date: '2026-10-15 18:00'
labels:
  - front-end
  - visuals
dependencies: []
ordinal: 165000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The wake reads as a tidy three-stripe pattern. Foam lives longer and breaks up into irregular patches that fade, instead of clean even stripes. Cost stays in the ribbon data and the wake shader; no history loops in the sea shader. water_render.md 5.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Spec 5 describes the longer life and the age-driven breakup
- [ ] #2 Native ribbon and GDScript reference agree (wakes_native_test)
- [ ] #3 Before/after previews of the wake at 19 kn
- [ ] #4 Water tests green
<!-- AC:END -->
