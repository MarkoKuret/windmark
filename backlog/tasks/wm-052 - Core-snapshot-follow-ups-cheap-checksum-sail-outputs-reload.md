---
id: WM-052
title: 'Core: snapshot follow-ups (cheap checksum, sail outputs, reload)'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-25 17:36'
updated_date: '2026-09-29 18:03'
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
- [x] #1 Checksum hashes without building the snapshot buffer
- [x] #2 Sail outputs restored on load
- [x] #3 A World can be reset and loaded repeatedly
- [x] #4 Default ctest run under 15 s, long tests behind a label
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Checksum: World::checksum() hashes the snapshot body through a hashing SnapshotWriter (FNV-1a 64 fed byte by byte as it is written, no buffer). Definition unchanged: per-tick checksums of the scripted full race (15477 ticks) and a 10-boat AI race (21438 ticks) were bit-identical before and after (windmark_race_trace files compared with cmp), and a test checks checksum() == FNV-1a 64 of the tick index and the saved body.

Sail outputs: they are not only for the HUD. Boat::let_fly_drive() reads the driving sail's m_opt, and the world feeds it to the rules in step 1 of the next tick (the slow-down escape, rules.md §3.6) and the AI reads it in step 2, so after a load it was stale (the spawn's values). conventions.md §9.1 updated first: the carried tick outputs now include the per-sail outputs of sails.md §7 (k_h, m_opt, beta_opt, beta_t, trim_error, luff_shiver, motion, backed), snapshot version 3. This adds them to the checksummed body, so checksum values changed once (race outcomes identical: same ticks, contacts, penalties).

Reset and reload: World::reset() returns a world to its state as built with its entries; World::load() works on any world with the same setup and entries: the snapshot first goes into a scratch world, and only when that succeeds is this world reset and loaded, so a failed load leaves it exactly as it was (spec §9.1 says so now). wm_world_load no longer needs a new world. The controller stays installed across reset and load.

Test time: the checksum was not the main cost (about 8 % of the full race). Profiling showed polar_vmg (361 polar lookups and wm_cos per config, per boat, every tick the wind at the boat changes) at about half of the scripted race's time. It now uses a cached TWA/cos grid and Table::at_each (x bracket once, y bracket swept forward), bit for bit the same as before (unit test, and the per-tick checksum files identical). Long tests behind the label long: the doctest suite long (full race, full-race snapshot) runs as core_long, and capi_race_example_full; capi_race_example now runs a quick mode.

Timings on the dev Mac (loaded, same conditions before and after): full-race test 9.0 to 9.3 s -> 4.1 to 4.8 s; full-race snapshot test 32 to 37 s -> 16.2 to 16.9 s; windmark_race_trace full race 4.75 s -> 4.37 s (checksum change) -> 1.94 s (polar_vmg); 10-boat AI race 14.0 s -> 8.75 s. Default ctest (ctest -LE long): 64.8 s before (core_tests about 50 s plus capi 14.3 s) -> about 12 s (core_tests 8.6 s, capi quick 3 s, core_no_fma). Long label about 34 s; ai_long about 196 s (was about 4 min).
<!-- SECTION:NOTES:END -->
