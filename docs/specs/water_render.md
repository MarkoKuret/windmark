# Water rendering

How the front end draws the sea: the surface from the same height function the boats sample, its normals, colour,
Fresnel and sky reflection, the wind on the water (puffs and lulls that players read tactically), whitecaps, bow
waves, wakes and spray, and the quality tiers for low-end GPUs. It ends with a comparison of our approach with the
open-source Godot FFT oceans and a recommendation.

The contract comes from `sea.md` §7: the drawn surface is `sea_height` itself (up to float rounding), visual-only
layers may add normals, foam and small displacements but no more than `0.05·Hs` of height, and the sea components
are never displaced horizontally. The wind on the water comes from `wind.md` §6 and §9. Scene axes are those of
`conventions.md` §11: Godot `X` = east, `Y` = up, `Z` = south, so a world point `(x, y)` on the water is `(x, η, −y)`.

## 1. What must match the simulation

| drawn | must equal | tolerance |
| --- | --- | --- |
| surface height | `sea_height(x, y)` at the render time (`sea.md` §4, §7.2) | 1 mm at the grid vertices for every component the grid carries; the waves the grid fades (§3.2) remove less than 3 px of height at the tier's reference screen wherever a boat is drawn |
| dark and light wind patches | `puff_factor(x, y, t)` of `wind.md` §6.4 | 1e-3 of the factor |
| sheltered calm | the exposure `E(x, y)` of `sea.md` §6 | 1e-3 |
| wind slowed by land | the venue speed factor `f` of `wind.md` §8 | 1e-3 |
| wakes and spray | anything (visual) | – |

The boats are drawn at their interpolated physics pose (`boat.md` §9), whose heave follows the mean wave height, so a
hull sits on the surface players see.

## 2. Per-frame data (CPU)

Every frame, at the render time `t_r` (ms, fractional, the environment clock):
```
origin (ox, oy) = the camera's world position on the water plane (double)
for each sea component i (sea.md §3; at most 10 + 4·3 = 22):
    d_i' = frac(c_i - fmod(t_r, T_i) / T_i + kx_i*ox + ky_i*oy)          // double, then to float
    uniform comp[i] = (a_i, kx_i, ky_i, d_i')                            // vec4 array
uniform n_comp, sum_a = Σ a_i, hs_eff = 4*sqrt(Σ a_i²/2)
for each live puff patch j (wind.md §9 puff_patches(t_r), at most 10):
    uniform puff[j] = (px_j - ox, py_j - oy, R_j, e_j * s_j)             // camera-relative
uniform puff_tile, puff_cap_lo = 1 - puff_cap_down, puff_cap_hi = 1 + puff_cap_up
uniform wind_to = unit vector the wind blows toward (global_from(t_r) + π), base_speed
uniform exposure texture (venue grid, R32F, texel (i, j) = node (i, j)) and its mapping, E default
uniform land texture (venue wind field, RG32F: the two sectors around global_from(t_r)), its mapping, tw (§4.3)
uniform detail and foam layer offsets: the camera-origin part of the §4.1 and §4.4 texture coordinates, in double, mod 1
```
The exposure is sampled in the vertex shader with `texelFetch` and exact bilinear weights (the hardware filter's
8-bit weights would miss the 1e-3 tolerance); R32F keeps the grid values exact.
The puff patches are evaluated at `t_r` with the drift formula of `wind.md` §6.3 (it is continuous in time), so they
glide between ticks. Nothing here needs to be deterministic; it only has to agree with the core's functions to the
tolerances of §1.

## 3. Surface mesh and vertex shader

### 3.1 Mesh
A **camera-centred radial grid** in the water plane, moved every frame to the camera's `(x, y)` (not rotated):
a centre fan and `N_r` rings of `N_s` segments at geometric radii `r_k = r_0·q^k`, `q = (r_max/r_0)^(1/(N_r − 1))`, so
the vertex spacing is about `s(r) = r·(q − 1)` radially and `2πr/N_s` around. `r_0 = 0.6 m`, `r_max = 24 km` (the
horizon at the far plane, `cameras.md` §7). Tiers set `N_r × N_s` (§7). The node's `custom_aabb` covers the whole
disc and ±(2·Hs + 1) m, so it is never culled.

