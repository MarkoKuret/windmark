---
id: WM-178
title: 'Scenario test: re-pin the quiz penalty times after the boat table regeneration'
status: Done
assignee: []
created_date: '2026-10-17 14:33'
updated_date: '2026-11-07 18:14'
labels: []
dependencies: []
priority: medium
ordinal: 202000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
run_scenario_test fails on main since the wm7 tables were regenerated: quiz mark_room penalty at 20.85 s (expected 20.90), quiz tack_in_zone 18.90 (expected 18.70), one and four ticks. Re-pin the expected times (and docs/marketing/quiz_scenarios.md if it quotes them) or widen the tolerance to a few ticks.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 run_scenario_test.sh green on main
<!-- AC:END -->
