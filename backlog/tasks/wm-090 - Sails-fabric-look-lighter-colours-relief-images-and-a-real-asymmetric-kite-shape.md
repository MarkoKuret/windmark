---
id: WM-090
title: >-
  Sails: fabric look, lighter colours, relief images and a real asymmetric kite
  shape
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-04 22:30'
updated_date: '2026-10-04 22:30'
labels:
  - boats
  - visuals
dependencies: []
references:
  - docs/specs/sail_visuals.md
  - docs/specs/data_format.md
priority: high
ordinal: 119000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner feedback 2026-10-04 (improve what we have, no new features): all sails including the kite look too plastic, not like fabric; panels not accurate, some details over-exaggerated, colours too dark; the kite's general shape is off. Research real sails (class rules, sailmaker and full-scale measurements), record them in sail_visuals.md, then fix the baked cloth, the sail shaders, the kite planform and its set shape, and give the owner a hand-editable relief image per sail.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 References with numbers and sources recorded in sail_visuals.md 14 before any change
- [x] #2 Baked sail textures (main, jib, code zero, kite, both classes) rebaked lighter and matte with panels, patches, battens and creases at real scale; shader sheen instead of a plastic highlight; cost not above today's
- [x] #3 Hand-editable greyscale relief image per sail; liverybake makes the normal map from it; documented in the liverybake README
- [x] #4 Kite planform and set shape compared with the references from the four photo angles and fixed (spec first; native, reference and generator in parity; clearance rule kept); class areas and data/perf regenerated
- [x] #5 Before/after contact sheet; boatgen, liverybake, VPP, core, sail visuals, sheets, livery, import and UI tests pass
- [ ] #6 Owner looks at the sails and the kite and approves
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
References (sail_visuals.md 14): J/70, Melges 24, J/80 class rules, ClubSwan 50 ORC certificate, TP52 rule, Deparday et al. 2016 (J/80 full-scale flying shapes), North Sails and Quantum trim guides, sailcloth notes. Our kite was a teardrop (mid girth 0.76 SF, 3/4 width 0.42 SF against 0.94 and 0.59 to 0.69), flat low down, draft at mid chord, no twist running.

Kite: planform leech 0.82, foot 0.57 of the luff, mid girth 0.88 of the foot, edge rounds deepest at 0.55 (widths 1.00, 0.98, 0.88, 0.68, 0.53 of SF at 1/6..3/4); set shape camber 0.27 deepest at 0.3 of the height (0.8 on the foot, 0.45 at the head), chordwise sin(pi uc^q) with draft 0.42 low and 0.61 at the head, twist up to 26 deg growing with the AWA (60 to 130 deg, off again dead downwind) on the side away from the wind; clearance: the obstacle's last section segment runs on 2 clearances past its leech so a kite leech cannot wrap behind the main. Native, reference and boatgen sail_set.py in parity (0.3 mm). Kite areas wm7 43.0 -> 48.5, wm12 126.0 -> 142.5 m2 (13 %, area/SLU^2 0.39, small end of the references); data/perf regenerated with the VPP. Test 18: 0 crossings, smallest clearance 0.356 m wm7 / 0.504 m wm12 a2, largest ease 9.5 deg (over-sheeted kite, main eased); test 20 clew at worst 0.17 m (wm7) and 0.97 m (wm12) aft of the mast. Kite update cost 79 us, all sails 95 us per boat (native).

Cloth: sail textures rebaked with liverybake --only sails (git history: never edited by hand); white dacron, wm12 laminate #8b8e93 with #2c2d30 yarns, kites royal blue #2a62ad (livery files); roughness 0.82 / 0.55 / 0.68; plies 1.5 %, thread 12 % (30 % on laminate), panels +-1.5 %; patches 0.05 luff (0.03 kites); battens 4 with top 2 full (<10 m LOA), 5 with top 3 full (>= 10 m); creases softer and fewer. Shaders: cloth (Charlie) sheen replaces the Blinn-Phong highlight, same cost; GPU proxy baked sails 0.42 to 0.74 of the procedural (was 0.42 to 0.71). New <sail>_relief.png per sail (8-bit grey, 128 flat, +-4 mm), the normal map is made from it on every liverybake run or with --normals-from-relief; README documents painting it.

Previews: game/tests/previews/sails_look_before_after.png (17 before/after pairs: the kite from the cockpit, abeam, astern and the chase quarter on both boats, backlit, close-ups, race distance), livery_*.jpg and livery_contact.png republished; boatgen downwind previews regenerated.
<!-- SECTION:NOTES:END -->
