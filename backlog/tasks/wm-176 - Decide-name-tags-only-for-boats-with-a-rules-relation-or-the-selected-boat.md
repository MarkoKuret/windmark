---
id: WM-176
title: 'Decide: name tags only for boats with a rules relation or the selected boat'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-17 14:33'
updated_date: '2026-11-07 18:03'
labels:
  - decide-later
dependencies: []
priority: low
ordinal: 200000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
hud.md §16.4 gives every boat within 50 m a name tag: at a crowded start that is one chip per mast. Proposal from the HUD review: tags for boats with a relation or the selected one; the rest only with boat_names. Also open from the same review: the rounding split banner repeats the feed line; the I-flag line under the start numbers is useful once per race; the penalty banner could go since the panel appears at the same moment.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Owner decides; hud.md §16.4 and §12 updated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decided 2026-11-07 (owner delegated): name tags on the water go to boats the player must watch: within 50 m with a rules relation (a radar colour other than white) or selected (any distance). N cycles watch (default) -> every boat nearby (all within 50 m) -> off, each with a 3 s note in the helm notes. The radar and course map keep their rule (viewed, selected, relations). Reason: at a crowded start one chip per mast hides the water; the tags that matter are the boats with a rules relation. The three other items of the HUD review (rounding split banner, I-flag line once per race, penalty banner) are not changed here: they are HUD content the HUD pass owns; filed as a playability task. Spec: hud.md §16.4, controls.md §2.
<!-- SECTION:NOTES:END -->
