# Performance audit

Audit of 2026-10-04/05 (read-only). Goal: a broad audience on cheap laptops (Intel UHD 620 / Vega 8 integrated GPU,
i3 / Ryzen 3 / Celeron CPU, 8 GB RAM, 1080p) and later regular smartphones. Targets from `PLATFORM.md`: Steam Deck
60 fps native with 16 boats; low-end PC with integrated GPU 60 fps at 1080p with reduced settings.

GPU figures are estimates from the shader code, geometry and the M1 measurements in WM-078, WM-079 and WM-086 (a
headless run has no GPU). CPU figures were measured on the dev Mac (Apple M5, Release builds) and scaled: an
i3-1115G4 or Ryzen 3 5300U has about 1/2 to 1/3 of its single-thread speed, a Celeron N4500 about 1/6. The
per-feature ablation measurements are in "Measured cost per feature" (to be filled).

## Where we stand (16 boats, 1080p)

| Item | Today | Note |
| --- | --- | --- |
| GPU, tier L, Intel UHD 620 | about 25 to 35 ms (30 to 40 fps) | 60 fps not plausible at native 1080p; plausible but marginal at 67 to 75 % render scale |
| GPU, tier L, Vega 8 | about 2x faster | tier L at native 1080p plausible |
| Default tier | M for everyone (`scripts/settings.gd:56`) | a weak laptop starts on the heavier tier |
| Auto render scale | 100 % on a non-HiDPI 1080p screen (`settings.gd:94-98, 347-352`) | |
| Game CPU per frame | 3.6 ms on M5 (tier H), about 3 ms tier L | 7 to 11 ms on i3/Ryzen 3, about 20 ms on Celeron |
| Core tick, 16 AI boats | mean 0.59 ms, p99 4.1 ms, max 7.5 ms on M5; after WM-102 racing mean 0.12 ms, p99 0.42 ms, max 0.94 ms | 15 to 45 ms one-frame hitches on cheap CPUs at starts and roundings (before WM-102) |
| VRAM, one class, 16 boats | about 190 MB (L), 235 MB (M), 270 MB (H) | |
| Download | about 237 MB of imported content | most of it 4K liveries and duplicated boat textures |
| Threads | everything on the main thread | no Thread or WorkerThreadPool in `game/scripts` or `game/native/src` |
| Export | no build can be exported today | see A4 |

### GPU time on tier L, UHD 620, 1080p (estimate)

| Part | ms | Where |
| --- | --- | --- |
| Bandwidth floor: HDR buffer, depth prepass, tonemap with 3D LUT, SMAA 3 passes, HUD (no vignette since 2026-10-11) | 4 to 5 | `scenes/sea/look_fx.gd` |
| Water pixels (Godot Burley + GGX + sky reflection dominate; own code: 3 taps, puff loop up to 10, overlay loop up to 12) | 2 to 3 | `water_body.gdshaderinc:7`, `sea_common.gdshaderinc:167-276` |
| Sky: about 9 value-noise octaves per pixel every frame | about 1 | `sky_common.gdshaderinc:56-73` |
| Sails (baked path) | about 0.5 | |
| Shadows: 2 cascades, 2048 atlas, soft very-low filter | 0.5 to 1 | `sea_quality.gd:13-14` |
| SMAA | 1.5 to 3 | spec's 0.35 to 0.8 ms is for the Deck |
| Sea vertices (19k vertices x 22 waves) | negligible | |
| **Total** | **about 11 to 16 ms GPU**, about 25 to 35 ms scaled from M1 data | plus render-thread draw submission |

### Core tick breakdown (M5)

- Scales with the square of the fleet: 4 boats 0.063 ms, 8 boats 0.21 ms, 16 boats 0.59 ms.
- By phase: open legs 0.16 ms, pre-start 1.0 ms, first mark rounding 1.7 ms mean; 1,143 of about 19,900 ticks over 2 ms.
- By system: rules update 47 %, AI 38 % (mostly `rules_overlay` calling `tracks_gap`), per-tick checksum 12 %, boat
  physics 2 %. Hull gap geometry (`convex_gap`, `point_polygon_edge_dist`, `max_separation`) is about 60 % of the tick.

### Game main thread per frame (M5, 16 boats, tier H, about 3.6 ms)

| Section | ms |
| --- | --- |
| Wakes + drawn shadows | 1.14 (0.34 on tier L) |
| HUD redraw (outside PerfStats; `--no-hud` saves about 1 ms) | about 0.75 |
| Sails | 0.59 to 0.73 |
| Audio | 0.51 |
| Course | 0.26 |
| Sim | 0.15 mean |
| HUD logic | 0.14 |
| Boats | 0.11 |
| Camera | 0.07 |

## Improvements

Effort: S (hours), M (a day or two), L (several days). Grouped into the work packages proposed to the owner.

### Package 1: quick wins, no visible change

