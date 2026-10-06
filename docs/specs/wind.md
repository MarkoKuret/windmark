# Wind and current

The true wind over the race area: a base wind, direction shifts (a random walk of persistent shifts plus a small
continuous oscillation), puffs and lulls that drift downwind, an optional venue field for land effects, and the
water current. Everything is a **pure function of `(race_seed, t_env_ms, position)`**, so the server and every
client compute the same wind without streaming it (`conventions.md` §4, §7). The shadows boats cast on each other
are applied on top, per receiving boat (`wind_shadow.md`).

## 1. Settings

The race layer (`race.md`) chooses the settings for a race and sends them with the seed. Defaults in brackets. At
a venue with `conditions` (`data_format.md` §6.7) the race layer derives them from the venue's typical weather and
the seed (`race.md` §2.1); nothing below changes, a venue only picks other numbers.

| block | name | unit | meaning |
| --- | --- | --- | --- |
| base | `base_speed` | m/s | median true wind speed at 10 m [7.2 = 14 kn] |
| | `base_from` | rad | median direction the wind comes from |
| shift | `shift_amplitude` | rad | typical size of a persistent shift, `A` [preset] |
| | `shift_hold_max_ms`, `shift_hold_min_ms` | ms | how long a shifted direction holds [preset; min = max/5] |
| | `shift_trend_rate`, `shift_trend_max` | rad/s, rad | steady rotation of the median (a persistent shift across the race) [0, 0.35] |
| oscillation | `osc_enabled` | bool | small continuous oscillation [false] |
| | `osc_amplitude` | rad | [2° = 0.0349] |
| | `osc_time_scale` | s | [17] |
| puffs | `puffs_enabled` | bool | [true] |
| | see §6.1 | | puff field parameters |
| venue | `venue_wind_field` | ref | optional land-effect field (`data_format.md` §6.2) |
| current | `current_speed`, `current_to` | m/s, rad | uniform current [0] |
| | `venue_current_field`, `tide_scale`, `tide_period_ms`, `tide_phase_ms` | | optional tidal current (§7) |

Shift presets (`shift_amplitude`, `shift_hold_max_ms`):

| preset | amplitude | hold max | character |
| --- | --- | --- | --- |
| `steady` | 0 | – | direction constant |
| `stable` | 3° | 120 s | small slow shifts |
| `oscillating` | 8° | 90 s | regular left/right swings |
| `shifty` | 15° | 60 s | frequent, tactical [default] |
| `unstable` | 25° | 45 s | big and frequent |

## 2. Wind at a point

For world position `(x, y)` at environment time `t` (ms):
```
dir_offset(t)  = shift(t) + trend(t) + osc(t)                     // rad, + = veer (clockwise)
global_from(t) = wrap_2pi(base_from + dir_offset(t))
(f, d)         = venue_field(x, y, global_from(t))                 // (1, 0) without a venue field, §8
m              = puffs_enabled ? puff_factor(x, y, t) : 1          // §6
wind_speed     = ((base_speed * f) * m)
wind_from      = wrap_2pi(global_from(t) + d)
```
The terms are summed in the order written. `wind_speed` is ≥ 0 by construction (`f ≥ 0`, `m > 0`). This is the
**clean wind**; the wind a boat sails in is the clean wind at its hull reference point with the other boats'
shadows applied (`wind_shadow.md` §5).

In tick step 3 (`conventions.md` §4.1) the core evaluates `global_from(t_n)` once and caches the per-tick parts
(shift segment, puff slot positions); per-point queries then only do the venue lookup and the puff product.

There is **no vertical profile** in the simulation: `wind_speed` is the 10 m wind, which is what the polar tables
are defined for. Renderers that want a height-dependent wind (flags, masthead wind indicators) use
`U(zh) = wind_speed · ln(zh / 0.0002) / ln(10 / 0.0002)` with `zh ≥ 0.5 m`; it never feeds back.

## 3. Direction terms

- `shift(t)`: the persistent-shift walk (§4).
- `trend(t) = clamp(shift_trend_rate * t_s, -shift_trend_max, shift_trend_max)`, `t_s = (float)t * 0.001f`: a
  steady veer or back over the race (a sea breeze filling in).
- `osc(t)`: the small oscillation (§5), 0 when disabled.

## 4. Persistent shifts

The direction steps between **plateaus**, joined by linear **ramps** at a fixed rate. Each new plateau is a
random step from the last, biased back toward the median, and bounded. The walk is a sequence of segments
`k = 0, 1, 2, …`, each a ramp then a hold, starting at environment time 0 on the median direction.

