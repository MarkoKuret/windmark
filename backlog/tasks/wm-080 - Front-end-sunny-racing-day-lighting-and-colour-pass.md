---
id: WM-080
title: 'Front end: sunny racing-day lighting and colour pass'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-01 10:30'
updated_date: '2026-10-01 11:00'
labels:
  - front-end
  - visuals
dependencies: []
priority: high
ordinal: 110000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner feedback 2026-10-01: the default daytime scene looks flat and washed out next to Virtual Skipper 5. Bright saturated sky with sun disc, halo and cumulus (presets clear, fair, hazy), stronger warmer sun with correct exposure and tonemap, blue-ish shadows, deep blue water with a strong Fresnel sky gradient and sun glitter, whitecaps as wind-driven streaks, boats and sails not blown out. Per-pixel cost on tier M at or below the previous. Laylines and course overlays are out of scope (owner decision 2026-10-01: race graphics stay as they are; WM-016.23 unchanged).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 water_render.md holds the target look (colours, exposure, sky presets, foam rule) before code
- [x] #2 Sky: saturated gradient, sun disc with halo, readable cumulus, 2-3 presets, bright default
- [x] #3 Sun, exposure and tonemap give a bright, high-contrast picture with blue-ish shadows
- [x] #4 Water: deep blue body, strong Fresnel sky gradient, sun glitter, streaky whitecaps only with wind
- [x] #5 Boats and sails read well in the new light
- [x] #6 Before/after pairs of 4 shots; water, UI, sail visuals and course land tests pass
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Before/after: game/generated/lighting_before_after.png (not committed). Sky presets clear/fair/hazy in SkyRig (--sky= in the sail test); exposure 0.50, ACES white 6, glow per tier from SkyRig.apply_quality. Water: slope contrast term removed, glint tap added (net about equal GPU time in the preview timing). Course preview now binds the venue land texture (it read another unit before). Follow-up: venue look files should pick the preset.
<!-- SECTION:NOTES:END -->