| # | What | Where | Gain | Effort |
| --- | --- | --- | --- | --- |
| G1 | Pick tier and render scale from the GPU at first launch: integrated GPU (`RenderingServer.get_video_adapter_name()` or the RenderingDevice device type) starts on tier L at 67 to 75 % render scale | `scripts/settings.gd:56, 94-98, 347-352` | 2 to 3x on the first experience | S |
| G4 | Sky clouds at half or quarter resolution (`AT_HALF_RES_PASS` / `AT_QUARTER_RES_PASS`), or bake the sky to a panorama per preset (clouds are static per preset) | `sky.gdshader:15-17`, `sky_common.gdshaderinc:56-73` | 0.7 to 1 ms GPU on UHD | S |
| C2 | Done (WM-102). Hull gap geometry: squared distances and a bounding-box cull in `vertex_edge_min` (prototyped: mean 0.595 to 0.450 ms, -24 %; max 7.5 to 5.45 ms; checksum bit-identical c574b95525e4ea39) | `core/src/course/geometry.cpp:93-140` | -24 % tick | S |
| C2b | Done (WM-102), plus samples taken nearest first with an oriented-box bound. Further: cull in the other boat's frame; precompute unit edge normals (`max_separation` takes a sqrt per edge per call); cache placed outlines per track sample instead of rebuilding them per candidate and neighbour; stop allocating a vector per call | `ai/ai_predict.cpp:67-83`, `ai_rules.cpp:440-475`, `rules/rules_geom.cpp:69-160` | another 30 to 50 % of the tick (untested) | M |
| C3 | Done (WM-102): `wm_world_step` takes no checksum, C API version 3. Checksum on demand or every N ticks instead of serialising the whole world every tick (game ignores it); check the networking spec first | `core/src/world/world.cpp:206-212, 328` | 12 % of the tick | S |
| A2 | Boatgen tiling textures VRAM-compressed (187 of 207 imported lossless, mode 0; `BoatMaterials._shared` keeps the first-loaded, lossless copy) | `game/generated/boats/*.jpg.import` | about 33 MB to 5 MB VRAM for wm7 | S |
| C5 | Wakes and drawn shadows: build `shadow_state()` only for selected boats (built for all 16 every frame though tier H draws none and L draws one: 0.15 ms on L); no Dictionary per boat per frame in `_wake_state`; copy the about 10 shader uniforms (textures included) onto the 2 materials only when the sea changes; avoid sorting arrays of arrays in `_select` | `sail_test.gd:752-753`, `boat_view.gd:739-759`, `sea_wakes.gd:303-308` | 0.3 to 0.8 ms CPU on M5 | S |
| C6 | Sails: full-rate update by screen size or for the nearest N boats, others at 30 Hz on tier L (today every boat within `NEAR_M` 200 m, about 1,250 vertices each, every frame); move `cam.get_frustum()` out of the per-sail loop (48 Array allocations per frame) | `boat_view.gd:17-20, 684-694` | 0.3 to 0.4 ms CPU on M5 | S |
| C7 | Audio: boat voice parameters at 20 to 30 Hz, reuse the scene's poses (today a Dictionary copy per voice, `render_pose(b, 1.0)` per boat and a lambda sort every frame) | `scripts/audio/game_audio.gd:546-620` | about 0.3 ms CPU on M5 | S |
| C8 | Sim bridge: one packed array of all poses per frame instead of a new object plus 9 dynamic `Object.set` calls per boat; integer cache keys instead of `"state:%d" % boat` | `core_sim_source.gd:320-321, 485-488` | 0.1 to 0.2 ms CPU on M5 | S |
| A9a | Cloth detail PNGs to VRAM-compressed (lossless today) | `liveries/_cloth` | about 4 MB VRAM | S |
| A6 | Bake load-time work to files: `BoatLivery.texture_mean/channel_mean` (GPU readback, CPU decompress and resize per texture at race start; boatgen can write the means to the sidecar); `SeaTextures` 256x256 noise built in GDScript loops; `LookFx.lut` 33^3 `grade()` calls per preset. `LiveryText` (16 images of 1024x512 on the CPU, about 11 MB VRAM) can stay | `scripts/livery/boat_livery.gd:782-825`, `scenes/sea/sea_textures.gd`, `scenes/sea/look_fx.gd` | shorter race load | S each |
| A8 | Shader warm-up on the loading screen: draw the boat, sail, wake, bow-wave, spray and mist materials for 1 or 2 frames off camera (Godot 4.6 ubershaders and pipeline cache are on, but each of the 14 custom shaders still compiles on first use) | loading screen | no first-use stutter | S |

### Package 2: texture diet

| # | What | Where | Gain | Effort |
| --- | --- | --- | --- | --- |
| A1 | Bake 2K hull/deck and 1K sail liveries by default, 4K only for tier H or an optional HD set (today hull 4096x2048, deck 4096x1336/1476, sails 2048 tall, BC7 albedo, BC5 normals, the same on every tier: about 89 MB wm12, 77 MB wm7) | `tools/liverybake`, `game/generated/liveries/<class>/navy/*`, `sails/*` | about 65 MB VRAM per class; about 120 MB off the download for both classes | M |
| A1b | Liveries albedo DXT1 (`high_quality=false`) instead of BC7; check that lettering stays sharp | livery `.import` | about 20 MB more per class | S |
| A3 | One shared boat texture set: every GLB (3 classes x LOD0/1/2) embeds the same about 22 images; 207 boat .jpg imported, 86 distinct, 24 used, 53.8 MB of imported .ctex. Boatgen writes `generated/boats/_tex/` referenced by URI, with a mode 2 import preset (also fixes A2) | `tools/boatgen` | about 48 MB off the download | S/M |
| A9b | Shadow atlas 2048 instead of 4096 on tier M | `sea_quality.gd` | 24 MB VRAM | S |