### 4.1 Constants
```
enabled = shift_amplitude >= 1e-5 and shift_hold_max_ms > 0         // otherwise shift(t) = 0
A    = clamp(shift_amplitude, DEG, PI)
B    = min(1.4f * A, PI)                                              // bound of the walk
C    = clamp(0.08f*A + 0.5f*(A*A), 0.02f, 0.2f)                       // ramp rate, rad/s
hmax = shift_hold_max_ms ; hmin = min(shift_hold_min_ms, hmax)        // default hmin = hmax / 5 (integer)
```
Reference ramp rates: 3° → 0.02 rad/s (2.6 s ramp for a full-amplitude step), 15° → 0.055 rad/s (4.8 s),
25° → 0.13 rad/s (3.4 s).

### 4.2 Segment `k`
With `o_prev` the plateau of segment `k − 1` (`o_prev = 0` for `k = 0`) and draws from stream 1:
```
u_dir  = rng_unit(race_seed, 1, 3k)
u_mag  = rng_unit(race_seed, 1, 3k + 1)
u_hold = rng_unit(race_seed, 1, 3k + 2)
p_pos  = 1.0f / (1.0f + wm_pow10(o_prev / (2.0f*A)))       // chance of a step to the right (veer)
s      = u_dir < p_pos ? +1 : -1
m      = clamp(0.45f - 0.35f*(s*(o_prev / A)), 0, 0.8f)
step   = (s*A) * (0.2f + m*u_mag)
o_k    = clamp(o_prev + step, -B, B)
ramp_k = (uint32)((fabsf(o_k - o_prev) / C) * 1000.0f + 0.5f)                       // ms
hold_k = hmin + min((uint32)(u_hold * (float)(hmax - hmin + 1)), hmax - hmin)        // ms
start_0 = 0 ; start_{k+1} = start_k + ramp_k + hold_k
```
- Mean reversion: at the median `p_pos = 0.5`; one amplitude to the right `p_pos = 0.24`; at the bound (1.4 A)
  `p_pos = 0.17`. Steps toward the median are also larger (`m` grows), so the wind oscillates about its median with
  occasional runs to one side.
- Step sizes lie between 0.2 A and A.

### 4.3 Evaluation
```
shift(t): find k with start_k <= t < start_{k+1}
          tau = t - start_k
          tau < ramp_k ? o_prev + (o_k - o_prev) * ((float)tau / (float)ramp_k) : o_k
```
Segments are generated in order from `k = 0`; implementations cache the current segment and its `o_prev` and
advance forward as `t` grows (a race of an hour has fewer than 400 segments). A query for an earlier time restarts
from `k = 0`. Both give identical results.

## 5. Oscillation

A continuous, non-repeating wobble of the direction:
```
t_o = (float)t * 0.001f + 1000.0f * rng_unit(race_seed, 2, 0)          // s, random start per race
tau = t_o / osc_time_scale
a = wm_sin(((6.0f*tau) + wm_sin(0.8f*tau)) + wm_sin(8.47f*tau))
b = wm_sin(wm_sin(tau) * wm_sin(3.0f*(tau + 7.0f)))
c = wm_sin(2.0f*tau)
osc(t) = osc_amplitude * (((0.5f*a) + b) + (0.3f*c))                   // |osc| <= 1.8 · amplitude
```
With the defaults it moves about ±3° over periods of tens of seconds to a few minutes: fine tactical texture on
top of the persistent shifts.

## 6. Puffs and lulls

Circular patches of stronger (puff) or weaker (lull) wind drift across the course with the wind, grow, hold and
fade. They live on a square **tile** that repeats over the whole venue, so a fixed set of slots covers any course.
Checked with the settings (when puffs are on): `puff_tile > 0`, `0 < puff_diameter_min ≤ puff_diameter_max`,
lifetimes as in the table, `lull_strength_max < 1`, `puff_cap_up ≥ 0`, `0 ≤ puff_cap_down < 1`.

### 6.1 Parameters

| name | default | meaning |
| --- | --- | --- |
| `puff_tile` | 1000 m | tile side; the pattern repeats every tile in x and y |
| `puff_count`, `lull_count` | 5, 5 | slots of each kind |
| `puff_diameter_min`, `_max` | 200, 300 m | patch diameter |
| `puff_strength_min`, `_max` | 0.3, 0.5 | peak relative increase of a puff |
| `lull_strength_min`, `_max` | 0.5, 0.7 | peak relative decrease of a lull |
| `puff_life_min_ms`, `_max_ms` | 60 000, 120 000 | lifetime of a patch; `0 < puff_life_min_ms ≤ puff_life_max_ms` |
| `puff_cap_up`, `puff_cap_down` | 0.25, 0.4 | the combined factor is clamped to `[1 − cap_down, 1 + cap_up]` |

