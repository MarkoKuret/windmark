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
| `game/data/courses/` | Course files (`windmark.course/1`: marks, lines, sequence, area), one folder per venue; `example_bay/example_wl` is the example |
| `tools/` | Boat generator, VPP, sound generator (`tools/soundgen`), livery texture baker (`tools/liverybake`), data tools |
| `data/classes/`, `data/perf/` | Boat-class files and the performance tables generated from them |
| `data/liveries/` | Livery files (`windmark.liveries/2`: class livery, class sail set, boat names and sail numbers) and, per class, the livery textures: hand-owned PNGs, baked once by `tools/liverybake` and then edited by hand |
| `data/venues/` | Venue physics files (`windmark.venue/1`: wind field, current, sea exposure, land, obstacles); `example_bay` is a small hand-made example |
| `docs/` | Design specs, plans, business and marketing |