### Package 3: exportable build

| # | What | Where | Gain | Effort |
| --- | --- | --- | --- | --- |
| A4 | `BoatClassData.repo_path()` reads `data/classes`, `data/perf`, `data/venues` and `data/liveries/*.json` through `globalize_path("res://")/..`, outside res://, so an exported build cannot find them (16 call sites). Stage them into res:// (for example `game/generated/data/`) and use res:// paths | `game/scripts/sim/boat_class_data.gd:23` | any export works | M |
| A4b | Add `game/export_presets.cfg`. Exclude `test_sym*` (21 MB), `generated/sea/sea_render_samples.json` (2.1 MB, CORE_SAMPLES mode and tests only), `generated/*.log`, `perf_smoke.csv` (imported as csv_translation, leaves 28 junk .translation files), `data/perf/plots` | `game/` | smaller pck | S |

### Package 4: fewer draw calls and triangles

| # | What | Where | Gain | Effort |
| --- | --- | --- | --- | --- |
| G3 | Boatgen emits LOD1 and LOD2 as 1 to 3 surfaces with one atlas or vertex-colour material, plus an impostor LOD3 beyond about 400 m. Today 32 to 36 surfaces at LOD0 (13 to 14 materials), 29 to 33 at LOD1 (from 30 m), 23 to 27 at LOD2 (from 100 m); Forward+ draws each in the depth prepass, colour pass and each shadow cascade: about 1,100 to 1,400 draws for 16 boats, about 5 to 10 ms render-thread CPU on a 15 W laptop | `tools/boatgen`, `generated/boats/wm*.physics.json`, `boat_view.gd:166-187` | about 60 % fewer draws | M |
| A7 | LOD distances per tier (L: LOD1 from about 12 m). Triangles: wm12 LOD0 93.7k (hardware alone 37k), LOD1 35k, LOD2 11.6k; wm7 LOD0 72.8k; 16 boats inside 30 m at a start is about 1.5M triangles plus the shadow pass | `boat_view.gd:342-360` | fewer triangles on L | S |
| A7b | Turn off `meshes/generate_lods` and `create_shadow_meshes` on the `_lod1`/`_lod2` GLBs (a second automatic LOD system and extra index buffers: 3.1 / 1.1 / 0.35 MB scene files); consider `visibility_range` instead of the per-boat LOD script (all three levels are instanced per boat) | boat GLB `.import`, `boat_view.gd` | less memory, simpler | S |

Already fine: meshes and materials are shared across identical boats; sails are per-boat dynamic meshes; wake and bow
meshes are written in place with `mesh_surface_update_*_region` (ribbons 80x15 vertices, two per boat; bow sheets
196 vertices); audio is small (42 ogg, 1 MB); fonts 330 KB.

### Package 5: simulation on a second core

| # | What | Where | Gain | Effort |
| --- | --- | --- | --- | --- |
| C1 | Step the core on a worker thread one tick ahead; CoreSim keeps double-buffered render poses, sails and wakes so the frame never reads the world while it steps. Also spread the `_on_tick` work (HUD tick, audio tick, `_snapshot_sails`), which all lands on one frame in three | `scripts/sim/sim_runner.gd:29-53`, `native/src/core_sim.cpp:223`, `scenes/sail_test.gd:593-611` | removes the 7.5 ms (M5) / 15 to 45 ms (cheap) hitches, uses a second core | M/L |
| C6b | Later: SailShape and ribbon updates as WorkerThreadPool tasks, upload on the main thread | native | | M |
| C9 | Done (WM-102), neutral on the fleet measurements over 140 races. Stagger AI decisions by boat index (today all on even ticks, `(x.n % 2u) == 0u`): halves the AI peak. Changes behaviour: spec update and new checksum files | `core/src/ai/ai.cpp:365` | half the AI peak | S |

### Package 6: potato tier and lighter renderers (also the phone and web baseline)

| # | What | Where | Gain | Effort |
| --- | --- | --- | --- | --- |
| G2 | Potato tier below L: render scale 0.5 to 0.67 with FSR, FXAA instead of SMAA, sun shadows off (keep the drawn BoatShadows on the water), no LUT grade; water `unshaded` with a hand-written sun specular and the sky-ramp Fresnel (already uniforms in `sea_common.gdshaderinc:45-48`), so no IBL fetch; 1 detail layer, no glint tap, puff loop capped at 4; sky without clouds or a baked panorama | quality tiers, shaders | 50 to 65 % of tier L GPU time | M |
| G6 | Try the Mobile renderer for tier L and potato: no depth prepass (about half the geometry and draws), no clustered-light compute. Everything tier L uses works there. Caveat: the 10-bit buffer clips highlights at exposure 0.5 / white 6 (`env_day.tres:26-28`), so the sun disc, glints and sails need a retune; renderer is chosen per export or launch, not live | `project.godot` | 15 to 30 % | M |
| G7 | Tier L shadows: hard filter (`SHADOW_QUALITY_SOFT_VERY_LOW` still takes several PCF taps), boats beyond about 30 m do not cast | `sea_quality.gd` | 0.3 to 0.6 ms GPU | S |
| G8 | Done 2026-10-11: the vignette is gone on every tier (owner decision: no vignette at all) | | about 0.3 ms GPU on iGPU | |
| G5 | SMAA to FXAA on L and potato, or SMAA only at 100 % scale (one pass instead of three). Against the owner's "SMAA everywhere" decision of 2026-10-03: owner decides after a measurement | `project.godot`, quality tiers | 1 to 2 ms GPU on iGPU | S |
| G9 | Mobile textures: `rendering/textures/vram_compression/import_etc2_astc` is unset. Enabling it on today's BC set roughly doubles the imported size (pair with A1 and A3), or use Basis Universal (mode 4, UASTC with RDO), one transcodable texture for desktop and mobile. All dimensions are multiples of 4 (ETC2/ASTC-safe) | `project.godot` | phone builds | S to set, M to check |

