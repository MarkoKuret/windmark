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
  boat's inputs.
- **No catch-up.** Nothing in the AI or its boat depends on the race position or the gap to others.
- **Deterministic.** Same seed, same inputs, same results: all randomness comes from the generator of
  `conventions.md` §7 with the race seed, in the AI streams: stream 16 = start choices (spot spread, start error),
  stream 17 = other random choices; `index = (boat_index << 32) | k`, with `k` a per-boat draw counter for that
  stream (kept in the AI state, reset at race start). All loops run in a fixed order.
- **Budget.** Decisions run at 10 Hz (on even ticks), the helm every tick. Average cost ≤ 0.2 ms per AI per decision
  on the server reference machine, so a 40-boat race costs < 1 ms per tick for the AI.

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

- Clean wind at the boat: `wind_speed_clean` and its direction (`boat.md` §2, `wind.md` §9 `wind_clean`), smoothed
  with a 2 s exponential filter: `TWD_f`, `TWS_f`.
- Felt wind: the boat's `wind_speed`, `wind_from` (with other boats' shadow), smoothed 2 s: `TWS_felt`.
- `TWD_ref`: the AI's idea of the mean direction: exponential average of `TWD_f` with a 90 s time constant (angles
  averaged as unit vectors).
- Shift `Δ = wrap_pi(TWD_f,5s − TWD_ref)`, with `TWD_f,5s` a 5 s average (positive = clockwise veer).
- Deficit `d = 1 − wind_speed / wind_speed_clean` (unsmoothed values; 0 = clean air), then smoothed 2 s. This is
  the shadow loss `l` of `wind_shadow.md` §5.
- Reading the water (Expert, Pro): `wind_clean(x, y, t_n)` at sample points on the two candidate tracks (current tack
  and other tack) at 100, 200, …, `R_read` m ahead (§13), at the present tick only.

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
ground points at it: `ψ = compass(R − c) − wrap_pi(cog − ψ)` with the present drift angle (the boat model has no
leeway, `boat.md` §6.4, so the drift is the current alone). Sail: `best_sail` for the
present TWA.

### 4.3 Beating and running: headings, laylines, tack points

- Target headings on the two tacks: upwind `ψ_port = TWD_f + θ_up`, `ψ_stbd = TWD_f − θ_up` (port tack has
  `twa < 0`); downwind `ψ_port = TWD_f + θ_dn`, `ψ_stbd = TWD_f − θ_dn`.
- **Speed build**: if boat speed < 0.85 × the polar target, sail 4° lower upwind (away from the wind) or 4° higher
  downwind until it is back above 0.92 ×.
- **Laylines**: the layline of tack t through R is the ray from R backwards along the course over ground the boat
  would have on tack t: `COG_t = compass(V_t·dir(ψ_t) + current)` with `V_t` the polar speed on that tack and the
  current at the boat (`wind.md` §7); without current, `COG_t = ψ_t`.
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
6. **Bad air** (§8).
7. **Cover** (§9).

### 4.5 Finish leg

The finish line is the target: aim at the point of the line that is closest on the current tack's COG ray if that
point is more than `L + B` inside the ends, else at the line's middle third nearest to the boat; on a beat use the
laylines to the favoured end (the end that is farther upwind along the wind axis).

### 4.6 Land and obstructions

Every decision: if `PredGap(boat, obstruction, 8 s)` on the current motion is below `2·L`, the boat tacks (beat),
gybes (run) or turns away to the side of the course (reach) — the side where the obstruction's nearest point is not.
Fixed courses may give waypoints per step (`courses.md` §8); when the direct line to R crosses land the AI routes
through them in order.

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
- **Target spot** `u* ∈ [0.05, 0.95]` along the line: with a significant bias, 0.15 from the favoured end, else 0.5;
  then each AI adds `spread·(rng() − 0.5)` (§13), clamped; if more than 3 other AIs already target a spot within
  `3·L`, the AI moves its spot `3·L` away from the favoured end, repeated until free. The spot is fixed at −75 s and
  kept unless the bias changes by more than 5°.

