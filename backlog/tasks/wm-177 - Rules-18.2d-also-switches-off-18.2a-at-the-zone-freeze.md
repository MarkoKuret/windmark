---
id: WM-177
title: 'Rules: 18.2(d) also switches off 18.2(a) at the zone freeze'
status: To Do
assignee: []
created_date: '2026-10-17 14:33'
labels: []
dependencies: []
priority: medium
ordinal: 201000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The 'also' of WM-156: when the mark-room status is frozen at the zone, the same exemption test as the (c) branch applies to (d). Core rules.cpp with a test like the 18.2(b) one.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A core test shows 18.2(a) ends at the zone freeze when (d) applies
<!-- AC:END -->
