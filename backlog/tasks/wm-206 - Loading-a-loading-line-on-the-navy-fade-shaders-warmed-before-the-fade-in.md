---
id: WM-206
title: 'Loading: a loading line on the navy fade, shaders warmed before the fade-in'
status: To Do
assignee: []
created_date: '2026-11-07 18:47'
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
- [ ] #1 A loading line shows when the build takes longer than 0.3 s
- [ ] #2 No first-frame shader stutter after the fade-in
<!-- AC:END -->
