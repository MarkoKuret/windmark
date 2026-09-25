---
id: WM-005
title: 'Core: project setup and math'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-25 13:31'
updated_date: '2026-09-25 13:53'
labels:
  - core
dependencies: []
priority: high
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
core/ CMake project: float rules, own math functions and counter-based RNG with the check values from docs/specs/conventions.md, table lookup, perf file loader, test framework.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Check values pass
- [x] #2 wm7 and wm12 perf files load and validate
- [x] #3 Builds with no FMA contraction
<!-- AC:END -->
