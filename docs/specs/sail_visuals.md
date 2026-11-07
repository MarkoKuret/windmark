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
- A kite on the lofted model (§6.5) is the exception: its flying shapes are built once by the generator from measured
  sections, and every update only blends them by the apparent wind and places the kite as a whole.
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

The generator writes the full topology: two triangles per cell per layer, zero-area cells at a collapsed head
included, so every grid vertex is referenced and carries its layer normal. The row-major order holds in the GLB
file only; the imported engine mesh is re-indexed by the glTF importer. The stable key of a vertex is its uv1
(exactly `(j / (cols − 1), 1 − i / (rows − 1))`, `u` mirrored on the starboard layer) plus its layer side (port
layer on `+y`), as in `tools/boatgen/README.md` "Sail grid". At load the renderer rebuilds **its own mesh in grid
order** (`2 · rows · cols` vertices, layer-major, then row-major): `SailGrid.grid_index` (`game/scripts/sail_grid.gd`)
maps each imported vertex to its grid index by that key, which gives the uv0 and uv1 of every grid vertex.
Triangles: two per cell per layer, wound so the port layer faces `+y` and the starboard layer `−y` in the rest
pose. Zero-area cells at a collapsed head are kept; they draw nothing.

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
| `twist_top` | rad | 0.070 (4°) | 0.175 (10°) | 0.140 (8°) | 0.45 (26°) | 0 | extra rotation of the head row to leeward (§7.1; the asymmetric spinnaker's grows with the AWA, §7.3) |
| `camber` `k_c` | – | – | – | 0.12 | 0.27 | 0.30 | largest camber over chord: flying sails when full, at a third of the height (asymmetric) or mid height (symmetric) (§6.3), the cap of the code zero (§6.2) |
| `tack_line_max` | – | – | – | – | 0 | – | largest tack swing on a fixed sprit, fraction of `Sl` (§7.3); 0: the tack stays on its fitting (owner, 2026-10-11; was 0.04) |
| `furl_radius` | m | – | size rule | size rule | – | – | radius of a furled sail's roll (§8.3) |

Size rules (smaller sails flutter faster):
```
r_f   = 0.6 + 2.4 * clamp((12 - loa) / 5, 0, 1)        // 3.0 at 7 m LOA and below, 0.6 at 12 m and above
w_max = 9.0 + clamp((loa - 7) / 5, 0, 1)               // 9 rad/s small, 10 rad/s large
furl_radius = 0.02 + 0.006 * Sa
clearance   = 0.042 * loa                          // m, flying sails off the other sails and the mast (§7.4), and the
                                                   // main and boom off a flying sail's sheet (§7.6): 0.30 on wm7
```
Fixed constants of the clew set (§7.7): fade height 0.3 of `Sl`, corner reach 2 grid steps, bounds `k_d` −0.1 to
0.25 and `k_l` −0.1 to 0.3, difference step 0.01, two Newton steps. Fixed constants of the tack pin (§7.5): its reach `0.25·Sl`; of the main's stop (§7.6): 24 scan steps, 10 bisection steps.
Fixed constants of the clearance (§7.4): push slope `k_p = 0.3` (m of push lost per m of cloth), ease threshold
`P_e = 2·c` (the leech depth the push takes on before the sail is eased; 3·c before 2026-10-10: a push deeper than
2·c could jump between frames where the stopped main of §7.6 lies along the kite's leech), ease cap `e_max = 0.35`
rad (20°). Of the forestay (§7.4, a flying sail on a pole): margin `c_s = max(0.25·J_b, c)` and half width
`w_s = 0.6·J_b` (`J_b` the horizontal distance from the mast axis to the forestay's tack fitting), full shift from
`0.5` of the chord, `0.3` of it lost toward the leech, fading out over the top `0.3` of the height.
The `camber` key replaces an earlier `depth` (0.30, 0.35 of the flat row chord, applied without shortening the
chord), which drew the kites about 40 % too deep and too wide; a `depth` key in a look block is ignored. The
asymmetric spinnaker's `camber` 0.27 and `twist_top` 0.45 (2026-10-04, were 0.26 and 0) follow the measured J/80
flying shapes of §14.2.
Fixed constants of the shapes: `c_hook = 0.0369260386` (headsail leech hook), the jib and genoa camber `k_j = 0.135`
and its fill scale `b_j = 0.15` (§6.2), foot fade rate 8 (§6.1), flutter spatial frequency 1 rad/m (§6.1, §6.2),
flake frequency 12 and flake amplitude 0.02 (§8.2). The jib's and genoa's `twist_top` 0.175 and the camber of §6.2
(2026-10-09, were 0.105 and a belly of `0.5·|D|·(u − u⁴)` against the whole sail's chord) follow §14.5.

### 4.1 Kite set parameters

The flying shape of a spinnaker (§6.3, §6.4, §7.3, §7.4, §7.7) is drawn from named **set parameters**, one block per
kite in the class file, `visual.sails.<id>.set` (`data_format.md` §3.7; spinnakers only). A missing key takes the
default of the kite's type below, so a class without the block draws exactly the shapes of the sections that follow
(the defaults are the constants they used before 2026-10-17, WM-173). They are presentation only: no core, VPP,
performance table or rule area reads them, and changing them needs no regeneration of `data/perf`.

Who reads them: the game's `BoatView` takes the class file's block (falling back to the sidecar's copy, `sails.<id>.set`,
for a class with no class file, such as a generator test class) and hands every key to `SailShape` (native and
reference) at set-up; the generator (`tools/boatgen`) validates the block, copies it with the defaults filled into the
physics sidecar, and draws its previews and `kite_preview` with it (§12 test 19). The kite tuner
(`game/scenes/tools/kite_tuner.tscn`, `game/README.md`) edits the block live and saves it. The kite's `look` keys
`camber` and `twist_top` (§4) are read the same way, the class file's `visual.sails.<id>.look` over the sidecar's, so
a saved change shows in the game without a rebuild.

Angles in radians in the file (the tuner shows degrees). `Sl` is the luff extent (§3.2), `C_0` the flat foot chord,
`h` a vertex's height (§3.2) and `h_i` its row's, `uc` its chordwise share (0 luff, 1 leech).

| key | asym | sym | range | meaning |
| --- | --- | --- | --- | --- |
| `depth_peak_h` | 0.3 | 0.5 | 0.1 to 0.9 | height of the deepest row, share of the luff (§6.3 `p_i`) |
| `depth_foot` | 0.8 | 1.0 | 0 to 1.5 | camber of the foot row over the deepest |
| `depth_head` | 0.45 | 0.7 | 0 to 1.5 | camber at the head over the deepest |
| `draft_low` | 0.5^(1/0.8) = 0.420 | 0.5 | 0.25 to 0.75 | draft position, share of the chord from the luff, from the foot up to `draft_from_h` |
| `draft_head` | 0.5^(1/1.4) = 0.610 | 0.5 | 0.25 to 0.75 | draft position at the head |
| `draft_from_h` | 0.55 | 0.55 | 0 to 0.95 | height where the draft starts to move from `draft_low` to `draft_head` |
| `belly_aft` | 0.5 | 0.5 | 0 to 2 | weight of the wind's chordwise part in the belly's direction (over `fill_curve`; more moves the draft aft downwind) |
| `belly_up` | 0.5 | 0.5 | 0 to 2 | weight of the wind's part along the luff in the belly's direction (more lifts the belly) |
| `twist_exp` | 2.5 | 1.5 | 0.5 to 5 | the twist's height profile: asym `1 − (1 − h_i)^x` (larger: more twist low down), sym `h_i^x` (larger: twist kept to the top) |
| `twist_awa_lo` | 60° | – | 20° to 150° | asym: the twist starts at this AWA |
| `twist_awa_hi` | 130° | – | 40° to 180° | asym: all of `twist_top` from this AWA (above `twist_awa_lo`) |
| `twist_run` | 25° | – | 3° to 60° | asym: the twist fades out over this much short of a dead run |
| `foot_sag` | 0 | 0.35 | 0 to 1 | the low rows' belly sags down by this share of its depth (§6.4) |
| `foot_sag_h` | 0.35 | 0.35 | 0.05 to 0.9 | ... fading out over this lower share of the height |
| `girth_foot` | 1 | 1 | 0.6 to 1.4 | the flying chord of the foot row over the §6.3 one (the belly scales with it) |
| `girth_mid` | 1 | 1 | 0.6 to 1.4 | the same at mid height |
| `girth_head` | 1 | 1 | 0.6 to 1.4 | the same at the head |
| `luff_curl` | 0 | 0 | −1 to 1 | extra belly along the luff, share of the row's camber at the edge (positive: the luff curls further to leeward; negative: it stands up to windward) |
| `leech_curl` | 0 | 0 | −1 to 1 | the same along the leech |
| `head_drop` | 0 | 0 | 0 to 0.15 | the head eased down the luff (halyard eased), share of `Sl` |
| `clew_lift` | 0 | 0 | −0.3 to 0.3 | the clew raised (negative: lowered) up the luff, share of `C_0` |
| `clew_out` | 0 | 0 | −0.3 to 0.3 | the clew let out along the chord (negative: drawn in), share of `C_0` |
| `clew_h` | 0.3 | 0.3 | 0.05 to 0.8 | the clew's moves (`clew_lift`, `clew_out`, §7.7) fade out at this share of the height |
| `forward` | 0 | 0 | −0.1 to 0.3 | the cloth projected forward of where the angles put it, share of `Sl`, the corners held |
| `tack_rise` | 0 | 0 | 0 to 0.15 | the tack raised, share of `Sl` (a pole kite: the pole end goes up with it; a sprit kite: the tack line is eased) |
| `stay_clear` | 0.25 | 0.25 | 0 to 1 | on a pole: margin ahead of the forestay, share of `J_b` (§7.4) |
| `stay_width` | 0.6 | 0.6 | 0.1 to 1.5 | on a pole: the forestay's half width, share of `J_b` |
| `stay_head` | 0.3 | 0.3 | 0.05 to 0.9 | on a pole: the forestay shift fades out over this top share of the height |
| `stay_luff` | 0.5 | 0.5 | 0.05 to 0.95 | on a pole: chord share from which the forestay shift is taken in full |
| `stay_leech` | 0.3 | 0.3 | 0 to 1 | on a pole: share of the forestay shift lost toward the leech |
| `model` | `hinge` | `hinge` | `hinge`, `loft` | the shape model: `hinge` the shapes of §6.3, §6.4 placed by §7.3 to §7.7; `loft` the lofted shapes of §6.5 (a string) |
| `shape` | – | – | a file name | for `loft`: the kite shape file the fixed shapes come from, `data/sails/<shape>.kite_shape.json` (`data_format.md` §3.7.6; a string): measured sections (asymmetric only) or a measured surface (either kind, §6.5 "The surface source") |
| `loft_depth` | 1 | 1 | 0.3 to 1.5 | `loft` only: the lofted depth over the measured (§6.5 `D`) |
| `loft_trim` | 0 | 0 | −20° to 20° | `loft` only: the whole kite turned further out about its luff (negative: in), on top of the core's angle (§6.5) |

A lofted kite (`model` `loft`, §6.5) reads only `loft_depth` and `loft_trim`; every other key is kept for the hinge
model and has no effect on it. Every spinnaker flies a fixed shape from a measured surface (2026-11-06): the
asymmetrics (wm7, wm10, wm12, wm16) the AC33, the symmetrics on a pole (wm9, wm21) the IACC series; wm7 flew the J/80
sections from 2026-11-03. The code zero, the jibs and the mains are unchanged.

How each enters the shape (the sections below give the rest; with the defaults every added term is zero or one):
```
p_i  = h_i < depth_peak_h ? 1 - (1 - depth_foot) * ((depth_peak_h - h_i) / depth_peak_h)^2         // §6.3, §6.4
                          : 1 - (1 - depth_head) * ((h_i - depth_peak_h) / (1 - depth_peak_h))^2
q(d) = ln 0.5 / ln d                                        // the exponent that puts the draft at d
t_i  = clamp((h_i - draft_from_h) / (1 - draft_from_h), 0, 1)
q_i  = q(draft_low) + (q(draft_head) - q(draft_low)) * t_i^2 (3 - 2 t_i)
prof = asym sin(PI x), sym 4 x (1 - x),  x = uc^q_i          // sym defaults: q = 1, the §6.4 parabola
     + luff_curl * (1 - uc / 0.25)^2 * 4 h_i (1 - h_i)      for uc < 0.25
     + leech_curl * (1 - (1 - uc) / 0.25)^2 * 4 h_i (1 - h_i) for uc > 0.75
g_i  = h_i < 0.5 ? girth_mid + (girth_foot - girth_mid) * (1 - 2 h_i)^2
                 : girth_mid + (girth_head - girth_mid) * (2 h_i - 1)^2
c_i  = (1 - h_i / clew_h)^3 for h_i < clew_h, else 0        // §7.7
e    = d_i * s_i * g_i * C_i * prof
a'   = a0_i + (a - a0_i) * s_i * g_i + clew_out * C_0 * c_i * uc^2
l'   = l - (k_l - clew_lift) * C_0 * c_i * uc^2 - head_drop * Sl * h - foot_sag * e * max(0, 1 - h_i / foot_sag_h)^2
w    = normalize(dot(U, Ap) * belly_aft / K, dot(U, Lp) * belly_up, dot(U, Np))
twist (asym) = twist_top * smoothstep((|awa| - twist_awa_lo) / (twist_awa_hi - twist_awa_lo))
                         * smoothstep((PI - |awa|) / twist_run) * (1 - (1 - h_i)^twist_exp)
twist (sym)  = tl * twist_top * h_i^twist_exp
after the placement of §7.3, before the forestay shift and the push of §7.4, times the flying share f_a (§7.5):
  hold_k = smoothstep(d_T / R) * smoothstep(d_H / R) * smoothstep(d_C / R),  R = 0.35 Sl   // d: rest distance from
                                                                           // the tack, head and clew corners
  P_k += fwd * forward * Sl * hold_k * f_a
  P_k += up * tack_rise * Sl * (1 - min(d_T / (0.5 Sl), 1))^2 * f_a       // the clearance margin fades at the
                                                                           // tack so raised (§7.5)
```
The head the margin of §7.4 fades at is the head so dropped. The forestay terms replace the constants of §4 and
§7.4 (`c_s = max(stay_clear·J_b, c)`, `w_s = stay_width·J_b`, the fade `stay_head`, the chord shares `stay_luff`
and `stay_leech`). On a pole kite the drawn pole tilts about its heel so its end follows the raised tack. The
fixed constants of the clew solve, the tack pin, the clearance and the main's stop stay as listed above: they keep
the shape continuous and clear rather than set its look.

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
A jib or genoa keeps its **clew line**: the leech of every row sits where the sheet puts it, off the rest plane by
the hook term of the sheet angle, and the camber is laid against each row's own chord, so the upper sail is as full
as the lower one (§14.5):
```
u0_i, ul_i = u of row i's luff and leech vertex
x   = clamp((u - u0_i) / max(ul_i - u0_i, 1e-3), 0, 1)       // fraction along the row's chord
n_l = 0.5 * D * (ul_i^4 - c_hook * ul_i)                      // the row's leech off the rest plane (the clew line)
m   = sgn(D) * k_j * tanh(sqrt(|D| / (4 * Sa)) / b_j)          // camber over chord, signed (|b| = sqrt(|D| / 4 Sa))
p_i = 1 - 0.15 * (2 * h_i - 1)^2                              // 0.85 at the foot and the head, 1 at mid height
g   = x * (1 - x) * (2 - x) / 0.3849                          // chordwise profile, 1 at the draft x = 0.42
n'  = n_l * x  -  m * p_i * C_i * g  +  A * I * u * sin(phi - a)
a' = a ; l' = l
```
- The leech and clew lie where they always did (the clew `0.5·|D|·(1 − c_hook) = 0.48·|D|` inboard of the rest
  plane at the foot, so the leech hooks slightly toward the centreline as a sheeted headsail does; the upper
  leech near the rest plane): the jib's angle and trim are those of the core. Between luff and leech each row
  carries a belly of `|m|·p_i` of its chord on the leeward side, deepest at 0.42 of the chord, with an entry of
  about 32° and an exit of about 17° to the chord at 12 % camber.
- The camber grows with the fill: at the jib's upwind sheet angles (`β` 8° to 12°: `b` 0.15 to 0.20) 9 to 12 %
  over the height, 10 to 13 % at `β` 15° to 20°, and at most `k_j` (13.5 %) eased. Strapped in on the centreline
  (`β = 0`) the sail is flat.
- The flutter grows from the luff aft (no height factor): a headsail luffs along its whole luff at once.
- Backed (`s_b = −1`): `D` and `m` change sign, the belly lies on the other side and the clew is pressed out.
- On a furler (§8.3) the unrolled part takes the same shape with `u0_i = 0`, `ul_i` reduced by the furled
  fraction `1 − p` and the chord `C_i` scaled by the unrolled share of the row.
- **Code zero** (a headsail with a `camber` key): a flat reaching sail with its draft aft; it keeps the shape
  ```
  n' = 0.5 * D * (pow(u, 4) - c_hook * u)  +  A * I * u * sin(phi - a)
  D_max = k_c * Sa / 0.2362
  D     = D_max * tanh(D / D_max)
  ```
  Relative to the line from the luff to the clew it carries a belly of `0.5·|D|·(u − u⁴)`, deepest at
  `u = 0.63`. The belly against the luff–clew line of a row reaching `u = U` is at most `0.2362·|D|·U³/Sa` of its
  chord (largest on the foot), so the code zero never passes `k_c` (12 %) and sits at 7.5 to 11 % across its
  normal trim (`β` 25° to 60°; 10 % at 40°).

### 6.3 Asymmetric spinnaker
The flat grid carries no depth, so the flying shape is built from a camber field extruded **down the apparent
wind**, which keeps the belly to leeward on either gybe and during a gybe round the bow. The cloth does not
stretch: as a row takes its camber its chord shortens so that the arc keeps the flat length. The camber's height
profile, its chordwise profile (draft forward, a curled luff) and the twist (§7.3) follow the full-scale
measurements of §14.2. The numbers below are the asymmetric defaults of the set parameters (§4.1), which every
class can change per kite.
```
h_i = h of the row's luff vertex
p_i = h_i < 0.3 ? 1 - 0.2 * ((0.3 - h_i) / 0.3)^2            // deepest at 0.3 of the height,
                : 1 - 0.55 * ((h_i - 0.3) / 0.7)^2           // 0.8 on the foot, 0.45 at the head
d_i = k_c * min(F, 1.15) * p_i                              // camber over chord of row i
s_i = 1 / (1 + 8/3 * d_i^2)                                 // chord shortening of an arc of that camber
t   = clamp((h_i - 0.55) / 0.45, 0, 1)
q_i = 0.8 + 0.6 * t * t * (3 - 2 * t)                       // draft exponent: 0.8 to 0.55 of the height, 1.4 at the head
a_s = a0_i + (a - a0_i) * s_i                               // a0_i: a of the row's luff vertex
e   = d_i * s_i * C_i * sin(PI * uc^q_i)                    // m, zero at the luff and leech of each row
U   = (cos(awa), -sin(awa), 0)                              // unit vector toward the wind, boat frame
(Ap, Lp, Np) = the sail axes after the placement of §7.3 (no twist)
w   = normalize(dot(U, Ap) * 0.5 / K,  dot(U, Lp) * 0.5,  dot(U, Np))     // (a, l, n) components, unit
I2  = 0.33 * flutter_amp * I
q   = phi - 7 * uc
m   = (w.a + 0.1 * I2 * sin(q),  w.l,  w.n + I2 * cos(q))
(a', l', n') = (a_s, l, 0) - e * m
```
- Camber over chord: `d_i·sqrt(1 − w.a²)` (the part of `w` along the chord shifts the draft, it adds no depth).
  With `k_c = 0.27` and the sail full (`F = 1`): 27 % at a third of the height, 22 % on the foot, 26 % at mid
  height, 18 % at five sixths and 12 % at the head, the J/80's 20 to 31 % low down and 15 to 18 % at the top
  (§14.2). In light air (`F = 0.5`) it sags to half.
- The profile `sin(π·uc^q)` puts the deepest point at `uc = 0.5^(1/q)`: 0.42 of the chord over the lower half of
  the sail (measured 0.39 to 0.49) and 0.61 at the head (measured 0.61 to 0.67). Its slope at the luff is steep,
  so the luff curls round into the belly (entry angle about 50° on the grid; measured 50 to 130°).
- The shortening makes a full row 16 % (a third of the height) to 4 % (the head) narrower than its flat chord; the
  clew comes in toward the luff with it, so the set kite shows about the projected size of a real one instead of
  the flat planform plus its depth.
- `F` inflates the sail with the apparent wind; the `0.5` weights keep the belly mostly across the sail (`n`) and
  only a little up the luff and aft along the chord; `K` flattens it further fore and aft.
- Luffing makes the belly breathe: the flutter modulates the extrusion, strongest where the depth is, travelling
  aft.

### 6.5 Lofted spinnaker: a fixed flying shape

The hinge model of §6.3 and §7 bends the flat grid every update into a computed belly and then corrects it locally:
the clearance push (§7.4), the forestay shift, the clew solve (§7.7), the row twist and the tack pin. Each correction
is local, so where they overlap the cloth dents and bulges. The lofted model draws a kite's flying shape as one
coherent surface, built **once** by the generator from measured full-scale sections (as a sail modeller would
sculpt it), and at run time only blends it by the apparent wind and places it as a whole. Picked per kite by the set
block's `model` (§4.1); the source is a kite shape file (`data_format.md` §3.7.6) of one of two kinds: measured
**sections** (camber, draft, twist and entry by height, lofted as below) or a measured **surface** (a complete 3D
flying shape, resampled and mapped onto the class, "The surface source" below). Either way the shapes are generated
into the physics sidecar (`sails.<id>.loft`, `data_format.md` §3.7.5) in the same form, so the run time below does
not know which source made them.

**The loft (generator, `tools/boatgen/boatgen/kite_loft.py`).** For each measured AWA, on the class's own flat grid
(`P`, rows `i` from the foot, columns `j` from the luff):
```
h_i  = i / (rows - 1)                       // the row's stripe: its share of the luff and of the leech, as measured
G_i  = sum over j of |P[i][j+1] - P[i][j]|  // the row's flat girth; t_ij its vertices' shares of it
f_i, e_i = the measured camber and entry at h_i: a monotone cubic (Fritsch-Carlson) through the sections and a head
           point h = 1: the camber run on along the top two sections' slope toward zero (never up, never below 0;
           a camber forced to 0 over the top sixth pinches the head into a waist, and the depth goes to 0 with the
           chord anyway), the entry 0
d_i   = a least-squares cubic in h through the measured drafts, held above the top section (the reach's 0.44, 0.39,
        0.44 would wave the line of deepest points, and the light on the cloth, from side to side)
tau_i = a least-squares cubic in h_i through the measured twists, 0 at the foot (fair: the reach's 6, 6, 3, 4 deg up
        the top half would bend the leech back and forth)
rho_i = flying chord over girth: the longest a convex section of (f_i, d_i) has (no luff curl), less a shortening
        that is a least-squares cubic in h through the measured sections' own (from their entry), 0 at the head,
        kept >= 0 with a smooth floor (+-0.01); the leech the chords make is fair (the measured entries scatter
        from 50 to 129 deg)
section of row i: a convex curve of arc length G_i (the cloth keeps its length) with camber f_i, draft d_i and chord
                  rho_i G_i (so the flying chord comes out of the camber), its curvature over the arc share t
    kappa(t) = k (e^{s (t - 1/2)} - e^{-s/2} w(t)) + g w(t) + q_i w_e(t),   w(t) = max(0, 1 - t / 0.3)^2,
               w_e(t) = max(0, 1 - (1 - t) / 0.5)^2
    k the depth, s the draft (s >= -2 / 0.3), g >= 0 the luff curl (spread over 0.3 of the girth: no crease),
    q_i the clew hook (below); every term >= 0: a membrane under pressure has no hollow
row i in 3D: from its flat luff vertex L_i, the chord along the flat row turned by tau_i about the vertical toward the
    belly, the belly to port; vertex j at its arc share t_ij:  Q_ij = L_i + G_i (X(t_ij) r_i' + Y(t_ij) n_i')
written per vertex in the sail frame of §3.2: (a, l, n) = (Q - T) . (Ah, Lh, Nh)
```
The tack, the head and the luff stay where the flat sail has them; the clew and the leech come out of the chords and
the twist. Then the loft is fitted to the kite as it flies, at a nominal trim per measured AWA (the class's optimum
kite angle at 12 kn true wind from its performance file, else `|awa| - 48 deg` within 15 to 64 deg), set alone with
the run-time placement below:
- **As flown.** A turn about the leaning luff changes the rows' horizontal chord angles by itself, and the clew's
  lift (below) the low rows' camber against their own chords, so `tau_i` and `f_i` are corrected, three times each
  before and after the clew is set, by the difference between the target and the drawn one (the chords' horizontal
  angles from the foot's; the largest distance from the chord, a parabola through the deepest vertex and its
  neighbours, over the chord).
- **Clew on its sheet** (what §7.7 did every update, done once): the clew hook `q_i = q (1 - h_i / 0.3)^3`
  (0 <= q <= 8: the foot's last half curving round into the clew, the low rows' chords drawn in) and the clew lift
  (the clew end of the low rows raised along the luff by `lift * C_0 * (1 - h_i / 0.3)^3 * uc^2`, |lift| <= 0.3) are
  chosen to bring the sheet nearest the clew corner's bisector (as test 25 measures it): seven hooks, then golden
  sections. The sidecar records them and the angle left.

On wm7 from the J/80 (Deparday et al. 2016), as drawn (test 27): the camber within 0.3 % of the measured on every
section, the draft within 0.03 (the cubic), the twist within 1.2° (the cubic, on the reach) at both AWAs and half
way; the entry angles where convexity allows them (the run's foot 66° for 61°); the clew hook 0 reaching and 8
running (the bound), the lift 0.01 and 0.13 of the foot; at the nominal trims the sheet leaves the clew 18° (reach)
and 12° (run) off its bisector, mostly out of the corner's plane: the measured sections leave the clew corner only
these two terms to turn it with (the hinge model's per-update clew solve, §7.7, gets within 4°).

**The surface source (generator, `tools/boatgen/boatgen/kite_surface.py`, 2026-11-06).** Lofting curves through a
handful of section numbers drew odd edges, a crease along the luff, a bowl at the clew and a poor outline (owner,
2026-11-06, on the J/80 loft). A surface source takes the whole measured surface instead and changes it as little as
possible: its outline, the curvature of its edges and its corners are the measured ones.
```
M(h, uc)   the measured surface by stripe and girth share: row h joins the luff's point at the share h of the luff's
           length from the foot to the leech's at the share h of the leech's, uc the share of that row's girth from
           the luff (h = 0 is the foot, h = 1 the pointed head); written in its own frame: from the tack, l toward
           the head, a square to it toward the clew in the tack-head-clew plane, n square to both on the belly's side
vertex (i, j) of the class grid: h_i = i / (rows - 1), uc_ij = its share of the flat row's girth
S_ij = M(h_i, uc_ij)                         // Catmull-Rom across the measured grid (49 x 41), the edges kept
the corner map (one linear map A of (a, l), the same for every vertex):
    head  -> the flat head: l = |head - tack| of the flat sail (the luff axis of 3.2), a = 0
    clew  -> where |T C'| = |T C|_m * SF_c / SF_m and |H C'| = |H C|_m * SLE_c / SLE_m meet, aft of the luff
             (the measured tack-clew and head-clew distances, each scaled by the class's foot or leech over the
             measured, both along the cloth)
    (a', l') = A (a, l),  n' = |A e_a| * n * depth          // the depth scales as the measured chord does
the head row collapsed to its mean (a pointed head)
```
No section solve: the tack and the head sit where the flat sail has them and the clew where the map puts it; the clew
lies in the rest plane, so the foot chord lies at the core's sheet angle `β` as the lofted shapes' do. Each measured
surface gives one shape per apparent wind angle listed in the file, with a depth factor (`n` only). Then one smooth
change, made once per shape by the generator (never per update; recorded in the sidecar's `loft` block):
```
foot lift (a shape's `foot_lift` f, 0 to 1): the foot's sag below the straight tack-clew line, along l, taken out by f
    s_j   = max(0, l_c * a_0j / a_c - l_0j)               // foot vertex j against the line from the tack to the clew
    l_ij += f * s_j * (1 - smoothstep(h_i / 0.25))        // the lift fades out over the lower quarter of the height
```
The sidecar also records, per shape, the sheet's angle off the clew corner's bisector with the kite set alone at its
nominal trim (the class's optimum sheet angle at 12 kn, its nominal pole angle on a pole; test 25's measure). The
clew is **not** turned toward its sheet (tried 2026-11-06, dropped): a twirl of the cloth round the clew, whole at
the clew and fading out across the lower-aft quarter, shears the cloth by about its own angle. At 45° it folded a
visible dent into the clew corner; at 8° over the lower-aft quarter it bent wm12's lower leech into an S (test 25's
bulge); at 8° over a whole foot's length from the clew it changed the measured sections up to half height by 3
points of camber (test 27). In each case it took only 6 to 7° off the sheet's angle; the rest (about 30 to 40° on
the asymmetrics at their nominal trims) is the measured clew corner against our sheet leads, and a smooth stored
shape cannot turn it further.
- **Asymmetric, the AC33 benchmark A-sail** (`data/sails/ac33_asym.kite_shape.json`): measured at AWA 55° only. The
  reach is the measured surface (55°) with half its foot sag lifted out (`foot_lift` 0.5: the wind-tunnel model's
  foot dips 0.65 m below the tack on wm7's close reach, the sportsboat kite rides 0.3 m higher); the run (130°) is the
  same surface 10 % deeper, turned out whole by the core's larger sheet angle at run time like any lofted kite.
  Between them the run-time blend; beyond, held.
- **Symmetric, the IACC parametric series** (`data/sails/iacc_sym_series.kite_shape.json`): five sails of the same
  girth that differ mainly in how close their clews are (foot camber 23 to 45 %): sail I at AWA 60°, II 90°, III 120°,
  IV 150°, V 180°, neighbours blended by the run-time smoothstep. The rows are the series' horizontal sections, the
  stripes shares of the luff from the foot (`t = 0.1`) to where its two luffs meet (`t` about 1.004). The series'
  model leans its luffs in toward the head (the clews about 28° downwind of the head); stood on the sail's luff axis
  square to its corner plane that lean would tip the level foot down by 2 m on wm21, so its depth is taken along the
  series' wind direction (`z`) instead of square to the corner plane: `p = T + a e_a + l e_l + n z` (an oblique
  frame; the same corner map), and the foot and every section stay level with the belly down the wind.

On wm7 (AC33): the corner map is nearly a plain scale (`a` 0.0318, `l` 0.0350 of the model's millimetres to metres, no
shear); the outline along the cloth over the luff, measured against the class: leech 0.87 / 0.86, foot 0.59 / 0.56,
mid girth 0.51 / 0.53 (the AC33 is about 10 % narrower at half height than the class planform; kept). On wm21 (IACC):
`a` 18.3 to 18.7, `l` 20.8, a shear of up to 0.05 (the series' luffs lean in toward the head); leech and luff 1.00
both, foot 0.53 / 0.49, mid girth 0.59 / 0.52 (the series is wider in the shoulders; kept). The sidecar's `map` block
records both outlines.

The surface files are third-party data, resampled once (`python3 -m boatgen.kite_surface ac33 <file.igs>` for the
AC33 geometry; the series is evaluated from its published equations) and recorded in `docs/THIRD_PARTY.md`;
`python3 -m boatgen.kite_surface render` draws every surface alone (no boat, plain shaded, three views) to check the
raw data before it goes on a boat (`docs/design/kite_ac_2026-11-06/raw_*.png`).

**Run time (`SailShape`, native and reference; the generator's preview port in `sail_set.py`).** Per update, with
`S_m` the lofted shapes at their AWAs `A_m` (rising) and `(a, l, 0)` the rest grid:
```
x    = |wrap_pi(awa)|
L    = S_0 for x <= A_0, S_last for x >= A_last, else S_m + (S_{m+1} - S_m) * smoothstep((x - A_m) / (A_{m+1} - A_m))
D    = min(F, 1) * loft_depth                     // F: the asymmetric fill of §5.1 (light air)
sd   = clamp(sin(wrap_pi(beta + awa)) / 0.1, -1, 1) ; side = sd (3 - sd^2) / 2      // the belly on the side the wind
                                                  // blows it to; through the wind line it goes flat and over
fly  = (a, l, 0) + D * (L - (a, l, 0)),  fly.n *= side
I2   = 0.33 * flutter_amp * I ;  q = phi - 7 uc   // luffing: the belly breathes, strongest where it is deep
fly += (0.1 I2 sin(q) |fly.n|, 0, I2 cos(q) fly.n)
loc  = fly (up), §8.4 hoist / §8.5 drop toward fly (with the tack pin of §7.5)
                                                  // the swing S and the turn about the (swung) luff as in §7.3:
ease = the turn further out, about the same luff (below)
k_e  = smoothstep(|wrap_pi(beta)| / 0.1) * (1 - smoothstep((|wrap_pi(beta)| - 100 deg) / 60 deg))   // the trim and
                                                  // the ease fade out where sgn(beta) flips (the centreline, round
                                                  // the bow in a gybe), so the kite does not jump there
th   = beta - gamma_e + sgn(beta) * k_e * loft_trim
P''  = R(Lh', T', th + sgn(beta) * k_e * ease) . (S . (T + a Ah + l Lh + n Nh) - T') + T'   // every vertex, one turn
```
No row twist on top of the measured, no clearance push, no forestay shift, no clew solve, no `forward` or
`tack_rise`: the kite moves only as a whole. The tack stays on its fitting and the head at its halyard (the luff axis
is the turn's axis), the clew where the turn puts it; the sheet runs straight from the placed clew to its block
(§11.3) and the main stops on it as before (§7.6, with the placed clew).

**The forestay rule (hard, owner 2026-11-07).** No spinnaker cloth is ever aft of or through the forestay, on any
class, at any AWA or trim, flying, hoisting or dropping: the forestay (its tack fitting to the hounds) passes through
no part of the kite, and no cloth near it athwartships lies behind it. The head stays at the halyard and the tack on
its fitting (the sprit end, or the pole end where the core puts it); the halyard is never eased. The kite meets the
rule by the whole-kite turn below, which on a run eases the sheet and brings the clew and the belly forward round the
stay; its drop slides the flying shape down the luff (§8.5) instead of relaxing it toward the flat sail.

**Clear as a whole.** Where the kite would come within the clearance `c` (§4) of the main, a shown headsail or the
mast (as §7.4 measures it: horizontal sections, the margin fading at the head and the tack), or within `c_f` of the
forestay, it is turned about its luff (the line from the tack to the head), as one body, just far enough:
```
X(delta) = min over every vertex of x - 1.2 c_P   // 1.2: the horizontal distance keeps a margin over the true one up
                                                  // by the head, where the sails lean
x includes how far the vertex lies ahead of the forestay (fwd), less c_f = 0.04 J_b (J_b the foretriangle base; 0.29
    m on wm21), where it is between the stay's tack fitting and the hounds in height and within 2 c of the stay
    athwartships (a wall; beside or above it, none)
turn out (away from the centreline; on a run: the sheet eased, the clew and the belly forward):
    delta = 0; up to 12 steps: stop when X >= 0; delta = min(delta + (-X) / max(r, 0.5), cap)   // r: the worst
                                                  // vertex's distance from the luff axis
    cap 1.8 rad; without a forestay 0.5 rad, and after the first step only the vertices then within 2 c of the
    worst are looked at again (with it every vertex: the whole kite may come round the stay)
the forestay still inside its margin at the end: the same solve turning in; the one that clears, or comes nearer
```
The turn is solved every update from nothing, so it grows smoothly as the run deepens. On wm21 at TWA 176° (pole 81°,
kite 79°) it is about 55° (the clew about 7.5 m forward); at TWA 150° about 1°. Leaning the kite forward about its
foot (the halyard eased) was tried on paper and does not help: the foot, where the stay clips, does not move.
On wm7 at the optimum trims (12 kn) the reach at AWA 64° (kite 16°, main 10°) needs about 16° of this turn, AWA 80°
and more none; the largest over test 18's sweep (over-sheeted, the main eased, the jib up) is 27°, and on the closest
reaches (test 20) it takes the clew up to 2.2 m outboard of the widest beam (the hinge model 1.9 m: it bends the
leech off the main instead). The forestay needs nothing: tacked to the sprit end ahead of it, the wm7 kite stays at
least 0.8 m off the forestay (AWA 60° to 150°, the kite at 60 to 130 % of its optimum, 2026-11-03).
Cost: about 77 µs per update native (the hinge kite 81 µs).

The lofted model replaces §6.3, §7.3's row twist, §7.4 (but the turn above), §7.5's shift and §7.7 for that kite;
the hoist and drop (§8.4, §8.5), the layers (§9), the sheets (§11.3) and the main's stop (§7.6) are unchanged.

### 6.4 Symmetric spinnaker
As §6.3 (with the symmetric defaults of the set parameters, §4.1) with `F` from the sheet angle (§5.1: strapped in it goes flat, eased it fills slightly beyond the nominal
camber, to 34 % at mid height with the defaults), but symmetric fore and aft: the height profile
`p_i = 1 − 0.3·max(0, 2·h_i − 1)²` (the full depth from the foot to mid height, 0.7 at the head; 2026-10-17, was
`1 − 0.45·(2·h_i − 1)²` with `camber` 0.26: a real running symmetric spinnaker is as deep in its lower panels as
anywhere, its foot curving round and forward between the clews, not a flat edge) and the lower panels' belly sags: each vertex's
height along the luff drops by `0.35·e·max(0, 1 − h_row/0.35)²`, `e` its camber offset (`drow·s·C·prof`), so the foot
curves round, forward and down between the clews and the chordwise profile
`4·uc·(1 − uc)` in place of `sin(π·uc^q_i)`; plus a **luff collapse** along the windward edge (column 0, the pole
side) while it luffs:
```
(a', l', n') from §6.3 with F = fabs(fill(sin(beta), G, K))
g  = max(0, I - uc) * (1 - (2*h - 1)^2)                    // band of width I from the luff, zero at head and foot
a' = a' + (amid_s[i] - a') * 0.5 * g                        // the luff curls in toward the (shortened) mid chord
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
with `h_row_i` = `h` of the row's luff vertex. `tl` is eased per sail toward `−sgn(awa)` with the same
`τ = 0.25 s` as `s_b` (§5.3; set to the target at spawn), so the twist crosses over in a tack or gybe instead of
jumping by `2·twist_top` at the head. The boom node turns about the same axis by `β`; the mainsheet is
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
  so the tack swings to windward on its tack line by at most `tack_line_max·Sl` (0 by default: the tack stays on its
  fitting, §7.5). The **tack line** is drawn from
  the sidecar `bowsprit_end` to the swung tack.
- **Code zero**: `γ_e = 0` (tacked hard to the sprit end).

Then each vertex `P` (from §3.2) of row `i` is placed as `P'' = R(Lh', T', β − γ_e + tl·τ_i) · (S·P − T') + T'`
with `T' = S·T`, `Lh' = S·Lh`, `tl` the eased side toward leeward of §7.1 and the row twist
```
tau_i = twist_top * pow(h_row_i, 1.5)                                   // code zero, symmetric spinnaker (0)
tau_i = twist_top * smoothstep(0, 1, (|awa| - 60°) / 70°) * (1 - (1 - h_row_i)^2.5)  // asymmetric spinnaker
```
The asymmetric spinnaker does not twist on a close reach and opens with the apparent wind angle: from 130° AWA its
upper rows turn up to `twist_top` (26°) further to leeward, most of it low down, as the J/80's sections do
running (10°, 18°, 23°, 25°, 26° at 1/6 to 5/6 of the height, §14.2; the profile gives 10°, 17°, 21°, 24°, 26°) while
the head stays on the luff. The profile starts with a finite slope at the foot (2.5 `twist_top` per unit height), so
the leech leaves the clew without a kink (until 2026-10-15 it was `sqrt(h_row_i)`, whose infinite slope at the foot
turned the leech 12 to 24° at the first row above the clew). `wrap_pi` of `β` at ±π (an asymmetric spinnaker gybing round the bow) is the same rotation, so the
sail moves continuously through the gybe.

**Pivot.** A flying sail turns about its own luff through its tack: the sprit end (asymmetric spinnaker, code
zero), or the pole end after the swing (symmetric spinnaker). That is where the core measures the flying sail's
`β` from (the VPP's kite optimum is the chord angle at the sprit-end tack, `tools/vpp`), not the gooseneck the
main turns about. The tack stays at the sprit end within the tack line. The luff leans aft from the tack (23° from
the vertical on wm7, 20° on wm12), so the foot's plan-view angle from the tack is about an eighth less than
`β` (28° at `β` 32°, 56° at 64°) and the clew lifts as the sail is eased (0.3 m at 32°, 1.2 m at 64° on wm7).
On a reach the main's angle, not the pivot, brings the two sails together: wm7 at 80° AWA, 10 kn, the core sheets
the kite at 32° and the main at 53°; the kite's clew lies 0.52 LOA forward of the transom (0.8 m aft of the mast)
and 1.3 m outboard of the widest beam, as a real reaching asymmetric sheeted to the quarter, but its upper leech
(rows 14 to 19 of 26) passes up to 0.27 m through the main near the luff. The upper leech is close to the luff
axis, so turning the whole sail to clear it would take 31° (35° on wm12) and swing the clew 1 m forward of the mast
and 4.4 m outboard; §7.4 clears it locally instead (owner decision 2026-09-30).

**Ease to leeward.** The drawing adds no rotation of its own: the chord of a flying sail lies at the core's sheet
angle `β` (`sails.md` §5.1, optimum 12–30° at the lowest AWA rising to 85–90° dead downwind), so it sits
`|awa| − |β|` off the apparent wind, about 30–45° reaching and 60–90° running, eased further when the sheet is
eased. The belly of §6.3 then lies down the wind from that chord, to leeward of the main and outside the jib; §7.4
keeps it clear where a trim or a gust would still bring it through them.

### 7.4 Clearance of the flying sails
A flying sail (spinnaker, code zero) never passes through the main, a headsail or the mast. The core often
sheets the kite inside the main (wm7 at 80° AWA: kite 32°, main 53°, so the upper leech lies up to 0.27 m through
the main near its luff). Nothing is hidden or clipped, and the sail keeps the core's angle wherever it can: the
cloth that meets an obstacle is **pushed** off it locally, in a smooth bump that is largest where it meets the
obstacle and fades over the cloth around it, and a last per-vertex push keeps the margin. Only when the leech would
have to be pushed more than `P_e` does the whole sail **ease** about its luff, and never by more than `e_max`. The
obstacles are the boat's other sails that are not `down` (as last placed) and the mast line
`mast_step` → `masthead`.
```
c    = clearance (§4, 0.042 * loa)                        // margin, m; b = c is the width of the falloff
smax(x) = x >= b ? x : (x <= -b ? 0 : (x + b)^2 / (4 * b))  // smooth max(x, 0), C1
c_P  = c * smoothstep(0, 1, |P - H| / (5 * c))              // H: the placed head; the margin fades to 0 there,
                                                             // since the head is hoisted at the mast
sail obstacle, once per update:
  z_r  = mean height (up) of row r of the obstacle as placed
  f    = horizontal unit normal of the obstacle's foot chord (row 0, luff to leech), signed so that
         dot(f, fwd + 0.3 * s_k * port) >= 0                // the side facing the bow; s_k = sgn(dot(Cl - mast_step,
                                                             // port)), Cl: the flying sail's clew before the ease
clearance x of a point P (with its push direction g):
  z = dot(P, up); none (x = INF) outside [z_0 - c, z_last]
  row pair r, r + 1 with z_r <= z < z_(r+1) (row 0 below z_0), t = (z - z_r) / (z_(r+1) - z_r) clamped to [0, 1]
  Q_j  = lerp(M[r][j], M[r + 1][j], t)                      // the obstacle's section at that height
  nearest point Q of the polyline Q_0 .. Q_last to P in the horizontal plane, its last segment run on past the
  leech by 6c (so a flying sail's leech meeting the obstacle's leech end is kept on the bow-facing side
  instead of wrapping round behind it; 2c until 2026-10-11: with the main sheeted near the kite's angle the
  kite's lower leech lies along the main's leech over more than 2c, and cloth that reached the end of the run-on
  flipped round it between frames)
  on a segment:  g = its horizontal normal on f's side,   x = dot(P - Q, g)
  at an end:     g = horizontal unit (P - Q),             x = |P - Q| horizontal
mast: x = horizontal distance of P from the mast line, g radial (to leeward, sgn(awa)·port, when P is on it)

ease (last resort): every row turns by a further e_s * delta about the luff (the §7.3 rotation), e_s = sgn(beta)
  delta = 0; 4 times:
    X = min over the leech vertices of rows 0, 3, 6, ... and the head row - 1, and the obstacles, of x - c_P
    if X >= -P_e: stop
    delta = min(delta + (-P_e - X) / max(r, 0.5), e_max)    // r: that vertex's distance from the luff axis
push, per sail obstacle in turn (c_P of each vertex from its position before the push):
  local:  d_k = c_P - x for every vertex k with x < c_P + b, else -INF      // depth into the margin
          D_k = max over k' of d_k' - k_p * s(k, k')        // s: distance over the rest cloth, by two chamfer
                                                             // passes over the grid (row, column and diagonal
                                                             // neighbours, their rest distances)
          P_k = P_k + f * smax(D_k) * c_P / c                // the head fade pins the head
  margin: every vertex P = P + g * (c_P + smax(x - c_P) - x), x and g of P after the local push
then the mast: P = P + g * (c_P + smax(x - c_P) - x)
```
- The local push moves the whole region that meets the obstacle as one smooth bump along the obstacle's bow-facing
  normal `f`: full depth where the cloth is deepest in the margin, falling off by `k_p` per metre of cloth around
  it (a 0.6 m push on the wm7 reach fades over 2 m of cloth), with a smooth base (`smax`) where it ends. The cloth
  bends instead of turning about the luff, so the clew stays where the core's angle puts it.
- The margin push then takes what is left (the obstacle's twist and camber make its normal differ a little from
  `f`): a vertex already `2c` or more clear is not moved; one inside the margin or through the obstacle lands at
  least `c_P` clear, on the flying sail's side, and the push falls off smoothly over `b`. The obstacles are not
  moved.
- The ease starts only when the leech is more than `P_e` inside the margin (a kite sheeted well inside the main, or
  the main eased onto it), and turns the sail just far enough to bring that depth back to `P_e`, at most `e_max`.
  At the core's optimum with the jib down both boats need no ease (the reach of the example above takes a local push
  of 0.59 m on wm7, 1.25 m on wm12, and no ease); with the jib up on a close reach the kite's foot is held outside
  the jib's leech and its run-on, up to 10° (wm7) and 12° (wm12) at AWA 70° (2026-10-15; before then the bounds test
  below cut the run-on off and the kite passed through it).
- The height slice makes it a horizontal distance: the sails stand close to vertical, so it is within a few per
  cent of the true one.
- The side is the one facing the bow (an obstacle eased out is passed on its forward, outboard face); only for an
  obstacle near the centreline does the kite's own side decide. It does not come from the wind, so it does not
  flip when the main luffs, is let fly or crosses the centreline in a gybe.
- **Continuity.** Every step is a continuous function of the placed sails: the depths, their spread (a maximum of
  continuous terms), the smooth max and the ease (zero until the leech passes `P_e`, then growing with it), so a
  change of trim or wind moves the cloth smoothly from frame to frame and a bump grows from nothing where the kite
  first touches the margin. Sheeting the kite in past the point where its leech meets the main presses it harder
  against the main's lee side, as a real kite that stalls there. The ease and the push are visual only (the core's
  `β` is not changed).
- Cost: per vertex and obstacle a row search and a bounds test (the row pair's horizontal bounds widened by the
  reach asked for plus the run-on, `6c`, so the test never cuts off a point the polyline would find), one polyline only near the obstacle, and a second
  one for the vertices the local push moved; two passes over the grid for the spread; plus a few dozen for the
  ease: about 60 µs per flying sail on a 26 × 16 grid (native), with the kite sheeted at the main's angle so that
  most of it is near the main (the whole kite update 83 µs, a wm7 with three sails 100 µs per frame).

**Forward of the forestay** (a flying sail on a pole; 2026-10-17). A real symmetric spinnaker flies well forward
of the forestay, its shoulders and foot projected ahead of the bow, while the pole end, the head and the clew's
sheet hold its corners. Placed by the core's angles alone its foot lies across the boat abreast the pole (with
the pole squared on a run, abreast the mast), up to two metres aft of the forestay on wm9. After the placement and
before the push above, the sail is shifted forward, row by row (sidecar `forestay_tack` → `hounds`, the stay):
```
J_b  = horizontal distance from the mast axis to forestay_tack
c_s  = max(0.25 * J_b, c),  w_s = 0.6 * J_b
w_j  = smoothstep(0, 1, uc_j / 0.5) * (1 - 0.3 * smoothstep(0, 1, (uc_j - 0.5) / 0.5))   // none at the luff
for every vertex P of rows 0 .. last-1 with stay_tack.z <= P.z <= hounds.z and w_j >= 0.25:
  Q = the stay at P's height;  dy = |dot(P - Q, port)|
  d = (c_s - dot(P - Q, fwd)) * (1 - smoothstep(0, 1, (dy - w_s) / c_s))   // ahead of the stay by c_s near it
  D_i = max(D_i, d / max(w_j, 0.5))
D_i = max(D_i, D_(i+1))                                   // from the head row down: it grows toward the foot
P   = P + fwd * D_i * smoothstep(0, 1, (1 - h_row_i) / 0.3) * w_j * f_a      // f_a: the flying share of 7.6
```
The shift scales with the foretriangle (`J_b`), so every pole class keeps its kite clear by the same proportion; the
head stays at the halyard and the luff at the pole, the middle of the chord moves forward in full and the clew
somewhat less, so the sail leans forward from the masthead with its foot well ahead of the bow, as a real one
does. The rows only move forward, so the sail stays clear of the main and the mast, and the push above still
follows. The terms are continuous in the placed sail (but at the stay's two ends), so it moves smoothly with trim,
wind and gybes.

### 7.5 The tack on its fitting
A flying sail on a sprit is tacked to the fitting at the sprit end (the generator puts the rest tack there,
`tools/boatgen/README.md`), and the tack stays on it in every trim, hoist, drop and gybe:
```
the placement (§7.3) turns the sail about its luff through the tack, so the tack does not move; with
  tack_line_max = 0 there is no swing either
the hoist and drop shapes (§8.4, §8.5) move the tack corner (the bundle's flutter, the gathered folds): their offset
  of the tack, dT = loc[tack] - (a_tack, l_tack, 0), is taken out of the cloth round it:
  loc_k = loc_k - dT * w_k^2,  w_k = 1 - clamp(d_k / (0.25 * Sl), 0, 1)       // d_k: rest distance from the tack
the clearance (§7.4): the margin c_P fades out at the placed tack as it does at the head, so neither push moves it
```
The share of the flying shape, `fa` (1 when up or about to drop, `k²` while hoisting with `k` of §8.4, `1 − c^0.3`
dropping, 0 otherwise), weights the main's stop of §7.6.

An earlier version of this section (2026-10-10) turned the cloth round the clew toward the sheet. It put a bulge in
the lower leech (owner, 2026-10-11) and was removed. The clew is now set by the shape itself (§7.7).

### 7.6 The main stops on the sheet
A flying sail's working sheet runs straight from its clew to its lead block (§11.3), outside the main and the boom.
Eased past that line, a real main comes to rest against the loaded sheet: the boom cannot swing through it. The
drawn main does the same; the core's main angle is not changed (presentation only):
```
S   = the sheet segment C..B of the flying sail shown (the working lead B of §11.3 on the side of its beta; its clew
      and angle as last placed, the clew taken
      before the clearance push of §7.4 so the main's angle does not feed back into it; with two flying sails the
      one with the larger share fa)
the main's region at angle th: the vertical rectangle through the gooseneck G along the rest foot direction
      (horizontal) turned by sgn(beta_m) * th about the boom axis: along 0 .. E_m (the farthest the rest sail reaches
      aft of G, the roach included), height -h_t .. h_head up the boom axis from G (h_t, h_head: the rest tack and
      head; the boom's underside taken as far under the pivot as the foot is above it)
x(th) = the distance of S from that rectangle (exact: its ends from the face, S from the four edges); 0 when S
        passes through it
th_s  = |beta_m| when x stays >= c from th = 0 to |beta_m| (checked in 24 steps); else the first step k with
        x < c, then 10 bisection steps between steps k - 1 and k
drawn = sgn(beta_m) * (|beta_m| - w_f * (|beta_m| - th_s))
```
`c` is the clearance of §4; `w_f` is the flying sail's `fa` (§7.5; 0 while it is down), so the stop comes in with
the hoist and goes with the drop. The main eases out from the centreline and stops where it first meets the sheet, so
the stop moves smoothly with the clew. The boom, the mainsheet tackle and the main's shape and fill all follow the
drawn angle. A sheet that passes `c` under the boom or aft of the leech does not stop the main. On reaches with the
main trimmed to the kite (the main about the kite's angle less 12.5°) nothing stops; running with the kite eased to
its `sheet_max` (64°) the main's 51.5° would bring the boom end onto the sheet, and the stop holds it at about 40°
(wm7, 39° wm12), as a real boom comes to rest on a loaded kite sheet; let fly (`sheet_max`) it holds the boom off the
sheet on every point of sail. The flying sail is placed after the main (its obstacles of §7.4 are the main as drawn).

### 7.7 The clew on its sheet
A loaded corner of cloth carries no load out of its own surface, so on a real sail the sheet leaves the clew in the
plane of the cloth there, between the foot and the leech (the radial clew panels and the clew patch are cut to fan
out round that line). The plain set shape of §6.3 does not do this: the clew corner faces the wind while the sheet
runs down and inboard to the quarter block, so the sheet left the corner 17 to 50° off its bisector (wm7 10 to 47°,
wm12 26 to 53° over AWA 60 to 160 at the optimum trims), mostly out of the cloth's plane. A real asymmetric meets the
sheet with its shape, not with a turned corner (§14.6): the sheet holds the clew in and down, the foot takes up the
cloth as a deeper round (the J/80 running is deepest at the foot, 31 %), and the lower leech leans out from the clew
to the shoulder above it. The asymmetric spinnaker's flying shape takes those two degrees of freedom, solved every
update so the corner's bisector lies on the sheet:
```
c_i = (1 - h_i / 0.3)^3 for h_i < 0.3, else 0           // the clew set's share of row i, 1 on the foot
draw-in k_d:    S_i = min(1, s_i * (1 - k_d * c_i))       // row i's chord over its flat chord (s_i of §6.3)
                d_i = sqrt(3/8 * (1 / S_i - 1))           // its camber: the cloth keeps its length
draw-down k_l:  l' = l - k_l * C_0 * c_i * uc^2           // the clew end of the low rows pulled down the luff
(a', l', n') = (a0_i + (a - a0_i) * S_i, l', 0) - e * m   // §6.3 with these S_i, d_i (e = d_i S_i C_i sin(PI uc^q_i))
corner(k_d, k_l), with the rows placed by §7.3 (twist and the ease of §7.4 included, no flutter):
  C = row 0, last column; F = row 0, column cols - 3; E = row 2, last column; B = the working lead (§11.3)
  b = unit(unit(F - C) + unit(E - C))                     // the corner's bisector, into the sail
  s = unit(C - B)                                         // the sheet, from the block through the clew
  r = ((b - s) . u1, (b - s) . u2)                        // u1 = unit(s0 x up), u2 = u1 x s0, s0 = s at (0, 0)
solve r = 0 from (0, 0): two Newton steps with forward differences (step 0.01), each step's (k_d, k_l) clamped to
  k_d in [-0.1, 0.25], k_l in [-0.1, 0.3]; a step whose Jacobian determinant is under 1e-9 stops the solve
(k_d, k_l) = g * solution,  g = (1 - smoothstep(0, 1, (|wrap_pi(beta)| - 75°) / 30°)) * smoothstep(0, 1, (|awa| - 45°) / 20°)
```
The fade `g` takes the clew set out as the kite goes round the bow in a gybe (the working sheet changes side at
`|β| = 180°`, where the sheet's load passes to the other sheet; past about 120° the corner's equations have no
solution near the start and the Newton steps could jump). No trim reaches 75°: the kites' `sheet_max` is 64°. It
also brings the clew set in from AWA 45° to 65°: closer to the wind the kite is past its working range, strapped at
`sheet_min` and luffing, the sheet carries little, and a clew drawn down there would sit on the jib's leech.
- **Draw-in** shortens the chord of the low rows and gives the cloth back as camber: the clew comes in toward the
  tack, the foot rounds (its exit at the clew steepens), and since the rows above are drawn in less the leech leans
  out from the clew to the shoulder. It is what turns the corner to face the sheet's side. Solved values at the optimum
  trims: −0.06 to −0.04 at AWA 60 (the clew let out a little), 0.03 to 0.05 at AWA 75, 0.09 to 0.11 at 90, 0.15 to
  0.25 running; running the foot then carries 39 % (wm7) to 43 % (wm12) camber (the J/80's 31 %), and the clew
  sits 0.5 m (AWA 90) to 1.1 m (running) nearer the tack on wm7, up to 2.4 m on wm12.
- **Draw-down** lowers the clew end of the low rows: the foot comes down into the clew, which lays the bisector
  toward a steep sheet (the close reach, where the clew is high over a block close aft of it). Solved values −0.02 to
  0.06 on wm7; on wm12, whose block is closer under its high clew, 0.04 to 0.12 (the clew 1.3 m lower at AWA 60).
- Both fade out smoothly up the sail (zero slope and curvature at 0.3 of the height) and along the foot toward the tack (`uc²`), so
  the foot and the leech stay fair: one curve each, no bulge or kink (test 25). The luff, the tack and the head do
  not move.
- The solve is continuous in the sail's angle, the wind and the ease, so the shape moves smoothly from frame to frame
  (tests 9, 15, 18, 21, 23 and 24 hold). Over AWA 60 to 160, the kite at 60 to 130 % of its optimum and the main from
  its optimum to let fly, the sheet leaves the clew within 4° (wm7) and 6° (wm12) of the bisector, the most at AWA 60
  where the AWA fade holds part of it back (it was up to 47° and 53°; 27° and 36° at AWA 90 at the optimum).
- The solve applies to an asymmetric spinnaker with a working lead (`sheet_lead`) in every phase: the hoist and drop
  shapes of §8.4, §8.5 take the solved flying shape as their target. Its cost is seven evaluations of three vertices
  and a second pass over the rows it reaches (about 2 µs native).
- Order per update: the shape of §6.3 with no clew set, the ease of §7.4 from it, the clew set (with that ease),
  then the placement, the clew `C0` of §7.6 and the push of §7.4.

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
    n' = the §6.2 shape evaluated with u' (and a'), u0_i = 0, ul_i - (1 - p) in place of ul_i and the chord
         C_i * clamp((ul_i - (1 - p)) / (ul_i - u0_i), 0, 1)  ; l' = l
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
The sail slides down the luff and gathers at the tack, fluttering as it comes down. A lofted kite (§6.5) keeps its
flying shape as it slides (`Tg = (af + W, lf - (thr - l_min), nf + W)` for the cloth still up), so it never relaxes
across the forestay.
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
| trimmed upwind | `d` 20–30°, `I = 0` | main with 12–15 % camber and an upper leech open to leeward; jib with 10–12 % camber at every height, draft 0.42 to 0.45, its sections opening about 11° from the foot to five sixths of the height, a slight leech hook |
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
  In Godot 4.6 the uncompressed vertex buffer is all positions (3 floats, stride 12) followed by the normal-tangent
  stream at `mesh_surface_get_format_offset(ARRAY_NORMAL)` with `mesh_surface_get_format_normal_tangent_stride`
  (8 bytes: the normal octahedral-encoded in two 16-bit units, then a tangent slot Godot adds even when none is
  given). The writer keeps a copy of the buffer from `mesh_get_surface`, rewrites positions and normals in it
  (tangent bytes untouched) and sends the whole buffer in one call per sail update.
- **Update rate by size on screen and distance**, per boat (a sphere around all its sails at any angle): every
  frame for the viewed boat (in view or not, so a camera cut never shows its sails a frame late) and for any boat
  whose sphere spans at least 20 % of the screen height (its radius over the distance times the tangent of
  half the vertical field of view; with an orthogonal camera its diameter over the view size); otherwise nearer
  than 200 m at 30 Hz (20 Hz on tier L); 200–800 m at 15 Hz; beyond at 4 Hz; outside the view frustum (the sphere
  against the camera's frustum planes) not at all, and at once on coming back into view. The boats keep out of step
  (each boat's first update in view waits a fixed share of its interval), so a rate's updates spread over its
  frames. At an update the sails, boom, pole, mainsheet tackle and running sheets are placed; between updates nothing
  of them is, and the drivers `φ`, `s_b` and `tl` and the sheets' sag advance at the next update by the time since
  the last one (at most 0.25 s), which is the same as advancing every frame. The camera's frustum is read once per
  frame for the fleet.
- **Mainsheet tackle**: its positions are rewritten in place like the sails' (uncompressed surface, positions
  stride 12, a custom AABB over every boom angle); rebuilding the surface is the fallback.
- **Material**: opaque, back faces culled (each layer faces its own side), with a back-light term (the sun through
  the cloth) and a cloth sheen instead of a plastic highlight (§11.5). With the class's baked sail textures (§11.2) the sail is drawn from them on the simple path of
  `shaders/sail_baked.gdshader`; without them, the generator's `sailcloth` slot (its colour and weave texture) with
  the procedural cloth of §11.1 and the procedural livery. Either way a copy per boat carries the boat's sail number
  and nation letters (§11.2). Opaque sails need no draw-order sorting. Shadows: `water_render.md`
  §4.6 (the shadow pass draws the sail 5 cm off the light along its normal, so the 2 mm layers never shadow each
  other).
- The sail node's transform stays the identity: the generator writes sails in the boat frame, and §7 places them in
  that frame.
- **Drawn shadow** (`water_render.md` §4.7, tiers L and M): 11 points of the placed mid-surface (luff and leech at
  the foot, a third, two thirds and the head row, mid-chord at three rows) are read each frame
  (`SailShape.mid_points`) and projected along the sun with the hull and mast. They are the sail as last updated,
  so a sail outside the view frustum casts the shadow of its last placed shape until it comes back into view.

### 11.1 Cloth
The cloth a sailmaker builds. The baked sail textures (§11.2) are drawn from this description by `tools/liverybake`
(at texture resolution, with more detail); without them it is drawn per pixel as the fallback and the GPU-cost
reference: procedural, in `shaders/sail_cloth.gdshaderinc` (no texture files), from the generator's uv sets without any change
to them: uv0 is metric (along the row aft from the luff; up the sail as the summed mean row spacing) and the same on
both layers, uv1.y is the row fraction. At load, per sail (`BoatMaterials.sail_cloth`, from the rest grid), a
material of its own gets:
- the **flat plan** `p = (a·sin θ, l + a·cos θ)` of uv0 `(a, l)`, with `θ` the mean angle between the luff and the
  rows, and the corners in it: tack `(0, 0)`, clew, head, top of the leech (the head on a pointed head);
- the row chords (distance to the leech `= (chord(row) − a)·sin θ`), the panel width and the corner patch radius.

| | woven polyester (style 0) | laminate (style 1) | nylon (style 2) |
| --- | --- | --- | --- |
| used on | main and headsails under 10 m LOA | main and headsails from 10 m LOA, every code zero | spinnakers |
| panels | cross-cut: seams square to the leech every 0.9 m | tri-radial: fans from head, tack and clew, cross-cut in the middle, 1.1 m at the fan's reach | tri-radial, 0.9 m plus 0.03 m per metre of LOA over 7 |
| seam | 16 mm, two rows of stitching | 18 mm | 10 mm |
| fine structure | the generator's weave texture (60 %) | scrim: load-path fibres every 22 mm along the panel, a diagonal grid every 45 mm | ripstop threads every 6 mm |
| roughness, through one ply | 0.82, 0.30 | 0.55, 0.20 | 0.68, 0.50 |

On every sail: edge tapes (luff 35 mm on the main, 45 mm on headsails, 20 mm on spinnakers; leech 25 mm; foot
30 mm; the head of a square-top main), reinforcement patches at the tack (0.8 r), clew and head (r = 0.06 luff,
0.045 on spinnakers; the baked sails use the sizes of §11.2) and the top of the leech of a square-top main (0.6 r):
two full plies with radial fingers of staggered length. The main has four batten pockets square to the leech at
1/5 to 4/5 of its length, the top one full length, the others 22 to 30 % of the way to the luff (the baked sails:
§11.2). Jibs and genoas carry three tell-tales 0.27 to 0.44 m
aft of the luff at 1/4, 1/2 and 3/4 of the height.

Shading: seams, tapes, patches and pockets count as extra plies. In front light every ply makes the cloth 4.5 %
greyer (up to four), stitching up to 45 % and each panel differs by ±3 % in albedo and ±0.05 in roughness (the
weave direction changes from panel to panel), so the panels read from the chase camera; against the sun the light
through the cloth falls by `exp(−0.8·plies)`, so seams, battens and patches show as darker shapes, and it grows
toward the sun (`0.75 + 0.75·max(0, −V·L)^4`). Every line is box-filtered over the pixel footprint (`fwidth` of
uv0), so detail finer than a pixel fades to its average instead of shimmering, and panel variation fades out when
panels get smaller than a few pixels. The albedo cap of 0.8 applies to the plain cloth before this.

### 11.2 Livery: the class sail set and the sail numbers
Every boat of a class carries the same sails: the class sail set of the livery file (`data_format.md` §8.3), baked
once into the class's sail textures (`data_format.md` §8.5). Only the nation letters and the sail number differ per
boat. Each boat has a copy of each sail's material (the shape and mesh are unchanged; one material and one draw per
sail as before).

**Baked sails** (the normal case): the material is `shaders/sail_baked.gdshader`, a simple path with no procedural
cloth or livery. Per pixel: the flat plan point from uv0 (computed per vertex, affine in uv0), one sample of the
layer's albedo (port image, or the starboard image mirrored), one of the ORM map and one of the normal map; one
sample of the cloth's tiling detail (weave, film or ripstop, 0.25 m tiles in the plan, albedo and relief at the
millimetre scale the sail images cannot hold), blended with the normal map; the tangent frame from the
screen-space derivatives of the plan point. The light is that of §11 (front light, the back light through the
cloth, the sheen), with the ORM blue channel as the light through the cloth in place of `backlight · exp(−0.8 ·
plies)`. The images hold what §11.1 lists and what a sailmaker adds: two-ply seams with two rows of stitching, edge
tapes, layered corner patches with radial fingers, webbing straps and stainless rings at the corners, a headboard
and the batten pockets with their battens on the main, draft stripes on the main and headsails, tell-tales on
headsails (red on port, green on starboard), the class insignia as stuck-on cloth on both sides of the main, fold
creases from flaking (crumpled creases on a spinnaker), stress wrinkles at the clew, head and tack, and a little
grime along the foot.

**The baked cloth** (2026-10-04, after the owner's "too plastic, over-exaggerated, too dark"; references §14.4).
What the images hold and how strongly, so the cloth reads as fabric from the chase camera and stays quiet at race
distance:
- **Colour**: the class sail set's colours as given (white dacron `#e4e4de`, a linear albedo of 0.77; a laminate's
  film mid grey with its load yarns darker; spinnakers in clear dyed nylon colours): nothing near black unless it is
  bare carbon. Plies show only faintly in front light (1.5 % greyer per ply, up to four; white thread on white
  cloth 12 % at most, dark thread on a laminate 30 %), panels differ by ±1.5 % in albedo, and the warm cast of
  woven polyester is 2.5 % in blue. The laminate's yarns cover at most 45 % of a texel's colour and its load bands
  darken it by 6 %. Against the sun every ply still cuts the light through the cloth by `exp(−0.8·plies)`: seams,
  patches and battens show as darker shapes in backlight, as on a real sail.
- **Roughness** (ORM green): dacron 0.82, laminate film 0.55 (a slight sheen), nylon 0.68, ±0.04 from panel to
  panel; plies a little rougher, the insignia's stuck-on cloth 0.6.
- **Panels** as §11.1 at real scale: 0.9 m cross-cut dacron panels square to the leech, 1.1 m laminate gores,
  spinnakers with radial head, tack and clew gores and horizontal panels between; 16, 18 and 10 mm seams.
- **Corners**: primary patch 0.025 luff (two plies), outer layer with fingers 0.05 luff (0.03 on spinnakers, primary
  0.015), the tack at 0.8 of that; webbing and rings as before.
- **Battens** on the main: four pockets under 10 m LOA with the top two full length, five from 10 m with the top
  three full length (J/70: five, top three; Melges 24: four, top two), evenly spaced up the leech; the short ones
  run 0.45 of the foot in from the leech; pockets 56 mm wide.
- **Creases**: in the relief only where real sails crease: flaking folds on woven polyester (soft, 0.6 mm, every
  0.4 to 0.7 m roughly parallel to the foot), a fainter set on laminates (rolled, not flaked), short soft creases on
  spinnakers (half as many as before, 0.4 mm), stress wrinkles fanning from the clew, head and tack, and a ridge
  along each batten. No crease lines in the albedo except a faint whitening on laminate folds.
- **Relief image** `<sail>_relief.png` (greyscale, the port view, data_format.md §8.5): the height of the cloth,
  white raised, black sunk, 128 flat, ±4 mm over the 8-bit range. The normal map is made from it (`tools/liverybake`
  `--normals-from-relief`, and on every run of the tool when the relief exists), so the owner paints creases, seams
  and wrinkles in grey instead of editing the normal map.
- **Fine structure**: the tiling detail (weave, film with scrim, ripstop) at millimetre scale; mipmapped, so it
  fades to its mean colour with distance and never shimmers.

**Numbers per boat**: the nation letters and the sail number go in the row slots of the sails' `layout.json` (the
baker places them by the rules below, with room for the class's widest nation and number): each row of the boat's
text at the slot's height, centred in it, shrunk to the slot's width when wider. The shader picks the row by
height and samples the boat's text texture once for each side (this layer's stack, and the other side's stack for
the light through the cloth).

**Procedural fallback** (a class without baked sail textures): the cloth of §11.1 on `shaders/sail.gdshader`, with
the class sail set's entry by role:
- **Cloth**: `dacron`, `laminate`, `nylon` set the style of §11.1 (panels, seam, fine structure, roughness, the light
  through one ply, and the share of the weave texture), `color` the albedo (capped as in §11.1), `fibre` the scrim
  or ripstop colour. Without a sail set entry the style follows the §11.1 table.
- **Design**: the panel colours of `data_format.md` §8.3 in the flat plan: height fractions are measured along the
  up axis below from the foot (0) to the head (1); `panels` alternates by the panel index of the cloth (the same
  panels as the seams); `gores` by the angle about the head.

Both paths:
- **Layer**: the grid-order mesh holds the port layer first, so a vertex index below `rows · cols` is the port
  layer, the rest the starboard layer.
- **Text frame**: in the flat plan, the reading axis `f = unit(clew - tack)` along the foot and the up axis `u`
  square to it toward the head. The port layer reads along `+f`, the starboard layer along `-f` (each reads left to
  right from its own side); up is `u` on both.
- **Character height** `h` by LOA (Appendix G1.2): under 3.5 m 0.23 m, to 8.5 m 0.30 m, to 11 m 0.375 m, over
  11 m 0.45 m; 0.2 `h` between rows and between the two sides' stacks. The insignia is drawn 1.2 `h` high.
- **Which sails** (Appendix G1.1, G1.3): the main carries the insignia, the nation letters (when the boat has
  them) and the sail number; genoas, code zeros and spinnakers the nation letters and the number; a jib none.
- **Where**: each side has a stack, top to bottom insignia, nation, number; the starboard stack is uppermost and
  the port stack below it, so the two never sit back to back. The stacks start, measured from the head point, at
  0 on the main (wholly above the arc of radius 0.6 leech when it fits), at 0.5 luff on a headsail (below the arc
  of half the luff) and at 0.4 of the foot median on a spinnaker. Each row goes at the first height, scanning down
  from there in 0.02 m steps, where its box (the text width at height `h` by `h`) lies inside the flat outline at
  least 0.6 `h` from the luff and 0.4 `h` from the leech and foot, centred on the outline's width at that height.
  When a stack does not fit above the foot, `h` shrinks in 10 % steps (down to 0.5 `h`).
- **Look**: the number colour covers the cloth like a printed or stuck-on sheet: in front light it replaces the
  albedo; against the sun the light through the cloth falls by `(1 - 0.85 c_near)(1 - 0.85 c_far)`, `c` the text
  coverage of this side and of the other side's stack, so the numbers of both sides show as shadows (the far side's
  mirrored, as on a real sail). Coverage edges are sharpened over the pixel footprint (`fwidth`) so the numbers stay
  crisp close up and fade to their average far away. On the baked path a faint darker hairline follows the edge of
  the stuck-on sheet.

### 11.3 Sheets
The working sheets of the headsails and flying sails follow the trimmed sail, so they are not in the generated model
(`tools/boatgen/README.md` "Running rigging"): the front end draws them every update from the placed clew to the
sidecar's `rig.sheet_leads` (lead block and winch, given on starboard; port is the mirror in `y`). Presentation only.

**Lead block.** A flying sail's sheet leads to a block on the rail of the aft quarter, `0.35·s` aft of the winch it
leads to (`s = (loa / 12)^0.7`; wm7 1.55 m forward of the transom, wm12 2.75 m), as on sportsboats and racers whose
spinnaker blocks sit "outboard of the primary winches and aft" (J/70 spec) or on the gunwale 2 m forward of the
transom corner (Viper 640 class rule 6.5). A block at the transom corner, the other common place, leaves the sheet
crossing the boom end when the main is eased for a run; this one lets it pass outside the leech and under the boom
(§7.6, test 23).

**Lines.** Per sail shown (not `down`), the front headsail (jib or genoa) and the flying sail (spinnaker or code
zero) each get one line per side; when two headsails or two flying sails are shown at once (a peel), the lines follow
the one further hoisted. The side of the sail angle (`sgn β`, starboard for `β > 0`) is the **working** side, the
other the **lazy** side.

| sail | working line | lazy line |
| --- | --- | --- |
| jib, genoa | clew → `headsail.lead` (the car block) → `headsail.winch` | clew → round the mast front (below) → the other `headsail.lead` → its winch |
| code zero, asymmetric spinnaker on a sprit | clew → `flying.lead` (the quarter block) → `flying.winch` | clew → round the forestay (below) → the other `flying.lead` → its winch |
| spinnaker on a pole | sheet: clew → `flying.lead` → `flying.winch` | guy: the tack (the pole end) → the other `flying.lead` → its winch |

An asymmetric spinnaker on a sprit also gets its **tack line**, from the sidecar `bowsprit_end` to the placed tack
(§7.3), as part of the flying sail's lines. The clew and tack are the placed mid-surface's corners (row 0, last and
first column), so a line moves with the sail as last updated.

**Lazy route.** A lazy line whose clew lies on the other side of the centreline from its lead runs round the front of
an obstacle: a jib or genoa sheet round the mast front (`0.6 · mast_chord` ahead of the mast axis), a flying sail's
sheet round the forestay (`0.15 · loa^0.5` m ahead of the `forestay_tack`). The waypoint `W` is where the straight
line from the clew to the lead crosses the centreline, moved forward to the obstacle's fore-and-aft position when it
lies aft of it (keeping the crossing's height; the sag and the deck then bring it down); a line whose clew is on its
lead's side has no waypoint. `W` is continuous as the clew moves, so a tack or gybe moves the line smoothly.

**Outside route.** A flying sail's sheets and the guy run outside everything, as a real kite sheet does: from the clew
round the leech side of the main and the end of the boom (or, with the clew forward, outside the shrouds and the
lifelines) to the quarter block, never through the main, the boom, the shown headsail, the shrouds or the
lifelines. In plan (model `x`, `z`; the sails stand close to vertical and the shrouds and the lifelines rise from
inside the rail, so a line clear of them in plan is clear at every height below them) the free run is the **taut
string** from its start `A` to its end `B` round the obstacles on the side of `B` (`σ = sgn(B.x)`): the shortest
path that keeps every obstacle point on the boat's side. Per update:
```
obstacles (each point with its margin m, model axes as last placed):
  the main's placed mid-surface (every grid vertex), the shown headsail's (jib, genoa; not down), and the boom
    (the corners of the box over its mesh's vertices within 0.35 s of its top, turned with the boom: the spar and
    the fittings under it, not the vang down to the mast foot): m = c_s = 0.05 + 2 * r      // r: the rope radius
  the rail on side σ: the outer edge of the deck height field (below) every 0.1 m, out by
    m = (0.01 + r) * smoothstep(B.z, B.z + 0.6, z), so the line comes in over the toe rail to the block
pivot O = (−σ · 0.15 · beam_max, 0, mast_step.z)     // a point inside the boat, a little to the other side
plan angle about O: theta(p) = atan2(σ · (p.x − O.x), p.z − O.z)   (0 ahead, π/2 abeam on side σ, π astern)
route(A, B, σ):
  if |theta(B) − theta(A)| >= π − 0.05: straight                    // never with a lead aft of the mast
  K = the obstacle points with theta strictly between theta(A) and theta(B) that lie outside the chord A–B (on
      the side away from O), each first eased in:
    under: with y_c the chord's height over the point (lerp(A.y, B.y) at its projection on the chord), the point
      moves onto the chord by smoothstep(0.1, 0.3, p.y − y_c) (its margin by the same factor): the line passes
      under a boom or a sail foot well above it (the boom over the cockpit in a gybe)
    ends: within 0.1 rad of theta(A) (or theta(B)) the point moves toward A (B) by 1 − smoothstep(0, 0.1, the
      angle): an obstacle coming into the wedge past an end starts at the end and moves out to its place
  none: straight (no waypoints)
  else: the convex chain from A to B round K (a Graham scan of K sorted by theta about O, keeping the turns
        that bend away from O), its inner vertices W_1 .. W_n; while n is over the cap (12 for a working line, 7
        for each leg of a lazy one), the vertex with the smallest turn goes and its depth outside the new edge is
        added to its neighbours' margins
  each W_i moves out along its outward bisector by (m_i + reach_i * sin(a_i / 2)) / max(cos(alpha_i / 2), 0.3):
        alpha_i its turn, a_i = sum over the vertices j of alpha_j * max(0, 1 − |l_j − l_i| / h) (the turns within
        a ring spacing, at most 2.5), reach_i = min(h / 2, l_i, l − l_i), h = the run's length / (free rings − 1):
        the straight tube between the rings either side of a corner (or of a cluster of corners) still keeps m_i
  height of W_i: the straight line's, lerp(A.y, B.y, l_i / l) by plan length along the chain
```
The working sheet (and the guy) is `route(clew, lead, σ)`; a lazy sheet with a forestay waypoint `W` is
`route(clew, W', −σ)`, `W'`, `route(W', lead, σ)`, so it passes outside the kite's own side, round the forestay and
back outside the other side; `W'` is `W` moved out along its plan bisector by `(h / 2 + c_s) · sin(α / 2) /
max(cos(α / 2), 0.3)` (`α` its turn between the clew and the lead), so the tube between the rings either side of it
stays ahead of the stay and the headsail's tack. Every term is a continuous function of the placed sails: a point
enters `K` where the chord or the wedge passes it, adding a corner of zero turn, or at an end where it starts on the
end, so the line bends smoothly away as a trim brings the leech or the boom end across it and straightens as it
clears (no pop through a trim change, a tack or a gybe). The jib and genoa lines keep their straight runs (they lead
inside the shrouds).

**Shape.** A line is a polyline of runs: the **free run** from the clew (or tack) through its waypoints to the lead, the
**lead run** from the lead block to the winch drum, then the turns on the drum and the tail (fixed in the boat).
Each run hangs as a parabola in the boat frame with its sag along gravity (the world down in the heeled boat's
frame), its depth from the line's tension:
```
q    = 0.5 * 1.225 * aws^2                          // dynamic pressure of the apparent wind, Pa
f_s  = phase in (up, prepare_drop) ? 1 : 0.1          // a hoisting, dropping or bagged sail pulls little
T    = 5 + 0.35 * q * A * f_s * (1 - I)^2             // N, working sheet or guy; A: the sail's flat area (sidecar
                                                     // area_m2), I: luff_shiver
w    = 700 * d^2                                      // kg/m, rope of diameter d (m): 0.057 kg/m at 9 mm
sag  = clamp(w * 9.81 * L / (8 * T) + 0.12 * I^2, 0.0005, 0.25)     // working: depth over span length L
sag  = 0.22                                          // lazy line (free run); its lead run with T = 5
sag  = clamp(w * 9.81 * L / (8 * T), 0.0005, 0.25)   // tack line and the lead run, with the working line's T
```
The first term is the catenary of a loaded rope (a trimmed sheet is within millimetres of straight); the second is
the slack the crew lets out as the sail luffs, up to 12 % of the span when it flogs. Per line the drawn `sag` eases
toward its target with `τ = 0.3 s` (the crew grinds in or casts off; a tack hands the load from one sheet to the
other without a jump). The lead run uses the same tension over its own length.

A point at the run fraction `t` (by length along the run's polyline, through its waypoints) is
```
P(t) = R(t) + 4 t (1 - t) * L * sag * (g * cos(psi) + s * sin(psi))
                + 4 t (1 - t) * 0.15 * L * I * sin(phi - 2 * PI * l / 1.5) * s       // whip of a flogging sheet
psi  = 0.6 * I * sin(phi)                            // the sag swings sideways as the clew flogs
```
with `R(t)` the straight polyline, `g` the unit gravity in the boat frame, `s` the unit side vector square to the run
and to `g`, `phi` the sail's flutter phase (§5.2), `l` the length from the clew (m). A lazy line swings with
`0.3 · I` of its sail and does not whip; the tack line neither swings nor whips. The lead run has no swing or whip. A lazy line's free run is at most `0.5` m deep
(`sag <= 0.5 / L`): a long kite sheet loops, it does not trail in the sea.

**Deck.** No part of a line lies below the deck: not a ring, and not the straight tube between two rings. The class's
**deck height field** is read from the boat's own meshes at load (so any deck or coachroof shape the generator
writes is followed): the highest surface over a 2.5 cm grid in model axes of the `deck` mesh of every level, raised
by the low fittings of the `hardware` meshes (hatches, tracks, cleats, padeyes: a fitting counts where it stands at
most `0.07` m above the deck there; winches, stanchions and blocks stand taller and do not), extended `0.2` m out
over the hull side at the height of the nearest deck edge (a line drapes over the toe rail instead of hanging through
the topsides), and then widened by a max filter of one cell (`ρ = 0.025` m). A line is then laid on it in two
steps:
```
every ring of a free or lead run except its ends: y = max(y, H(x, z) + r)             // H: the field, bilinear
drape, once over each run (its end rings fixed; a lift only raises the tubes either side, so a point once clear stays
  clear): for each pair of rings k, k + 1, at n = ceil(plan length / 0.025)
  points f = j / n along the straight tube (j = 1 .. n − 1):
    d = H(p) + r − p.y; when d > 0 lift ring k by d (1 − f) / D and ring k + 1 by d f / D, D = (1 − f)^2 + f^2
    (a fixed ring takes no lift, the other then takes all of it: the least lift that puts that point on the deck)
```
Since the field is widened by the drape's step, a straight tube clear of the field at its sample points is clear of
the true surface between them (within a few mm at a vertical edge): the line lies along the side deck and the foredeck, over the
cabin top, and bridges from a cabin edge, the toe rail or a hatch down to the deck as a rope does, never cutting a
corner. Outside the deck there is no limit (a kite's lazy sheet hangs ahead of the bow). The field is built natively
once per class (a few ms); its outer edge per 2.5 cm station is the rail of the outside route.

**Winch and tail.** The lead run meets the drum on its tangent (winches turn clockwise from above), the line takes
three turns up the drum (`0.34` to `0.59` of the drum diameter above its base, at the drum radius plus the rope
radius) and its tail leaves the self-tailer at the top, drops into the cockpit `0.35 · s` aft of the winch and half
way to the centreline, and lies on the floor in two short bights (`s = (loa / 12)^0.7`). These parts are fixed in the
boat and built once.

**Rope.** Diameter `2 · max(0.0045, 0.0055 · s)` m (the generator's sheets), the tack line `0.8` of it. A tube of 6 sides with a seam vertex (one texture turn around, `data_format.md` §8.5), uv0 = (metres along, the
fraction around times the rope texture tile). Materials by function (`data_format.md` §8.7): jib and genoa lines
`sheet`, flying-sail lines and the tack line `kite_sheet`.

**Mesh and cost.** One mesh per boat for all its sheets, with two surfaces (headsail lines, flying-sail lines), fixed
vertex and index counts (a hidden line collapses to a point), rewritten in place like a sail
(`mesh_surface_update_vertex_region` for positions and normals, `mesh_surface_update_attribute_region` for uv0), in
the native `SheetRopes` (one per surface; `SheetRopesRef` is the GDScript reference). The mesh is redrawn in the frames
in which any of the boat's sails is updated (§11 rates: every frame within 200 m, and not outside the view frustum),
thin (a rope under a pixel wide) at most at 15 Hz; the eased sag runs every frame. The detail goes by the size of a
metre on screen (§11.4, `BoatView.sheet_detail_for`): full while a metre is at least 31 px tall (about 30 m at 1080
lines and 60°), thin to 9.4 px (about 100 m), none beyond. Per line full: 16 rings on the free run, 4 on the lead
run, 24 on the drum and 6 on the tail; thin: 8 and 2 rings, 4 sides, no drum turns or tail. A line takes up to 16
waypoints (`SheetRopes.update`'s `ways`: that many slots per line, unused ones NaN; the headsail lines one). Cost
(native, debug build, best of batches): a wm7 with jib and kite about 75 µs per redraw with the outside route and the
drape (about 58 µs before them): the route about 6 µs, the drape about 6 µs.

### 11.4 Levels of detail
One detailed model per class (`<id>.glb`; `tools/boatgen/README.md` "The game model"), and the engine simplifies it
by its size on screen: Godot's automatic mesh LOD, generated on import (`generate_lods`), picks per frame and per
mesh the coarsest version whose error stays under the viewport's mesh LOD threshold (1 px, tier L 2 px,
`water_render.md` §7). No hand-made coarser models and no distance switches. The performance comes from fewer
pieces and materials:
- **Nodes**: `body` (hull, deck, keel, mast, rigging and the static hardware, one mesh), the moving parts `rudder`
  (with the tiller), `wheel` (and `wheel_2` on a twin-wheel class), `boom`, `mainsheet`, `pole`, and the sails; each
  node is one surface. A boat at chase range is 4 to 6 draws without the sails (wm7 4: body, rudder, boom,
  mainsheet; wm12 5 with the wheel; wm16 6 with twin wheels) and 6 to 8
  with the sails shown. The moving parts are their own nodes and follow the helm and the sail angles at every
  distance.
- **One material**: every opaque surface but the sails is drawn with one material per boat,
  `shaders/boat_atlas.gdshader`: the slot of each vertex (vertex colour green, `data_format.md` §8.5) picks its mean
  colour, roughness, metallic, tile of the shared tiling atlas (stainless, rubber, rope and gelcoat detail; the spars,
  pedestal and wheel are dark clear-coated carbon with no weave or stripe pattern, the wheel's rim a dark grip wrap)
  and livery region; the livery regions (hull, deck, transom, keel) read the boat's staged livery atlas. Glass is a
  dark opaque slot of it.
- **Paint what is flat, model what sticks up, drop what is under a pixel**: the jib and traveller tracks, the flush
  hatches (on the deck as a plain raised box about 3 cm proud whose top shows the painted frame and lens), organisers,
  the cam, horn and traveller cleats, the rudder bearing ring and the lines lying on surfaces (halyards and their
  tails, the mainsheet tail and coil, traveller lines: on the deck and the coachroof's top within 3.5 cm of the
  surface, and down the coachroof's aft face on its own rectangle of the deck image, `data_format.md` §8.5; no
  halyard coils: each tail runs as straight as it can from its clutch to its place at a low rope bag on the aft face
  either side of the companionway (the places a little unevenly spaced), passing a halyard winch's base or a hatch
  on whichever side is shorter, then over the aft edge and down the face into the bag, modelled, so a tail never
  ends in the air or flat on the top; opaque in their own colours; only where a line hangs clear in the air it stays thin rope geometry) are painted into the deck region of the livery atlas
  with their shading (darker under and around a fitting, lighter edges). Winches (about 450 triangles), clutches
  (about 80 each), the blocks that stand up (mast foot, traveller, mainsheet, cars, about 120), the cars, the mast
  foot, the mast instruments, the wind wand, stanchions, pulpit, pushpit, lifelines, rigging screws, a regatta helm
  (the wheel with a smooth rim, about 1,100 triangles, on a slim pedestal, no guard or instrument pod) or the tiller
  stay low-poly geometry. The upper mainsheet block hangs from a bail under the boom and the tackle runs from the
  traveller car up to it; it is sheared with the boom angle so it stays on the block (`BoatView.sheet_positions`). The halyard exits, sheaves, sheave boxes, bolts, the anemometer,
  the antenna and the outhaul go.
- **The own boat** keeps its full detail at chase range: its meshes have a LOD bias of 32 (`BoatView.OWN_LOD_BIAS`),
  so the engine simplifies them only where the error is under 1/32 of the threshold: the full model to about 70 m.
- **Sails**: the vertex buffer is the simulation's whole grid, updated at the rates of §11. Each sail mesh carries
  two engine levels over the same vertex buffer, every 2nd and every 4th row and column of the grid (always the last
  row and column too), keyed by their error (a cambered row of `n` segments is off its arc by about `camber / n²` of
  the chord, taken three times over for the shading); the renderer picks them by size on screen like the model's.
- **Sheets** by the size of a metre on screen (§11.3).
- **Shadows**: the visible boat meshes cast no sun shadow. The model carries the class's shadow proxy (a few
  hundred triangles: the hull with the deck, cockpit and coachroof, and the mast as `shadow`; the boom as
  `shadow_boom` under the boom node, so it swings with it; a rudder that stands above the waterline as
  `shadow_rudder` under the rudder node, so it turns with the helm), drawn only into the shadow maps (shadows
  only). The sails keep casting their own shadows (their shape changes every frame and a proxy could not follow
  it), with their engine levels. On a quality tier with `boat_cast_distance` > 0 (`water_render.md` §4.6) the
  proxies and sails of boats other than the player's own stop casting beyond that distance from the camera.
  - **Proxy shape** (`tools/boatgen`, `Boat.shadow_proxy`): it only casts where the drawn boat would, and never
    onto the boat's own lit faces. Every face lies at least the inset inside the drawn surfaces (hull, deck,
    cockpit and coachroof 4 cm; mast, boom and rudder 1.2 cm a side, shrunk toward their axes; near the transom,
    where the cockpit's sides come close to the narrowing topsides, at least 70 % of it, and the hull's bottom, which
    looks away from the sun, gives way to the lit cockpit floor over it), so no face is coplanar with or above a
    drawn surface (a coplanar caster shades its receiver in facets that crawl as the boat
    moves). The deck is open over the cockpit: its edge stands the inset back from the cockpit's sides, walls go
    down from there and the floor lies the inset under the cockpit floor (the wheel well under it stays shaded), so
    the cockpit takes the shadows of its coamings and of the coachroof, mast, boom and sails and nothing else. The
    coachroof is its section inset (the deck, raked side and top lines moved in and met at their corners). Hull and
    deck close into one shell, so the hull's shadow on the sea has no holes. Parts that stay under the water (keel,
    bulb, a spade rudder) are left out. No fittings, rigging or lines: thin casters break up into crawling dashes
    in the low tiers' shadow maps.
  - **Turning casting off** (beyond `boat_cast_distance`, or the look panel's "Boat sun shadows", `hud.md` §18):
    a proxy keeps `SHADOWS_ONLY` in every state and is hidden instead (a hidden instance draws into no pass;
    `OFF` would draw the grey proxy in the colour pass); the sails go from `ON` to `OFF`. Turning it back on
    restores exactly that set-up: drawn meshes `OFF`, proxies shown and `SHADOWS_ONLY`, sails `ON`.
- **Livery**: the boat's livery material goes on every node, so the engine's levels change the triangles, never the
  paint.

### 11.5 Light on the cloth
Both sail shaders (`sail.gdshader`, `sail_baked.gdshader`) light the cloth the same way: Lambert diffuse from the
front, the light through the cloth from behind (§11.1, `0.75 + 0.75·max(0, −V·L)^4`, shadowed), the sky's
ambient and reflections from the engine with `SPECULAR` 0.5 (F0 0.04, a polymer) and the cloth's roughness, and
**no Blinn-Phong highlight**: cloth has no mirror-like lobe. In its place a fabric sheen (the "Charlie" sheen of
Estevez and Kulla, 2017, with the visibility term of Neubelt and Pettineo), which is zero looking straight at
the cloth and rises at grazing angles, as the fibres scatter light forward:
```
a  = ROUGHNESS                                  // 0.82 dacron, 0.55 laminate, 0.68 nylon
s2 = max(1 - dot(N, H)^2, 0)
D  = (2 + 1 / a) * pow(s2, 0.5 / a) / (2 * PI)
Vs = 1 / (4 * (NdotL + NdotV - NdotL * NdotV))
SPECULAR_LIGHT += (0.03 + 0.35 * ALBEDO) * D * Vs * NdotL * ATTENUATION * LIGHT_COLOR
```
One `pow` per light, as the highlight it replaces, so the cost is unchanged. The plastic look came from the
highlight and the low roughness (0.38 to 0.55 before): a smooth, tight lobe and sky reflections at grazing angles on
the coloured kites.

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
   `n' = −0.198·Sa` (inboard, toward the windward side of the rest plane); camber `m = −0.1313`; the belly of the
   mid row (`p_i = 1`) against its luff–clew line is largest on the grid at `x = 0.4` (next to the draft 0.42) with
   `0.1310·Sa` toward port. `β = 0`: every `n' = 0`. A code zero (`camber` 0.12) keeps the shape of §6.2's last
   item.
5. **Backed headsail.** `backed` switches on: `s_b` passes 0 after 0.173 s and is within 0.04 of −1 after 1 s (−0.963); the
   belly then lies on the other side.
6. **Flutter.** Main, `I = 1`: at the head–leech corner of the rectangle the flutter term swings `±0.15·Sa = ±0.45` m.
   Phase speed at `aws = 6 m/s`: `wm7` (LOA 7.2 m, `r_f = 2.90`, `w_max = 9.04`) `w = 9.04 rad/s`, period 0.70 s;
   a 12 m boat `w = 3.6 rad/s`, period 1.75 s. Crests move toward the leech.
7. **Asym inflation.** `aws ≤ 1.543 m/s` (3 kn): `F = 0.5`; `aws = 2 m/s` (3.9 kn): `F = 0.648`; `aws ≥ 3.087 m/s` (6 kn): `F = 1`; with `I = 0` a
   mid-chord vertex moves by `d_i·s_i·C_i·sin(π·0.5^q_i)` off its shortened flat position (±1 %),
   `d_i = k_c·F·p_i` (§6.3; at mid height `p_i = 0.955`, `q_i = 0.8`), and
   the leech of each row comes in to `s_i` of its flat chord.
8. **Asym leeward belly.** For `awa` = ±60°, ±120°, ±170° with `β` at the optimum on the leeward side, every inner
   vertex of the placed kite lies on the leeward side of the vertical plane through its row's luff vertex, parallel
   to the placed tack–head line (the generated luff is cut with a curve, so vertices just aft of it can sit to
   windward of the straight tack–head plane).
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
15. **Continuity.** A scripted tack (awa from +30° to −30° over 4 s, `β` following the new side's target with the
    motion of `sails.md` §5.5 at the class's `rate_in` / `rate_out`, `backed` from its `sails.md` §7 formula) and a
    gybe (awa from 150° through 180° to −150° over 4 s) move no vertex more than `0.05·Sa` between frames at 60 fps.
16. **Cloth.** On the generated `wm7` and `wm12` sails: the cloth style and kind by sail type and LOA (§11.1),
    the flat plan (a unit shear, the clew aft, the plan height within 15 % of the tack-head distance), the row chords,
    battens on the main only, tell-tales on the jib only, one material per sail; the sail shader has the cloth
    uniforms and the shadow-pass push. The offline preview (`tests/sail_preview.py`) renders the cloth with the same
    include; its shots `cloth_main_close`, `cloth_backlit`, `cloth_kite_close` and `cloth_wm12_close` show it close
    and against the sun.
17. **Camber.** Rectangle, asym defaults, `aws` 6 kn, `awa` 90° and 150° (`β` at the leeward optimum): the largest
    distance of a row from its luff–leech line over its chord is 0.20–0.30 at mid height and smaller at the foot
    and the head (asymmetric 0.23 and 0.25 at mid height, 0.19 and 0.21 on the foot); symmetric the same at mid
    height at full fill (at most 0.30) but at least 0.9 of it on the foot (§6.4: a deep foot) and less at the head; a code zero (`camber` 0.12) at `β` 25°, 40° and
    60° 0.07–0.12, never above 0.12.
18. **Clearance.** On the generated `wm7` and `wm12` (both kites and the code zero), over TWA 60–180° (20° steps),
    TWS 6, 12, 22 kn, both tacks and the trims optimum, 15 % over-sheeted and 20 % eased (apparent wind from the
    class polar; every `β` from the class's optimum tables; the jib up at its own optimum as well as down): no edge of
    the flying sail crosses a triangle of the main or the jib or comes within the mast's radius of its line, no
    edge of theirs crosses the flying sail, and the smallest distance of a flying-sail vertex from the main, the
    jib and the mast, away from the head fade, is at least `0.9·c`; the test prints the smallest distance found.
    Each config is a steady state: the eased twist side of §7.1 is settled on its tack before the check.
    Sheeting the flying sail from 60 % to 130 % of its optimum over 2 s (TWA 100°, 12 kn, main eased 20 %, jib up)
    moves no vertex more than `0.05·Sa` between frames at 60 fps (no pop as the local push starts, grows or hands
    over to the ease). The test also prints the largest ease found (13 to 15° on the over-sheeted kite with the main
    eased or the jib up, under `e_max`; at the optimum trims with the jib down none: the push does the work).
19. **Generator parity.** The generator's preview poses and `kite_preview` set the sails with a port of §5.1,
    §6.1 to §6.4 and §7 (`tools/boatgen/boatgen/sail_set.py`: `up` phase, no luff shiver, headsails drawing) and
    write each pose's wind, angles and placed mid-surfaces to `<id>.sets.json`. BoatView, native and reference,
    given the same wind and angles on the generated `wm7`, `wm12` and the generator's symmetric-spinnaker test
    class, places every vertex within 0.01 m of the generator's.

20. **Reaching kite.** On the generated `wm7` and `wm12`, the asymmetric spinnaker at the core's optimum (main and
    kite at their optimum angles, jib down and up) on every reach with AWA 70° to 90° (TWS 6, 12, 22 kn, TWA in 2°
    steps, both tacks): the clew (row 0, last column) stays at most `0.05·LOA` forward of the mast (abreast of it or
    aft; the clew set of §7.7 draws it up to 0.25 m forward at AWA 90°, wm7 is then 0.03 m forward of the mast) and at
    most `0.3·LOA` outboard of the widest beam (2.2 m on wm7, 3.6 m on wm12), where a real reaching asymmetric sheeted
    to the quarter flies, while
    test 18 holds in every config and trim. The test prints the clew's worst position and the largest ease.
21. **Sheets.** On the generated `wm7` (jib and kite) and `wm12` (jib, code zero and kite), native and reference:
    every working and lazy line starts at its sail's placed clew (the guy and the tack line at the tack) within 1 mm,
    passes its lead block within 1 mm and meets the drum at the winch's radius; it follows the clew through a
    scripted tack and gybe (no vertex of a line moves more than `0.05·Sa` of its sail between frames at 60 fps, away
    from the sag easing); a trimmed sheet (`I = 0`, 10 kn) sags under 1 % of its span and a flogging one (`I = 1`)
    over 8 %; a lazy line never lies below the deck height field; a sail `down` hides its lines; native and
    reference agree within 1e-4 m (lines, routes and the deck field). **Clearance**: over a sweep of configs and
    trims (wm7 and wm12, jib up and down, kite up, TWA 60° to 170° on both tacks, the trims optimum, 15 % over-sheeted
    and 25 % eased, and a scripted gybe and tack), no straight tube between two rings of a flying sail's sheet comes
    within the rope radius of a triangle of the main's or the shown headsail's placed mid-surface or of the boom's
    box, and every lazy line, sampled every 2 cm along its tube, lies at or above the true top of the deck (the
    model's deck triangles); through the gybe and a kite trimmed from 60 % to 130 % of its optimum no ring
    moves more than `0.05·Sa` between frames. The test prints the smallest clearance, the deepest point under the
    deck and the cost per boat.
22. **Levels of detail.** The model has its engine levels (generated on import) and every sail mesh its two reduced
    grids over the whole grid's vertices; every node carries the boat's one livery material; the moving parts follow
    the boom and the helm; the sheets are full with the camera at 25 m, thin at 50 m and hidden at 150 m.

23. **Kite sheet straight and clear.** On the generated `wm7` and `wm12` with each asymmetric spinnaker up, through
    BoatView (native; the reference at 12 kn), over TWA 60° to 170° (10° steps), TWS 6, 12 and 22 kn, both tacks,
    the flying sail at 85 %, 100 % and 120 % of its optimum and the main at its optimum, 15 % eased and at its
    `sheet_max` (let fly), the jib down: the straight line from the placed clew to the working lead block keeps at
    least `0.5·c` from every triangle of the main's placed mid-surface and from the boom's box, and the drawn main
    never exceeds the core's angle. A kite trimmed from 60 % to 130 % of its optimum over 2 s with the main let
    fly moves no vertex of the main more than `0.05·Sa` between frames at 60 fps (the stop eases in and out). The test
    prints the smallest distances and the largest stop.

24. **Tack on the sprit.** On the generated `wm7` and `wm12`, the asymmetric spinnaker through BoatView (native and
    reference) at 12 kn over TWA 60° to 170° on both tacks, the kite at 60 %, 100 % and 130 % of its optimum with the
    main at its optimum and let fly, through a hoist and a drop (progress 0 to 1) and a gybe round the bow (the kite's
    angle through ±180°): the placed tack is within 1 mm of the sidecar's `bowsprit_end`.

25. **Clew on its sheet.** On the generated `wm7` and `wm12`, the asymmetric spinnaker through BoatView (native and
    reference) at 12 kn over AWA 60° to 160° (10° steps) on both tacks, the kite at 60 %, 85 %, 100 %, 120 % and 130 %
    of its optimum with the main at its optimum and let fly: the straight sheet from the placed clew to the working
    lead leaves the clew at most 12° off the bisector of the corner (§7.7: foot to the third vertex along the foot,
    leech to the third vertex up the leech), and the foot (row 0) and the lower leech (last column, rows 0 to 45 % of
    the height) of the flying shape, placed again without obstacles (the push of §7.4 is test 18's), are fair: the turn
    at each vertex, signed about the clew corner's normal, changes by at most 3° from one vertex to the next (no kink)
    and changes sign at most once outside a 0.5° dead band (no bulge; the 2026-10-10 clew turn fails it). The test
    prints the largest angle and turn step found.

26. **Kite set parameters.** With no `set` block every class draws as before WM-173 (tests 7 to 25 and 19
    unchanged). On the rectangle, native against reference with a non-default value of every key of §4.1 (both kites,
    sprit and pole) over random drivers, within 1 mm. The generator's two set test classes (`test_set_asym` on a
    sprit, `test_set_sym` on a pole, every key away from its default) pass test 19. The kite tuner, headless
    (`game/tests/kite_tuner_test.gd`): moving a slider changes the drawn kite, Reset to defaults gives back the
    default shape, and Save then a reload of the class file gives back the same values (and an unchanged class file
    when every value is back at its default).
    The lofted model (§6.5) on the leaning rectangle with a synthetic two-AWA loft: `loft_depth` and `loft_trim`
    move the kite, the tack and the head stay where they are hoisted, and native against reference over random
    drivers in every phase (hoist, drop) with the clearance on, within 1 mm. The tuner on wm7 (lofted): only the
    loft's sliders, the switch to the hinge model and back, Save writes `model` and the keys, and back at the
    defaults the class file is unchanged byte for byte.

27. **Lofted kite against its sections.** On the generated `wm7` (`model` `loft`). From a surface file (the AC33,
    2026-11-06): through BoatView (native and reference), the kite alone and full at the file's first AWA on both
    tacks, at heights 1/6 to 5/6 the drawn row's camber and draft are within 0.025 and 0.05 of the measured surface's
    row at that stripe (computed from the file's grid the same way). From a sections file (the J/80): through
    BoatView (native and reference), the kite alone and full at AWA 64°, 94° and 124° on both tacks: at each measured
    section's height (between the rows either side) the drawn row's camber (its largest distance from its chord over
    the chord), draft and twist (its chord's horizontal angle from the foot's, to leeward) are within 0.025, 0.05 and
    2.5° of the measured (half way: the two shapes' numbers blended by the smoothstep of §6.5). The test prints the
    table. On a lofted kite tests 8, 20 and 25 read: 8, every inner vertex on the downwind side of the vertical plane
    through its row's chord, with `β` at most the kite's `sheet_max` (64°; test 9 takes it round the bow); 20, the
    clew at most `0.32·LOA` outboard (the kite is cleared of the main by turning it out whole); 25, the sheet at most
    50° off the clew's bisector over the whole sweep of trims (the clew is set once per measured AWA at its nominal
    trim, not every update) and the foot and lower leech fair with turn steps up to 4° (the clew hook) and no bulge.

28. **The forestay rule.** On every class with a spinnaker (wm7, wm9, wm10, wm12, wm16, wm21), through BoatView
    (native), the kite at AWA 60° to 180° in 10° steps on both gybes, sheeted at 60, 85, 100 and 130 % of its optimum,
    and every 30° hoisted and dropped (progress 0.2, 0.5, 0.8, 1): the forestay passes through no triangle of the
    kite, and no vertex within 0.5 m of it athwartships, between its ends in height, lies less than 0.05 m ahead of
    it. The test prints the smallest such distance per kite.

## 13. Dependencies and open points

- The generator writes the `look` block per sail and a `pole` node (pivot at its heel on the mast, turning about the
  vertical) for pole-flown spinnaker classes (`tools/boatgen`, WM-029), and the full grid topology with the
  collapsed head vertex referenced (WM-017). Its previews draw the set sails with the shapes of this spec (§12,
  test 19), so a preview shows what a race shows.
- Running rigging: the headsail and flying-sail sheets, guys and the tack line are drawn at run time (§11.3); the
  halyards, mainsheet and control lines are in the generated model. Not drawn yet: the spinnaker halyard from the
  head to the mast (left for now by owner decision, 2026-10-04), the lazy sheet on a pole-flown spinnaker, barber
  haulers and twings. The lazy guy is not drawn by owner decision (2026-10-04).
- The cloth style comes from the sail type and the LOA (§11.1) until the class file can name it (a
  `visual.sails.<id>.cloth` key in the generator's `look` block).
- Crew, winches and tell-tales follow the sail `motion` output (`sails.md` §7) and are specified with the crew.

## 14. References

Real sails the look is checked against (collected 2026-10-04 for the sail look pass, owner: "too plastic, panels not
accurate, details over-exaggerated, colours too dark; the kite's shape is off"). Our classes: `wm7` is J/70 to
Melges 24 size (LOA 7.2 m), `wm12` ClubSwan 50 to TP52 size scaled down (LOA 12 m).

### 14.1 Asymmetric spinnaker planform

Rule measurements (World Sailing ERS: `SLU`, `SLE`, `SF` along the edges, `SHW` between the mid points of luff and
leech, three-quarter width between the 3/4 points, widths as straight lines on the flat sail):

| boat | source | SLU | SLE | SF | SHW | 3/4 width | SLE/SLU | SF/SLU | SHW/SF | 3/4 / SF |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| J/70 | International J/70 class rules 2019, G.5.3 (max) | 10.80 | 8.80 | 5.70 | 5.56 | | 0.81 | 0.53 | 0.98 | |
| Melges 24 | International Melges 24 class rules 2020, spinnaker table | 11.29 to 11.59 | 10.00 to 11.08 | 6.00 to 6.30 | 5.86 max | 3.70 max | 0.86 to 0.96 | 0.53 to 0.55 | 0.93 to 0.98 | 0.59 to 0.62 |
| J/80 | Deparday et al., Ocean Engineering 127 (2016), table 2 (design) | 12.18 | 9.65 | 7.30 | 6.85 (stripe at 1/2) | 5.05 (stripe at 2/3) | 0.79 | 0.60 | 0.94 | 0.69 at 2/3 |
| ClubSwan 50 | ORC one-design certificate CLUBSWAN50 (2021) | 24.96 | 19.91 | 12.67 | 12.62 | | 0.80 | 0.51 | 1.00 | |
| J/80 | J/80 class rules 2024, G.5 | ≤ 12.20 | | | ≥ 0.65 SF | | | | | |
| TP52 | TP52 rule 2025 | luff at least 5 % longer than the leech | | | | | | | | |

The J/80 sail's stripe lengths (Deparday table 2, flat, at 1/6 to 5/6 of the luff and leech): 7.45, 7.60, 6.85,
5.05, 2.50 m, that is 1.02, 1.04, 0.94, 0.69, 0.34 of the foot: a real asymmetric is as wide as its foot up to a
third of its height and still 0.6 of it at three quarters (Melges 24), with broad shoulders and a blunt head. ORC
counts an asymmetric with `SHW/SFL` above 0.85 as the normal case (certificate note). Rule area over `SLU²`: J/70
0.39, Melges 24 0.42, J/80 0.46, ClubSwan 50 0.38.

### 14.2 Asymmetric spinnaker flying shape

Measured on a J/80 at full scale by photogrammetry (Deparday J., Bot P., Hauville F., Augier B., Rabaud M., "Full-scale
flying shape measurement of offwind yacht sails with photogrammetry", Ocean Engineering 127 (2016) 135-143, table 3;
the lofted model of §6.5 is built from these numbers, `data/sails/j80_deparday2016.kite_shape.json`; camber and draft over the
section's chord, twist the horizontal angle of the section's chord from the foot's, entry the angle between the luff
tangent and the chord):

| section | AWA 64°: camber | draft | twist | entry | AWA 124°: camber | draft | twist | entry |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| foot | 20 % | 0.49 | | 50° | 31 % | 0.41 | | 61° |
| 1/6 | 25 % | 0.44 | 3° | 118° | 31 % | 0.46 | 10° | 84° |
| 2/6 | 27 % | 0.39 | 6° | 129° | 28 % | 0.46 | 18° | 90° |
| 3/6 | 26 % | 0.44 | 6° | 97° | 24 % | 0.48 | 23° | 59° |
| 4/6 | 18 % | 0.45 | 3° | 44° | 20 % | 0.49 | 25° | 38° |
| 5/6 | 15 % | 0.61 | 4° | 49° | 18 % | 0.67 | 26° | 51° |

- Deepest at a third of the height reaching, near the foot running; the top sixth still 15 to 18 %.
- The draft lies forward of mid chord (0.39 to 0.49) and moves aft only at the head (0.61 to 0.67).
- Reaching the sail barely twists (3 to 6°); running it twists steadily with height to 26° at the top: the clew
  comes 2.3 m forward and 1.4 m higher from AWA 64° to 141°, the luff rotates to windward and the leech opens at
  three quarters height.
- The luff curls: the entry angle is 50 to 130°, the luff "slightly folded" at tight angles. Trim guides (North
  Sails, "Trim an asymmetric spinnaker on a sport boat"; Quantum, asymmetrical trim guide) sail it with a curl
  "flicking into the luff every few seconds", a bigger curl on a broader reach, the tack line eased "a couple of
  feet" to let the sail rotate out from behind the main.
- The projected area, square to the wind, is about 0.75 of the sail area at AWA 64° and less at deeper angles.

### 14.3 Our kite against the references

wm7 kite (wm12 a2 within 0.01 of the same ratios; flying shape from `tools/boatgen` `sail_set.py`, the game's shape,
at kite_preview's reach, AWA 80°, sheet 32°, 6 m/s, and run, AWA 140°, sheet 64°, 4 m/s; camber over chord, draft
and twist of the rows at 0, 1/6 .. 5/6 of the luff):

| | before (2026-09-30) | after (this pass) | references |
| --- | --- | --- | --- |
| SLE / SLU, SF / SLU | 0.89, 0.56 | 0.85, 0.56 | 0.79 to 0.96, 0.51 to 0.60 |
| widths at 1/6, 1/3, 1/2, 2/3, 3/4, 5/6 of SF | 0.97, 0.91, 0.76, 0.55, 0.42, 0.29 | 1.00, 0.98, 0.88, 0.68, 0.53, 0.37 | 1.02, 1.04, 0.94, 0.69, 0.59, 0.34 |
| rule area wm7, wm12 (m²); over SLU² | 43.1, 126.2; 0.36 | 48.7, 142.7; 0.39 | 0.38 to 0.46 |
| reach camber foot to 5/6 | 17, 21, 21, 18, 16, 13 % | 23, 25, 24, 18, 13, 11 % | 20, 25, 27, 26, 18, 15 % |
| run camber foot to 5/6 | 18, 23, 26, 27, 24, 16 % | 24, 27, 27, 26, 23, 17 % | 31, 31, 28, 24, 20, 18 % |
| draft (run) | 0.47 to 0.54 everywhere | 0.40 to 0.48, 0.55 at 5/6 | 0.41 to 0.49, 0.67 at 5/6 |
| twist at 1/6 .. 5/6 (run) | 0, 0, 0, 2, 12° | 9, 14, 18, 21, 26° | 10, 18, 23, 25, 26° |
| entry angle (run) | 32 to 43° | 50 to 54° (17° at 5/6) | 59 to 90° |
| clew above the tack, reach / run (wm7) | 1.0 / 1.7 m | 1.7 / 2.3 m | the J/80's rises 1.4 m from AWA 64° to 141° |

The reach's upper rows are flatter and more twisted than the J/80's because the clearance push of §7.4 bends the
upper leech off the main there (that reach sheets the kite 21° inside the main). The mid girth stays a little under
the class rules' (0.88 against 0.93 to 1.0 of the foot) and the foot a little long (0.56 of the luff) so the
reaching clew stays aft of the mast (test 20). The kite areas grow by 13 % (wm7 43.0 to 48.5 m², wm12 126.0 to
142.5 m²), still at the small end of the references over `SLU²`; `data/perf` was regenerated with the VPP.

### 14.4 Sailcloth, panels and fittings

| item | reference | used here |
| --- | --- | --- |
| cross-cut panels (woven polyester) | horizontal panels stacked foot to head, square to the leech (UK Sailmakers glossary "cross cut"); cloth comes in 36" and 54" rolls (Cruising World "Sailcloth 101") | 0.9 m panels square to the leech under 10 m LOA |
| seams | 16 to 20 mm overlap with two rows of zigzag (sailmaker practice; broadseam about 1/2" per 30" in the shaping zone, 36" cloth) | 16 mm dacron, 18 mm laminate, 10 mm nylon |
| tri-radial | radial gores from head, tack and clew meeting cross-cut centre panels (North Sails A1 asymmetric and S3 symmetric, tri-radial cut) | laminates from 10 m LOA and code zeros; spinnakers: radial head, tack and clew, horizontal panels between |
| cloth weight and type | J/70 main and jib PET woven 235 g/m², spinnaker nylon 40 g/m²; Melges 24 spinnaker 40 g/m²; J/80 gennaker at least 32 g/m² | dacron, nylon |
| laminate colour | racing sails are black where carbon is bare (North Sails "Why are racing sails black?", 3Di RAW black); taffeta-covered and Endurance laminates grey, white or gold | wm12 mid grey film over darker load yarns |
| battens | J/70: 5 pockets, top 3 full length, lower 1.28 m inside; Melges 24: 4, top 2 full length; J/80: 4 | 4 pockets, top 2 full length (under 10 m LOA); 5, top 3 full length (from 10 m) |
| corner reinforcement | J/70 headsail: primary clew reinforcement at most 210 mm; small-boat rule of thumb about 1" of patch per foot of edge (8 %), layers each a little smaller | primary 0.025 luff, outer layer with fingers 0.05 luff (spinnakers 0.03) |
| class insignia | J/70: 610 × 320 mm on both sides of the main | 1.2 `h` high (§11.2) |
| reflectance | fabrics reflect close to diffusely (Sadeghi et al., "A practical microcylinder appearance model for cloth rendering", ACM TOG 2013); a thin white ripstop nylon reflects only 0.25 of sunlight, the rest goes through (radiative cooling patent US 11,306,949, measured fabrics) | white dacron albedo 0.77 (the cap 0.8), nylon light through one ply 0.5 |

Sources: [J/70 class rules](https://www.sailing.org/tools/documents/J70CR20181129-[24552].pdf),
[Melges 24 class rules](https://www.sailing.org/tools/documents/M242020CR0806-%5B26384%5D.pdf),
[J/80 class rules 2024](https://www.j80na.com/wp-content/uploads/2025/02/j80_class_rules_2024.pdf),
[ClubSwan 50 ORC certificate](https://data.orc.org/public/od/2021/CLUBSWAN50.od.html?nav=1),
[TP52 rule 2025](https://www.transpac52.org/wp-content/uploads/2024/11/2025-TP52-Rule.pdf),
[Deparday et al. 2016](https://www.juliendeparday.com/wp-content/uploads/2023/03/Deparday2016_OE_FlyingShapePhotogrammetry.pdf),
[North Sails sport boat asymmetric trim](https://www.northsails.com/en-us/blogs/north-sails-blog/trim-an-asymmetric-spinnaker-on-a-sport-boat),
[Quantum asymmetrical trim guide](https://www.quantumsails.com/en/resources-and-expertise/articles/asymmetrical-trim-guide),
[North Sails, why racing sails are black](https://www.northsails.com/en-us/blogs/north-sails-blog/why-are-racing-sails-black),
[UK Sailmakers, cross cut](https://www.uksailmakers.com/encyclopedia/glossary/cross-cut/),
[Cruising World, Sailcloth 101](https://www.cruisingworld.com/story/how-to/sail-materials-101/),
[Sadeghi et al. 2013](http://graphics.ucsd.edu/~henrik/papers/practical_microcylinder_appearance_model_for_cloth_rendering.pdf).

### 14.5 Jib camber and twist

Owner (2026-10-09): the jib sits where it should but is a little too flat and lacks twist. The shape before this
pass carried its belly against the whole sail's chord `Sa` (§3.2), so a row reaching only part of `Sa` got only a
little of it: at the jib's upwind sheet angles (8° to 12°) 2 to 4 % camber on the foot, under 1 % from mid height up,
the draft at 0.64 of the chord.

| | before | after (§6.2) | references |
| --- | --- | --- | --- |
| camber at `β` 8°, foot / 1/3 / 1/2 / 5/6 | 2.1, 0.8, 0.4, 0.1 % | 8.8, 10.2, 10.4, 9.8 % | headsails sail upwind at about 10 to 14 % camber (sailmaking practice; a 10 % section with the draft at 40 % is the worked example of One Metre's twist and camber notes) |
| camber at `β` 12° | 3.7, 1.3, 0.7, 0.2 % | 9.9, 11.6, 11.8, 11.1 % | |
| draft (fraction of the chord from the luff) | 0.55 to 0.64 | 0.44 to 0.45 | 40 to 45 % (Dellenbaugh, "Visualize the shape of your jib"; Speed and Smarts, jib and genoa trim: 40 to 45 % draft-forward, 45 to 47 % a No. 1 genoa) |
| twist, foot to 5/6 of the height, at `β` 12° (chord angles, wm7) | 7.2° to 15.7° (8.5°) | 7.2° to 18.5° (11.3°) | the leech opens up the sail to follow the twisted apparent wind (the top tell-tales break with the bottom ones) |
| foot chord angle (the clew) | 7.2° | 7.2° | unchanged: the owner's "position is good" |

Sources: [Dellenbaugh, Visualize the shape of your jib (Scuttlebutt)](https://www.sailingscuttlebutt.com/?p=131526),
[Speed and Smarts, jib and genoa trim](https://www.speedandsmarts.com/toolbox/articles2/the-fast-course/jib-and-genoa-trim),
[One Metre, sail twist](https://onemetre.net/Design/Twist/twist.htm).

### 14.6 Asymmetric spinnaker size, planform and sheet (2026-10-09)

Owner: the kite's clew sits at a bad angle, mostly from the kite's shape; a bigger kite is fine if real data supports
it; the sheet must never come close to the boom or the main. ORC one-design and individual certificates (**SLU**,
**SLE**, **SFL**, **SHW**; **TPS** the tack point from the mast; ratios computed here):

| boat | area m² | SLU | SLE | SFL | SHW | TPS | main m² | A / SLU² | SF / SLU | SLE / SLU | SHW / SF |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| J/70 | 45.64 | 10.80 | 8.80 | 5.70 | 5.56 | 4.00 | 15.44 | 0.39 | 0.53 | 0.81 | 0.98 |
| Melges 24 (rig of wm7: I 8.62, J 2.51, P 8.82) | 56.18 | 11.59 | 11.08 | 6.30 | 5.86 | 4.11 | 21.38 | 0.42 | 0.54 | 0.96 | 0.93 |
| J/80 | 64.99 | 12.20 | 9.90 | 7.37 | 6.98 | 4.80 | 20.91 | 0.44 | 0.60 | 0.81 | 0.95 |
| Viper 640, RS21 (class maxima) | | 9.72, 10.21 | 7.60, 8.10 | 5.63, 5.40 | 5.50, 5.22 | | | | 0.58, 0.53 | 0.78, 0.79 | 0.98, 0.97 |
| Melges 32 | 125.49 | 17.00 | 14.57 | 9.70 | 9.50 | 5.90 | 41.31 | 0.43 | 0.57 | 0.86 | 0.98 |
| IC37 | 149.91 | 18.54 | 15.91 | 11.06 | 10.29 | 6.79 | 49.41 | 0.44 | 0.60 | 0.86 | 0.93 |
| J/111 A2 | 149.58 | 18.40 | 15.20 | 10.54 | 10.72 | 6.62 | 36.34 | 0.44 | 0.57 | 0.83 | 1.02 |
| J/122E A4 (rig of wm12: I 16.6, J 4.57, P 15.65) | 159.43 | 20.20 | 16.55 | 10.50 | 10.39 | 6.49 | 49.50 | 0.39 | 0.52 | 0.82 | 0.99 |
| ClubSwan 50 | 236.13 | 24.96 | 19.91 | 12.67 | 12.62 | 8.24 | 90.26 | 0.38 | 0.51 | 0.80 | 1.00 |

Asymmetric areas on the ORC certificates of comparable 12 m racers: J/122 143 to 152 m², J/121 149 to 167, ClubSwan 36
143 to 145 (class rule 125 to 145, `SHW` at least 0.85 `SFL`), J/124 131 to 157; sportsboats: SB20 43 to 45, Melges 20
39 to 44. Running spinnakers have `SHW / SF` 0.93 to 1.02 (sailmakers: about 1.05 measured as `SMG`), reachers less
(J/111 A3 0.93, A5 0.76); ORC calls a sail with `SHW` under 0.75 `SFL` a headsail.

- **Size**: our planform's mid girth goes from 0.88 to 0.95 of the foot (§14.3 kept it under the references so the
  reaching clew stayed aft of the mast; the clew is set by the foot and the leech, not the mid girth, so it stays where
  it was). Luff, leech and foot stay (SF/SLU 0.56, SLE/SLU 0.86 along the edges, inside the references). Areas: wm7
  48.5 to 52.5 m² (A/SLU² 0.41; the Melges 24 on the same rig carries 56), wm12 142.5 to 153.5 m² (0.41; J/122 and
  J/111 A2 about 150). Area over the main: wm7 2.2, wm12 2.6 (references 2.6 to 4.1; our mains are large for the rig).
- **Clew**: the plain set shape (§6.3, §7.3) turns the clew to face the wind, so the sheet leaves the corner 17 to 50°
  off its bisector, mostly out of the sail's plane. Turning the cloth round the clew toward the sheet (2026-10-10)
  bulged the lower leech and was removed (§7.5). What real sails show (2026-10-15): no source measures the angle at
  the clew, but the cloth decides it. A membrane corner carries load only in its own surface, so the sheet lies in the
  cloth's plane at the clew, between the foot and leech tapes, which take most of the load; sailmakers cut the radial
  clew panels to fan out from the sheet's line, and photographs of set kites from astern and to leeward show the clew
  pointing along its sheet, the clew patch flat along it, the foot rounding forward from the clew and the leech
  leaning out from the clew to a shoulder wider than the clew (the sheet holds the clew in under it). The J/80
  sections (§14.2) are deepest at the foot running (31 %) and their luff entries match circular arcs of their camber
  (50° at 20 %, 61° at 31 %), as a pressure-loaded membrane under even tension sets. §7.7 reproduces that: the sheet
  pulls the clew in (a deeper foot round, the leech leaning out) and down, solved so the sheet runs along the corner's
  bisector; within 6° in every trim, where a real corner sits within roughly 10 to 15° (the sheet nearer the tape
  that carries more load).
- **Lead block**: §11.3. Trim guides lead the sheet to "blocks on the leeward quarter", "just forward of the stern
  pulpit" (Quantum), "outboard of primary winches and aft" (J/70); the Viper 640 rule puts them 2 m forward of the
  transom corner. The sheet runs outside all rigging (Quantum, Flynn), the clew flies outside and aft of the boom and
  main, and an over-eased main traps the kite behind the boom (North Sails J/80 guide).
- **Tack line**: two-blocked reaching, eased 0.3 to 0.45 m running deep (North Sails Melges 24 and J/80 guides);
  the J/70 sails it two-blocked (Doyle). Owner (2026-10-11): the tack stays on the sprit fitting, so `tack_line_max`
  is 0 and the rest tack is the sprit end itself (it was 0.12 m above it).
- No source gives the clew height above the deck or a sheeting angle in degrees; trim guides say the clew rises as the
  sheet is eased and twings bring it down running (Yachting World).

Sources: [ORC J/70](https://data.orc.org/public/od/2019/j70.od.pdf),
[ORC Melges 24](https://data.orc.org/public/od/2019/melg24.od.pdf),
[ORC J/80](https://data.orc.org/public/od/2019/j80.od.pdf),
[ORC Melges 32](https://data.orc.org/public/od/2020/melg32.od.pdf),
[ORC IC37](https://data.orc.org/public/od/2020/ic37.od.pdf),
[ORC ClubSwan 50](https://data.orc.org/public/od/2019/CLUBSWAN50.od.pdf),
[J/111 ORC certificate PER 066](http://www.copagalapagos.com/certificados-orc/2017/PER066.pdf),
[J/122E ORC certificate](https://www.vicmaui.org/pdfs/2018-documents/VM2018%20ORC%20Joy%20Ride%20ORCi%20Certificate%20rev%20June%202018.pdf),
ORC certificate data (`data.orc.org`, boat RMS files) for the J/121, J/122, J/124, ClubSwan 36, SB20, Melges 20,
[ClubSwan 36 class rules 2026](https://www.nautorswan.com/w1/wp-content/uploads/2026/03/36-ClubSwan36-Class-Rules-2026_Version-26-01_March-2026_clean.pdf),
[Viper 640 class rules](https://www.ussailing.org/wp-content/uploads/2020/09/Viper-640-Intl-Class-Rules-updated-January-1-2020-1.pdf),
[RS21 class rules](https://www.rs21italianclass.org/_files/ugd/812873_96486ffcf2db4d5482bbe7bb94eeb435.pdf),
[J/70 specifications](https://jboatssouthwest.com/wp-json/wp/v2/posts/334),
[Quantum asymmetrical trim guide](https://www.quantumsails.com/en/resources-and-expertise/articles/asymmetrical-trim-guide),
[North Sails J/80 tuning guide](https://yachting.web.cern.ch/documentation/keelboats/files/j80/North_Sails_Tuning_Guide.pdf),
[North Sails Melges 24 tuning guide](https://www.northsails.com/sailing/en/resources/melges-24-tuning-guide),
[Yachting World, spinnaker trim](https://www.yachtingworld.com/features/sail-faster-sail-safer-advanced-techniques-series-part-9-spinnaker-trim-76224),
[UK Sailmakers, spinnaker design brief](https://www.uksailmakers.com/2023/10/02/spinnaker-design-technical-brief-in-seahorse-magazine/).

### 14.7 Measured kite surfaces (2026-11-06)

Complete measured 3D flying shapes, the sources of §6.5's surface source (the research notes:
`docs/design/kite_research/flying_shapes_2026-11.md`, sections 6 and 7):

| kite | what it is | source | licence | used for |
| --- | --- | --- | --- | --- |
| AC33 benchmark asymmetric spinnaker | the flying shape at its optimum AWA 55°, measured by photogrammetry in the Auckland twisted-flow wind tunnel and built as a rigid 1:106 model (span 300 mm, 16° twist foot to head; 510 m² full size) | Arredondo-Galeana A., Viola I. M. (2020), *PIV dataset for near wake of spinnaker: Vortex flows of downwind sails*, University of Edinburgh DataShare, https://doi.org/10.7488/ds/2857, file `Geometries/IGS_format/Spinnaker_high_twist_16deg.igs`; Viola I. M., Flay R. G. J. (2011), Ocean Engineering 38, 1733-1743; Arredondo-Galeana A. (2019), PhD thesis, University of Edinburgh, http://hdl.handle.net/1842/36074 | CC-BY 4.0 | wm7 (`ac33_asym`) |
| IACC parametric symmetric spinnaker series, sails I to V | rigid 1:25 wind-tunnel models in closed form, the same girth, foot camber 23.0, 28.5, 34.8, 39.8, 44.6 % | Moore P. (2004), ME thesis, University of Auckland; Lasher W. C., Richards P. J. (2007), Journal of Ship Research 51(1), 22-38, https://doi.org/10.5957/jsr.2007.51.1.22; equations and coefficients as reprinted in Peart T. (2022), PhD thesis, University of Auckland, appendix A, https://researchspace.auckland.ac.nz/handle/2292/64018 | published equations (cited) | wm21 (`iacc_sym_series`) |

The AC33 model is solid (about 3 mm thick inside, bevelled to 10 mm at the edges); the surface used is its outer
(leeward, convex) face, the largest of its 36 trimmed NURBS faces; the mounting bosses and the edge faces are left out.
Along the cloth: luff 330.5 mm, leech 288.5 mm, foot 193.6 mm (leech / luff 0.87, foot / luff 0.59), deepest about
0.40 of the tack-clew distance. The series reproduces Peart's foot cambers to 0.1 % (`tests/test_kite_surface.py`).