Renderer compatibility:
- Forward+: works on all tiers, heaviest for integrated GPUs.
- Mobile: fits tier L and phones. SSR (tier H only) and the HDR range (G6) are missing; the sail shader's custom
  `light()`, `IN_SHADOW_PASS` and `VERTEX_ID` work; mist's `hint_depth_texture` (`mist.gdshader:16`) works.
- Compatibility (web): feasible, no compute used and 32F textures read with `texelFetch` only. No SMAA (FXAA or
  MSAA), no FSR (`settings.gd:368-380` already falls back to bilinear), glow levels ignored (L has no glow), mist's
  depth texture costs a copy, no SSAO (tier H only) or DOF (clip cameras only). Unchecked: depth-mode fog
  (`sky_rig.gd:200`) and the colour-correction LUT.

### Other CPU

| # | What | Where | Gain | Effort |
| --- | --- | --- | --- | --- |
| C4 | HUD redraws every canvas every frame; `hud_canvas.gd` rebuilds shapes as string-keyed Dictionaries and `_draw` matches on strings and redraws text. Redraw only blocks that changed, cache text sizes | `scripts/hud/hud.gd:1261-1264`, `hud_canvas.gd:30-37, 123` | 0.75 to 1 ms on M5, 2 to 6 ms on target | M |

## Estimated VRAM: one class (wm12), 16 boats, 1080p

| Item (MB) | L | M | H |
| --- | --- | --- | --- |
| Hull/deck/keel/transom liveries | 52 | 52 | 52 |
| Sail liveries | 34 | 34 | 34 |
| Ropes and cloth detail | 6 | 6 | 6 |
| Boatgen tiles (lossless copies) | 24 to 33 | 24 to 33 | 24 to 33 |
| Livery text (16 x 0.7) | 11 | 11 | 11 |
| Meshes (shared and dynamic) | 8 | 8 | 8 |
| Shadow atlas | 8 | 32 | 32 |
| Wake buffer | 0 | 2 | 2 |
| Render targets (rough; H adds SSR) | 40 | 60 | 90 |
| **Total today** | **about 190** | **about 235** | **about 270** |
| **After A1 to A3** (L: 1K hull, compressed tiles) | about 80 | about 140 | about 200 (4K kept) |

A race with both classes adds about 80 MB.

## Download size

- Imported content today about 237 MB, roughly the pck size (VRAM-compressed .ctex is stored raw; Steam's
  compression shrinks it somewhat). The 112 MB in `native/build`, `tests/previews` and `native/third_party` are
  excluded by `.gdignore`.
- After A1, A3 and A4: about 50 to 60 MB on desktop.
- ETC2/ASTC for mobile adds about 30 to 40 MB, or nothing with Basis Universal.

## Owner decisions

1. SMAA to FXAA on tier L (G5): decide after a measurement.
2. 4K liveries only on tier H (A1).
3. AI decisions staggered by boat (C9): done in WM-102; it changes individual races but not the fleet averages.
4. A real cheap laptop to measure on (ideally Windows, Intel UHD): `--quality=L --no-vsync --perf-log --fleet=16`
   at `--render-scale` 1.0, 0.75 and 0.67, with `--aa=fxaa` and `--shadow-splits=0` (matches WM-016.29).

## Expected outcome

Packages 1 to 5: tier L with 16 boats at 60 fps realistic on i3 / Ryzen 3 laptops; a Celeron still needs a smaller
fleet or the potato tier. Phones become realistic only after package 6.

## Static inventory (2026-10-05)

Counted from the GLBs and an in-memory boatgen rebuild per tagged part; estimates are marked.

### Boats: triangles per part (LOD0 / LOD1 / LOD2)

| Part | wm7 | wm12 |
| --- | --- | --- |
| Hardware | 22.1k / 6.9k / 0.1k | 35.9k / 12.8k / 0.8k |
| of which winches | 4.1k (2 x 2.0k) | 11.8k (8 winches) |
| mast-foot blocks | 2.4k | 3.2k |
| clutches and organisers | 2.7k | 3.5k |
| halyards and coils (4 mm rope) | 3.7k + 0.9k | 4.1k + 0.9k |
| horn cleats | 2.3k | 2.3k |
| stanchions, lifelines, pulpits | none | 3.9k |
| Deck (with coachroof) | 23.0k / 7.2k / 2.5k | 24.3k / 7.6k / 2.7k |
| Hull | 13.0k / 3.7k / 1.2k | 12.8k / 3.8k / 1.2k |
| Mast, rigging, boom | 9.2k / 3.3k / 1.2k | 12.9k / 5.0k / 1.7k |
| Keel, rudder, wheel | 5.0k / 1.8k / 0.7k | 5.6k / 1.7k / 0.7k |
| Sails (same mesh on every LOD) | 3.7k | 4.7k |
| **Total** | **76k / 27k / 9.6k** | **96k / 36k / 11.9k** |
| Surfaces (draw calls) | 32 / 29 / 23 | 36 / 33 / 26 |

