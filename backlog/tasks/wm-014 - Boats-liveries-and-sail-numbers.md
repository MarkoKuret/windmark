---
id: WM-014
title: 'Boats: liveries and sail numbers'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-25 13:31'
updated_date: '2026-10-01 11:15'
labels:
  - boats
dependencies: []
priority: low
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Decal pipeline through uv1 for hull liveries and sail numbers.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Two example liveries in previews
- [x] #2 Livery file format specified (data_format.md §8) with 12+ liveries per class
- [x] #3 Fleet rule: player's choice, AI distinct, deterministic from the race seed
- [x] #4 Liveries applied at runtime without regenerating meshes, one text texture per boat, no extra draw calls
- [x] #5 Sail numbers on both sides per Appendix G (starboard uppermost), insignia on the main
- [x] #6 Livery row in Quick race and Free sail (menus.md)
- [x] #7 Headless livery test and previews of a start line, hull sides and mains
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Spec: data_format.md §8, sail_visuals.md §11.2, menus.md §1. Code: game/scripts/livery/, shaders hull_livery/sail_livery/livery_text.gdshaderinc. Tests: tests/livery_test.gd (run_livery_test.sh, run_boat_import_test.sh). Previews: tests/previews/livery_*.jpg. Follow-up for WM-016.31: when the LOD files load, call BoatLivery on the LOD meshes too (same slot names and uv1).
<!-- SECTION:NOTES:END -->
