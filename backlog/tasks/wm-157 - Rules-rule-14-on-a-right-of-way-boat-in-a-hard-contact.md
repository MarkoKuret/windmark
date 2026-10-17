---
id: WM-157
title: 'Rules: rule 14 on a right-of-way boat in a hard contact'
status: To Do
assignee: []
created_date: '2026-10-16 20:40'
labels:
  - rules
dependencies: []
priority: medium
ordinal: 182000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in WM-073. The did-she-act check reads speed history that already includes the contact tick, and the collision cuts speed by over 10 %, so a right-of-way boat holding course into a hard collision never gets rule 14 (port_starboard: Kestrel, 3.9 m/s closing). rules.md §5.1 intends otherwise.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Speed history read before contact; port_starboard gives Kestrel rule 14 per rules.md §5.1 or the spec says why not
<!-- AC:END -->
