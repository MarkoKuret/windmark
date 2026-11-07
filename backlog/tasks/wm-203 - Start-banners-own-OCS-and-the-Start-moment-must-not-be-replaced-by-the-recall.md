---
id: WM-203
title: 'Start banners: own OCS and the Start moment must not be replaced by the recall'
status: To Do
assignee: []
created_date: '2026-11-07 18:47'
labels:
  - playability
dependencies: []
priority: high
ordinal: 219000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
At the gun the core emits start, then the OCS events, then X up on one tick; the HUD keeps one banner (race_hud_values.gd ~954), so 'Start' and the player's own 'OCS: return behind the line' both vanish under 'Individual recall: X flag'. A short banner queue or a priority (own OCS > Start > recall) fixes it. Also no sound of the player's own OCS (the ocs HUD event is not handled in game_audio.gd).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With a boat over at the gun the player sees Start and, when over, her own OCS line; the recall does not hide them
- [ ] #2 An own OCS has a sound
<!-- AC:END -->
