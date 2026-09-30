---
id: WM-077
title: 'Front end: native wakes, bow waves and mist'
status: In Progress
assignee: []
created_date: '2026-09-30 04:38'
updated_date: '2026-09-30 05:05'
labels:
  - front-end
  - performance
dependencies: []
ordinal: 108000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The wakes section costs about 2 ms per boat with wakes on the M1 (tier M 13 to 17 ms, H 18 to 26 ms): GDScript WakeRibbon step and build_arrays, BowWave.build_arrays, meshes rebuilt every frame, and the mist MultiMesh written instance by instance. Move them to native classes in game/native (the GDScript kept as the reference), update fixed-size mesh buffers in place, and write the mist in one buffer call, with the same look (water_render.md §5).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 WakeRibbon step and mesh building and BowWave mesh building run natively (GDExtension), the GDScript kept as the reference and used when the extension is missing
- [x] #2 Sea height for the wakes evaluated natively from the wave components passed once per frame, matching SeaModel.height within float tolerance
- [x] #3 Ribbon and bow wave meshes updated in place in fixed-size buffers, not rebuilt each frame
- [x] #4 Mist MultiMesh written with one multimesh_set_buffer call
- [x] #5 Parity test native vs GDScript reference (vertex positions and attributes within a tolerance) in game/tests
- [x] #6 run_water_test.sh, run_ui_tests.sh and run_sail_visuals_test.sh pass
- [x] #7 Headless wakes_ms before/after at L, M, H recorded; at most 0.3 ms per boat with wakes at M and H
- [ ] #8 Windowed check on the owner's M1 (tier M 60 fps with 10 boats)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Headless wakes_ms (sail_test --race --fleet=10, 20 s, mean of seconds 6 to 20), before -> after: L 2.14 -> 0.19 ms (1 boat), M 11.49 -> 0.53 ms (7 boats, 0.08 ms per boat), H 17.67 -> 0.73 ms (10 boats, 0.07 ms per boat). Micro benchmark (wakes_native_test, tier H, spray and mist, full ribbons): native 0.044 ms per boat, reference 1.72 ms. Parity: ribbon positions within 3.1e-5 m (float32 at a few hundred metres), UV, UV2, colours and indices identical; bow wave and mist identical; SeaSampler equals SeaModel.height exactly; in-place buffers byte for byte as Godot encodes them. Headless uses the dummy renderer, so the buffer uploads are not in these numbers: the windowed check on the M1 is left for the owner (criterion 8).
<!-- SECTION:NOTES:END -->