### 3.2 Height and slope
Per vertex at world `(x, y)`, local `(xl, yl) = (x − ox, y − oy)`:
```
s  = local vertex spacing (from the ring radius of the vertex)
for each component i:
    lam_i = 1 / length(kx_i, ky_i)                        // wavelength, m
    w_i   = smoothstep(2, 4, lam_i / s)                   // fade waves the grid cannot carry (far field only)
    f     = fract(kx_i*xl + ky_i*yl + d_i')
    eta  += w_i * a_i * cos(TWO_PI * f)
    grad += w_i * a_i * TWO_PI * (kx_i, ky_i) * (-sin(TWO_PI * f))
E = exposure(x, y)
eta *= E ; grad *= E                                      // gradient of E ignored, as in sea.md §4
VERTEX.y = eta ; normal = normalize(-grad.x, 1, grad.y)   // scene axes: Z = -y
```
- The fade removes the waves shorter than two to four grid spacings, where they would alias into shimmer. The
  shortest wind-sea components are about 1 m long (`r = 3`, `sea.md` §3.1), so even near the camera (spacing
  0.3 m at 5 m, 1.5 m at 25 m on tier M) some are faded: the surface equals `sea_height` at the vertices for the
  components the grid carries, and the long waves (swell, the peak of the wind sea) everywhere. What is removed
  is small in the picture: its typical height (2σ) is 1 to 3 px at the tier's reference screen between 5 and
  100 m from the camera and under 1 px beyond 200 m (test §9.2 prints the table). These short waves are also the
  ones a hull averages out (`sea.md` §5), so the drawn hull sits on the surface the grid carries. The
  `0.05·Hs` limit of `sea.md` §7.3 applies to added visual layers, not to this fade.
- The fragment shader re-evaluates the slope of the components the vertex grid faded (`w_i < 1`) per pixel on the
  higher tiers, themselves faded by the pixel footprint (`fwidth` of the position) so they never alias, so
  distant water keeps its wave texture in the lighting.
- A later option for tier H, if the near field needs it: a small fine patch (say 64 m at 0.25 m) under the
  camera, blended into the radial grid.
- No horizontal displacement of any component (`sea.md` §7.3).

## 4. Shading

### 4.1 Normal
```
n_geo    = vertex normal, plus the per-pixel slope of faded components (tiers M and H)
detail   = 2 to 4 layers of a tiling normal map, sampled in a wind-aligned frame (downwind, across):
           uv_k = rot(angle_k) * scale_k * (dot(p, dir) - drift_k * t, dot(p, perp(dir)))
           dir = the median wind's downwind direction (base_from + π), so the pattern does not swirl in shifts
           scales 1/13 m, 1/22 m, 1/48 m, 1/70 m; drifts 1.4, 1.0, 0.9, 0.6 m/s; angles 0, 0.35, -0.6, 0.95 rad
           break the tiling
m        = wind factor at the pixel (§4.3)
k_detail = 0.32 * clamp(m * base_speed / 7.2, 0.15, 1.6) * fade(dist; 300 m -> 1, 3 km -> 0)
n        = normalize(n_geo + k_detail * (detail.x * wind_to + detail.y * perp(wind_to)) in the water plane)
```
The normal map (256², tiling) and the foam noise are generated at load from Godot's seamless noise
(`FastNoiseLite`, bump to normal map), so no texture files ship. Under 1.5 m/s of wind (`m·base_speed`) the
detail fades out (fully gone at 0.5 m/s): glassy water.

### 4.2 Colour, Fresnel, reflection
Godot's PBR does the lighting; the shader sets:
```
crest    = clamp(eta / max(sum_a, 1e-3), 0, 1)
ALBEDO   = mix(deep, shallow, 0.55 * crest), then foam (§4.4)       // deep (0.010, 0.048, 0.085), shallow (0.025, 0.20, 0.24), linear
SPECULAR = 0.35                                                      // Godot's F0 = 0.16·SPECULAR² = 0.02, water at normal incidence
ROUGHNESS = 0.06 + 0.05 * clamp(m - 1, -0.4, 0.25) / 0.25 + 0.18 * fade_far(dist)   // rougher in puffs and far away
EMISSION = sss * crest * pow(max(0, dot(-view, sun)), 3) * 0.9 + sss * crest * 0.12  // light through the crests, sss (0.04, 0.40, 0.38)
```
- **Sky reflection** comes from the scene's sky radiance through PBR (Schlick Fresnel: 2 % looking straight down,
  most of the sky at grazing angles), so the water takes the sky's colour at every time of day and weather.