Puff presets (named in a venue's conditions; any key above may still be overridden). Keys not listed keep the
defaults; `standard` is the defaults.

| preset | puff strength | lull strength | diameter | life | counts (puff, lull) | caps (up, down) |
| --- | --- | --- | --- | --- | --- | --- |
| `none` | puffs off (`puffs_enabled = false`) | | | | | |
| `light` | 0.10 – 0.20 | 0.15 – 0.30 | 200 – 300 m | 60 – 120 s | 5, 5 | 0.15, 0.25 |
| `standard` | 0.30 – 0.50 | 0.50 – 0.70 | 200 – 300 m | 60 – 120 s | 5, 5 | 0.25, 0.40 |
| `gusty` | 0.40 – 0.70 | 0.50 – 0.70 | 150 – 300 m | 30 – 90 s | 7, 5 | 0.45, 0.40 |

### 6.2 Slots and generations
Slot `j` (`0 ≤ j < N`, `N = puff_count + lull_count`; `j < puff_count` are puffs) has a fixed lifetime and stagger:
```
span_j = puff_life_max_ms - puff_life_min_ms
life_j = puff_life_min_ms + min((uint32)(rng_unit(race_seed, 3, 2j) * (float)(span_j + 1)), span_j)   // ms, > 0
off_j  = min((uint32)(rng_unit(race_seed, 3, 2j + 1) * (float)life_j), life_j - 1)
```
At time `t` the slot shows generation `g` at age `a`:
```
q = (uint64)t + off_j ; g = q / life_j ; a = q % life_j ; birth = (int64)t - a      // ms
idx = ((uint64)j << 32) | g
u0..u3 = rng_unit(race_seed, 4, 4*idx + i), i = 0..3
cx = u0 * puff_tile ; cy = u1 * puff_tile                       // spawn point in the tile, m
R  = 0.5f * (puff_diameter_min + u2 * (puff_diameter_max - puff_diameter_min))
s  = j < puff_count ? puff_strength_min + u3*(puff_strength_max - puff_strength_min)
                    : -(lull_strength_min + u3*(lull_strength_max - lull_strength_min))
```
Each generation is a new patch in a new place; the stagger means patches are born and die at different times and
some are already mature when the race environment starts.

### 6.3 Drift and envelope
A patch drifts with the wind it was born in, at its own speed (a puff travels faster than a lull):
```
fb = global_from(max(birth, 0))                  // direction at birth
sb = base_speed * (1.0f + s)
age_s = (float)a * 0.001f
px = cx + (-sb * wm_sin(fb)) * age_s ; py = cy + (-sb * wm_cos(fb)) * age_s
fl = (float)life_j ; fa = (float)a
e = fa < 0.1f*fl ? fa / (0.1f*fl) : (fa < 0.9f*fl ? 1.0f : (fl - fa) / (0.1f*fl))    // fade in 10 %, out 10 %
```
`(px, py)` is not wrapped into the tile: it is one image of a pattern that repeats every `puff_tile` in x and y.
The factor (§6.4) takes the nearest image; a renderer draws the patch at `(px + m·puff_tile, py + n·puff_tile)`
for every tile it shows.

The patch keeps its birth direction for its whole life; after a big shift, patches born before it still drift
the old way for up to a minute or two, which reads as the new wind "filling in".

### 6.4 Factor at a point
```
puff_factor(x, y, t):
  m = 1
  for j = 0 .. N-1:                                        // slot order
     compute (px, py, R, s, e) of slot j at t (§6.2, §6.3)
     if e < 1e-4: continue
     dx = wrap_tile(x - px) ; dy = wrap_tile(y - py)
     r2 = dx*dx + dy*dy ; R2 = R*R
     if r2 <= R2: m = m * (1.0f + (e*s) * (1.0f - r2 / R2))
  return clamp(m, 1 - puff_cap_down, 1 + puff_cap_up)

wrap_tile(d) = d - puff_tile * floorf(d * (1.0f / puff_tile) + 0.5f)      // nearest image, [-tile/2, tile/2)
```
The profile is a paraboloid: strongest at the centre, zero at the edge. Overlapping patches multiply; the clamp
keeps the extremes playable (0.6 to 1.25 of the base with the defaults). The per-tick cache (§2) holds each slot's
`(px, py, R, s, e)` for `t_n`; `1.0f / puff_tile` is computed once at setup.

## 7. Current

```
current(x, y, t) = uniform + tide(t) * venue_current_field(x, y)          // m/s, east/north
uniform = current_speed * (sin(current_to), cos(current_to))
tide(t) = tide_scale * wm_cos(TWO_PI * ((float)(((uint64)t + tide_phase_ms) % tide_period_ms) / (float)tide_period_ms))
```
The sum `t + tide_phase_ms` is taken in 64 bits, so it never wraps before the modulo; `tide_period_ms > 0`.
At a venue the race layer sets `tide_phase_ms` from the race seed: each race starts at a drawn point of the tidal
cycle (`race.md` §2.1).
`venue_current_field` is a grid of velocity vectors at the reference (spring) tide (`data_format.md` §6.3),
bilinear, zero outside its box; absent = zero. `tide_period_ms` default 44 712 000 (12 h 25 min). The boat step
takes the current at its hull reference point (`boat.md` §5.1): it drifts the boat and it changes the
water-relative true wind the boat sails in.

## 8. Venue wind field

Land bends and slows the wind near shores. A venue may carry, for each of the 8 base directions
(from N, NE, E, SE, S, SW, W, NW), a grid of **speed factor** `f ≥ 0` and **direction offset** `d` (rad, + =
veer) (`data_format.md` §6.2). For `global_from = θ`:
```
w  = θ / QUARTER_PI ; k0 = (int32)floorf(w) & 7 ; k1 = (k0 + 1) & 7 ; tw = w - floorf(w)
(f0, d0) = grid[k0](x, y) ; (f1, d1) = grid[k1](x, y)          // bilinear, §8.1
f = lerp(f0, f1, tw) ; d = lerp(d0, d1, tw)
```

### 8.1 Grid sampling
A grid has `nx × ny` nodes at `(x0 + i·dx, y0 + j·dy)`, values stored row by row (`j` major, `i` fastest), with
`nx ≥ 2`, `ny ≥ 2` (a grid is at least one cell), `dx, dy > 0`, and every value finite.
```
if x < x0 or y < y0 or x > x0 + (nx-1)*dx or y > y0 + (ny-1)*dy: return the default (1, 0)
u = (x - x0) / dx ; i = min((int32)u, nx - 2) ; tx = u - (float)i          // likewise j, ty from y
r0 = lerp(v[j][i], v[j][i+1], tx) ; r1 = lerp(v[j+1][i], v[j+1][i+1], tx)
return lerp(r0, r1, ty)
```
The same sampler serves the current field and the sea exposure grid (`sea.md` §6). Venue tools write the border
nodes of wind grids as `(1, 0)` so leaving the box is seamless.

## 9. Queries for other systems

| query | returns | used by |
| --- | --- | --- |
| `wind_clean(x, y, t)` | `wind_speed`, `wind_from` without shadows | boat step input, AI, HUD wind arrows |
| `global_from(t)`, `dir_offset(t)` and its three terms | the median direction and the current shift | HUD, debug views |
| `puff_factor(x, y, t)` | the puff/lull factor | AI, renderer (dark patches on the water) |
| `puff_patches(t)` | each live patch `(px, py, R, s, e)`, centres unwrapped (§6.3) | renderer, debug views |
| `current(x, y, t)` | current vector | boat step, AI, HUD |

They are pure functions, but the AI only reads what a sailor could observe: the wind at its own boat and nearby
water now, and its own history. It never evaluates future times or `global_from` (`ai.md`).

## 10. Tests

1. Determinism: `wind_clean` over a 50 × 50 grid at 100 times equals a stored vector file bit for bit. The file
   may store a hash of each time's grid (FNV-1a 64 over the bit patterns, `conventions.md` §9) instead of every
   value.
2. Shift statistics over 10⁵ segments for `shifty`: offsets stay within ±1.4 A, mean within 0.05 A of 0, and the
   distribution of hold times is uniform in `[hmin, hmax]`.
3. Continuity: `global_from` has no jumps larger than `C · (DT + 0.5 ms)` between ticks with the oscillation off
   (plus float rounding): ramps last a whole number of ms (§4.2 rounds `|step| / C`), so a ramp's rate can exceed
   `C` by half a millisecond's worth.
4. Puff factor: always within the caps; a patch's centre moves `sb · DT` per tick; a patch's envelope is 0 at birth
   and death.
5. Cache: evaluating a race's wind tick by tick with the cache and from scratch at random times gives identical bits.
