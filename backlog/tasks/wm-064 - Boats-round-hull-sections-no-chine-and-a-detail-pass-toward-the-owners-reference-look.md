---
id: WM-064
title: >-
  Boats: round hull sections (no chine) and a detail pass toward the owner's
  reference look
status: In Progress
assignee:
  - '@claude'
created_date: '2026-09-26 12:19'
updated_date: '2026-09-29 17:27'
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
- [ ] #4 Every fitting touches what it is attached to: tiller on the rudder head, mainsheet blocks on the boom and deck, shrouds and stays at the chainplates and stemhead (tested: no gap over 5 mm)
- [ ] #5 Surfaces read as real materials rather than CG (gelcoat, non-slip deck, metal, rope)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Round wm7 sections, faired bilge turn and forefoot; detail pass in boatgen (hardware, rig fittings, halyards, posed sheets, livery panels); LOD0/1/2 at 0/30/100 m: wm7 72k/26k/9.5k, wm12 92k/34k/11.6k triangles. Previews in tools/boatgen/previews (new: *_cockpit, *_mastbase, *_bow). data/perf not regenerated (coordinator).

Owner (2026-09-29): still looks too artificial, not real. Detail faults seen: the tiller sits wrong on the rudder head; the mainsheet block has an air gap to the boom; the rigging (shrouds, stays) ends a few inches above the deck instead of at the chainplates; and similar attachment gaps elsewhere.
<!-- SECTION:NOTES:END -->
