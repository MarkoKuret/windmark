---
id: WM-118
title: 'Decide: ship the bowsprit overlap in the performance files'
status: To Do
assignee: []
created_date: '2026-10-06 13:27'
labels:
  - decide-later
dependencies: []
ordinal: 138000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
6d31fe8 added collision.sprit (rules.md 3.2) but left data/perf without it. Regenerating wm7 and wm12 now writes sprit 1.65 m, and the long ai_races test then fails: stuck_max 118.6 s against 60 (seeds 1 to 5, ten Intermediate boats). The stern-clearance branch (2026-10-06) ships the perf files without sprit. Decide: ship it and fix the stuck boat, or drop it.
<!-- SECTION:DESCRIPTION:END -->
