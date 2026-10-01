# Windmark front end (Godot)

Godot 4.6, Forward+ renderer. So far: the boat import test, the sea, sky and lighting (`docs/specs/water_render.md`),
the core binding (a GDExtension over the core's C API) and a placeholder simulation behind the same interface, the
controls, the cameras, the minimal HUD, the audio and a sail test scene that puts them together on the core.

## Layout

| Path | Role |
| --- | --- |
| `project.godot` | Project settings |
| `scripts/` | GDScript. `sail_grid.gd` (`SailGrid`) maps imported sail vertices back to the boatgen sail grid; `frames.gd` (`Frames`) holds the axes and angle helpers; `boat_view.gd` (`BoatView`) places the generated boat, its rudder, wheel, boom and mainsheet, and bends the sails; `sail_shape_ref.gd` (`SailShapeRef`) is the GDScript reference of the native sail shapes; `boat_materials.gd` (`BoatMaterials`) puts the boat materials on the imported meshes |
| `scripts/sim/` | `SimSource` (the simulation interface), `CoreSimSource` (the core, through the GDExtension) and `CoreEnvSource` (its sea and wind for the Sea node), `FakeSim` and `FakeBoat` (placeholder), `SimRunner` (50 ms ticks), class loading |
| `native/` | The GDExtension: `CoreSim` over `core/include/windmark.h` `SailShape` (the per-vertex sail shapes) and the wakes (`sea_wakes.h`: `SeaSampler`, `WakeRibbon`, `BowWaveSheets`, `MistCloud`) in `src/`, `build.sh`, `CMakeLists.txt`. Godot skips the folder (`.gdignore`) |
| `bin/` | The built extension library and `windmark.gdextension`. Not committed |
| `scripts/settings.gd` | `Settings`: the player's settings (`docs/specs/menus.md` §3), saved in `user://settings.cfg`, read through `Settings.current()` and applied with `apply_*` |
| `scripts/perf/` | `PerfMonitor` (the frame-time overlay and its CSV log, `docs/specs/hud.md` §17) and `PerfStats` (the per-frame section timings) |
| `scripts/controls/` | Input map defaults, device reader, `PlayerControls` (boat commands), sail key mapping, the input frame |
| `scripts/cameras/` | `CameraRig` and the chase, onboard, aerial and free cameras, shake, onboard eye point |
| `scripts/hud/` | `Hud`, `HudValues`, formats, bars and trim gauges; the race HUD: `RaceHudValues`, `RaceText` (rule texts, flags, signals), `RadarView`, `FlagsView`, `RoundingArrowView`, `PenaltyRingView` |
| `scripts/audio/` | The audio (`docs/specs/audio.md`): `GameAudio` (the node that plays the race), `SoundMap` (the sound map and its files), `SoundFormula` (terms, gates, triggers), `BoatSoundInputs` (the formula inputs of a boat), `AudioBuses` (the buses, ducking and wind pan), `SoundSynth` (the synthesised fallback) |
| `audio/default/` | The default sound set: Ogg Vorbis files written by `tools/soundgen` (our own synthesis), with their `.import` files |
| `data/sound_map.json` | The sound map (`audio.md` §9): the only place that names sound files |
| `scripts/venue/` | `VenueShapes` (the venue's land polygons and obstacles, from the core or the venue file), `LandTerrain` (the drawn ground height and colours), `ColorMesh` (vertex-coloured mesh builder) |
| `shaders/` | Shaders. `sea_common`, `sky_common`, `wake_common` (`.gdshaderinc`) hold the water, sky and wake maths, written so the offline preview can compile them as GLSL too; `water_l/m/h` are the sea per quality tier, `sky`, `wake`, `wake_normal`; `boat` is the boat surface shader; `sail` the sails, with the procedural cloth of `sail_cloth.gdshaderinc` (also compiled by the sail preview) |
| `scenes/` | Scenes. `sea/` is the sea (`sea.tscn`, `Sea`), its data source and wakes, and the daytime sky (`sky_day.tscn`, `SkyRig`, `env_day.tres`); `water_test.tscn` shows them together; `sail_test.tscn` is one boat sailing freely on the core (FakeSim as fallback), or racing alone on the example course, with cameras, controls and HUD on that sea and sky; `venue/` draws the venue land and obstacles (`VenueView`, `land.gdshader`); `course/` the course (`CourseView`, `CourseProps`); `menu/` the menus (`main_menu.tscn`, the main scene; `pause_menu.tscn`; the setup and settings panels, rows, theme and backdrop) |
| `tests/` | Headless tests |
| `generated/` | Build outputs staged for import (boatgen GLBs and sidecars). Not committed |
| `.godot/` | Godot's import cache. Not committed |

## Boat import test

```
game/tests/run_boat_import_test.sh           # generate wm12 and wm7, import, test
game/tests/run_boat_import_test.sh --no-gen  # reuse the GLBs already in game/generated/boats
```

The script runs boatgen (`python3 -m boatgen ... --out game/generated/boats --no-previews`, about 30 s for
both boats), then `godot --headless --path game --import`, and fails if the import log has any error or
warning. It then runs the test:

```
godot --headless --path game -s res://tests/boat_import_test.gd
```

The test loads every `<id>.glb` and `<id>_collision.glb` in `generated/boats/` and checks them against the class
file (`data/classes/<id>.boat.json`) and the physics sidecar (`<id>.physics.json`):

- axes and scale: +Y up, bow toward +Z, port toward +X, origin on the DWL at mid LWL; hull length, beam and
  canoe draft, keel and rudder depth and mast height match the class file
- the node set and total triangle count match the sidecar
- every material slot is present as a shared `StandardMaterial3D`, opaque, back faces culled, with
  `extras.tiling_m` kept as metadata
- `rudder`, `boom`, `wheel` and `pole` sit on the sidecar pivots, with their geometry placed for turning about the
  right axis
- sails: vertex and triangle counts, every vertex on its own grid node, corners where the sidecar puts them,
  and the two layers 2 mm apart with outward normals
- the collision GLB comes in as `StaticBody3D` nodes with one `ConvexPolygonShape3D` each and no visible mesh

Exit code 0 when every check passes. `WARN:` lines are known boatgen issues that do not break the import
(see the backlog tasks labelled `boats`).

Set `GODOT=/path/to/godot` if `godot` is not on the path. Everything runs headless; nothing opens a window.

## Simulation interface (`SimSource`)

Cameras, controls and HUD read the simulation only through `scripts/sim/sim_source.gd`. `CoreSimSource` implements
it on the core (below), `FakeSim` on a GDScript placeholder; switching one for the other changes nothing else. Names and units are the core's (`boat.md` §3, `sails.md` §3 and §7):
world ENU metres, radians, compass angles clockwise from north, one tick = `DT` = 0.05 s.

| Call | Returns |
| --- | --- |
| `tick()` | ticks stepped so far |
| `boat_count()` | number of boats |
| `class_info(b)` | `ClassInfo`: id, name, `loa`, `beam_max`, `lwl`, `bwl` (perf file), `transom_width` (class file), `rudder_max`, steering, sails (`SailInfo`: name, type, `sheet_min`, `sheet_max`) in sail order, `main_sail`, `front_sails` (sail slots), the boatgen physics sidecar |
| `state(b)` | `BoatState`: every field of `wm::BoatState` |
| `controls(b)` | `BoatControls`: `h_cmd`, `sheet_cmd`, `auto_trim`, `let_fly`, `performance_scale` |
| `outputs(b)` | `BoatOutputs`: every field of `wm::BoatOutputs` |
| `sails(b)` | `SailsView`: `front`, the change queue (`SailStep` sail, phase, reversed), `queue_len`, `queue_pos`, `queue_progress`, per sail `SailState` (phase, progress, beta, pole) and `SailOutput` (`k_h`, `m_opt`, `beta_opt`, `beta_t`, `trim_error`, `luff_shiver`, motion, backed) |
| `render_pose(b, alpha)` | `RenderPose` between the last two ticks: position, `z`, `psi`, `theta`, `phi`, `h`, `twa`, `twd_from` |
| `wind_clean(x, y)` | clean wind at a point: `Vector2(speed, from)` |
| `sea_height(x, y)` | sea surface height at a point (the one sea hook; in `FakeSim` flat, the test swell or the drawn sea's model) |
| `trim_speed_at(b, tws, awa_abs, eps)` | the config's `trim_speed` table (HUD trim tolerance), `NAN` without one |
| `apply_input(b, frame)` | applies an `InputFrame` (`networking.md` §4.1); returns the sail request result |
| `step()` | one tick |

Race and rules readers (empty without a race: `FakeSim`, free sailing), the Dictionaries of `CoreSim` with the C
field names: `has_race()`, `race()`, `race_boat(b)`, `race_order()`, `course()`, `course_labels()` (the course
file's display labels), `results()`, `race_split(b, step)` (race time at a completed step, `NAN` before),
`race_start_status(b)` (the rules hull against the start line: oriented ends, `s_bow`, `u_bow`, `in_band`,
`course_side`, `in_triangle`, `pre_start`, `over` under the prep flag), `boat_rules(b)`, `pairs()`, `race_events()`,
`rules_events()`, `contact_events()` (collisions.md §5, for the audio), `hail_state(b)` (`{}` until the core has rule 20 hails), `polar_vmg(b, tws)`,
`polar(b, tws, twa, front)`, `current_at(x, y, t_ms)`. `CoreSimSource` caches them until the next step.

`FakeSim` is a GDScript sketch of `boat.md` §5 and `sails.md` §4 to §5 on the class's generated tables (polar,
heel, accel, trim and optimal-angle tables, sail change timing), with a uniform wind (optional slow direction
oscillation), and flat water, a test swell (the water only, the hulls stay level) or the drawn sea
(`use_sea(model, t0_ms)`: the `SeaModel` of the Sea node, with heave, pitch and wave roll of `boat.md` §5.6 on the
hull points of `sea.md` §5, no wobble), and no collisions or wind shadow. Tick n is at environment time
`sea_time_ms(n) = t0_ms + 50 n`. It is not the reference and not deterministic across platforms.

## Core binding (GDExtension)

`native/` builds `CoreSim`, a Godot class over the core's C API (`core/include/windmark.h`, `core/README.md`), and
`scripts/sim/core_sim_source.gd` (`CoreSimSource`) puts the `SimSource` interface on it. Requirements: CMake 3.22 or
newer, Ninja, Clang, git, Godot 4.6 (tested with 4.6.3 on macOS arm64; the Linux and Windows library names are in
`windmark.gdextension`, not built yet).

```
game/native/build.sh                   # template_debug (default): game/bin/libwindmark_godot.macos.template_debug.arm64.dylib
game/native/build.sh template_release  # the release library
game/tests/run_core_sim_test.sh        # builds when game/bin has no library, then the headless test
```

`build.sh` clones the pinned godot-cpp (10.0.0-stable, commit `507ed9d`, MIT) into `native/third_party/godot-cpp`
when missing and checks the commit, configures `native/build/<target>` with CMake and Ninja, and builds the core
(under its float rules, `windmark_static`) and the extension into `bin/`, together with `windmark.gdextension`.
The first build takes a few minutes (godot-cpp), later ones seconds. It then runs `native/register.sh`, which lists
the extension in `.godot/extension_list.cfg`: in Godot 4.6.3 a headless `--import` that discovers a new extension
crashes on exit, and with the entry in place the extension loads at start-up instead. The test runners call it too.
Without a built library the rest of the project runs as before: nothing refers to `CoreSim` by type, and
`CoreSimSource.available()` is false.

`tests/core_sim_test.gd` (run by `run_core_sim_test.sh`, headless): one wm7 sailing freely for 60 s exactly as the C
API example does it (`core/examples/race_example.c`), and the runner checks that both end at the same place and
speed; every `SimSource` call, the render pose between ticks, the input frame wire form against the core's, sail
requests; a race world on `example_bay`: two runs with the same inputs give the same checksum, race signals, the
sea components and exposure, the wind state with live puff patches, the current, and `SeaModel` on the core's
components within 1 mm of the core's sea height.

**`CoreSimSource`** (a `SimSource`; also what `FakeSim` offers besides it, so it drops in):

| Call | Does |
| --- | --- |
| `settings` | world settings for `create()`, the keys of `CoreSimSource.default_settings()` (the C API's `wm_world_settings`: seed, wind, shift preset, puffs, sea, shadows, race and rules settings) |
| `create(venue = "")` | the world on a venue (`example_bay` or a path; `""` open water); `last_error()` on failure |
| `add_boat(id, x, y, psi, v, auto_trim)` | FakeSim's call: a free-sailing boat of class `id` (creates an open-water world when none exists); the core starts it at 60 % of its polar speed, so `v` is unused |
| `add_entry(id, entry)`, `create_race(course)`, `place_boat(b, x, y, psi)` | a race entry (`human`, `ai`, `performance_scale`, `auto_trim`, `front_sail`), the race on `venue/course` or a path, free-sailing placement |
| `apply_input(b, frame)` | applies the frame decoded from its 6-byte wire form, the values every peer applies; the controls take effect at the next step (`controls(b)` shows them after it) |
| `sea_time_ms(ticks)`, `render_time_ms(alpha)` | the environment clock: tick n at 50 n ms (the world's tick 0 is its zero); a pose at alpha at `sea_time_ms(tick() - 1 + alpha)` |
| `sea_height_at(x, y, t_s)` | sea height at any time (s since tick 0) |
| `sea_components()`, `sea_exposure()`, `wind_state(t_ms)`, `current_at(x, y, t_ms)` | the Sea node's source calls (as `SeaEnvSource`), from the core: the drawn puffs are the ones the boats sail in. `CoreEnvSource` is the Node that hands them to the Sea (`source`) |
| `boat_env(b)`, `wake_state(b, pose, own)`, `checksum()` | the wind, current and shadow the boat stepped in; the `SeaWakes.update_boat` state with the class waterline and transom; the tick checksum |
| `add_ai(id, level, speed_only)` | an AI boat of class `id` sailed by the core's AI skippers (ai.md) at `level` (`AI_LEVELS`: easy, intermediate, expert, pro, or its index) |
| `ai_take_over(b)`, `ai_release(b)`, `ai_has(b)` | an AI sails a boat as it is (a disconnected human, ai.md §14), hands it back; whether an AI sails it |
| `ai_telemetry(b)`, `ai_debug(b)` | ai.md §15 per-race telemetry (tacks, gybes, penalties, OCS, tactic activations by name, stuck time, minimum gap, bad air records, start delay) and the last decision (tactic, target heading, filtered wind, leg, aim and start spot) |
| `save_snapshot()`, `load_snapshot(snap, course)` | the world snapshot and the AI memory (`{world, ai}`, PackedByteArrays), into a new world with the same settings and boats |
| `step_ticks(n, stop_when_closed)` | fast-forward without rendering (only the last tick's events stay readable) |
| `core` | the `CoreSim` itself for everything else: race, course, results, splits (`race_split`), the start line status (`race_start_status`), rules state, pairs, race, rules and contact events, sail events, perf tables by name, polar |

Records read every tick (`boat_state`, `boat_outputs`, `boat_controls`, `render_pose`, `sail`, `boat_env`) come from
`CoreSim` as `PackedFloat32Array` in the C structs' field order (`CoreSimSource.STATE_FIELDS` and the rest), the
others as Dictionaries with the C field names. `CoreSimSource` caches the per-boat records until the next step.

## Controls, cameras and HUD

- **Frame order** (`scenes/sail_test.gd`): `InputReader.read()` (devices through the input map into a `RawInput`),
  `PlayerControls.update()`, `SimRunner.advance()` (at each 50 ms boundary: `PlayerControls.stamp()` the input
  frame, `apply_input`, `step`, `Hud.tick`, the sail snapshot), the Sea's render time, `render_pose`, the boat node
  (`BoatView.apply`, `apply_sails` between the last two sail snapshots) and `SeaWakes.update_boat`,
  `CameraRig.frame()`, `Hud.frame()`; the Sea and SeaWakes nodes then draw the frame.
- **Race mode with AI** (`race_mode`, `fleet_size`, `ai_level`, `ai_speed_only`, `watch`): the player (boat 0)
  and `fleet_size - 1` AI boats of the core's skippers on `course`, each drawn by its own `BoatView` (hull, rig,
  sails at the distance update rates, wakes). The set-up comes from `GameSetup.current()` when the menus have
  written one (`GameSetup.next`) or a test sets `setup`, else the scene's exports (free sailing); command-line
  flags after `--` override both: `--race`, `--free`, `--fleet=10`, `--level=expert`, `--speed-only`, `--watch`
  (an AI sails the player's boat too), `--class=wm12`, `--venue=`, `--course=<venue>/<id>`, `--seed=` (0: from
  the clock), `--wind=<kn>`, `--wind-from=<deg>`, `--fake`, `--core`. Spectating (`spectate_next`, `prev`,
  `leader` by race rank) works when not racing (`--watch`) or once the player has finished, retired or left.
  To race in a window: `godot --path game res://scenes/sail_test.tscn -- --race --fleet=10 --level=intermediate`.
- **Simulation** (`sim_kind`): `AUTO` (the default) runs the core through `CoreSimSource` when the GDExtension is
  loaded and `FakeSim` otherwise; `CORE` and `FAKE` force one. On the core the scene is free sailing without a race
  (`create(venue)`, `add_entry`, `place_boat` at `start_x`, `start_y`, `start_twa_deg` off the wind) on
  `example_bay`, one `class_id` boat (`wm7`, or `wm12`), with the wind of `wind_speed_kn`, `wind_from_deg`,
  `puffs`, `shift_preset` and `world_seed`. The Sea's source is a `CoreEnvSource`, its clock the core's
  `render_time_ms`, the wakes `CoreSimSource.wake_state`, so the puffs drawn are the ones the boat sails in.
- **Boat** (`BoatView`): the node at the render pose (`conventions.md` §11), the rudder (with the tiller it
  carries) and the wheel from the helm `h`, the boom at the main's sail angle with the mainsheet sheared to follow
  it, and the sails bent per vertex every frame as `docs/specs/sail_visuals.md` says (below). The sail inputs are
  interpolated between the last two ticks (`apply_sails(prev, cur, alpha, dt)`): sail angles, pole angle, progress,
  luff shiver and the boat's apparent wind (`SailsView.awa`, `aws`, `tws`); a sail that is `down` is hidden.
- **Sails** (`sail_visuals.md`): at load each sail becomes its own grid-order mesh (`2 · rows · cols` vertices, the
  imported uv sets and triangles re-indexed by `SailGrid`, vertex compression off, a `custom_aabb` around the sail
  at any angle) on `shaders/sail.gdshader` (roughness 0.55, the sun through the cloth as a back-light). Every frame
  the native `SailShape` (one per sail) advances the flutter phase, the backed factor and the twist side, builds the
  shape (fill and camber from the sail angle and the wind line, twist to leeward, flutter from the core's luff
  shiver, the jib popping through when backed, halyard and furler hoists, the spinnaker bundle, fill and drop, the
  flying kite extruded down the apparent wind), places it about the boom, the luff, the sprit or the pole, derives
  both cloth layers and their normals, and rewrites the mesh's vertex buffer in one
  `mesh_surface_update_vertex_region` call. Update rate by distance to the camera: every frame within 200 m, 15 Hz
  to 800 m, 4 Hz beyond, none outside the view frustum. Cost on an M-series Mac: about 11 µs per sail update (wm7:
  30 µs for main, jib and kite), so 40 boats near the camera take about 1.2 ms per frame. Without the GDExtension
  the GDScript `SailShapeRef` does the same about 45 times slower (a test and fallback path, not for fleets).
- **HUD commands**: the helm mark, the sheet bar and text, `AUTO` and `LET FLY` of the own boat come from the
  local `PlayerControls` every frame (`Hud.local_commands`), since the core applies a command at its next step.
- **Input map**: `scripts/controls/default_bindings.gd` is the one source of the defaults of `controls.md` §3.
  After changing it, rewrite the `[input]` section of `project.godot` (nothing else in the file is touched):
  `godot --headless --path game -s res://scripts/controls/write_input_map.gd`. Axis actions and device pairs carry
  suffixes (`helm_stick_left/right`, `sheet_in_trigger`, `camera_orbit_*`, `camera_look_*`,
  `camera_orbit_drag`); combos and context rules are resolved in code (see the file's header).
- **Steam Deck**: the default Steam Input template presents the gamepad bindings; its Deck-only items (L4 for
  `helm_fine`, right trackpad as `camera_orbit`, Steam + R1 for `screenshot`, R4 for `hud_density`, R5 for
  `boat_select`) belong in that template, which is not in the repo yet. The gamepad's View is `rankings_pad`: a tap
  cycles the instrument density, a hold shows the ranking (resolved in the Hud).
- **Sea on FakeSim**: the scene holds the Sea node, its `SeaWakes` and the `SkyRig` of `scenes/sea/`. `sea_source` picks the
  example bay as the core writes it (`CORE_SAMPLES`, scenario `sea_scenario`, default `example_bay_10kn`; its wind
  replaces the scene's) or the placeholder sea from the scene's wind; `AUTO` (the default) takes the core samples
  when `generated/sea/sea_render_samples.json` exists (`tests/run_water_test.sh` writes it). The fake sim runs on
  the same `SeaModel` (`FakeSim.use_sea`), and the Sea's clock follows the ticks (`sea_time_ms(tick - 1 + alpha)`),
  so hull and water agree. The cameras keep clear of the water through `CamTypes.Target.sea_height`, a function
  `(x east, y north) -> height`, set to `Sea.height_at` (`sea.md` §7.2 at the frame's render time).
- **Options** not wired to a settings screen yet: `PlayerControls` (helm key mode, dead zone and curve, sheet rate,
  hold or toggle, sheet turns auto-trim off), `CameraRig.options` (speed, invert, reduced motion, smooth switch,
  auto-recentre), `Hud.assist` (Full, Standard, Minimal). Not implemented yet: mouse helm, one-hand layout,
  rebinding UI, vibration.

## Measuring performance

The sail scene carries a frame-time overlay (`docs/specs/hud.md` §17): F9 shows and hides it. It shows FPS, the
frame time (mean and the 1 % worst over the last 5 s), the CPU time of the process step, the render thread's CPU
time, the GPU time of the main view and of the other views (Godot's viewport render time measurement), draw calls,
primitives and objects, the render scale, sizes, tier, boats and renderer, and the game's own sections in
milliseconds per frame (`input`, `sim`, `hud`, `audio`, `sails`, `boats`, `wakes`, `sea`, `course`, `camera`).
Flags after `--`:

| flag | effect |
| --- | --- |
| `--perf` | the overlay shown from the start |
| `--perf-log=PATH` | one CSV line per second to PATH (absolute, `user://`, or relative to the shell's folder) |
| `--perf-seconds=N` | quit after N seconds (from the scene's start, after loading) |
| `--render-scale=0.67` | this run's render scale (0.5 to 1, or 50 to 100), over the setting; not saved |
| `--upscaler=fsr` | this run's upscaler: `fsr`, `bilinear` or `metalfx` (MetalFX spatial, Metal only) |
| `--quality=M` | this run's quality tier: `L`, `M` or `H`, over the setting; not saved |
| `--no-vsync` | this run without vsync, to see the headroom; not saved |
| `--shadow-splits=0` | this run's sun shadow cascades: `0` (off), `2` or `4`, over the tier; not saved |
| `--shadow-atlas=2048` | this run's directional shadow atlas size, over the tier; not saved |
| `--no-wake-buffer` | this run without the wake normal buffer (tiers M and H); not saved |
| `--no-boat-shadows` | the boats cast no sun shadows in this run |
| `--sea-grid=120x160` | this run's sea radial grid (rings x segments), over the tier; not saved |
| `--water-shader=l` | this run's water shader (`water_l`, `_m` or `_h`), over the tier; not saved |
| `--no-hud` | the HUD hidden from the start (as F10) |

A measured race in a window (asks the owner first: it opens one), 10 boats for 60 s:

```
godot --path game res://scenes/sail_test.tscn -- --race --fleet=10 --perf --perf-log=perf/race_m1.csv --perf-seconds=60
```

The CSV starts with a header line; each line is the means over one second: `time_s`, `frames`, `fps`,
`frame_ms`, `frame_max_ms`, `frame_p99_ms` (1 % worst over the last 5 s), `process_ms`, `physics_ms`,
`render_cpu_ms`, `setup_cpu_ms`, `gpu_ms` (main view), `gpu_other_ms` (other views: the wake normal buffer),
`draw_calls`, `primitives`, `objects`, the sections `input_ms` … `camera_ms` with `sim_max_ms` (the slowest frame's
simulation, the tick frames), then the set-up: `render_scale`, `render_w`, `render_h`, `window_w`, `window_h`,
`upscaler`, `quality`, `boats`, `camera`, `renderer`, `driver`, `vsync`, `max_fps`. The GPU columns are 0 where
the driver does not measure (headless). With vsync on the frame rate stops at the display's; turn it off in the
settings (or compare `gpu_ms` with the frame time) to see the headroom. The first seconds include shader
compilation.

**Renderer comparison.** The project renders with Forward+. To try the Mobile renderer (built for tile-based GPUs
such as Apple's M1) without changing the project, pass Godot's own flag before `--`:

```
godot --path game --rendering-method mobile res://scenes/sail_test.tscn -- --race --fleet=10 --perf-log=perf/race_mobile.csv --perf-seconds=60
```

The `renderer` column records which one ran. On Mobile, screen-space reflections (tier H) are not drawn and
`water_render.md` §7 only promises tier L; the others may miss effects. Godot's `--rendering-driver` (`metal`,
`vulkan`) picks the graphics API the same way.

## Sail visuals tests

```
game/tests/run_sail_visuals_test.sh             # the tests of sail_visuals.md §12 and the BoatView sails
game/tests/run_sail_visuals_test.sh --preview   # also the offline previews (numpy, Pillow, moderngl)
```

Headless. `tests/sail_visuals_test.gd` runs every numbered test of `sail_visuals.md` §12 on the GDScript reference
and on the native `SailShape`, compares the two on random drivers in every phase, checks the native vertex buffer
against Godot's own encoding of the same arrays, sets up the wm7 and wm12 sails in `BoatView` (grid-order meshes,
uv sets, sail shader, rest-pose normals, the kite's belly to leeward, flaked headsails), checks the update rate by
distance and the frustum, and prints the cost per sail. The previews: `tests/sail_preview_dump.gd` sails a boat on
the core into trimmed, eased, let-fly, tacking, hoisting, reaching, running and dropping situations and dumps the
bent boat, `tests/sail_preview.py` renders them offscreen to `generated/sail_preview/` (with `--publish` the
JPEGs in `tests/previews/sails_*.jpg`). Its lighting is a stand-in for Godot's: it is for judging shapes.

## Race HUD

`Hud` shows the race whenever the sim it is ticked with has one (`SimSource.has_race()`), so the sail scene needs
no extra call; `RaceHudValues` (`Hud.race`) computes the values every tick from the race and rules readers, for the
viewed boat. What it shows (`docs/specs/hud.md`):

- **Start** (§9): the countdown ("Warning in", "Start in" with tenths in the last 10 s, then the race clock), the
  flags row (class, the prep flag, X, first substitute), a 3 s banner at each signal, the start line panel
  (distance to the line or to the nearer end, time to the line along the COG, time to burn, the bias with the
  favoured end), `OVER` with the flag's consequence in the last minute, `OCS` with the way back after the gun.
- **Next mark** (§7, §4, §6, §3.2): name (course file label), lap and leg, rounding arrows (red port, green
  starboard; both for a gate), distance and bearing, leg type and ETA, VMG and VMG % (VMC on a reach) with the
  target speed and angle, the distance and time to the layline or `OVERSTOOD`, the shift meter, the sail hint.
- **Position** (§10): rank with the 2 s hysteresis (finishes at once), gap to the leader at the last common split or
  as an estimate (`~`), the boats ahead and behind; the ranking list while `rankings` is held (Tab).
- **Rules** (§11, §12): the highest priority awareness line, the protest prompt (8 s) and the hail button and reply,
  both wired into `PlayerControls`; the penalty panel (rule text and other boat, turn ring with tack and gybe
  ticks, zone and reset notes, deadline, the disqualification warning); penalty, served, late, finish blocked
  and disqualification banners.
- **Radar** (§8): heading-up or north-up (Z), range 100 m to 3 km in x1.5 steps (= and -), both remembered in
  `user://hud.cfg`; boats coloured from the pair records (pulsing on Warning and Breach), marks, lines, laylines,
  the wind arrow.
- **Feed and results** (§13): six lines of 8 s; provisional results at the own finish, the core's results at the
  close (AI badges, projected finishes marked `proj.`).
- **Assists** (§14): `Hud.assist` and `Hud.shows(element)`; the wind shadow view is not drawn yet.

Names, skippers and AI levels come from `Hud.race.names`, `skippers`, `ai_levels` (boat index to text; defaults
"You" and "Boat n"). `Hud.hud_event(kind, data)` reports signals, OCS, penalties, served penalties, rule warnings,
the finish, the protest prompt and the results for the audio. `Hud.ui_input(raw)` takes the ranking and radar keys
from a `RawInput`; without it the Hud polls the input map (not headless).

## UI tests

```
game/tests/run_ui_tests.sh    # needs the generated boats (runs run_boat_import_test.sh when they are missing)
```

Runs headless, with scripted input at fixed frame rates:

- `tests/controls_test.gd`: `controls.md` §8 (stick curve, hold-to-steer ramp, sheet keys, latching, sail
  mapping, focus, last-moved source, set and hold at 30, 60 and 144 fps), auto-trim hand-over, the input map
  against the defaults, the input frame encoding and one frame per tick.
- `tests/cameras_test.gd`: `cameras.md` §10 (chase geometry, heading follow, frame-rate independence, 10 minutes of
  water clearance in a 1.5 m sea, onboard side change, aerial up modes, presets, shake), the free camera, near
  and far planes, cycling and the smooth switch.
- `tests/race_hud_test.gd`: the race HUD on scripted race states (`tests/race_stub_sim.gd`): countdown, flags,
  banners, the time to burn test of `hud.md` §15, bias, OVER and OCS, next mark, VMG on a run and VMC away from
  the mark, layline distance and overstanding, shift meter, sail hint, rank hysteresis, gaps and splits, every
  rules awareness line, radar colours for the port-starboard, windward-leeward and mark-room pair records,
  penalties, protest and hail prompts, feed, results and assists; the layline test of §15 on the core; a race on
  the core (`example_bay/example_wl`, two boats steered by `tests/race_pilot.gd` from the spawn to the results)
  with the HUD checked against the race and rules records every tick; the sail test scene in race mode; the
  presentation of `hud.md` §16 (what each instrument density shows per phase, the density key, the View tap and
  hold, the stored setting, name tags within 50 m or selected, the penalty turn only in the chase and aerial
  cameras, every text fitting at 1280 x 800 for UI scales 80 % to 130 %). The previews:
  `tests/race_hud_preview_dump.gd` runs the course preview shots of `tests/course_preview_dump.gd` (start, upwind,
  aerial) with their cameras so the world tags land on the frame, at the Glance, Race and Data densities and on
  the Deck's 1280 x 800, plus a scripted incident and the results; `tests/race_hud_preview.py` draws every
  block's primitives in Barlow over the course frames (`generated/race_hud_preview/`, with `--publish`
  `tests/previews/race_hud_*.jpg`).
- `tests/hud_test.gd`: `hud.md` formats, filters and time constants, trim gauge colours, tell-tales, tolerance and
  assist presets on a scripted boat state; then `scenes/sail_test.tscn` on FakeSim sails 20 s with scripted input
  on the example bay sea and the HUD text is checked against the sim's values, with the sea checks: Sea and
  SkyRig in place, the sim on the drawn sea's model, the camera never below `Sea.height_at + 0.99` and its
  clearance hook being `Sea.height_at`, the hull heaving, both wakes of the boat laid; a short run on the
  placeholder sea; then the scene on the core, 40 s with a set-and-hold tack, a kite hoist and auto-trim off:
  every frame the boat node against the core's render pose record, the rudder, boom and main at the helm and the
  interpolated sail angle, sails hidden only when down, clews on the side of the sail angle, the Sea's clock and
  wind state the core's, the HUD commands the local ones (while the core's lag a step); at the end the HUD
  numbers against the core's state; and a short wm12 run. The script writes the core sea samples first when they
  are missing, and builds the GDExtension when `game/bin` has none.
- `tests/perf_test.gd`: the frame-time overlay (`hud.md` §17): the 1 % worst statistic, the sections, and the
  sail scene (a three-boat race on the core, FakeSim without it) with the overlay shown and a log for 2.6 s of
  real frames: every column, one line per second, the sections timed, F9 hiding it. The runner then starts the
  sail scene as the game does with `--fake --perf --perf-log=generated/perf_smoke.csv --perf-seconds=3` and checks
  that it quits with a log.

To sail the test scene yourself (opens a window): `game/native/build.sh` once (the core; without it the scene
runs on FakeSim), then `godot --path game res://scenes/sail_test.tscn` (after `--`: `--class=wm12` for the
12 m boat, `--fake` for FakeSim, `--race` to race alone on `example_bay/example_wl` through the start sequence,
`--course=<venue>/<id>` for another course). Keys: ←/→ or
A/D helm (set and hold, ↓ centres), T auto-trim, W/S sheet, Space let fly, 1/2 sails, C camera, F5 to F8 camera
modes, right mouse drag or IJKL orbit, wheel or O/U zoom, R recentre, Backspace reset (free sailing: back to the
start point; race mode: restart the race), Esc pause, F10 hide HUD, G instrument density (Glance, Race, Data),
B select the next boat for a name tag (or click a boat), N name tags on and off, F9 the frame-time overlay.

## Menus

`scenes/menu/main_menu.tscn` is the main scene (`docs/specs/menus.md`): Quick race, Free sail, Settings, Quit.
Start writes `GameSetup.current()` and changes to `scenes/sail_test.tscn`. The pause menu is a scene of its own
that the sail scene instances as a child; it follows the scene's pause, holds the boat's controls while open and
applies the settings to the scene.

```
game/tests/run_menus_test.sh
```

checks that the lists match the files on disk, that a quick race and a free sail write `GameSetup` and ask for
the sail scene, keyboard navigation, the settings file round trip, the apply calls (the render scale on the
root viewport's 3D scale and upscaler, Auto's rule), the layout at 1280 × 800 at
every UI scale, and the pause menu over the sail scene on FakeSim. To look at the menus (opens a window):
`godot --path game`.

## Audio

`scripts/audio/game_audio.gd` (`GameAudio`) plays the race as `docs/specs/audio.md` says, from the sound map
`data/sound_map.json` (`SoundMap`): the boat sounds of §3 on every boat (hull, wake, bow wave, slaps, rig, luffing
and flogging sails, winches and sheets, the gybe, halyards, furlers, drops, collisions and rubbing), the wind at
the listener (§4, panned toward the apparent wind onboard), the race signals and events (§5), the ambience beds and
one-shots (§6) and the course objects (§7: a buoy on each mark, the committee boat's engine). The sail test scene
makes one `Audio` node: `setup(sim, boat_views, viewed)` once, `tick()` after each step, `frame(dt, camera,
onboard)` every frame, `restart()` when the race restarts, and `Hud.hud_event` into `on_hud_event`. Boat sounds hang
under each `BoatView` at their anchors from the physics sidecar, so the camera (the listener) hears them from where
they are on deck. Voices: at most 48, the viewed boat first, then the race, then the other boats by distance (the
six nearest; beyond 150 m only the wake and collisions). Cost: about 0.5 ms per frame on an M-series Mac with 20
boats around the listener and all 48 voices taken (`audio_test` prints it).

- **Buses** (`AudioBuses`): `own_boat`, `fleet`, `wind`, `race`, `voice`, `ambience`, `venue`, `ui`, made at run time
  (`Settings.apply_audio` makes them and sets the player's volumes on them). Each has an Amplify effect for the
  ducking (a signal ducks the ambience 6 dB for 1.5 s, the pause menu everything but ambience and UI by 12 dB), the
  wind bus a Panner.
- **Sounds**: `audio/default` is synthesised by `tools/soundgen` (filtered noise, tones and impulses; our own, so
  no licence to record; about 770 kB for 42 files). A recording replaces a file by its name, or a map entry points
  at other files; a second map (another folder, even outside `res://`) swaps the set with no code change
  (`GameAudio.setup(sim, nodes, viewed, SoundMap.load_file(path))`). A missing file warns once and drops out; the
  wind, water and horn fall back to sounds made at load (`SoundSynth`).
- **Not there yet**: the voice hails (no recordings; the map's `hails` table is ready), captions (`audio.md` §8),
  the venue placed sources (no venue look files), the Doppler option, the rounding tick, the `sound_set` setting
  and interface sounds.
- **Headless**, `GameAudio.audible` is off: the players are set up and tracked but not started, so test runs never
  leave playbacks in the audio server at exit.

```
game/tests/run_ui_tests.sh    # includes tests/audio_test.gd
godot --headless --path game -s res://tests/audio_test.gd
python3 tools/soundgen/soundgen.py   # rewrites audio/default (NumPy, ffmpeg)
```

`tests/audio_test.gd` runs the tests of `audio.md` §11 (formulas, gates, triggers, signals through `hud_event`, the
swap and the missing file, the voice limit with 20 boats), the buses and the settings' volumes, the pause ducking,
the wind pan and beds, the synthesised fallback, a short run with real players, and the sail test scene with its
sound on FakeSim and in a race on the core (the warning signal's horns, the fleet bus, the restart).

## Venue land and the course

- **Land** (`scenes/venue/venue_view.gd`): the venue's land polygons and obstacles come from the core
  (`CoreSim.venue_land`, `venue_obstacles`, the shapes the collisions use; the venue file on FakeSim). Each land
  polygon becomes a terrain mesh on a 5 m grid (`LandTerrain`): the waterline lies on the polygon or up to 2.5 m
  inside it (never outside, so a boat never sails through drawn land), pebble beaches or low rocky shore under a
  wet band, low hills (about 45 m) of dry grass and maquis with stone pines and shrubs. Polygon obstacles are
  concrete quays (walls into the water, deck at 1.3 m, bollards, a harbour light at the seaward end), circle
  obstacles limestone rocks whose waterline is the circle. The land shader's grain (`land_common.gdshaderinc`) is
  shared with the offline preview. `VenueView.ground_height` is the drawn ground for the cameras (`cameras.md`
  §7: chase and aerial pulled in 2 m short of land, eased out over 0.5 s; the free camera stays above it).
- **Course** (`scenes/course/course_view.gd`, race mode): marks at the core's resolved positions (styles and
  labels from the course file): inflatable and large cylinders and the tetra pin riding the drawn sea, the
  committee and mark boats on the 17-point outline at their resolved heading, the committee boat's flags hoisted
  per signal (class, prep, X; orange always) and blue on the finish boat after the start. On the water through
  the Sea overlay hooks: the start line (white, red while over in the last minute, green until started), the
  gate line, the finish line on the last leg, the laylines (`hud.md` §6, from `CoreSim.polar_vmg` at the
  10 s smoothed clean wind, 2 Hz) and the zone circle within 6 L; in 3-D the rounding arrow on the next mark and
  a bouncing marker with its name and distance beyond 500 m. The race HUD (see "Race HUD") shows the race state.
- **Tests**: `tests/run_course_land_test.sh` (headless, `tests/course_land_test.gd`): the core's shapes equal the
  venue file, ground above water only inside the polygons, quay and rock on their obstacles, the camera never
  inside land, the reset key in free sailing (core and FakeSim) and in race mode, marks at the core's positions
  riding the sea, the committee boat heading, start line state and flags against the race state through every
  start signal, laylines at the polar VMG angles. `--preview` also writes the offline previews
  (`tests/course_preview_dump.gd`, then `tests/course_preview.py`, which reuses `water_preview.py`) into
  `generated/course_preview`; the committed ones are `tests/previews/course_*.jpg`.

## Notes on the imported boats

- Godot wraps each GLB in its own root node named after the file. The boat's root node (named after the class
  id, with `extras` metadata `class` and `name`) is its only child, and the parts are children of that.
- The glTF importer re-indexes every mesh: vertices come out in the order the triangles first use them. Every
  sail vertex is referenced (the full two-layer grid, zero-area head cells kept), so all `2 · rows · cols` of them
  import, but the sidecar's row-major order holds only in the GLB file. The stable key is uv1 plus the layer side:
  `SailGrid.grid_index(mesh, rows, cols)` rebuilds the grid index from it; call it once on the flat sail as
  imported.
- Materials come in as `StandardMaterial3D` with boatgen's tiling texture sets (albedo, roughness and normal maps
  on uv0, scaled by `1 / tiling_m`) and its PBR factors (base colours converted from linear to sRGB). Every node
  but the sails and the mainsheet carries baked ambient occlusion in `COLOR_0`, which Godot's import multiplies
  into the albedo (`vertex_color_use_as_albedo`). boatgen's uv1 (liveries) arrives as Godot's `UV2`.
- **Boat materials** (`BoatMaterials.apply(root)`, called by `BoatView.create` and the water test scene): every
  imported slot is replaced on the imported meshes by a `ShaderMaterial` on `shaders/boat.gdshader` with the
  slot's factors and textures. One texture per texture set and map serves every boat of every class (the importer
  extracts a copy of the set from each GLB; the first loaded is kept and the others are released with their
  `StandardMaterial3D`), and slots with the same factors share one material. The baked AO goes to `AO` with
  `AO_LIGHT_AFFECT = 0`, so it darkens the ambient and reflected light only, never the sunlit albedo. The shader
  caps the linear albedo at 0.8 (bright paint and gelcoat), so a white hull in full sun keeps its shading.
  `tests/boat_materials_test.gd` (run by `run_boat_import_test.sh`) checks a fleet of both classes.
- Default import settings generate LODs and shadow meshes and compress vertices. `BoatView` rebuilds each sail as
  its own uncompressed `ArrayMesh` at load, so the import settings of the sail meshes do not matter.

## Sea, sky and lighting

`scenes/sea/sea.tscn` (`Sea`) draws the water of `docs/specs/water_render.md`: a camera-centred radial grid whose
vertex shader evaluates the core's `sea_height` from the wave components, with detail normals, puffs and lulls,
whitecaps, wakes (`SeaWakes`) and water overlays, in three quality tiers (`SeaQuality`: L, M, H). It reads:

- a source with `sea_components()`, `sea_exposure()` and `wind_state(t_ms)`, and optionally
  `venue_wind_field()` (the venue file's land-effect field, drawn as the wind slowed near land; `Sea.set_wind_field`
  sets it directly). `SeaEnvSource` is the placeholder
  until the core binding exists: `PLACEHOLDER` builds a sea and puffs with the spec formulas and Godot's random
  numbers, `CORE_SAMPLES` reads the core's own components, exposure and puff patches from
  `generated/sea/sea_render_samples.json`;
- `render_time_ms`, the environment clock of the frame (advanced by the node itself unless `use_internal_clock`
  is off);
- a `SkyRig` for the sky colours and the sun, and the camera it follows.

Boats get wakes through `SeaWakes.update_boat(id, state)` with the interpolated pose and the class dimensions.
With the GDExtension built, the wakes' per-frame work is native (`native/src/sea_wakes.h`): the sea height for the
spray from the wave components (handed over when they change), each ribbon and bow wave written in place into a
fixed-size mesh, and the mist written into its MultiMesh with one buffer call. Without it (or with
`SeaWakes.use_reference`) the GDScript references draw the same: `WakeRibbonRef`, `BowWave`, `SeaModel.height`.
Headless Godot does not keep in-place mesh updates, so the preview dumps draw with the references.
The wake normal buffer (tiers M and H) exists only while wakes are drawn.
`Sea.height_at(x, y)` is a CPU mirror of the core's sea height (double precision) for anything that needs the
surface before the binding exists.

`scenes/sea/sky_day.tscn` (`SkyRig`) is the daytime preset: the sky shader, the sun light, fog toward the
horizon colour, sky reflections and the camera exposure, set from one group of parameters. Sun and sky keep their
clear-day proportion (the sun about four fifths of the light on a level surface), and the exposure brings the
scene back to screen range.

### Water tests

```
game/tests/run_water_test.sh            # core samples, import, checks
game/tests/run_water_test.sh --preview  # also the offline previews
```

The script builds `core/tools/gen_sea_render_samples.cpp`, writes the core's samples, imports the project (fails
on any error or warning) and runs `tests/water_test.gd`: every shader parses; the drawn height matches the core's
`sea_height` within 1 mm (a double-precision mirror and a float32 emulation of the shader path, points up to
8 km, times up to 4 h); slope, puff factor and exposure match; the far-field fade table; the wake geometry; and
the test scene on every tier. With the GDExtension built it then runs `tests/wakes_native_test.gd`: the native
wakes against their GDScript references (sea height, ribbons with spray, current and hidden rows, bow waves, mist,
and a `SeaWakes` drawing each way), the in-place buffers byte for byte against Godot's own encoding, and the cost
per boat of both paths.

### Offline previews

Godot's headless mode has no renderer, so the previews run in two steps without a window:
`tests/water_preview_dump.gd` runs the test scene headless and writes every uniform, mesh and texture the water,
wake and sky shaders get, then `tests/water_preview.py` renders them on an offscreen OpenGL context with the
same shared shader functions (the lighting around them is a stand-in for Godot's). `--publish` also writes the
JPEGs committed in `tests/previews/`.

The previews draw the boats with the boat shader's textures, factors and baked AO, without shadows. The engine's
own picture needs a short windowed run (it opens a window for about 7 seconds):

```
godot --path game res://scenes/water_test.tscn -- --capture=/tmp/windmark_water --tier=M
```

It writes `water_<camera>_<tier>.png` for the chase, aerial, overview and sun cameras and quits.
