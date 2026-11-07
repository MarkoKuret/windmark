# Race flow

What a race is, tick by tick: the start sequence and its signals, starting and recalls, sailing the course (mark
rounding, gates, laps), finishing, the live ranking and the results. The racing rules between boats are in
`rules.md`, the course file in `courses.md`, the computer skippers in `ai.md`, the instruments in `hud.md` and the
online layer in `networking.md`. Rule numbers refer to the World Sailing Racing Rules of Sailing (RRS) 2025–2028;
the text here explains them in our own words. Windmark follows the rules except for two documented penalty
departures (`rules.md` intro: every penalty one 360° turn, completed within 120 s of the incident).

Everything in this file runs in the core on the authoritative side (the server online, the local process offline)
and is deterministic: the same course, settings, seed and inputs give the same race.

## 0. Conventions

Frames, units, the tick, arithmetic, math functions and random numbers are those of `conventions.md`: ENU world
frame (`x` east, `y` north), compass angles ψ (0 = north, clockwise), `dir(ψ) = (sin ψ, cos ψ)`,
`compass(v) = wrap_2pi(wm_atan2(v.x, v.y))`, the 50 ms tick (`DT`), integer tick index `n` and `t_ms = 50·n`,
binary32 arithmetic and the `wm_*` functions. The race-specific helpers:

| Item | Definition |
| --- | --- |
| Race time | `t = (n − n_gun) · DT`, negative before the start signal. Durations in seconds are converted to whole ticks with `ceil(T / DT)`. Displayed times come from ticks, never from wall clocks. |
| Environment clock | The race layer sets `t_env0_ms` (`conventions.md` §4) to the tick at which the race is created (the start of free sailing, §3.1), so wind and sea time starts when the boats appear. |
| Wind for race and rules logic | The **clean wind** at the boat's hull reference point: `wind_clean` of `wind.md` §9 (the boat's `wind_speed_clean`, and its direction), without other boats' shadow, so a passing shadow never flips a boat's tack. `TWD` below means that direction (`twd_from`). The physics itself sails in the shadowed wind (`boat.md` §2). |
| Wind angle | `twa = wrap_pi(TWD − ψ)` (`conventions.md` §3): **positive = wind from starboard**. `|twa|` is the true wind angle. |
| Side of a line | `left(p; a→b) = cross(b − a, p − a)` with `cross(u, v) = u.x·v.y − u.y·v.x`: > 0 when `p` is to the left of the directed line seen from above, looking from `a` towards `b`. |
| Signed angle | `ang(u → v) = wm_atan2(cross(u, v), dot(u, v))`: > 0 when v is anticlockwise (to the left) of u. |
| Rules hull | The boat's collision outline (`dynamics.collision.outline`, `collisions.md` §2.1): a convex polygon in the body frame, placed in the world at the boat's current `pos` and `ψ`, heel ignored. The race and the rules use exactly the polygon the collisions use. `L` = hull length (`loa`), `B` = beam (`bwl` if no beam is given). |
| Reference point | `c` = the boat's `pos` (the hull reference point, `data_format.md` §2). |
| Bow / stern | `bow` = the outline vertex with the largest body `x` (the stem point); `stern` = the midpoint of the outline vertices with the smallest body `x` (the transom). |

**Tack for the rules** (`rules_tack`, port or starboard, named after the windward side as in the RRS). The physics
tack is `sgn(twa)` (`conventions.md` §3); the rules tack differs only where the RRS does:

- `|twa| < π/2`: starboard ⇔ `twa > 0`, with a 1° hysteresis around `twa = 0` (the label only changes once
  `|twa| > 1°` on the other side);
- `|twa| ≥ π/2`: the tack follows the main boom (RRS: sailing by the lee or dead downwind, the leeward side is the
  side the mainsail lies on): main sail angle `β > 0` (boom to starboard, `sails.md` §3) ⇒ **port** tack,
  `β < 0` ⇒ starboard. While the boom is within 2° of the centreline the previous label is kept.

## 1. Where the race runs in the tick

The order of a tick is fixed by `conventions.md` §4.1. The race layer and the rules engine run in **step 1**, on the
state at `t_n` (the result of the previous tick's boat steps and collisions) and on the contact events of the
previous tick's step 6. Within step 1:

1. **Race progress** (this file): signals, starts, OCS, rounding, gates, finishing, time limits, ghosting.
2. **Rules** (`rules.md`): right of way, room, penalties, penalty turns, exoneration, disqualification.
3. **Ranking** and distances (§8).
4. The race layer writes the per-boat flags the physics reads this tick: `collides` (`collisions.md` §6), `casts`
   (`wind_shadow.md` §3) and `performance_scale` (`boat.md` §2, set once at spawn).

Then step 2 applies the controls: human commands stamped for tick `n` and the AI decisions, which the AI makes in
step 2 from the state and race/rules results of step 1 (`ai.md`). Steps 3–6 are the environment, the shadow snapshot,
the boat steps and the collisions; step 7 publishes the race and rules events of step 1 with the snapshot.

A line crossing, a rounding and a contact are therefore all judged on the same positions: the motion from `t_{n−1}`
to `t_n` and the contacts found at the end of that motion.

## 2. Race settings

A race is created from a course (`courses.md`) and a settings record (lobby or offline menu). Settings that the
course also defines are overridden by the lobby.

| Setting | Values | Default |
| --- | --- | --- |
| `race_type` | `fleet`, `match` | `fleet` |
| `sequence` | `5-4-1-0`, `3-2-1-0`, `match` | fleet `3-2-1-0` online quick race, `5-4-1-0` otherwise; `match` for match races |
| `prep_flag` | `P`, `I`, `Z`, `U`, `black` (§3.3) | `I` fleet; `P` match; `P` in an offline quick race whatever the course says (`menus.md` §1) |
| `free_sailing_s` | time between the boats' spawn and the warning signal | 30 s |
| `general_recall` | off / on (§4.5) | off |
| `rules_level` | `none`, `basic` (rules 10–16, 21, 31), `full` | `full` |
| `penalty` | `one_turn` only: every penalty is one 360° turn (`rules.md` §9.2) | `one_turn` |
| `umpire` | `standard`, `contact_only`, `protest` (`rules.md` §10) | `standard` |
| `time_limit_s` | race time limit after the start signal, 0 = from the course | 0 |
| `finish_window` | first-finisher window rule (§7.3) | on |
| `race_seed` | 64-bit race seed (`conventions.md` §7): spawn order, AI, wind, sea | random at creation (server) |

Game modes (for menus) are presets of these settings plus the HUD and assist options of `hud.md`. There is no mode
that changes boat speed with the race position (no catch-up of any kind).

### 2.1 Venue conditions and weather modes

The wind, current and sea settings of `wind.md` §1 and `sea.md` §2 come from the venue's `conditions`
(`data_format.md` §6.7), the race seed and the **weather mode** of the lobby or menu (`menus.md` §1):

| mode | what the race gets | briefing (`menus.md` §1.3) |
| --- | --- | --- |
| `local` (default) | the venue's own conditions, drawn within its ranges | full, with the Tip |
| `random` | a surprise day from everything the venue can plausibly produce (`conditions.random`), wider than local: light days, weak or strong days, neap or spring tides | none, anywhere: not on the card, before the start or in the race |
| `custom` | the player's wind speed and direction, a shift preset and a puff preset (defaults: the venue's); everything else the venue's | the lines without the Tip |

