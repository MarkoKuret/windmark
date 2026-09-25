---
id: WM-048
title: 'Core: race and rules state snapshot'
status: To Do
assignee: []
created_date: '2026-09-25 17:17'
labels:
  - core
dependencies: []
priority: high
ordinal: 63000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From WM-009: race and rules state is not serialised; the tick checksum covers boats and collisions only. Networking resync (WM-015) and replays (WM-016.15, WM-034) need a full snapshot of race and rules state, included in the checksum.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 World save/load round-trips race and rules state bit for bit
- [ ] #2 Tick checksum covers race and rules state
<!-- AC:END -->
