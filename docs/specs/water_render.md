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
components sorted by wavelength lam_i = 1/|(kx_i, ky_i)|, longest first (once per sea; §3.2)
uniform comp_lam[i] = lam_i                                              // float array, once per sea
for each sea component i (sea.md §3; at most 10 + 4·3 = 22):
    d_i' = frac(c_i - fmod(t_r, T_i) / T_i + kx_i*ox + ky_i*oy)          // double, then to float
    uniform comp[i] = (a_i, kx_i, ky_i, d_i')                            // vec4 array
uniform n_comp, sum_a = Σ a_i, hs_eff = 4*sqrt(Σ a_i²/2)
for each live puff patch j (wind.md §9 puff_patches(t_r), at most 16; beyond 16 the strongest |e·s| are drawn):
    uniform puff[j] = (px_j - ox, py_j - oy, R_j, e_j * s_j)             // camera-relative
uniform puff_tile, puff_cap_lo = 1 - puff_cap_down, puff_cap_hi = 1 + puff_cap_up
uniform wind_to = unit vector the wind blows toward (global_from(t_r) + π), base_speed
uniform exposure texture (venue grid, R32F, texel (i, j) = node (i, j)) and its mapping, E default
uniform land texture (venue wind field, RG32F: the two sectors around global_from(t_r)), its mapping, tw (§4.3)
uniform detail layer offsets: the camera-origin part of the §4.1 texture coordinates, in double, mod 1
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
- The fragment shader re-evaluates the slope of the components the vertex grid faded (`w_i < 1`) per pixel on
  tier H, themselves faded by the pixel footprint (`fwidth` of the position) so they never alias, so
  distant water keeps its wave texture in the lighting:
  ```
  px  = pixel footprint, m (length of fwidth of the position)
  w_i = (1 - smoothstep(2, 4, lam_i / s)) * smoothstep(2, 4, lam_i / px)
  grad += w_i * a_i * TWO_PI * (kx_i, ky_i) * (-sin(TWO_PI * f))
  ```
  `w_i` is zero unless `2·px < lam_i < 4·s` (the first factor is 0 from `lam_i ≥ 4·s`, the second from
  `lam_i ≤ 2·px`), so only the components in that band are evaluated. The CPU uploads the components **sorted by
  wavelength, longest first** (every sum over them is order-independent), with each one's wavelength
  `comp_lam[i] = lam_i` (§2); the pixel loop skips the components with `lam_i ≥ 4·s`, stops at the first with
  `lam_i ≤ 2·px`, and returns at once when the band is empty (`2·px ≥ 4·s`, or every component at least `4·s`
  long). The result equals the sum over every component up to float rounding.
- A later option for tier H, if the near field needs it: a small fine patch (say 64 m at 0.25 m) under the
  camera, blended into the radial grid.
- No horizontal displacement of any component (`sea.md` §7.3).

## 4. Shading

### 4.1 Normal
```
n_geo    = vertex normal, plus the per-pixel slope of faded components (tier H; §3.2: only the
           components in the band 2·px < lam < 4·s, from the wavelength-sorted comp and comp_lam)
detail   = 2 to 4 layers of a tiling normal map, sampled in a wind-aligned frame (downwind, across):
           uv_k = rot(angle_k) * scale_k * (dot(p, dir) - drift_k * t, dot(p, perp(dir)))
           dir = the median wind's downwind direction (base_from + π), so the pattern does not swirl in shifts
           scales 1/13 m, 1/22 m, 1/48 m, 1/70 m; drifts 1.4, 1.0, 0.9, 0.6 m/s; angles 0, 0.35, -0.6, 0.95 rad
           break the tiling; the layers are averaged
glint    = one more tap of the same normal map in the same frame: scale 1/3.2 m, drift 1.6 m/s, angle 1.25 rad
near     = 1 - smoothstep(30 m, 200 m, dist)
k_detail, k_glint = the strengths of §4.1.1 (wind roughness)
n        = normalize(n_geo + k_detail * detail + k_glint * glint, each as (x * wind_to + y * perp(wind_to)) in the
           water plane)
```
The glint layer is the ripples a few metres long that break the sun's reflection into glitter near the boats;
beyond 200 m the mip-mapped detail layers and a rougher surface (§4.2) carry it. It is the only texture tap the
daylight pass (WM-080) added, on every tier.
The normal map (256², tiling) and the foam noise are generated at load from Godot's seamless noise
(`FastNoiseLite`, bump to normal map), so no texture files ship. Under 1.5 m/s of wind (`m·base_speed`) the
detail fades out (fully gone at 0.5 m/s): glassy water.

#### 4.1.1 Wind roughness
How rough the water looks follows the local wind by the measured slope statistics of the sea surface (Cox and Munk,
1954, from the sun's glitter): the mean square slope of a clean sea is
```
U         = m·base_speed                         // local wind, m/s (§4.3: puffs, lulls and the venue's land effect)
sig2_all  = 0.003 + 0.00512·U                    // all waves, down to the capillaries
sig2_long = min(0.008 + 0.00156·U, sig2_all)     // a slick sea (an oil film damps the waves shorter than ~0.3 m)
sig2_short = sig2_all - sig2_long                 // the capillaries and short ripples: smaller than a pixel
```
At 8 kn that is a mean square slope of 0.024 (rms 8.9°), at 15 kn 0.042, at 25 kn 0.069 (rms 15°): a 25 kn sea has
three times the slope variance of an 8 kn one, and the extra is mostly in the short waves, which is what turns a
mirror into a rough, broken surface. The slope is split between what the picture can show and what it cannot:
- the **waves of the sea** (§3) carry `geo_var = Σ (2π·a_i/lam_i)²/2` (CPU, once per sea);
- the **detail and glint layers** carry the rest of the long waves, `sig2_d = max(sig2_long - geo_var, 0.3·sig2_long)`,
  0.6 of it in the detail layers and 0.4 in the glint layer near the camera, and the glint layer also the short waves
  the pixel resolves. With a saturated slope spectrum every octave of the short waves (0.3 m down to the capillaries'
  4 mm) carries the same slope, so the share smaller than the pixel footprint `px` is
  `sub = clamp(log(2·px / 4 mm) / log(0.3 m / 4 mm), 0, 1)` (about 0.4 at 1 cm, 0.75 at 5 cm, 1 from 15 cm):
  ```
  V        = mean of |rg·2 − 1|² over the normal map (CPU at load, about 0.118); N layers averaged have V/N
  k_detail = sqrt(0.6·sig2_d / (V/N)) · (1 − smoothstep(300 m, 3 km, dist)) · glassy
  k_glint  = sqrt((0.4·sig2_d + sig2_short·(1 − sub)) / V) · near · glassy     // glassy = smoothstep(0.5, 1.5, U)
  ```
- the **roughness** of the lighting carries the short waves under the pixel, and the share of the long waves the
  layers lose with distance (their fade, and the mip-maps averaging the map once the footprint passes their
  ripples):
  ```
  vis      = (0.6·(1 − smoothstep(300 m, 3 km, dist)) + 0.4·near) / (1 + (px / 0.25 m)²)
  sig2_r   = (sig2_short·(1 − (1 − sub)·near) + sig2_d·(1 − vis)) · glassy
  r        = sqrt(sqrt(sig2_r))                     // GGX alpha = r² = rms slope (Beckmann match)
  ROUGHNESS = clamp(r · (1 − 0.6·(1 − n_geo·v)⁶), 0.035, 0.6)
  ```
  The last factor is for Godot's lighting: its environment BRDF (the Lazarov/Karis approximation) dims the sky's
  reflection of a rough surface toward grazing far below a measured rough sea, which still reflects about half of
  what a calm one does near the horizon (at roughness 0.45 it would keep 0.19 of the calm 0.94); lowering the
  roughness only in the last few degrees above the horizon keeps the horizon band of §4.5 and leaves the sun's
  glitter (seen at steeper angles) as computed.
So an 8 kn sea is a mirror broken by ripples (roughness about 0.27 near the boats), a 25 kn sea is matte with a wide
sun glitter (about 0.4 near, 0.5 far away), and flat calm stays glassy (0.035). Godot's sky reflection is blurred by the
roughness and its Fresnel term falls with it (`F0 + (max(1 − roughness, F0) − F0)·(1 − n·v)⁵`), so the long bright sky
streaks of a glassy sea shorten and dim as the wind rises. Every tier uses it; it costs a few arithmetic operations
per pixel (a log and two square roots) from the uniforms `geo_var` and `detail_var`, no texture taps. The tiers keep their layer counts: the
`V/N` normalisation gives each tier the same slope variance.

### 4.2 Colour, Fresnel, reflection
Godot's PBR does the lighting; the shader sets:
```
crest    = clamp(eta / max(sum_a, 1e-3), 0, 1)
ALBEDO   = mix(deep, shallow, 0.55 * crest)                         // deep (0.006, 0.042, 0.115), shallow (0.012, 0.100, 0.155), linear (full sun)
SPECULAR = 0.40                                                      // Godot's F0 = 0.16·SPECULAR² = 0.026 (water 0.02, a little lifted)
ROUGHNESS = the wind roughness of §4.1.1                            // rougher in puffs, in a breeze and far away
EMISSION = sss * crest * (pow(max(0, dot(-view, sun)), 3) * 0.3 * sun_radiance + 0.05)  // light through the crests, sss (0.03, 0.33, 0.40)
```
- **Wind on the body colour** (round 4): in a strong breeze the sea looks greyer and darker, not the saturated blue of
  a fair-weather day. The water under a rough, aerated surface scatters more white from bubbles near the top and
  shows less of its deep blue, and its glossy blue reflections are broken up; Beaufort's own descriptions run from
  "blue" through "white horses" to "sea heaps up, foam blown in streaks". From 12 kn of local wind the body colour
  moves toward its own grey (its luminance) and darkens:
  ```
  gw     = smoothstep(12 kn, 30 kn, U)                // U = m·base_speed (§4.3)
  ALBEDO = mix(ALBEDO, luma(ALBEDO)·(0.75, 0.82, 0.88), 0.45·gw)        // 25 kn: about 30 % greyer, 10 % darker
  sss    × (1 − 0.35·gw)                                // less clear-water glow through the crests
  ```
  8 to 12 kn are unchanged; the sun, the sky, the exposure and the grade (§4.5, WM-080) are not touched.
- **Body colour**: a deep, saturated blue (about sRGB `#004684` from the aerial camera in the default light), a
  little greener on the crests; it is what the sea shows looking down, so it carries the race-day look. The
  conditions (§4.5) scale deep, shallow and sss about their luminance: `value · mix(luma, colour, saturation)`
  (`Daylight.sea_colors`, set on the sea by `Sea` from `SkyRig` every frame); 1 and 1 except overcast (0.5, 0.85),
  where the water under a grey sky is a dark slate blue-grey.
- **Sky reflection** comes from the scene's sky radiance through PBR (Schlick Fresnel: under 3 % looking straight
  down, most of the sky at grazing angles), so the water takes the sky's colour at every time of day and weather:
  with the saturated sky of §4.5 this is a gradient from the deep blue below the camera to a light blue band at the
  horizon. Clouds reflect too.
- **No slope contrast term** (removed in WM-080): its Fresnel taken from the full detail normal turned every steep
  detail facet into a white blotch at grazing angles; the PBR reflection of the stronger sky gradient shows the
  wave shapes by itself.
- **Boats and marks in the reflection**: screen-space reflections on tier H only; elsewhere the sky alone.
- **Sun glitter** is the PBR specular on the detail and glint normals with the wind roughness of §4.1.1: sharp
  sparkle in light air, a wide glitter path in a breeze, broader far away; the glow of §4.5 blooms the brightest
  glints.
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
A puff (`m > 1`) is rougher and so darker (it mirrors less bright horizon), a lull (`m < 1`) smoother and brighter:
the wind roughness of §4.1.1 takes the local wind `U = m·base_speed`, so a puff of 1.25 on 16 kn has the slope of
20 kn.
The effect is also made explicit so it reads from the aerial camera and in flat light:
```
ALBEDO *= 1 - k_puff * puff_k * clamp((m - 1) / 0.25, 0, 1) + k_lull * clamp((1 - m) / 0.4, 0, 1)    // k_puff 0.25, k_lull 0.15
```
`puff_k` is the conditions' factor (§4.5, 1 except overcast 2.4); the puffs' extra roughness comes from their wind
(§4.1.1) and is not scaled. Under a diffuse sky the albedo carries less of the picture and there is no glitter to
lose, so overcast strengthens the darkening to keep the puffs reading as well as in fair weather. Checked offline
(before the wind roughness of §4.1.1, when `puff_k` also scaled a fixed puff roughness; 2026-10-16, Practice Waters at 20 kn, 14:00,
each shot rendered with and without its puffs, the display luminance inside the puffs): aerial fair −9.4 %
(−0.030), overcast −9.2 % (−0.033); chase fair −2.6 % (−0.018), overcast −2.7 % (−0.021). Without the factor
overcast gave −4.0 % from the aerial camera.
Venues with a wind field (`wind.md` §8): the land-effect speed factor `f` multiplies `m` after the
puff clamp (the caps bound the puffs, not the venue). The CPU keeps the eight sector grids of the venue file
and uploads the two around the current direction (`k0`, `k1` of `wind.md` §8, from `global_from`) as one RG32F
texture (R = `k0`, G = `k1`, texel (i, j) = node (i, j)), again only when the pair changes; the blend weight `tw`
is a uniform every frame. The vertex shader samples it with `texelFetch` and exact bilinear weights like the
exposure, 1 outside the grid, and passes `f` to the fragment shader, so the drawn factor equals the core's to
float rounding at the vertices. The direction offset `d` does not show on the water and is not drawn.

### 4.4 Whitecaps
Foam belongs to the wave components: each component carries a foam value from its own travelling phase, so a cap
rides its crest, builds on its front and leaves a fading trail behind it. Caps appear where the crests of several
steep components meet (a wave group), so they come and go as the components run in and out of step, and their
number follows the local wind. (A first version thresholded a scrolling noise texture on crest height: hard white
blotches that popped on and off and slid over the waves; it was removed on 2026-10-03.)

**Off by default** (owner, 2026-10-05): in play the caps read as too many and as a uniform, repeating pattern,
worst from the helicopter camera, so the game draws none until a version that is sparse and non-repeating at every
camera height is approved. The look panel and `--caps=on` still turn the mechanism below on for judging it.

**Why the first version read as too many** (2026-10-15): its threshold let about a fifth of the water (22 % at 25 kn)
carry some foam, as faint lace over wide patches; the mean opacity matched the measured cover, but the eye counts the
area with any foam. And the sum of six crest windows tops out on a regular lattice (the beats of components of
nearly the same wavelength and direction), which from the helicopter is a grid of dots. The version below draws
the measured cover as the **area** of foam, nearly opaque where it is, and lets the waves break in groups.

**Why the second version drew foam sheets in the game** (2026-10-15, the engine clip at 25 kn): its group envelope
was **added** to the steepness sum, so where the envelope was high it lifted troughs and crests alike over the
threshold: white sheets tens of metres across near the boat and long bars further off (patches up to 50 m, 95 % up
to 27 m, measured on the same sea). The offline helicopter preview hid it (from 500 m the sheets read as clusters).
It was not the swell (the clip's sea had none), but a swell bigger than the wind sea's peak would have made it
worse: it was the "dominant" wave, with crest windows of 18 and 45 m. Now the envelope and a short-crest breakup
**multiply** the crest windows (foam stays on crests, a few metres long), only the wind sea carries caps, and the
law is calibrated on the foamed area.

**Cover law** (Monahan and O'Muircheartaigh, 1980, the fraction of the sea surface covered by whitecaps):
```
W(U) = 3.84e-6 · U^3.41          // U the local wind at 10 m, m/s: 8 kn 0.05 %, 12 kn 0.19 %, 15 kn 0.41 %,
                                 // 20 kn 1.1 %, 25 kn 2.3 %
```

**Wind sea only**: breaking whitecaps are wind-forced waves; a swell outruns the wind and does not break in deep
water. A component is wind sea when its phase speed `c_i = g·T_i/2π` is at most `1.2·U` (the wave age of a fully
developed sea, Pierson–Moskowitz), `U` the base wind; the others (the swell) take amplitude 0 for everything below:
they carry no foam and are never the dominant wave. The choice is made again when the drawn base wind changes by
more than 5 %.

**Per component** (CPU, once per sea, `SeaWhitecaps`, on the wind sea), with `lam_i` the wavelength, `k_i = 2π/lam_i`
and `lam_p` the wavelength of the largest-amplitude wind-sea component:
```
b_i       = a_i·k_i · min(1, lam_i/lam_p)²              // foam weight: steepness, waves shorter than the peak weighed down
sf_i      = max(0.08, 0.6 m / lam_i)                    // crest window half widths, cycles: ahead of the crest
sb_i      = max(0.15, 1.2 m / lam_i)                    //   and behind it (the trail)
mean_i    = mean over a cycle of W_i (below)
selected  = the 6 components with the largest b_i ≥ 0.004, heaviest first (tier L evaluates the first 4)
caps_w[j] = (1/sf, 1/sb, mean, lam) of selected j ; caps_rest = Σ b_i·mean_i of the components not selected
```
**Wave groups**: waves break where a group of them is highest, and a group travels at the group speed, half the
phase speed of its waves, so the crests run through it: a cap builds at the back of a group and fades at its front.
The six crest windows alone give groups on a regular lattice; a slow envelope breaks it up: the coarse channel (G)
of the wake foam noise (`foam_tex`, §5), mapped over a `GROUP_TILE = 600 m` square along the dominant wave and
drifting with it at the group speed `c_p/2` (features of about 100 m, a few groups of the peak waves), scales the
crests' steepness:
```
env = max(0, 1 + 0.5·(G − G_mean)/σ_G)          // g_amp = 0.5/σ_G
```
**Short crests**: our components are long-crested, so the crests of two of them coincide along a line tens of metres
long; a real whitecap breaks over a few metres of a crest. The same noise channel over `BREAK_TILE = 30 m` along the
dominant wave by `15 m` across (features of about 6 m), riding the dominant wave at `c_p` (so a cap keeps its piece of
crest), passes a crest's foam only where it is high:
```
brk = clamp((G_b − 0.55)/0.25, 0, 1), and 0.6 where the pixel cannot resolve it (mix by smoothstep(2, 4, 6 m/px))
```
**Crest segments, not lines** (round 6, 2026-10-16): with the windows, the groups and the 6 m breakup alone, whole
crests of the dominant wave broke in step across the sea, a line of caps, a line of nothing, like a zebra crossing
(from the air, runs of caps along a crest of 4 to 5 peak wavelengths). Real wind seas are short-crested: a breaking
crest segment is half to two peak wavelengths long, and neighbouring crests do not break in step. A third factor of
the same noise channel over `SEG_TILE = 45 m` along the dominant wave by `120 m` across it (features of about 9 m
across the crests, so neighbouring crests differ, and 25 m along them), riding the crests at `c_p`, passes a crest's
foam only on its segments:
```
seg = clamp((G_s − 0.5)/0.2, 0, 1), and 0.45 where the pixel cannot resolve it (mix by smoothstep(2, 4, 9 m/px))
S  ×= seg
```
Measured on the CPU mirror, 25 kn, fetch 30 km, a 1.2 km aerial window: the 99th percentile of crest-aligned runs of
caps fell from 4.4 to 2.2 peak wavelengths (18 kn: 1.0); the mask's power within 20° of the wave direction on the
ring 0.6 to 1.4 `k_p`, over the same for the caps moved at random across the crests, from 2.1 to 1.3 (18 kn 1.4). A
narrow peak at `k_p` itself remains: the caps sit on the crests of the dominant wave, which are long in a sea of ten
components.

The cap's surroundings (the trail, the residual foam, the darker face and the bubble glow) are measured relative to
the threshold, `xr = (S − S_b)/(0.25·S_b)`, and take `xs = min(x, xr)` plus the same lace and streak noise as `xj`:
with the segments multiplying `S` the thresholds of a sea can be small, and a fixed band below them (`x > −1.5`)
then lit whole bands of the wave's back.

**Calibration** (CPU, once per sea): the steepness sum `S` (below, every component resolved) times `env`, `brk` and `seg` at
65 536 points of a jittered grid over a 600 m square (one tile of the envelope), at time 0, gives its distribution; for each of the
four covers `W_k = 0.05, 0.2, 0.8, 3.2 %` the threshold `caps_thr[k]` at which the share of those points with
`F ≥ 0.5` (the whitecap area a photograph counts, as Monahan's data) equals `W_k` (bisection). So the cover follows
the law on any sea (a short fetch, a swell, an open ocean) without a per-sea tuning. It takes about 0.2 s of
GDScript on the development Mac, once per sea (at the race start, when the caps are turned on, or when the base wind
changes by more than 5 %).

Every frame: `caps_k[j] = (kx, ky, d', b)` of selected `j`, with the phase `d'` of `comp` (§2), the foam texture frame
`caps_uv = (e, u0, v0)` (`e` the travel direction of the largest-amplitude component, `(u0, v0)` the camera-origin
part of the texture coordinates below, drifting along `e` at that component's phase speed `c_p = lam_p/T_p`), and the
group frame `caps_grp = (g_amp, G_mean, ug, vg)` (the same along `GROUP_TILE`, drifting at `c_p/2`) and the breakup
frame `caps_brk = (ub, vb)` (along `BREAK_TILE`, drifting at `c_p`), in double, mod 1.

**Per pixel** (`wm_caps_intensity`, `wm_apply_caps`; `m` the drawn wind factor of §4.3, `E` the exposure, `px` the pixel
footprint):
```
U     = m·base_speed                                             // local wind, m/s
gate  = smoothstep(8, 10, U/KNOT)                                // no caps under 8 kn
fade  = 1 - smoothstep(1200 m, 2500 m, dist)                     // both 0: no further work
for each selected j:  d = signed cycles from the crest (fract of the phase, ahead > 0; for j > 0 the phase
                          bent by 0.5·(G_b − 0.5), the breakup noise below: straight crest lines cut straight
                          edges into caps)
                      W = exp(-(d/sf)²) ahead, exp(-(d/sb)²) behind, times 1 − smoothstep(0.3, 0.5, |d|)
                          (0 at the trough: a broad back window cut there drew a straight edge along it)
                      S += b · mix(mean, W, smoothstep(2, 4, lam/px))   // too short for the pixel: its mean
qd    = (dot(xl, e), dot(xl, perp(e)))
env   = max(0, 1 + g_amp·(texture(foam_tex, qd / GROUP_TILE + (ug, vg)).g − G_mean))
brk   = the short-crest breakup above, from texture(foam_tex, qd / BREAK_TILE + (ub, vb)).g
S     = E · (S + caps_rest + Σ b·mean of the selected beyond the tier's count) · env · brk · seg
x_c   = log2(W(U) / 0.0005) / 2                                  // 0..3 at the four calibrated covers
S_b   = caps_thr piecewise linear in x_c (extrapolated beyond the ends)
x     = (S − S_b) / (0.35·S_b)                                   // relative ramp (round 7)
ev    = the breaking event at this crest spot now (life cycle, below)
F     = min(clamp(x, 0, 1), ev) · gate · fade                    // active foam intensity
```
The crest windows travel with their components, so a cap moves with its crests; the sum only passes the threshold
where crests coincide inside a high group, and a cap builds and fades as they drift in and out of step and as its
crest runs through the group. Patches: in the chase view at 25 kn with a swell, median 1 m, 95 % under 4 m, the
largest about 11 m (real caps at 25 kn: 1 to 5 m, a trail of a few metres, rarely over 10 m). The
components the pixel cannot resolve count with their mean, so far away the caps thin out instead of aliasing.

**Look**: the foam texture (`SeaTextures.caps`, 256², RGBA8, tiling, generated at load) holds four nested density
levels as coverage: R sparse fizz (broken fine lace and a few longer filaments), G the lace net, B dense foam (thick
lace and a milky film), A near-solid white with a few holes; built from periodic cellular noise (exact tiling) with a
smooth warp that curves its borders, and seamless value noise for the breakup. It is mapped `4.5 m` along `e` by
`3 m` across, moving with the dominant wave. Mip-mapped, anisotropic: the mips average coverage, so a distant cap
fades to its true mean whiteness. With caps a few metres across and far apart the tiling inside them does not read.
**The life cycle** (round 7, 2026-10-16: the owner saw each cap as a rigid foam shape carried across the sea at the
wave's phase speed; whitecaps are events that happen, change and disappear with the wave). Two stages:

*Active breaking (stage A).* A patch of crest breaks once per event period `T_ev = 0.9·T_p` (dominant wave) for 0.4
of a wave period (1.7 s at 25 kn). The patch phase is a smooth field riding the crests, stretched across them
(`G` over 270 m along the wave by 900 m across, `caps_seg.zw`, lookup warped slightly by the local noise): along a
crest it changes by about 0.01 periods per metre, so an event's edges are soft and no band of phase shows on a cap,
while from one crest to the next it changes by most of a period, so neighbouring crests do not break in step and
the cover holds steady over any view. Each point joins its patch's event after a delay `dl` (from the local event
noise `G_ev`, features about 8 × 23 m, and the breakup noise: the break starts at a point and spreads) and parts
stop early by `ee` (from the segments' fine channel: a ragged end, and a ragged outline to the foam left behind).
The whole patch otherwise stops together; ending by a local phase left rings where the first points stopped while
later ones still broke. Where the pixel cannot resolve the spots, `ev = 0.15` (about the mean on-share; 0.35 drew a
grey blanket at the horizon).
```
ph   = fract(t/T_ev + 2·G_slow)                                   // caps_ev = (fract(t/T_ev), 1/T_ev, c_p, 3.5 s)
dl   = 0.06·clamp((G_ev − 0.35)/0.3, 0, 1) + 0.15·clamp((G_b − 0.3)/0.4, 0, 1)
ee   = 0.22·clamp((R_s − 0.3)/0.4, 0, 1)
ev   = smoothstep(dl, dl + 0.15, ph) · (1 − smoothstep(0.311 − ee, 0.444 − ee, ph))   // ph in event periods
```
(Two rejected phases: fine noise swept into thin streaks in the foam left behind; a phase from noise with a large
gradient, 8 periods over a 360 m tile, made the event a band of phase about 3 m wide, drawn as stripes and rings.)
The event gates the foam, not the steepness: the threshold is still set by the crests. Since the delay and early
end come from the same noise as the breakup and segments, the calibration weighs each point's `S` by the share of
the cycle its event is on (32 phases) and sets the threshold where the weighted share above `S_b·1.175` is the
cover. The core: `xj = x + 1.2·(L.g − 0.5)` (the lace riding the crest), `core = smoothstep(0, 3, xj) ·
smoothstep(0, 0.7, ev) · front · g`, `a = core·mix(0.85·mix(L.g, L.b, smoothstep(2, 5, xj)), 0.95·L.a, solid)`:
the lace net at the edges, dense foam inside, at most 0.85 opaque, and solid white only on `solid =
smoothstep(1.5, 2.5, xj) · band · smoothstep(0.55, 0.75, st)`, a band of ±0.03 `lam` at the crest (the tumbling
water) broken along its length by the streak noise `st`. Its brightness follows the event, so a cap fades in and
out instead of popping. `front = smoothstep(−4 m, −1 m, dm)·(1 − smoothstep(0.25·lam, 0.45·lam, dm))`: back to 0
before the trough, where `dm` jumps from `+lam/2` to `−lam/2` (a factor that differed on the two sides drew a
straight edge along the trough).

*Residual foam (stage B).* What a crest left stays in the water and moves only with the surface drift (`caps_drift
= 0.03·U` along the dominant wave), not with the crest: the crest runs ahead and the foam falls behind on the wave's
back, then decays and erodes. Analytically, at a point, for the last two passings of the heaviest component's crest:
```
tau    = time since that crest passed where this foam fell (x − e·drift·tau; one fixed-point step, the passing
         nearest the first guess)
A      = min(clamp(x(t − tau), 0, 1), ev_wide(t − tau))   // the active foam then: the potential at that time (the
                                                          // windows moved back by tau/T_j, the segments where the
                                                          // crest was, c_p·tau back, the breakup at its mean: the
                                                          // crest sweeps its fine detail into streaks along the wave,
                                                          // which the residual's own lace replaces), the event at any
                                                          // time within ±0.25 s of the passing
R      = max over the two passings of A² · exp(−tau / 3.5 s) · smoothstep(0, 0.6 s, tau)
         · (1 − smoothstep(1.5·T_0, 2·T_0, tau)) · (1 − smoothstep(300 m, 400 m, dist))
age    = 1 − exp(−tau / 7 s)
Lr     = texture(caps_tex, q/(5, 3) + caps_res.xy)                // the foam lace, drifting with the surface and
                                                                  // wandering slowly, so outlines change
cov    = 2·age < 1 ? mix(Lr.b, Lr.g, 2·age) : mix(Lr.g, Lr.r, 2·age − 1)   // dense foam, then the net, then fizz
blob   = texture(foam_tex, q/(16, 10) + caps_res.zw).g            // erosion blobs in the same drifting frame
a      = max(a, 0.6 · R · cov · smoothstep(th, th + 0.2, blob) · g),   th = 0.4 + 0.3·age   // breaking into fragments
```
It costs two more passes of the six-component loop and four taps each (breakup, segments, the two event-phase
taps; the breakup tap now comes before the loop, which it bends), evaluated within 400 m (fading out from 300 m) where the heaviest component is resolved, and two taps for
its lace and blobs; the stage A field two taps more than round 6 (the event phase).

*Around a breaking cap* (round 4, kept, now only while it breaks): `near = smoothstep(−0.8, 0.4, xj) ·
smoothstep(0, 0.7, ev)`; the face ahead is darker (`ALBEDO ×= 1 − 0.22·near·(1 − behind)·(1 − smoothstep(0.5 m, 3 m,
dm))`) and the bubble cloud behind lifts it slightly toward green-blue, broken like the foam and fading faster than
it (`mix(ALBEDO, (0.05, 0.20, 0.23), 0.1·near·behind·ev²·L.b)`, at most 0.1; 0.35 flat made bright turquoise pools),
with `behind = (1 − smoothstep(0, 1.5 m, dm))·smoothstep(−0.4·lam, −0.15·lam, dm)` (0 where `dm` is unresolved).
Then `ALBEDO = mix(ALBEDO, col_foam, a)`, `ROUGHNESS = mix(ROUGHNESS, 0.55, a)`, `EMISSION ×= 1 − a`, the normal toward
`n_geo` by `0.6·a` (no glints in foam).

Measured (CPU mirror, 25 kn, fetch 30 km, a 150 m window): one second on, the drawn foam moved on by `c_p` (6.8 m)
correlates 0.01 with itself (the steady caps of round 6: 0.95), its best-overlap IoU is 0.03 (0.30); residual foam
older than 1.5 s moves with the drift, not with the crests (`c_p` 6.8); active breaking at points riding the crests
lasts 0.5 s (median, round 7b), the residual patches (their lace aside) at points drifting with the surface 2.7 s;
the opacity changes by at most 0.10 per 60 Hz frame; the most opaque foam patch is 4 % opaque.

**Cover** (the area with `F ≥ 0.5`, every component resolved, on the reference wind seas of `sea.md` §2 at fetch
10 km) against the law, and the share of the water with any visible foam (`a > 0.1`): see the checks below, which
print both; the area with visible foam stays within twice the law (the first version: about ten times). Puffs and lulls change it through the local wind `U`, so caps show the puffs and a lull is almost free of
them.

**Cost**: one loop of 6 (tier L 4) components with a fract, an exp and a smoothstep each, from 12 vec4 uniforms with
a constant bound, two taps of the foam noise (group envelope, short-crest breakup), a `pow` and a `log2` for the
threshold, and one
tap of the foam texture where `F > 0`; nothing below 8 kn or beyond 2.5 km. The per-component windows are a few
metres wide, narrower than the vertex spacing at the chase camera's distance (1.5 m at 25 m, 6 m at 100 m on tier
M), so they are evaluated per pixel; what the vertex stage already has (exposure, venue factor) comes as varyings.
Measured with `tests/water_cost.py` (the development M1, OpenGL proxy, 1280 × 800): the helicopter view of the
25 kn open sea, where every water pixel runs the loop, +0.35 ms on tier L, +0.39 ms on M, +0.34 ms on H (round 7b;
round 7 +0.26, +0.28, +0.27 ms, with the residual foam within 400 m; round 6 +0.21, +0.23, +0.14 ms; round 5 +0.16 to 0.18, +0.21 to 0.24, +0.22 to 0.24 ms; runs vary by ±0.05 ms)
(the first version +0.10, +0.14, +0.10 ms on the same view; the runs vary by ±0.05 ms); the game's chase view at
25 kn +0.01 to 0.02 ms (round 7b). On the Steam Deck (about 0.6 of the M1's GPU) about
+0.65 ms on the helicopter view, inside the 2.5 ms of §7.

(Round 4 drew wind-aligned foam lanes between the caps; in the game they read as hundreds of short white dashes,
like rain over the sea, and were dropped on 2026-10-16.)

**Checks** (`tests/water_test.gd`, on the CPU mirror `SeaWhitecaps.intensity` and `SeaWhitecaps.drawn`): no caps under 8 kn (6 and 7.9 kn, and
a puff on a 7 kn breeze); cover never falling and rising over 10 to 25 kn, within ×1.3 of the law at 12, 15, 20 and 25
kn, on the fetch-10 km seas and on an open sea (fetch 30 km with a 0.8 m swell), tier L within ×1.6; the area with
visible foam (`a > 0.1`, active and residual) at most 4.5 times the active cover (residual foam covers several
times the actively breaking area); the drawn opacity is never one flat value
(over the foamed points its spread is at least 0.15) and the core is brighter than the trail; with a swell bigger than the wind sea's peak (25 kn with 1.2 m, 18 and 12 kn
with 0.8 m, 12 s): no swell component carries caps, cover within ×1.4 of the law, and in the chase view (0.5 m
cells over 200 m) 95 % of the patches at most 8 m and the largest at most 16 m (the second version: 27 and 51 m); more caps in puffs, fewer in lulls; no lattice: the autocorrelation of the foam
field at 25 kn over 512 m (8 m cells) rises nowhere more than 0.3 above its mean at the same distance (2 to 16 cells;
the first version 0.8, the six crest windows alone 0.7); each component's window equal after moving with its phase velocity;
the foam texture drifting with the dominant wave and the group envelope at half its speed; the life cycle (above): one second on, the foam moved on by `c_p` correlates under 0.4 with itself and its
best-overlap IoU is under 0.5; residual foam older than 1.5 s moves under a quarter of `c_p`; active breaking lasts
0.3 to 2 s (median, points riding the crests), residual foam 2 to 8 s (points drifting with the surface); the
opacity never changes by more than 0.15 per 60 Hz frame (the active foam seen riding, the residual seen drifting). No zebra crossing (an 800 m aerial window at 25 and
18 kn, fetch 30 km): caps linked along a crest (within 0.15 `lam_p` across and 0.6 `lam_p` along it) run at most 3
peak wavelengths (99th percentile; round 5: 3.8 to 5.0). No solid slabs (25 kn, six 150 m windows at 0.75 m): in every foam
patch of at least 20 cells under 30 % of the area is opaque (over 0.9); the bubble glow mixes at most 0.1 toward
green-blue.
Previews: `tests/previews/whitecaps_{12,18,24}kn_{chase,heli}.jpg` and `whitecaps_20kn_sequence.jpg` (6 frames 0.5 s
apart).

### 4.5 Daylight
Target look (WM-080): a bright, sunny, high-contrast racing day. A hard sun, a clear saturated blue sky (deep at
the zenith, light at the horizon) with a sun disc, a halo and a few fair-weather cumulus, deep blue water with a
strong sky-reflection gradient to the horizon and sun glitter, crisp light and shade on hulls and sails, and
shadows that are blue (lit by the sky), never black.

The daytime light (`SkyRig`) keeps sun and sky in their clear-day proportion: on a level surface the sun gives
about four fifths of the light and the sky the rest, and a white deck in full sun is about three times as bright
as the horizon sky; ambient and reflections from the sky; a distance haze toward the horizon colour (below).

**Time of day and conditions** (WM-124). The light has two independent inputs: the **time of day** (a local clock
hour, continuous, e.g. 14:30) and the **conditions** (clear, fair, hazy or overcast). The venue's look file gives
their defaults (data_format.md §6.11), the race may override them (`GameSetup.light_time`, `light_conditions`;
`--time=HH:MM` and `--conditions=` in the sail test), the look panel changes them live (hud.md §18). The light is
fixed for a race; `--light-advance=<rate>` (`GameSetup.light_advance`, game time per real time, 1 = real time)
lets the clock run. There is no night: the hour is clamped to the hours with the sun at least
`MIN_SUN` = 6° high on the venue's date.

- **Sun position** (`Daylight.sun_position`): from the hour, the venue's latitude and longitude (the venue file's
  `origin`), its UTC offset and its date (the look file), with the short NOAA formulas: the fractional year
  `γ = 2π/365 · (day − 1 + (hour_utc − 12)/24)`, the declination and the equation of time as the usual five-term
  Fourier series in γ, the true solar time `hour·60 + eqtime + 4·lon − 60·utc_offset` minutes, the hour angle
  `tst/4 − 180°`, then the elevation `asin(sin φ sin δ + cos φ cos δ cos ha)` and the azimuth (compass, clockwise
  from north) `atan2(sin ha, cos ha sin φ − tan δ cos φ) + 180°`. No refraction, no almanac: about 0.2° from the
  NOAA calculator (reference: Greenwich, 21 June, 12:00 UTC: 61.97° high, bearing 179.4°). World north is the venue
  file's north (scene −Z).
- **Hour keyframes**: the colours follow the **sun's elevation**, not the clock, so a venue's date and latitude set
  how the day looks. Two branches, morning (the sun rising: cooler, cleaner, a little more mist and fewer cumulus)
  and afternoon (warmer), each a table over the elevation, linear between its keys and held beyond them; around
  solar noon the two blend over three hours (`w_pm = smoothstep(−1.5 h, +1.5 h, solar time − 12 h)`), so the light
  is continuous through the day even where the sun never reaches 38°. At 38° and above both branches are the
  WM-080 midday: ACES, exposure 0.50 with sun 3.6, glow, cumulus.

  | branch, sun | sun colour | energy | sky horizon | sky zenith | exposure | haze × | clouds × |
  | --- | --- | --- | --- | --- | --- | --- | --- |
  | midday, ≥ 38° | (1.0, 0.92, 0.80) | 3.6 | (0.50, 0.74, 1.10) | (0.05, 0.18, 0.62) | 0.50 | 1.0 | 1.0 |
  | afternoon, 26° | (1.0, 0.86, 0.68) | 3.7 | (0.55, 0.72, 1.02) | (0.05, 0.175, 0.60) | 0.55 | 1.04 | 0.88 |
  | afternoon, 17° (late) | (1.0, 0.72, 0.44) | 3.8 | (0.60, 0.70, 0.94) | (0.05, 0.17, 0.58) | 0.60 | 1.083 | 0.75 |
  | afternoon, 12° (golden) | (1.0, 0.64, 0.34) | 3.7 | (0.74, 0.72, 0.76) | (0.07, 0.18, 0.54) | 0.66 | 1.13 | 0.72 |
  | afternoon, 6° | (1.0, 0.54, 0.24) | 3.3 | (0.86, 0.72, 0.58) | (0.09, 0.19, 0.50) | 0.78 | 1.25 | 0.70 |
  | morning, 26° | (1.0, 0.90, 0.78) | 3.6 | (0.50, 0.72, 1.08) | (0.05, 0.18, 0.63) | 0.54 | 1.10 | 0.70 |
  | morning, 17° | (1.0, 0.84, 0.66) | 3.6 | (0.56, 0.70, 1.00) | (0.055, 0.175, 0.60) | 0.60 | 1.20 | 0.50 |
  | morning, 12° | (1.0, 0.80, 0.58) | 3.5 | (0.62, 0.72, 0.95) | (0.055, 0.17, 0.57) | 0.65 | 1.28 | 0.45 |
  | morning, 6° | (1.0, 0.70, 0.46) | 3.2 | (0.72, 0.72, 0.86) | (0.06, 0.155, 0.50) | 0.76 | 1.40 | 0.40 |

  The afternoon 17° key is the former late-afternoon preset (a 20 m mast throws a 65 m shadow, the sails take the
  light across their faces, the sun's glitter is a path toward a camera that faces it); the exposure rises as the
  sun drops because a level surface gets less of it, so a low sun stays a little darker and warmer than midday,
  never dim. The haze and cloud columns are factors on the conditions' `haze max` and cloud cover.
- **Conditions** (`Daylight.CONDITIONS`), over the hour: the distance haze (WM-084's numbers), the cloud cover, a
  factor on the sun's energy, the sky and sun colours as a per-channel ratio to fair (the conditions' midday colours
  over fair's, so hazy midday is exactly the former hazy preset and a hazy evening a pale, warm one), a factor on the
  exposure, a factor on the drawn boat shadows (§4.7) and the grade's change (below); and (second table) the cloud
  deck's diffuse lighting, a factor on the sun shadows' blur (§4.6), the sea body colour's saturation and value
  (§4.2) and a factor on the puffs' darkening (§4.3).

  | conditions | haze begin, end, max, curve | clouds | sun × | sun colour at midday | sky horizon, zenith at midday | exposure × | shadow × |
  | --- | --- | --- | --- | --- | --- | --- | --- |
  | clear | 300 m, 16 km, 0.45, 0.42 | 0 | 1.0 | as fair | as fair | 1.0 | 1.0 |
  | fair (default) | 200 m, 14 km, 0.60, 0.40 | 0.40, cumulus | 1.0 | (1.0, 0.92, 0.80) | (0.50, 0.74, 1.10), (0.05, 0.18, 0.62) | 1.0 | 1.0 |
  | hazy | 150 m, 10 km, 0.80, 0.40 | 0.25, cumulus | 0.78 | (1.0, 0.95, 0.88) | (0.80, 0.88, 1.00), (0.24, 0.40, 0.74) | 1.10 | 0.85 |
  | overcast | 120 m, 9 km, 0.75, 0.40 | 0.88, a deck | 0.04 | (1.0, 0.98, 0.96) | grey: (0.60, 0.63, 0.67), (0.68, 0.71, 0.75) | 1.6 | 0.10 |

  | conditions | grey sky | deck diffuse | shadow blur × | sea saturation, value | puff × |
  | --- | --- | --- | --- | --- | --- |
  | clear, fair, hazy | no | 0 | 1 | 1, 1 | 1 |
  | overcast | yes | 1 | 4 | 0.5, 0.85 | 2.4 |

  Cumulus build through the day (the hour's cloud factor); the overcast deck does not (its cover stays 0.88, so a
  few thinner patches show). `haze max` is the conditions' times the hour's factor, at most 0.9. The haze colour is the
  horizon colour, as before.
- **Overcast** (owner decision 2026-10-16: real diffuse light). The sun is behind the deck, so the light comes from
  the sky: the sun keeps 0.04 of the hour's energy (at 14:00 at Practice Waters about a tenth of the light on a
  level deck, against four fifths on a fair day), the sky's grey ramp gives the rest as ambient light and
  reflections, and the exposure (× 1.6) brings the dimmer whole back up, with the bright grey sky the lightest thing
  in the picture. A **grey sky** does not take the hour's blue colours by ratio: its horizon and zenith are its own
  (brighter overhead, as an overcast sky is) times `Daylight.grey_sky_k`: `mix(white, hour's sun colour, 0.25) ·
  sqrt(clamp(sin(el)/sin 38°, 0.2025, 1))`, so the deck dims and warms a little as the sun drops. The deck itself is
  drawn **diffuse** (`cloud_diffuse` 1 in the sky shader): the ramp's colour from below, up to 22 % darker where the
  cloud is thick, no sunlit side, silver lining, disc or halo. With so little direct sun the boats' sun shadows are
  faint and, with the blur × 4 (§4.6), soft; the drawn shadows keep 0.10 of their full-sun strength (§4.7); the sea
  has no glitter, turns a dark slate grey-blue (§4.2) reflecting the grey sky toward the horizon, and the grade
  lowers contrast and colour (below). The puffs keep their contrast (§4.3). It is a flat, grey racing day, not a
  storm: no rain, no dark base.
- **Old names**: `--sky=clear|fair|hazy|late` stays as an alias. clear, fair and hazy set those conditions at the
  hour of the afternoon sun at 38° (the former presets' sun; solar noon where the sun never gets so high); `late` is
  fair at the hour of the afternoon sun at 17°.
- **Updates**: the sky shader has no `TIME`, so Godot only redraws the radiance map when a value changes. A change of
  hour or conditions sets every value at once and applies them in one pass. With `--light-advance` the clock moves
  in steps: at most every 5 s of real time and only once the hour has moved by a game minute; the grade's LUT is
  rebuilt when the hour has moved by 15 game minutes (about 40 ms of CPU, cached per light).

| venue | date | UTC offset | race window | default | conditions | typical | why |
| --- | --- | --- | --- | --- | --- | --- | --- |
| practice_waters | 25 Aug | +2 | 10:00 to 18:30 | 14:30, sun 51° | fair | clear, fair, hazy | a late-summer day on the northern Adriatic |
| garda | 20 Jul | +2 | 12:30 to 18:30 | 14:30, sun 61° | fair | clear, fair, hazy | the Ora fills from about midday and races run through the afternoon (the morning Peler from the north is a different wind, a venue matter) |
| solent | 5 Aug | +1 | 10:30 to 17:30 | 13:00, sun 56° | fair | fair, hazy, overcast | Cowes Week: starts from late morning |
| fremantle | 25 Jan | +8 | 12:30 to 18:00 | 15:00, sun 54° | clear | clear, fair | the Doctor arrives around midday in high summer; clear dry air |
| trieste | 11 Oct | +2 | 10:00 to 16:30 | 12:00, sun 36° | clear | clear, fair | Barcolana season; a bora clears the air, a low autumn sun |

In a **Random** weather race (race.md §2.1) the light is drawn from the race seed too: an hour in the venue's window
(30 min steps) and one of its typical conditions; Local and Custom take the venue's defaults. A rules scenario takes
the venue's defaults.

Colours are linear. With these the sunlit white of a hull or sail (albedo 0.8) lands just under display white
with its shading still visible, the sky between the zenith and 20° up is a saturated mid blue, and the horizon a
light blue, not grey.

- **Tone mapping**: Godot's ACES (white 6), not AgX: ACES keeps the saturation of the sky and the sea and gives the
  stronger contrast this look wants; AgX's desaturated highlights read as the washed-out haze we are leaving.
- **Sky** (`sky_common.gdshaderinc`): the two-colour ramp `mix(horizon, zenith, h^0.45)`, a darker sea haze below
  the horizon, forward scattering around the sun (`0.03·mu^8·(0.5 + haze) + 0.12·mu^64` of the sun radiance, so
  the sky stays blue a few tens of degrees from the sun), the sun disc (0.53°, 20 × the sun radiance) and a tight
  halo (`0.35·mu^2048 + 0.06·mu^256`, the disc and halo only in the background, not in the radiance map, where the
  light's own specular gives the glint).
- **Cumulus**: a layer projected on a plane above the camera (`uv = d.xz / (h + 0.06) · 0.55 + offset`), value
  noise: the two coarse octaves give the cloud masses, three fine ones their billowed edges; cover `c` sets the
  threshold (`smoothstep(1 − c, 1 − c + 0.16, n)`). One more look-up of the coarse octaves a little toward the sun
  lights the side of the cloud facing the sun (`sun · 0.40 + horizon · 0.25`) and leaves the far side and the base
  grey-blue (`mix(horizon, zenith, 0.35) · 0.85 + sun · 0.07`); thin edges toward the sun glow (silver lining);
  clouds fade into the horizon haze below 17°. Under overcast the deck is drawn diffuse instead (the
  Overcast item above). The sun disc and halo are drawn times `1 − 0.95·c` (hidden behind a
  cloud). The sky has no `TIME`, so Godot only redraws its radiance map when a value changes. On tier L the
  cumulus (the noise, the lit side and the silver lining) are drawn in the sky's half-resolution pass
  (`sky_l.gdshader`, a quarter of the sky pixels) and blended over the full-resolution ramp, haze and sun
  disc; the ramp and the disc stay sharp, the soft cloud edges are bilinear-filtered up. M and H draw every
  pixel in full.
- **Distance haze** (WM-084): aerial perspective, so far boats, marks and land fade softly toward the horizon and
  the race area reads with depth and scale. Godot's depth fog (`FOG_MODE_DEPTH`) toward the horizon colour: at a
  distance `d` from the camera the share of haze is `max · smoothstep(begin, end, d)^curve`. None on the near water
  (the own boat and its neighbours stay crisp), rising from a few hundred metres, flattening toward `max` at the
  horizon (the sea grid ends at 24 km). A curve below 1 makes it rise early. The share at a distance:

  | conditions (midday) | 500 m | 1 km | 3 km | 5 km | 10 km | horizon |
  | --- | --- | --- | --- | --- | --- | --- |
  | clear | 2 % | 5 % | 15 % | 24 % | 38 % | 45 % |
  | fair | 4 % | 9 % | 25 % | 36 % | 55 % | 60 % |
  | hazy | 9 % | 17 % | 42 % | 60 % | 80 % | 80 % |

  (The exponential fog it replaces gave fair 4 % at 1 km and 33 % at 10 km: the race area had almost no aerial
  perspective.) The fog's sun scatter stays 0.1 (the haze a little brighter looking toward the sun). The sky is not
  fogged (`fog_sky_affect` 0): Godot's fog on the sky is one colour over the whole dome and would wash out the
  zenith, and the sky already reaches the horizon colour at the horizon and has its own sea haze below it, so the
  hazed far sea meets the sky without a seam. No height fog, no aerial perspective from the radiance map. The
  offline previews (`tests/water_preview.py`, `course_preview.py`) draw the same curve.
- **Glow** on the brightest highlights only: additive, threshold 4.0 (linear radiance before the exposure: above
  the sunlit hulls, sails and clouds, below the sun disc and the glints on the water), HDR scale 2, intensity 0.5,
  normalized levels. Off on tier L, levels 3 to 5 on M, 2 to 5 on H (`SkyRig.apply_quality`).
- Boats cap their linear albedo at 0.8 and take their baked AO on the ambient and reflected light only; the sails
  keep their cloth (`sail_visuals.md` §11.1), which reads in this light without change.

**Colour grade** (WM-016.38, WM-124, `LookFx`): a recognisable film look over the final image, on top of the ACES
tone mapping, never instead of it: richer contrast, warm light, cooler shadows, a little more colour, changing with
the time of day (cleaner and cooler in the morning, neutral at midday, warmer through the afternoon, warmest at golden
hour) and the conditions. Godot applies it after the tone mapping on the display (sRGB) values through the
environment's colour correction, a 3-D LUT of 33³ texels (RGBA8, 144 kB) built from the formula below, one texture
read per pixel in the tone mapping pass that already runs (cost: nil to measure). Brightness, contrast and
saturation stay at 1. On a display colour `c` (0..1), with `L = c · (0.2126, 0.7152, 0.0722)` and
`chroma = max(c) − min(c)`:
```
y   = mix(c, smoothstep S-curve of c, contrast)                            // per channel, pivot mid grey
y  += cool · (1 − smoothstep(0.05, 0.45, L)) · smoothstep(0, 0.08, L)       // shadows, nothing at black
w   = smoothstep(0.25, 0.55, L) · (1 − smoothstep(0.80, 0.97, L))           // the light, neutral again at white
w  *= 1 − smoothstep(0.02, 0.20, c.b − c.r)                                // not on blue: sky and sea keep their colour
w  *= 1 − white_keep · (1 − smoothstep(0.03, 0.12, chroma)) · smoothstep(0.40, 0.60, L)   // white guard
y  += warm · w
y   = mix(luma(y), y, saturation), clamped to 0..1
```
The **white guard** keeps bright, nearly neutral colours (a white sail or hull in the sun, its lit shading) out of
the warm tint, so whites stay white at midday while the warm colours (a red hull, the deck, the skin of a sunlit
face) warm; blue (the sky, the sea) takes no warm tint, so the grade never greys the sky; at golden hour it lets go (`white_keep` 0.3) and the sails take the warm light. The grade follows the
same keys as the light (its morning and afternoon tables over the sun's elevation, the noon blend), then the
conditions:

| key | contrast | warm (r, g, b) | cool (r, g, b) | saturation | white keep |
| --- | --- | --- | --- | --- | --- |
| midday, ≥ 38° | 0.30 | (+0.040, +0.014, −0.036) | (−0.030, +0.004, +0.044) | 1.07 | 1.0 |
| afternoon, 26° | 0.30 | (+0.052, +0.018, −0.044) | (−0.030, +0.002, +0.046) | 1.08 | 0.9 |
| afternoon, 17° | 0.28 | (+0.066, +0.024, −0.052) | (−0.032, 0, +0.048) | 1.09 | 0.6 |
| afternoon, 12° | 0.27 | (+0.076, +0.028, −0.056) | (−0.034, 0, +0.050) | 1.10 | 0.4 |
| afternoon, 6° | 0.26 | (+0.084, +0.030, −0.060) | (−0.036, 0, +0.052) | 1.10 | 0.3 |
| morning, 26° | 0.28 | (+0.026, +0.012, −0.020) | (−0.034, +0.006, +0.050) | 1.05 | 1.0 |
| morning, 17° | 0.27 | (+0.030, +0.014, −0.016) | (−0.036, +0.008, +0.054) | 1.04 | 1.0 |
| morning, 12° | 0.27 | (+0.036, +0.016, −0.014) | (−0.038, +0.008, +0.056) | 1.04 | 0.8 |
| morning, 6° | 0.26 | (+0.044, +0.018, −0.012) | (−0.040, +0.008, +0.058) | 1.04 | 0.6 |

| conditions | contrast + | warm × | cool × | saturation × |
| --- | --- | --- | --- | --- |
| clear | +0.02 | 1.0 | 1.0 | 1.02 |
| fair | 0 | 1.0 | 1.0 | 1.0 |
| hazy | +0.06 | 0.9 | 0.9 | 1.0 |
| overcast | −0.06 | 0.3 | 0.5 | 0.90 |

**Grade strength** `k` (0 to 1.5, default 1; the look panel's row, `--grade=`): contrast, warm and cool times `k`,
saturation `1 + (s − 1)·k`; 0 is no grade (the LUT is skipped). At strength 1 a display value moves by up to about
0.12 (the old gentle grade: 0.06). Godot samples the LUT with the colour itself as the texture coordinate, so texel
`i` holds the grade of `(i + 0.5)/33`, and the end texels the grade of 0 and 1: black stays black and white stays
white. A white or light grey (`L` ≥ 0.6, chroma 0) at midday stays within 0.02 of neutral at strength 1.5.
`--look=off` in the sail test turns the grade, the contact shading and the depth of field off, to compare.

**No vignette** (owner decision 2026-10-11): no camera darkens the corners or edges of the picture, regular or clip;
there is no vignette layer, strength setting or flag. The colour grade is the only full-picture finish.

**Contact shading** (SSAO, tier H only): Godot's screen-space ambient occlusion, soft darkening where the deck meets
the rig, in the cockpit and under the boom: radius 0.8 m, intensity 1.6, power 1.5, detail 0.5, horizon 0.06,
sharpness 0.98, medium quality at half resolution, two blur passes, faded out from 40 to 150 m. It darkens the
ambient light only (light affect 0, AO channel affect 0), so the sunlit side stays as it is; Godot takes the minimum
of it and the material's AO, so the boats' baked AO (`WM-016.16`) and the SSAO never darken the same place twice. On
the water it touches only the small ambient share of the sea's light: the sky reflection, which carries the sea's
look, keeps its specular occlusion at 1 under a bright sky (Godot occludes reflections only where the occluded
ambient is dark), so the sea does not darken around the hulls or in the wave troughs. Expected cost on tier H: about
0.5 to 1 ms per frame on a desktop GPU at 1080p, 1 to 1.5 ms on an M1 at 2880 × 1800 at the default render scale
(to be measured with `--perf`, `--ssao=on|off`). Off on tiers L and M (the Steam Deck's water budget of §7 has no
room for it); `--ssao=on` tries it on any tier.

### 4.6 Shadows
The sun casts one directional shadow map, sized for a boat seen from the chase camera (24.5 m) and on board, not for
the whole race area: beyond the shadow distance the fleet is small on screen and its shadows would only add noise.

| | L | M | H |
| --- | --- | --- | --- |
| cascades | 1 | 2 | 4 |
| distance | 45 m | 90 m | 150 m |
| cascade edges | none | 45 m | 9, 39, 82 m |
| blend between cascades | no | no | yes |
| directional shadow atlas | 2048 | 2048 | 4096 |
| soft shadow filter | hard | low | medium |
| other boats cast | within 30 m of the camera | all | all |
| trees cast | no | yes | yes |
| the sea takes shadows | no | no | yes |
| boat shadows drawn on the sea (§4.7) | own boat | own boat and the 6 nearest within 90 m | no |

- The chase camera's own boat (about 15 to 35 m from the camera) lies inside one cascade on every tier, so its
  shadows never change resolution or cross a seam; on tier H on board the first cascade (9 m, about 5 mm per
  texel) carries the deck, the boom and the sails. On M the first cascade (45 m) carries both the chase and the
  on-board view, on L the single map does. The shadows fade out over the last 20 % of the distance (L: from 36 m,
  past the chase boat).
- **Cost** (WM-101, `PERFORMANCE.md` measured items 1 and 5): the shadow pass draws every caster again in each
  cascade it touches, and was about half of all draw calls (tier M at a 16-boat start: 256 of 548). So the low tiers
  use fewer cascades and a shorter distance: L one map over 45 m, M two cascades over 90 m (the menu's drift camera
  at 45 to 70 m, `menus.md` §4, stays inside it). The atlas is 2048 on L and M (a 4096 atlas is 32 MB of video
  memory, 2048 is 8 MB). L's filter is hard (one tap; the very low soft filter still takes several), and on L the
  trees (one mesh per island, `VenueView`, whose box usually reaches into the shadow map) and the other boats beyond
  30 m of the camera cast none: they are small on screen there and their shadows mostly fall on the water, which does
  not take them on L. The boats' casters are the boat view's (`SeaQuality` key `boat_cast_distance`); the venue's
  trees follow the tier (`VenueView.apply_quality`).
- Bias 0.1, normal bias 2.0 (Godot's scaled units, the same on every tier), pancake 30 m (a mast of 20 m with the
  sun at 38° stays inside the caster range), blur 1 times the conditions' shadow blur factor (§4.5: 4 under
  overcast, a diffuse sun's soft edge; no effect with tier L's hard filter). With a low sun the masthead lies far up the light ray from its
  shadow (68 m at 17°, 191 m at the lowest sun of 6°), beyond the pancake: Godot then clamps that caster onto the
  cascade's near plane (its depth only; an orthographic light keeps its outline), which still shadows every receiver
  in the cascade, so no setting changes with the time of day. The own boat's long shadows on the water are the
  drawn ones of §4.7 on tiers L and M (any sun above 3°; at 6° a 20 m mast's shadow is 190 m long and the drawn
  grid's 32 cells along it are 6 m each, still finer than the shadow's 0.7 m penumbra needs across it); on tier H a
  mast shadow seen from the chase camera fades out from 120 m (the last 20 % of the 150 m distance), so below about
  10° the tip of a long mast shadow on the water fades before it ends. **Low sun limit** (WM-124): the light never
  goes below `MIN_SUN` = 6° (the hour is clamped), and the venues' race windows end with the sun at 10° or more,
  where the shadow map's texels on a level deck are stretched at most 6 times (1/sin 10°) and the normal bias still
  covers them. Below 6° the stretch passes 10 times and the water on tier H and the decks would start to show
  shadow acne and stripes; the 6 to 10° band is the panel's (Time of day past the window) and is to be checked in a
  window on tier H.
- **Sails** (`sail_visuals.md` §11): their two cloth layers are 2 mm apart, closer than any bias can separate, so
  the sail shader draws the sail 5 cm away from the light along its normal in the shadow pass (only the layer
  facing the light is drawn there). Neither layer shadows itself or its twin, while the mast, the boom and the
  other sails still shadow it; the light through the cloth takes that shadow too (80 %), so the rig shows through
  a sail seen against the sun.
- **Sea**: the water's shadow only removes the sun's glitter and its small diffuse share (the sky reflection is
  not shadowed), which is what a shadow on water looks like. Only tier H draws it: a sea that receives shadows
  takes Godot's heavier light path on every water pixel, about 4 ms per frame on an M1 at 2880 × 1800 whatever the
  shadow distance and filter (owner decision 2026-10-01), so tiers L and M draw the boats' shadows on the water
  instead (§4.7). The sea, the wake ribbons, the spray and the drawn shadows cast no shadows.
- The atlas size and the soft filter are global rendering settings, applied with the tier (`SeaQuality.apply_shadows`
  through `SkyRig.apply_quality`, called by the Sea when its tier is set).

### 4.7 Drawn boat shadows (tiers L and M)
Where the sea takes no shadows, each nearby boat's shadow on the water is drawn instead: one small transparent mesh
per boat lying on the sea that darkens the water as a real shadow would. The boats still cast and receive the real
shadows of §4.6 on each other and on themselves; only the water's share is drawn.

**Which boats**: the own boat always; on tier M also the 6 nearest others within the tier's shadow distance (90 m)
of the camera, faded out over the last 20 % of it like the real shadows; on tier L the own boat only (its cost is
one draw call of a few hundred vertices and a short per-pixel loop, small next to the sea itself); tier H none (it
draws the real ones).

**Casters** (per frame, at the render pose, in scene space):

| caster | points |
| --- | --- |
| hull | the sheer outline of the physics sidecar (`perf_inputs.collision.outline`, 17 points, each at the height of the nearest vertex of the collision hull), and every 8th point of the DWL waterline (`waterline`) |
| mast | mast step and masthead (`rig`), as a strip of the mast width |
| each sail that is shown | its placed mid-surface (`sail_visuals.md` §9): luff and leech at the foot, a third, two thirds and the head row, and mid-chord at the foot, a third and two thirds (11 points) |

Each caster's points are projected along the sun direction `L` (toward the sun, unit) onto the horizontal plane
at the boat's heave `y0` (the render pose `z`): `p' = p − L·(p.y − y0)/L.y`, and the caster's shadow is the convex hull of
its projected points (a sail's twist and camber make it slightly larger than the true outline; the test below
bounds it). A polygon is kept as its edge lines `(n, c)` (outward unit normal and offset in the scene's `(x, z)`,
relative to the boat), at most 8 polygons and 96 edges. The **hull footprint**, the convex hull of the hull points
dropped vertically onto the plane, is kept the same way (at most 40 edges): water inside it is under the hull and is
never darkened, so the shadow never shows on the hull's sides at the waterline. Nothing is drawn while the sun is
less than 3° high.

**Mesh**: a 32 × 16 grid over the rectangle that holds the polygons and the footprint (one side along the shadow,
plus 0.5 m all round), draped on the drawn sea like the wake ribbons (`wm_drape`, lift 0.03 m, the same pull toward
the camera so the sea's facets never cover it), unshaded, multiplying the colour behind it, no depth write, depth
test on (the hull, deck and sails in front hide it), no shadows, no fog, drawn before the wakes and mist
(render priority −1), which take no shadows on tier H either. The grid moves by its transform only. All boats share
one material: each boat's polygons are one row of a small RGBA32F texture (160 texels: origin and fade, sun and
polygon count, footprint count, then the polygons, their bounding circles, the edge lines and the footprint's),
uploaded once per frame, and each grid instance names its row.

**Per pixel** (`boat_shadow_common.gdshaderinc`, also compiled by the offline preview):
```
P      = the water point (the draped vertex before the pull, interpolated)
r      = (P.x, P.z) − origin + (L.x, L.z) · (y0 − P.y) / L.y         // along the sun ray to the plane
d_k    = max over the edges of polygon k of (n · r − c)               // signed distance, exact inside
f_k    = 0.03 m + 0.0047 · h_k / L.y + pixel footprint                // half penumbra: the sun's 0.53° disc over
                                                                     // the mean height h_k of the caster's points
s      = max over k of (1 − smoothstep(−f_k, f_k, d_k)) · strength    // union; strength = the distance fade
s     *= smoothstep(−0.04, 0, d_footprint(P))                        // not under the hull
colour = colour behind × mix(1, keep, s)
```
`keep` is a fixed factor, the uniform `shadow_keep = (0.76, 0.66, 0.70)` (linear), matched in the engine to the
real shadow of tier H: the same race frame (seed 7, chase camera, 10 boats, 2026-10-01) rendered with and without
shadows, the per-pixel ratio inside the shadow (linear, median): real (0.72, 0.59, 0.68), luminance 0.61; drawn
(0.63, 0.58, 0.68), luminance 0.60. On this water a shadow removes the sun's diffuse light through the green-blue
water body, so it reads darker and slightly violet-navy rather than grey. A view-dependent `keep` built from the
§4.2 lighting terms was tried first and dropped: under the bright day of §4.5 it came out far too dark in the
engine (luminance 0.26 to 0.42) because Godot's light on the sea is not that model. Recheck the factor when the
daylight of §4.5 or the water colours of §4.2 change. Under weaker sun the drawn shadow is fainter as the real one
is: `shadow_keep` is `mix(1, keep, shadow)` with the conditions' shadow factor (clear and fair 1, hazy 0.85,
overcast 0.10, the sun's share of the light under the deck; `Daylight.CONDITIONS`), set by `BoatShadows` when the sky's light changes.

**Cost**: the per-boat geometry (about 70 points projected, five convex hulls) runs in the GDExtension
(`BoatShadowShape`, with the GDScript reference `BoatShadows.build`); with the sails' outline read natively
(`SailShape.mid_points`) a boat costs about 0.01 ms of CPU (0.1 ms for 10 boats, measured headless by test §9.10);
the GPU draws one 32 × 16 grid per boat with a loop over at most 96 edges, skipping polygons by their bounding
circle, on the pixels of its rectangle.

## 5. Wakes and bow spray

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
push the row into a ring buffer of N = 180 rows (a 9 s ribbon)
```
**Each frame** (the own boat; the other boats' ribbons at most 30 times a second, the frames' time added up,
since nobody sees a wake 10 m away move between two frames), for every row of age `t` (a row is drawn with 15
vertices across: a feathered, transparent outer
vertex `0.3 + 0.25·w` outside each edge, and 13 from edge to edge, so it follows the waves between its edges):
```
half width  w = w0 + tan(α) * v_row * min(t, 4 s)            // edges open at the wake angle α while the diverging
                                                              // waves break (their foam is gone well before 4 s)
wake angle  Fr = 0.399·ratio_row                               // hull Froude number v/sqrt(g·lwl) (hull speed: 0.4)
            α = min(19.47°, 0.1995 rad / Fr)                   // Kelvin's angle at low speed; at high Froude the
                                                              // apparent angle falls as 1/Fr (Rabaud and Moisy, 2013:
                                                              // α ≈ 1/(2·sqrt(2π)·Fr)): WM7 at 8 kn 19.5°, 15 kn 12°,
                                                              // 19 kn 9.5°
edges       = row point ± w across the frozen heading, each draped on the drawn sea + 0.1 m (in the vertex shader,
              with the sea's uniforms and grid fade) and pulled toward the camera along the view ray (the pixel
              stays, only the depth moves) far enough to clear the sea by h_c = 0.15 m + 2 Σ a_i·w_i·(1 − fade_i(1 m))
              (the short waves the sea grid carries but the ribbon, flat between its vertices, does not):
              pull = min(h_c / sin(elevation of the view), 0.3 · distance), so the sea's facets never cover it
alpha       = (1 - t / 9 s) * min(1, ratio_row * 2)          // fades with age, faint at low speed
age         = t / 9 s (COLOR.g)                               // the foam's breakup (below)
texture v   = distance sailed at emission / 10 m              // foam texture along the ribbon
the row drifts with the surface current at its point (wind.md §7)
```
**Spray reach** (quality H, and M for the own boat): each row launches two particles from its edges with speed
`k_s·ratio²·pulse` (`k_s = 2.5 m/s`), direction 0.6 outward and 0.8 up in the boat frame, kept within 10° of the
vertical when heeled, `pulse = max(0.01, 1 − (0.3·sin(0.07a + 1) + 0.4·sin(0.5a) + 0.4·sin(0.3a)))` with `a` the
distance sailed times 1 rad/m plus a random offset per boat, so the spray comes in bursts. They fly under gravity,
stick where they reach the surface and become the ribbon's outer vertices (pushed out to the particle's distance
from the row, flying or landed, never inside the edge, so the strip does not fold; that reach is smoothed over the
four rows either side with triangular weights, so the outer edge has no steps from row to row): the sheet of spray
thrown off the bow lands and spreads into the wake. The particles themselves are **not drawn** (small sprites read
as dots); what the eye sees is the mist and the bursts below.

**Bow wave** (not drawn): a sheet of water peeling off the stem into a foam crest was drawn on every tier until
2026-10-16; the owner found it read as a knife edge and the boats look better without it. Its crest still places the
bow spray and the mist (below), from the bow's drivers:
```
v, ratio  = the bow's speed and speed ratio of the last emission (above), smoothed over 0.3 s
plunge    = the bow sinking into the sea: max(0, -d(bow height above the sea)/dt), m/s, smoothed over 0.3 s
H         = min(0.08·lwl, 0.55·v²/(2g)) · (1 + 0.6·min(plunge, 1.5))          // crest height, m
L         = lwl · (0.18 + 0.22·min(ratio, 1.3)) · (1 + 0.3·min(plunge, 1.5))  // length along the hull
```
The crest runs aft from the stem along the hull (`σ = 0..1` of `L`), a crest width `(0.12 + 0.5·σ·L)·(1 + 0.3·ratio)`
off the hull at `τ = 0.45` of it, `0.75·H` above the sea.

**Mist** (quality H, and M for the own boat): soft spray clouds, never dots. They appear only above
`ratio = 0.55`, when the bow plunges, and in bursts when the bow meets a wave:
```
impact    = the bow sinking into the sea, as the plunge (the bow's height above the sea the front end evaluates,
            sea.md §7, so a bow meeting a wave face counts as much as one dropping off a crest), but quick:
            it follows a rise within 0.05 s and decays over 0.25 s
I         = clamp(impact / 0.6 m/s, 0, 2) · smoothstep(0.3, 1.0, ratio)          // the impact burst, 0..2
rate      = 14 /s · (clamp((ratio − 0.55) / 0.5, 0, 1) · pulse + 0.8 · clamp(plunge, 0, 1.5) + 3 · I)   // per boat
spawn     on the crest, σ = 0.05..0.35, the lee side twice as often as the windward side
velocity  outward (0.8..2.0)·ratio m/s, up 0.5..1.5 m/s (· (1 + plunge)), plus 0.7 of the boat's velocity
motion    drag exp(−2.5 t) on the velocity, gravity 2 m/s² (fine droplets fall slowly), life 0.8..1.3 s
size      0.5 m growing to (1.2 + 0.8·ratio) m over its life
alpha     0.16 · fade in over 0.12 s · (1 − age/life)² ; at most 256 sprites in the scene
burst     at impact I, each sprite launched is, with probability I/(1 + I), a sheet of droplets instead of mist:
          thrown outboard along the flare and a little aft, flat and fast, falling like water:
          velocity  outboard (2.5..4.5)·(0.5 + 0.5·min(ratio, 1.5))·(0.6 + 0.4·I) m/s, aft 0.15 of that,
                    up (0.8..1.6)·(0.5 + 0.5·I) m/s, plus 0.85 of the boat's velocity
          motion    gravity 9.81 m/s² (drops of a millimetre or more fall almost ballistically), drag 1.0/s,
                    life 0.35..0.6 s
          size      0.25 m growing to 0.6..0.9 m ; alpha 0.16 · min(1 + I, 2.2)
          look      droplets: the soft disc keeps only the high values of the foam noise (a speckle that thins
                    toward the edge), not a round cloud (wm_mist_alpha, kind 1)
```
Why: a hull section entering the water at a relative speed `w` throws a jet of several times `w` along its surface
(Wagner's wedge-entry result, the jet tip at about π/(2·tan β)·w, 4 to 5 times `w` for the 20° to 25° deadrise of a
sportsboat's forward sections); drag in the air and the breakup into droplets keep only a share of that. The
relative sink speed is what matters, so the same bow that rides the sea quietly bursts into spray when it overtakes
a wave and its stem meets the back of the next one; and a slow boat does not throw spray (the `ratio` term). The
bursts reuse the mist sprites and their cap: no other particle system. (A first version made the burst sprites
bigger and denser mist; in the engine that read as a round puff of smoke beside the bow.)
Each is a camera-facing quad with a soft round falloff broken up by the foam texture (`wm_mist_alpha`), unshaded
with the sky's horizon colour plus a share of the sun that grows looking toward it (forward scattering), faded where
it meets the water or the hull (depth fade over 0.6 m) and near the camera (under 3 m).

**Wake foam** (`wm_wake_alpha`): the foam of a real wake is not a set of even stripes. Two things make it:
- the **diverging waves** off the bow and quarters: their crests break into bands of foam along the wake's edges that
  start narrow at the bow and quarters and widen and soften as the waves spread away from the boat (round 4: the
  owner preferred these broad bands to thin lines), gone within a few boat lengths;
- the **turbulent wake** behind the hull: churned water about the hull's width, the widest and most lasting foam
  (tens of seconds behind a sportsboat at speed), which spreads slowly and, as the bubbles rise, breaks up into
  separate patches and streaks that thin and fade.

The bow ribbon draws the bands, the transom ribbon (below) the turbulent wake. Per vertex `COLOR.r` is the turbulent
band's half width over the ribbon's (1 on the transom ribbon; 0 on the bow ribbon), `COLOR.b` on the bow ribbon
`0.25 m / w` (so `w = 0.25/b`), on the transom ribbon the hollow behind a planing transom (below), `COLOR.g` the age.
With `s = |2u − 1| / 0.6` the distance across in half widths (1 at the edge vertex, beyond it the feathered margin),
`t = 9 s·age`, `n = 0.7·n1 + 0.5·n2` the fine foam noise (`n1` sampled in **world metres**, `world xz / 3 m`, so it
is never stretched across a wide ribbon into a comb; `n2` along the ribbon) and `p` the coarse patch noise (one tap
along the ribbon):
```
W       = 0.5 m + 0.55 m/s · t                              // the band's width, m: narrow at the bow, widening
bw      = W · b / 0.25                                      // in half widths
band    = s ≤ 1 ? smoothstep(1 − bw, 1 − 0.35·bw, s) · (1 − smoothstep(0.9, 1, s)) : 0   // soft, inside the edge
lace    = smoothstep(th, th + 0.35, 0.6·n + 0.4·p)          // th = 0.5 + 0.25·age: broken foam, thinning
bands   = band · lace · (1 − smoothstep(0.05, 0.38, age)) · 0.65 / (1 + 0.25·t)   // softer as it spreads, gone
                                                            // after 2 to 3 s (a few boat lengths at speed)
mid     = 1 − smoothstep(0.6·r, r, s)                       // the turbulent wake (hollowed when planing, below)
th      = 0.45 + 0.35·age                                   // the foam thins: more of it falls under the threshold
breakup = smoothstep(th, th + 0.4 − 0.25·age, 0.6·n + 0.4·p)   // and its patches get sharper borders
a       = alpha² · (bands + 0.9·mid·breakup)
```
Nothing is drawn beyond the edge vertex, so the spray reach (which pushes the outer vertices out, invisible) no
longer smears foam sideways into a comb of streaks (the first ribbons: a band out to 0.9 of the ribbon and texture
coordinates stretched over the spray's reach). The ribbons stop widening at 4 s, so the long tail adds rows but no
wide transparent area to the blending. Cost: the same three foam noise taps per wake pixel as before and a few more
operations; nothing in the sea shader.

**Planing: the hourglass.** Behind a planing transom the flow off the two quarters converges: right behind the
transom the water is hollow, the foam closes in to a waist and, past it, spreads again (and sometimes peaks in a small
rooster tail at the waist). The waist lies where the quarter flows meet, at a distance that scales with the
transom's Froude length `v²/g`; for a sportsboat it is half to one and a half boat lengths behind. Above a length
Froude number of about 0.8 the transom ribbon follows that profile, with `d = v·t` the distance behind the transom:
```
P       = smoothstep(0.8, 1.05, Fr)                         // Fr = 0.399·ratio; displacement speeds: off
x_w     = 0.7 · v²/g                                        // the waist: WM7 at 19 kn about 6.8 m, one boat length
pinch   = exp(−((d − x_w)/(0.5·x_w))²)
w       = w0·(1 + 0.15·t)·(1 − 0.55·P·pinch)                // narrows to under half at the waist, widens after
hollow  = P · (1 − smoothstep(0.3·x_w, x_w, d))             // COLOR.b: the centre right behind the transom is clear
mid    ×= 1 − 0.85·hollow·(1 − smoothstep(0.25, 0.75, s))   // foam on the converging sides only
alpha  ×= 1 + 0.3·P·pinch                                   // the waist is the brightest
```

A second ribbon from the **transom** (no spray) is the **turbulent wake**: `w0 = 0.45·bwl` (the hull's breadth near
the stern), widening slowly as the turbulence spreads, `w = w0·(1 + 0.15·t)` (to about twice the hull's width after
9 s), not at the wake angle. It emerges from under the transom: over the first `bwl` of distance sailed
(`v·t`) its alpha ramps in and its band narrows to 0.4 of its width at the start
(`k = smoothstep(0, bwl, v·t)`: alpha × k, `COLOR.r = 0.4 + 0.6·k`), so it has a feathered, rounded start instead of
a straight edge. On tiers
M and H every ribbon is also drawn into a camera-centred **wake normal buffer** (RG8, 512 × 512 over 400 m, cleared
each frame) as a normal disturbance that the sea shader adds to its detail normal, so wakes also ripple the
reflections. The buffer is a sub-viewport with its own world (the ribbons' meshes shared), so the scene's cameras
need no layer setup. Quality: all boats within 400 m (H), own boat and 6 nearest (M), own boat only (L).

## 6. Overlays drawn on the water

Drawn in the sea shader from uniforms (or as decals) with widths that grow with distance so they stay visible: the
start line ribbon (`hud.md` §9.3), laylines (`hud.md` §6), gate lines, the zone circle (`hud.md` §7), and the wind
shadow view (`hud.md` §3.3, from the core's shadow zones). Their colours come from the HUD palette (including the
colour-blind palettes).

Each line and circle has a width in metres on the water (`CourseView`: the start line 0.35 m, the laylines 0.22 m,
the zone circle 0.25 m) and is drawn at least 1.5 px thick on the screen, with its edge anti-aliased over 1 px. A
band on the water seen from a low camera foreshortens: its thickness on the screen, measured square to
the line's own screen direction, is its width on the water times
```
f      = sin e / sqrt((c·h)² + sin²e · (c×h)²)
c      = unit vector across the line in the water plane (the radial direction for a circle)
h      = unit horizontal direction from the camera to the pixel's water point; e: the view's elevation
```
(a line across the view is squeezed by `sin e`, a layline running away from the camera, `c ⟂ h`, not at all, and a
diagonal line almost like the cross one, since it projects to a nearly level screen line). So the 1.5 px are
converted to metres across the line through that factor,
```
px     = dist · px_angle / max(f, 0.002)             // metres across the line per screen pixel (px_angle: rad per pixel)
w      = max(width, 1.5 · px) ; a = 1 − smoothstep(w/2 − px/2, w/2 + px/2, d)
```
and not through the perpendicular pixel size alone: a far start line is then a fraction of a pixel tall and breaks
into a staircase of dashes, where it should be a thin steady line out to the haze (the distance fog applies to the
overlays as to the water).

Each line also carries an opacity and an optional dash (`Sea.set_overlay_lines`: `opacity`, `dash` in metres, 0 for
solid). The start, gate and finish lines are solid and opaque; the laylines are light and dashed, so they read as
guides and not as marks on the water: opacity 0.6, a dash period of 8 m along the line or 12 px where that is
longer (the along-line pixel size comes from the same foreshortening with the line's direction in place of `c`),
60 % of it drawn, the dash ends anti-aliased over one pixel.

A thin band on the water is also hidden by the wave crests just in front of it: from a camera `H` above the sea a
crest of height `a` hides `a / sin e` of water behind it, which at a few hundred metres is longer than the band, so
the line breaks into dashes that crawl as the waves pass, while the crests themselves are under a pixel tall and
invisible. So where the waves are small on the screen the overlay is tested not at the pixel's water point `xl` but
where the pixel's view ray meets the mean sea level, `xl · H / (H − η)` (`η` the pixel's height, `H` the camera's
height over the mean level): the crest pixel in front of the line then counts as the line, which stays a steady,
straight line as if drawn on the mean plane. Near the camera, where the waves are visible shapes, the ribbon rides
them instead: the two points blend by the waves' height on the screen, `k = 1 − smoothstep(2 px, 6 px, Σa / (dist ·
px_angle))`, from the mean-plane point (`k = 1`) to the water point (`k = 0`).

## 7. Quality tiers

| | L (low-end, integrated GPUs, Steam Deck default) | M (default) | H (desktop) |
| --- | --- | --- | --- |
| radial grid `N_r × N_s` | 120 × 160 (19 k vertices) | 180 × 256 (46 k) | 260 × 384 (100 k) |
| components in the vertex shader | all | all | all |
| per-pixel slope of faded components | no | no (owner decision 2026-10-01: about 3.5 ms on an M1 at 2880 × 1800) | yes |
| detail normal layers | 2 | 3 | 4 |
| puffs and lulls (§4.3) | yes (gameplay information) | yes | yes |
| whitecaps (§4.4) | the 4 heaviest foam components | the 6 heaviest | the 6 heaviest |
| wake ribbons | own boat | own + 6 nearest | all within 400 m |
| mist (and spray reach) | no | own boat | yes |
| wake normal buffer | no | yes | yes |
| screen-space reflections | no | no | yes |
| sun shadows (§4.6) | 1 map to 45 m, hard, 2048 atlas, no trees or boats beyond 30 m casting, no shadows on the sea | 2 cascades to 90 m, 2048 atlas, no shadows on the sea | 4 blended cascades to 150 m, 4096 atlas |
| boat shadows drawn on the sea (§4.7) | own boat | own boat and the 6 nearest within 90 m | no (real shadows) |
| automatic mesh LOD threshold (the boats, `sail_visuals.md` §11.4) | 2 px | 1 px (Godot's default) | 1 px |
| anti-aliasing | SMAA 1x | SMAA 1x | SMAA 1x |
| sky cumulus (§4.5) | half-resolution pass | full | full |

Anti-aliasing (WM-084, owner decision 2026-10-03: keep it simple): SMAA 1x on every tier, no per-tier choice
(FXAA only if SMAA turned out too costly for tier L; it did not need to). It is the project default
(`rendering/anti_aliasing/quality/screen_space_aa` = SMAA, so every scene starts with it) and `Settings.apply_render_scale`
keeps it on the root viewport with the upscaler (`Settings.screen_space_aa`). Godot runs it after tone mapping at
the 3D render resolution and before a spatial upscaler (FSR 1.0, MetalFX spatial), which wants an antialiased input,
so the render scale and SMAA go together. A temporal upscaler (FSR 2, MetalFX temporal, not used now) antialiases
by itself: with one SMAA is off, not stacked. No MSAA or TAA. SMAA smooths the edges of masts, stays, sheets,
sail edges and the horizon; like any post-process AA it does not stop sub-pixel crawl of lines thinner than a pixel
(far rigging), which the boat LODs and rope widths handle. Cost: the SMAA paper gives 1.02 ms for SMAA 1x at
1920 × 1080 on a GeForce GTX 470 (1.1 TFLOPS, 134 GB/s); scaled to the Steam Deck's 1280 × 800 (half the pixels)
and its GPU (1.6 TFLOPS, 88 GB/s) that is about 0.35 ms if arithmetic bound and 0.8 ms if bandwidth bound per
frame, on every tier (it does not depend on the scene); to be measured on the Deck.

The tiers do not set the render scale (`menus.md` §3): it is its own setting, Auto by default (67 % above
1920 × 1200 or on a HiDPI screen, else 100 %), and it scales every per-pixel cost here (the normal-map taps, the
puff loop, the sail cloth) by its square.

Budget: the water within 2.5 ms of GPU time per frame on the Steam Deck at 1280 × 800 on tier M. The Deck starts on
tier L (owner, 2026-10-05); the budget stays on M so a Deck player can choose M. The vertex work is
small (22 cosines per vertex, 1 M per frame on tier M); the pixel work is dominated by the normal-map taps and the
puff loop (at most 16 patches; the presets use at most 12). The per-pixel slope of the faded components (tier H) evaluates only the
components in the band `2·px < lam < 4·s` (§3.2), each with one sine and two smoothsteps from the uploaded
wavelength; the others cost a compare (the carried ones) or end the loop (the ones too short for the pixel). Every tier renders with Godot's Forward+; tier L also works on the Mobile renderer,
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
6. **Wake geometry**: a boat at a steady 3 m/s: the ribbon's half width 2 s behind the bow is `w0 + 2.12 m` (±5 %)
   and 6 s behind `w0 + 4.25 m` (it stops opening at 4 s), the ribbon lasts 9 s, and its rows stay where they were
   laid (no drift without current).
7. **Band loop**: the components the sea uploads are sorted by wavelength, longest first, `comp_lam` equals
   `1/|(kx, ky)|` of each, and the band loop of §3.2 equals the per-pixel slope summed over every component with the
   full weights (CPU mirror, random points, spacings and footprints).
8. **Offline renders** (headless, to image files) of fixed seeds: flat calm, 10 kn, 20 kn with puffs, from the
   chase and aerial cameras, compared against stored images for visual regressions. Godot's headless mode has no
   renderer, so these run the shared shader functions (`sea_common`, `sky_common`, `wake_common`) with the
   uniforms and meshes the engine computed on an offscreen OpenGL context (`game/tests/water_preview.py`); the
   engine's own picture needs a short windowed capture.
9. **Performance**: tier M water pass under 2.5 ms on the Steam Deck in the 20 kn scene with 12 boats.
10. **Drawn boat shadows** (§4.7, headless, the sail scene on the core): on tier M the own boat has a drawn shadow
    whose mesh lies on the water (its plane at the boat's heave, within 0.3 m of the sea height there), whose area
    lies away from the sun (the centroid more than 1 m from the boat against the sun's bearing), and whose coverage
    (the CPU mirror of the shader, s > 0.5) matches the projected silhouette of the drawn hull, rig and sails
    (every triangle above the water, rasterised on a 10 cm grid, outside the hull's plan) within an
    intersection-over-union of 0.75; on tier H there is none and on tier L only the own boat's. The native
    geometry equals the GDScript reference within 1e-4 m, and its cost per boat is printed.
