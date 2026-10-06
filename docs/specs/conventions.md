# Conventions: frames, units, time, determinism

Shared ground rules for every simulation spec in `docs/specs/` (`boat.md`, `sails.md`, `wind.md`,
`wind_shadow.md`, `sea.md`, `collisions.md`, `data_format.md`, and the race, rules, AI and networking specs).
Where a spec gives a formula, it is evaluated with the rules here: the frames and signs of §1–§3, the tick of §4,
the arithmetic of §5, the math functions of §6, the random numbers of §7 and the table lookups of §8. §11 maps the
frames into the front end's Godot scene.

The core is authoritative: the server and every client run the same core, so the same inputs must give the same
bits on every platform. That requirement drives most of this document.

## 1. Units

- SI inside the core: metres, seconds, kilograms, radians, m/s, m/s², rad/s.
- Knots and degrees appear only at the edges: HUD display, logs, printed tables, human-facing tools.
  Data files the core loads are SI (see `data_format.md`).
- Conversion constants (used only at the edges):

  | name | value | float32 |
  | --- | --- | --- |
  | `KNOT` | 1852/3600 m/s | `0.514444470f` (0x3F03B2A2) |
  | `DEG` | π/180 rad | `0.0174532924f` (0x3C8EFA35) |

- Gravity `G = 9.81f` m/s² (used by the sea, `sea.md`).

## 2. World frame

- Right-handed **ENU**: `x` east, `y` north, `z` up, metres. The origin is the venue origin
  (`data_format.md` §6); venues keep all racing within ±8 km of it so float positions keep ≤ 1 mm resolution.
- Positions in the simulation are 2-D `(x, y)` on the water plane plus a separate heave `z` for the hull.
- **Compass angle** `ψ`: radians, 0 = north (+y), increasing **clockwise** seen from above (east = π/2).
  Stored wrapped to `[0, 2π)`.
- Unit vector of a compass angle: `dir(ψ) = (sin ψ, cos ψ)` (east, north).
- Compass angle of a vector `v = (vx, vy)`: `compass(v) = wrap_2pi(atan2(vx, vy))` (note the argument order:
  east first). For `|v|` below `1e-6` the caller keeps its previous angle (each spec says which one).
- Directions of flows are named by what they mean:
  - wind: `*_from`, the meteorological direction the wind **comes from**;
  - waves: `*_from` as for wind (a wave train from the north travels south);
  - current: `*_to`, the direction the water **flows toward**.
  A flow of speed `s` from compass `ψ_from` has the velocity vector `−s·dir(ψ_from)`; a current of speed `s`
  toward `ψ_to` has `+s·dir(ψ_to)`.

## 3. Boat frame and signed angles

- **Body frame**: `x` forward (bow), `y` to **port**, `z` up (right-handed). Origin: on the centreline, in the
  design waterline plane, at the midpoint of the waterline length (the "hull reference point", `data_format.md`
  §2). Class-file positions are in this frame.
- **Heading** `ψ`: compass angle of the body `x` axis.
- **Heel** `φ`: roll about body `x`, **positive = starboard side down** (right-handed about the bow axis). A boat
  on starboard tack heels to port, so its heel is negative.
- **Pitch** `θ`: **positive = bow up**.
- **Attitude matrix** (body → world), for renderers and collision geometry that needs 3-D:
  `R = Rz(π/2 − ψ) · Ry(−θ) · Rx(φ)`, with `Rz, Ry, Rx` the right-handed rotations about world/body z, y, x.
  The simulation itself stores the scalars `ψ, θ, φ, z`, never a matrix.
- **Helm** `h ∈ [−1, 1]` (normalised) and rudder angle `δ = h·δ_max`: **positive turns the bow to starboard**
  (heading increases). Every turning rate in the specs is a **heading rate** `dψ/dt`, positive clockwise.
- **Wind angles** `TWA`, `AWA` ∈ `[−π, π)`: angle from the bow to the wind's *from* direction,
  `wrap_pi(wind_from − ψ)`. **Positive = wind from starboard.**
