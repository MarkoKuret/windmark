---
id: WM-052
title: 'Core: snapshot follow-ups (cheap checksum, sail outputs, reload)'
status: To Do
assignee: []
created_date: '2026-09-25 17:36'
labels:
  - core
dependencies: []
priority: medium
ordinal: 67000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From WM-048: the per-tick checksum serialises the whole snapshot every tick (9 to 13 KB for 6 boats, maybe 110 to 330 KB at 40 boats; full-race test 5.9 to 7.1 s): hash while writing instead of copying. Per-sail outputs (trim error, luff) are not restored on load, so the HUD may read stale values for one tick. World::load only works on a brand-new World and a failed load leaves it unusable; networking resync and replay scrubbing need a reset and repeated loads. The core test suite went from about 12 s to 42 s with the snapshot test: keep the default run short (e.g. a long-test label).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Checksum hashes without building the snapshot buffer
- [ ] #2 Sail outputs restored on load
- [ ] #3 A World can be reset and loaded repeatedly
- [ ] #4 Default ctest run under 15 s, long tests behind a label
<!-- AC:END -->
