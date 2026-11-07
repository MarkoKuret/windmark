---
id: WM-214
title: >-
  Sailing feedback at the defaults: trim tell-tales with auto trim, V
  wind-shadow view, the sail strip and busy flash
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07 18:47'
updated_date: '2026-11-07 19:36'
labels:
  - hud
dependencies: []
priority: medium
ordinal: 230000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
With the defaults (auto trim on, Standard assist, Glance or Race density) the player gets no word on luffing, stalled or in irons: the trim tell-tales hide while auto trim is on (hud.gd ~732) and at Glance (~746); let fly shows no LET FLY word (hud_paint.gd ~606). The V key (wind_shadow_view) is bound but nothing reads it, and the hud.md 3.1 'Bad air' readout is missing. controls.md 5.4's sail strip (slot names and keys) and the busy flash (set, never drawn, hud.gd ~573) do not exist, so nothing says which number key hoists which sail.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A one-word state (Luffing, Stalled, In irons, Let fly) shows at Race density with auto trim on
- [x] #2 V shows the wind shadow or is unbound; the sail strip or an equivalent says the sail keys
<!-- AC:END -->
