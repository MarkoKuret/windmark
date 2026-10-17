---
id: WM-156
title: 'Rules: 18.2 entitlement ends only when the entitled boat leaves the zone'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-16 20:40'
updated_date: '2026-10-17 11:46'
labels:
  - rules
dependencies: []
priority: high
ordinal: 181000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in WM-073. Rules::mark_rules (core/src/rules/rules.cpp) drops 18.2 status whenever the entitled boat is not in the zone, so if the outside boat reaches the zone first the inside boat loses mark-room next tick. RRS 18.2(b): status ends when she leaves the zone. At a leeward mark with the inside boat to windward this penalises the wrong boat. Also RRS 18.2(d) switches off 18.2(a) and (c), rules.md and the engine only (c).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 rules.md and the engine end 18.2 status only on leaving the zone (or the 18.2(d) cases); a test with the outside boat entering first
<!-- AC:END -->
