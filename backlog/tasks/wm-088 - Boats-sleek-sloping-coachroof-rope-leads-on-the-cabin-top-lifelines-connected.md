---
id: WM-088
title: >-
  Boats: sleek sloping coachroof, rope leads on the cabin top, lifelines
  connected
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-04 11:24'
updated_date: '2026-10-04 11:25'
labels:
  - boats
  - visuals
dependencies: []
priority: high
ordinal: 118000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner (2026-10-04), improve what we have, no new features. wm7 and wm12: (1) the cabin top is too boxy: make it a low Club Swan 50 style coachroof whose top slopes down forward and blends into the deck at (or just aft of) the mast partners, radiused edges, sides raked inward following the sheer, no vertical front; flush hatches on the sloping top; spec first (class file cabin parameters). (2) Halyards and control lines from the mast foot to the clutches and winches run oddly over the cabin roof: lead them along the deck and up the sloping top lying on it, through organisers to the clutches and winches, nothing floating or through the cabin. (3) Lifelines are disconnected from stanchions, pulpit and pushpit at some points; wm12 has a stanchion too many at the stern: every lifeline end on a stanchion top or rail, tested per segment end and per stanchion passed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Spec first: data_format.md and boatgen README give the coachroof parameters (height aft, slope, where it meets the deck, side rake, edge radius); both class files set them
- [ ] #2 Coachroof: low, top slopes forward and fairs into the deck at or just aft of the mast, radiused edges, raked sides following the sheer, no vertical front; flush hatches; previews show it
- [ ] #3 Halyards and control lines lie on the deck and sloping top (a few mm above) from the mast foot through organisers to clutches and winches; nothing floats or passes through the cabin (tested)
- [ ] #4 Lifelines: every segment end on a stanchion top or eye, the pulpit or the pushpit, and every stanchion passed carries each tier (test_attachments extended); wm12 stern stanchion layout as a real 12 m boat
- [ ] #5 Boats regenerated, LODs consistent; navy deck (and transom if affected) rebaked with --only; tests pass (boatgen, liverybake, boat import, livery, sail visuals, UI)
<!-- AC:END -->
