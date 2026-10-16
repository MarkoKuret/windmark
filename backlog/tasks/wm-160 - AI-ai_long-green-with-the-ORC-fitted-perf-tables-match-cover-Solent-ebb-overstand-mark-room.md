---
id: WM-160
title: >-
  AI: ai_long green with the ORC-fitted perf tables (match cover, Solent ebb
  overstand, mark-room)
status: Done
assignee: []
created_date: '2026-10-16 20:54'
updated_date: '2026-10-16 21:05'
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
- [x] #1 ai_long passes twice in a row with the new tables
- [x] #2 The rule-13 tack check no longer blocks a tack that does not close on the other boat (two boats a length apart on the same tack no longer lock each other out of a layline tack)
- [x] #3 A boat entitled to mark-room does not steer away from its room giver onto the mark; the giver acts on the engine's room warning
- [x] #4 Core tests, GDExtension rebuild, core sim and UI tests green
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Causes and fixes: (1) rule-13 tack check counted the gap two boats already had, so two boats a length apart on the same tack locked each other out of tacking (Solent ebb layline overstand, refused tight-cover tacks); now only a tack that closes the gap by more than 0.1 L is barred. (2) A room-entitled inside boat kept clear of her giver under rule 11 onto the mark, and the giver never acted on the engine's room warning; fixed in the keep-clear layer. (3) The no-clear keep-clear fallback turned onto a mark and left the boat pinned; it now holds its heading when the turn would touch a course object. Also: VMG table switch coverage over both classes (wm12 has no angle jump with the new tables). 16-race sweeps over six fleet kinds: penalties -10 %, mark touches -51 %, finishers 826 vs 805, no boat stuck over 60 s.
<!-- SECTION:NOTES:END -->
