---
id: WM-198
title: 'Codebase: focused cleanup of the front end scripts'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07 17:44'
updated_date: '2026-11-07 18:45'
labels: []
dependencies: []
priority: high
ordinal: 215000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Dead code, duplication and oversized scripts in game/scripts and game/scenes/menu; conservative, reviewable changes with tests green. No behaviour change.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All game and core tests green after the pass. Dead code and duplicated helpers removed; hud.gd and race_hud_values.gd split along their comment headers.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done 2026-11-07 on branch tidy2: 14 commits, one kind of change each. Stale mentions of the dropped settings, the wind page and Quit to menu fixed in the specs, README and a test comment; 21 unreferenced declarations removed (90 lines); 5 duplicated helpers merged into Frames and HudFormat; hud.gd split into HudLayout, HudText and HudItems (1973 to 1393 lines) and race_hud_values.gd into RaceHudMarks and RaceHudEvents (1339 to 881 lines), static helpers on the Hud and the values, public API unchanged. Suites: menus, core sim, scenario, boat import, sail visuals and venue terrain green; ui tests green but for one check that fails on untouched main at 26be3ef (race_hud_test, the two-boat core race: the finish card has expired by the race close since the weather helm went off by default in the helm merge).
<!-- SECTION:NOTES:END -->
