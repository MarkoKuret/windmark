# Windmark front end (Godot)

Godot 4.6, Forward+ renderer. So far: the boat import test, the sea, sky and lighting (`docs/specs/water_render.md`),
a placeholder simulation behind the interface the core binding will fill, the controls, the cameras, the minimal
HUD and a sail test scene that puts them together.

## Layout

| Path | Role |
| --- | --- |
| `project.godot` | Project settings |
| `scripts/` | GDScript. `sail_grid.gd` (`SailGrid`) maps imported sail vertices back to the boatgen sail grid; `frames.gd` (`Frames`) holds the axes and angle helpers; `boat_view.gd` places the generated boat |
| `scripts/sim/` | `SimSource` (the simulation interface), `FakeSim` and `FakeBoat` (placeholder), `SimRunner` (50 ms ticks), class loading |
| `scripts/controls/` | Input map defaults, device reader, `PlayerControls` (boat commands), sail key mapping, the input frame |
| `scripts/cameras/` | `CameraRig` and the chase, onboard, aerial and free cameras, shake, onboard eye point |
| `scripts/hud/` | `Hud`, `HudValues`, formats, bars and trim gauges |
| `shaders/` | Shaders. `sea_common`, `sky_common`, `wake_common` (`.gdshaderinc`) hold the water, sky and wake maths, written so the offline preview can compile them as GLSL too; `water_l/m/h` are the sea per quality tier, `sky`, `wake`, `wake_normal` |
| `scenes/` | Scenes. `sea/` is the sea (`sea.tscn`, `Sea`), its data source and wakes, and the daytime sky (`sky_day.tscn`, `SkyRig`, `env_day.tres`); `water_test.tscn` shows them together; `sail_test.tscn` is one boat with the fake sim, cameras, controls and HUD |
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

Cameras, controls and HUD read the simulation only through `scripts/sim/sim_source.gd`. `FakeSim` implements it
now; the core binding (WM-016.01) will be a second implementation (a `SimSource` subclass wrapping the
GDExtension), and nothing else changes. Names and units are the core's (`boat.md` §3, `sails.md` §3 and §7):
world ENU metres, radians, compass angles clockwise from north, one tick = `DT` = 0.05 s.

| Call | Returns |
| --- | --- |
| `tick()` | ticks stepped so far |
| `boat_count()` | number of boats |
| `class_info(b)` | `ClassInfo`: id, name, `loa`, `beam_max`, steering, sails (`SailInfo`: name, type, `sheet_min`, `sheet_max`) in sail order, `main_sail`, `front_sails` (sail slots), the boatgen physics sidecar |
| `state(b)` | `BoatState`: every field of `wm::BoatState` |
| `controls(b)` | `BoatControls`: `h_cmd`, `sheet_cmd`, `auto_trim`, `let_fly`, `performance_scale` |
| `outputs(b)` | `BoatOutputs`: every field of `wm::BoatOutputs` |
| `sails(b)` | `SailsView`: `front`, the change queue (`SailStep` sail, phase, reversed), `queue_len`, `queue_pos`, `queue_progress`, per sail `SailState` (phase, progress, beta, pole) and `SailOutput` (`k_h`, `m_opt`, `beta_opt`, `beta_t`, `trim_error`, `luff_shiver`, motion, backed) |
| `render_pose(b, alpha)` | `RenderPose` between the last two ticks: position, `z`, `psi`, `theta`, `phi`, `h`, `twa`, `twd_from` |
| `wind_clean(x, y)` | clean wind at a point: `Vector2(speed, from)` |
| `sea_height(x, y)` | sea surface height at a point (the one sea hook; flat in `FakeSim`) |
| `trim_speed_at(b, tws, awa_abs, eps)` | the config's `trim_speed` table (HUD trim tolerance), `NAN` without one |
| `apply_input(b, frame)` | applies an `InputFrame` (`networking.md` §4.1); returns the sail request result |
| `step()` | one tick |

`FakeSim` is a GDScript sketch of `boat.md` §5 and `sails.md` §4 to §5 on the class's generated tables (polar,
heel, accel, trim and optimal-angle tables, sail change timing), with a uniform wind (optional slow direction
oscillation), flat water or a test swell, and no waves on the hull, collisions or wind shadow. It is not the
reference and not deterministic across platforms.

## Controls, cameras and HUD

- **Frame order** (`scenes/sail_test.gd`): `InputReader.read()` (devices through the input map into a `RawInput`),
  `PlayerControls.update()`, `SimRunner.advance()` (at each 50 ms boundary: `PlayerControls.stamp()` the input
  frame, `apply_input`, `step`, `Hud.tick`), `render_pose`, the boat node, `CameraRig.frame()`, `Hud.frame()`.
- **Input map**: `scripts/controls/default_bindings.gd` is the one source of the defaults of `controls.md` §3.
  After changing it, rewrite the `[input]` section of `project.godot` (nothing else in the file is touched):
  `godot --headless --path game -s res://scripts/controls/write_input_map.gd`. Axis actions and device pairs carry
  suffixes (`helm_stick_left/right`, `sheet_in_trigger`, `camera_orbit_*`, `camera_look_*`,
  `camera_orbit_drag`); combos and context rules are resolved in code (see the file's header).
- **Steam Deck**: the default Steam Input template presents the gamepad bindings; its Deck-only items (L4 for
  `helm_fine`, right trackpad as `camera_orbit`, Steam + R1 for `screenshot`) belong in that template, which is
  not in the repo yet.
- **Sea**: the cameras keep clear of the water through `CamTypes.Target.sea_height`, a function
  `(x east, y north) -> height`. The scene sets it to `sim.sea_height`; the Sea node (`scenes/sea/`) will provide
  the same function evaluated as `sea.md` §7.2. The scene's `SeaPlaceholder` plane stands in for the Sea node.
- **Options** not wired to a settings screen yet: `PlayerControls` (helm key mode, dead zone and curve, sheet rate,
  hold or toggle, sheet turns auto-trim off), `CameraRig.options` (speed, invert, reduced motion, smooth switch,
  auto-recentre), `Hud.assist` (Full, Standard, Minimal). Not implemented yet: mouse helm, one-hand layout,
  rebinding UI, vibration, land avoidance of the cameras (no venue land yet), the aerial next-mark framing (no
  marks yet).

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
  assist presets on a scripted boat state; then `scenes/sail_test.tscn` sails 20 s with scripted input and the HUD
  text is checked against the sim's values.

To sail the test scene yourself (opens a window): `godot --path game res://scenes/sail_test.tscn`. Keys: ←/→ or
A/D helm (set and hold, ↓ centres), T auto-trim, W/S sheet, Space let fly, 1/2 sails, C camera, F5 to F8 camera
modes, right mouse drag or IJKL orbit, wheel or O/U zoom, R recentre, Esc pause, F10 hide HUD.

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
