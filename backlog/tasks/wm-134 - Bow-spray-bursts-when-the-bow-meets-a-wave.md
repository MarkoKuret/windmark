---
id: WM-134
title: Bow spray bursts when the bow meets a wave
status: In Progress
assignee:
  - '@sea-look'
created_date: '2026-10-15 18:00'
updated_date: '2026-10-15 18:28'
labels:
  - front-end
  - visuals
dependencies: []
ordinal: 166000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
No bow spray at 19 kn in a 25 kn sea. Drive the existing bow wave sheet and mist by the bow's vertical speed relative to the sea surface (the front end evaluates the sea as the core does, sea.md 7), scaled by boat speed. No new particle systems. water_render.md 5.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Spec 5 gives the relative bow speed law for the sheet and mist
- [x] #2 Native and reference agree; mist cap unchanged
- [ ] #3 Before/after bow previews
- [x] #4 Water tests green
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Offline previews use the water test's placeholder boat, whose bow follows the sea without the physics heave lag, so it rarely plunges: the bursts need the engine clip to judge (bow previews in game/generated/sea_look/step4_bow.jpg show no change).
<!-- SECTION:NOTES:END -->
