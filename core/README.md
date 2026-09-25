# Windmark core

The deterministic simulation core: boats, sails, wind, wind shadow, sea, collisions, race, rules and AI on a fixed
50 ms tick. C++20, no engine dependency. The server and every client run the same core, so the same inputs give
the same bits on every platform. Behaviour is defined by the specs in `docs/specs/`; `conventions.md` sets the
frames, units, tick, float rules, math functions, random numbers and table lookups that everything here follows.

## Build and test

Requirements: CMake 3.20 or newer, Ninja, Clang or GCC with C++20 (MSVC 2022 flags are set but not yet tested).

```sh
cmake -S core -B core/build -G Ninja          # Release by default; -DCMAKE_BUILD_TYPE=Debug for asserts
cmake --build core/build
ctest --test-dir core/build --output-on-failure
```

Options:

| option | default | meaning |
| --- | --- | --- |
| `WINDMARK_BUILD_TESTS` | `ON` | build the test suite |
| `WINDMARK_WERROR` | `OFF` | warnings are errors |
| `WINDMARK_BUILD_CAPI` | `ON` | build the C API (`libwindmark` shared, `windmark_static`) and its example |
| `WINDMARK_DATA_DIR` | `<repo>/data` | where the tests find `classes/`, `perf/` and `venues/` |
| `WINDMARK_COURSES_DIR` | `<repo>/game/data/courses` | where the tests find the course files |

Tests (`ctest`):

- `core_tests`: the doctest suite in `tests/` (check values of `conventions.md`, the math vector file, tables,
  checksums, JSON, loading and validating `data/perf/wm7.perf.json` and `wm12.perf.json` against their class
  files, and loading `data/venues/example_bay.venue.json` into the environment; the course files, the race flow
  and the racing rules scenarios of `courses.md` §7, `race.md` §12 and `rules.md` §13; the world loop; and a full
  headless race of six scripted boats with penalties on `example_bay`, run twice for determinism).
- `core_no_fma`: disassembles `libwindmark_core.a` and fails on any fused multiply-add instruction.
- `capi_race_example`: `examples/race_example.c` through the C API only: a race of four scripted boats on the
  example course from the spawn to the results, run twice for the same checksum, then a free-sailing boat
  (render pose, input frame encoding, sail requests, trim_speed lookup).

## Float rules

`cmake/WindmarkFloatRules.cmake` defines the interface target `windmark_float_rules`, which `windmark_core`
links publicly, so anything that links the core compiles under the same rules (`conventions.md` §5):

- `-ffp-contract=off`: no fused multiply-add (ARM64 compilers fuse by default);
- no fast-math: `-fno-fast-math -fno-unsafe-math-optimizations -fno-associative-math -fno-reciprocal-math
  -fno-finite-math-only -fsigned-zeros`;
- 32-bit x86 uses SSE2 (`-mfpmath=sse -msse2`), never x87; MSVC uses `/fp:precise`;
- configuring with `-ffast-math`, `-Ofast`, `-funsafe-math-optimizations` or an FP contraction flag in
  `CMAKE_CXX_FLAGS` is a configure error.

Checks: `tests/test_float_rules.cpp` evaluates `a*b + c` on inputs where the fused and the separately rounded
results differ (in the library and in the test itself), and checks that the FP environment rounds to nearest and
keeps denormals. `WM_DEBUG_CHECK_FP_ENV()` does the environment check at the start of a tick in debug builds.

The math vector file `tests/vectors/math_vectors.txt` holds inputs and results of every math function and the
RNG as bit patterns. It is written by `windmark_gen_vectors`; regenerate it only on purpose, and check the new
file on a second architecture before committing it (on an Apple Silicon Mac: configure a second build with
`-DCMAKE_OSX_ARCHITECTURES=x86_64` and run its tests under Rosetta).

## Layout

Sources live in `src/<module>/`, included as `"module/header.h"`, all in namespace `wm`.

