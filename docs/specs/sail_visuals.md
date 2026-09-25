# Sail visuals

How the front end bends and places the sails every rendered frame: belly that fills with the wind, twist, leech,
luffing and flogging, backing, hoisting and dropping, the spinnakers on their sprit or pole, and the normals.
Everything here is **presentation only**: it reads the sail outputs of the simulation (`sails.md` §7) and the
generated sail grids (`tools/boatgen/README.md`), and nothing feeds back into the core. It does not need to be
deterministic or bit-exact; the formulas below are the reference look and the tests at the end pin it down.

Frames and signs are those of `conventions.md` §3: boat body frame `x` forward, `y` port, `z` up; sail angle `β`
from the aft centreline, positive = sail on the starboard side; `awa` positive = wind from starboard; a drawing sail
has `sgn(β) = −sgn(awa)`. The generated model uses glTF axes `(X, Y, Z) = (y, z, x)` (a rotation, so every formula
below holds in either frame once the axes are mapped).

## 1. Principles

- The generator writes each sail **flat**, in the centreline plane `y = 0`, in its standard hoisted outline. The
  renderer keeps that flat grid as the rest shape and rebuilds the drawn shape from it every frame, per vertex, on
  the CPU: first a shape in the sail's own frame (§6, §8), then a rigid placement about the luff or the boom (§7).
- Shape comes from a few scalar drivers: the **fill** of the sail (from the sail angle and the wind line), the
  **luff shiver** intensity from the core, a **flutter phase** advanced with the apparent wind, the **backed**
  flag, and the hoist or drop **progress**. The same drivers give every situation: a trimmed sail is full and
  smooth, an eased sail on the wind line goes flat and flutters from the luff aft, a let-fly sail flogs, a backed
  headsail pops through to the other side, a spinnaker rises as a thin bundle and fills over the last tenth of its
  hoist.
- One mid-surface grid is deformed; the two cloth layers and their normals are derived from it (§9), so the drawn
  sail is always two-sided and correctly lit from both sides.

## 2. Inputs per frame

Per boat, from the render state (the two tick snapshots around the render time, interpolated with the render
fraction `α`; `networking.md` §6 for remote boats):

| name | from | interpolation |
| --- | --- | --- |
| `awa`, `aws`, `tws` | boat outputs (`boat.md` §3, §5.1) | `awa` with `angle_lerp`, speeds with `lerp` |
| `loa` | class file | |
| `dt` | frame time, s, clamped to `[0, 0.1]` | |

Per sail, from `sails.md` §7:

| name | meaning | interpolation |
| --- | --- | --- |
| `phase` | `down`, `prepare_hoist`, `hoisting`, `up`, `prepare_drop`, `dropping` | the newer snapshot's |
| `progress` | 0..1, fraction hoisted (`hoisting`) or lowered (`dropping`) | `lerp` when both snapshots have the same phase, else the newer value |
| `beta` | sail angle `β` | `angle_lerp` |
| `pole` | pole / tack angle `γ` (same rotation sense as `β`, §7.3) | `angle_lerp` |
| `luff_shiver` | `I` ∈ [0, 1] | `lerp` |
| `backed` | bool | the newer snapshot's (smoothed in §5.3) |

