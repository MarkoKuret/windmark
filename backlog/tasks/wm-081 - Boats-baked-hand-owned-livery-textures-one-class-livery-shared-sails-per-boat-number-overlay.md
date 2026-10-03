---
id: WM-081
title: >-
  Boats: baked hand-owned livery textures (one class livery, shared sails,
  per-boat number overlay)
status: Done
assignee:
  - '@claude'
created_date: '2026-10-01 11:49'
updated_date: '2026-10-01 17:23'
labels:
  - boats
  - visuals
  - performance
dependencies: []
references:
  - docs/specs/data_format.md
  - docs/specs/sail_visuals.md
priority: high
ordinal: 111000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner feedback 2026-10-01 on WM-014: liveries static (baked texture files instead of per-pixel procedural graphics and cloth), hand-editable in a paint program, and much more realistic (gelcoat, antifouling, vinyl, real sailcloth). Scope change the same day: one really good livery per class instead of 14; one baked sail set per class shared by the fleet; only the sail number, nation and boat name differ per boat, as a small per-boat overlay. Follows WM-014; part of the hand-owned boat art question of WM-066 (textures only, the models stay generated).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Spec: data_format.md §8 (windmark.liveries/2: class livery, class sail set, boat identities; texture folders, resolutions, colour spaces, channels, ownership rule) and sail_visuals.md §11/§11.2; note in WM-066
- [x] #2 tools/liverybake bakes realistic hull, keel and sail textures from the livery file, never overwriting existing files without --force or --only
- [x] #3 Game loads the staged textures on a simple shader path (no procedural livery or cloth), per-boat name and number overlay; procedural path kept as fallback
- [x] #4 Textures baked and committed for wm7 and wm12, sizes on disk and in memory stated
- [x] #5 GPU cost proxy and load time per boat measured before and after
- [x] #6 Hand-edit workflow documented in tools/liverybake/README.md and game/README.md
- [x] #7 Previews and a contact sheet in game/tests/previews; boatgen, liverybake, import, livery, UI, sail visuals and menus tests pass
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Spec: data_format.md §8 (`windmark.liveries/2`; §8.5 textures, §8.6 ownership), sail_visuals.md §11 and §11.2, menus.md §1 (Sail number row; `GameSetup.livery` holds a boat id). Tool: tools/liverybake (README there). Textures: data/liveries/<class>/navy/ (hull 4096 x 2048 albedo, normal, ORM; keel; layout.json) and data/liveries/<class>/sails/ (per sail port and starboard albedo, normal, ORM, 2048 on the longer side; layout.json with the number slots). 22 MB of PNG in the repository; proposal: Git LFS for data/liveries/**/*.png before the textures grow (not set up). Game: BakedLivery, BoatLivery's baked path, shaders boat_baked, sail_baked, livery_baked.gdshaderinc; the procedural path is kept (`BakedLivery.enabled = false`). Video memory shared by the fleet: wm7 about 55 MB, wm12 about 63 MB (hull set 28 MB; a 2048 x 1024 hull would be 7 MB). Load (headless M1): the first boat of a class 20 to 30 ms (loads the set), then 1.4 to 1.8 ms per boat (procedural 2.0 to 2.5). Per pixel (tests/livery_cost.py, the M1's GPU through OpenGL): baked sails 0.42 to 0.71 of the procedural cloth, topsides 1.05 to 1.13 of the procedural livery. Previews: game/tests/previews/livery_*.jpg and livery_contact.png. Open: the windowed 60 fps check on the owner's MacBook Air M1 (tier M); the transom stays in the deck gelcoat colour (it is a deck surface).
<!-- SECTION:NOTES:END -->