The shifts themselves always come from the seed (`wind.md` §4); a mode only picks their size and pace. Online,
scheduled and ranked rooms use `local` or `random` only; `custom` is for private lobbies and offline play
(`networking.md` §12.2; the rule for phase 4).

Resolved once when the race is created, in this order, in binary32 with the draws of stream 8
(`conventions.md` §7); the resolved settings are what the server sends and what a replay records.
`pick(list, i) = list[min((uint32)(rng_unit(seed, 8, i) * (float)n), n - 1)]` for a list of `n` entries.

```
// wind speed and direction
local:  base_speed = s0 + (s1 - s0) * (0.5f * (rng_unit(seed, 8, 0) + rng_unit(seed, 8, 1)))  // [s0, s1] = wind.speed
        base_from  = wrap_2pi(from + from_spread * (2.0f * rng_unit(seed, 8, 2) - 1.0f))
random: base_speed = r0 + (r1 - r0) * rng_unit(seed, 8, 4)                                    // [r0, r1] = random.speed
        base_from  = wrap_2pi(from + random.from_spread * (2.0f * rng_unit(seed, 8, 5) - 1.0f))
custom: base_speed = kn * KNOT ; base_from = deg * DEG
// shifts: the venue's (preset, replaced by any explicit values, s * 1000); random: pick(random.shift, 6);
//         custom: the chosen preset. Trend and oscillation are the venue's in every mode.
shift_trend_rate, shift_trend_max = shift.trend_rate, shift.trend_max
osc_enabled = oscillation present ; osc_amplitude, osc_time_scale = its values
// puffs: the venue's (preset, then each key given; lifetimes s * 1000); random: pick(random.puffs, 7);
//        custom: the chosen preset (a picked or chosen preset takes no venue overrides)
current_speed, current_to = current.speed, current.to
// tide (when present): the race starts at a drawn point of the whole cycle, in every mode
P       = period * 1000                                             // ms, a multiple of 4
t_gun   = (uint64)(n_gun - n_created) * 50                          // ms of environment time at the start signal
phi     = min((uint64)(rng_unit(seed, 8, 3) * (float)P), P - 1)     // ms into the cycle at the start signal
tide_phase_ms = (phi + P - (t_gun % P)) % P                         // uint64; tide(t_gun) = tide_scale * cos(2π phi / P)
tide_scale = tide.scale ; random: tide.scale * (q0 + (q1 - q0) * rng_unit(seed, 8, 8))   // [q0, q1] = random.tide_scale
tide_period_ms = P ; venue_current_field = the venue's current_field
// sea
sea_hs, sea_tp from base_speed and the venue fetch (sea.md §2) ; sea_from = base_from
swells = sea.swells ; random: each hs * (w0 + (w1 - w0) * rng_unit(seed, 8, 9))         // [w0, w1] = random.swell_scale
sea_scale = sea.scale
```
- The local speed draw is the mean of two uniforms (most races near the middle of the range); random is uniform,
  so off days are as likely as typical ones. The local direction stays within `from_spread` (at most 20°) of the
  typical direction.
- The tide keeps the venue's period (the real one, 12 h 25 min, at a tidal venue), so it is nearly steady over a
  race: the draw gives a strong flood (`phi` near 0), a strong ebb (near `P / 2`) or a stream near slack and turning
  (near `P / 4` or `3P / 4`), uniformly over the cycle. Random draws the strength on top (`tide_scale`).
