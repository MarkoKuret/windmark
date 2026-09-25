# Wind shadow

Every boat disturbs the air downwind of its sails. A boat sailing in that disturbed air gets less wind and a
header. This is the core of fleet tactics: covering, clearing your air, the safe leeward position, starting-line
positioning. The model is geometric and cheap: two zones per boat (blanket and backwind), evaluated from a per-tick snapshot, the
strongest one wins.

## 1. Zones

For a source boat `B`:

1. **Blanket**: the wind shadow of the sail plan, along `B`'s apparent wind, starting at its centre of effort.
   Long (about 3 mast heights in a moderate breeze), widening downwind, strongest a short distance behind the
   sails. It exists on every point of sail: upwind it lies to leeward and behind, downwind it lies ahead of `B`
   (a boat running behind you steals your wind).
2. **Backwind**: upwind only, a band of disturbed air astern of `B`, angled a little to windward of its wake
   line, shorter and weaker than the blanket. It is what makes sitting astern and to windward of a boat slow even
   outside its blanket, and it is why the safe-leeward position works: the boat to leeward and ahead puts the
   boat to windward and behind in its backwind.

A receiving boat in either zone gets a **speed loss** `l` (fraction of the wind speed) and a **header** `δ` (the
wind bent to follow `B`'s sails, heading boats on `B`'s tack).

## 2. Parameters

Per class, in the performance file `dynamics.wind_shadow` (`data_format.md` §4.2). The boat generator derives the
geometric ones from the rig; the rest are model constants with the defaults shown.

| name | unit | S | L | meaning |
| --- | --- | --- | --- | --- |
| `height` | m | 10.5 | 33 | masthead height above the waterline |
| `ce_x` | m | body x | body x | centre of effort of the sail plan (body x) |
| `stern_x` | m | body x | body x | body x of the transom |
| `chord` | m | 6.5 | 30 | fore-aft length of the sail plan (≈ J + E) |
| `width_min` | m | 4 | 12 | source width when the sail plan is seen end-on (running without spinnaker: ≈ 1.5 E) |
| `width_spinnaker` | m | 7 | 22 | the same with a spinnaker up (≈ spinnaker foot + E) |
| `length_coef` | – | 4.5 | 4.5 | blanket length per mast height at high apparent wind |
| `length_knee` | m/s | 4.12 | 4.12 | apparent wind speed at which the length reaches half its high-wind value (8 kn) |
| `blanket_depth` | – | 0.22 | 0.22 | peak loss of the blanket |
| `blanket_depth_spinnaker` | – | 0.25 | 0.25 | peak loss with a spinnaker up |
| `blanket_peak` | – | 0.25 | 0.25 | where along the blanket the loss peaks (fraction of its length) |
| `blanket_near` | – | 0.7 | 0.7 | relative loss right at the sails |
| `blanket_reach_up` | – | 0.05 | 0.05 | how far upwind of the centre of effort the blanket fades in (fraction of length) |
| `blanket_spread` | – | 0.10 | 0.10 | half-width growth per metre downwind |
| `turb_length` | – | 0.4 | 0.4 | backwind length as a fraction of the blanket length |
| `turb_depth` | – | 0.15 | 0.15 | peak loss of the backwind |
| `turb_width` | m | 2.5 | 5 | backwind half-width at the stern (≈ beam) |
| `turb_spread` | – | 0.3 | 0.3 | its growth per metre astern |
| `turb_angle` | rad | 10° | 10° | angle of the backwind band to windward of the astern direction |
| `turb_awa_fade`, `turb_awa_max` | rad | 70°, 75° | 70°, 75° | backwind fades out between these apparent wind angles |
| `header_coef` | rad | 0.4 | 0.4 | header per unit of loss |
| `header_max` | rad | 3° | 3° | largest header |

## 3. Snapshot

In tick step 4 (`conventions.md` §4.1), for each boat, from its state at `t_n` (`boat.md` §3):
`pos_x`, `pos_y`, `psi`, `aws`, `awd_from`, `awa`, `twa`, `spinnaker` (the front sail is a spinnaker of either type and
it is `up` or `prepare_drop`), and `casts` (the race layer may exclude boats: not yet launched, retired, ghost;
`race.md`). All shadows of the tick are computed from this snapshot, so boat order does not matter and a boat's
shadow lags its motion by one tick (50 ms, invisible).

## 4. Loss from one source