### 5.3 Approach heading

Starboard tack, `ψ_app = TWD_f − (θ_CH + 8°)` (a little cracked off close-hauled for speed on the run to the line).

### 5.4 Setup point and hovering

`S = spot − d_back·dir(ψ_app)` with `d_back = V_up·T_final`, `T_final` from §13. While hovering the AI keeps within
`3·L` of S: it sails at `twa ≈ +60°` (starboard) with sails let fly to 25–40 % of target speed; if it drifts more than
`3·L` from S it bears away, gybes round and comes back (a small loop, not a tack, so it never stalls head to wind).
It respects the rules against boats around it (§7) — in particular it stays on starboard whenever a boat is within
`5·L`.

### 5.5 Go decision (time to the line)

The time to reach the spot from the current state is simulated with the class's own tables (`accel` and `polar`
of the current config at `TWS_f` and the approach angle `θ_a = θ_CH + 8°`), from the current speed `v0`:

```
v = v0 ; x = 0 ; t = turn_time                    turn_time = |wrap_pi(ψ_app − ψ)| / (v0 / turn_radius_full), max 8 s
while x < d_path:                                 steps of 0.1 s, at most 120 s
    V = polar(TWS_f, θ_a) ; a = v < V ? accel(TWS_f, θ_a) : 0
    v = min(v + a·0.1, V) ; x = x + v·0.1 ; t = t + 0.1
t_run = t
d_path = distance from the bow to the spot along the approach (straight line after the turn onto ψ_app)
go when  (−t_race) ≤ t_run + 1.0 s + e_start      t_race = race time (negative), e_start = the level's start error
```

`e_start` is drawn once per start from the level distribution (§13): positive = late. Pro starts are within half a
second of the gun; Easy boats start seconds late.

### 5.6 Final approach

Sail `ψ_app` towards the spot with sails trimmed. Every decision, re-solve `t_run`: if the boat would arrive more
than 1.0 s early, luff to `|twa| = 45°` and let fly until back on time; if more than 1.0 s late, bear away 8° for
speed. In the last 5 s: if the bow is within `0.3·L` of the line and `t < −0.5 s`, luff and let fly (brake) — never
cross early on purpose.

### 5.7 Launch and OCS

- At the gun: trim on, sail the first-leg heading (beat: close-hauled on starboard, then the strategy of §4).
- **OCS (P flag)**: bear away and gybe back to the pre-start side by the shortest turn that does not cross a boat
  (§7 avoidance still applies; the boat now keeps clear of everyone under rule 22.1), then start again at full speed.
- **OCS-I**: route around the nearer end: waypoints `end + 1.5·L` beyond the end on the extension, then `2·L` behind
  the line on the pre-start side, then start.

### 5.8 Match race pre-start (v1, simple)

The entry duties of `race.md` §3.4 are sailed with waypoints: before −4:00 hold `6·L` beyond the assigned end,
outside the line band; from −4:00 enter through the line from the course side within 30 s; then hover `4·L` behind
the line's middle and start as in fleet with `u* = 0.5`. Dial-ups and hooks are not in v1.

## 6. Marks

### 6.1 Approach and rounding

- **Rounding circle**: centre M, radius `ρ = r_mark + 0.5·B + c_lvl + n_in·(B + 1 m)` where `c_lvl` is the
  level's clearance (§13) and `n_in` the number of boats the rules engine says are entitled to mark-room from this
  boat at this mark (they need space inside it).
- **Aim point** while more than `4·L` away: the tangent point of the circle on the required side as seen from the
  boat. Within `4·L`: follow the circle; the turn starts when the distance to the tangent point is below the turning
  radius at the planned helm (`boat.md` §5.9 radius law), so the boat leaves the circle on the exit tangent towards the next leg's
  heading (the VMG heading of the next leg if it is a beat or run, the direct course if a reach).
