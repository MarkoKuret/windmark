---
id: WM-087
title: 'Rules: check the latest World Sailing racing rules before release'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-04 10:54'
updated_date: '2026-10-05 09:20'
labels:
  - rules
dependencies: []
priority: low
ordinal: 117000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner (2026-10-04): before the public release (demo or Early Access), check rules.md and the game against the current Racing Rules of Sailing (World Sailing edition in force then), including the penalty: the game uses a one-turn penalty (rule 44.2 by default is a two-turns penalty); the owner judged switching to the 720 overkill for now. List every difference and decide each: follow the rule, or keep a documented simplification (rules.md 7.8 to 7.10).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 rules.md compared with the edition in force; differences listed
- [ ] #2 Each difference decided by the owner (follow or documented simplification)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Comparison with RRS 2025-2028 (Changes and Corrections v2) in docs/design/rules_check.md: edition and changes (§1), every difference with kind, impact and a recommendation (§2), penalty deadline options for WM-056 (§3), and the list of owner decisions (§4). AC #2 waits for the owner.
<!-- SECTION:NOTES:END -->
