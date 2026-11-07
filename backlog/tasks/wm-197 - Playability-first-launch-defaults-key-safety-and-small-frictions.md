---
id: WM-197
title: 'Playability: first-launch defaults, key safety and small frictions'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07 17:44'
updated_date: '2026-11-07 18:06'
labels: []
dependencies: []
priority: high
ordinal: 214000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Decide and apply the open playability items (WM-174 defaults, WM-175 key safety, WM-176 name tags) and fix other small frictions found in a playthrough of the menu to race to results flow.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 WM-174, WM-175 and WM-176 are decided, applied and closed. Frictions found in the flow are fixed or filed.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done 2026-11-07 on branch play2. Decisions: WM-174 Easy AI default and the P flag for quick races; WM-175 sheet keys drop auto trim (with a note), Backspace asks before a race restart, capture keys only with the capture preset; WM-176 name tags for boats to watch, N cycles all nearby and off. Frictions fixed: pause menu Restart and Quit to menu ask first while the race is on; the chat line is online only (Enter took the keys offline). Filed: WM-199 first-race key hints, WM-200 HUD review leftovers, WM-201 decide the quick race start limit.
<!-- SECTION:NOTES:END -->
