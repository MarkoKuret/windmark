---
id: WM-203
title: 'Start banners: own OCS and the Start moment must not be replaced by the recall'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07 18:47'
updated_date: '2026-11-07 19:53'
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
- [x] #1 With a boat over at the gun the player sees Start and, when over, her own OCS line; the recall does not hide them
- [x] #2 An own OCS has a sound
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Banner priority (hud.md 9.1): the viewed boat's own banners (OCS/OVER, Returned, Started, penalties, finish blocked, DSQ, start limit, abandoned) over the race's (signals, splits, finishing window) over the individual recall (X up/down); a lower banner does not replace a higher one still up, it goes to the feed (signals are fed anyway). At the gun: own OCS line if over, else Start; the recall in the feed. Own OCS plays race.ocs (new, tools/soundgen: three rising pips), audio.md 5. Tests: race_hud_test 'banner priority at the gun', audio_test OCS sound.
<!-- SECTION:NOTES:END -->
