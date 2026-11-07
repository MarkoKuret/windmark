---
id: WM-211
title: >-
  Pause menu and settings quirks: live volume and quality from the pause menu,
  naming, Reset section
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07 18:47'
updated_date: '2026-11-07 19:29'
labels:
  - polish
dependencies: []
priority: low
ordinal: 227000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the pause menu only the display keys apply live; volumes, quality, controls and HUD wait for Done (pause_menu.gd ~260) while the main menu applies them at once. The welcome screen says 'Steering' and Settings 'Helm keys' for the same thing. Reset section in Graphics also drops fullscreen (settings.gd ~320). Bindings show raw action ids ('Sail 1', 'Drop front', 'Camera orbit drag', settings_panel.gd ~297). Stick dead zone shows '0.10' where other rows show %. Course names carry '2 laps' next to the '2 laps, 6 legs' caption.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Volumes and quality apply live from the pause menu
- [x] #2 One name for the helm key mode; bindings in plain words; dead zone as %
<!-- AC:END -->
