---
id: WM-121
title: 'Boats: sun shadows: proxy never drawn, no cockpit lid, inside the drawn boat'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-09 21:34'
updated_date: '2026-10-09 21:34'
labels:
  - boats
  - visuals
dependencies: []
ordinal: 155000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner report 2026-10-09: on tiers L and M the cockpit shows faceted shadow triangles that crawl as the boat moves, and turning Boat sun shadows off in the F9 panel draws the grey shadow proxy over the boat. The proxy must never be drawn in the colour pass in any state, and its shape must sit inside the drawn surfaces, open over the cockpit (sail_visuals.md 11.4).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Spec: sail_visuals.md 11.4 states the proxy shape rules and how casting is turned off
- [ ] #2 No proxy is drawn in the colour pass in any state (panel off/on, near/far casting, every tier); headless test
- [ ] #3 Panel off/on restores exactly the setup: visible meshes OFF, proxies shadows-only and shown, sails ON
- [ ] #4 Boatgen proxy: no face over the cockpit opening, every face at least the inset inside the drawn hull, deck, coachroof, mast and boom; boatgen test
- [ ] #5 Rudder proxy turns with the rudder; mast and boom proxies follow the real sections
- [ ] #6 Boat import, livery, UI and water suites pass; before/after previews of the cockpit shadow
<!-- AC:END -->
