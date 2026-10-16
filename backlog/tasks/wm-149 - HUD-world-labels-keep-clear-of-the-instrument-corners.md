---
id: WM-149
title: 'HUD: world labels keep clear of the instrument corners'
status: In Progress
assignee:
  - '@hudux2'
created_date: '2026-10-16 20:09'
labels:
  - hud
dependencies: []
ordinal: 174000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
World labels on the water (TACK IN, the mark tag, name tags) must keep clear of the instrument corner blocks as the edge pointers already do.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 hud.md §16.4 specifies the keep-clear rule
- [ ] #2 The tack point label is moved or hidden so it never overlaps the instrument page, radar, helm strip, race bug, wind page or alert lane
- [ ] #3 race_hud_test checks a tack point under a corner block
<!-- AC:END -->
