# Windmark

Online tactical sailing races: fleet and match racing under the real racing rules, AI boats filling every race,
short races, realistic handling that stays accessible, and a light footprint (low-end PCs, Steam Deck).

Windmark is a working name.

## Layout

| Path | Role |
| --- | --- |
| `core/` | C++ simulation: boats, wind, rules, race, AI, collisions. Deterministic fixed tick, engine-agnostic |
| `server/` | Authoritative race server on top of the core |
| `game/` | Front end (Godot) |
| `tools/` | Boat generator, VPP, data tools |
| `docs/` | Design specs, plans, business and marketing |