| path | role | spec |
| --- | --- | --- |
| `src/base/` | FP environment check, contraction probe | conventions.md §5 |
| `src/math/` | `wm_math`: constants, clamp/lerp/sgn, `wm_sincos`, `wm_atan2`, `wm_asin`, `wm_exp`, angle helpers; `rng`: counter-based RNG and its stream numbers | conventions.md §5, §6, §7 |
| `src/table/` | axis bracket, Table1D/2D/3D interpolation, axis quantities and units | conventions.md §8, data_format.md §5 |
| `src/state/` | snapshot writer and reader, FNV-1a 64 tick checksum, SHA-256 for data identity | conventions.md §9, data_format.md §4.1 |
| `src/wind/` | `grid`: the venue grid sampler; `wind`: base wind, shift walk, trend, oscillation, puffs and lulls, venue wind field, current | wind.md |
| `src/sea/` | wave components, per-tick phases, height, slope, exposure, the wind-sea growth law | sea.md |
| `src/shadow/` | shadow snapshot sources, blanket and backwind losses, the strongest-source rule, zone outlines, the environment at a boat | wind_shadow.md |
| `src/boat/` | `boat_env`: the environment a boat step reads (`BoatEnv`, `SeaSurface`); `hull_sampling`: hull points, mean height and wave pitch and roll; `boat`: state, controls, the tick, snapshot save and load, AI lookups | boat.md, sea.md §5 |
| `src/sails/` | inventory, the sail-change queue (peels, cancels, timing, slowdown), trim, sail motion, trim error and luff outputs | sails.md |
| `src/data/` | strict JSON reader with correctly rounded binary32 numbers, load errors with JSON paths, the `windmark.perf/1` loader and validator, the `windmark.boatclass/1` header reader and the perf-to-class check; `venue`: the `windmark.venue/1` loader and validator | data_format.md |
| `src/collide/` | `collide`: shape tests (separating axes, circle, land with its band index), the static `CollisionScene`, the tick-6 step `Collisions::step` (detection, response, contact events) and the contact pair set | collisions.md |
| `src/course/` | `geometry`: plane helpers of `race.md` §0, placed hull outlines, convex gaps; `course`: the `windmark.course/1` loader, sequence expansion with laps, laying a course to the wind, the scale factor, the resolved course and its hash, the geometry checks | courses.md |
| `src/race/` | the race flow: states, signals, prep flags, OCS and recalls, starting, the winding test for marks and gates, finishing, closing, ranking, results; spawn grid and order | race.md |
| `src/rules/` | the racing rules engine: tack and tacking, relations, right of way, the keep-clear, escape and mark-room tests, rules 14 to 19, 22, 31 and boundaries, incidents, penalties, penalty turns, deadlines and disqualification | rules.md |
| `src/world/` | `World`: one tick in the order of `conventions.md` §4.1 over the boats, wind, sea, shadows, collisions, race and rules; creating a race, controls, events, the tick checksum | conventions.md §4.1, race.md §1 |
| `include/windmark.h`, `src/capi/` | the C API over the world (below) | networking.md §4 |
| `examples/` | `race_example.c`: a headless race and a free-sailing boat through the C API only | |
| `tests/` | doctest suite and the math vector file | |
| `tools/` | `gen_math_vectors.cpp`, `gen_env_vectors.cpp`; `gen_sea_render_samples.cpp` (sea and puff samples for the front end's water checks, `game/tests/run_water_test.sh`) | |
| `third_party/doctest/` | doctest 2.4.12 (MIT), test framework | |

Planned modules, one directory each under `src/`, in the tick order of `conventions.md` §4.1:

| path | role | spec |
| --- | --- | --- |
| `src/ai/` | AI helms | ai.md |

## World calls

The world is what the C API and the front end wrap. It is created when the race environment starts (its tick 0
is the environment clock's zero, `race.md` §0).

| call | does | spec |
| --- | --- | --- |
| `World(WorldSetup)` | venue, seed, wind and sea settings (the venue's fields applied, the wind sea grown from the venue fetch), race settings, rules parameters | race.md §2 |
| `add_boat(BoatEntry)` | an entry (class, human or AI, performance scale, auto trim, start sail); after `create_race` a joiner placed in the first free slot, until the prep signal | race.md §3.5 |
| `place_boat(i, p, psi)` | free sailing: places a boat (60 % of its polar speed, sails up and trimmed); only before `create_race`. A world that never creates a race steps boats, wind, sea, shadows and collisions without race or rules | race.md §3.5 |
| `create_race(CourseData, err)` | lays the course to the median wind at the gun and scales it, checks it on the venue, builds the collision scene, creates the race and the rules, spawns the boats | courses.md §6, §7; race.md §3.1 |
| `set_helm`, `set_sheet`, `set_auto_trim`, `set_let_fly`, `hoist`, `drop_front`, `retire`, `protest` | controls queued for step 2 of the next tick | boat.md §2, race.md §6.4, rules.md §10 |
| `set_controller(fn)` | called in step 2 before the queued controls: computer skippers and scripts decide there | ai.md |
| `step()` | one tick: race and rules on `t_n` and the last contacts, controls, environment, shadow snapshot, boat steps, collisions, publish; returns the tick checksum | conventions.md §4.1 |
| `boat(i)`, `env(i)`, `race()`, `rules()`, `course()`, `scene()`, `events()`, `checksum()` | state, the race and rules records, this tick's race, rules and contact events | race.md §11, rules.md §11 |

`Race` and `Rules` can also be driven directly with poses (`RaceBoatInput`, `RulesBoatInput`), which is how the
scenario tests script tracks without physics.

## C API

`include/windmark.h` is the stable C interface over the world, for the server and the engine bindings
(`game/native`): opaque handles (`wm_perf`, `wm_venue`, `wm_course`, `wm_world`), plain structs of fixed-width
types, `wm_status` codes with `wm_last_error()`, and `WM_API_VERSION` / `wm_api_version()` bumped on any struct or
signature change. `libwindmark` (shared) exports only the `wm_*` functions; `windmark_static` is the same for
hosts that link it in. Everything is built under the float rules; hosts must not enable flush-to-zero.

| group | calls |
| --- | --- |
| data | `wm_perf_load/parse`, `wm_venue_load/parse`, `wm_course_load/parse`; `wm_perf_info`, `wm_perf_sail`, `wm_perf_polar`, `wm_perf_polar_vmg`, `wm_perf_trim_speed` |
| set-up | `wm_world_settings_init`, `wm_world_create(settings, venue or NULL)`, `wm_world_add_boat`, `wm_world_place_boat` (free sailing), `wm_world_create_race` |
| controls | `wm_world_apply_input` (the input frame of networking.md §4.1; the sail request result is answered at once), `wm_input_encode/decode` (the 6-byte wire form), single controls, `wm_world_set_controller` (step-2 callback) |
| step | `wm_world_step` (returns the tick checksum), `wm_world_checksum`, `wm_world_tick`, `wm_world_time_ms`, `wm_world_render_time_ms` |
| boats | state, controls, outputs, the environment at the boat, `wm_world_render_pose(alpha)` (interpolated between the last two ticks), `wm_world_trim_speed_at` (HUD trim tolerance), sails, per-sail state and outputs, sail phase events |
| environment | clean wind, global direction, current, puff patches (now or at any `t_ms`), `wm_world_wind_state`, sea height (now or at any `t_ms`), slope, exposure and its grid, wave components |
| race and rules | course marks, steps and boundary; race state, per-boat race state, order, results; per-boat rules state, pending penalties, pair records; race, rules and contact events of the last tick |

A world holds references to the data it was given, so callers may free their handles after passing them. The
world's tick 0 is the environment clock's zero. Point queries use a second wind field with the same seed and
settings (identical bits) and cached sea ticks, so they never touch the world's own caches.

## Boat calls

| call | does | spec |
| --- | --- | --- |
| `Boat::init(perf, race_seed, index)` | binds the class; the seed and index give the wobble phase | boat.md §6.5 |
| `Boat::reset(x, y, psi, v, front_sail, auto_trim, env)` | placement: sails up and trimmed, wind triangle, filters | boat.md §6.6 |
| `set_helm`, `set_sheet`, `set_auto_trim`, `set_let_fly`, `set_performance_scale` | controls, clamped, NaN is neutral | boat.md §2, §8 |
| `hoist(sail)`, `drop_front()` | sail requests, `accepted` or `rejected` | sails.md §4.2 |
| `Boat::step(BoatEnv)` | tick step 5 for one boat; `BoatEnv` maps one to one onto `EnvAtBoat`, `sea = &sea_tick` | boat.md §5 |
| `state()`, `outputs()`, `sails()` | state, derived outputs (target and polar speed, vmg, sog, cog), per-sail outputs and phase events | boat.md §3, §9; sails.md §7 |
| `save(w)`, `load(r)` | the snapshot of boat.md §3 then sails.md §3 | conventions.md §9 |

## Environment queries

Wind, current and sea are pure functions of `(race_seed, t_env_ms, position)`; the shadows add the tick's boat
snapshot. Settings structs carry the spec defaults; `check_wind_settings` / `check_sea_settings` validate them
(venue grids are passed as pointers the caller keeps alive).

| call | returns | spec |
| --- | --- | --- |
| `WindField(seed, WindSettings)`, `apply_shift_preset` | the wind of a race | wind.md §1 |
| `WindField::advance(t)` | tick step 3: the `WindTick` at `t` (shift terms, `global_from`, every puff slot), cached | wind.md §2 |
| `WindField::at(t)` | the same `WindTick` from scratch (identical bits; any time) | wind.md §4.3 |
| `wind_clean(tick, x, y)` | clean wind speed and direction at a point | wind.md §2 |
| `puff_factor(tick, x, y)`, `puff_patches(tick)` | puff/lull factor; live patches `(px, py, R, s, e)` for drawing (repeat every `puff_tile`) | wind.md §6 |
| `shift(t)`, `trend(t)`, `osc(t)`, `dir_offset(t)`, `global_from(t)`, `segment(k)` | direction terms, the shift walk | wind.md §3–§5 |
| `current(x, y, t)` | current vector, m/s east/north | wind.md §7 |
| `SeaField(seed, SeaSettings)`, `components()` | the wave components `(a, kx, ky, c, T)` for renderers | sea.md §3, §7.1 |
| `SeaField::at(t)` → `SeaTick` | tick step 3: the surface at `t`; `sea_height(x, y)`, `sea_slope(x, y)` | sea.md §4 |
| `wind_sea_from_wind(U, F, from)` | server side: wind-sea `Hs`, `Tp` from base wind and fetch | sea.md §2 |
| `make_shadow_class(WindShadowParams)`, `ShadowSource` | per-class constants; one boat of the tick-4 snapshot | wind_shadow.md §2, §3 |
| `shadow(B, x, y)` | loss and header from one source | wind_shadow.md §4 |
| `shadowed_wind(snapshot, self, x, y, U, from)` | the wind at a point after the strongest other boat's shadow | wind_shadow.md §5 |
| `env_at_boat(wind, tick, snapshot, self, x, y)` | tick step 5: shadowed and clean wind plus current at a boat | wind_shadow.md §5, wind.md §7 |
| `shadow_zones(B)` | blanket and backwind outlines for drawing | wind_shadow.md §7 |
| `load_venue(file, VenueData, err)` | the venue physics file: wind field, current, exposure, land, obstacles, file hash | data_format.md §6 |
| `apply_venue(venue, WindSettings, SeaSettings)` | points the settings at the venue's grids (the venue must outlive the fields) | data_format.md §6 |

The boat step reads the sea through `SeaTick::sea_height` (it samples the hull points itself, `sea.md` §5);
`SeaTick` implements the boat's `SeaSurface` interface. The renderer takes `components()`
and the exposure grid and evaluates `sea.md` §7.2 in double precision per frame.

The env vector file is written by `windmark_gen_env_vectors` from the fixed scenarios in
`tests/env_scenarios.h`; like the math vectors, regenerate it only on purpose and check it on a second
architecture.

## Rules for core code

- Every simulation value is `float` and every formula is written as the spec writes it: one rounding per
  operation, in the written order, parentheses binding. Transcendentals come from `math/wm_math.h`, never from
  `<cmath>` (only `sqrt`, `fabs`, `floor`, `ceil`, `nearbyint`, `ldexp`, `fmin`, `fmax`, which are exact).
- Random draws come from `math/rng.h` with a stream from `RngStream`; a new use gets a new stream number in
  `conventions.md` §7 first.
- Data is loaded and validated once; a loader returns false with a `LoadError` (file, JSON path, reason) and
  leaves nothing partly loaded.
- No wall clocks, hash-map iteration, uninitialised memory or addresses inside a tick.
- Headers in `src/` are internal: code that includes them must build under `windmark_float_rules`, which it gets
  by linking `windmark_core`.
