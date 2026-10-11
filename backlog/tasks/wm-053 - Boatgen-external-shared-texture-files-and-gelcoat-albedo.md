---
id: WM-053
title: 'Boatgen: external shared texture files and gelcoat albedo'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-25 19:08'
updated_date: '2026-10-11 12:25'
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
- [x] #1 GLBs reference one shared texture set on disk
- [x] #2 Gelcoat albedo at most 0.8 linear in the data
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Gelcoat mean 0.72 linear, factor 0.78 with the texture set (WM-064); test in tests/test_textures_ao.py. Shared texture files: the command line writes the set once into <out>/_tex/ (textures.write_shared, with Godot .import files) and every GLB references it by relative URI (_tex/<file>), no image data in the GLB; in place since the game levels of detail (2e734f2). Covered by test_textures_ao.SharedTextureFilesTest and the game's boat_import_test (atlas path under res://generated/boats/_tex/) and boat_materials_test (one shared atlas); Godot imports one copy of each file for all boats.
<!-- SECTION:NOTES:END -->