- `T_race` (the course's `race.target_duration`, or 900 s without one, `courses.md` §5.2) times the trend line of
  the briefing (`menus.md` §1.3).
- Free sailing has no start: `t_gun = 0`, `T_race = 900 s`.
- Rules scenarios (§14) keep their own explicit settings and ignore the venue's conditions.
- A venue without `conditions` offers `custom` only, on the defaults of `wind.md` §1 and `sea.md` §2.

## 3. The start sequence

### 3.1 Race-level states

```
Created ──► FreeSailing ──► Sequence ──► Racing ──► Closing ──► Closed
                               ▲    │
                               └────┘ general recall (§4.5): back to Sequence with a new start time
Abandoned: from any state (server shutdown, all humans left in an online race, host decision)
```

- **Created**: course resolved (wind-relative courses laid to the wind, `courses.md` §6), boats spawned (§3.5),
  `n_gun` fixed.
- **FreeSailing**: boats sail; no signals, no rules except collisions. Lasts `free_sailing_s`.
- **Sequence**: from the warning signal to the start signal. Rules are live from the **preparatory signal** (RRS:
  a boat is racing from her preparatory signal). Between the warning and the preparatory signal only collisions and
  rule 14-style contact avoidance apply (no penalties).
- **Racing**: from the start signal until the race closes (§7).
- **Closing**: the finishing window is running (§7.3).
- **Closed**: results are final.

`n_gun` is fixed when the race is created: `n_gun = n_created + ceil((free_sailing_s + T_warning) / DT)`,
with `T_warning` the warning time of the sequence (5:00 or 3:00). Online, the server sends `n_gun` to every client
(`networking.md` §7) and every signal is derived from it; nothing about the start is sent as a timer.

### 3.2 Signals

Signals happen on the first tick whose race time `t` is ≥ the signal time (race times are negative before the start).
Each signal is an event with a sound and a flag change (`hud.md` §9).

| Sequence | Warning | Preparatory up | Preparatory down ("one minute") | Start |
| --- | --- | --- | --- | --- |
| `5-4-1-0` (RRS 26) | −5:00, class flag up | −4:00, prep flag up | −1:00, prep flag down, long sound | 0:00, class flag down |
| `3-2-1-0` (short-race variant) | −3:00 | −2:00 | −1:00 | 0:00 |
| `match` (RRS Appendix C, simplified) | −5:00 | −4:00, entry period starts (§3.4) | −1:00 | 0:00 |

The last minute is `−60 s ≤ t < 0`. A client that joins late does not replay past sounds; it only shows the current
flags.

### 3.3 Preparatory flags

The prep flag decides what happens to a boat over the line early (RRS 29 and 30). Let the **starting line** be the
segment from end `A` to end `B` of the start line (`courses.md` §4.2), oriented so that the course side (the side of
the first mark) is on the left of `A → B`; the pre-start side is on the right. For a point `p`:

- `s(p) = left(p; A→B) / |B − A|`: signed distance to the line, > 0 on the course side.
- `u(p) = dot(p − A, B − A) / |B − A|²`: position along the line, 0 at A, 1 at B.
- the **line band**: `0 ≤ u ≤ 1`; the **extensions**: `u < 0` or `u > 1`.
- the **start triangle**: the triangle A, B, first mark (for a first gate: its midpoint).

A hull is **over** when any hull point has `s > 0` and `0 ≤ u ≤ 1`. It is **on the course side of the line or its
extensions** when any hull point has `s > 0`. It is **completely on the pre-start side** when every hull point has
`s ≤ 0`.

| Flag | Rule | Trigger | Consequence |
| --- | --- | --- | --- |
| `P` | 29.1 | hull over at the start signal | OCS: return to be completely on the pre-start side, then start (§4.2) |
| `I` | 30.1 | hull on the course side of the line or its extensions at any tick of the last minute | OCS-I: return to the pre-start side **across an extension** (round an end), then start (§4.3) |
| `Z` | 30.2 | any hull point inside the start triangle at any tick of the last minute | the boat may start normally (a boat over at the start signal is OCS and must return as under `P`, rule 29.1); she receives a scoring penalty of 20 % of the `DNF` score, rounded to the nearest tenth of a point (`ZFP`, §9). The identification stands if the race is restarted after a general recall |
| `U` | 30.3 | any hull point inside the start triangle at any tick of the last minute | disqualified without a hearing (`UFD`); the boat becomes a ghost (§6.3) at the start signal |
| `black` | 30.4 | as U | disqualified (`BFD`); she also may not sail a restart after a general recall |

Under `P`, a boat that is over only at an earlier tick but back behind the line at the start signal is fine. Under
`I`, `Z`, `U` and `black` the check runs every tick of the last minute, so a boat that dips over at −0:30 is caught
even if she is back at the gun. A boat under `Z`, `U` or `black` is identified once per sequence.

### 3.4 Match race entry

Match races have two boats. At race creation boat 0 is assigned the **starboard entry end** (the end of the line
that is on the right when looking from the pre-start side towards the course side; this is `B`) and boat 1 the
**port entry end** (`A`). Following the idea of Appendix C:

1. **Outside at the preparatory signal.** At −4:00 each boat's hull must be completely outside the line band on the
   pre-start or course side beyond her assigned end: every hull point has `u > 1` (boat 0) or `u < 0` (boat 1).
   Otherwise she receives a penalty (rule "C-prep", handled as a turn penalty, `rules.md` §9).
2. **Entry.** Within 2:00 after the preparatory signal (by −2:00) each boat must cross the starting line from the
   course side to the pre-start side (her hull goes from over to completely on the pre-start side through the line
   band, detected with the crossing test of §4.1 in the reverse direction). A boat that has not entered by −2:00
   receives a penalty (rule "C-entry").
3. After the entry both boats are in the pre-start area and the normal start rules apply with the `P` flag.

### 3.5 Spawning

At race creation every boat gets a spawn pose in the course's spawn area (`courses.md` §5.1) or, if the course has
none, on an automatic grid:

- Grid rows parallel to the start line on the pre-start side at distances `d_k = (4 + 3k)·L_max` from the line
  (`L_max` = the longest hull in the race), `k = 0, 1, 2, …`; slots along each row every `3·L_max`, the row
  centred on the line midpoint and extended beyond the port end `A` by at most half the line length, not beyond
  the starboard end `B` (the boats head for it, below). Slots closer than `2·L_max` to a mark or obstruction are
  removed.
- Slots are ordered by distance from the line, then by `u`. The boats are ordered by a Fisher–Yates shuffle of
  the entry list driven by the race seed (§10). Boat `k` of the shuffled order takes slot `k`; with more
  boats than slots, rows are added.
- Heading: port tack at `twa = −60°` (a close reach), i.e. `ψ = wrap_2pi(TWD + 60°)` with the clean wind at the
  slot: on a line square to the wind that is 30° towards the line and along it towards `B`, so every boat (the
  slots run from beyond `A` to `B`) appears with the line ahead of her and in the chase camera's view (`hud.md`
  §9.3, `cameras.md` §2) and sails towards it, not away. She is behind the line at the spawn and may cross it in
  free sailing (no start rule applies before the last minute, §3.3). All boats are on the same tack and heading, so
  neighbouring slots do not converge, and no rule but collisions applies before the warning signal. Speed: 60 % of
  the polar speed at that angle, so boats are sailing when they appear.
