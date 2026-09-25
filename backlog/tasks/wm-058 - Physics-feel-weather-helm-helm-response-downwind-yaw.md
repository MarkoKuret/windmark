---
id: WM-058
title: 'Physics feel: weather helm, helm response, downwind yaw'
status: To Do
assignee: []
created_date: '2026-09-25 20:19'
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
- [ ] #2 Yaw response has inertia: turn rate builds and decays over a time constant, no twitch on centring
- [ ] #3 Key helm: progressive rate, fast when held, centring eased at the same rate
- [ ] #4 Owner sails it and the feel is better
<!-- AC:END -->