- LOD1 from 30 m, LOD2 from 100 m (`tools/boatgen/boatgen/build.py:135`): the chase camera at 15 to 35 m mostly
  draws LOD0. 16 x wm12 is 454k triangles and 464 surfaces before shadows; tier M shadows have 4 cascades to 100 m,
  H to 150 m (`sea_quality.gd:18,25`), so boats in range are drawn again per cascade.
- Visibility at 1080p, about 60 deg FOV: 1 px is about 2 cm at 20 m, 3 cm at 30 m, 10 cm at 100 m. A 10 to 14 cm
  winch is 5 to 7 px at 20 m but 2,036 triangles (28-segment revolve, `hardware.py`); halyards are under half a pixel
  even at 20 m; rigging turnbuckles 256 triangles each. **The boats are too detailed; hardware is the clearest waste.**
- Proposed budget: LOD0 (closer than about 15 m) 20 to 25k triangles, 12 surfaces or fewer; LOD1 (15 to 80 m, the
  chase model) 6 to 8k; LOD2 (80 to 250 m) 1.5 to 2k with the sail grids halved; LOD3 (beyond 250 m) under 500.
- Cuts (B1 to B6):
  - B1 winches to about 250 triangles;
  - B2 blocks, cleats and clutches to 40 to 80 each;
  - B3 halyards, coils and screws dropped from LOD0;
  - B4 deck stations 23k to about 10k;
  - B5 static parts merged by material;
  - B6 a reduced sail mesh on LOD2, where sails are 40 % of the boat.
- Runtime meshes per boat:
  - sail grids in two layers (26x14, 22x12, 26x16); native bend 47.8 us per boat, the kite 38.8 us; each update
    rebuilds the surface with `clear_surfaces` and `add_surface_from_arrays` (`boat_view.gd:668-673`);
  - running sheets: 1,869 vertices, 40 us per native update, 15 Hz on LOD1, hidden on LOD2 (`boat_view.gd:641`,
    `boat_sheets.gd:370`);
  - livery text: 1024x512 RGBA8 per boat, 2 MB (`livery_text.gd:9`);
  - wakes: a 512x512 buffer viewport redrawn every frame on M and H (`sea_wakes.gd:23,203`).

### Boats after WM-100 (2026-10-06)

One detailed model per class; the engine's automatic LOD simplifies it by size on screen; one material per boat;
the static parts in one node; flat fittings painted; a shadow proxy casts instead of the boat (sail_visuals.md §11.4).

| | wm7 | wm12 |
| --- | --- | --- |
| Surfaces drawn without sails (before) | 4 (29 at LOD0) | 5 (32 at LOD0) |
| Surfaces with the sails shown (main and one other) | 6 | 7 |
| Model triangles without sails, full detail (before LOD0) | 51k (72k) | 60k (92k) |
| Drawn by the engine's levels at 25 / 50 / 100 / 250 m, other boats | 13.6k / 7.1k / 6.6k / 3.1k | 30k / 16k / 8k / 3.6k |
| The own boat (LOD bias 32) at 25 / 50 / 100 m | 51k / 51k / 27k | 60k / 60k / 60k |
| Shadow casters per cascade | proxy (about 600 triangles, 2 draws) and the sails | the same |
| Staged textures of one class (imported) | boat atlas 14 MB, sails 7.5 MB, shared tiling atlas 7.5 MB (before 52, 30, 27 MB) | |

Per boat at chase range with 2 cascades about 20 draws (prepass and colour of 5 to 7 surfaces, proxy and sails per
cascade) where it was about 130: an estimate from the surfaces, to confirm with a windowed `matrix.py` run.

### Venue (example_bay, now practice_waters)

| Item | Triangles | Note |
| --- | --- | --- |
| Island terrain, 5 m grid (`venue_view.gd:11`) | about 33k (max 47k, estimate) | 1 draw, casts shadows; land shader 3 value noises per pixel |
| Trees and shrubs (`venue_view.gd:129-157`) | about 25 to 45k (estimate) | 1 draw, vertex colour |
| Quay, rock, harbour light | under 2k | |
| Marks, committee boat, flags | about 1 to 2k | course lines drawn in the sea shader (8 lines, 4 circles per sea pixel) |
| Sea grid L / M / H (`sea_quality.gd:11-25`) | 38k / 92k / 197k | to 24 km |
| Sky | none | 5 noise octaves per sky pixel; radiance rebuilt only on a parameter change |

The land factor in the water shader is 4 `texelFetch` per vertex from a 13x13 RG32F texture, uploaded only when the
wind moves a whole 45 deg sector (`sea.gd:285-309`): negligible. **The venue is about 6 to 9 % of triangles and 3 to
5 draws: not the problem.** Optional: thin the trees (V1), halve the land grid away from shore (V2), trees and LOD2
boats not casting shadows on L (V3).

