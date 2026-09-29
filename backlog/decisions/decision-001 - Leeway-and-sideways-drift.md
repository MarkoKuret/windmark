---
id: decision-001
title: Leeway and sideways drift
date: '2026-09-29 10:56'
status: proposed
---
## Context

The boat moves only along its heading (`boat.md` §6.4). Current already moves it, but wind never pushes it
sideways: a stalled boat (in irons, flogging, badly over-sheeted) just stops in the water instead of being carried
to leeward. The VPP already computes leeway (`configs[].vpp.leeway`, diagnostic only; wm7 in 10 kn: about 7.6°
close-hauled, 4° at 60°, 2.8° at 90°), but the core does not read it.

Proposed model:
- a sway velocity in the boat frame, relaxed toward a target over about 2 to 3 s (added mass);
- target when sailing: `v * tan(leeway)`, leeway from the table, scaled by heel and trim;
- target when stalled: the steady downwind drift of rig and hull windage against hull cross-flow drag (a new VPP
  table by TWS and AWA, roughly 0.3 to 0.8 kn for wm7);
- blend between the two by keel grip, e.g. `v^2 / (v^2 + v0^2)`;
- apparent wind, collisions, SOG/COG, rules and AI use the ground track.

## Decision

Postponed (owner, 2026-09-29). Options when it is taken up:
- (a) drift when stalled only: leeway fades to 0 above a few knots, so racing-speed handling, laylines and AI do
  not change;
- (b) full leeway: more realistic, upwind ground track about 4 to 7° lower, needs HUD layline and AI pointing
  updates.
Suggested: (a) first, built so that (b) is a data switch.

## Consequences

Spec change in `boat.md` §6.4 first, then the core step, a new VPP drift table and new tests; (b) also touches
the HUD laylines, the AI and race balance.
