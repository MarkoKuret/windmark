# Sea

The water surface: a wind sea and optional swells built as a small sum of travelling sine waves that obey the
deep-water dispersion relation, scaled down in sheltered water by a venue exposure grid. The boat samples it for
heave, pitch and roll (`boat.md` §5.6); the renderer evaluates **the same height function** for the drawn surface,
so boats sit on the waves players see.

## 1. Model

```
η(x, y, t) = E(x, y) · Σ_i a_i · cos(2π · (κx_i·x + κy_i·y + c_i − t/T_i))
```
- component `i`: amplitude `a_i` (m), wave vector `(κx_i, κy_i)` in **cycles per metre** pointing the way the
  wave travels, period `T_i` (integer ms), phase `c_i` (cycles);
- deep-water dispersion: `ω_i = 2π/T_i`, wavenumber `k_i = ω_i²/G`, so long waves are fast and short ones slow,
  and crests travel at the phase speed `G/ω_i`;
- `E(x, y) ∈ [0, 1]`: exposure (open water 1, sheltered water less, §6).

Pure height field: points on the surface only move up and down, so the height at `(x, y)` is one direct sum, cheap
on a CPU and in a vertex shader. Wave shape (steeper crests) is left to the renderer's visual detail (§7.3).

## 2. Sea-state settings

Chosen by the race layer (`race.md`) and sent with the race seed:

| name | unit | meaning |
| --- | --- | --- |
| `sea_hs`, `sea_tp` | m, s | significant height and peak period of the wind sea |
| `sea_from` | rad | direction the wind sea comes from (default: `base_from` of the wind) |
| `swells[0..3]` | {`hs`, `tp`, `from`} | optional swells, at most 4 (`hs ≥ 0`; `tp > 0` when `hs > 0`) |
| `sea_scale` | – | overall multiplier (0 = flat water) [1] |
| `venue_exposure` | ref | exposure grid of the venue (`data_format.md` §6.4) [none: E = 1] |

The **wind sea follows the base wind**: the server derives `sea_hs`, `sea_tp` from the base wind speed `U`
(`wind.md` §1) and the venue fetch `F` (`data_format.md` §6.1) with the fetch-limited growth law
```
χ  = min(G·F / U², 2.2e4)                    // dimensionless fetch; 2.2e4 = fully developed
Hs = 0.0016 · sqrt(χ) · U² / G
Tp = 0.286 · χ^(1/3) · U / G                 // Hs = 0 when U < 1 m/s
```
evaluated in any precision; only the resulting floats are sent, so clients never evaluate the cube root.
At a venue, `U` is the drawn `base_speed` of the race (`race.md` §2.1), `F` the header's `fetch` (the fetch for the
venue's typical wind direction), and `swells` and `sea_scale` come from the venue's `conditions.sea`
(`data_format.md` §6.7). The exposure grid is made by `venuegen` for that typical direction, so a lee shore (land
upwind, as in an offshore bora) reads as flat water near it. Reference values (fetch 10 km): 10 kn → Hs 0.26 m, Tp 2.3 s; 15 kn → 0.39 m, 2.7 s; 20 kn → 0.53 m, 2.9 s;
25 kn → 0.66 m, 3.2 s. Open-sea venues use a longer fetch (30 km: 15 kn → 0.68 m, 3.8 s) and add a swell.
The sea does not follow wind shifts or puffs during a race (it takes minutes to hours to change).

## 3. Components

Built once when the race environment starts, in this order.

### 3.1 Wind sea: 10 components
| i | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `r_i` (f/fp) | 0.75 | 0.85 | 0.95 | 1.05 | 1.18 | 1.35 | 1.6 | 1.95 | 2.4 | 3.0 |
| `w_i` | 0.1621 | 0.2738 | 0.4766 | 0.5384 | 0.3616 | 0.3225 | 0.2765 | 0.2051 | 0.1433 | 0.0887 |
| `o_i` (deg) | 0 | −25 | 20 | −10 | 35 | −40 | 12 | 45 | −30 | 5 |

`w_i` samples a peaked wind-sea spectrum (JONSWAP shape, peak enhancement 3.3) over bands around `r_i` and are
normalised so `Σ w_i² = 1`; `o_i` spread the directions (more spread in the short waves), giving short-crested,
non-repeating seas.

### 3.2 Swells: 3 components each
`r = (0.92, 1.0, 1.08)`, `w = (0.5, 0.70710678, 0.5)`, `o = (−8°, 0°, +8°)`, from the swell's own `hs`, `tp`,
`from`. Swell `s` gives components `10 + 3s + m`, `m = 0..2`.

### 3.3 Per component `i` (with the owning train's `Hs`, `Tp`, `from`)
```
T_i   = max(200, (uint32)((Tp*1000.0f) / r_i + 0.5f))                      // period, ms
w_ang = (TWO_PI*1000.0f) / (float)T_i                                    // ω, rad/s
kap   = ((w_ang*w_ang) / G) / TWO_PI                                     // cycles per metre
dir   = wrap_2pi(((from + PI) + o_i*DEG) + (rng_unit(race_seed, 5, 2i+1) - 0.5f)*(10.0f*DEG))  // travel direction
kx_i  = kap * wm_sin(dir) ; ky_i = kap * wm_cos(dir)
a_i   = ((Hs * 0.353553391f) * w_i) * sea_scale                           // Hs/(2√2)·w
a_i   = min(a_i, 0.1f / (kap*TWO_PI))                                     // steepness cap a·k <= 0.1
c_i   = rng_unit(race_seed, 5, 2i)                                        // phase, cycles
```
With `Σ w_i² = 1` a train has variance `Σ a_i²/2 = (Hs/4)²`, so its significant height is `Hs` (before the
steepness cap, which only trims very short, steep components). Components with `a_i = 0` are dropped (a train
with `Hs = 0` contributes nothing). The list keeps its construction order.

