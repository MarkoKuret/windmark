# Platform, engine and technical direction

*Decisions of 2026-09-25. Behaviour details live in `docs/specs/` (networking in `docs/specs/networking.md`).*

## Priorities

1. **Reach:** PC/Steam first (Windows, Linux, Steam Deck), then web, mobile and consoles as business decisions.
2. **Lightweight performance:** runs well on low-end PCs and Steam Deck; small download.
3. **Visuals per unit of performance:** the scene is open water, sky and a few boats, so custom water, sky and sail
   shaders matter more than engine features.

## Platforms

| Platform | Role | When | Notes |
| --- | --- | --- | --- |
| **PC / Steam** (Win, Linux, Steam Deck) | The product | First | Payments, VAT, refunds, playtests, demo, community hub in one place. *Steam Deck Verified* is a realistic badge |
| Web | Business decision; maybe a free rules trainer or replay viewer | After EA | Browser networking is WebSocket/WebRTC, not raw UDP; Godot web builds with native extensions need matching thread builds ([Godot blog](https://godotengine.org/article/progress-report-web-export-in-4-3/)); rehosting risk, so no online play without an account |
| Mobile | Port or companion (spectate, results, rules quiz) | After Steam works | Touch helming is hard for precise mark roundings; low ARPU |
| Consoles | Port | After Steam works | Godot console ports go through porting partners |

## Engine

| | Godot (chosen for now) | Unity (fallback) | Unreal (ruled out) |
| --- | --- | --- | --- |
| Weight | Light editor and runtime, small builds | Medium | Heavy |
| Licence | MIT, no fees | Proprietary; paid seats above a revenue threshold | Royalty above threshold |
| PC / Linux / Deck | Yes | Yes | Yes |
| Web | Yes (single-threaded default) | Yes (WebGL/WebGPU) | No practical path |
| Mobile | Yes | Most mature | Poor on low end |
| Consoles | Via porting partners | First-party tooling | First-party tooling |
| Low-end performance | Good with custom shaders | Good | Poor |

- **Godot now.** Unity becomes the choice if consoles or the widest mobile reach become firm goals.
- **Keep the engine layer thin.** The simulation is a C++ core (`core/`), engine-agnostic; the Godot front end
  renders, interpolates and reads input. Switching engines means rewriting the front end only.
- **Reuse good free assets** (open-source ocean, sky, weather shaders and tools) where licences allow (MIT, BSD,
  Apache-2.0, CC0, CC-BY); record each in `docs/THIRD_PARTY.md`.

## Simulation timing

- **Deterministic fixed tick of 50 ms (20 Hz)** in the core, identical on server and client.
- The client renders at display rate and **interpolates** between ticks. Still standard practice, and it suits
  sailing, whose dynamics are slow compared with the tick.
- Weather (wind field, shifts, puffs, waves) is **deterministic from a shared seed**, so it is never streamed.

## Networking direction

Details: `docs/specs/networking.md`.

| Topic | Direction |
| --- | --- |
| Authority | Authoritative headless server built on the C++ core; the server gives the one verdict on rules, penalties and collisions |
| Own boat | Client-side prediction with reconciliation against server snapshots |
| Other boats | Interpolated 100–150 ms behind |
| Transport | UDP with a reliability layer for events (penalties, race state, chat) |
| Bandwidth | Delta snapshots; update rate banded by distance (near boats full rate, far boats reduced) |
| Weather | Shared seed, simulated locally on both sides |
| Budget | ~5–15 KB/s per player at 16 boats (estimate, measure) |
| Hosting | Cheap EU VPS first, then 2–3 regions (EU, US-East, Oceania) |
| Anti-cheat | Server validates input rates and plausibility; server replays for protests; Steam-bound ranked |

## Boat data

- The sim is **table-driven**: per boat class and sail set, tables of target speed, heel, trim and acceleration over
  true wind speed and angle; dynamics (response times, turning, collisions) from the boat's geometry.
- Tables are **produced by our own VPP tool** (`tools/vpp`) from hull and rig parameters in the boat-class file.
  Generated tables are never hand-edited; a change goes into the class file or the VPP.

## Assets

| Asset | Approach |
| --- | --- |
| **Yachts** | Generated parametrically (`tools/boatgen`) from the boat-class file: hull, deck, appendages, rig, sails. Detailed deck hardware as reusable parts placed by the generator. Generated UVs, tiling PBR materials, decals for liveries |
| Props | 3D generators (marks, committee boats, spectator craft) |
| Textures, 2D art | Image models plus owner curation |
| Venues | Mostly sea and sky; coastlines fictional or from open elevation / OpenStreetMap data with attribution |
| Water, sky, sails | Custom shaders, or permissive open-source ones adapted |
| Crew | Later (e.g. Mixamo animations) |
| Audio | Own recordings and synthesis |

## Performance targets (initial)

| Target | Goal |
| --- | --- |
| Steam Deck | 60 fps at native resolution, 16 boats |
| Low-end PC (integrated GPU) | 60 fps at 1080p with reduced settings |
| Server | Several 16-boat rooms per vCPU (measure headless) |
| Download | Small (hundreds of MB, not GB) |
