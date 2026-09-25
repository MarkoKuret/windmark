---
id: WM-033
title: 'Core: full AI race determinism test'
status: To Do
assignee: []
created_date: '2026-09-25 15:24'
labels:
  - core
dependencies:
  - WM-009
  - WM-008
  - WM-010
priority: high
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Phase 2 gate item (ROADMAP.md): a headless full race with the AI fleet, collisions and rules; same seed and inputs give identical checksums every tick, also across a second architecture (x86_64 under Rosetta).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Full AI race finishes headless
- [ ] #2 Two runs and a second-architecture run give identical per-tick checksums
<!-- AC:END -->