- **Tack sign** `tack = sgn(TWA)`: +1 = starboard tack (wind over the starboard side), −1 = port tack.
- **Sail angle** `β` ∈ `[−π, π)`: angle of the boom (or the sail's chord line from its tack) measured from the
  boat's **aft** centreline, **positive = sail on the starboard side**. A drawing sail sits to leeward, so
  normally `sgn(β) = −sgn(AWA)`. `|β| = π` means the sail points forward along the bow.
- `sgn(x)` is `+1` for `x ≥ 0` (including `+0` and `−0`) and `−1` for `x < 0`. It never returns 0.

## 4. Time and the tick

- The simulation advances in fixed ticks of **50 ms**. `DT = 0.05f` (0x3D4CCCCD) in every formula.
- Simulation time is the **integer tick index** `n` (uint32, wraps after 6.8 years) and the integer time
  `t_ms = 50·n` (uint32 milliseconds; races and rooms reset it long before it wraps at 49.7 days).
  Formulas needing seconds convert once: `t_s = (float)t_ms * 0.001f`, and periodic phases are computed from
  integers (`t_ms mod period_ms`) so they never lose precision.
- A tick integrates the state from `t_n` to `t_{n+1}` using the environment evaluated at `t_n`.
- The environment clock (wind shifts, puffs, waves, current) counts from the moment the race environment starts
  (`t_env_ms = t_ms − t_env0_ms`, set by the race layer, `race.md`). Everything seeded is a pure function of
  `(seed, t_env_ms)`.

### 4.1 Order within one tick

This is the physics order. `race.md`, `rules.md`, `ai.md` and `networking.md` define what happens inside their
steps; the order of the steps is fixed here.

| step | what | spec |
| --- | --- | --- |
| 1 | Race and rules update on the state at `t_n` (race state machine, penalties, the contact events of the previous tick) | race.md, rules.md |
| 2 | Controls: player commands stamped for tick `n` are applied; AI helms decide and write their controls | networking.md, ai.md |
| 3 | Environment at `t_n`: wind field (base, shifts, oscillation, puffs), current, sea phases | wind.md, sea.md |
| 4 | Shadow snapshot: each boat's wind-shadow source is frozen from its state at `t_n` | wind_shadow.md |
| 5 | For each boat in index order: wind at the boat (field, then the other boats' shadows from the snapshot), then the boat step | boat.md, sails.md |
| 6 | Collisions on the new positions: detection, response, contact events | collisions.md |
| 7 | Outputs: snapshots for rendering and networking (the state checksum is taken on request, §9) | networking.md |

Boats in step 5 depend only on the environment and the step-4 snapshot, never on another boat's new state, so
the result does not depend on the boat order. Step 6 is the only place boats interact directly, and it uses a
fixed pair order.

## 5. Arithmetic rules (determinism)

1. **IEEE-754 binary32** (`float`) for every simulation value unless a spec says otherwise. Integers are
   fixed-width (`uint32`, `int32`, `uint64`) with wrap-around semantics for unsigned types.
2. **Round to nearest, ties to even**, the default mode. Nothing in the core changes the rounding mode.
3. **One rounding per operation**, in the order written. `a + b + c` means `(a + b) + c`. Parentheses in the
   specs are binding. No reassociation, no fused multiply-add: build with `-ffp-contract=off` (Clang/GCC),
   `/fp:precise` and no `/fp:contract` (MSVC). Never `-ffast-math`, `-Ofast`, `-funsafe-math-optimizations`.
4. **No x87.** 32-bit x86 builds use SSE2 (`-mfpmath=sse -msse2`). On ARM64 the contraction flag above is required
   (compilers fuse by default there).
5. **Denormals are kept** (no flush-to-zero / denormals-are-zero). The core checks the FP control state at the
   start of a tick in debug builds, because host engines sometimes enable FTZ.
6. Where a spec writes `(double)`, that sub-expression is evaluated in binary64 and rounded to float once at the
   end. This is used only for load-time constants.
7. `sqrt` and `/` are the IEEE correctly rounded operations (`sqrtf`). `fabsf`, `floorf`, `ceilf`, `fminf`/`fmaxf`
   semantics are exact. **Every other transcendental function** comes from §6, never from the platform's libm.
8. Conversions: `(int32)x` truncates toward zero; `round_half_even(x)` = `nearbyintf` in the default mode;
   `(float)i` of an integer is the correctly rounded conversion.
9. Sums over collections run in the order the spec names (usually ascending index). Containers whose iteration
   order is not defined (hash maps) are never iterated in simulation code.
10. No reads of wall clocks, thread timing, uninitialised memory or addresses inside a tick. Multithreading is
    allowed only if each thread's result is merged in a fixed order and does not depend on scheduling.
11. **NaN policy**: data files are validated at load (no NaN or infinity in any table or parameter, every axis
    non-decreasing, `data_format.md` §5). At run time inputs from outside (network commands, AI) are clamped to
    their ranges before use; a NaN command is treated as the neutral value (helm 0, sheet unchanged).
12. `clamp(x, lo, hi)` = `x < lo ? lo : (x > hi ? hi : x)`, which maps NaN to NaN (hence rule 11).
    `lerp(a, b, t) = a + t*(b − a)`. `min`, `max` are `a < b ? a : b` and `a > b ? a : b`.
13. Loading data: decimal numbers in data files are parsed straight to binary32 with correct rounding
    (`strtof` behaviour). Tools write floats with 9 significant digits so they round-trip exactly.

## 6. Math functions

All simulation code calls these functions; they are defined in the core's math module with exactly the operations
below (float constants written with enough digits to be exact). Accuracy on their stated domains is about 1e-7
absolute, and the point is not accuracy but identical bits everywhere.

Constants: `PI = 3.14159274f`, `TWO_PI = 6.28318548f`, `HALF_PI = 1.57079637f`, `QUARTER_PI = 0.785398163f`.

### 6.1 `wm_sincos(x) → (s, c)`, `wm_sin`, `wm_cos`

Accurate to about 1e-7 for `|x| ≤ 8192` and 1e-4 up to 65 536; deterministic for any finite `x`. Callers keep
arguments below 65 536 and reduce larger phases first (`sea.md` §4 shows how).
```
k  = round_half_even(x * 0.636619772f)          // 2/π
q  = (int32)k
r  = ((x - k*1.5703125f) - k*4.83751297e-4f) - k*7.54978995e-8f     // three-part π/2
z  = r*r
sr = ((-1.9515295891e-4f*z + 8.3321608736e-3f)*z - 1.6666654611e-1f)*z*r + r
cr = ((2.443315711809948e-5f*z - 1.388731625493765e-3f)*z + 4.166664568298827e-2f)*z*z - 0.5f*z + 1.0f
switch (q & 3):  0: (s, c) = ( sr,  cr)   1: ( cr, -sr)   2: (-sr, -cr)   3: (-cr,  sr)
```
`wm_sin(x)` and `wm_cos(x)` return the components of `wm_sincos(x)`. The three multiplications by `k` in the
reduction are separate products; `*z*r` means `((poly)*z)*r`.

### 6.2 `wm_atan(x)`, `wm_atan2(y, x)`
```
wm_atan(x):
  sign = x < 0 ? -1 : 1 ;  x = fabsf(x) ; y = 0
  if x > 2.41421356f:      y = HALF_PI    ; x = -1.0f / x
  else if x > 0.414213562f: y = QUARTER_PI ; x = (x - 1.0f) / (x + 1.0f)
  z = x*x
  y = y + ((((8.05374449538e-2f*z - 1.38776856032e-1f)*z + 1.99777106478e-1f)*z - 3.33329491539e-1f)*z*x + x)
  return sign * y

wm_atan2(y, x):
  if x == 0:  return y > 0 ? HALF_PI : (y < 0 ? -HALF_PI : 0)
  a = wm_atan(y / x)
  if x < 0:   a = y >= 0 ? a + PI : a - PI
  return a                                     // in [-π, π]
```

### 6.3 `wm_asin(x)`, `wm_acos(x)`
Domain `[−1, 1]`; callers clamp.
```
wm_asin(x):
  a = fabsf(x)
  if a > 0.5f: z = 0.5f*(1.0f - a) ; r = sqrtf(z) ; big = true
  else:        z = a*a             ; r = a        ; big = false
  p = ((((4.2163199048e-2f*z + 2.4181311049e-2f)*z + 4.5470025998e-2f)*z + 7.4953002686e-2f)*z
        + 1.6666752422e-1f)*z*r + r
  if big: p = HALF_PI - (p + p)
  return x < 0 ? -p : p
wm_acos(x) = HALF_PI - wm_asin(x)
```

### 6.4 `wm_exp(x)`
Domain `[−80, 80]`; callers clamp.
```
n = floorf(x * 1.44269504f + 0.5f)
r = (x - n*0.693359375f) - n*(-2.12194440e-4f)
z = r*r
y = (((((1.9875691500e-4f*r + 1.3981999507e-3f)*r + 8.3334519073e-3f)*r + 4.1665795894e-2f)*r
      + 1.6666665459e-1f)*r + 5.0000001201e-1f)*z + r + 1.0f
return ldexpf(y, (int32)n)                       // exact scaling by 2^n
```
`wm_pow10(x) = wm_exp(x * 2.30258512f)`.

### 6.5 Angle helpers
```
wrap_pi(a):    if (-PI <= a && a < PI) return a
               k = floorf((a + PI) * 0.159154937f)          // 1/(2π)
               r = (a - k*6.28125f) - k*1.93530717e-3f       // two-part 2π
               if r < -PI: r = r + TWO_PI
               if r >= PI: r = r - TWO_PI
               return r
wrap_2pi(a):   if (0 <= a && a < TWO_PI) return a
               k = floorf(a * 0.159154937f)
               r = (a - k*6.28125f) - k*1.93530717e-3f
               if r < 0: r = r + TWO_PI
               if r >= TWO_PI: r = r - TWO_PI
               return r
angle_diff(a, b) = wrap_pi(a - b)                              // signed shortest difference
angle_lerp(a, b, t) = wrap_2pi(a + t*angle_diff(b, a))         // compass angles
```

### 6.6 Check values
A conforming implementation reproduces these bits (hex = binary32 pattern):

| call | result | bits |
| --- | --- | --- |
| `wm_sincos(0.5f)` | 0.47942555, 0.87758255 | 3EF57744, 3F60A940 |
| `wm_sincos(1.0f)` | 0.841470957, 0.540302277 | 3F576AA4, 3F0A5140 |
| `wm_sincos(-3.0f)` | −0.141120002, −0.989992499 | BE1081C3, BF7D7026 |
| `wm_sincos(100.0f)` | −0.506365657, 0.862318873 | BF01A12E, 3F5CC0EE |
| `wm_atan(2.0f)` | 1.10714877 | 3F8DB70D |
| `wm_asin(0.9f)` | 1.11976957 | 3F8F549C |
| `wm_exp(1.0f)` | 2.71828175 | 402DF854 |

The core's test suite carries a larger vector file generated by the reference implementation.

## 7. Random numbers

Everything random in the simulation (wind shifts, puffs, oscillation phases, wave phases, AI choices that are
random) comes from one **counter-based** generator: a value is a pure function of `(seed, stream, index)`, so
any client can evaluate any draw at any time without replaying a sequence.

```
mix64(z):                       // all arithmetic mod 2^64
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9
  z = (z ^ (z >> 27)) * 0x94D049BB133111EB
  return z ^ (z >> 31)

rng_u64(seed, stream, index):   // seed, stream, index: uint64
  key = mix64(seed + 0x9E3779B97F4A7C15 * (stream + 1))
  return mix64(key + 0xD1B54A32D192ED03 * (index + 1))

rng_u32(seed, stream, index)   = (uint32)(rng_u64(seed, stream, index) >> 32)
rng_unit(seed, stream, index)  = (float)(rng_u32(...) >> 8) * 5.96046448e-8f      // [0, 1), exact
rng_range(lo, hi, ...)         = lo + (hi - lo) * rng_unit(...)
```

Check values:

| seed | stream | index | `rng_u64` | `rng_unit` |
| --- | --- | --- | --- | --- |
| 0 | 0 | 0 | 0x2FF145472E2746D6 | 0.187275231 |
| 0 | 0 | 1 | 0x7B575A03C5870447 | 0.481801629 |
| 1 | 1 | 0 | 0xBB1D2681F3984480 | 0.730913520 |
| 12345 | 2 | 7 | 0xF90F0DD20CC249EB | 0.972885907 |
| 3735928559 | 3 | 1000 | 0x32CD075B64360FC1 | 0.198440969 |

**Seeds.** The race layer draws one 64-bit `race_seed` per race (server side) and sends it to clients
(`networking.md`). Subsystem seeds are the race seed itself; subsystems are separated by stream.

**Streams** (the only allowed values; a new use gets a new number here):

| stream | use | spec |
| --- | --- | --- |
| 1 | wind shift walk | wind.md §4 |
| 2 | wind oscillation phase | wind.md §5 |
| 3 | puff slots (lifetime, stagger) | wind.md §6 |
| 4 | puff generations (position, size, strength) | wind.md §6 |
| 5 | wave component phases and direction jitter | sea.md §3 |
| 6 | per-boat attitude wobble phase | boat.md §6.5 |
| 7 | spawn order shuffle | race.md |
| 8 | venue conditions draw (wind speed, direction, tide turn) | race.md §2.1 |
| 16–31 | AI decisions | ai.md |

## 8. Tables and lookup

Performance and handling data are rectilinear tables of 1 to 3 axes (`data_format.md` §5 for the file layout).

### 8.1 Axis bracket

An axis is a list of `n ≥ 1` breakpoints `a[0..n−1]`, **non-decreasing**. Two consecutive equal breakpoints mark
a **step** (a discontinuity); three equal in a row are not allowed. `bracket(a, x) → (i0, i1, t)`:
```
if n == 1:           return (0, 0, 0)
if !(x >= a[0]):     return (0, 0, 0)            // below the range, and NaN: clamp to the first
if x >= a[n-1]:      return (n-1, n-1, 0)        // above the range: clamp to the last
i = the largest index with a[i] <= x              // binary search; i <= n-2 here
t = (x - a[i]) / (a[i+1] - a[i])                  // a[i+1] > x >= a[i], so the divisor is > 0
return (i, i+1, t)
```
So a lookup never extrapolates, and at a step (`a[k] == a[k+1]`) the value is **right-continuous**: `x == a[k]`
gives the value at `k+1`.

### 8.2 Interpolation

Values are stored row-major with the last axis varying fastest. With `(i0, i1, t)` from each axis:
```
Table1D  v(x)       = lerp(V[i0], V[i1], t)
Table2D  v(x, y)    : r0 = lerp(V[i0][j0], V[i0][j1], ty)
                      r1 = lerp(V[i1][j0], V[i1][j1], ty)
                      v  = lerp(r0, r1, tx)
Table3D  v(x, y, w) : along w first at the four (i, j) corners, then along y, then along x, each with lerp
```
`V[i][j]` of a 2-D table is `values[i*n1 + j]`; of a 3-D table `values[(i*n1 + j)*n2 + k]`. A clamped axis gives
`i0 == i1` and `t = 0`, so `lerp(p, p, 0) = p` exactly.

### 8.3 Optional tables

A spec that reads an optional table says what to use when it is absent (usually 1 for coefficients, 0 for
rates). An absent table is not the same as an empty one: empty tables are a load error.

## 9. State, snapshots and checksums

- Each spec lists its **state**: the values that must be carried from one tick to the next. State plus the
  loaded data plus the environment parameters fully determine the future; everything else is derived output.
- A **snapshot** serialises the state in the order the specs list it, floats as their 32 raw bits (little
  endian), integers little endian, booleans as one byte.
- The **checksum** of a tick is FNV-1a 64 over the tick index (uint32) followed by the **body** of the world
  snapshot (§9.1): every boat in index order, the collision pair set, the race, the rules and the carried tick
  outputs. Server and clients compare checksums to detect divergence (`networking.md` §10.2); the own-boat hash of
  `networking.md` §5.5 is a separate, smaller hash. The checksum is a pure function of the state between two
  ticks, so it is taken only when asked for (the world hash every 5 s, replays, tests), never as part of the tick:
  serialising the whole world every tick would cost a tenth to a fifth of the tick.
- Encodings: `vec2` = `x`, `y` as two floats; `list<T>` = uint32 count, then the items in order; an enum is one
  byte with the numeric value of its declaration order; tick numbers are uint32 and signed tick numbers
  (`n_gun` and the like) int64; infinities keep their raw bits like every float.

### 9.1 World snapshot

A world snapshot is everything a race world carries from one tick to the next, taken between ticks (after step 7
of tick `n − 1`, before step 1 of tick `n`). Loaded into a world built from the same race parameters
(`networking.md` §7.1: race seed, wind and sea settings, venue, course, rules parameters and the boat entries in
index order), it continues with the same bits, tick for tick, as the run it was taken from: the same checksums,
events and results. A reconnect or resync sends it (`networking.md` §9) and a replay can start from it
(`networking.md` §14).

Not state, never serialised: the loaded data and the environment parameters; the wind and the sea, which are pure
functions of the race seed and the tick (`wind.md`, `sea.md`; the counter-based generator of §7 has no stream
position to save); caches rebuilt before they are read (the wind's per-tick walk cache, the sea phases of the
tick, the shadow snapshot of step 4, the rules engine's predicted poses and hulls and its escape manoeuvres, the
race and rules inputs of the tick); the events of the last tick (published in step 7, then gone); and the memory
of the controllers that decide in step 2 (computer skippers, `ai.md`, and scripts), which they keep themselves.

Layout, in this order:

```
header (identity, not covered by the checksum)
  uint32  magic 0x57574D57, uint32 version = 4
  uint32  tick                     the next tick to run
  uint64  race_seed (§7)
  bool    race created; uint32 n_created (tick of creation, 0 without a race); uint32 entries at creation
  uint64  FNV-1a 64 of the venue's file_sha256 text
  uint64  FNV-1a 64 of the resolved course's hash text (courses.md §9), 0 without a race
  list    boats: uint64 FNV-1a 64 of the performance file's file_sha256 text, bool human, bool ai,
          float performance_scale, bool auto_trim, int32 front sail at spawn
body (covered by the checksum, after the tick index)
  per boat in index order: boat.md §3 then sails.md §3 (the boat snapshot)
  the collision pair set (collisions.md §6)
  the race block (race.md §13) and the rules block (rules.md §14), only when the race exists
  carried tick outputs, per boat in index order:
    the boat's derived outputs of its last step, boat.md §3 (target_speed, polar_speed, heel_target, turn_rate,
      vmg, sog, cog, man_coef, trim_speed, trim_heel, heel_coef, surf_coef, wind_speed_clean): the next tick's
      race and rules step reads turn_rate, cog and sog, and controllers read them in step 2
    the environment at the boat of the last step 5, wind_shadow.md §5 (wind_speed, wind_from, wind_speed_clean,
      wind_from_clean, current_x, current_y, shadow_loss, shadow_header, int32 shadow_source)
    the per-sail outputs of the last step, sails.md §7, per sail in sail order (k_h, m_opt, beta_opt, beta_t,
      trim_error, luff_shiver, uint8 motion, bool backed): the next tick's race and rules step reads m_opt through
      let_fly_drive (boat.md §9), controllers read it in step 2, and the HUD reads trim_error and luff_shiver
  list    contact events of the last collision step (collisions.md §5), read by the next tick's rules:
          uint64 tick, int32 boat, uint8 other_kind, int32 other, vec2 point, vec2 normal, float depth,
          float closing_speed, float impulse, bool begin
  list    queued controls for the next step 2, in arrival order: uint8 kind (helm, sheet, auto_trim, let_fly,
          hoist, drop, retire, protest), int32 boat, float value, int32 sail
```

A load checks the header against the world it goes into (same race seed, venue, course, boat count and
entries) and rejects a snapshot that does not match, is truncated, has bytes left over or holds a value out of
range. A world whose race took joiners (`race.md` §3.5) is rebuilt as it was built: the race is created at
`n_created` with the entries at creation, the later entries join after it, and the snapshot then overwrites every
state value.

A world takes any number of loads, whatever it has run before (a resync, `networking.md` §9, or a replay scrubbed
back and forth, `networking.md` §14): a load first resets the world to its state when it was built with its entries (tick 0, no
race), then rebuilds and overwrites it as above. A load that fails changes nothing: the world keeps the state it
had and can go on stepping or take another load.

## 10. Naming

Identifiers in the specs are the names used in code (snake_case). Recurring ones:

| name | meaning |
| --- | --- |
| `tws`, `twd_from`, `twa` | true wind speed, direction (from), angle, relative to the **water** |
| `aws`, `awd_from`, `awa` | apparent wind speed, direction, angle |
| `v` | boat speed through the water along the heading (m/s, may be negative when going astern) |
| `psi` / `ψ` | heading |
| `phi` / `φ`, `theta` / `θ` | heel, pitch |
| `h`, `h_cmd` | helm (actual, commanded), normalised |
| `beta` / `β` | sail angle |
| `eps` / `ε` | trim error of a sail (`sails.md` §5) |
| `tack` | `sgn(twa)` |
| `front sail` | the one non-main sail flown at a time (jib, genoa, code zero or spinnaker) |
| `config` | the sail combination whose tables drive the boat: main only, or main + one front sail |

## 11. Front-end scene frame (Godot)

Presentation only: the core never sees these axes. The front-end specs (`cameras.md`, `water_render.md`,
`sail_visuals.md`) use them.

- **Scene world**: Godot `X` = east, `Y` = up, `Z` = south. A world point `(x, y, z)` (ENU, §2) is drawn at
  `(x, z, −y)`, so north is `−Z` (Godot's forward). As a matrix, `M = [[1, 0, 0], [0, 0, 1], [0, −1, 0]]`, a
  rotation (no mirror). Compass angles stay clockwise from north: a heading `ψ` points along
  `(sin ψ, 0, −cos ψ)`.
- **Generated model axes** (`tools/boatgen/README.md`): glTF `(X, Y, Z) = (y, z, x)` of the body frame (§3), so
  model `+X` is port, `+Y` up and `+Z` the bow; a body-frame point `p` of the class file or the physics sidecar is
  `C·p = (p.y, p.z, p.x)` in the model (also a rotation).
- **Boat node**: its local axes are the model axes, and the imported model sits under it with the identity
  transform. Its origin is the hull reference point drawn at `M·(x, y, z)` (position and heave), and its basis is
  `M · R · C⁻¹` with `R` the attitude matrix of §3: the basis columns are `M·R` applied to the body `y`, `z` and
  `x` axes. Upright on `ψ = 0` the basis is a half turn about `Y`: the bow (local `+Z`) points north (`−Z`). Note
  that the bow is the node's local `+Z`, not Godot's forward `−Z`.
