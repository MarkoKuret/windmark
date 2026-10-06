# AI skippers

Computer-sailed boats that fill every race: they start, sail the course with sensible tactics, respect the racing
rules, and differ by level. They run in the core on the authoritative side (the server online) in step 2 of the tick
(`conventions.md` §4.1), after the race and rules update of step 1, and write the boat's controls for this tick
through exactly the same **input frame** a human produces (`h_cmd`, `sheet_cmd`, `auto_trim`, `let_fly`, sail
requests; `boat.md` §2, `networking.md` §4). They cannot do anything a human boat cannot.

Conventions: `conventions.md` (`twa` positive = wind from starboard, compass angles, binary32, `wm_*`) and the race
helpers of `race.md` §0. Polar quantities come from the class performance file (`data_format.md` §4, `sails.md` §6);
rules information from the rules engine records (`rules.md` §11); wind from `wind.md` and `wind_shadow.md`.

## 1. Principles

- **Same boat, same controls.** The AI steers with the tiller and trims with the sheets through the input frame.
  Its boat uses the normal physics. The only physical difference is the level's `performance_scale` (§13).
- **Same information.** The AI reads its own boat's instruments, the positions and motion of the other boats, the
  course, the rules engine's published verdicts, and the wind at its own boat. Expert and Pro may also "read the
  water" (sample the present clean wind within a radius, §3.3), which a human does by looking at the puffs. No AI
  evaluates the wind at a future time or reads the race-wide `global_from` / `dir_offset` (`wind.md` §9 allows it
  technically; Windmark's AI does not, so it knows no more than a good sailor could see), and no AI reads another
  boat's inputs. Two things a sailor knows before the gun it may use: the **tidal stream** (`wind.md` §7: the current
  anywhere on the course now, as from a tidal atlas and the stream round the marks; it is steady through a race), and
  the **briefing** (`menus.md` §1.3: the venue's trend over the race, the same number the race card shows). Both hold
  in every weather mode, Random included, where the player sees no briefing (owner decision, 2026-10-06).
- **No catch-up.** Nothing in the AI or its boat depends on the race position or the gap to others.
- **Deterministic.** Same seed, same inputs, same results: all randomness comes from the generator of
  `conventions.md` §7 with the race seed, in the AI streams: stream 16 = start choices (spot spread, start error),
  stream 17 = other random choices; `index = (boat_index << 32) | k`, with `k` a per-boat draw counter for that
  stream (kept in the AI state, reset at race start). All loops run in a fixed order.
- **Budget.** Decisions run at 10 Hz, the helm every tick. The decisions are staggered by boat: boat index `i`
  decides on the ticks `n` with `n + i` even, so half the fleet decides on each tick and the cost of a tick does not
  peak every second tick (the fleet assignment of start spots, §5.2, stays on even ticks). A boat with no decision yet
  decides on her first tick whatever its parity. Average cost ≤ 0.2 ms per AI per decision on the server reference
  machine, so a 40-boat race costs < 1 ms per tick for the AI; no single tick should cost more than 2 ms for
  16 boats on the development machine (`windmark_race_bench`).

## 2. Structure

```
Perception (every tick) ─► Strategy (10 Hz): route for this leg, tack/gybe plan
                          ─► Tactics (10 Hz): start, marks, rules avoidance, bad air, cover, penalties
                          ─► Manoeuvre state machine: straight / tack / gybe / rounding / penalty turn / brake
                          ─► Helm and trim (every tick) ─► input frame for the next tick
```

Tactics can override strategy; rules avoidance (§7) can override everything except an emergency (§7.5). Each
decision records its reason (`AiTactic` enum, §15) for tests and the debug overlay.

## 3. Perception

### 3.1 Polar tables (per class, built at load)

From the performance file's `polar` table of every config (main only, main + each front sail; `sails.md` §6), for
every true wind speed on a grid of 0.25 m/s from 0 to 20 m/s:

- `θ_up(TWS)`, `V_up(TWS)`: the upwind VMG optimum (TWA and boat speed maximising `V·cos θ`, searched in 0.25° steps
  over 25°–90°);
- `θ_dn(TWS)`, `V_dn(TWS)`: the downwind optimum (maximising `−V·cos θ` over 90°–180°);
- `V(TWS, TWA)` of the best config, and `best_sail(TWS, TWA)` (its front sail, or none);
- `VMG_up = V_up·cos θ_up`, `VMG_dn = −V_dn·cos θ_dn`.

Each is taken over the configs the boat can fly (the best one wins). Lookups interpolate linearly in TWS.
`θ_CH` (close-hauled, as used by the rules) is `θ_up` of the best upwind config. The polar already includes the
boat's optimal leeway (`boat.md` §6.4); the tables are multiplied by the boat's `performance_scale` only where the
AI predicts its own speed.

### 3.2 Own state

Position, heading ψ, `sog`/`cog`, boat speed `v`, `turn_rate`, heel, sail state, tack, race state (next step,
OCS, penalties, deadline), rules records involving the boat.

### 3.3 Wind

- Clean wind at the boat: `wind_speed_clean` and its direction (`boat.md` §2, `wind.md` §9 `wind_clean`), taken
  **relative to the water** (the wind over the ground minus the current at the boat, as her instruments read it and
  as she sails in it, `boat.md` §5.1; without current it is the ground wind itself), smoothed with a 2 s exponential
  filter: `TWD_f`, `TWS_f`. Every TWA, close-hauled heading and polar speed of this file uses it; so does the tack of
  another boat (her clean water wind).
- Felt wind: the boat's `wind_speed`, `wind_from` (with other boats' shadow), relative to the water, smoothed 2 s:
  `TWS_felt`.
- `TWD_ref`: the AI's idea of the mean direction: exponential average of `TWD_f` with a 90 s time constant (angles
  averaged as unit vectors).
- Shift `Δ = wrap_pi(TWD_f,5s − TWD_ref)`, with `TWD_f,5s` a 5 s average (positive = clockwise veer).
- Deficit `d = 1 − wind_speed / wind_speed_clean` (unsmoothed values; 0 = clean air), then smoothed 2 s. This is
  the shadow loss `l` of `wind_shadow.md` §5.
- Reading the water (Expert, Pro): `wind_clean(x, y, t_n)` at sample points on the two candidate tracks (current tack
  and other tack) at 100, 200, …, `R_read` m ahead (§13), at the present tick only, once a second: on the boat's
  decision ticks with `(n + i) mod 20 = 0` (boat index `i`, §1).

### 3.4 Others

The other racing boats within `20·L` sorted by hull gap, each with position, heading, speed, turn rate and the pair
record from the rules engine (`rules.md` §11.1: obligation, states, room, ttc). Ghosts are ignored.

### 3.5 Course

Next step and its geometry, laylines (§4.3), leg type (§4.1), the step after (for planning the rounding and the
sail change), mark zones.

## 4. Strategy: sailing a leg

### 4.1 Leg type

With the target point `R` (buoy, gate buoy chosen in §6.3, or the nearest point of the finish line) and
`θ_R = |wrap_pi(TWD_f − compass(R − c))|`:

- **beat** if `θ_R < θ_up + 3°`,
- **run** if `θ_R > θ_dn − 3°`,
- **reach** otherwise,

with a 3° hysteresis on each boundary so the type does not flicker.

### 4.2 Reaching

