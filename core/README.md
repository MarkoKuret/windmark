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
| `src/data/` | strict JSON reader with correctly rounded binary32 numbers, load errors with JSON paths, the `windmark.perf/1` loader and validator, the `windmark.boatclass/1` header reader and the perf-to-class check | data_format.md |
| `tests/` | doctest suite and the math vector file | |
| `tools/` | `gen_math_vectors.cpp` | |
| `third_party/doctest/` | doctest 2.4.12 (MIT), test framework | |

Planned modules, one directory each under `src/`, in the tick order of `conventions.md` §4.1:

| path | role | spec |
| --- | --- | --- |
| `src/wind/` | wind field: base, shifts, oscillation, puffs, venue field, current | wind.md |
| `src/sea/` | wave components, heights, hull sampling | sea.md |
| `src/shadow/` | wind-shadow snapshot and losses | wind_shadow.md |
| `src/boat/` | boat state and step | boat.md |
| `src/sails/` | inventory, sail changes, trim | sails.md |
| `src/collisions/` | detection, response, contact events | collisions.md |
| `src/race/` | race state machine, course and marks | race.md, courses.md |
| `src/rules/` | racing rules and penalties | rules.md |
| `src/ai/` | AI helms | ai.md |
| `src/capi/`, `include/windmark.h` | the C API for the server and engine bindings | networking.md |

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
