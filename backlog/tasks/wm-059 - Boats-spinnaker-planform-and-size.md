---
id: WM-059
title: 'Boats: spinnaker planform and size'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-09-25 20:42'
updated_date: '2026-09-29 21:40'
labels:
  - boats
dependencies: []
priority: high
ordinal: 81000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner after the first races (2026-09-25): the gennakers and spinnakers are far too big and their shape is weird, on wm7 and on wm12. Measured: wm7 kite luff 10.8 m, leech 10.3 m, foot 9.1 m (0.84 of the luff; typical 0.55 to 0.65) with the clew 0.3 m behind the transom, because boatgen stretches the planform to hit the class file's 60 m2; wm12 A2 foot 12.5 m on an 18.6 m luff, 150 m2. Fix: boatgen draws asymmetric and symmetric spinnakers (and code zeros) from standard proportions (foot about 0.6 of the luff, a wide mid girth, clew near the transom when set), and the class files take the area that planform gives, erring small (owner: both are way too big). Then regenerate data/perf with the VPP.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Kite planforms follow standard proportions; clew near the transom
- [x] #2 wm7 and wm12 kite areas reduced to what the planform gives; data/perf regenerated
- [ ] #3 Owner looks at the new kites and they no longer look huge
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Planform rule in docs/specs/data_format.md 3.5 and tools/boatgen/README.md. Class areas now the planform's rule area rounded down to 0.5 m2: wm7 kite 60 -> 43.0, wm12 a2 150 -> 126.0, code0 82 -> 81.0. AC2: class areas done on branch kites; data/perf still to be regenerated after the feel branch merges (coordinator).

2026-09-29: class areas are the planform's rule area rounded down to 0.5 m2 (wm7 kite 43.08 -> 43.0, wm12 a2 126.19 -> 126.0, code0 81.36 -> 81.0; originally 60, 150, 82). data/perf regenerated with the VPP from the class files and the boatgen sidecar: byte-identical to the committed tables and plots (already built from these areas in b880046 and later). VPP 46 tests, core ctest (-LE ai_long) 3/3 pass.
<!-- SECTION:NOTES:END -->