Steer the direct course to the aim point of the mark approach (§6.1), adjusted for the current so the course over
ground points at it: `ψ = compass(R − c) − wrap_pi(cog − ψ)` with the present drift angle (the boat model folds
the leeway of a sailing boat into the polar, `boat.md` §6.4, so with way on the drift is the current alone). The
correction is solved for the speed she will make on that course, her own and at least `0.8 ×` the polar speed: a
slow boat's own speed would turn the heading into the wind and keep her slow. Sail: `best_sail` for the present TWA.

### 4.3 Beating and running: headings, laylines, tack points

- Target headings on the two tacks: upwind `ψ_port = TWD_f + θ_up`, `ψ_stbd = TWD_f − θ_up` (port tack has
  `twa < 0`); downwind `ψ_port = TWD_f + θ_dn`, `ψ_stbd = TWD_f − θ_dn`.
- **Speed build**: if boat speed < 0.85 × the polar target, sail 4° lower upwind (away from the wind) or 4° higher
  downwind until it is back above 0.92 ×.
- **Laylines**: the layline of tack t through R is the ray from R backwards along the course over ground the boat
  would have on tack t: `COG_t = compass(V_t·dir(ψ_t) + current)` with `V_t` the polar speed on that tack. The present
  tack's track takes the current at the boat; the layline through R takes the mean current between the boat and R
  (three samples at 1/6, 1/2 and 5/6 of the way, `wind.md` §7), so a stream that is stronger mid-channel or weaker
  near the mark sets the tack point; without current, `COG_t = ψ_t`.
- **Tack point** `I`: the intersection of the ray from `c` along the current COG and the layline of the other tack.
  If it exists, `d_I = |I − c|`.
