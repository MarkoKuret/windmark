---
id: WM-213
title: >-
  HUD units and jargon pass: degree signs, units on AWS/COG/TWD, BURN seconds vs
  S for starboard, P/S vs L/R
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07 18:47'
updated_date: '2026-11-07 19:34'
labels:
  - hud
dependencies: []
priority: low
ordinal: 229000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Headings show no degree sign (hud_format.gd ~21); AWS, COG, TWD in the Data row have no unit (hud_paint.gd ~173); the Data helm reads '35 S' with no %; BURN's unit is 'S' for seconds, the same letter as S for starboard on TWA and heel; sides are P/S on TWA and heel but L/R on the relative bearing (hud_format.gd ~84). TWA, VMG, BIAS PIN, LIFT/HEADER have no legend anywhere (WM-096 can carry a glossary).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 One side convention; every number with a unit where the label does not say it
<!-- AC:END -->
