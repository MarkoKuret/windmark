---
id: WM-130
title: 'AI: lower compute cost and more reliable racing'
status: To Do
assignee: []
created_date: '2026-10-15 17:30'
labels:
  - ai
dependencies: []
priority: medium
ordinal: 162000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner (2026-10-15): the AI should use less CPU and be more reliable. Measure AI cost per tick (mean and worst case, 16 boats) and reliability over many seeds (finished, DNF, stuck time, contacts, penalties) before and after. Cut planning cost without making the racing worse; fix stuck cases (pinned against an object, stuck short of a mark, see WM-119, WM-126, WM-054). Boat physics unchanged; ai.md first if behaviour changes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 AI cost per tick measured before and after (mean and worst case), recorded in ai.md or PERFORMANCE.md
- [ ] #2 Reliability over many seeds measured before and after, no stuck boats in the measured set
- [ ] #3 Core tests including ai_long green
<!-- AC:END -->