- **Layline trigger**: tack (gybe) when `d_I ≤ 0.5·V·t_man + M_lay`, with `t_man` the class's typical tack (gybe)
  duration (constants of this file: 6 s tack, 5 s gybe; scaled by `0.5·(1 + L / 10 m)` for longer boats) and `M_lay` the level's overstand margin (§13). A boat already beyond
  the layline (no intersection and the mark on the other tack's side) tacks at once.

### 4.4 Beating and running: when to tack or gybe

Checked at every decision, the first that fires wins. A tack (gybe) is only started if the **manoeuvre checks** pass:
cooldown `T_cool` since the last tack or gybe has elapsed (§13), boat speed ≥ 0.6 × target (not for layline, rules
or obstruction triggers), and the tack is legal and safe (§7.3).

1. **Rules or obstruction**: the avoidance layer (§7) or the land check (§4.6) asks for it.
2. **Layline** (§4.3).
3. **Corridor**: the lateral offset from the wind axis through the mark `e = cross(w, c − R)` (w = unit vector
   towards `TWD_ref`) with `|e| ≥ W_c = max(4·L, min(0.35·D_axis, 500 m))`, `D_axis = dot(R − c, w)` for a beat
   (the opposite sign for a run), and the boat sailing away from the axis.
4. **Shift**: the current tack is **headed** when the shift rotates its optimal heading away from the mark:
   `Δ · sgn(wrap_pi(ψ_t − compass(R − c))) > 0` with `|Δ| ≥ h_up` (beat) or `h_dn` (run, §13), and that has held for
   6 s; the other tack must not overstand (its COG ray must still intersect the current tack's layline, i.e. it is
   not already past it). Easy does not play shifts.
5. **Pressure** (Expert, Pro): the mean free wind speed sampled on the other tack's track (§3.3) is ≥ 12 % higher
   than on the current track, for 10 s, and the other tack is not unfavoured by more than 3° of shift.
6. **Stream and trend** (§4.7, all but Easy): the other tack first is the quicker route by the level's margin, three
   evaluations in a row (tactic `Pressure`).

While the present tack first is the quicker route (§4.7 "stay"), triggers 3 to 5 do not fire: the boat holds on to
the side that pays.
7. **Bad air** (§8).
8. **Cover** (§9).

### 4.5 Finish leg

The finish line is the target: aim at the point of the line that is closest on the current tack's COG ray if that
point is more than `L + B` inside the ends, else at the line's middle third nearest to the boat; on a beat use the
laylines to the favoured end (the end that is farther upwind along the wind axis).

### 4.6 Land and obstructions

Every decision: if `PredGap(boat, obstruction, 8 s)` on the current motion is below `2·L`, the boat tacks (beat),
gybes (run) or turns away to the side of the course (reach) — the side where the obstruction's nearest point is not.
Fixed courses may give waypoints per step (`courses.md` §8); when the direct line to R crosses land the AI routes
through them in order.

### 4.7 Stream and trend: which side pays

Once a second (on the decision ticks with `(n + i) mod 20 = 0`), on a beat or a run outside `6·L` of the mark, the AI
times the two routes to R of two legs each: the present tack first, then the other tack along its layline, and the
other tack first (a tack now), then back. Each leg is sailed at the polar target speed `V` (`V_up` or `V_dn`) on its
VMG heading in the mean wind `TWD_ref` turned by the briefed trend `r` (§1: the trend term's rotation from the gun to
the gun plus the course's target time, divided by that time; 0 without a trend), with the mean current along that
leg (three samples, §4.3):

```
leg 1 heading ψ1 from TWD_ref + r·T1/2, leg 2 heading ψ2 from TWD_ref + r·(T1 + T2/2)
g1 = V·dir(ψ1) + c1 ; g2 = V·dir(ψ2) + c2          c1, c2: the current at the boat and the mean of boat and R,
c + g1·T1 + g2·T2 = R  (solve for T1, T2 ≥ 0)       then (a second pass) the means along the legs found
T_route = T1 + T2 ; a route with T1 < 0 or T2 < 0 is not timed
gain = T_present − (T_other + t_man)                 t_man of §4.3: the tack (gybe) it costs
tack (trigger 6 of §4.4)  when gain > m·T_present + 1 s for three evaluations
stay                      while T_other − T_present > 3 s
```

With a uniform current and no trend both routes take the same time (they are the two sides of one parallelogram):
only a stream that differs across the course (stronger mid-channel, weaker inshore or over a bank) or a turning wind
makes a side pay. The margin `m` is the level's (§13). The wind's own shifts are left to triggers 4 and 5.

## 5. The start

### 5.1 Phases

| Phase | When | Goal |
| --- | --- | --- |
| Position | from spawn until −75 s (fleet) | get to the setup point S (§5.4) |
| Hover | from −75 s or on reaching S, until the go signal | stay near S, slow, in clear water |
| Final approach | from the go decision (§5.5) to the start signal | reach the target spot at full speed at the gun |
| Launch | from the start signal | sail the first leg; handle OCS |

Before the warning signal (free sailing) the AI sails upwind and downwind near the line at 70 % of its setup
distance to sample the wind: it feeds `TWD_ref` so the start decision uses a mean wind, not the gust of the moment.

### 5.2 Line analysis

With `n̂` the line normal towards the course side and `w` towards `TWD_ref`:

- **bias** `β = wrap_pi(compass(n̂) − TWD_ref)` (0 = square); the end that is farther upwind is **favoured**:
  `Δu = dot(B − A, w)` (> 0: B end favoured). Significant if `|Δu| > max(1·L, 0.05·|B − A|)`.
- **Target spot** `u* ∈ [0.05, 0.95]` along the line: each AI's wanted spot is, with a significant bias, 0.15 from
  the favoured end, else 0.5, plus `spread·(rng() − 0.5)` (§13), clamped.
- **Fleet assignment**: the spots of a fleet are given out together. The wanted spots of all AIs not yet started are
  sorted and spread to at least `2·L` apart (`L` the largest hull; closer only when the line is too short for the
  fleet, and kept inside `[0.05, 0.95]`), and handed to the boats in the order of their present positions along the
  line (ties by boat index), so no two approaches to the spots cross. The draw of each AI still shapes where the
  spots are; which boat takes which follows the positions. The assignment is made when the race is created, again
  at −75 s (the mean wind is known better by then), and whenever an AI's bias estimate changes by more than 5°.
  A match race boat takes her side's spot (§5.8).

### 5.3 Approach heading

Starboard tack, towards the spot: the heading of the bearing to the spot corrected for the current (§4.2), its TWA
kept between `θ_CH + 2°` and 115° (after the correction too). The **setup bearing** `ψ_app = TWD_f − (θ_CH + 25°)` is the middle of the sector
from which the spot can be laid on starboard (between close-hauled and a beam reach): a setup point on it stays
inside that sector when the boat drifts while parked, where a point on the close-hauled edge would not.

### 5.4 Setup point and hovering

`S = spot − d_back·dir(ψ_app)` with `d_back = V_up·T_final`, `T_final` from §13; the setup points of neighbouring
spots (odd places in the fleet assignment) lie `1.5·L` farther back, so a boat on her way to her point passes the
parked ones instead of sailing into them. Before the warning signal the AI waits `1.2·d_back` back along the same
bearing (§5.1). While hovering the AI **parks** near S: starboard, `twa ≈ 50°`, the sails in until the boat has
turned onto that heading (a stopped boat does not steer) and let fly after that. More than `3·L` from S it sails
back to S (turning through a gybe, never a tack, so it never stalls head to wind), easing the sheets within `5·L`
so it arrives slowly, and parks again within `1·L`. It respects the rules against boats around it (§7).

### 5.5 Go decision (time to the line)

The time to reach the spot from the current state is simulated with the class's own tables (`accel` and `polar`
of the current config at `TWS_f` and the approach angle `θ_a = θ_CH + 8°`), from the current speed `v0`:

```
v = v0 ; x = 0 ; t = turn_time (+ 2 s if the sails are let fly: they take that long to come in)
                                                  turn_time = |wrap_pi(ψ_a − ψ)| / (max(v0, 0.5) / turn_radius_full), max 8 s
while x < d_path:                                 steps of 0.1 s, at most 120 s
    V = polar(TWS_f, θ_a)·scale
    a = v < V ? (v < V/2 ? accel_rest + (accel − accel_rest)·v/(V/2) : accel) : 0     boat.md §5.8, at θ_a
    v = min(v + a·0.1, V) ; x = x + v_g·0.1 ; t = t + 0.1
                                                  v_g = sqrt(max(0, v² − c_x²)) + c_a: over the ground, with the
                                                  current along (c_a) and across (c_x) the path to the spot
t_run = t
θ_a, ψ_a = the approach TWA and heading of §5.3 from the present position
d_path = distance from the bow to the spot (straight line)
go when  (−t_race) ≤ 1.1·t_run + 2 s + 1.0 s + e_start      t_race = race time (negative), e_start = the level's start error
```

The go decision uses `1.1·t_run + 2 s`: a boat reaches her table speed later than the tables alone say (the trim
settles, the heading wanders), and an early boat can take the time off by letting fly while a late one cannot make
it up. The final approach (§5.6) uses `t_run` itself. If at the go the spot is above close-hauled from where the
boat is, she takes the spot where her close-hauled course (`θ_CH + 2°`) meets the line, when that is inside
`[0.08, 0.92]`.

`e_start` is drawn once per start from the level distribution (§13): positive = late. Pro starts are within half a
second of the gun; Easy boats start seconds late.

### 5.6 Final approach

Sail the approach heading of §5.3 towards the spot with sails trimmed. Every decision, re-solve `t_run`: if the
boat would arrive more than 1.0 s early (against `−t_race + e_start`), let fly until back on time. Late, she sails
on at full speed on the course to the spot (bearing away from it only makes her miss it). **Brake**: while the bow
would reach the line before the gun at the present speed and is within the let-fly stopping distance (about 5 s of
the present speed towards the line: a let-fly boat loses speed slowly, `boat.md` §5.8), let fly. The speed towards
the line is taken on the heading she is about to sail (near the spot the approach heads up to close-hauled, which
points her more at the line), not the present one. **Hard brake**, within the same stopping distance: the distance she coasts until the gun with the
sails let fly (the deceleration law of `boat.md` §5.8 from the present speed, down to `let_fly_drive · v`, the drive
the let-fly sails keep), times the share of it towards the line, would bring the bow to within `0.3·L` of the line
before −0.3 s, or she is within `0.3·L` already: let fly and luff to `|twa| = 40°`. The coast is read from the
class's own deceleration and let-fly drive, so a class that coasts far starts braking earlier. A current setting
towards the line adds its drift until the gun (`max(0, current·n̂)·min(−t_race, 30 s)`) to both the distance within
which she brakes and the coast. Never cross early on purpose.

### 5.7 Launch and OCS

- At the gun: trim on, sail the first-leg heading (beat: close-hauled on starboard, then the strategy of §4).
- **OCS (P flag)**, and a boat not yet seen completely on the pre-start side after the gun (`race.md` §4.2, her bow
  over at the gun): bear away and gybe back to `2·L` behind the line by the shortest turn that does not cross a boat
  (§7 avoidance still applies; the boat now keeps clear of everyone under rule 21.1), then start again at full speed.
- **OCS-I**: route around the nearer end: a waypoint `1.5·L + B` beyond the end and `1·L` on the course side, then
  one as far beyond the end and `2.5·L` behind the line, then start. The second waypoint is taken once the boat is on
  the course side beyond the end, so the crossing back is around the end; a boat that dives back through the band
  starts over.
- **Outside the band** after the gun (not OCS): sail to a point `1.5·L` behind the line inside it (`u` clamped to
  `[0.12, 0.88]`), then up through it.

### 5.8 Match race pre-start (v1, simple)

The entry duties of `race.md` §3.4 are sailed with waypoints: before −4:00 hold `6·L` beyond the assigned end,
outside the line band; from −4:00 enter through the line from the course side within 30 s; then hover `4·L` behind
the line's middle and start as in fleet with `u* = 0.5`. Dial-ups and hooks are not in v1.

## 6. Marks

### 6.1 Approach and rounding

- **Rounding circle**: centre M, radius `ρ = r_mark + 0.5·B + c_lvl + n_in·(B + 1 m) + |v|·t_r` where `c_lvl`
  is the level's clearance (§13), `n_in` the number of boats the rules engine says are entitled to mark-room from
  this boat at this mark (they need space inside it), and the last term the way the boat runs on before a turn
  takes hold: the **reaction time** `t_r = yaw_time + 0.5 / helm_rate` (the hull's yaw lag and the rudder's travel
  to half helm, `boat.md` §5.9), read from the class's data, so the margin follows the boat and its speed. `ρ` is at
  least the turning radius at the helm of a smooth turn (0.6, §10): a tighter circle cannot be followed, and a boat
  that cannot follow it swings out of it on the exit. In a current `c` the circle grows by the set over the reaction
  and the first quarter of the turn, half of it towards the mark on average:
  `0.5·|c|·(t_r + (π/2)·R_0.6 / max(|v|, 1 m/s))`.
- **Aim point** while more than `4·L` away: the tangent point of the circle on the required side as seen from the
  boat. Within `4·L`: follow the circle; the turn starts when the distance to the tangent point is below the turning
  radius at the planned helm (`boat.md` §5.9 radius law), so the boat leaves the circle on the exit tangent towards the next leg's
  heading (the VMG heading of the next leg if it is a beat or run, the direct course if a reach).
- Beats and runs to a mark use §4 until the layline, aiming at the **pass point**: the circle's point on the required
  side across the wind (upwind for a beat, downwind for a run), `0.5·L` farther out than `ρ` as a margin; the
  rounding plan takes over within `ρ + 4·L` of the mark.
- **Inside the rounding plan** the guide is the tangent point of the circle ahead in the rounding direction (outside
  `1.15·ρ`), or the point `55°` ahead on the circle (inside it). The race's own winding angle φ and its target
  `φ_done` (`race.md` §5.1) tell how far round the boat is: a boat that came in on the wrong side is behind (φ small
  or negative) and simply goes on round the circle, which takes her back the way she came and round, the way the
  winding test counts it. With less than `70°` of winding to go she leaves on the exit heading once the guide has
  turned past it.
  - Guide above close-hauled: the present tack if it moves round in the rounding direction and passes the mark on
    the required side by at least `0.9·ρ` (or the mark is behind), both judged along the course over ground the tack
    makes (§4.2: the current sets her on or off the mark; so does the wrong-side test below and in §7.2), else a beat to the pass point on its laylines, so
    a boat that cannot lay the mark tacks away early and comes back on the layline, not at the mark. A present tack
    that runs at the mark on the wrong side, passing it closer than `ρ + 0.5·L` within `ρ + 3·L`, tacks away at
    once (if the tack is safe) instead of sailing on to the mark.
  - Guide on the other tack with the shorter turn through head to wind: a tack if the boat has way on (≥ 0.6 ×
    target) and the tack is safe (§7.3); if not, as close to the guide as the present tack goes, and wait. A turn
    the long way round (through a gybe) only when the boat is nearly stopped: a loop near a mark and other boats is
    worse than a late tack.
  - A tack in progress keeps its target; pending tacks of the strategy are dropped when the rounding plan starts.
- If entitled to mark-room: keep `c_lvl` and ignore boats outside (the engine protects the corridor). If giving
  room: add the entitled boats' widths to ρ (above) and, if still overlapped outside when 1 L from the zone, slow
  (let fly partially) so they can go inside. If clear astern at the zone with no room: aim at the stern of the boat
  ahead + `1·L` until she has rounded.

### 6.2 Sails around marks

Requests are those of `sails.md` §4.2: `hoist(X)` (a peel: the new sail goes up and drives, then the old one comes
down) or `drop_front()`; a rejected request (a change already running) is retried on the next decision. Plans come
from the next leg's TWA:

- **Hoist** (windward mark → downwind leg): start the hoist when the boat is 1 L past the mark and has borne away to
  a TWA where the new sail is faster (`best_sail`), not within `2·L` of another boat's hull ahead-to-leeward.
- **Drop** (downwind → beat, or a reach too tight for the downwind sail): request `hoist(upwind sail)` when the
  distance to the rounding tangent point is ≤ `V·(t_drop + 4 s)`, with `t_drop` the whole peel: the new sail's
  `prepare_hoist_time + hoist_time` plus the old sail's `prepare_drop_time + drop_time` at the present wind
  (`sails.md` §4.4); Pro uses 3 s instead of 4 s, Easy 7 s.
- **Change** on a leg: when `best_sail` differs from the current sail and would be ≥ 3 % faster for 5 s, and the
  remaining leg time ≥ `t_change + 10 s`. Hysteresis 2° in TWA.
- During a penalty turn with a downwind sail up in more than 10 kn true wind: drop first.

### 6.4 Course objects

Every decision, the planned heading is checked against every course object (marks, committee and mark boats,
`courses.md` §2) ahead within `max(3·L, 6 s)` of travel along the course over ground it makes (§4.2; a tangent found
there is turned back into the heading that makes it good): one whose centre is closer to the track than
`r + 0.5·B + 1 m + 0.15·L` (a committee or mark boat another `0.5·L`: the bow of a boat still turning onto the
tangent reaches its long flat side first) is passed by the tangent to that clearance circle on the side it is on
(the other side when that side is above close-hauled). The mark being rounded is only checked for a collision course (clearance
`r + 0.5·B + 0.5 m`, the rounding circle keeps the planned one), and it is never passed on the other side (the side
it is passed on is the rounding side, whichever side of the planned track it lies on at that moment): if its
side is above close-hauled the AI tacks away from it (if safe); if it cannot tack, it bears away past the mark on
the other side when that is sailable on the present tack (the rounding then goes on round, §6.1: going round again
costs less than a touch and its turn), and only when neither is possible pinches and lets fly (only with way on, faster
than 0.5 m/s: nearly stopped at the mark it keeps its sails drawing so that it can steer away). The mark being
rounded is also checked along the predicted track, not only the straight line: the planned heading sailed from here
(the reaction time `t_r` of §6.1, then the turn at the radius law's full rate) for 4 s must keep the hull 0.3 m off
the mark, or the rounding is re-planned on the nearest heading that does, turning away from the mark (the rounding
side) in 5° steps up to 45° and not above close-hauled; when none does, it is handled as the collision course above.
So a rounding that would touch is dropped before the touch, whatever the class's turning circle and speed.
Tacks, gybes (§7.3) and the avoidance candidates (§7.2) are rejected when the predicted hull would touch a course
object.

### 6.5 Pinned on an object

A boat in contact with a course object, an obstacle or land (the contacts of the last collision step, felt as a
bump; one within the last second counts, since the contact comes and goes while she lies against it) with less than
0.3 m/s over the ground for 2 s is **pinned** (a current holding her on a mark, a crowd pressing her onto a committee
boat). Racing, she then sails for 6 s on the heading that takes her away: the bow not into the object
(`dot(dir(ψ), n) ≥ 0`, `n` the contact normal towards her), the course over the ground leading most directly away
(`dot(V(ψ)·dir(ψ) + current, n) + 0.5·dot(dir(ψ), n) − 0.3·|ψ − ψ_now|`, 5° steps, not above close-hauled), on the
present tack (a stopped boat cannot tack), else on the other by bearing away round; the sails drawing and the helm
free of the drag limit (tactic `Land`). Still held after 8 s, she lets fly for 6 s out of every 12 so the stream
carries her round the object, then sails again. Rules avoidance (§7) still applies.

### 6.3 Gate choice

Score each gate buoy and pick the lowest, fixed when the boat is `8·L` from the gate line (re-evaluated only if a
buoy becomes blocked by 3 or more boats within `3·L`):

```
score = distance to the buoy's tangent point / V
      + 2 s × (number of other boats within 4 L of that buoy and heading to it)
      − 3 s × (next leg is a beat and rounding this buoy leaves the boat on the tack that is currently lifted
               (|Δ| ≥ 3° in its favour) or on the side of the course with the stronger mean wind (Expert/Pro))
```

## 7. Rules-aware sailing

### 7.1 Inputs

For every other racing boat within `10·L` the AI takes the pair record (`rules.md` §11.1): who keeps clear, the
keep-clear state (`Clear`/`Warning`/`Breach`), room entitlements, rule-17 flag, ttc. The AI does not re-derive
right of way; it trusts the engine, which is the same verdict that will penalise it.

### 7.2 Keeping clear (the AI must keep clear of B)

Trigger: state `Warning` or `Breach`, or `ttc < H_avoid` (§13).

Candidate evaluation (runs at 10 Hz while triggered, and 1.5 s after the trigger ends):

```
candidates: headings ψ + k·5°, k = −8 … +8 (hold, bear away, luff),
            tack or gybe (if §4.4 manoeuvre checks allow),
            slow: hold heading, let fly (brake; the speed decays towards let_fly_drive · v, boat.md §9, as in
                  the rules' escape test, rules.md §3.6: running, letting fly hardly slows the boat)
for each: move own hull with CTRV at the candidate heading (turn at `|v| / turn_radius_full` to the candidate heading,
          then straight; with the sails drawing the speed grows towards the polar speed at half the table
          acceleration, so a stopped boat sees a way out) for 6 s; move B and every other boat within 5 L on their
          current motion; a candidate whose hull touches a course object (§6.4) is dropped
cost = ∞                                    if PredGap to B < m (rules.md §3.1) or to any other boat < 0
     + 20 / max(gap_min_m, 0.5)             proximity to B
     + 4 · (VMC_ref − VMC_candidate)/V_ref   loss of progress to the mark
     + 3 · tack_or_gybe                      manoeuvre cost
     + 10 · creates_new_obligation           the candidate makes the AI a give-way boat to someone else (e.g. tacking to port)
     + 30 · wrong_side                       rounding (§6.1): the candidate heading runs at the mark on the wrong side
                                             (passing it closer than ρ + 0.5·L within ρ + 3·L, the test of §6.1)
choose the minimum; keep it for at least 1.5 s unless a new ∞ appears
```

The `wrong_side` term keeps the avoidance from trading a keep-clear penalty for a touch: a port boat luffing to let
a starboard boat by at the windward mark must not luff onto the wrong side of the mark, from where the rounding can
only turn her into it. It is a cost, not a ban, so a candidate that is the only way clear of a boat is still taken.
The usual manoeuvres come out of this: ducking a starboard boat (bear away behind her stern), tacking to leeward
and ahead ("lee-bow") when that clears, slowing when crossing is impossible. The brake (the `slow` candidate, and
letting fly when no candidate clears) is dropped for a boat that has started and has been nearly stopped (under
0.3 m/s) for more than 5 s: she keeps her sails drawing so that she can gather way and steer clear.

### 7.3 Before gaining right of way (rules 13, 15, 16)

Before a tack, gybe, luff of more than 10°, or an overtaking move that would make the AI the right-of-way boat
over a boat B within `5·L`, it predicts its pose 3 s after the manoeuvre and evaluates the rules engine's
`Escape(B, me)` (`rules.md` §3.6) from that pose. If B would have no escape, the manoeuvre is not made (the AI waits
or chooses another). It never tacks within `3·L` directly into the path of a boat on the other tack (rule 13).

### 7.4 With right of way

- **Hold course**: while a give-way boat is within `5·L` and not in `Breach`, the AI makes no course change of more
  than 5° towards it (rule 16) unless rounding a mark within its mark-room.
- **Rule 17**: when the pair has the rule-17 flag with the AI as holder, the AI's heading is limited to not above its
  proper course (`rules.md` §3.7); not while rounding a mark (§6.1), where the rounding is her proper course.
- **Emergency (rule 14)**: if the give-way boat is in `Breach` and `ttc < 1.5 s`, the AI evades with the candidate
  evaluation of §7.2 but only among candidates that do not turn towards the other boat; it prefers turning parallel
  to her. This avoids damaging contacts (`rules.md` §5.1).

### 7.5 Priority

Emergency evasion (§7.4) > keeping clear (§7.2) > room at marks (§6.1) > starts and rounding plans > strategy.
A manoeuvre started by the avoidance layer is not cancelled by strategy for 1.5 s.

### 7.6 Penalty turns

A penalty is one 360° turn that must be completed within 120 s of the incident, and in a fleet race it counts
anywhere (`rules.md` §9.3, §9.4). With a pending penalty the AI starts a turn when all of:

- **match races only**: the turn's circle keeps the hull out of the zones of the next mark and the last one rounded
  (a turn only counts there, Appendix C): the circle's centre, `1.3·R` to the side of the turn (`R` the radius at
  the turn's helm, a margin for the speed the turn loses), is at least `Z + r_mark + 1.3·R + 0.6·L` from those
  marks, and the next zone is more than 20 s of sailing (plus the circle) away. A fleet race has no zone condition;
- boat speed ≥ 0.75 × target, and not within 5 s after a failed turn;
- the turn's circle is clear of the other boats as they move: no hull within `0.5·L` of the circle over the next
  6 s, each boat moved on her present course and speed with her drift (`rules.md` §3.1) (a boat coming up fast is in the way, one sailing away is
  not; a boat taking a penalty must keep clear of all others, rule 21.2), and none within `3·L` ahead.

From 45 s before the deadline (`rules.md` §9.4: the turn must be **completed** by then; a turn takes 10 to 25 s)
it is **urgent**: only the zones (match), 0.4 × target speed and a hull inside the circle within the next 6 s hold
it back. Direction: on a beat start by luffing into a tack (turn towards the wind), on a run start by bearing away
into a gybe, on a reach turn towards the wind; in a match race the other way when only that keeps the circle out of
the zones. Helm 0.8 of full (0.6 below 9 kn true wind, where a slammed turn stalls), sheets on auto-trim through the
turn, downwind sail dropped first in more than 10 kn. The turn is kept up until the engine reports it served, through
the tracker's resets; stopped for 4 s (in irons) it is given up and started again after 5 s of speed building, and
so is a turn that enters a zone in a match race.

While a penalty waits, the AI makes the conditions: before the start it leaves the parking and sails a broad reach
on starboard (`twa 110°`) away from the line with the sails in until it can turn; racing, it steers up to 15° away
from the boat in the way (not above close-hauled). In a match race, when only the zones hold the turn back and the
boat is outside the zone of the mark she is heading for, she sails away from the marks whose zones are in the way
(the next and the last rounded, those within `3·Z`), on her present tack and not above close-hauled, until the
turn's circle is clear of them. A pre-start penalty is taken before the start (`rules.md` §9.3), except in the last
20 s.

## 8. Bad air

The AI must escape bad air it actually gets, and the thresholds are set relative to the wind shadow model, so that the
behaviour triggers whatever the shadow's calibration.

- **Measure**: the deficit `d` (§3.3), smoothed 2 s.
- **Threshold**: `d_bad = 0.35 · d_peak`, where `d_peak` is the source boat's peak blanket loss:
  `blanket_depth` (or `blanket_depth_spinnaker` when the source flies a spinnaker) of its class
  (`wind_shadow.md` §2). With the reference 0.22, `d_bad ≈ 0.077`: the AI reacts in the inner part of a blanket
  (the loss exceeds it over roughly the first half of the blanket's length, on and near its axis) and in the
  strongest part of a backwind band (peak 0.15), not at its faint edges. Being relative to the model's own depth,
  the trigger keeps working if the shadow is recalibrated.
- **Trigger**: `d ≥ d_bad` for 3 s continuously, the source boat (the boat `j` with the largest loss
  `shadow(j, x, y)` at the AI's position, `wind_shadow.md` §7) is within `8·L`, and the AI is not inside a mark zone or in the last 10 s before
  the start. The source is the tick's (`EnvAtBoat::shadow_source`); where there is none for a moment (the smoothed
  deficit outlasts the loss at a blanket's edges) the last one seen stands in. The check runs on every leg, beats,
  runs and reaches, also close to the marks outside the zone.
- **Escape**, by leg type:
  - beat: tack, if the §4.4 manoeuvre checks pass, the other tack does not overstand, and no boat within `5·L` on
    the other tack would have to be ducked (rules check §7.3); otherwise **foot**: bear away 5° for up to 20 s to
    sail out below the shadow; if the source is to leeward and ahead (backwind), luff 3° instead to climb above it
    when there is clear water to windward;
  - run: gybe if the checks pass; otherwise head up 10° to cross out of the shadow cone on its edge;
  - reach: head up 10° if the boat to windward is the source, else bear away 10°.
- **Anticipation**: when scoring a tack or gybe decision or the start spot, the AI adds
  `5 s × d_pred / d_bad` to the option's cost, with `d_pred` the loss from `shadowed_wind(i, x, y)`
  (`wind_shadow.md` §7) at the position 15 s ahead on that option (the other boats' present shadows, not moved:
  the query uses the tick's snapshot).
- Level: Easy only reacts after 6 s and never anticipates; Intermediate reacts after 3 s; Expert and Pro after 2 s and
  anticipate.

## 9. Cover

- **Match race**: when the AI leads (`D_me < D_opp`, `race.md` §8.2) on a beat and the opponent is within `12·L`
  behind along the axis:
  - **tight cover** (opponent within `5·L`): keep her in the AI's shadow: when she tacks, tack within 2 s (if the §4.4
    checks pass) so both are on the same tack with the AI ahead and to windward;
  - **loose cover** (farther): stay between her and the mark: when she has been on the other tack for 10 s, tack.
  - On a run the leader gybes to stay between the trailing boat and the leeward mark and out of her shadow.
  - Cover yields to laylines (never overstand to cover) and to rules avoidance.
- **Fleet**: when the AI is in the first three on the last beat (or on a beat to the finish), it loosely covers the
  nearest boat behind it by `D` if that boat is within `10·L` of it along the axis. Also, on any beat, if the AI is
  leading a group (no boat ahead within `8·L` on its side of the course) it does not split to the far side:
  corridor half-width `W_c` is halved.

## 10. Manoeuvre execution

- **Tack**: target heading = the new tack's VMG heading; the helm goes to `h = ±0.6` (a smooth tack: hard helm
  bleeds speed, `boat.md` §4 rudder drag) and holds it until `|twa|` passes 20° on the new tack, then settles on the new heading. Entry speed below 0.6 × target: the AI first
  sails 5° lower for up to 8 s (unless forced). If the boat stops head to wind (in irons: speed < 0.5 m/s and
  `|twa| < 25°` for 3 s), it puts the tiller over to fall off on the new tack with sails let fly for 2 s.
- **Gybe**: controlled rate: helm for a turn rate of 15°/s (radius law of `boat.md` §5.9); the sails follow on
  auto-trim (`sails.md` §5).
- **Brake**: let fly and head up to `|twa| = 40°`.
- **Rounding**: as §6.1.

## 11. Helm and trim

- **Heading controller**: target turn rate `r* = clamp(wrap_pi(ψ_target − ψ) / T_h, −r_max, r_max)`, `T_h = 1.2 s`,
  `r_max = |v| / turn_radius_full`. Helm from the inverse of the radius law (`boat.md` §5.9): for `|r*| > 0`,
  `R* = |v| / |r*|`, `|h| = min(1, (turn_radius_full + turn_radius_offset) / (R* + turn_radius_offset))`,
  `h = sgn(r*)·|h|` (reversed in sternway), plus a damping term `−K_r·(turn_rate − r*)` with `K_r = 0.5 s/rad`,
  clamped to [−1, 1]. Unless forced, `|h|` is limited to the largest value whose rudder drag (`rudder_drag_luff` /
  `rudder_drag_bear` at the present speed) is at most 0.1 m/s² (never below 0.25, so the boat can always turn), so the
  AI steers as gently as a good helm. The actual helm follows `h_cmd` at `helm_rate` in the physics.
- **Heading hold**: the boat turns with the helm centred (weather helm and fall-off, `boat.md` §5.9: a wm7 under jib
  in 16 kn at TWA 100° turns at about 5°/s; a spinnaker close reaching pulls the bow away; an overpowered kite
  broaches), and it answers the helm with its yaw inertia (`yaw_time`), so the controller adds
  an integral term: `I += tack·(r* − turn_rate)·DT` (per second of turn-rate error, only with `|v| > 0.3 m/s`),
  clamped to ±0.6, and the helm gets `+ tack·I` (reversed in sternway). It is kept relative to the tack because the
  balance of the sail plan flips with it.
- **Trim**: `auto_trim` is always on for AI boats (`boat.md` §2): the sails sit at their optimum (`sails.md` §5.2).
  The level does not add trim errors (the `performance_scale` represents crew quality).
- **Let fly**: used for braking (start, room at marks, avoidance "slow").
- **Output**: the input frame for the next tick (`networking.md` §4.1 fields), identical in form to a human's.

### 11.1 Finished boats

After finishing, an AI boat is sailed by the finished-boat autopilot of `race.md` §6.2: to the point `5·L` beyond the
finish line's middle and `2·(i + 1)·L` along it (`i` = her finishing place), where she stops (luffed to `twa 50°`,
sails let fly, the spinnaker dropped: a kite let fly is held at its fully eased angle and still draws on a reach,
`sails.md` §5.3). It keeps doing so after the race has closed. A ghost that did not finish (retired, disqualified)
and any boat still sailing when the race closes stop where they are. `AiSkippers::add_autopilot` gives a human boat
(offline) only this autopilot: it steers her from her finish on and never before.

## 12. Easy starts and mistakes

The AI is predictable by design; the levels (§13) change speed and the precision of timing and tactics, not whether it
obeys the rules. It does not make deliberate rule mistakes. When it does get a penalty (it misjudged), it serves it like
anyone else.

## 13. Levels

| Parameter | Easy (0) | Intermediate (1) | Expert (2) | Pro (3) |
| --- | --- | --- | --- | --- |
| **`performance_scale`** | **0.90** | **1.00** | **1.025** | **1.04** |
| Start error `e_start` (s), `rng_range` in stream 16 | +1 … +6 | 0 … +2.5 | −0.5 … +1.2 | −0.3 … +0.5 |
| Start spot spread | 0.9 | 0.6 | 0.45 | 0.35 |
| `T_final` (s) | 35 | 30 | 25 | 22 |
| Overstand margin `M_lay` | 3·L | 2·L | 1·L | 0.5·L |
| Shift thresholds `h_up` / `h_dn` | off | 10° / 15° | 7° / 11° | 5° / 8° |
| Reading the water `R_read` | 0 | 0 | 250 m | 400 m |
| Tack cooldown `T_cool` | 30 s | 20 s | 15 s | 12 s |
| Keep-clear horizon `H_avoid` | 6 s | 5 s | 4 s | 3.5 s |
| Rounding clearance `c_lvl` | 1.5·B | 1.0·B | 0.6·B | 0.4·B |
| Bad-air reaction | 6 s, no anticipation | 3 s | 2 s, anticipates | 2 s, anticipates |
| Covers | no | match only | yes | yes |
| Stream and trend margin `m` (§4.7) | off | 2 % | 1.2 % | 0.6 % |

- The race layer sets the AI boat's `performance_scale` (`boat.md` §2, §5.8: it multiplies the target speed of
  every config at every angle) to the level's value at spawn, for the whole race (`race.md` §3.5). It is the main
  difference between the levels, and the only physical one. It does not depend on anything that happens in the race.
- The other rows shape decision quality (timing, margins, shift play). A lobby may set **"speed only"** levels, which
  use the Intermediate row for every level and keep only `performance_scale`.
- Online, AI fill boats get the level matched to the lobby (`networking.md` §12). Human boats always have
  `performance_scale = 1`.

## 14. Replacing a disconnected human

When a human loses the connection during a race, after 3 s their boat is sailed by an AI at Intermediate decisions
with the boat's existing `performance_scale` of 1.0 until the player reconnects (`networking.md` §9); the result is shown
with an "AI" mark. The AI takes over the current state as is (including pending penalties and OCS).

## 15. Telemetry and tests

Every AI records per race: tacks, gybes, penalties received, OCS, tactic activations by kind
(`None, Start, Rounding, KeepClear, Emergency, BadAir, Cover, Shift, Pressure, Layline, Corridor, PenaltyTurn, Land`),
time stuck (speed < 0.3 m/s for > 5 s after the start), and the minimum hull gap to any boat.

Headless acceptance tests (on the default course, 10 AI boats at Intermediate unless said, 5 seeds):

- every boat finishes; no boat is stuck for more than 20 s in total;
- average penalties per boat per race ≤ 0.4, contacts per race ≤ 1;
- OCS rate: Pro < 5 % of starts, Easy < 15 %; average start delay after the gun: Pro < 2 s, Easy 3–8 s;
- tacks per boat on a 1 nm beat between 3 and 14;
- **bad air triggers** at least 2 times per boat per race on average, and the boats that trigger have a lower average
  deficit 20 s later than at the trigger;
- **cover**: in a match race (two Expert boats, 5 seeds) the leader on a beat covers at least once per race;
- level separation: in a mixed fleet the average finishing order is monotonic in level, and with "speed only" levels
  the finishing time ratios follow the `performance_scale` values within 3 %;
- scenario tests: port boat ducks a starboard boat; AI does not tack into a starboard boat's path within 3 L; AI gives
  room to an inside boat at the windward mark; AI with right of way holds course while a give-way boat ducks; AI
  escapes a boat's shadow on a beat by tacking and, with a boat on its hip on the other tack, by footing.

### 15.1 Where the tests are, and what they measure now

The fast checks and the scenarios run in `core_tests` (`core/tests/test_ai.cpp`): the level table, the polar
tables, a lone boat sailing the default course clean, the memory block (§16) saved and loaded mid-race and in the
sequence continuing bit for bit and rejected when damaged or of another tick, projected finishes and the
finished-boat autopilot, and the scenarios above (duck, hold course, no tack into a starboard boat's path, escape a
shadow by tacking and by footing). The mark-room scenario is covered by the fleet runs only so far.

The fleet runs are a separate test, `ai_races` (`core/tests/test_ai_race.cpp`, ctest label `ai_long`, about half
a minute): `ctest --test-dir core/build -L ai_long` runs them, `-LE ai_long` leaves them out. They print their
measurements. Measured on the default course (11 kn, stable shifts), with the decisions staggered by boat (§1,
WM-102; the runs before it, all boats deciding on even ticks, in brackets where they differ):

| run | measured | spec target |
| --- | --- | --- |
| 10 Intermediate, 5 seeds | 96 % finish (the rest DSQ) [94 %]; 0.66 penalties/boat [0.64]; 5.4 contacts/race [3.8]; stuck ≤ 22 s [18 s] | all finish; ≤ 0.4; ≤ 1; ≤ 20 s |
| same | bad air 2.4 triggers/boat [3.3], deficit 0.14 → 0.04 twenty seconds later (93 % lower) | ≥ 2, lower |
| every level, 10 boats, 2 seeds | 85–100 % finish [90–95 %]; OCS 0–5 % [0–15 %]; mean start delay 18–30 s [14–19 s] | Pro OCS < 5 %, delay < 2 s; Easy < 15 %, 3–8 s |
| 1 nm beat, 10 boats | 4.2 tacks/boat [5.1] | 3–14 |
| match race, 2 Expert, 5 seeds | the leader covers in every race (2–8 activations); one penalty and two contacts in seed 3 [none] | ≥ 1 |
| mixed fleet (2 per level, 3 seeds) | mean place Easy 7.3, Intermediate 3.5, Expert 3.8, Pro 3.3 [6.3, 5.5, 4.0, 2.3] | monotonic |
| speed only (same) | mean place Easy 7.2, Intermediate 4.3, Expert 3.3, Pro 3.3 [7.2, 3.5, 2.8, 4.7]; mean finish times 733 / 666 / 626 / 629 s [737 / 614 / 616 / 657]: since WM-095 the ratios do not follow `performance_scale` (before: within 2.5 %), the six races are dominated by start delays and a few penalties | within 3 % |

These few races move a lot with any change of timing. Over 140 races of the 10 Intermediate fleet (`AI_SCENE=1
AI_FLEET=1 AI_LEVEL=1`, seeds 100 to 239) the stagger is neutral: 4.20 contacts/race against 3.91 unstaggered
(difference 0.29, standard error 0.32), 0.63 penalties/boat against 0.60, 78 DSQ against 73; over 40 races each of
Expert and Pro fleets the same (contacts 5.2 / 5.0 and 4.3 / 4.8, penalties 0.72 / 0.72 and 0.62 / 0.67).

The assertions of `ai_races` hold the measured level (finish ≥ 80 %, ≤ 1.3 penalties/boat, ≤ 6 contacts/race,
bad air ≥ 1.0 and lower 20 s later, every level ≥ 70 % finish, tacks 3–14, cover in every match, Easy behind Pro).
**Open**: the penalty and contact targets, the start delays (a lone boat starts within 1–9 s; in a fleet the
crowd at the line and pre-start penalties make the mean 13–25 s) and strict level order in a mixed fleet are not
met yet. Most remaining penalties come from crowds at the line and the windward mark; the disqualifications left
are boats that do not complete a penalty within the 120 s (`rules.md` §9.4), usually because the crowd at the
windward mark keeps the turn's circle blocked until the urgent phase and the urgent turn then stalls.

**Rules to the 2025-2028 RRS (WM-095), before and after** (same runs and seeds; "late" counts the penalties not
taken in time: before, each added a `44.1-late` penalty, after, each disqualifies):

| run | before (45 s deadline, zone ban, late = +1 penalty) | after (120 s from the incident, turns anywhere, late = DSQ) |
| --- | --- | --- |
| 10 Intermediate, 5 seeds | 43/50 finish, DSQ 7; 1.00 penalties/boat; late 6; 4.6 contacts/race | 47/50 finish, DSQ 3; 0.64 penalties/boat; late 4; 3.8 contacts/race |
| Easy, 2 seeds | 20/20, DSQ 0; 0.60; late 2; 4.5 | 19/20, DSQ 1; 0.75; late 2; 8.0 |
| Intermediate, 2 seeds | 19/20, DSQ 1; 0.75; late 2; 5.5 | 19/20, DSQ 1; 0.65; late 2; 3.0 |
| Expert, 2 seeds | 18/20, DSQ 2; 0.90; late 3; 2.5 | 18/20, DSQ 2; 0.85; late 2; 3.0 (one boat pinned at the windward mark for 118 s, seed 22) |
| Pro, 2 seeds | 19/20, DSQ 1; 0.70; late 3; 4.5 | 19/20, DSQ 1; 0.80; late 2; 8.0 |
| 1 nm beat, 2 seeds | 17/20, DSQ 3; 0.70; late 4; 5.0 | 19/20, DSQ 1; 0.55; late 2; 6.0 |
| match race, 5 seeds | no penalties, no contacts | no penalties, no contacts |
| mixed fleet, mean place by level | 7.5 / 4.0 / 3.5 / 3.0 | 6.3 / 5.5 / 4.0 / 2.3 |
| speed only, mean place by level | 6.0 / 4.8 / 4.0 / 3.3 | 7.2 / 3.5 / 2.8 / 4.7 |
| full AI race (`core_long`, seed 33) | 6/10 finish | 9/10 finish |

**Current, a trending wind and the venues (WM-111).** `ai_races` also races ten Intermediate boats at the Solent on
its own conditions with the tide forced to a strong flood, a strong ebb and slack (seeds 1 and 2 each): at least
80 % finish, nobody stopped for more than 60 s, at most one windward approach in five overstood by more than 10 s
and at most 8 s overstood per approach on average, and the beats lean further to the left (the shore, out of the
stream) in the flood than in the ebb. The windward approach measure: from a boat's last tack to the mark, the time
sailed more than 10° freer than her own median close-hauled TWA on that leg, farther than `3·L` from the mark.
Measured over 80 seeds each (10 Intermediate boats, `AI_VENUE=<venue> [AI_TIDE=flood|ebb|slack]`), before and after:

| venue | finished | DSQ/race | winner (s) | boats stopped > 60 s (races) | overstood s/approach (> 10 s) | beats' side |
| --- | --- | --- | --- | --- | --- | --- |
| Solent flood | 92.0 → 92.1 % | 0.80 → 0.78 | 1174 → 1134 | 17 → 14 (longest 129 → 132 s) | 1.6 (5 %) → 2.4 (9 %) | +49 → +99 m |
| Solent ebb | 94.4 → 97.6 % | 0.50 → 0.21 | 803 → 796 | 15 → 6 (longest 1101 → 93 s) | 5.5 (12 %) → 5.3 (10 %) | +39 → +35 m |
| Solent slack | 94.9 → 94.0 % | 0.51 → 0.60 | 915 → 915 | 2 → 1 | 3.4 (14 %) → 3.1 (12 %) | +58 → +60 m |
| Solent, drawn tide | 92.1 → 92.6 % | 0.76 → 0.68 | 926 → 918 | 11 → 8 (longest 481 → 118 s) | 3.3 (8 %) → 3.6 (10 %) | +49 → +59 m |
| Fremantle | 95.9 → 95.8 % | 0.41 → 0.42 | 1038 → 1039 | 4 → 6 | 2.4 (6 %) → 2.8 (7 %) | +55 → +68 m |
| Trieste (200 seeds) | 96.3 → 96.3 % | 0.37 → 0.36 | 981 → 987 | 19 → 11 | 2.7 → 2.7 | +43 → +43 m |
| Garda | 95.1 → 95.2 % | 0.46 → 0.45 | 742 → 742 | 3 → 3 | 2.9 → 2.9 | +47 → +47 m |

The flood's start had boats in irons behind the line (the current correction solved at their own low speed turned
them into the wind): mean start delay 76 → 27 s. Open: in a strong stream a boat that touches the windward mark can
still lie pinned on it for up to about two minutes before she gets clear (§6.5); a stream setting the fleet over the
line still gives OCS 13 % of starts in the ebb (no current: 4 %).