## 4. Height evaluation

Per tick (step 3, `conventions.md` §4.1), at `t = t_env_ms` of the tick:
```
d_i = c_i - (float)(t % T_i) / (float)T_i                      // cycles
```
Height at a world point:
```
sea_height(x, y):
  sum = 0
  for i in component order:
     c = ((kx_i*x) + (ky_i*y)) + d_i                            // cycles
     f = c - round_half_even(c)                                 // [-0.5, 0.5]
     sum = sum + a_i * wm_cos(TWO_PI*f)
  return E(x, y) * sum
```
Working in cycles and removing the whole part before the cosine keeps the argument inside `[−π, π]` at any
distance and any time, and the time phase is exact because it comes from an integer modulo.

Slope (renderers, AI): `∂η/∂x = −E·Σ a_i·2π·kx_i·sin(2π f_i)`, likewise `y` (the gradient of `E` is ignored).

## 5. Boat sampling

### 5.1 Hull points
The performance file may list the hull sample points (`dynamics.hull_points`, body frame, m). Otherwise the core
derives 8 points from `dynamics.lwl` and `dynamics.bwl` (`data_format.md` §4.2), in this order:
```
( 0.45·lwl, 0), (−0.45·lwl, 0),
( 0.25·lwl,  0.35·bwl), ( 0.25·lwl, −0.35·bwl),
( 0,         0.35·bwl), ( 0,        −0.35·bwl),
(−0.25·lwl,  0.35·bwl), (−0.25·lwl, −0.35·bwl)
```
At load: `mx`, `my` = means of the point coordinates, `sxx = Σ(px − mx)²`, `syy = Σ(py − my)²` (sums in point
order).

### 5.2 Per tick (boat step 5.6)
```
fx = sin(psi) ; fy = cos(psi) ; lx = -fy ; ly = fx                      // bow and port unit vectors
for each point k: wx = (pos_x + px_k*fx) + py_k*lx ; wy = (pos_y + px_k*fy) + py_k*ly
                  h_k = sea_height(wx, wy)
hm = (Σ h_k) / (float)n
gx = Σ (h_k - hm)*(px_k - mx) ; gy = Σ (h_k - hm)*(py_k - my)          // point order
wave_pitch = sxx > 1e-6 ? wm_atan(gx / sxx) : 0                        // + = bow up
wave_roll  = syy > 1e-6 ? wm_atan(gy / syy) : 0                        // + = starboard down (port side lifted)
```
The points are placed with the heading only (the boat's own heel and pitch are ignored for sampling), which keeps
the response stable. A least-squares plane through the points gives the slopes, so waves much shorter than the
hull average out and waves of hull length and longer move the boat: a large boat stays steady in a short chop, a
small one pitches in it.

## 6. Exposure

`E(x, y)` comes from the venue exposure grid, sampled with the grid sampler of `wind.md` §8.1 (bilinear, row-major
nodes), with `exposure_default` (normally 1) outside the grid and 1 when the venue has none. Land cells hold 0,
harbours and lee shores small values; the tool that makes the grid (`data_format.md` §6.4) smooths it so the sea
fades out over a few wavelengths rather than stopping at a line.

## 7. Renderer contract

### 7.1 What the core exports
The component list `(a_i, kx_i, ky_i, c_i, T_i)`, the exposure grid, and `sea_height` / slope functions for any
point and time. The list is fixed for a race.

### 7.2 Evaluating it identically
The renderer draws at its own frame time `t_r` (ms, fractional, the same clock as `t_env_ms`). Per frame, on the
CPU in double precision, for a camera-relative origin `(ox, oy)`:
```
d_i' = frac(c_i − fmod(t_r, T_i)/T_i + kx_i·ox + ky_i·oy)          // cycles, [0, 1)
```
and the shader evaluates, for a local position `(xl, yl) = (x − ox, y − oy)`:
```
η = E(x, y) · Σ_i a_i · cos(2π · fract(kx_i·xl + ky_i·yl + d_i'))
```
which is the physics function up to float rounding (well under a millimetre for venue-size coordinates). At a
tick time `t_r = t_env_ms` the drawn surface is the one the boats sampled.

### 7.3 Visual detail
The renderer may add visual-only layers: normal maps and ripples, foam, crest sharpening, and horizontal
("choppy") displacement of **those layers only**. Their height displacement stays below `0.05·Hs` so hulls never
visibly sink into or float above the drawn surface. The components of §3 are never displaced horizontally.

### 7.4 Boats on the drawn sea
Boats are drawn at their interpolated physics state (`boat.md` §9), whose heave already follows the mean wave
height with the lag of `heave_time`. Bow waves, wakes and spray are visual (renderer spec); they read the boat's
speed and attitude and this height function.

## 8. Tests

1. Bit-exact `sea_height` against a stored vector file for several sea states, points up to 8 km from the origin,
   and times up to 4 hours.
2. Statistics: over a 1 km × 1 km grid and 10 minutes, the significant height `4·std(η)` of an uncapped train is
   within 5 % of `Hs`; its mean is within 1 cm of 0.
3. Dispersion: the crest of each component moves `G·T_i/(2π)` metres per second along its direction.
4. Boat response: an L-class boat in `Hs = 0.4 m, Tp = 2.7 s` pitches less than an S-class boat in the same sea.
5. Renderer parity: a double-precision evaluation of §7.2 at tick times matches `sea_height` within 1 mm.
