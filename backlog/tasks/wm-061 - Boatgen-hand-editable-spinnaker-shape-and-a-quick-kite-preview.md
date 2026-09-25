---
id: WM-061
title: 'Boatgen: hand-editable spinnaker shape and a quick kite preview'
status: To Do
assignee: []
created_date: '2026-09-25 21:35'
labels:
  - boats
dependencies: []
priority: high
ordinal: 86000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner (2026-09-25): the new kites are still too big at the foot and the curves are a bit off; they want to shape them by hand. Keep the pipeline (the class file is the source; generated GLBs and perf tables follow): add class-file keys per spinnaker and code zero for mid girth and edge rounds (luff, leech, foot, and where the maximum round sits), next to the existing luff/leech/foot overrides; and a fast preview command that regenerates only the chosen boat and renders its flying sails from a few fixed angles (flat planform with dimensions, set on a run, set on a reach) in seconds, with the rule area printed. Document it as a short how-to in tools/boatgen/README.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Class-file keys for mid girth and edge rounds, documented
- [ ] #2 One command previews a kite edit in under 30 s
<!-- AC:END -->
