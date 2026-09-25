---
id: WM-058
title: 'Physics feel: weather helm, helm response, downwind yaw'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-09-25 20:19'
updated_date: '2026-09-25 21:14'
labels:
  - vpp
dependencies: []
priority: high
ordinal: 80000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner after the first races (2026-09-25): the rudder moves too slowly when steering with the keys but snaps back when centring; centring then makes the boat twitch because the weather helm is too strong (a centred helm turns the boat); the boat is too twitchy downwind; overall the physics feel is off. Measured now: weather_helm up to +15 deg/s (wm7 jib 16 kn TWA 100), kites -9 to -17 deg/s close reaching, broach within seconds at 22 kn TWA 130; set-and-hold key rate 0.6/s against core helm_rate 1.6/s. Direction: a real boat is nearly balanced with a slight weather helm (a few degrees of rudder), carries its heading, and turns with some yaw inertia; downwind it is steady unless overpowered. Spec first (boat.md, controls.md), then VPP/core/front end.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Centred helm upwind drifts at most 2 deg/s, on a reach at most 3 deg/s, below 18 kn; broaching only when overpowered
- [x] #2 Yaw response has inertia: turn rate builds and decays over a time constant, no twitch on centring
- [x] #3 Key helm: progressive rate, fast when held, centring eased at the same rate
- [ ] #4 Owner sails it and the feel is better
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch feel (worktree ~/Code/wt/windmark-feel).

- Weather helm (VPP): the holding helm now uses the whole rudder angle (straight course; the free drift meets the same yaw damping as that helm's turn), and the radius law offset is -(1 - h_s) R_full so small helms turn at the linear rudder's rate. Centred-helm drift fell about 3x: wm7 jib 16 kn TWA 100 +15 -> +4.6 deg/s, kite close reaching -9..-17 -> -3..-6. Holding a course takes 1 to 3 deg of rudder.
- Broach: heel-limited broached cells from 45 deg TWA round up at v_b / R_full (kite reaching in 23+ kn, kite at 50-60 deg from 14 kn). A 20 -> 26 kn gust on a kite reach broaches with the helm centred; full helm catches it.
- Yaw inertia: yaw_rate state, yaw_time 0.36 s (wm7), 0.45 s (wm12). C API version 2, world snapshot version 2.
- Key helm: 0.4/s ramping to 1.5/s by 0.5 s held; centring eased along the same ramp.
- AC1 partly: upwind <= 1 deg/s everywhere, reaching <= 1.6 deg/s up to 10-12 kn, but 4 to 7 deg/s on a breezy reach (14-17 kn) near the heel limit (VPP picks full power at 25-28 deg heel; no crew-balance model). Owner decision needed.
- AC4 open: owner to sail it.
<!-- SECTION:NOTES:END -->
