---
id: WM-078
title: 'Front end: cheap per-pixel slope of faded waves (tier M)'
status: Done
assignee: []
created_date: '2026-10-01 10:07'
updated_date: '2026-10-01 10:19'
labels:
  - front-end
  - performance
dependencies: []
ordinal: 109000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
On the M1 (2880x1800, tier M, 10 boats) the water shader costs about 8.3 ms of GPU per frame more on M than on L; about 4 ms of it (on mains) is wm_faded_slope, which runs every wave component per water pixel with two wm_fade calls (length, division, smoothstep), a branch and a sin. Upload the components sorted by wavelength (longest first) with their wavelengths (comp_lam), and loop only over the band 2*px < lam < 4*s, with no visible change (water_render.md §3.2, §4.1, §7).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 water_render.md §3.2, §4.1 and §7 describe the sorted components, comp_lam and the band bound
- [x] #2 SeaModel sorts the components by wavelength, longest first, and the sea uploads comp_lam; every user of comp checked (water, wake, bow, mist, previews)
- [x] #3 wm_faded_slope skips lam >= 4s, stops at lam <= 2px and computes the weight from comp_lam
- [x] #4 water_test checks comp_lam matches the components and is sorted
- [x] #5 offline previews before and after equal within a small tolerance (max and mean pixel difference reported)
- [x] #6 run_water_test.sh, run_ui_tests.sh and run_sail_visuals_test.sh pass
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Previews: the same dump rendered with the old and the new loop differ by at most 1/255 on at most 2 pixels per 1280x720 shot (mean below 1e-5); the full dump-and-render pipeline differs only at its own run-to-run noise (wake and mist, max 8 to 33, mean below 0.008, as two runs of the old code). Per pixel (preview scenes, 10 components): the band evaluates the same components the old loop found w > 0 for (mean 1.2 to 8.3), so the bound is exact; the skipped long components cost a compare. Windowed M1 measurement still to do by the owner.
<!-- SECTION:NOTES:END -->
