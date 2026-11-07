---
id: WM-218
title: 'HUD: true wind speed on the Glance page'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07 19:02'
updated_date: '2026-11-07 19:11'
labels: []
dependencies: []
priority: high
ordinal: 234000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The owner: the true wind speed is one of the most important parts. The 2026-11-07 redesign left Glance (the Deck default) with boat speed and the TWA dial only; TWS showed from Race up. Glance gets a TRUE WIND cell (KN, 52 px value on the boat speed's baseline) between the boat speed and the dial; the page grows from 486 to 654 x 150 design px, the cell's width set by the 11 px text floor at UI scale 130 % on 1280 x 800. Spec hud.md 16.1 and 16.3, the design note hud_wind_2026-11-07.md and hud_direction.md updated first; previews glance_tws*.jpg.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 hud.md 16.1 and 16.3 and the design note list the true wind speed on the Glance page with its size
- [x] #2 The Glance page shows TRUE WIND in KN beside boat speed at every phase, 52 px number, the page as narrow as it needs
- [x] #3 Glance clears the compact radar in portrait and the helm notes at 1280x800 at UI scale 80 to 130 percent; run_ui_tests.sh green
- [x] #4 Glance previews landscape and portrait rendered to docs/design/hud_wind_2026-11-07/glance_tws*.jpg
<!-- AC:END -->