- Placement is `boat.md` §6.6 `reset(pos_x, pos_y, psi, v, front_sail, auto_trim)`: `front_sail` from the class's
  `start.front_sail` (`data_format.md` §3.7) unless the race says otherwise; `auto_trim` from the player's assist
  setting (always on for AI boats). At the same time the race layer sets the boat's `performance_scale`: 1.0 for
  human boats, the level's value for AI boats (`ai.md` §13); it does not change during the race.
- Match races: boat 0 spawns `6·L` beyond end B, boat 1 `6·L` beyond end A, both on the pre-start side, sailing
  away from the line on the tack that points them outwards.

A boat that joins after the race was created (online, `networking.md` §9) takes the first free slot whose disc of
radius `3·L_max` contains no other boat, at the current spawn pose rule. Joining is allowed until the preparatory
signal; later joiners spectate. Match races take no joiners.

## 4. Starting

### 4.1 Line crossing test

A **crossing** of a line segment `A–B` by a moving point during a tick is detected on the segment the point
travelled during that tick, from its position after the previous tick `p0` to its position now `p1`:

```
s0 = s(p0), s1 = s(p1)
crossing from pre-start to course side  ⇔  s0 ≤ 0 < s1
f = s0 / (s0 − s1)                      # fraction of the tick at the crossing, in [0, 1]
q = p0 + f·(p1 − p0)                    # crossing point
through the line band ⇔ 0 ≤ u(q) ≤ 1
```

The **hull crosses** the line when at least one hull point crosses; the crossing time is that of the earliest
hull point (smallest `f`). Hull points are taken in the boat frame and moved with the boat, so a boat that turns in
place also sweeps its points. Boats move far less than a hull length per tick, so the per-point test is sufficient;
the rules hull points are the test points.

### 4.2 Start

After the start signal a boat **starts** when:

1. she has been completely on the pre-start side at some tick at or after the start signal (for a boat that was
   behind the line at the gun this is the gun tick itself), and
2. if she is OCS (P, §4.3) she has returned; if OCS-I (§4.3) she has returned around an end, and
3. her hull crosses the starting line from the pre-start side through the line band (§4.1).

The **start time** is `t_start = (n − 1 − n_gun)·DT + f·DT`, with `f` of the earliest hull point. Starting is
the race event `Started(boat, t_start)`; the boat's next step becomes step 1 of the course (§5).

A boat that crosses the line through the band while OCS is not starting: she is still OCS and must return.

### 4.3 OCS and returning

- **P / rule 29.1**: a boat over at the start signal is **OCS**. She has returned when she is completely on the
  pre-start side at a tick after the gun. She may then start per §4.2.
- **I / rule 30.1**: a boat on the course side of the line or its extensions during the last minute is **OCS-I**.
  Track the boat's reference point `c`: each time `c` crosses the infinite line from the course side to the pre-start
  side, record whether the crossing point is in the band (`0 ≤ u ≤ 1`: "through the line") or on an extension
  ("around an end"). She has returned when she is completely on the pre-start side and the last such crossing was
  around an end. Diving back through the band re-arms the requirement.
- While OCS, OCS-I or returning, she must keep clear of boats that are not (rule 22, `rules.md` §6.2).
- Individual recall (rule 29.1): the X flag is shown from the start signal until every OCS boat has returned or
  4:00 after the start, whichever comes first. The OCS boats are told individually (`hud.md` §9); the server knows
  exactly who is over, so there is no hail-by-sail-number ambiguity.
- An OCS boat that never returns has no start: at the close of the race she scores `OCS` (§9) whatever she did
  afterwards; she still sails on the course (and is a racing boat for the rules) until she finishes or the race
  closes, so that a mistake does not end the player's race. Until the start limit (§4.4) she can still return and
  start. At the start limit a boat still OCS or OCS-I is **released onto the course**: her next step becomes step 1
  (as if she had started there, with the winding of §5.1 set from her position then), she rounds and finishes like
  any boat and appears in the ranking, but her finish gets no place and she scores `OCS`.

### 4.4 Did not start

A boat that has not started 4:00 after the start signal (or by the race close if earlier) scores `DNS`; if she
never sailed within 10 hull lengths of the start line after the warning signal she scores `DNC`. At the start limit
such a boat (not OCS, see §4.3) becomes a ghost (§6.3). The 4-minute limit
is a Windmark choice so that a boat cannot hide behind the line; it is a race setting (`start_limit_s`, default 240).

### 4.5 General recall (optional)

