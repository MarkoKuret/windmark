---
id: WM-086
title: 'Front end: full speed on a non-Retina screen next to a Retina Mac (mixed-DPI)'
status: To Do
assignee: []
created_date: '2026-10-04 10:54'
labels:
  - front-end
  - performance
dependencies: []
priority: low
ordinal: 116000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Postponed by the owner (2026-10-04). On a MacBook Air M1 with an external 3440 x 1440 ultrawide (Samsung LS34A650U, set to 3440 x 1440, scale 1.0) as the main display, Godot 4.6 reports that screen as 6880 x 2880 and renders full screen there at 2x (it seems to use the highest screen scale, the laptop's 2.0, for every screen), so macOS downsamples a 20 MP frame. Measured on tier M, 10 boats: 21 fps before, 37.7 fps after the Auto render scale pixel cap (3D 2359 x 988); the rest is window-size work (upscale, HUD, compositor). The laptop screen gives 74 fps. Fix idea: render at the screen's real backing scale (a small macOS patch in the GDExtension setting the Metal layer's contentsScale, or a Godot fix/upgrade); confirm the cause first with a probe.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Cause confirmed on the owner's setup
- [ ] #2 Tier M at 60 fps full screen on the ultrawide with 10 boats
<!-- AC:END -->
