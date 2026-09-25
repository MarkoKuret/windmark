---
id: WM-002
title: 'VPP: gate and smooth planing'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-25 13:31'
updated_date: '2026-09-25 14:08'
labels:
  - vpp
dependencies: []
priority: high
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Planing depends on hull weight relative to length so heavy displacement boats never plane; the planing onset is smoothed so sportsboat polars have no hard jump.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 wm12 shows no planing jump at 30 kn
- [x] #2 Sportsboat still takes off but continuously
- [x] #3 Tests for both
<!-- AC:END -->
