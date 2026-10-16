---
id: WM-160
title: >-
  AI: ai_long green with the ORC-fitted perf tables (match cover, Solent ebb
  overstand, mark-room)
status: In Progress
assignee: []
created_date: '2026-10-16 20:54'
updated_date: '2026-10-16 20:54'
labels:
  - ai
dependencies: []
priority: medium
ordinal: 171000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
With the new wm7/wm12 perf tables (WM-138, WM-127) two ai_races checks failed: the match-race leader covered in 3 of 5 seeds, and in the Solent ebb boats overstood the windward mark by 8 to 18 s per approach. Find the causes in the AI, fix them generally, keep the AI's cost.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ai_long passes twice in a row with the new tables
- [ ] #2 The rule-13 tack check no longer blocks a tack that does not close on the other boat (two boats a length apart on the same tack no longer lock each other out of a layline tack)
- [ ] #3 A boat entitled to mark-room does not steer away from its room giver onto the mark; the giver acts on the engine's room warning
- [ ] #4 Core tests, GDExtension rebuild, core sim and UI tests green
<!-- AC:END -->
