---
id: WM-182
title: >-
  Previews: republish tests/previews with the corrected guide width, dashed
  laylines and the fleet livery shots
status: To Do
assignee: []
created_date: '2026-10-17 14:33'
labels: []
dependencies: []
priority: low
ordinal: 206000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The committed course and race HUD previews were rendered with the 64 px headless window's pixel angle, so the on-water guide lines are about 12x too wide; course_preview_dump.gd now writes the 720 px frame's angle. Refresh course_*.jpg, race_hud_*.jpg and add the fleet shots of livery_preview.py (chase and aerial per class) so the documentation matches the game.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 tests/previews refreshed and game/README.md lists the fleet shots
<!-- AC:END -->
