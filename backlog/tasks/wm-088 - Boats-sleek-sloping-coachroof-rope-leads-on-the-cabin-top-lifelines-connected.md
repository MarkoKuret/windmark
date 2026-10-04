---
id: WM-088
title: >-
  Boats: sleek sloping coachroof, rope leads on the cabin top, lifelines
  connected
status: Done
assignee:
  - '@claude'
created_date: '2026-10-04 11:24'
updated_date: '2026-10-04 16:51'
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
- [x] #1 Spec first: data_format.md and boatgen README give the coachroof parameters (height aft, slope, where it meets the deck, side rake, edge radius); both class files set them
- [x] #2 Coachroof: low, top slopes forward and fairs into the deck at or just aft of the mast, radiused edges, raked sides following the sheer, no vertical front; flush hatches; previews show it
- [x] #3 Halyards and control lines lie on the deck and sloping top (a few mm above) from the mast foot through organisers to clutches and winches; nothing floats or passes through the cabin (tested)
- [x] #4 Lifelines: every segment end on a stanchion top or eye, the pulpit or the pushpit, and every stanchion passed carries each tier (test_attachments extended); wm12 stern stanchion layout as a real 12 m boat
- [x] #5 Boats regenerated, LODs consistent; navy deck (and transom if affected) rebaked with --only; tests pass (boatgen, liverybake, boat import, livery, sail visuals, UI)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Spec: data_format.md 3.7 look rules (leads lie on the deck and coachroof, lifelines fitting to fitting, stanchions between pushpit and pulpit at most 2.2 m apart) and new 3.7.2 visual.deck.cabin (height, meet_aft_of_mast or length, slope_from, width, side_rake, edge_radius, windows); boatgen README. Class files: wm7 height 0.15, meets the deck 0.04 m aft of the mast, slope_from 0.2, width 0.50, rake 0.40, radius 0.035 (1.34 m long, steepest 12.4 deg); wm12 0.30, 0.06, 0.3, 0.56, 0.38, 0.06 (3.31 m, 11.5 deg). Coachroof: height field over the deck (fillet, raked side, edge radius, cambered top, all shrinking with the height; half-cosine slope tangent to the deck; plan follows the sheer, quarter-ellipse nose), meshed on the deck stations so the edge is shared; only the aft face upright, the deck steps in from the cockpit edge to it; draped flush companionway lid, conformed hatches, slim side windows (wm12). Leads: hardware.lead_path follows the surface between surface points (2 mm above), straight to fittings; halyards round the mast-foot block sheave, along the deck and up the slope to the organiser at sheave height, clutch jaws, tails flaked (wm12) or over the aft edge and down the aft face (wm7); clutches clear of the hatch. Lifelines: pushpit to 0.9 s, pulpit aft legs 1.3 s from the stem, stanchions only between (wm12: 4 a side at 1.96 m; before 6 with the aft one 5 cm from the pushpit leg and the forward one 5 cm from the pulpit leg, the aft one carrying no lifeline); end legs raked in the stanchion line. Tests: test_attachments LifelineTest (each segment end within 1 mm of its fitting, each stanchion on both tiers, spacing 1 to 2.2 m) and RopeLeadTest (never in the surface, spans along it within 5 mm of the deck mesh, through exit, block, organiser, clutch); the old layout fails both. LODs: wm7 76k/27k/9.6k, wm12 96k/36k/11.9k. Rebaked (liverybake --only deck): data/liveries/wm7/navy/deck_*.png and wm12/navy/deck_*.png; transom unchanged (outline unaffected). data/perf regenerated with the VPP and the boatgen sidecar: only class_sha256 changed. Tests: boatgen 41, liverybake 13, boat import (969 checks), livery, sail visuals (491 and sheets/LOD 195), UI all pass.
<!-- SECTION:NOTES:END -->
