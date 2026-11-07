---
id: WM-175
title: >-
  Decide: offline key safety (sheet keys drop auto trim, Backspace restart
  confirm, capture keys only with the capture preset)
status: Done
assignee:
  - '@claude'
created_date: '2026-10-17 14:33'
updated_date: '2026-11-07 18:01'
labels:
  - decide-later
dependencies: []
priority: medium
ordinal: 199000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Today W/S and the triggers do nothing while AUTO shows (T is the only way out); Backspace restarts a race at once; the capture keys . and , are live in every offline session and a stray . freezes the game with no label by design (controls.md §7). Options: 'sheet turns auto trim off' default on; a confirm on Backspace; capture keys gated behind the capture preset.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Owner decides; controls.md and menus.md updated with the choice
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decided 2026-11-07 (owner delegated), all three: (1) 'Sheeting turns auto trim off' is on by default: a first press on W, S or a trigger trims the boat instead of doing nothing, and the HUD notes 'Auto trim off: T turns it back on' (the player's binding) for 3 s. (2) Backspace in an offline race asks first ('Restart the race? Press Backspace again', 3 s) and restarts on the second press; free sailing and rules scenarios re-place at once. (3) The capture keys . and , are live only while the capture preset is on, a shot script runs, or the scene starts with --capture-keys; / (world tags) always works. Reason: a laptop first-timer must never lose a race or freeze the game to one stray key, and the sheet keys must do something visible. Specs: controls.md §2, §5.3, §6, §7, §8; menus.md §3.
<!-- SECTION:NOTES:END -->
