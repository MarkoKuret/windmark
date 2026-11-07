---
id: WM-208
title: >-
  Decide: hails and protests offline (H and P do nothing, hails are silent, the
  AI never hails)
status: To Do
assignee: []
created_date: '2026-11-07 18:47'
updated_date: '2026-11-07 19:09'
labels:
  - decide-later
dependencies: []
priority: medium
ordinal: 224000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
H (room to tack) and P (protest) are in the Bindings list but dead in a quick race: the core accepts hail flags and does not use them (windmark.h ~271), protest needs the umpire mode 'protest' which the game never sets (race.h ~40). 'Starboard!' is text only: the voice.hail_* ids in sound_map.json have no sounds, though the Settings hint promises hails. Options: (a) hide H and P from the Bindings until online, and drop 'hails' from the hint; (b) give hails a short horn-like call and let the AI hail the player (right-of-way boat in Warning). Recommendation: (a) now, (b) as a feature later.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Owner decides; Bindings and the Settings hint match what works
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decided 2026-11-07 (recommendation taken): option (a). Hail and Protest leave the Bindings list and their prompts stay off until online play exists; the signals volume hint drops 'hails'. The AI hailing the player is a later feature. D-pad up, freed, opens the course map (WM-215).
<!-- SECTION:NOTES:END -->
