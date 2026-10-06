---
id: WM-103
title: 'Front end: main-thread work at lower rates and the sim on a second core'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-05 17:12'
updated_date: '2026-10-06 11:14'
labels:
  - performance
dependencies: []
priority: high
ordinal: 140000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
docs/PERFORMANCE.md C1, C4, C5, C6, C7, C8 and measured item 4: sails full rate only for near or on-screen boats, the rest 30 Hz or less; wakes and drawn-shadow state only for selected boats, uniforms copied on change; audio voices at 20-30 Hz; one packed pose array per frame; HUD redraws only changed blocks; the core stepped on a worker thread one tick ahead with double-buffered render state.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Main-thread game CPU at 16 boats measured headless before and after (PerfStats), target -1.5 ms on the dev Mac
- [x] #2 Sim on a worker thread: no frame hitch from a slow tick; determinism and replays unchanged
- [x] #3 All headless game tests pass
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Measured 2026-10-05 headless, 16 boats, seed 7, interleaved base/new runs. Clock-matched (a spinner keeps the P-cluster clock up; input section equal): main_ms L 1.18 -> 0.90, M 1.37 -> 1.12; process_ms L 2.15 -> 1.58, M 2.43 -> 1.72. As specified (144 fps cap): new looks slower because macOS lowers the clock when the main thread idles more (untouched input section 0.059 -> 0.072). Target -1.5 ms not reached: AC1 open.

Why the target was out of reach: the audit's 2.8-3.3 ms main-thread figure was mostly macOS clocking the CPU down while the game idled; at full clock the starting point was 1.2-1.4 ms, so -1.5 ms was not possible. Achieved: main_ms -0.25 ms (about -20 %), whole process step -25 to -30 %. Leftovers if a later measurement (WM-113) shows the main thread still matters: (1) other boats' wake ribbons stepped at 30 Hz on tier M, about 0.3 ms on the dev Mac; (2) HUD rebuilding only the blocks whose inputs changed, about 0.19 ms; (3) course view (marks, lines), about 0.13 ms. Together about 0.6 ms on the dev Mac, roughly 1.5 ms on a cheap laptop. Owner to decide: close with AC1 reworded, leftovers as a low-priority task.
<!-- SECTION:NOTES:END -->
