---
id: WM-120
title: >-
  Boats: wm12 racing helm, one big wheel through a floor well, no pedestal
  extras
status: Done
assignee:
  - '@claude'
created_date: '2026-10-07 13:35'
updated_date: '2026-10-09 11:32'
labels: []
dependencies: []
ordinal: 140000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner, 2026-10-07: the wm12 wheel looks cruiser-like. Wanted: a plain racing setup like a First 35 or a Farr 40: one big wheel whose lower part runs through a slot (wheel well) in the cockpit floor, on a short low pedestal or a bearing in the floor, with no pedestal guard, no instrument pod and no arms around it. Today (tools/boatgen/hardware.py, helm block): wheel diameter min(1.71 x cockpit half-width, 1.35 m x scale), hub at floor + radius + 0.12 m so the whole wheel stands above the floor, carbon pedestal, binnacle, guard hoop and a display pod on two arms. Change the generator (spec first: data_format.md 3.7 visual.deck.steering and boatgen README), regenerate wm12, rebake if the deck set changes, previews for the owner. Twin wheels stay an option for later classes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 wm12 helm: one wheel of racing size (about 1.6 to 1.8 m) with its lower part in a floor well, no guard, pod or arms; previews approved by the owner
- [x] #2 spec and boatgen README describe the helm; boatgen attachment tests pass (wheel on its shaft, shaft on its bearing, well in the floor)
<!-- AC:END -->
