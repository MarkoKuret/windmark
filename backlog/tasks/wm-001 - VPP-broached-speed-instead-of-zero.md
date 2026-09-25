---
id: WM-001
title: 'VPP: broached speed instead of zero'
status: To Do
assignee: []
created_date: '2026-09-25 13:31'
labels:
  - vpp
dependencies: []
priority: high
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Where no depowering keeps a sail config under the heel limit, the polar gives a low broached speed instead of 0, so the boat wallows rather than stops.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No zero speed in any config above the no-go zone
- [ ] #2 Broached speed documented in tools/vpp/README.md
- [ ] #3 Tests cover a gale spinnaker reach
<!-- AC:END -->
