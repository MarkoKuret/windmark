---
id: WM-011
title: 'Core: C API for front end and server'
status: To Do
assignee: []
created_date: '2026-09-25 13:31'
updated_date: '2026-09-25 17:14'
labels:
  - core
dependencies: []
priority: medium
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Stable C interface over the world: create race, add boats, controls, step, state, events. The front end also needs a trim_speed table lookup (HUD trim tolerance) and a render pose (interpolated between ticks) or it keeps them on its side; see game/scripts/sim/sim_source.gd for the SimSource interface the binding must fill.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Documented header
- [ ] #2 Used by a headless example
<!-- AC:END -->
