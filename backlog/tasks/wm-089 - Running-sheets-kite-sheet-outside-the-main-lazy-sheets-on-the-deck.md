---
id: WM-089
title: 'Running sheets: kite sheet outside the main, lazy sheets on the deck'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-04 16:51'
updated_date: '2026-10-04 16:51'
labels:
  - front-end
  - visuals
dependencies: []
priority: medium
ordinal: 118000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner report (2026-10-04): the kite sheet passes through the mainsail, and the lazy sheets go through the deck. Route a flying sail's sheets outside the main, the boom, the headsail, the shrouds and the lifelines (sail_visuals.md 11.3 'Outside route'), continuous through trim changes, tacks and gybes; lay the lazy lines on the real deck and cabin top read from the boat's meshes at load (11.3 'Deck'), draping over edges. Not in scope (owner): the rope texture sliding along a still sheet, the lazy guy, the spinnaker halyard.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Spec first: sail_visuals.md 11.3 and test 21
- [x] #2 Native SheetRopes and SheetRopesRef in parity (routes, drape, deck field)
- [x] #3 sheets_lod_test: over a sweep of configs and trims no flying-sail sheet tube comes within the rope radius of the main, the headsail or the boom; lazy lines at or above the true deck; no pop through a kite trim sweep and a gybe
- [x] #4 Headless previews of the kite sheet route and the lazy sheets on the deck
- [x] #5 Per-redraw cost reported before and after
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Spec: sail_visuals.md 11.3 'Outside route' and 'Deck', test 21. Routes: taut string in plan about a pivot by the mast (Graham scan), obstacles the main and headsail mid-surfaces, the boom box and the rail from the deck field; points fade in at the ends and fade out when well above the line (passes under the boom near the lead); corner allowance per ring spacing. Lazy lines: deck field from every level's deck mesh plus low hardware fittings, 2.5 cm grid, 0.2 m skirt, widened one cell, built natively at load; one-pass drape of every tube every 2.5 cm. Tests (sheets_lod_test): 432 configs per boat, nearest 0.055 m wm7 / 0.044 m wm12 (rope radius 0.0045 / 0.0055), lazy lines at least 0.5 mm above the true deck, ring moves 0.18 / 0.39 m (limits 0.31 / 0.52) through the trim sweep and gybe, native and reference agree. Cost (wm7 jib and kite, debug build, best of batches): about 58 us before, 75 us after. Previews: sheets_* shots in tests/sail_preview_dump.gd (also fixed: the dump now reads the sheets from their shapes; before, headless, it drew them collapsed).
<!-- SECTION:NOTES:END -->