- **Slope contrast**: a zero-mean correction `(sky(reflect(n)) − sky(reflect(up)))·F·(1 − foam)` added to `EMISSION`,
  with `sky(d)` a two-colour horizon-to-zenith ramp matching the sky, makes wave shapes readable without brightening
  the sea overall.
- **Boats and marks in the reflection**: screen-space reflections on tier H only; elsewhere the sky alone.
- **Sun glitter** is the PBR specular on the detail normals.
- **Fog** blends to the sky's horizon colour with distance; the detail normals flatten between 2 and 4 km.

### 4.3 Wind on the water
The gameplay puffs and lulls are drawn exactly where they are, from the same patches and profile as the core:
```
m = 1
for each patch j:
    dx = wrap_tile(xl - puff[j].x) ; dy = wrap_tile(yl - puff[j].y)          // wind.md §6.4
    r2 = dx*dx + dy*dy ; R2 = puff[j].R^2
    if r2 <= R2: m *= 1 + puff[j].es * (1 - r2 / R2)
m = clamp(m, puff_cap_lo, puff_cap_hi)
```
A puff (`m > 1`) is rougher and so darker (it mirrors less bright horizon), a lull (`m < 1`) smoother and brighter.
The effect is also made explicit so it reads from the aerial camera and in flat light:
```
ALBEDO *= 1 - k_puff * clamp((m - 1) / 0.25, 0, 1) + k_lull * clamp((1 - m) / 0.4, 0, 1)    // k_puff 0.25, k_lull 0.15
```
Venues with a wind field (`wind.md` §8): the land-effect speed factor `f` multiplies `m` after the
puff clamp (the caps bound the puffs, not the venue). The CPU keeps the eight sector grids of the venue file
and uploads the two around the current direction (`k0`, `k1` of `wind.md` §8, from `global_from`) as one RG32F
texture (R = `k0`, G = `k1`, texel (i, j) = node (i, j)), again only when the pair changes; the blend weight `tw`
is a uniform every frame. The vertex shader samples it with `texelFetch` and exact bilinear weights like the
exposure, 1 outside the grid, and passes `f` to the fragment shader, so the drawn factor equals the core's to
float rounding at the vertices. The direction offset `d` does not show on the water and is not drawn.

### 4.4 Whitecaps
```
tws_local = m * base_speed / KNOT                              // kn
caps  = smoothstep(8, 24, tws_local)
n1    = foam texture streaks along the wind (23 m along, 5 m across), n2 = coarse breakup noise (61 m)
th    = 0.62 - 0.30*caps
foam  = smoothstep(th, th + 0.1, crest * (0.45 + 0.75*n1)) * smoothstep(0.25, 0.65, n2) * (0.2 + 0.8*caps) * fade(dist; 1.3 km)
ALBEDO = mix(ALBEDO, (0.86, 0.90, 0.92), 0.8 * foam) ; ROUGHNESS = mix(ROUGHNESS, 0.65, foam)
```
So whitecaps come with the wind, more of them in the puffs. With the reference seas this covers about 0.2 % of
the water at 15 kn, 1.4 % at 20 kn and 2.5 % at 25 kn, close to measured whitecap cover (it rises with about the
3.4th power of the wind speed).

## 5. Bow waves, wakes and spray

Per boat, a **wake ribbon**: a strip of the water laid down behind the bow and left where it was laid, which opens
into the V of the wake and fades. It is visual only and runs per rendered frame on the render clock.