**Remote boats** get only the sail angles, the front sail and the running change step (`networking.md` §5.3). The
renderer computes `awa`, `aws`, `tws` from the interpolated pose and the local wind, `luff_shiver` and `backed`
with the formulas of `sails.md` §7 (the class's `shiver_angle` table is in the performance file), and for a sail
that is in a change step but has no sent angle (the new sail of a peel) it uses the trim target of `sails.md` §5.4
at the optimal angle (auto-trim) with the step's `k_h`.

## 3. Geometry from the generator

### 3.1 The grid
Each sail is a regular grid of `rows × cols` vertices (`grid_rows`, `grid_cols` in the physics sidecar): row `i`
from the foot (0) to the head (`rows − 1`), column `j` from the luff (0) to the leech (`cols − 1`). Corners from the
sidecar: `tack` (0, 0), `clew` (0, cols − 1), `head` (rows − 1, 0), and for a square-headed main `head_aft`
(rows − 1, cols − 1). On pointed-head sails (jib, genoa, code zero, spinnakers) the whole head row is one point.
Two layers 2 mm apart, port layer first; uv0 is metric, uv1 is (chord fraction, 1 − height fraction).

The imported engine mesh is re-indexed by the glTF importer. At load the renderer rebuilds **its own mesh in grid
order** (`2 · rows · cols` vertices, layer-major, then row-major): `SailGrid.grid_index` (`game/scripts/sail_grid.gd`)
maps each imported vertex to its grid index, which gives the uv0 and uv1 of every grid vertex. Grid vertices the
importer dropped (the collapsed head vertex until the generator references it) take the sidecar corner position
and the uv of their grid position. Triangles: two per cell per layer, wound so the port layer faces `+y` and the
starboard layer `−y` in the rest pose. Zero-area cells at a collapsed head are kept; they draw nothing.

### 3.2 Rest mid-surface and sail frame
`Q0[i][j]` = the mean of the two layer vertices = the rest mid-surface (in `y = 0`). At load, per sail:
```
T  = Q0[0][0]                              // tack
Lh = normalize(Q0[rows-1][0] - T)          // luff axis, tack -> head, points up
Nh = (0, 1, 0)                             // port normal of the rest plane
Ah = cross(Lh, Nh)                         // in the plane, perpendicular to the luff, points aft
for every vertex: a = dot(Q0 - T, Ah) ; l = dot(Q0 - T, Lh)      // m: aft of the luff line, along the luff
a_min, a_max, l_min, l_max over the grid
Sa = a_max - a_min ; Sl = l_max - l_min    // chord and luff extents of the sail
u = (a - a_min) / Sa                       // 0 on the luff line, 1 at the farthest point aft (the clew)
h = (l - l_min) / Sl                       // 0 at the foot, 1 at the head
uc[j] = j / (cols - 1)                     // fraction along the row, 0 at the luff, 1 at the leech
C[i] = |Q0[i][cols-1] - Q0[i][0]|          // chord of row i (0 at a pointed head)
amid[i] = (a[i][0] + a[i][cols-1]) / 2     // mid-chord of row i
```
`u` is measured against the whole sail's chord `Sa`, not per row: on a main whose leech tapers toward the head the
upper rows never reach `u = 1`, so the camber term of §6.1 lifts the upper leech off the plane to leeward. That is
the sail's natural twist and is part of the look.

A deformed vertex is written in the sail frame as `(a', l', n')` (aft, along the luff, toward port) and mapped back
with `P = T + a'·Ah + l'·Lh + n'·Nh` before the placement of §7.

## 4. Look parameters

Per sail, from the physics sidecar entry `sails.<id>.look` (the generator copies the class file's
`visual.sails.<id>.look` and fills missing keys with the defaults below). Amplitudes are relative so one table fits
every size of boat.

| name | unit | main | jib, genoa | code zero | spinnaker asym | spinnaker sym | meaning |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `fill_gain` `G` | – | 0.6 | 0.75 | 0.7 | 1.0 | 1.5 | how full the sail gets |
| `fill_curve` `K` | – | 4.0 | 1.2 | 1.3 | 1.0 | 1.5 | how fast it fills as the angle opens (large = full almost at once); on spinnakers it also flattens the belly fore and aft |
| `flutter_amp` | – | 0.15 | 0.07 | 0.08 | 1.0 | 1.0 | flutter amplitude: main and headsails as a fraction of `Sa` (metres = `flutter_amp·Sa`); spinnakers a multiplier of §6.3, §6.4 |
| `flutter_rate` `r_f` | rad/s per m/s | size rule | size rule | size rule | size rule | size rule | flutter phase speed per m/s of `aws` |
| `flutter_rate_max` `w_max` | rad/s | size rule | … | … | … | … | cap of the phase speed |
| `twist_top` | rad | 0.070 (4°) | 0.105 (6°) | 0.140 (8°) | 0 | 0 | extra rotation of the head row to leeward (§7.1) |
| `depth` `k_d` | – | – | – | – | 0.30 | 0.35 | belly depth as a fraction of the row chord (flying sails) |
| `tack_line_max` | – | – | – | – | 0.04 | – | largest tack swing on a fixed sprit, fraction of `Sl` (§7.3) |
| `furl_radius` | m | – | size rule | size rule | – | – | radius of a furled sail's roll (§8.3) |

Size rules (smaller sails flutter faster):
```
r_f   = 0.6 + 2.4 * clamp((12 - loa) / 5, 0, 1)        // 3.0 at 7 m LOA and below, 0.6 at 12 m and above
w_max = 9.0 + clamp((loa - 7) / 5, 0, 1)               // 9 rad/s small, 10 rad/s large
furl_radius = 0.02 + 0.006 * Sa
```
Fixed constants of the shapes: `c_hook = 0.0369260386` (headsail leech hook), foot fade rate 8 (§6.1), flutter
spatial frequency 1 rad/m (§6.1, §6.2), flake frequency 12 and flake amplitude 0.02 (§8.2).

## 5. Per-frame drivers

### 5.1 Fill
```
fill(v, G, K):
    x = fabs(v)
    m = clamp(pow(x, 0.75 / K) * exp(-0.01 / (x + 1e-6)), 0, 1)
    return sgn(v) * 0.75 * G * m

d = wrap_pi(beta + awa)                    // the sail's angle to the wind line; > 0 = sail inside the line on
                                           // the side the wind blows it to
main:              b = fill(sin(d), G, K)
jib, genoa, code0: b = fill(sin(beta), G, K) * s_b         // s_b: backed factor, §5.3
spinnaker sym:     F = fabs(fill(sin(beta), G, K))         // inflation of the flying shape
spinnaker asym:    F = G * clamp(aws / KNOT, 3, 6) / 6      // full from 6 kn apparent, half at 3 kn and below
D = sgn(b) * 4 * Sa * b * b                // camber scale, m (main and headsails)
```
- The main fills from its angle to the wind line: trimmed inside the line it is full, on the line it is flat
  (`b → 0`, the `exp` term makes the approach smooth), sheeted past the line (`d < 0`) the belly flips to windward:
  backwinded.
- A headsail fills from its own sheet angle: sheeted hard in near the centreline it is almost flat, eased it gets
  full.
- For the main the largest camber over chord is `b²·(1 − e^(−8h))` of `Sa` at mid chord (§6.1).

### 5.2 Flutter phase
Per sail, a phase `φ` ∈ [0, 2π), random at spawn (so boats and sails do not flutter in step), advanced every frame,
paused with the game:
```
w = min(r_f * aws, w_max)                  // rad/s
phi = wrap_2pi(phi + w * dt)
```
The flutter itself is a wave travelling from the luff to the leech with spatial frequency 1 rad per metre of chord,
so its crests move aft at `w` m/s; its amplitude is `I = luff_shiver` times the per-type terms of §6.

### 5.3 Backed factor
Headsails only. A per-sail factor `s_b`, +1 when drawing, −1 when backed:
```
target = backed ? -1 : +1
s_b = s_b + (target - s_b) * (1 - exp(-dt / 0.25))         // τ = 0.25 s; s_b = +1 at spawn
```
Crossing zero, the sail goes flat for an instant and pops through to the other side, as cloth pressed aback does.

## 6. Shapes when up

Applied to every vertex of the mid-surface, with the rest coordinates `(a, l)`, the fractions `u`, `h`, `uc` of
§3.2, `A = flutter_amp · Sa` (m), `I = luff_shiver`.

### 6.1 Main
```
f  = 1 - exp(-8 * h)                                   // camber fades out toward the boom
n' = f * D * u * (1 - u)  +  A * I * h * u * sin(phi - a)
a' = a ; l' = l
```
- Belly on the leeward side, deepest at mid chord, zero on the luff (mast) and falling to the leech; flat along the
  boom.
- The flutter grows toward the head (`h`) and the leech (`u`), so a luffing main shivers along its upper leech
  first and the whole leech flaps when it is let fly.

### 6.2 Jib, genoa, code zero
```
n' = 0.5 * D * (pow(u, 4) - c_hook * u)  +  A * I * u * sin(phi - a)
a' = a ; l' = l
```
- Relative to the line from the luff to the clew the sail carries a belly of `0.5·|D|·(u − u⁴)`, deepest at
  `u = 0.63`, on the leeward side; the clew itself sits `0.5·|D|·(1 − c_hook) = 0.48·|D|` inboard of the rest plane,
  so the leech hooks slightly toward the centreline as a sheeted headsail does.
- The flutter grows from the luff aft (no height factor): a headsail luffs along its whole luff at once.
- Backed (`s_b = −1`): `D` changes sign, the belly lies on the other side and the clew is pressed out.

### 6.3 Asymmetric spinnaker
The flat grid carries no depth, so the flying shape is built from a depth field extruded **down the apparent wind**,
which keeps the belly to leeward on either gybe and during a gybe round the bow.
```
e[i][j] = k_d * C[i] * 4 * uc * (1 - uc)                  // m, zero at the luff and leech of each row
U  = (cos(awa), -sin(awa), 0)                              // unit vector toward the wind, boat frame
(Ap, Lp, Np) = the sail axes after the placement of §7.3 (no twist)
w  = (dot(U, Ap) * 0.5 / K,  dot(U, Lp) * 0.5,  dot(U, Np))          // (a, l, n) components
w  = normalize(w) * F
I2 = 0.33 * flutter_amp * I
q  = phi - 7 * uc
m  = (w.a + 0.1 * I2 * sin(q),  w.l,  w.n + I2 * cos(q))
(a', l', n') = (a, l, 0) - e[i][j] * m
```
- `F` inflates the sail with the apparent wind; the `0.5` weights keep the belly mostly across the sail (`n`) and
  only a little up the luff and aft along the chord; `K` flattens it further fore and aft.
- Luffing makes the belly breathe: the flutter modulates the extrusion, strongest where the depth is (mid chord),
  travelling aft.

### 6.4 Symmetric spinnaker
As §6.3 with `F` from the sheet angle (§5.1: strapped in it goes flat, eased it fills slightly beyond the nominal
depth), plus a **luff collapse** along the windward edge (column 0, the pole side) while it luffs:
```
(a', l', n') from §6.3 with F = fabs(fill(sin(beta), G, K))
g  = max(0, I - uc) * (1 - (2*h - 1)^2)                    // band of width I from the luff, zero at head and foot
a' = a' + (amid[i] - a') * 0.5 * g                          // the luff curls in toward the middle of the sail
n' = n' + g * flutter_amp * 0.1 * Sa * sin(phi - a)
```

## 7. Placement

The shaped sail is rotated rigidly into position. Rotations are right-handed about the stated axis; a rotation by
`+θ` about an upward axis turns an aft-pointing part to starboard (this is the sense of `β`, `conventions.md` §3)
and a forward-pointing part to port.

### 7.1 Main
Axis: through the sidecar `boom_pivot`, direction `boom_axis` (the gooseneck's vertical, so the foot of the sail
and the boom turn together). Row `i` is rotated by
```
theta_i = beta + tl * twist_top * pow(h_row_i, 1.5)        // tl = -sgn(awa): toward leeward
```
with `h_row_i` = `h` of the row's luff vertex. The boom node turns about the same axis by `β`; the mainsheet is
rebuilt between the boom and the traveller (`tools/boatgen/README.md`).

### 7.2 Jib, genoa, code zero
Axis: through the tack `T` along the luff `Lh` (the stay or the sprit-to-masthead line). Row `i` is rotated by
`theta_i = beta + tl * twist_top * pow(h_row_i, 1.5)`, `tl = −sgn(awa)`. The clew travels on a cone about the stay,
lifting as the sail is eased, as a real headsail does. Twist opens the upper sail away from the wind; with the
implicit twist of §3.2 it gives the leech its spiral.

### 7.3 Spinnakers and the code zero on the sprit
First a **swing** `S` of the whole sail, then a rotation about the swung luff by `β − γ_e`, so the chord still ends
at `β`:
- **On a pole** (symmetric spinnaker; any flying sail of a class with `rig.pole > 0` and no bowsprit): `S` rotates
  about the mast axis (sidecar `mast_step` → `masthead`) by `γ_e = γ`. The tack, which the generator placed one pole
  length ahead of the mast, lands at the pole end to windward (the core writes `γ = −sgn(awa)·pole_angle`, which in
  this rotation sense puts a forward-pointing pole to windward). The **pole** node turns about its heel on the mast
  by the same `γ` and is shown while the sail is not `down`.
- **On a fixed sprit** (asymmetric spinnaker of a class with `rig.bowsprit > 0`): `S` rotates about the vertical
  through the head by
  ```
  r_h = horizontal distance from the head to the rest tack
  gamma_e = sgn(gamma) * min(fabs(gamma), asin(min(1, tack_line_max * Sl / r_h)))
  ```
  so the tack swings to windward on its tack line by at most `tack_line_max·Sl`. The **tack line** is drawn from
  the sidecar `bowsprit_end` to the swung tack.
- **Code zero**: `γ_e = 0` (tacked hard to the sprit end).

Then each vertex `P` (from §3.2) is placed as `P'' = R(Lh', T', β − γ_e) · (S·P − T') + T'` with `T' = S·T`,
`Lh' = S·Lh`. `wrap_pi` of `β` at ±π (an asymmetric spinnaker gybing round the bow) is the same rotation, so the
sail moves continuously through the gybe.

## 8. Hoisting and dropping

### 8.1 Which shape in which phase

| phase | main | jib, genoa, code zero on a halyard | on a furler (`furling`) | spinnakers |
| --- | --- | --- | --- | --- |
| `down` | (never) | hidden | hidden (for now; drawing it furled with `p = 0` of §8.3 is backlog work) | hidden |
| `prepare_hoist` | – | §8.2 with `p = 0`: flaked on deck | §8.3 with `p = 0` | §8.4 with `c = 0`: a small bag at the tack |
| `hoisting` | – | §8.2, `p = progress` | §8.3, `p = progress` | §8.4, `c = progress` |
| `up`, `prepare_drop` | §6.1 | §6.2 | §6.2 | §6.3 / §6.4 |
| `dropping` | – | §8.2, `p = 1 − progress` | §8.3, `p = 1 − progress` | §8.5, `c = progress` |

Reversed steps (a cancelled hoist or drop, `sails.md` §4.2) keep their phase and run `progress` backwards, so the
same table plays the change in reverse from where it was. Placement (§7) applies in every phase, with the `β` the
core gives (held near the centreline while hoisting, `sails.md` §5.4).

### 8.2 Headsail on a halyard
The head rises from the deck; the part not yet hoisted lies flaked along the foot.
```
hc = 1 - p                                         // cut height fraction
kappa = dot(H, Lh) / dot(H, Ah),  H = (-1, 0, 0)    // slope of a horizontal line in the sail frame
if h >= hc:                                        // hoisted part, slid down so its cut edge is at the foot
    (a', n') = the §6.2 shape at (a, u) ; l' = l - hc * Sl
else:                                              // flaked on deck under its chord position
    a' = a ; l' = a * kappa + 0.03
    n' = 0.02 * Sl * sin(12 * h)                   // zig-zag of the flakes
```
At `p = 1` this is exactly the `up` shape; at `p = 0` all of the sail lies on the deck line.

### 8.3 Headsail on a furler
The sail unrolls aft from the luff; the rest stays wound on the roll.
```
ac = (1 - p) * Sa                                  // chord still furled
r  = furl_radius * (0.4 + 0.6 * (1 - p))           // the roll thins as it unwinds
if a - a_min < ac:                                 // on the roll
    t = 6 * PI * uc                                // three turns over the chord
    a' = a_min + r * (1 - cos(t)) ; n' = r * sin(t) ; l' = l
else:                                              // unrolled, moved forward so its cut edge is on the luff
    a' = a - ac ; u' = (a' - a_min) / Sa
    n' = the §6.2 shape evaluated with u' (and a')  ; l' = l
```

### 8.4 Spinnaker hoist
Up to 90 % of the hoist a thin bundle climbs the luff from the tack; over the last 10 % it fills from the foot up
into the flying shape.
```
if c <= 0.9: hy = c / 0.9 ; k = 0
else:        hy = 1       ; k = (c - 0.9) / 0.1
(af, lf, nf) = the flying shape (§6.3 / §6.4) of the vertex
As = flutter_amp * 0.1 * Sa
sn = As * sin(15 * h + phi)
g  = 0.05 + 0.1 * clamp(10 * pow((1 - h) * k, 4), 0, 1)      // 5 % thin, fattening from the foot as it fills
bundle = (g * (af + sn),  l_min + (l - l_min) * hy,  g * (nf - sn))
(a', l', n') = bundle + ((af, lf, nf) - bundle) * k * k
```

### 8.5 Spinnaker drop
The sail slides down the luff and gathers at the tack, fluttering as it comes down.
```
thr = l_min + Sl * c ; k = pow(c, 0.3)             // quick to start, then steady
r = 1 - h
if l <= thr:                                       // already down: gathered at the tack
    Tg = (0.05 * Sl * sin(4 * r),  l_min,  0)
else:                                              // still up: slides down, relaxes toward the flat sail
    t2 = (l - thr) / Sl
    W  = As * 0.63 * atan(8 * r) * (1 - t2) * 2 * sin(l + phi)
    Tg = (a + (af - a) * t2 + W,  l - (thr - l_min),  t2 * nf + W)
(a', l', n') = (af, lf, nf) + (Tg - (af, lf, nf)) * k
```

## 9. Layers and normals

The deformed and placed mid-surface `Q[i][j]` (boat frame) gives both layers:
```
Tu = Q[i][j+1] - Q[i][j-1]        // one-sided at j = 0 and j = cols-1
Th = Q[i+1][j] - Q[i-1][j]        // one-sided at i = 0 and i = rows-1
N  = cross(Tu, Th)
if |N|^2 < 1e-12:                 // collapsed head, gathered cloth
    N = N[i-1][j] (already computed) if i > 0, else the placed plane normal R·Nh
N = normalize(N)
port layer:      position Q + 0.001 * N, normal  N
starboard layer: position Q - 0.001 * N, normal -N
```
Rows are processed from the foot up so the fallback is defined. In the rest pose `N = +y` (port) for every vertex:
the check at load is `dot(N, +y) > 0.99`. Finite differences on the grid serve every shape (camber, flutter, flakes,
roll, bundle) with one rule, and cost less than analytic derivatives of each formula. Tangents are not written (the
sail material uses no normal map).

## 10. What it looks like

| situation | drivers | picture |
| --- | --- | --- |
| trimmed upwind | `d` 20–30°, `I = 0` | main with 12–15 % camber and an upper leech open to leeward; jib full with a slight leech hook |
| eased past the optimum | `d → 0`, `I` rising | belly thins, a flutter starts at the upper leech (main) and along the luff (headsail) and runs aft |
| let fly, head to wind | `d ≈ 0`, `I = 1` | flat cloth, the whole leech flapping at 0.3–1.5 Hz depending on size and wind, boom on the wind line |
| over-sheeted main | `d < 0` | belly flips to windward (backwinded main) |
| tack | `backed` true for a moment, `β` swinging | jib goes flat, pops through, swings across on its cone and refills |
| backed jib (in irons) | `backed` | jib pressed out to windward, belly on the other side |
| gybe | `β` crosses 0 aft | main goes flat on the centreline and refills on the new side |
| asym gybe | `β` through ±π | kite swings forward round the forestay, belly always downwind |
| spinnaker hoist | `c` 0 → 1 | a thin bundle climbs the luff, then fills from the foot up in the last 10 % |
| spinnaker drop | `c` 0 → 1 | slides down, flapping, gathers at the tack |
| headsail hoist | `p` 0 → 1 | head rises from the deck, the rest unfolds from the flakes |

## 11. Engine notes (Godot)

- **Where it runs**: after the boat's render pose is interpolated and before the cameras. The per-vertex loops go
  in C++ (a front-end GDExtension next to the core bindings, not in the deterministic core); a GDScript version is
  kept as the test reference. Cost per boat is small (the generator's grids: main 26 × 14, jib 22 × 12, spinnaker
  26 × 16, under 1 300 mid vertices).
- **Mesh update**: the sail mesh is the grid-order `ArrayMesh` of §3.1, built with vertex compression off. Each frame
  write positions and normals with `RenderingServer.mesh_surface_update_vertex_region` using the surface's stride
  and offsets (`mesh_surface_get_format_vertex_stride`, `mesh_surface_get_format_offset`); rebuilding the surface
  with `add_surface_from_arrays` is an acceptable fallback. Set a `custom_aabb` that covers the sail at any angle
  (a box around the luff with the sail's extents), so culling never needs the vertex data.
- **Update rate by distance** (the phase `φ` always advances): nearer than 200 m every frame; 200–800 m at 15 Hz;
  beyond at 4 Hz; outside the view frustum not at all.
- **Material**: the generator's `sailcloth` slot, opaque, back faces culled (each layer faces its own side),
  roughness about 0.55, a back-light term of about 0.3 of the albedo so the sun shows through the cloth; liveries and
  sail numbers through uv1 (Godot's `UV2`) in a sail shader. Opaque sails need no draw-order sorting.
- The sail node's transform stays the identity: the generator writes sails in the boat frame, and §7 places them in
  that frame.

## 12. Tests

Synthetic grids for exact numbers: a rectangle in `y = 0` with the luff on `x = 0` from `z = 0` to `z = 9` m, the
leech at `x = −3` m, 11 × 11 vertices (so `Sa = 3`, `Sl = 9`, `u = uc`); and the generated `wm7` sails for the rest.
Flutter phase `φ = 0` unless stated.

1. **Main fill.** Type main, defaults, `awa = 30°`, `β = −5°` (`d = 25°`), `I = 0`: `b = 0.3739`; at
   `(u, h) = (0.5, 0.5)` `n'/Sa = b²(1 − e^−4) = 0.1373` (±1e-3), positive (port = leeward); `n' = 0` on the luff and
   the leech columns of the rectangle. Other angles: `d = 10°` → `b = 0.3059`, camber 0.0919; `d = 40°` → 0.4078,
   0.1633.
2. **Main backwind.** `awa = 30°`, `β = −40°` (`d = −10°`): `b < 0`, `n'` negative (to windward) at every inner
   vertex.
3. **Mirror.** `awa = −30°`, `β = +5°`: the shape of test 1 mirrored (`n'` of equal size, negative).
4. **Headsail.** Type jib, defaults, `awa = 30°`, `β = −25°`, `s_b = 1`: `b = −0.3207`, `D = −0.4113·Sa`; clew
   `n' = −0.198·Sa` (inboard, toward the windward side of the rest plane); the belly against the luff–clew line is
   largest at `u = 0.63` with `0.0972·Sa` toward port. `β = 0`: every `n' = 0`.
5. **Backed headsail.** `backed` switches on: `s_b` passes 0 after 0.173 s and is within 0.04 of −1 after 1 s (−0.963); the
   belly then lies on the other side.
6. **Flutter.** Main, `I = 1`: at the head–leech corner of the rectangle the flutter term swings `±0.15·Sa = ±0.45` m.
   Phase speed at `aws = 6 m/s`: `wm7` (LOA 7.2 m, `r_f = 2.90`, `w_max = 9.04`) `w = 9.04 rad/s`, period 0.70 s;
   a 12 m boat `w = 3.6 rad/s`, period 1.75 s. Crests move toward the leech.
7. **Asym inflation.** `aws ≤ 1.543 m/s` (3 kn): `F = 0.5`; `aws = 2 m/s` (3.9 kn): `F = 0.648`; `aws ≥ 3.087 m/s` (6 kn): `F = 1`; the displacement of a
   mid-chord vertex has length `k_d·C_i·F` (±1 %) with `I = 0`.
8. **Asym leeward belly.** For `awa` = ±60°, ±120°, ±170° with `β` at the optimum on the leeward side, every inner
   vertex of the placed kite lies on the leeward side of the vertical plane through its luff.
9. **Asym gybe.** Sweeping `β` from −170° through ±180° to +170° over 2 s moves no vertex more than `0.05·Sa` between
   frames at 60 fps.
10. **Halyard hoist.** Jib at `p = 0.5`: the highest vertex has `l' = 0.5·Sl` (±1e-3); every flaked vertex lies
    within `0.02·Sl` of the flake line; at `p = 1` the positions equal the `up` shape (±1e-5 m); at `p = 0` no vertex
    is above `0.03 m + Sa·kappa`.
11. **Furler.** At `p = 0.3`: no vertex has `a' < a_min`; the unrolled part spans `0.3·Sa` of chord; at `p = 0` every
    vertex is within `furl_radius·2` of the luff line.
12. **Spinnaker hoist.** `c = 0.45`: the highest vertex is at `l_min + 0.5·Sl`; `c = 0.9`: the bundle reaches the head
    and is at most `0.05·(|a_f| + |n_f| + 2·As)` from the luff line; `c = 1`: the flying shape exactly.
13. **Spinnaker drop.** `c = 1`: every vertex within `0.05·Sl` of the tack; the highest vertex falls monotonically
    with `c`.
14. **Normals and layers.** Rest pose: port normals `(0, 1, 0)` within 1e-6; after any shape the two layers are 2 mm
    apart along the normal; no NaN with a collapsed head, a gathered drop or a fully furled sail.
15. **Continuity.** A scripted tack (awa from +30° to −30° over 4 s, `β` following at the core's rates, `backed` set
    for 0.5 s) and a gybe move no vertex more than `0.05·Sa` between frames at 60 fps.

## 13. Dependencies and open points

- The generator writes the `look` block per sail and a `pole` node (pivot at its heel on the mast, turning about the
  vertical) for pole-flown spinnaker classes (`tools/boatgen`, WM-029). Still open: referencing the collapsed head
  vertex (backlog WM-017).
- Running rigging (sheets, halyards, guys) is not drawn yet; when it is, the sheets run from the placed clew.
- Crew, winches and tell-tales follow the sail `motion` output (`sails.md` §7) and are specified with the crew.
