---
id: WM-111
title: 'AI: race well in current, turning tide and a trending wind'
status: In Progress
assignee:
  - '@ai-current'
created_date: '2026-10-06 08:27'
updated_date: '2026-10-06 13:58'
labels:
  - venues
  - ai
dependencies:
  - WM-107
  - WM-108
priority: medium
ordinal: 148000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The AI has never raced in current or a steady wind rotation. Check and fix laylines with current, tide turn mid-race, and a veering sea breeze.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Full AI fleet races finish at the Solent and Fremantle with no boats stuck or overstanding by large margins
- [x] #2 ai_long tests cover one current venue
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
WM-111 (branch ai-current): ai.md 1, 3.3, 4.3, 4.7 (new), 5.5, 5.6, 6.1, 6.4, 6.5 (new), 13, 15.1, 16 updated first.
- Causes: the AI used the ground wind (boats sail in the water wind); current corrections solved at the boat's own low speed turned slow boats into the wind (flood start: boats in irons behind the line, mean start delay 76 s); laylines took only the current at the boat; rounding and object checks ignored the set; boats pinned on marks by the stream never got off (one lay 1100 s on a gate buoy).
- Changes: water-relative wind; corrections at >= 0.8 x polar speed; laylines on the mean stream to the mark; two-route stream and trend choice (all but Easy, margins 2/1.2/0.6 %), trend from the briefing; start time and brake with current; rounding circle grows with the set; COG-based mark and object checks; pinned escape (contacts, 6 s sail away, let fly cycles); AI block v2.
- 80 seeds each, before -> after: Solent flood finish 92.0 -> 92.1 %, winner 1174 -> 1134 s; ebb 94.4 -> 97.6 %, DSQ/race 0.50 -> 0.21, races with a boat stopped > 60 s 15 -> 6 (longest 1101 -> 93 s); drawn tide winner 926 -> 918 s; Fremantle unchanged times, beats lean left +55 -> +68 m; Trieste, Garda unchanged (200 / 80 seeds). Table in ai.md 15.1.
- Observed-only trend estimation measured too noisy (se 0.7 deg/min at 6 min against 0.5 deg/min), so the trend comes from the briefing.
- AC1 open: in a strong flood a boat that touches the windward mark can still be pinned up to ~2 min (14 of 80 races); ebb OCS 13 % of starts (no current 4 %).
- ai_long: Solent flood/ebb/slack case added. race_bench: 'local' arg; Solent 10 boats racing mean 61 -> 69 us, 40 boats 397 -> 344 us; practice_waters bit-identical at 10 boats.
<!-- SECTION:NOTES:END -->
