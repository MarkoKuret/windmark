---
id: WM-084
title: 'Front end: anti-aliasing and distance haze'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-03 17:16'
updated_date: '2026-10-04 11:16'
labels:
  - front-end
  - look
dependencies: []
priority: high
ordinal: 114000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two cheap look gaps found 2026-10-03. (1) No anti-aliasing is set anywhere (project.godot has no MSAA, TAA or FXAA, so Godot's defaults leave it off): masts, stays, sheets, sail edges and the horizon stair-step and shimmer. Owner decision 2026-10-03: keep it simple, SMAA on every tier, no per-tier choice (fall back to FXAA only if SMAA does not fit tier L). (2) The fair preset's exponential fog (4e-5 /m) is about 4 % at 1 km and 33 % at 10 km, so the race area has almost no aerial perspective and reads flat. Try a depth haze that starts a few hundred metres out and reaches about 60 % at the horizon, horizon coloured, keeping the WM-080 sky and sea colours. Spec first (water_render.md §4.5 and §7).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Spec sets SMAA on every tier and the haze curve per weather preset, with constants
- [ ] #2 Rigging and sail edges stop shimmering in a moving headless preview on every tier
- [ ] #3 Before/after preview renders at the chase camera and at 1, 3 and 10 km show the added depth; the owner approves the look
- [ ] #4 Frame cost per tier measured; tier M stays within the Deck budget
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done on branch aahaze:
- Haze: Godot depth fog toward the horizon colour, share = max * smoothstep(begin, end, d)^curve. clear 300 m/16 km/0.45/0.42, fair 200 m/14 km/0.60/0.40, hazy 150 m/10 km/0.80/0.40. Fair: 4 % at 500 m, 9 % at 1 km, 25 % at 3 km, 55 % at 10 km, 60 % at the horizon (was 4 % at 1 km, 33 % at 10 km). Sky not fogged (fog_sky_affect 0); sky colours, exposure, glow unchanged.
- AA: SMAA 1x on every tier: project default rendering/anti_aliasing/quality/screen_space_aa=2 and Settings.screen_space_aa with the upscaler (off only under FSR2 / MetalFX temporal; SMAA runs before FSR 1.0). menus_test checks it.
- Previews: tests/previews/haze_before_*.jpg and haze_after_*.jpg (chase, 1, 3, 10 km; 3 km clear and hazy). Offline previews mirror Godot's depth fog and sun scatter.
Open (owner, windowed): AC2 rigging/sail-edge shimmer with SMAA on each tier; AC3 approve the look; AC4 frame cost per tier on the Deck (expected SMAA 0.35 to 0.8 ms at 1280x800).
<!-- SECTION:NOTES:END -->
