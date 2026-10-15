---
id: WM-133
title: 'Wakes: long-lived foam that breaks into fading patches'
status: In Progress
assignee:
  - '@sea-look'
created_date: '2026-10-15 18:00'
updated_date: '2026-10-15 19:33'
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
- [x] #1 Spec 5 describes the longer life and the age-driven breakup
- [x] #2 Native ribbon and GDScript reference agree (wakes_native_test)
- [x] #3 Before/after previews of the wake at 19 kn
- [x] #4 Water tests green
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Wake shape 2026-10-15: bow ribbon at the Froude wedge angle (19.5/12/9.5 deg at 8/15/19 kn) with thin broken lines inside its edges, transom ribbon = turbulent wake; no foam in the spray margin. Previews game/generated/sea_look/wake_chase.jpg, wake_aerial.jpg.
<!-- SECTION:NOTES:END -->