**Emission** (every `dt_e = 50 ms` of render time, at most once per frame):
```
stem point P  = boat pose applied to the bow end of the waterline, lowered or raised so it sits 0.1 m above the sea
v             = speed of the stem point over the ground since the last emission (from positions, m/s)
V_ref         = 1.34 * sqrt(lwl / 0.3048) * KNOT            // hull speed, m/s
ratio         = v / V_ref
if the bow point is more than 1 m above the sea (a bow out of the water on a wave): emit an invisible row
row = { frozen boat frame (heading, heel), P, v, age 0, alpha 1,
        w0 = 0.35 * bwl * min(1, ratio + 0.2),               // half width at the bow
        spray: two particles, port and starboard }
push the row into a ring buffer of N = 80 rows (a 4 s ribbon)
```
**Each frame**, for every row of age `t` (a row is drawn with 15 vertices across: a feathered, transparent outer
vertex `0.3 + 0.25·w` outside each edge, and 13 from edge to edge, so it follows the waves between its edges):
```
half width  w = w0 + 0.354 * v_row * t                       // edges open at the Kelvin angle, tan 19.47°
edges       = row point ± w across the frozen heading, each draped on the drawn sea + 0.1 m (in the vertex shader,
              with the sea's uniforms and grid fade) and pulled toward the camera along the view ray (the pixel
              stays, only the depth moves) far enough to clear the sea by h_c = 0.15 m + 2 Σ a_i·w_i·(1 − fade_i(1 m))
              (the short waves the sea grid carries but the ribbon, flat between its vertices, does not):
              pull = min(h_c / sin(elevation of the view), 0.3 · distance), so the sea's facets never cover it
alpha       = (1 - t / 4 s) * min(1, ratio_row * 2)          // fades with age, faint at low speed
texture v   = distance sailed at emission / 10 m              // foam texture along the ribbon
the row drifts with the surface current at its point (wind.md §7)
```
**Spray** (quality H, and M for the own boat): each row launches two particles from its edges with speed
`k_s·ratio²·pulse` (`k_s = 2.5 m/s`), direction 0.6 outward and 0.8 up in the boat frame, kept within 10° of the
vertical when heeled, `pulse = max(0.01, 1 − (0.3·sin(0.07a + 1) + 0.4·sin(0.5a) + 0.4·sin(0.3a)))` with `a` the
distance sailed times 1 rad/m plus a random offset per boat, so the spray comes in bursts. They fly under gravity,
stick where they reach the surface and become the ribbon's outer vertices (pushed out to the particle's distance
from the row, flying or landed, never inside the edge, so the strip does not fold; that reach is smoothed over the
four rows either side with triangular weights, so the outer edge has no steps from row to row): the sheet of spray
thrown off the bow lands and spreads into the wake.

