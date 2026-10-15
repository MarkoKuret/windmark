---
id: WM-125
title: >-
  VPP: realistic heel for every class (righting moment, depowering), checked on
  wm12
status: Done
assignee:
  - '@heel'
created_date: '2026-10-11 11:44'
updated_date: '2026-10-15 17:53'
labels:
  - physics
  - vpp
dependencies: []
priority: high
ordinal: 158000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner (2026-10-11): wm12 heels too much (21-24 deg close hauled from 6 m/s, 30 deg on an 8 m/s kite reach at TWA 110; wm7 to be checked too). Not necessarily lower: whatever is realistic. The fix must be general in the VPP (righting moment from hull form, ballast and crew; flattening/twist depowering; kite heel), not a per-boat tweak. Compare against real heel figures for comparable boats (12 m racers, sportsboats) with sources.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Spec and tools/vpp/README.md describe the heel and depowering model with sources for the reference heel figures
- [x] #2 wm7 and wm12 heel tables (upwind and kite) fall within the sourced ranges, from a general VPP change (no per-class hot fix)
- [x] #3 Perf regenerated; VPP, core and AI tests green (ai_long stuck failure is pre-existing, WM-119)
<!-- AC:END -->
