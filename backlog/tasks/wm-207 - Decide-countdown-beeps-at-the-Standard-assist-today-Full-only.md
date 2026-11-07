---
id: WM-207
title: 'Decide: countdown beeps at the Standard assist (today Full only)'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07 18:47'
updated_date: '2026-11-07 19:53'
labels:
  - decide-later
dependencies: []
priority: medium
ordinal: 223000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Beeps at 30/20/10/5..1 s play only with the Full assist (sail_test.gd ~1115); the default assist is Standard (settings.gd ~36), so a new player hears horns at the signals and silence in the last seconds. Recommendation: beeps at Standard too; Minimal stays silent.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Owner decides; the assist table in hud.md updated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decided 2026-11-07 (owner: 'fix all of those', the recommendation taken): countdown beeps at the Full and Standard assists; Minimal stays silent.

Done: GameAudio.beeps_at(assist) (Full and Standard), used by the sail scene; hud.md 14 assist table has the countdown beeps row, audio.md 5 updated. Test: audio_test (beeps_at per assist, 8 beeps at Standard).
<!-- SECTION:NOTES:END -->
