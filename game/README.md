# Windmark front end (Godot)

Godot 4.6, Forward+ renderer. So far: the boat import test, the sea, sky and lighting (`docs/specs/water_render.md`),
the core binding (a GDExtension over the core's C API) and a placeholder simulation behind the same interface, the
controls, the cameras, the minimal HUD and a sail test scene that puts them together on the core.

## Layout

| Path | Role |
| --- | --- |
| `project.godot` | Project settings |
| `scripts/` | GDScript. `sail_grid.gd` (`SailGrid`) maps imported sail vertices back to the boatgen sail grid; `frames.gd` (`Frames`) holds the axes and angle helpers; `boat_view.gd` (`BoatView`) places the generated boat, its rudder, wheel, boom, mainsheet and sails |
| `scripts/sim/` | `SimSource` (the simulation interface), `CoreSimSource` (the core, through the GDExtension) and `CoreEnvSource` (its sea and wind for the Sea node), `FakeSim` and `FakeBoat` (placeholder), `SimRunner` (50 ms ticks), class loading |
| `native/` | The GDExtension: `CoreSim` over `core/include/windmark.h` (`src/`), `build.sh`, `CMakeLists.txt`. Godot skips the folder (`.gdignore`) |
| `bin/` | The built extension library and `windmark.gdextension`. Not committed |
| `scripts/controls/` | Input map defaults, device reader, `PlayerControls` (boat commands), sail key mapping, the input frame |
| `scripts/cameras/` | `CameraRig` and the chase, onboard, aerial and free cameras, shake, onboard eye point |
| `scripts/hud/` | `Hud`, `HudValues`, formats, bars and trim gauges |
| `scripts/venue/` | `VenueShapes` (the venue's land polygons and obstacles, from the core or the venue file), `LandTerrain` (the drawn ground height and colours), `ColorMesh` (vertex-coloured mesh builder) |
| `shaders/` | Shaders. `sea_common`, `sky_common`, `wake_common` (`.gdshaderinc`) hold the water, sky and wake maths, written so the offline preview can compile them as GLSL too; `water_l/m/h` are the sea per quality tier, `sky`, `wake`, `wake_normal` |
| `scenes/` | Scenes. `sea/` is the sea (`sea.tscn`, `Sea`), its data source and wakes, and the daytime sky (`sky_day.tscn`, `SkyRig`, `env_day.tres`); `water_test.tscn` shows them together; `sail_test.tscn` is one boat sailing freely on the core (FakeSim as fallback), or racing alone on the example course, with cameras, controls and HUD on that sea and sky; `venue/` draws the venue land and obstacles (`VenueView`, `land.gdshader`); `course/` the course (`CourseView`, `CourseProps`) |
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
| `core` | the `CoreSim` itself for everything else: race, course, results, rules state, pairs, race, rules and contact events, sail events, perf tables by name, polar |

Records read every tick (`boat_state`, `boat_outputs`, `boat_controls`, `render_pose`, `sail`, `boat_env`) come from
`CoreSim` as `PackedFloat32Array` in the C structs' field order (`CoreSimSource.STATE_FIELDS` and the rest), the
others as Dictionaries with the C field names. `CoreSimSource` caches the per-boat records until the next step.

## Controls, cameras and HUD

- **Frame order** (`scenes/sail_test.gd`): `InputReader.read()` (devices through the input map into a `RawInput`),
  `PlayerControls.update()`, `SimRunner.advance()` (at each 50 ms boundary: `PlayerControls.stamp()` the input
  frame, `apply_input`, `step`, `Hud.tick`, the sail snapshot), the Sea's render time, `render_pose`, the boat node
  (`BoatView.apply`, `apply_sails` between the last two sail snapshots) and `SeaWakes.update_boat`,
  `CameraRig.frame()`, `Hud.frame()`; the Sea and SeaWakes nodes then draw the frame.
- **Simulation** (`sim_kind`): `AUTO` (the default) runs the core through `CoreSimSource` when the GDExtension is
  loaded and `FakeSim` otherwise; `CORE` and `FAKE` force one. On the core the scene is free sailing without a race
  (`create(venue)`, `add_entry`, `place_boat` at `start_x`, `start_y`, `start_twa_deg` off the wind) on
  `example_bay`, one `class_id` boat (`wm7`, or `wm12`), with the wind of `wind_speed_kn`, `wind_from_deg`,
  `puffs`, `shift_preset` and `world_seed`. The Sea's source is a `CoreEnvSource`, its clock the core's
  `render_time_ms`, the wakes `CoreSimSource.wake_state`, so the puffs drawn are the ones the boat sails in.
- **Boat** (`BoatView`): the node at the render pose (`conventions.md` §11), the rudder (with the tiller it
  carries) and the wheel from the helm `h`, the boom at the main's sail angle with the mainsheet sheared to follow
  it, and every sail placed rigidly as `sail_visuals.md` §7 does (main about the boom axis, headsails about the
  luff, spinnakers swung on the sprit tack line or the pole first), with the sail angles interpolated between the
  last two ticks. The shape is the flat generated sail (the §6 shapes and flutter are WM-016.09); hoisting and
  dropping (§8) scale it in its own frame: a headsail grows up its luff from the deck, a spinnaker climbs as a thin
  bundle and widens over the last tenth, drops run back; a sail that is `down` is hidden.
- **HUD commands**: the helm mark, the sheet bar and text, `AUTO` and `LET FLY` of the own boat come from the
  local `PlayerControls` every frame (`Hud.local_commands`), since the core applies a command at its next step.
- **Input map**: `scripts/controls/default_bindings.gd` is the one source of the defaults of `controls.md` §3.
  After changing it, rewrite the `[input]` section of `project.godot` (nothing else in the file is touched):
  `godot --headless --path game -s res://scripts/controls/write_input_map.gd`. Axis actions and device pairs carry
  suffixes (`helm_stick_left/right`, `sheet_in_trigger`, `camera_orbit_*`, `camera_look_*`,
  `camera_orbit_drag`); combos and context rules are resolved in code (see the file's header).
- **Steam Deck**: the default Steam Input template presents the gamepad bindings; its Deck-only items (L4 for
  `helm_fine`, right trackpad as `camera_orbit`, Steam + R1 for `screenshot`) belong in that template, which is
  not in the repo yet.
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

To sail the test scene yourself (opens a window): `game/native/build.sh` once (the core; without it the scene
runs on FakeSim), then `godot --path game res://scenes/sail_test.tscn` (after `--`: `--class=wm12` for the
12 m boat, `--fake` for FakeSim, `--race` to race alone on `example_bay/example_wl` through the start sequence,
`--course=<venue>/<id>` for another course). Keys: ←/→ or
A/D helm (set and hold, ↓ centres), T auto-trim, W/S sheet, Space let fly, 1/2 sails, C camera, F5 to F8 camera
modes, right mouse drag or IJKL orbit, wheel or O/U zoom, R recentre, Backspace reset (free sailing: back to the
start point; race mode: restart the race), Esc pause, F10 hide HUD.

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
  a bouncing marker with its name and distance beyond 500 m. A line of race status text at the top (countdown,
  flags, OCS, next mark, lap) stands in for the race HUD (WM-016.11).
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
  but the sails and the mainsheet carries baked ambient occlusion in `COLOR_0`, which Godot applies through
  `vertex_color_use_as_albedo`. boatgen's uv1 (liveries) arrives as Godot's `UV2`, which `StandardMaterial3D`
  does not use for albedo, so liveries will need a shader or material override.
- Default import settings generate LODs and shadow meshes and compress vertices. For sails deformed at run
  time these should be turned off for the sail meshes (or the sails rebuilt as `ArrayMesh` at load).

## Sea, sky and lighting

`scenes/sea/sea.tscn` (`Sea`) draws the water of `docs/specs/water_render.md`: a camera-centred radial grid whose
vertex shader evaluates the core's `sea_height` from the wave components, with detail normals, puffs and lulls,
whitecaps, wakes (`SeaWakes`) and water overlays, in three quality tiers (`SeaQuality`: L, M, H). It reads:

- a source with `sea_components()`, `sea_exposure()` and `wind_state(t_ms)`. `SeaEnvSource` is the placeholder
  until the core binding exists: `PLACEHOLDER` builds a sea and puffs with the spec formulas and Godot's random
  numbers, `CORE_SAMPLES` reads the core's own components, exposure and puff patches from
  `generated/sea/sea_render_samples.json`;
- `render_time_ms`, the environment clock of the frame (advanced by the node itself unless `use_internal_clock`
  is off);
- a `SkyRig` for the sky colours and the sun, and the camera it follows.

Boats get wakes through `SeaWakes.update_boat(id, state)` with the interpolated pose and the class dimensions.
`Sea.height_at(x, y)` is a CPU mirror of the core's sea height (double precision) for anything that needs the
surface before the binding exists.

`scenes/sea/sky_day.tscn` (`SkyRig`) is the daytime preset: the sky shader, the sun light, fog toward the
horizon colour and sky reflections, set from one group of parameters.

### Water tests

```
game/tests/run_water_test.sh            # core samples, import, checks
game/tests/run_water_test.sh --preview  # also the offline previews
```

The script builds `core/tools/gen_sea_render_samples.cpp`, writes the core's samples, imports the project (fails
on any error or warning) and runs `tests/water_test.gd`: every shader parses; the drawn height matches the core's
`sea_height` within 1 mm (a double-precision mirror and a float32 emulation of the shader path, points up to
8 km, times up to 4 h); slope, puff factor and exposure match; the far-field fade table; the wake geometry; and
the test scene on every tier.

### Offline previews

Godot's headless mode has no renderer, so the previews run in two steps without a window:
`tests/water_preview_dump.gd` runs the test scene headless and writes every uniform, mesh and texture the water,
wake and sky shaders get, then `tests/water_preview.py` renders them on an offscreen OpenGL context with the
same shared shader functions (the lighting around them is a stand-in for Godot's). `--publish` also writes the
JPEGs committed in `tests/previews/`.

The engine's own picture needs a short windowed run (it opens a window for about 7 seconds):

```
godot --path game res://scenes/water_test.tscn -- --capture=/tmp/windmark_water --tier=M
```

It writes `water_<camera>_<tier>.png` for the chase, aerial, overview and sun cameras and quits.
