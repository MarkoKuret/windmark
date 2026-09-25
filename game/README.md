# Windmark front end (Godot)

Godot 4.6, Forward+ renderer. So far: a headless import test of the boat models made by `tools/boatgen`, and
the sea, sky and lighting (`docs/specs/water_render.md`).

## Layout

| Path | Role |
| --- | --- |
| `project.godot` | Project settings |
| `scripts/` | GDScript. `sail_grid.gd` (`SailGrid`) maps imported sail vertices back to the boatgen sail grid |
| `shaders/` | Shaders. `sea_common`, `sky_common`, `wake_common` (`.gdshaderinc`) hold the water, sky and wake maths, written so the offline preview can compile them as GLSL too; `water_l/m/h` are the sea per quality tier, `sky`, `wake`, `wake_normal` |
| `scenes/` | Scenes. `sea/` is the sea (`sea.tscn`, `Sea`), its data source and wakes, and the daytime sky (`sky_day.tscn`, `SkyRig`, `env_day.tres`); `water_test.tscn` shows them together |
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

## Notes on the imported boats

- Godot wraps each GLB in its own root node named after the file. The boat's root node (named after the class
  id, with `extras` metadata `class` and `name`) is its only child, and the parts are children of that.
- The glTF importer re-indexes every mesh: vertices come out in the order the triangles first use them, and
  unreferenced vertices are dropped. The sidecar's row-major sail order therefore holds in the GLB file but
  not in Godot. `SailGrid.grid_index(mesh, rows, cols)` rebuilds the grid index from uv1 and the layer side;
  call it once on the flat sail as imported.
- Materials come in as `StandardMaterial3D` with the boatgen PBR factors (base colours are converted from linear
  to sRGB). boatgen's uv1 (liveries) arrives as Godot's `UV2`, which `StandardMaterial3D` does not use for
  albedo, so liveries will need a shader or material override.
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
