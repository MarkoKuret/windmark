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
| `WINDMARK_DATA_DIR` | `<repo>/data` | where the tests find `classes/` and `perf/` |

Tests (`ctest`):

- `core_tests`: the doctest suite in `tests/` (check values of `conventions.md`, the math vector file, tables,
  checksums, JSON, and loading and validating `data/perf/wm7.perf.json` and `wm12.perf.json` against their class
  files).
- `core_no_fma`: disassembles `libwindmark_core.a` and fails on any fused multiply-add instruction.

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
| `src/data/` | strict JSON reader with correctly rounded binary32 numbers, load errors with JSON paths, the `windmark.perf/1` loader and validator, the `windmark.boatclass/1` header reader and the perf-to-class check | data_format.md |
| `tests/` | doctest suite and the math vector file | |
| `tools/` | `gen_math_vectors.cpp`, `gen_env_vectors.cpp` | |
| `third_party/doctest/` | doctest 2.4.12 (MIT), test framework | |

Planned modules, one directory each under `src/`, in the tick order of `conventions.md` §4.1:

| path | role | spec |
| --- | --- | --- |
| `src/boat/` | boat state and step | boat.md |
| `src/sails/` | inventory, sail changes, trim | sails.md |
| `src/collisions/` | detection, response, contact events | collisions.md |
| `src/race/` | race state machine, course and marks | race.md, courses.md |
| `src/rules/` | racing rules and penalties | rules.md |
| `src/ai/` | AI helms | ai.md |
| `src/capi/`, `include/windmark.h` | the C API for the server and engine bindings | networking.md |

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

The boat step reads the sea through `SeaTick::sea_height` (it samples the hull points itself, `sea.md` §5); when
`boat/boat_env.h` is present `SeaTick` implements its `SeaSurface` interface. The renderer takes `components()`
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