With `general_recall = on`: if at the start signal at least `max(3, 30 % of the boats racing)` boats are OCS (P) or
OCS-I, the race committee (the server) signals a general recall (rule 29.2). All boats' start states reset; a new
`n_gun` is set so that the new warning signal is 1:00 after the recall; the prep flag escalates `P → I → U`
(`Z` → `U`, `U` → `black`). A boat identified under `black` may not start the restart and scores `BFD`. At most two
general recalls; the third start is sailed with `black`. Off by default because recalls cost online players
minutes. The recall is decided before the U and black disqualifications of §3.3: a recall cancels a U-flag
identification (the race is restarted), a black-flag one stands, and so does a Z-flag one (rule 30.2: the scoring
penalty applies even if the race is restarted; the restart's flag is U, so a boat cannot be identified under Z a
second time). From the recall until the new preparatory signal
the rules are not live (the boats are not racing, as between the warning and preparatory signals). The time limit
keeps its length from the new gun.

## 5. Sailing the course

The course is a list of **steps** (`courses.md` §4.4, after laps are expanded): step 0 is the start line, the last
step is the finish line, and every step between is a **mark** (one buoy with a rounding side) or a **gate** (two
buoys). After starting, each boat has a **next step** index `k` (initially 1) and must complete the steps in order
(rule 28: a string laid along her track would pass each mark on the required side, in order).

Every step has a reference point `R_k`: the buoy position for a mark, the midpoint of the two buoys for a gate, the
midpoint of the line for the start and the finish.

### 5.1 Rounding a mark: the winding test

For a mark `M` with rounding side `side ∈ {port, starboard}` ("port" = the boat leaves the mark on her port side),
previous reference `P = R_{k−1}` and next reference `N = R_{k+1}`:

```
σ        = +1 for port, −1 for starboard            # port rounding = the boat goes anticlockwise around M
α_in     = compass(P − M)                            # entry ray
α_out    = compass(N − M)                            # exit ray
sweep    = wrap_2pi( σ · (α_in − α_out) ), then + 2π if it is below π/6   # compass bearings grow clockwise
φ_done   = max(π/2, sweep − π/2)
```

The per-boat **winding angle** φ around M in the rounding direction:

- when M becomes the boat's next step (at her start, or when she completes step k−1):
  `φ = σ · wrap_pi(α_in − compass(c − M))`, the angle she has already swept from the entry ray;
