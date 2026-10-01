---
id: WM-066
title: 'Decide: hand-owned boat art models (generate once, edit in Blender)'
status: To Do
assignee: []
created_date: '2026-09-26 13:18'
updated_date: '2026-10-01 12:04'
labels:
  - decide-later
dependencies: []
priority: low
ordinal: 93000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner (2026-09-26): the generated models still have small faults that are hard to fix in code (mainsheet not reaching the boom, gaps between the lower and upper rigging at the deck, ropes twisting between the clutches and the mast, ropes going into the deck), and they want to edit the models by hand. Proposal: the generator makes the starting model; the owner edits it in Blender and saves data/boats/<id>/<id>.art.glb (committed, hand-owned, never overwritten); a validator checks it against the contract (nodes and pivots the game needs, sail attachment points, hull within tolerance of the physics hull, triangle budgets per LOD); the game loads the art model when present; sails stay generated. Lighter alternative: an overrides file for small part moves. Postponed by the owner.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Owner decided; workflow, validator and loading built if chosen
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-01 (WM-081): the livery textures are the first hand-owned boat art. tools/liverybake bakes the starting PNGs into data/liveries/<class>/<livery>/ (hull, keel, optional deck) and data/liveries/<class>/sails/ (one shared sail set per class); from then on they are edited by hand and committed, and the tool rewrites them only with --force or --only (data_format.md §8.6). The same ownership rule would carry over to hand-edited art models (<id>.art.glb) if the owner chooses them; the models themselves stay generated for now.
<!-- SECTION:NOTES:END -->
