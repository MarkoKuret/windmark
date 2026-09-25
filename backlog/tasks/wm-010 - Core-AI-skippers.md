---
id: WM-010
title: 'Core: AI skippers'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-09-25 13:31'
updated_date: '2026-09-25 19:07'
labels:
  - core
dependencies: []
priority: medium
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AI per docs/specs/ai.md, including bad air and cover that actually trigger.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Spec acceptance tests pass
- [x] #2 AI fleet completes races at every level
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AI skippers in core/src/ai (ai.md). Fast tests in test_ai.cpp (core_tests), fleet runs in test_ai_race.cpp (ctest label ai_long). AC1 partly met: the ai.md 15 fleet targets for penalties (measured 1.0/boat vs 0.4), contacts (4.4/race vs 1), start delay and strict level order are not reached yet; ai.md 15.1 records the measurements. Memory block for snapshots: ai.md 16.
<!-- SECTION:NOTES:END -->