Development runs (skipped unless asked for, in `test_ai_race.cpp`): `AI_SCENE=1` races the game scene's fleet (6
Expert wm7, 12 kn from 0°, the default shifts) over `AI_SEEDS=first,count` and prints per seed the first-mark
roundings, mark touches, penalties, DSQs, finishes and OCS boats; `AI_FLEET=1` switches to the fleet of the runs
above, `AI_WM12=1` to a mixed wm7 and wm12 fleet, `AI_TRACE` writes a CSV of every boat every 0.5 s (with the reason
of the last manoeuvre and why a penalty turn waits), `AI_VENUE=<venue>` races a venue on its own conditions over
`AI_SEEDS` (with `AI_TIDE`, `AI_N`, `AI_LEVEL`, `AI_MIXED`) and prints the windward approaches and the beats' side,
and `AI_SNAP=<dir>` resumes a race the game saved (the world
snapshot and the skippers' block, `world.bin` and `ai.bin`, boat 0 the player) instead of creating one, so a
failure seen in the game scene is replayed in the core.

## 16. The skippers' memory in a snapshot

`conventions.md` §9.1 leaves the memory of the step-2 controllers out of the world snapshot and out of the tick
checksum: the AI runs only on the authoritative side, and clients never have its memory. The skippers keep it
themselves and serialise it as a **block of their own**, taken at the same moment as the world snapshot (between
ticks) and stored or sent next to it:

```
uint32 magic 0x49414D57 ("WMAI"), uint32 version = 2
uint32 tick (the world's next tick), uint64 race_seed, uint32 boat count of the world
list   AI boats, in the order they were added:
  int32 boat index
  every carried field of the per-boat state (ai_internal.h, AiSkippers::Boat) in declaration order: level,
    speed_only, autopilot_only, active; the RNG draw counters of streams 16 and 17 (§1); the wind filters; the
    manoeuvre, strategy (with the stream and trend routing of §4.7), start, rules, pinned (§6.5), bad air, cover,
    penalty and sail state; the outputs of the last decision
    (target heading, let fly, fixed helm, helm integral, tactic); the telemetry (§15) and the debug record
  list bad air records (§15): uint32 tick, float deficit at the trigger, float deficit 20 s later
```

Encodings as `conventions.md` §9. The level parameters (§13) are rebuilt from the level and `speed_only`; the polar
tables and shadow classes are caches rebuilt from the world's performance data; the per-tick context is rebuilt
every step. `AiSkippers::save(writer, world)` writes the block; `AiSkippers::load(bytes, world, error)` goes into a
new `AiSkippers` after `World::load` of the same snapshot and before the next step, and rejects a block of another
tick, race seed or fleet, one that is truncated, has bytes left over or holds a value out of range. With both loaded,
the race continues with the same checksums, events and results as the run the snapshot was taken from (tested at
several ticks, `test_ai.cpp`, `test_ai_race.cpp`). A reconnect or resync (`networking.md` §9) needs only the world
snapshot; a server restart or a replay that continues AI boats needs both.
