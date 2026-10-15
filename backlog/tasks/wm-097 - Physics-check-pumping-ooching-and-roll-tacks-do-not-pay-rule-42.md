---
id: WM-097
title: 'Physics: check pumping, ooching and roll tacks do not pay (rule 42)'
status: To Do
assignee: []
created_date: '2026-10-05 09:35'
updated_date: '2026-10-15 17:30'
labels:
  - core
  - physics
dependencies: []
priority: low
ordinal: 129000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the rules check (2026-10-05): the rules ban propelling a boat by repeated rudder, sheet or body movement. The rules engine need not judge it, but the boat model must not reward it. Test headlessly whether rapid helm sculling, sheet pumping or repeated sail changes give a speed or VMG gain over steady sailing, in light and moderate wind, both classes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Headless test for helm sculling and sheet pumping against steady sailing, both classes, 4 to 20 kn
- [ ] #2 Any gain found removed in the boat model, spec first
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner (2026-10-15): not sure this is valid; in real sailing pumping can pay at times (rule 42.3 allows it in some conditions). Low priority; revisit the premise before any work.
<!-- SECTION:NOTES:END -->