A second, narrower ribbon from the **transom** (`w0 = 0.4·transom width`, no spray) gives the stern wake. On tiers
M and H every ribbon is also drawn into a camera-centred **wake normal buffer** (RG8, 512 × 512 over 400 m, cleared
each frame) as a normal disturbance that the sea shader adds to its detail normal, so wakes also ripple the
reflections. The buffer is a sub-viewport with its own world (the ribbons' meshes shared), so the scene's cameras
need no layer setup. Quality: all boats within 400 m (H), own boat and 6 nearest (M), own boat only (L).

## 6. Overlays drawn on the water

Drawn in the sea shader from uniforms (or as decals) with widths that grow with distance so they stay visible: the
start line ribbon (`hud.md` §9.3), laylines (`hud.md` §6), gate lines, the zone circle (`hud.md` §7), and the wind
shadow view (`hud.md` §3.3, from the core's shadow zones). Their colours come from the HUD palette (including the
colour-blind palettes).

## 7. Quality tiers

| | L (low-end, integrated GPUs) | M (Steam Deck default) | H (desktop) |
| --- | --- | --- | --- |
| radial grid `N_r × N_s` | 120 × 160 (19 k vertices) | 180 × 256 (46 k) | 260 × 384 (100 k) |
| components in the vertex shader | all | all | all |
| per-pixel slope of faded components | no | yes | yes |
| detail normal layers | 2 | 3 | 4 |
| puffs and lulls (§4.3) | yes (gameplay information) | yes | yes |
| whitecaps | yes, one texture | yes | yes |
| wake ribbons | own boat | own + 6 nearest | all within 400 m |
| spray particles | no | own boat | yes |
| wake normal buffer | no | yes | yes |
| screen-space reflections | no | no | yes |

Budget: the water within 2.5 ms of GPU time per frame on the Steam Deck at 1280 × 800 on tier M. The vertex work is
small (22 cosines per vertex, 1 M per frame on tier M); the pixel work is dominated by the normal-map taps and the
puff loop (at most 10 patches). Every tier renders with Godot's Forward+; tier L also works on the Mobile renderer,
and nothing in §3–§6 needs compute shaders, so a Compatibility (web) port stays possible.

## 8. Options compared

| | our own (this spec) | GodotOceanWaves (2Retr0) | godot4-oceanfft (tessarakkt) | Boujie water shader |
| --- | --- | --- | --- | --- |
| licence | ours | MIT | MIT | MIT |
| method | `sea.md` sum of up to 22 travelling waves, analytic in the vertex shader | Tessendorf FFT on the GPU (compute shaders), several cascades, JONSWAP/TMA spectrum, Jacobian foam, spray particles | Tessendorf FFT (compute shaders), quadtree CDLOD surface, buoyancy by GPU readback | Gerstner waves in a vertex shader, prefab ocean scenes |
| Godot | 4.6, any renderer | 4.3+, Forward+ (RenderingDevice compute) | 4.3+, compute | 4.1+ |
| boats on the waves players see | yes, by construction (same function, `sea.md` §7) | no: the FFT field cannot be evaluated by the core, so physics and picture diverge; a readback would make online play non-deterministic | only through its own GPU buoyancy, not our deterministic core | no (Gerstner moves the surface sideways, against `sea.md` §7.3) |
| look at our sea states (0.2–0.7 m wind sea, some swell) | good with detail normals, foam, wakes | excellent, best for open-ocean storms | good, work in progress | fair |
| low-end cost | lowest (no compute, no textures to update) | cascade FFTs per update, amortised over frames | FFT + quadtree | low |
| web / Compatibility | possible | no (compute) | no | yes |
| state | to build | mature, 3.3 k stars, last change 2025-04 | early, last change 2025-11 | stable |

**Recommendation: build our own renderer on the `sea.md` contract.** It is the only option where the boats sit on
the waves players see, which online racing needs, and it is the cheapest on the Steam Deck. From GodotOceanWaves
(MIT) take ideas, and code only with a `docs/THIRD_PARTY.md` row: its GGX-based water lighting, the mix of bicubic and
bilinear filtering of the detail normals by pixel density, and its spray billboards. Revisit an **FFT detail layer**
later for tier H only: one small cascade (about a 64 m tile, 128²) used for normals and foam only, never for height,
which the contract allows. godot-realistic-water (godot-extended-libraries) was left out because its licence is not
stated clearly.

## 9. Tests

1. **Height parity**: a CPU mirror of the shader (§3.2, all `w_i = 1`) in double precision matches the core's
   `sea_height` within 1 mm at tick times, at points up to 8 km from the origin and at times up to 4 hours
   (`sea.md` §8 test 5).
2. **Far-field fade**: for the reference sea states (fetch 10 km at 10, 15, 20, 25 kn; plus a 0.8 m swell) and every
   tier, the typical height removed by the fade (2σ of the faded components) at distances up to 3 km from the
   camera is below 3 px of the tier's reference screen (L 720, M 800, H 1080 lines, 60° vertical field of view).
   Measured: at most 2.8 px (tier L, 25 kn, 25 m), 1 to 2 px from 10 to 100 m on M and H, under 1 px beyond 200 m.
3. **Puff parity**: the shader's `m` (CPU mirror) equals `wind.md` `puff_factor` within 1e-3 over a 2 × 2 km grid
   at 100 random times, including points across the tile wrap.
4. **Exposure parity**: the exposure texture sampled at 10 000 random points equals the grid sampler of `wind.md`
   §8.1 within 1e-3.
5. **Land factor parity**: the CPU mirror of `wind.md` §8 on the venue file equals the core's clean wind over its
   base speed (puffs off) within 1e-3 at 2000 random points over eight directions, and the shader's texture path
   (float32 emulation on the uploaded texture) equals the mirror within 1e-3; the texture follows the wind into the
   next sector.
6. **Wake geometry**: a boat at a steady 3 m/s: the ribbon's half width 2 s behind the bow is `w0 + 2.12 m` (±5 %),
   and its rows stay where they were laid (no drift without current).
7. **Offline renders** (headless, to image files) of fixed seeds: flat calm, 10 kn, 20 kn with puffs, from the
   chase and aerial cameras, compared against stored images for visual regressions. Godot's headless mode has no
   renderer, so these run the shared shader functions (`sea_common`, `sky_common`, `wake_common`) with the
   uniforms and meshes the engine computed on an offscreen OpenGL context (`game/tests/water_preview.py`); the
   engine's own picture needs a short windowed capture.
8. **Performance**: tier M water pass under 2.5 ms on the Steam Deck in the 20 kn scene with 12 boats.
