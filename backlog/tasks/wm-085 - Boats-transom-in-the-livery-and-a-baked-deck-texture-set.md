---
id: WM-085
title: 'Boats: transom in the livery and a baked deck texture set'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-03 17:02'
updated_date: '2026-10-03 17:35'
labels:
  - boats
  - visuals
dependencies: []
references:
  - docs/specs/data_format.md
priority: medium
ordinal: 112000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follows WM-081. The transom stayed in the deck gelcoat (white from behind); on real boats of the navy livery it carries the hull colour with the stripe ending on it and the boat name. And the deck had only an optional flat colour template: owner wants a hand-owned baked deck set (albedo, normal, roughness) with moulded non-slip areas, smooth margins and walkways, foot-traffic wear and dirt, scuffs round winches and clutches, sun fade and sealant lines round hardware.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Spec first: data_format.md §8 (transom and deck files, slots, uv1, ownership per part), boatgen and liverybake READMEs (hand-edit workflow)
- [x] #2 boatgen: transom on its own material slot with its own uv1, deck uv1 the plan view, the same on every LOD; boats regenerated
- [x] #3 liverybake bakes transom and deck sets (never overwriting existing files without --force or --only), committed for wm7 and wm12
- [x] #4 BoatLivery applies transom (navy, stripe, per-boat name) and deck sets on the baked path, topsides colour on the transom in the fallback
- [x] #5 Previews: stern quarters of both classes, cockpit and deck from above and from the helm, a fleet from behind; contact sheet updated
- [x] #6 Tests: liverybake, boatgen, boat import, livery (transom and deck applied, kept without --force), UI, sail visuals
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Spec: data_format.md §8.1, §8.2 (stripes with from 0 return onto the transom), §8.3, §8.5 (transom_* and deck_* sets, transom and deck uv1, livery_transom and deck_plan extras, the deck ORM blue = non-slip mask), §8.6 (ownership per part: a part is baked only when none of its files exists). boatgen: slot 'transom' on the deck node (own uv1, seen from astern), every other deck surface's uv1 the plan view, the same on LOD1 and LOD2; GLB extras livery_transom {rect, panel} and deck_plan. liverybake: hull.bake_transom, deck.py (non-slip panels and margins, pads, sealant, traffic, grime, scuffs, sun fade, tea stain), --transom-size 2048, --deck-size 4096, --deck flag removed; hulls rebaked (--only hull) for the stripes running to the transom (livery files from 0.0). Game: BakedLivery loads the transom and deck sets, BoatLivery baked_transom_material (name box in the panel, to starboard of the gudgeons on wm7) and baked_deck_material (one material for gelcoat and nonslip, the mask picks the tiling detail, steep faces plain), fallback transom in topsides colour. New PNGs 4.4 MB (deck 1.8 to 2.0 MB a class, transom 0.17 to 0.19 MB); the rebaked hulls replace 9.9 MB. VRAM: deck set 18 to 20 MB, transom 3.8 MB per class. Previews: game/tests/previews/livery_transom_*, livery_deck_*_above, livery_helm_*, livery_fleet_behind_*, livery_contact.png. Open: the owner's look in the engine; hailing port on the transom not done (needs a per-boat field).
<!-- SECTION:NOTES:END -->
