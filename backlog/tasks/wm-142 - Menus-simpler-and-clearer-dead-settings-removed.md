---
id: WM-142
title: 'Menus: simpler and clearer, dead settings removed'
status: Done
assignee:
  - '@menus2'
created_date: '2026-10-16 19:42'
updated_date: '2026-10-16 19:50'
labels: []
dependencies: []
ordinal: 168000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner: improve the menu UI: remove settings that do nothing, bigger buttons where they fit, no filler copy or ornament, a simpler and clearer look. Scope: game/scenes/menu/* and game/scripts/settings.gd (not the in-race HUD).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every setting traced to where the game reads it; settings nothing reads are removed from the screen and the saved file (stale keys ignored on load)
- [x] #2 Main menu, pause menu, results actions and race card Start are bigger, consistent buttons with generous padding
- [x] #3 Filler removed: redundant sub-lines, ornamental rules, needless hints and over-explaining help text
- [x] #4 One clear primary action per screen, fewer boxes and colours; wordmark, tagline, yellow accent and Barlow kept
- [x] #5 docs/specs/menus.md updated first for every behaviour change
- [x] #6 Headless menu tests pass; before and after previews rendered
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Removed: hud.captions (no caption lines in the audio), audio.voice_volume (no hail recordings; the voice bus now follows Signals). Every other setting traced to its reader. Quit and Quit to menu are plain items now; red only for Retire and resets. Headless menus and UI tests pass.
<!-- SECTION:NOTES:END -->
