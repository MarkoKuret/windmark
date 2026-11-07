---
id: WM-202
title: >-
  AI: a pinned boat with no way on needs an escape that works without the helm
  balance
status: To Do
assignee: []
created_date: '2026-11-07 18:08'
labels:
  - ai
  - bug
dependencies: []
ordinal: 216000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
With the weather helm off (the game's default since WM-195, boat.md §2 weather_helm_enabled) nothing turns a boat without way: the pinned escape (ai.md §6.5) counted on the sail plan's luff to pivot a boat off a mark. Repro: core/build/tests/windmark_ai_race_tests with AiRaceSpec.weather_helm = false (core/tests/ai_harness.h), AI_VENUE=solent AI_TIDE=flood AI_SEEDS=2,1: boat 5 pinned on the leeward mark (-1118.8, -1413.0) on her port side at 60 deg TWA, sails drawing or let fly, 0.0 to 0.14 m/s, cycling the three modes every 3 s for 118 s until the penalty deadline (DSQ); slack seed 2 boat 0 the same for 114 s. Contact friction (collisions.md, 0.5 against marks) eats the drive from rest while the leeward drift presses her on. The AI race tests run with weather_helm = true until this is fixed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With AiRaceSpec.weather_helm = false the Solent fleet test (test_ai_race.cpp) passes: stuck max under 60 s in flood, ebb and slack, seeds 1 and 2
- [ ] #2 ai.md §6.5 describes the escape for a boat with no way on and the helm balance off
<!-- AC:END -->
