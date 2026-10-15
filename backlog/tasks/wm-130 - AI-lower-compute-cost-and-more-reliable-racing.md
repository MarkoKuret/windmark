---
id: WM-130
title: 'AI: lower compute cost and more reliable racing'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-15 17:30'
updated_date: '2026-10-15 20:20'
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
- [x] #1 AI cost per tick measured before and after (mean and worst case), recorded in ai.md or PERFORMANCE.md
- [ ] #2 Reliability over many seeds measured before and after, no stuck boats in the measured set
- [x] #3 Core tests including ai_long green
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch ai-reliable (ai.md 6.4, 6.5, 7.3, 7.4, 7.6, 15.1 and PERFORMANCE.md updated).
Reliability: dev sweep AI_REL (fleet7, fleet12, mixed, match7, match12, big, bigmix; winds 8, 11, 15, 19 kn by seed) and a harness 'pinned' time (racing, in contact with an object, under 0.3 m/s). 400 seeds each, before -> after: match7 finished 777 -> 798/800, DNF 20 -> 0, races with a boat pinned > 30 s 51 -> 1; match12 764 -> 781/800, DNF 18 -> 4, pinned 28 -> 0; fleet7 3780 -> 3802/4000, pinned races 29 -> 14, touches 1.25 -> 1.00/race; fleet12 3309 -> 3327, pinned 28 -> 28, touches 1.68 -> 1.35; mixed 3659 -> 3649, pinned 19 -> 16, touches 1.31 -> 1.15; big (16 boats, 200 seeds) 2841 -> 2823/3200, pinned 13 -> 8. Contacts and penalties unchanged within noise. Solent tide (42 seeds each): flood 379 -> 392/420 finished, DSQ 40 -> 27; ebb and slack unchanged.
Cost: AI step timed alone, 16 boats, 10 races, Release M5: mean 24.0 -> 12.4 us/tick, p99 249 -> 140, worst 815 -> 838 us (Intermediate wm7); mixed levels and classes 23.4 -> 12.8, p99 250 -> 166, worst 769 -> 679. The cut (keep-clear: held candidate first, the others in lower-bound order) makes the same decisions bit for bit; determinism and memory-block tests pass.
Tried and dropped: start spots 1.5 L from the line ends (worse), hold-course exemption without the touch test (Solent overstanding), several escape variants (hard helm turns wedge the boat; let fly first loses boats that would slide off).
Open (AC 2 not met): fleet boats still pinned over 30 s in about 1 race in 20, nearly all near head to wind against a buoy (windward mark after a keep-clear luff in a crowd, the pin end just after the start, the offset mark) or against the finish mark boat, wedged before the escape starts; most fleet DSQs are late penalties (44.2-late). Rules engine, not AI, is now most of the core tick (polar_vmg per boat per tick about a fifth): owner decision.
<!-- SECTION:NOTES:END -->
