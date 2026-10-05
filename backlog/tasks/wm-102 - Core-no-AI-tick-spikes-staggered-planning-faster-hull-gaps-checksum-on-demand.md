---
id: WM-102
title: >-
  Core: no AI tick spikes (staggered planning, faster hull gaps, checksum on
  demand)
status: To Do
assignee: []
created_date: '2026-10-05 17:12'
labels:
  - performance
dependencies: []
priority: high
ordinal: 139000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
docs/PERFORMANCE.md C2, C2b, C3, C9 and measured item 3: AI planning spread over boats and ticks, hull gap geometry with squared distances, bounding-box culls, cached outlines and no per-call allocations, the world checksum only when asked. Racing max tick today 9.7 ms on M5 (16 boats), p99 4.2 ms.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Specs (ai.md, conventions/networking as needed) updated first; checksum files regenerated where behaviour changes
- [ ] #2 race bench: 16 AI boats racing max tick under 2 ms and p99 under 1 ms on the dev Mac; 24 boats measured
- [ ] #3 All core tests pass including ai_long; determinism holds
<!-- AC:END -->
