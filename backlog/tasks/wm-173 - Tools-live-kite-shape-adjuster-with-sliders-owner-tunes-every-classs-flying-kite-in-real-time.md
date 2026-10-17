---
id: WM-173
title: >-
  Tools: live kite shape adjuster with sliders (owner tunes every class's flying
  kite in real time)
status: To Do
assignee: []
created_date: '2026-10-17 11:56'
labels:
  - tools
  - sails
dependencies: []
priority: high
ordinal: 197000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner: kite shapes are still poor; wants a manual adjuster to shape them in real time with sliders. A windowed Godot tool (owner runs it): pick class and kite (symmetric on a pole or asymmetric), wind angle and gybe; sliders for the set-shape parameters the native SailShape uses (depth/camber and draft position per height, how far ahead of the forestay, foot round and sag, head and clew positions, twist, luff and leech curl, girths); the kite updates live through the same native code the game uses, from several camera views (abeam, ahead, above, chase). Save writes the values per class into the class data (spec first) so the game, boatgen previews and parity tests all read them; reset to defaults. Supersedes WM-062.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Spec says where the per-class kite shape values live and how the game and boatgen read them
- [ ] #2 Windowed tool with live sliders, class/kite/heading/gybe pickers and fixed camera views
- [ ] #3 Save and reload per class; game and boatgen previews show the saved shape; parity tests pass
<!-- AC:END -->
