---
id: WM-053
title: 'Boatgen: external shared texture files and gelcoat albedo'
status: To Do
assignee: []
created_date: '2026-09-25 19:08'
labels:
  - boats
dependencies: []
priority: low
ordinal: 70000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From WM-016.16: the texture set is embedded in every GLB, so each GLB carries its own copy on disk (only one in memory now); write it as external image files so the importer shares one copy on disk. Gelcoat factor fdfeff is about 0.98 linear and the boat shader caps albedo at 0.8: lower it in the class and boatgen data instead.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GLBs reference one shared texture set on disk
- [ ] #2 Gelcoat albedo at most 0.8 linear in the data
<!-- AC:END -->
