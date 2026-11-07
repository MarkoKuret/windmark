---
id: WM-215
title: 'Gamepad on the water: the course map reachable, prompts with the pad''s buttons'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07 18:47'
updated_date: '2026-11-07 19:36'
labels:
  - controls
dependencies: []
priority: low
ordinal: 231000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The course map has no gamepad binding and no pause-menu item (default_bindings.gd ~82), though controls.md 3 says the pad gets it in the pause menu. Prompts name keyboard keys ('[P]', '[H]', 'T turns it back on', 'M CLOSE') even on a pad (hud.gd ~787, player_controls.gd ~279, course_map_view.gd ~469), and the hard-coded letters ignore rebinding.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The map opens from the pad; prompts show the device's binding
<!-- AC:END -->