- every tick after that: `φ += σ · ang(c_prev − M → c − M)` (the anticlockwise angle increment of the vector
  from the mark to the boat's reference point, with the sign that makes a port rounding positive).

In the (east, north) frame anticlockwise seen from above is the positive `ang`, and a port rounding goes
anticlockwise (the compass bearing from the mark to the boat decreases), so a port mark adds `ang` and a
starboard mark subtracts it. The initial value and the increments measure the same angle; `sweep` uses compass
bearings, where anticlockwise is a decreasing bearing, hence `α_in − α_out` for a port mark.

The mark is **rounded** on the first tick with `φ ≥ φ_done`. The event is `Rounded(boat, k, t)` with `t` the tick
time; the next step becomes `k + 1` and its winding starts.

What this means:

- φ is the net angle the boat's track has turned around the mark on the required side. It is the RRS "string" test
  in angle form: a boat that passes on the wrong side accumulates a negative φ and can only complete the mark by
  going back and unwinding it (rule 28 lets her correct before finishing).
- `φ_done`: when the course passes a mark at up to 180°, the boat must be abeam of it on the required side
  (φ = π/2, abeam of the incoming leg); when the course turns more (windward mark, leeward gate buoy, a hairpin),
  she must be abeam of the outgoing leg (`sweep − π/2`), i.e. actually around.
- A boat that rounds wide still rounds; there is no distance limit.
- The test uses the reference point; with the mark at least half a beam from the hull (else it is a collision) the
  per-tick increment is far below π, so `ang` is never ambiguous.
- `sweep` below π/6 (30°): P, M and N alone cannot tell a course that turns away from the mark by more than 150°
  from one that turns around it by a little more than 180° (a leeward gate buoy whose exit leg leans slightly
  across the entry leg gives a `sweep` of a few degrees). The sweep is then read as the turn around the mark
  (`+ 2π`), so the boat must be abeam of the outgoing leg; a course that really wants a mark on the outside of a
  turn sharper than 150° is not sailable anyway.
- Degenerate geometry: if `|P − M| < 1 m` use `α_in = α_out + σ·π` (a straight pass); if `|N − M| < 1 m` use the
  bearing of the step after N. The course validator rejects consecutive steps at the same point (`courses.md` §7).

### 5.2 Gates

A gate has two buoys `G0`, `G1`, each with its own rounding side (by default the side that keeps the buoy on the
inside of a U-turn, `courses.md` §4.3). The **gate line** is the segment `G0–G1`; its **entry side** is the side of
`P` and its exit side the other.

Per boat, while the gate is her next step:

1. **Crossings.** The reference point crossing the gate line through the band (§4.1 with the gate line) from the entry side
   to the exit side adds 1 to `n_cross`; crossing back through the band subtracts 1. Crossings outside the band do
   not count.
2. **Winding** for each buoy separately, exactly as §5.1 with `M = G0` or `G1`, its own side, and the same `P`, `N`.
3. The gate is **completed** on the first tick with `n_cross ≥ 1` and `φ_Gi ≥ φ_done,Gi` for either buoy `i`.
   The event records which buoy was rounded.

So a boat must pass between the buoys from the previous leg's side and then go around one of them; a boat that
sails around the outside of a buoy without passing between them does not complete the gate. A course may set
`gate_mode = "cross"` (`courses.md` §4.3), in which case step 3 needs only `n_cross ≥ 1`; that is for training
courses, not for racing.

### 5.3 Laps

Laps are repeated steps: a two-lap windward–leeward course is `start, W, L-gate, W, L-gate, finish` after expansion.
Each expanded step keeps its lap number and its position in the lap for display ("Lap 2/2, leg 3/4"). There is no
separate lap counter in the logic; the next-step index is the only progress state.

### 5.4 Marks, obstructions and the next step

Touching a mark is judged by the rules (`rules.md` §8, rule 31). A mark that is not the boat's next step is just an
obstruction to her. The committee boat is both the start/finish mark and an obstruction.

## 6. Finishing

### 6.1 Finish

When the next step is the finish line, the finish line segment `F_A–F_B` is oriented with the course side (the side
of the last mark's reference point) on the left of `F_A → F_B`. A boat **finishes** when:

1. she has no unserved turn penalty (`rules.md` §9: a penalty must be taken before finishing, RRS 44.2) (a boat
   released onto the course as OCS, §4.3, finishes but scores `OCS` and gets no place), and
2. her hull crosses the finish line from the course side through the band (§4.1).

`t_finish = (n − 1 − n_gun)·DT + f·DT` (the earliest hull point), stored as integer microseconds after the
gun: `t_finish_us = (n − 1 − n_gun)·50000 + (int64)round_half_even(f · 50000)`, so the tick part is exact. That fraction breaks most ties that a tick-resolution time would create; boats with equal `t_finish` share the
place (RRS Appendix A ties, §9). The event is `Finished(boat, t_finish)`.

A boat with an unserved penalty that crosses the line has not finished; the HUD says why, and she may take the
penalty and cross again (having returned completely to the course side first: if she takes the penalty near the
line she must be completely on the course side before finishing).

If the finish line is also the start line (`courses.md` §4.2) its orientation for finishing is the one above: the
side of the last mark is the course side.

### 6.2 After finishing

A finished boat stays racing for the rules until she has **cleared the finish**: 10 s after `t_finish`, or when
every hull point is more than `2·L` beyond the line, whichever is first (RRS: racing lasts until she finishes and
clears the finishing line and marks). Then she becomes a **ghost** (§6.3). Her controls stay with the player, who
can sail freely; offline and for AI boats an autopilot sails her 5 L beyond the line and 2·(i+1)·L along it
(`i` = finishing place) so finished boats spread out and leave the line clear, and stops her there (luffed, sails let
fly, the spinnaker down). Offline the front end gives the player's boat this autopilot (`wm_world_ai_add_autopilot`) on the tick her race
is over (`hud.md` §13.2: her finish, or she becomes a ghost; a ghost that did not finish stops where she is,
luffed), so the boat sails on safely while the finish view and the results run (`menus.md` §5); before that the
helm is the player's alone and the computer skippers' draws are those of a race without it.

### 6.3 Ghosts

A ghost boat is shown semi-transparent. The race layer sets its `collides = false` (`collisions.md` §6: no contact
with anything) and `casts = false` (`wind_shadow.md` §3: no shadow on others); it is ignored by the rules and the AI
and cannot interfere with racing boats (rule 23.1). It still sails normally (it still feels the other boats'
shadows). Boats become ghosts when they have cleared the finish, retired (`RET`), been disqualified (`DSQ`, `UFD`, `BFD`), timed out (`DNF` at the close),
or lost their connection for more than the grace period (`networking.md` §9).

### 6.4 Retiring

A player may retire at any time (menu): the boat becomes a ghost and scores `RET` (after her start) or `DNS` (before
it). Offline that is the pause menu's **Retire** (`menus.md` §2), from the warning signal until her finish.

## 7. Closing the race

### 7.1 Time limit

`time_limit_s` from the settings, else from the course (`courses.md` §5.2), else `2.5 × course target duration`
(`courses.md` §6.3), else 30:00. If no boat has finished when race time reaches the limit, the race is
**abandoned** (rule 35: when no boat sails the course and finishes within the time limit, the race committee
abandons the race): event `Abandoned`, state `abandoned`, no results and no rating change, as §7.4.

### 7.2 Early close

The race closes as soon as no human boat is still racing (every human boat has finished, retired, been disqualified
or left). This applies only to a race with at least one human entry; a race of computer boats only (tests, the
`sim` harness, server soak runs) closes by the rules below. Every race also closes as soon as no boat at all is
still racing (all finished or ghosts). Offline and online the AI boats still racing are then given **projected finishes**:
`t_proj = t_now + D / V_ref`, with `D` the boat's remaining course distance (§8.2) and `V_ref` 0.9 × `s` × her polar
VMG (upwind and downwind legs, from the class's VMG table, `rules.md` §3.7) or polar speed (reaching legs) averaged over the remaining legs at the current wind,
where `s` is the boat's `performance_scale` (`boat.md` §2, set at spawn, §3.5), so an Easy AI boat (`s = 0.90`,
`ai.md` §13) is projected at the pace she would sail. The average is weighted by distance:
`D / V_ref = Σ_j d_j / (0.9·s·V_j)` over the remaining part `d_j` of each remaining leg, with the leg types of §8.1,
the class's best sail and the clean wind speed at the boat. They
are ranked after every real finisher, in order of `t_proj`, and marked "projected" in the results. This keeps a
human from waiting for computer boats to cross the line; projected times are never before `t_now`, so no projected
AI boat is placed ahead of a human who finished.

### 7.3 Finishing window

With `finish_window = on`, when the first boat finishes the race enters **Closing** and the window
`T_win = clamp(0.5 × t_finish,winner, 120 s, 600 s)` starts. When it runs out, every boat still racing scores `DNF`
(an online-friendly version of the usual sailing-instruction limit after the first finisher). Humans still racing
are warned at 60 s and 10 s before the window closes.

An offline quick race (`menus.md` §1) runs with `finish_window = off`: nobody waits for the player there (the
computer boats are projected the moment she finishes, §7.2), and a window that scores a slow first race `DNF` five
minutes behind the winner would end the race before she learns to finish one. The time limit (§7.1) still closes
it.

### 7.4 Abandonment

The server may abandon a race (server stop, fewer than the minimum humans left in a ranked race). An abandoned race
has no results and does not count for ratings (rule 32 in spirit).

## 8. Live ranking and distances

### 8.1 Leg axis

For each leg `j` (from step `j−1` to step `j`, reference points `R_{j−1}`, `R_j`) the progress axis `e_j` is:

- the **wind axis** if the leg is a beat or a run: with `w` = the unit vector pointing to where the mean wind comes
  from (`dir(TWD_mean)`), `e_j = sign(dot(R_j − R_{j−1}, w))·w`, when the angle between `R_j − R_{j−1}` and `±w` is
  at most 45°;
- otherwise the **rhumb line**: `e_j = unit(R_j − R_{j−1})`.

`TWD_mean` is the race-wide wind direction `global_from(t)` of `wind.md` §2 (the median plus the present shift, no
puffs, no venue offsets, no shadow), sampled every 10 s (on ticks with `n mod 200 = 0`) and held in between so the
ranking does not jitter. The axis length of leg j is
`ℓ_j = max(0, dot(R_j − R_{j−1}, e_j))`. Measuring beats and runs along the wind axis ("ladder rungs") is what makes a
boat 200 m to the side but level with the wind counted as level, which matches how sailors read a beat.

### 8.2 Remaining distance

For a racing boat with next step k:

```
D = max(0, dot(R_k − bow, e_k)) + Σ_{j = k+1 .. last} ℓ_j
```

`bow` for a gate or mark leg; for the finish leg the distance is to the finish line along `e_last` (the line's
nearest point for a reaching finish). Finished boats have D = 0.

### 8.3 Ranking

Every tick the boats are sorted by the key:

1. finished boats, by `t_finish` (then boat index);
2. racing boats that have started, by next step index descending, then by `D` ascending (then index);
3. boats that have not started yet (before or after the gun), by distance to the start line;
4. ghosts that did not finish (RET, DSQ, …) last.

The live **rank** is the position in that order (1-based), with equal `t_finish` sharing a rank. Tie on D between
boats on the same step is broken by boat index so the order is stable. The ranking is published each tick; the HUD
shows it with hysteresis (`hud.md` §10) so it does not flicker between two boats that are level.

### 8.4 Gaps

- **Distance to the leader**: `D_me − D_leader` (≥ 0).
- **Time to the leader (split)**: at each completed step the race records the step time of every boat; the gap at
  step k is `t_me(k) − t_leader(k)`. The HUD shows the latest common split.
- **Estimated time gap** between splits: `(D_me − D_leader) / V_ref(leg of me)` (as §7.2). Labelled as an estimate.

## 9. Results and scoring

The results table of a race lists every entry with finishing place, time and score code. Scores use the RRS
Appendix A low-point system:

| Code | Meaning | Points |
| --- | --- | --- |
| (none) | finished in place n | n (ties share the average of the places) |
| `ZFP` | finished, Z-flag penalty (§3.3) | place + 20 % of the `DNF` points (entries + 1), rounded to the nearest tenth (halves to even), not above `DNF` points |

| `DNC` | did not come to the starting area (§4.4) | entries + 1 |
| `DNS` | did not start | entries + 1 |
| `OCS` | on the course side at the start and did not return (§4.3) | entries + 1 |
| `UFD` / `BFD` | U-flag / black-flag disqualification | entries + 1 |
| `DNF` | started but did not finish (time limit, window, disconnected) | entries + 1 |
| `RET` | retired | entries + 1 |
| `DSQ` | disqualified by the rules engine (`rules.md` §9.5) | entries + 1 |

"Entries" = the boats in the race (AI boats included). Projected AI finishes (§7.2) score their projected place.
Places are computed from the finished boats in time order; the non-finishing codes come after, in the table order
above (`ZFP` sits with the finishers).

A **series** (several races in one lobby) adds points; ties are broken by the most first places, then seconds, and
so on, then by the last race (Appendix A8). Discards (`drop worst`) are a lobby option. Ratings (`networking.md`
§12) use the race order, not the points.

## 10. Randomness

The server draws one 64-bit `race_seed` per race and sends it to clients (`conventions.md` §7). Every random choice
of the race layer uses the counter-based generator of `conventions.md` §7 with that seed:

- **stream 7: race layer** (`conventions.md` §7, "spawn order shuffle"). Spawn shuffle:
  draw `j = min((uint32)(rng_unit(race_seed, 7, k) * (float)(k + 1)), k)` for `k = n−1 … 1` (Fisher–Yates from the
  end), swapping entries `k` and `j`. General recall restarts use indices from 1000 upwards.
- **stream 8: venue conditions draw** (§2.1): indices 0 to 2 local (speed, direction), 3 the tide phase (every mode),
  4 to 9 random.
- AI boats use streams 16–31 (`ai.md` §1).

No wall clock, address or thread order may enter any of these.

## 11. Race events

Every tick the race layer publishes its events in tick order (for the HUD, audio, network event channel, replays):

| Event | Data |
| --- | --- |
| `Signal` | kind (warning, prep up, prep down, start, general recall, X up/down), flags now shown |
| `BoatOCS` / `BoatReturned` | boat, flag rule (29.1 / 30.1 / 30.2 / 30.3 / 30.4) |
| `Started` | boat, t_start |
| `Rounded` | boat, step, buoy (gates), t |
| `FinishBlocked` | boat, reason (penalty to take, OCS) |
| `Finished` | boat, t_finish, place |
| `Ghosted` | boat, reason |
| `Retired`, `Joined`, `Left` | boat |
| `RaceClosing`, `RaceClosed`, `Abandoned` | window length / results |

The rules layer adds its own events (`rules.md` §11).

## 12. Tests the implementation must pass (headless)

- Start: a boat 0.1 m over at the gun under `P` is OCS; the same boat exactly on the line (`s = 0`) is not; under
  `I` a boat over at −0:30 and back at the gun is OCS-I and is released only after returning around an end.
- Rounding: for each of the leg geometries straight pass, 90° turn with the mark inside the turn, 90° turn with the
  mark outside the turn, 180° U-turn and a 30° hairpin, a scripted track that rounds correctly completes the mark,
  the mirror track on the wrong side does not, and the wrong-side track followed by unwinding and a correct
  rounding completes it.
- Gate: passing between and rounding either buoy completes; rounding a buoy from outside without passing between
  does not; passing between, sailing back through, and rounding does not until the boat passes between again.
- Finish: a boat with an unserved turn penalty crossing the line does not finish; sub-tick finish times of two
  boats crossing in the same tick order them by the crossing fraction.
- Time limit: a race in which no boat has finished at the time limit is abandoned with no results.
- Z flag: in a fleet of 10 a Z-flag finisher in place 3 scores 3 + 2.2 points; her identification stands after a
  general recall.

- Ranking: two boats on a beat level on the wind axis but 300 m apart laterally have equal D (± 1 m).
- A full headless race (the default course, 10 AI boats, `sim` harness) ends with every boat finished or scored,
  and the same seed reproduces the identical results table and final state hash.
- Snapshot: the same race saved at several ticks (before the warning, in the sequence, mid-race, after the first
  finish) and loaded into a new world continues with the same checksum every tick and the same results.
- Scenario (§14): the port/starboard example scenario starts with every boat started, the port-tack boat is the
  one to keep clear under rule 10 and receives the rule 10 penalty, and a second run gives the same checksum every
  tick.

## 13. State and snapshot

The race block of the world snapshot (`conventions.md` §9.1), in this order. Entry data (class, `L`, `B`), the
settings, the resolved course and the start and finish lines come from the race parameters and are not written;
the events of the tick are not state.

```
uint8 race_type, uint8 sequence, uint8 prep_flag, uint8 state
uint32 n_created; int64 n_gun, n_warning; int32 signals_done, general_recalls
bool x_flag, rules_live, any_finished; int64 n_window_end, n_time_limit
float L_max, twd_mean, legs_twd
list  legs (§8.1): vec2 e, bool wind_axis, float length
list  boats, per boat:
  bool human; uint32 joined_tick
  bool has_prev; vec2 c_prev, c; float psi_prev, psi; list<vec2> hull_prev, hull
  bool came_near, pre_seen, ocs, ocs_i, i_around_end, z_flag, u_flag, black_flag, ocs_scored, started
  float t_start; bool entry_crossed, entered
  int32 next; float phi[2], phi_done[2]; int32 n_cross; bool finish_armed, rounded_this_tick
  int32 last_rounded; list<float> splits
  bool finished; int64 t_finish_us; int32 place; uint32 finish_tick; bool cleared, ghost; uint8 ghost_reason
  bool retired, dsq; uint8 code; bool projected; float t_proj
  float D; int32 rank
list  order (int32 boat indices by rank, §8.3)
list  results (§9): int32 boat, int32 place, uint8 code, float points, int64 t_finish_us, bool projected
list  penalty requests of the tick to the rules (§3.4): int32 boat, uint8 rule
```

## 14. Rules scenarios

A rules scenario is a short, repeatable set-up for a rules question (the "Who's wrong?" clips): two to eight boats
put on chosen courses on the first beat of an offline race, sailing into an incident about `lead` seconds later.
The file is `data_format.md` §9; the front end starts it (offline only, never online) from the core's calls alone:

1. **World.** The scenario's wind (`base_speed`, `base_from`, the shift preset, puffs, oscillation off) and seed,
   `free_sailing_s = 0`, `sequence = 3-2-1-0`, `prep_flag = P`; the other settings of §2 keep their defaults (rules
   `full`, umpire `standard`, one-turn penalties) except `weather_helm_enabled`, which a scenario world keeps **on**
   whatever the player's setting: the scripts were written on the full model (`boat.md` §2). The boats are added in file order on the scenario's class: boat 0
   is the human entry (the player's boat), the others are not human. The race is created on the scenario's course
   (§3.1).
2. **To the gun.** Before every tick each boat is placed (`wm_world_scenario_place`) on the pre-start side,
   25 m behind the start line at `u = (k + 0.5) / n` (boat `k` of `n`, §3.3), on her set-up heading, at speed 0,
   until a race tick at or after the start signal has seen them there.
3. **Start.** Each boat is placed 5 m over the line at the same `u`, at 1 m/s, and the world steps once: every boat
   has started (§4.2). A boat that has not is a start failure, and the scenario does not run.
4. **Set-up.** Each boat is placed at her set-up pose, speed and front sail (`data_format.md` §9.2); boats with
   `helm: ai` get their AI skipper now (`wm_world_ai_add`). The race sees the jump as one tick of track up the first
   beat, before any mark. This tick is clip time 0.
5. **Running.** A `hold` boat is steered by the front end before every tick: `h_cmd = clamp(2.5 · wrap_pi(ψ_set −
   ψ), −0.6, 0.6)`, let fly off, auto trim as the file says. `ψ_set` is her set-up heading until the clip time of
   her first `turns` entry (`data_format.md` §9.2), then that entry's heading, and so on: a scripted tack, gybe or
   bear-away at a mark, the same every run. AI boats sail as in any race; a `player` boat (boat 0
   only) follows the player's controls. The race and the rules run as in any race: the race clock shows the time
   since the gun, a few ticks at clip time 0.
6. **End.** At clip time `lead + after` the scene pauses the simulation (the offline pause, `controls.md` §7); the
   reset key (`reset_boat`) starts the scenario again from step 1.

The same scenario file gives the same run every time (the same checksum every tick) as long as no boat is sailed
by the player: hold boats read only the core state, and the AI skippers draw from the race seed. The positions of
step 2 and 3 never show: the scene draws nothing before clip time 0.

