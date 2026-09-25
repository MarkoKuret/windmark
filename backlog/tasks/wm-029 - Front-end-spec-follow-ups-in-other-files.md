---
id: WM-029
title: Front-end spec follow-ups in other files
status: Done
assignee:
  - '@claude'
created_date: '2026-09-25 15:03'
updated_date: '2026-09-25 15:38'
labels:
  - boats
dependencies: []
priority: medium
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the front-end specs: boatgen writes a sails.<id>.look block in the sidecar (from visual.sails.<id>.look with defaults from sail_visuals.md section 4) and a pole node for symmetric-spinnaker classes, README visual keys updated; conventions.md gets the Godot scene axes (now in cameras.md section 1); data_format.md section 6 notes where the front-end venue look file lives; sails.md 7 optionally outputs beta_t for winch sounds.

Split: the data_format.md section 6 venue look note moved to the env-venue work and sails.md section 7 beta_t to the vpp-tack work; this task covers the rest.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 boatgen sidecar has look blocks and pole node
- [x] #2 conventions.md and data_format.md updated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- boatgen: sails.<id>.look in the sidecar (class file visual.sails.<id>.look, unknown keys rejected, defaults and size rules of sail_visuals.md 4); pole node and rig.pole_pivot/pole_axis/pole_length/pole_end for classes flying a spinnaker on a pole; symmetric-spinnaker test fixture in tools/boatgen/tests/fixtures, unit tests in tools/boatgen/tests, fixture also run by the Godot import test.
- data_format.md 3.7: visual row mentions the look block. conventions.md 11: Godot scene frame, model axes and boat node basis; cameras.md 1 and water_render.md reference it.
- Furled sails (down on a furler) stay hidden per the owner decision; nothing built for drawing them.
- Sidecar for wm12/wm7: only sails.<id>.look added; perf_inputs, GLBs and previews unchanged.
- AC 2 covers conventions.md and data_format.md 3; the data_format.md 6 note is in the env-venue work.
<!-- SECTION:NOTES:END -->
