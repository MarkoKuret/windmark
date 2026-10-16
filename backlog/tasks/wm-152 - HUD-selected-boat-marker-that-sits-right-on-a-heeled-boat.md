---
id: WM-152
title: 'HUD: selected boat marker that sits right on a heeled boat'
status: Done
assignee:
  - '@hudux2'
created_date: '2026-10-16 20:09'
updated_date: '2026-10-16 20:28'
labels:
  - hud
dependencies: []
ordinal: 177000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The square bracket round a selected boat looks out of place when she heels. Replace it with a plain marker that does not rely on an axis-aligned box.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 hud.md §16.4.1 specifies the new marker
- [x] #2 The marker follows the boat's heel (masthead from the pose with heel), no axis-aligned box
- [x] #3 race_hud_test checks the marker with a heeled boat
<!-- AC:END -->