### Textures (VRAM estimate)

| Owner | Files | VRAM |
| --- | --- | --- |
| Baked livery hull and deck, 4096x2048 and 4096x1476, 3 maps | 10 per class | about 60 MB per class |
| Sail livery up to 1160x2048, 4 per sail | 12 to 16 per class | 30 MB (wm7), 38 MB (wm12) |
| Boat tiling textures 512x512 jpg, uncompressed | 207 files, 23 distinct | 32 MB resident |
| Rope livery | 14 | 5 MB |
| Sail cloth detail 3 x 512x512 | 3 | 4 MB |
| Livery text | runtime | 2 MB per boat |
| Sea detail, caps, wake | runtime | under 2 MB |
| Boot splash (uncompressed), icons | 3 | 5 MB, boot only |
| HUD, menus, fonts | procedural + 5 TTF | small |

The sail relief images live in `data/liveries` and are baked into the normal maps: no runtime cost.

### Commits since 432fad0 (2026-10-04 to 05)

| Change | Cost |
| --- | --- |
| WM-088 coachroof, leads, lifelines | +4k triangles on LOD0 (72k to 76k, 92k to 96k), +1k on LOD1 |
| WM-089 draped sheets | deck height field built once per class; routing inside the 40 us update |
| WM-090 fabric sails | Charlie sheen instead of Blinn-Phong, same cost (`sail_baked.gdshader:59-74`); relief baked offline |
| Menu live backdrop | **a full race scene with 4 AI boats while the menu is open** (`menu_stage.gd:9,41-84`): the menu costs as much as a race |
| Look panel | developer only, `_process` returns early when closed (`look_panel.gd:420`) |
| RRS 2025-2028, bowsprit overlap | a few flops per boat pair per tick (`rules.cpp:495`, `world.cpp:247`) |
| Race end | UI and finish camera at the finish only |
| Branding | icons and a 4 MB splash, boot only |
| Earlier: whitecaps, SMAA, haze, LUT, SSAO on H, DOF | sea per pixel +4 to 6 `exp` and 1 texture read |

Menu fix (M1): cap the backdrop at 30 fps or 2 boats on the low tiers.

### Shaders by per-pixel cost

- Very heavy: `water_l/m/h` (sea_common). Vertex: up to 22 wave components plus 8 fetches (exposure, land). Pixel:
  H re-loops 22 components for the faded slope; puffs (10); 2 to 4 detail taps plus glint; whitecaps (4 to 6 `exp`,
  1 tap); wake tap; 12 overlay distance tests. Covers 50 to 70 % of the screen.
- Heavy: `sail.gdshader` procedural cloth (loops of 3, 6, 3, hashes, custom `light()`); fallback only, baked
  liveries use `sail_baked`.
- Medium: `boat_baked` (up to 10 reads, deck non-slip blend, derivative normals); `sail_baked` (5 reads, custom
  `light()`); `boat_shadow` (polygon loops).
- Light to medium: `sky` (5 octaves, sky pixels only), `land` (3 noises), `wake` and `bow_wave` (wave loop in the
  vertex stage), `mist` (2 reads, alpha blended).
- Light: `boat.gdshader` (4 taps), `wake_normal`, the grade (in the tonemap pass; there is no vignette).

Cheaper sea on L (W1): no whitecaps or puffs, the course overlays on their own mesh instead of in every sea pixel,
1 detail tap.

### Ranked static costs

1. Boat triangles x fleet x shadow cascades (about 0.45M plus shadows for 16 boats; LOD0 at chase range). The cuts
   above, LOD1 from about 15 m, LOD2 from about 80 m, a LOD3 and reduced sails: boat triangles -60 to 70 %.
2. Draw calls: 30 to 37 surfaces per boat, own livery materials, plus shadow passes: about 1,000 or more for 16
   boats. Merge static parts per material.
3. Sea pixel shader on integrated GPUs (W1).
4. Shadows on L: 1 to 2 cascades over 40 m, no casting from LOD2 boats or trees.
5. Textures for phones: 2048 hull and deck, 1024-wide sails, compressed shared tiles (A1 to A3).
6. Menu backdrop (M1).
7. The venue (V1, V2): optional.

## Measured cost per feature (2026-10-05)

Windowed ablation runs on the dev Mac (Apple M5, 10-core GPU), 1920x1080 render pixels, `--race --fleet=16
--watch --seed=7`, start camera `--skip=185` (fleet bunched before the gun), open leg `--skip=330`, 26 s per run,
first 6 s dropped. One run per configuration, on battery; some runs were capped by Low Power Mode (90 fps) or the
120 Hz display, which lowers the GPU clock, so GPU differences under about 1 ms are noise. Draw and primitive
counts are exact; CPU section times are fair. GPU ms from Vulkan (MoltenVK) timestamps (Godot's Metal driver
reports 0). Editor binary, so GDScript ran as a debug build. Flags and the core benchmark are on branch
`perf-measure`; driver and data: `matrix.py`, `agg.py`, `perf/runs/*.csv`.

### Baseline, 16 boats (start / leg)

