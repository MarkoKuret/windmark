---
id: WM-128
title: >-
  Core: rudder drag at helm 0 counted twice (wm7 25 kn TWA 40 settles 5.11 kn vs
  5.31)
status: Done
assignee:
  - '@claude'
created_date: '2026-10-15 17:14'
updated_date: '2026-10-15 17:53'
labels:
  - physics
  - core
dependencies: []
priority: medium
ordinal: 161000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From WM-125: the core charges rudder drag with the helm centred, though the polar already includes it. At the pinching cell wm7 jib 25 kn TWA 40 the spare accel (0.0054 m/s2) is below that drag (0.012), so core_tests' steady-state check fails. Making it 0 at helm 0 (boat.md §4 table) broke the AI match race; flooring accel broke the full race too. Fix with the AI fragility (WM-119).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 core_tests steady state passes at every cell; AI races (incl. ai_long) green
<!-- AC:END -->
