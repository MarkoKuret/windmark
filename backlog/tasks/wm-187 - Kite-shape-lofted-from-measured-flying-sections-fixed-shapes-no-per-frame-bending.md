---
id: WM-187
title: >-
  Kite shape: lofted from measured flying sections (fixed shapes, no per-frame
  bending)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-03 09:00'
updated_date: '2026-11-03 11:21'
labels:
  - sails
  - look
dependencies: []
priority: high
ordinal: 211000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Four kite models (the hinge model on main, balloon, inflated cloth, sculpted) bent the flat grid every frame and then corrected it locally (clearance push, forestay shift, clew solve, twist, tack pin); where the corrections overlap the cloth dents and bulges. New model: the flying shape is lofted once by the generator from measured full-scale sections (J/80, Deparday et al. 2016), scaled to the class planform with the cloth length kept, and at run time only blended by AWA and placed as a whole. wm7 only for now; other classes stay on the hinge model until their section data arrives.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Spec: a lofted spinnaker subsection in docs/specs/sail_visuals.md, its keys in §4.1 and the kite shape file in data_format.md, Deparday et al. 2016 cited
- [x] #2 Measured section data in a per-kite data file (sections at two or more AWAs, source cited), documented
- [x] #3 boatgen lofts each measured AWA through the sections, scaled to the class planform with each section's arc equal to the flat girth, and writes the shapes as generated data
- [x] #4 Runtime (native SailShape and SailShapeRef, in parity): grid mapped to the loft, AWA blend, rigid placement (tack on its fitting, head at the halyard, clew toward its sheet), fill and flutter; no clearance push, forestay shift, clew solve or extra twist; hoist and drop work; sheet straight from the clew
- [x] #5 `model` key per kite set block (`loft` or `hinge`), loft on wm7 only; kite tuner model switch with a depth scale and a rotation trim
- [x] #6 GDExtension rebuilt; sail visuals, parity, kite tuner, boatgen and UI tests green; a test measures camber, draft and twist by height on the drawn wm7 kite against the J/80 table at both AWAs and between
- [x] #7 Headless comparison sheets for wm7 (hinge against loft, AWA about 64, 95, 124; leeward side, stern quarter, bow quarter) in docs/design/kite_loft_2026-11-03/, checked for dents, bulges, creases, cloth through the main or forestay and the sheet angle
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Lofted kite model (sail_visuals.md 6.5) on wm7 from the J/80 sections (Deparday et al. 2016). Owner to judge the previews in docs/design/kite_loft_2026-11-03/. Open: the clew's sheet angle (18 deg reach, 12 deg run at the nominal trims, up to 48 deg over-sheeted), the turn-out clearance on close reaches (up to 27 deg), measured sections for the other classes.
<!-- SECTION:NOTES:END -->