| Tier | GPU ms | Main-thread CPU ms | Renderer CPU ms | Draws | Primitives |
| --- | --- | --- | --- | --- | --- |
| L | 4.6 / 4.0 | 2.8 / 2.2 | 3.2 / 2.8 | 429 / 336 | 395k / 315k |
| M | about 5.0 / 4.0 | 3.3 / 2.8 | 3.5 | 548 / 414 | 497k / 479k |
| H | 9.5 / 6.7 | 4.1 / 1.9 | 5.9 / 5.0 | 701 / 465 | 875k / 636k |

Metal, tier M, full power: 3.8 ms per frame at the start (262 fps), 5.5 ms on the leg. Video memory 350 to 510 MB.
On this Mac the frame is main-thread CPU plus renderer CPU; the GPU is not the limit. **Draw calls are.**

### Removing X saves (tier M, start camera)

| Removal | GPU ms | CPU ms | Draws | Primitives |
| --- | --- | --- | --- | --- |
| Boats not drawn (sim, sails, wakes still run) | about 1 to 1.5 | | 386 | 353k |
| Fleet 16 to 4 | about 1.3 | about 0.8 main | 266 | 102k |
| Sun shadows off | 0.2 to 0.5 | renderer | 292 | 241k |
| Boats cast no sun shadow | 0.3 | renderer | 290 | 240k |
| HUD | about 0 | 0.1 to 0.2 | 93 to 142 | |
| All boats on LOD2 | about 0.2 | 0.1 (sails) | 107 | 224k |
| Boat hardware hidden | noise | | 53 | 92k |
| Sails | about 0.5 | 0.4 | 59 | 57k |
| Rigging and sheets | noise | 0.1 | 48 | 39k |
| Wakes, bow waves, spray | noise | 0.5 | 34 | 47k |
| Water as a flat plane | 0 | | about 1 | 81 to 92k |
| Venue (land, quays, rocks) | 0 | | 4 | 80k (leg) |
| Post, AA off or FXAA, sky | 0.3 or less each | | | |
| Audio | | 0.35 to 0.6 | | |
| Course visuals | | 0.17 to 0.27 | | |

### Core tick, 16 intermediate AI boats (us per 50 ms tick)

| Phase | Mean | p99 | Max |
| --- | --- | --- | --- |
| Free sailing | 170 | | |
| Sequence | 460 | | |
| Gun to +60 s | 710 | | |
| Racing | 810 | 4,200 | 9,700 |

Without AI the same 16 boats cost 350 to 375 us per tick: the AI is about half the mean and all of the spikes.
24 boats: 1.45 ms mean, 13 ms max. A spike lands in one frame, so it shows as a hitch.

