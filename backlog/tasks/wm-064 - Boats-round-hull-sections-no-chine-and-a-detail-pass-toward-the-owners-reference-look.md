---
id: WM-064
title: >-
  Boats: round hull sections (no chine) and a detail pass toward the owner's
  reference look
status: In Progress
assignee:
  - '@claude'
created_date: '2026-09-26 12:19'
updated_date: '2026-09-29 22:02'
labels:
  - boats
dependencies: []
priority: high
ordinal: 90000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner (2026-09-26): update the boats to a hull without the chine (wm7 is section_shape chined; check wm12 for any hard knuckle), and the boat and sail detail is still well behind the look the owner has in mind (a classic sailing sim they know). Round sections for wm7, then the WM-060 detail pass (deck hardware, running rigging, fittings, edges, LODs).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 wm7 hull without chine; no visible hard knuckle on either boat
- [x] #2 Close-up previews visibly richer; triangle budget and LODs stated
- [ ] #3 Owner approves the look
- [x] #4 Every fitting touches what it is attached to: tiller on the rudder head, mainsheet blocks on the boom and deck, shrouds and stays at the chainplates and stemhead (tested: no gap over 5 mm)
- [x] #5 Surfaces read as real materials rather than CG (gelcoat, non-slip deck, metal, rope)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Round wm7 sections, faired bilge turn and forefoot; detail pass in boatgen (hardware, rig fittings, halyards, posed sheets, livery panels); LOD0/1/2 at 0/30/100 m: wm7 72k/26k/9.5k, wm12 92k/34k/11.6k triangles. Previews in tools/boatgen/previews (new: *_cockpit, *_mastbase, *_bow). data/perf not regenerated (coordinator).

Owner (2026-09-29): still looks too artificial, not real. Detail faults seen: the tiller sits wrong on the rudder head; the mainsheet block has an air gap to the boom; the rigging (shrouds, stays) ends a few inches above the deck instead of at the chainplates; and similar attachment gaps elsewhere.

WM-064 detail faults (2026-09-30): causes and fixes. Rigging screws were built along the wire's lean while the wire started straight above the pin (lower 39-59 mm, cap 12-28 mm, forestay 22-26 mm off), one screw served cap and lower, the stemhead box and backstay foot sat on a nominal height (backstay 5 cm up, and over the open cockpit on wm12), the backstay top missed the crane (62 mm), the bobstay ended short of the meshed stem: now each wire has its own screw in line on a chainplate strap through a cover plate, stemhead cheeks reach the deck, wm12 has a split backstay to quarter plates, backstay to the crane end, bobstay on an eye on the stem mesh. Mainsheet upper block hung at a fixed offset under the gooseneck height instead of the tapered boom's underside (24-38 mm) and the tackle ended 3-5 cm short of both sheaves: block now on a bail at Rig.boom_bottom, lower block on the traveller car (turned along its track), tackle between the sheaves. Tiller sat on top of oversized cheeks with the bolt missing it: rudder head rebuilt from Appendages.tiller_pivot, cheek gap = blade thickness, tiller butt on the bolt; gudgeons were above the open transom's top and arms off their plates: pintle heights below the cockpit floor at the transom. Also pulpit legs outside the sheer, pushpit legs over the open cockpit and off the bent rail, lower lifelines off the raked stanchions, masthead fittings off the tapered mast, pod arms, outhaul. Attachment test tools/boatgen/tests/test_attachments.py (attach.py, pieces tagged, Part.attach): before 27 (wm7) and 36 (wm12) attachments over 5 mm, after 0 of 175 and 304. Materials: gelcoat 0.72 linear (factor 0.78) roughness 0.22, non-slip procedural moulded diamond set (0.1 m tile) 0.47 matt, stainless 0.62 r0.22, rope 0.34 braid; spec data_format.md 3.7 look rules. Tests: boatgen 28 OK, run_boat_import_test.sh passed. data/perf unchanged (no hydro change).
<!-- SECTION:NOTES:END -->