- Beats and runs to a mark use §4 until the layline; the rounding plan takes over inside `4·L` of the tangent point.
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
            slow: hold heading, let fly (brake)
for each: move own hull with CTRV at the candidate heading (turn at `|v| / turn_radius_full` to the candidate heading,
          then straight) for 6 s; move B and every other boat within 5 L on their current motion
cost = ∞                                    if PredGap to B < m (rules.md §3.1) or to any other boat < 0
     + 20 / max(gap_min_m, 0.5)             proximity to B
     + 4 · (VMC_ref − VMC_candidate)/V_ref   loss of progress to the mark
     + 3 · tack_or_gybe                      manoeuvre cost
     + 10 · creates_new_obligation           the candidate makes the AI a give-way boat to someone else (e.g. tacking to port)
choose the minimum; keep it for at least 1.5 s unless a new ∞ appears
```

The usual manoeuvres come out of this: ducking a starboard boat (bear away behind her stern), tacking to leeward
and ahead ("lee-bow") when that clears, slowing when crossing is impossible.

### 7.3 Before gaining right of way (rules 13, 15, 16)

Before a tack, gybe, luff of more than 10°, or an overtaking move that would make the AI the right-of-way boat
over a boat B within `5·L`, it predicts its pose 3 s after the manoeuvre and evaluates the rules engine's
`Escape(B, me)` (`rules.md` §3.6) from that pose. If B would have no escape, the manoeuvre is not made (the AI waits
or chooses another). It never tacks within `3·L` directly into the path of a boat on the other tack (rule 13).

### 7.4 With right of way

- **Hold course**: while a give-way boat is within `5·L` and not in `Breach`, the AI makes no course change of more
  than 5° towards it (rule 16) unless rounding a mark within its mark-room.
- **Rule 17**: when the pair has the rule-17 flag with the AI as holder, the AI's heading is limited to not above its
  proper course (`rules.md` §3.7).
- **Emergency (rule 14)**: if the give-way boat is in `Breach` and `ttc < 1.5 s`, the AI evades with the candidate
  evaluation of §7.2 but only among candidates that do not turn towards the other boat; it prefers turning parallel
  to her. This avoids damaging contacts (`rules.md` §5.1).

### 7.5 Priority

Emergency evasion (§7.4) > keeping clear (§7.2) > room at marks (§6.1) > starts and rounding plans > strategy.
A manoeuvre started by the avoidance layer is not cancelled by strategy for 1.5 s.

### 7.6 Penalty turns

With a pending penalty the AI starts a turn when all of: no boat within `4·L` ahead or `2·L` in any direction, not in
the zone of the previous or next mark, not within 30 s of its next planned rounding; or, regardless, when the
deadline (`rules.md` §9.4) is less than 12 s away. Direction: on a beat start by luffing into a tack (turn towards
the wind), on a run start by bearing away into a gybe, on a reach turn towards the wind. Helm 0.8 of full, sheets
on auto-trim through the turn, downwind sail dropped first in more than 10 kn. The turn is kept up
until the engine reports it served; if the tracker resets (`rules.md` §9.3), the AI restarts when the conditions hold
again.

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
  the start.
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
  `rudder_drag_bear` at the present speed) is at most 0.1 m/s², so the AI steers as gently as a good helm. The actual
  helm follows `h_cmd` at `helm_rate` in the physics.
- **Trim**: `auto_trim` is always on for AI boats (`boat.md` §2): the sails sit at their optimum (`sails.md` §5.2).
  The level does not add trim errors (the `performance_scale` represents crew quality).
- **Let fly**: used for braking (start, room at marks, avoidance "slow").
- **Output**: the input frame for the next tick (`networking.md` §4.1 fields), identical in form to a human's.

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