After WM-102 (C2, C2b, C3, C9), `windmark_race_bench` seed 7, the build before and after run back to back on a
quiet M5 (the audit's numbers above were taken on a busier machine), µs per tick, mean / p99 / max:

| Phase | 16 boats before | 16 boats after | 24 boats before | 24 boats after |
| --- | --- | --- | --- | --- |
| Free sailing | 88 / 94 / 1,225 | 57 / 71 / 244 | 129 / 144 / 1,247 | 72 / 76 / 146 |
| Sequence | 244 / 1,509 / 2,400 | 123 / 405 / 613 | 690 / 3,505 / 6,188 | 214 / 598 / 944 |
| Gun to +60 s | 376 / 1,451 / 1,677 | 105 / 252 / 286 | 701 / 3,178 / 4,116 | 208 / 597 / 669 |
| Racing | 426 / 2,227 / 3,964 | 124 / 416 / 938 | 766 / 4,357 / 7,208 | 186 / 463 / 964 |
| First finish to close | 145 / 1,213 / 1,461 | 63 / 100 / 238 | 485 / 1,942 / 2,452 | 127 / 290 / 460 |

Without AI, racing: 16 boats 201 to 77 µs mean, 24 boats 307 to 121. Seeds 3, 11 and 21 at 16 boats: racing max
631 to 851 µs.

### AI skippers alone, 16 boats (WM-130, 2026-10-15)

The skippers' step timed on its own every tick from the warning signal to the close (`AI_REL=big|bigmix
AI_SEEDS=1,10`, `windmark_ai_race_tests`, Release, M5, one process at a time; `big` is 16 Intermediate wm7 boats on
the default course, `bigmix` 16 boats of every level and both classes; the wind cycles 8, 11, 15, 19 kn over the
seeds), µs per tick over the ten races:

| Build | Fleet | Mean | p50 | p99 | p99.9 | Max |
| --- | --- | --- | --- | --- | --- | --- |
| main before WM-126 | big | 24.0 | 4.8 | 249 | 408 | 815 |
| | bigmix | 23.4 | 4.7 | 250 | 443 | 769 |
| WM-126 fixes alone | big | 25.9 | 5.0 | 261 | 446 | 1,087 |
| | bigmix | 23.8 | 4.8 | 259 | 452 | 971 |
| WM-126 + WM-130 | big | 12.4 | 4.9 | 140 | 293 | 838 |
| | bigmix | 12.8 | 4.8 | 166 | 343 | 679 |
| main with the heel model and WM-119's fixes | big | 18.8 | 4.8 | 206 | 332 | 574 |
| | bigmix | 22.9 | 4.9 | 234 | 368 | 680 |
| the same merged with WM-126 + WM-130 | big | 10.1 | 4.8 | 110 | 246 | 539 |
| | bigmix | 11.1 | 5.0 | 126 | 261 | 520 |

The rows "WM-126 fixes alone" and "WM-126 + WM-130" race the same races bit for bit (the cost cut does not change a
decision): the mean halves and the 99th percentile drops by about 40 %; against main with the new heel model the
merged branch halves the mean and the 99th percentile too (the last two rows race different races). The cost was the keep-clear candidate
evaluation (ai.md §7.2: about 70 % of the AI time, nearly all of it hull-to-hull gaps along the predicted tracks):
the candidate held from the last decision is now checked first and stands when it is still clear, and the others are
taken in the order of a lower bound of their cost, so the track checks of candidates that cannot win are skipped. The
mean is about 0.8 µs per boat per tick; the worst ticks (several boats keeping clear at once) stay under 1 ms.

The whole core tick is now dominated by the rules engine, not the AI: in a `sample` profile of the 16-boat race
(`Rules::update` about three quarters of the tick, the AI about 13 %, the boats 8 %), a fifth of the tick is
`polar_vmg`, which the rules
engine calls for every boat on every tick whose true wind speed changed (it always does) to find the close-hauled
angle by scanning the polar. Caching it on a speed grid would remove most of that, but changes the rules' angles
slightly (a `rules.md` decision).

### Menu backdrop (4 boats)

3.2 ms per frame (about 310 fps): GPU 2.6 ms, main 1.0 ms, about 300 draws, 280 to 340k primitives, about two
thirds of a race scene.

### Verdicts

- **Boats:** draw calls, not triangles. LOD0 is 34 surfaces per boat; forcing LOD2 halves the primitives but barely
  moves the GPU. The cost is per-surface draws, repeated in up to 4 shadow cascades. Hardware detail costs
  triangles and memory but little measured time on this Mac (it matters more on a non-tile laptop GPU).
- **Shadows:** about 53 % of all draws, the biggest structural item.
- **Venue, water, sky, post:** each cheap. Removing them does not make the game fly.
- **Sails:** 0.5 to 0.9 ms CPU and 59 draws; the shaping is native, the overhead is per-sail GDScript.
- **Physics, AI, rules:** small on average (0.1 to 0.2 ms per frame); the AI spikes are the risk.
- **HUD:** 0.1 to 0.2 ms CPU but 90 to 140 draws. **Audio:** 0.35 to 0.6 ms GDScript, high for what it does.

### Scaling to cheap laptops

M5 is about 2.3x an M1 in compute and 2.25x in bandwidth, so an Intel UHD 620 has about 1/14 of its compute and
1/5.6 of its bandwidth. Tier M at 1080p (3 to 5 ms here) is roughly 30 to 60 ms there; tier L at 0.67 render
scale about 15 to 25 ms. Shadow and post passes cost relatively more on a non-tile GPU. The menu backdrop would
take 15 to 35 ms. An i3 laptop CPU: frame CPU of 6 to 7 ms here becomes 15 to 17 ms (borderline for 60 fps), and
AI tick spikes become 10 to 25 ms hitches.

### What would make it fly (measured ranking)

1. **Shadow casting:** a cheap proxy caster per boat (LOD2 or hull and sails), hardware out of the shadow pass,
   fewer cascades or a shorter distance on L and M: about 290 draws and 240k primitives.
2. **Boat draw calls:** merge surfaces per boat by material (G3, B5), LOD1 from about 15 m, no hardware at distance.
3. **AI spikes:** spread AI planning across ticks (C9) plus the hull gap geometry (C2): no 4 to 10 ms ticks (done,
   WM-102: under 1 ms at 16 and 24 boats on M5).
4. **Main-thread GDScript:** sails, wakes and audio (about 1.5 to 2 ms) native or at a lower rate for boats nobody
   is watching (C5, C6, C7); the simulation on a second core (C1).
5. **Low-end defaults:** tier L and 0.67 render scale on integrated GPUs (G1); a lighter menu backdrop on L (M1).

Re-run for clean numbers on AC power, avoiding the display refresh cap, with 3 repetitions (`matrix.py PLAN 3`),
and on a real Windows laptop with Intel UHD graphics.

## Before and after on another machine

Tags: `perf-before` (the last commit before WM-100 to WM-103, with the measurement flags) and `perf-after`. Each
side gets its own folder, its own native build and its own generated boats:

```
git clone https://github.com/MarkoKuret/windmark.git wm-after
cd wm-after && git checkout perf-after && game/native/build.sh && game/tests/run_boat_import_test.sh && cd ..
git -C wm-after worktree add ../wm-before perf-before
cd wm-before && game/native/build.sh && game/tests/run_boat_import_test.sh && cd ..
```

Needs Godot 4.6, CMake, Ninja and Python 3 with numpy, scipy, pillow and moderngl. Run each side the same way, on AC
power, Low Power Mode off, one at a time, nothing else running:

```
godot --path game --resolution 1920x1080 res://scenes/sail_test.tscn -- --race --fleet=16 --watch --seed=7 \
  --skip=185 --quality=M --no-vsync --perf-log=start_M.csv --perf-seconds=60
```

Repeat with `--skip=330` (open leg) and `--quality=L`, three times each, and compare the median `fps`, `main_ms`
and draw calls in the CSVs.