`shadow(B, px, py) → (l, δ)` for a receiving point `(px, py)`:
```
if !B.casts: return (0, 0)
ax = -sin(B.awd_from) ; ay = -cos(B.awd_from)          // unit vector the apparent wind blows toward
nx = ay ; ny = -ax                                      // perpendicular
fx = sin(B.psi) ; fy = cos(B.psi)                      // bow direction
aws = B.aws
Lb = height * length_coef * (aws / (aws + length_knee))  // blanket length, m
if Lb < 1: return (0, 0)
cx = B.pos_x + ce_x*fx ; cy = B.pos_y + ce_x*fy        // centre of effort
dx = px - cx ; dy = py - cy
if dx*dx + dy*dy > (1.25f*Lb + width_spinnaker) * (1.25f*Lb + width_spinnaker): return (0, 0)   // far away

// blanket
xi  = dx*ax + dy*ay                                     // metres downwind of the sails
eta = dx*nx + dy*ny                                     // metres across
wsrc = max(chord * fabsf(sin(B.awa)), B.spinnaker ? width_spinnaker : width_min)
W   = 0.5f*wsrc + max(xi, 0) * blanket_spread
s   = xi / Lb
lb  = (B.spinnaker ? blanket_depth_spinnaker : blanket_depth) * p_long(s) * p_lat(fabsf(eta) / W)

// backwind
lt = 0
aa = fabsf(B.awa)
if aa < turb_awa_max:
    fade = aa <= turb_awa_fade ? 1 : (turb_awa_max - aa) / (turb_awa_max - turb_awa_fade)
    tk = sgn(B.twa)                                     // +1: windward side is starboard
    ca = cos(turb_angle) ; sa = sin(turb_angle)         // constants per class
    wx = (-ca*fx) + (tk*sa)*fy ; wy = (-ca*fy) - (tk*sa)*fx   // astern, turned toward windward
    tx = px - (B.pos_x + stern_x*fx) ; ty = py - (B.pos_y + stern_x*fy)
    xt = tx*wx + ty*wy ; et = tx*wy - ty*wx
    Lt = turb_length * Lb
    if xt > 0 and xt < Lt:
        st = xt / Lt ; q = 1 - st*st
        lt = ((turb_depth * fade) * (q*q)) * p_lat(fabsf(et) / (turb_width + xt*turb_spread))

l = max(lb, lt)
delta = min(header_coef * l, header_max)
return (l, delta)
```
Profiles (smooth, zero at their ends):
```
p_long(s):  s <= -blanket_reach_up or s >= 1 : 0
            s < 0            : blanket_near * (1 + s / blanket_reach_up)
            s < blanket_peak : r = s / blanket_peak ; blanket_near + (1 - blanket_near) * (r * (2 - r))
            else             : u = (s - blanket_peak) / (1 - blanket_peak) ; (1 - u*u) * (1 - u*u)
p_lat(q):   q >= 1 : 0 ; else (1 - q*q) * (1 - q*q)
```
(`sin`, `cos` are `wm_sin`, `wm_cos`.) Operations are evaluated in the order written; products of three factors
associate left to right.

Sizes: at 8 m/s apparent wind the S blanket is 31 m long (3 mast heights), 22 % loss at about 8 m behind the sails
on its axis, half-width 3–6 m; the L blanket is 98 m long. In light air (2 m/s apparent) both shrink to about
half, and in a strong breeze (20 m/s) they grow by another quarter: shadows reach further when there is more wind
to disturb.

## 5. Wind at a receiving boat

In tick step 5, for receiving boat `i` with clean wind `(U, from)` at its hull reference point (`wind.md` §2):
```
best_l = 0 ; best_d = 0 ; best_tack = +1
for j = 0 .. boat_count-1, j != i:                     // index order
    (l, d) = shadow(snapshot[j], boat_i.pos_x, boat_i.pos_y)
    if l > best_l: best_l = l ; best_d = d ; best_tack = sgn(snapshot[j].twa)
wind_speed = U * (1 - best_l)
wind_from  = wrap_2pi(from - best_tack * best_d)
```
- Only the **strongest** source counts (shadows do not stack), with its own header. Ties go to the lower index.
- **Header sign**: the bent wind follows the source's sails. For a source on starboard tack (`twa > 0`) the wind
  in its shadow backs (`from` decreases), which heads a receiver on starboard tack and lifts one on port. So a boat
  just to leeward and behind on the same tack gets less wind **and** is headed, and has to tack or foot out.
- The receiver's own point is its hull reference point; the whole boat sails in the wind at that point.

## 6. Tactical reading

| position relative to `B` (upwind, same tack) | effect |
| --- | --- |
| directly downwind along `B`'s apparent wind, within 1–3 mast heights | blanket: up to 22 % less wind and a 3° header |
| astern and to windward, within about 1.5 boat lengths | backwind: up to 15 % less wind and a smaller header |
| to leeward and ahead ("safe leeward") | clear air; `B` sits in this boat's backwind |
| to windward and abeam or ahead | clear air |
Downwind, the blanket of a boat behind reaches ahead of it: the boat behind can blanket the boat in front.

Where safe leeward starts: the leeward boat is clear of `B`'s blanket once its hull reference point is more than
`blanket_reach_up · Lb` upwind of `B`'s centre of effort along `B`'s apparent wind (`ξ ≤ −blanket_reach_up · Lb`,
§4), or wider than the blanket (`|η| ≥ W`). Close-hauled in 7 m/s true wind with the reference values of §2:
S is clear about level with `B` at 3 m to leeward (1 m ahead at 2 m, already 3 m behind at 5 m); L about 8 m
ahead at 2 to 5 m to leeward, 3 m ahead at 8 m. Closer to `B` or further back, the leeward boat sails in `B`'s
blanket instead.

## 7. Queries

| query | returns | used by |
| --- | --- | --- |
| `shadow(j, x, y)` | `(l, δ)` from boat `j` at a point | AI (bad-air detection, covering) |
| `shadowed_wind(i, x, y)` | the wind boat `i` would get at a point from all other boats | AI look-ahead |
| `shadow_zones(j)` | the blanket and backwind outlines for drawing | HUD overlay, training mode |

For drawing, the blanket outline is the curve `|η| = W(ξ)` for `ξ ∈ [−reach_up·Lb, Lb]` and the
backwind outline `|η_t| = turb_width + ξ_t·turb_spread` for `ξ_t ∈ [0, Lt]`, in the frames of §4.

## 8. Tests

1. Zero loss upwind of any source and beyond `1.25·Lb`; loss exactly `blanket_depth` at `s = blanket_peak` on the
   axis; symmetric in `η`.
2. Two boats on the same tack, the second placed 2 mast heights downwind on the first's apparent wind axis: the
   second's speed settles lower than the first's by the factor of its polar at the reduced TWS, and its heading
   at optimal VMG turns lower by the header.
3. No dependence on boat order: permuting boat indices permutes the per-boat winds and nothing else (up to the
   tie rule).
