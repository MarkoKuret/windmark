---
id: WM-124
title: >-
  Look: time of day and conditions instead of light presets; visible grade and
  vignette
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-11 11:37'
labels:
  - front-end
  - look
dependencies: []
ordinal: 158000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner direction 2026-10-11: the race looks different in different conditions and at different times of day. Two inputs (hour, conditions) replace the four light presets; the sun from the hour, the venue latitude and date; the venue look file gives defaults, the race overrides. The colour grade and vignette clearly visible, with strength rows in the F9 panel.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Spec: water_render.md 4.5 time of day, conditions, keyframes, grade and vignette; hud.md 18 rows and hints; data_format.md look file light keys
- [ ] #2 SkyRig: hour and conditions drive sun position, colours, exposure, haze, clouds and grade; old preset names map onto them
- [ ] #3 Venue look files carry light defaults (race window, typical conditions, date); GameSetup and sail test flags --time, --conditions, --sky alias
- [ ] #4 F9 panel: Time of day, Conditions, Grade strength, Vignette strength rows, a where-to-look hint on every row
- [ ] #5 Grade and vignette clearly visible by default, white sails stay white at midday, strength 0 is off
- [ ] #6 Low sun checked against the shadow settings; race window clamped where shadows break
- [ ] #7 Headless tests: sun position, keyframe continuity, conditions x hour, flags and aliases, panel round trip, grade bounds
- [ ] #8 Previews: daylight contact sheet, conditions at 14:00, grade off vs default
<!-- AC:END -->
