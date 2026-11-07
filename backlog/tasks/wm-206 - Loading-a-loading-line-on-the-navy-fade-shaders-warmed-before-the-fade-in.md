---
id: WM-206
title: 'Loading: a loading line on the navy fade, shaders warmed before the fade-in'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-07 18:47'
updated_date: '2026-11-07 19:37'
labels:
  - polish
dependencies:
  - WM-180
priority: medium
ordinal: 222000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Start race, Race again and Main menu each freeze on a navy screen for about 1.2 s (everything builds synchronously in sail_test.gd ~230-333, PERFORMANCE.md 530) and the custom shaders compile on first use while the fade-in runs. Keep the fade but show a quiet 'Setting up the course' line (and the venue name) after 0.3 s, and warm the shaders behind it (PERFORMANCE.md A8).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A loading line shows when the build takes longer than 0.3 s
- [ ] #2 No first-frame shader stutter after the fade-in
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Loading line (menus.md §5): SceneFade draws the line on the navy two frames before the change when the last build of that scene this session took over 0.3 s or it has not been built yet; Setting up <venue> for a race or restart, the venue name for free sail, Setting up the scenario, Back to the menu. menus_test checks it. Warm-up: ShaderWarmup puts a tiny copy of every new mesh and shader combination in front of its camera for 2 frames under the opaque navy; the navy holds until the mesh, surface and draw pipeline counters stop rising (3 frames to 1 s). AC 2 needs a windowed check (headless renders nothing): godot --path game -- --fade-log, Start race, Race again, Main menu; in_pipelines draw should read 0.
<!-- SECTION:NOTES:END -->
