# Sails

Sail inventory, hoisting and dropping, sheet trim, and the per-configuration performance tables that drive the
boat (`boat.md`). Frames and signs: `conventions.md` §3 (sail angle `β` from the aft centreline, positive to
starboard; a drawing sail has `sgn(β) = −sgn(AWA)`).

## 1. Inventory

A class has one **main** and any number of **front sails** (`data_format.md` §3.5). Sail types:

| type | role | pole / sprit | notes |
| --- | --- | --- | --- |
| `main` | always up | boom | never hoisted or dropped in a race |
| `jib` | upwind front sail | – | non-overlapping |
| `genoa` | upwind/reaching front sail | – | overlapping |
| `code_zero` | reaching front sail | sprit | flat, set flying |
| `spinnaker_sym` | downwind | pole, gybed from side to side | swaps sides at once when gybed |
| `spinnaker_asym` | downwind/reaching | sprit | gybes round the front of the forestay |

At most **one front sail** is up at a time; the main plus that sail is the boat's **config**, and each config has
its own performance tables (§6). With no front sail up the boat sails on the **main-only** config.

## 2. Per-sail parameters

From the performance file (`data_format.md` §4.4). Reference values: S = sportsboat, L = large monohull
(`boat.md` §4).

| name | unit | meaning | reference |
| --- | --- | --- | --- |
| `sheet_min`, `sheet_max` | rad | range of the sail angle magnitude the sheet can reach; the main's `sheet_min` may be negative (the traveller carries the boom to windward, at most π/16) | main −3°–45° (S), −3°–60° (L); jib/genoa 14–70° (L), 25–90° (S genoa); code zero 18–55° (its unsupported luff sags to leeward, so it is never sheeted as close as a jib); spinnaker sym 25–90°; asym 12–170° |
| `sheet_max_by_heel` | Table1D(`heel_abs`) → rad, optional | lower limit on `sheet_max` when heeled (the boom end reaches the water) | L main: (23°, 57°) (30°, 43°) (45°, 25°) (65°, 11°) |
| `rate_in`, `rate_out` | 1/s | sheeting-in and easing speed factors (§5.5) | main 0.5–0.65 / 0.5–1.0; jib 0.5–0.8 / 0.9–1.0; spinnakers 0.1–0.5 / 0.7–1.0 |
| `pole_angle` | Table2D(`tws`, `awa_abs`) → rad, optional | spinnaker pole / tack line angle target, magnitude | asym: 1–5° close reaching, 20–35° at 140–160° AWA |
| `pole_rate` | 1/s | pole follow rate | 0.3–0.4 |
| `shiver_angle` | Table1D(`tws`) → rad | angle to the wind line inside which the luff shivers (visual, §7) | main 12°→20° from 12 to 23 m/s TWS; jib 1–4°; spinnaker 16°→35° from 3 to 9 m/s |
| `shiver_free` | bool | the luff can shiver at any angle (spinnakers) | spinnakers true |
| `handling` | block | hoist and drop timing (§4.4) | |

## 3. State

### 3.1 Per sail (serialised in sail order, after the boat state of `boat.md` §3)

| name | type | meaning |
| --- | --- | --- |
| `phase` | uint8 | `down` 0, `prepare_hoist` 1, `hoisting` 2, `up` 3, `prepare_drop` 4, `dropping` 5 |
| `progress` | float | shown progress of a timed phase, 0..1 (fraction hoisted for `hoisting`, fraction lowered for `dropping`) |
| `beta` | float | sail angle `β`, rad, `[−π, π)` |
| `pole` | float | pole/boom angle `γ`, rad (equals `β` for sails without a pole) |

### 3.2 Per boat

| name | type | meaning |
| --- | --- | --- |
| `front` | int8 | index of the front sail that drives the boat, −1 = none (main-only config) |
| `queue[0..5]` | {sail int8, phase uint8, reversed uint8} | the running sail change, a list of steps |
| `queue_len`, `queue_pos` | uint8 | number of steps, index of the running step (`queue_pos == queue_len` = idle) |
| `queue_progress` | float | progress of the running step (not reversed) |

Reset (`boat.md` §6.6): main `up`, the requested front sail `up` and `front` = its index (or −1), every other sail
`down`, `progress = 0`, queue empty.

## 4. Sail changes

### 4.1 Steps
A change is a list of steps run in order. A step is `{sail, phase, reversed}`:
- `prepare_hoist`, `hoisting`, `prepare_drop`, `dropping` are **timed**: they last a duration (§4.4) and slow the
  boat (§4.5);
- `up` and `down` are **instant**: `up` makes the sail the front sail, `down` removes it.

### 4.2 Requests
Requests arrive as control events (`boat.md` §2): `hoist(X)` for a front sail `X`, or `drop_front()`.
With `F = front`:

**Idle** (no change running):
- `hoist(X)`, `X ≠ F`: queue `[X prepare_hoist, X hoisting, X up]`, then, if `F ≥ 0`,
  `[F prepare_drop, F dropping, F down]`. The new sail goes up first and drives the boat as soon as it is up; the
  old one comes down afterwards (a "peel"). `hoist(F)` is rejected.
- `drop_front()`: if `F ≥ 0`, queue `[F prepare_drop, F dropping, F down]`, else rejected.

**Busy** (a change is running; `S`, `P`, `p` = the running step's sail, phase and shown progress):
- **Cancel a hoist**: `hoist(F)` (asking again for the sail still up) while the running step is the new sail `S`:
  - `P = prepare_hoist`: queue `[S down]` (nothing had gone up yet);
  - `P = hoisting`: queue `[S hoisting reversed, S down]`, `queue_progress = 1 − p`: the sail comes back down
    along its hoist, from where it was.
- **Cancel a drop**: `hoist(S)` while the queue is a lone drop of `S` (it was started by `drop_front()`):
  - `P = prepare_drop`: queue `[S up]`;
  - `P = dropping`: queue `[S dropping reversed, S up]`, `queue_progress = 1 − p`.
- **Cancel a first hoist**: `drop_front()` while no front sail is up (`F = −1`) and the queue is a lone hoist of
  `S` (there is no `hoist(F)` to ask for): the same as cancelling a hoist, `P = prepare_hoist`: queue `[S down]`;
  `P = hoisting`: queue `[S hoisting reversed, S down]`, `queue_progress = 1 − p`.
- Anything else is **rejected** while busy. A rejected request changes nothing and reports `rejected` to the
  caller (HUD feedback, AI retries later).
Rebuilding the queue sets `queue_pos = 0`; `queue_progress = 0` unless stated.

### 4.3 Advance (boat step 5.3, once per tick)
```
dt_left = DT                                                  // time of this tick not yet used, seconds
while queue_pos < queue_len:
    {S, P, rev} = queue[queue_pos]
    sail[S].phase = P
    if P == up:     front = S ; sail[S].progress = 0
    elif P == down: if front == S: front = -1
                    sail[S].progress = 0
    else:
        d = duration(S, P, tws, fabsf(twa))                  // §4.4, seconds
        queue_progress = d > 1e-5 ? queue_progress + dt_left/d : 1
        q = clamp(queue_progress, 0, 1)
        sail[S].progress = rev ? 1 - q : q
        if queue_progress < 1: break                          // step still running
        if d > 1e-5: dt_left = (queue_progress - 1) * d       // leftover seconds, into the next step
    queue_pos = queue_pos + 1
    queue_progress = 0
if queue_pos >= queue_len: queue_len = queue_pos = 0 ; queue_progress = 0
```
Instant steps and finished steps fall through in the same tick, with the leftover time carried into the next
step **in seconds** (a step of another duration uses it at its own rate), so a change takes the sum of its
durations, each step ending in the tick that reaches its end time. `tws` and `twa` are this tick's values (`boat.md` §5.1).
A sail in `prepare_hoist` or `hoisting` is drawn on the way up but does not drive the boat until its `up` step;
the old front sail drives until then.

### 4.4 Durations
Per front sail, in `handling` (`data_format.md` §4.4). Each duration is either a constant (s) or a
Table2D(`tws`, `twa_abs`) → s.

| step | name | S reference | L reference |
| --- | --- | --- | --- |
| prepare hoist | `prepare_hoist_time` | jib 0.5 s, spinnaker 2 s | 2 s |
| hoisting | `hoist_time` | jib 2.5 s, spinnaker 4 s | jib 5–10 s (longer on a reach, table), asym 5–8 s |
| prepare drop | `prepare_drop_time` | jib 2 s, spinnaker 0 s | jib 2 s, asym 0 s |
| dropping | `drop_time` | jib 4 s, spinnaker 6 s | jib 5–10 s, asym 4 s dead downwind to 9–15 s upwind |

`hoisting reversed` uses `hoist_time`, `dropping reversed` uses `drop_time`. Duration tables are the place where
crew work is felt: a spinnaker drop reaching or upwind takes much longer than one dead downwind.

### 4.5 Slowdown while changing
Each timed step has a slowdown coefficient `s` (`slow_prepare_hoist`, `slow_hoist`, `slow_prepare_drop`,
`slow_drop`, 1 = none). While a step runs:
```
man_coef = s + (1 - s) * fabsf(sin(0.5f * twa))
```
which is the full slowdown `s` head to wind and none dead downwind (crew weight off the rail, sails flogging while
they are handled upwind; little effect with the boat running). Reference: prepare steps 1.0; jib hoist/drop 0.8
(L), 0.9 (S); spinnaker hoist 0.9–1.0; spinnaker drop 0.65 (L), 0.1 (S: a spinnaker drop at a leeward mark is a
real speed cost when reaching). With no change running `man_coef = 1`.

## 5. Trim

Runs in boat step 5.4 for **every** sail (down sails included, so angles stay continuous), in sail order.
`awa`, `tws`, `phi` are this tick's values.

### 5.1 Optimal angle
```
cfg_for(S) = S is main ? the current config : the config "main + S"
m_opt = clamp(cfg_for(S).optimal_angle[S](tws, fabsf(awa)), sheet_min, sheet_max)   // sheet_min if no table
beta_opt = -sgn(awa) * m_opt
```
The main's optimum depends on which front sail is up, which is why it lives in the config tables. The main's
angle is its **boom** angle; a negative `m_opt` (main only) puts the boom to windward of the centreline.

- **Main alone**: the main's own best angle for the apparent wind (the VPP's sail optimum).
- **Behind a front sail F (the slot)**: the main sits in the flow that leaves F's leech. F's circulation turns
  the wind the main meets (a header: the forward sail of a two-sail rig lifts the wind ahead of it and heads the
  wind behind it), and where the main's luff lies behind F the flow there leaves F's leech along it (the
  trailing-edge, or Kutta, condition). The main therefore trims to its own best angle for a wind coming from F's
  sail angle, not from the free stream: `m_opt[main] = best angle of the main for the wind angle
  min(β_e, m_opt[F])` (`β_e` the free stream's effective angle at the rig, `tools/vpp/README.md`). The forces are
  unchanged (the sail coefficients are in-situ coefficients against the free stream), so this moves only the
  drawn main and its place on the single manual sheet (§5.2): with a front sail up only the front sail's trim
  drives the boat (`boat.md` §5.4).
  - Close-hauled, the jib's optimum is 11 to 13° in light air and the main's best angle of attack is about
    12°: the boom is on the centreline, and a little to windward when the jib nears its inboard limit
    (pinching), as the traveller carries it there (the main's `sheet_min` −3°, an estimate of a sportsboat
    traveller's reach). As the wind builds the VPP depowers (from about 6 m/s TWS on wm7 and wm12) and the
    apparent wind widens: the jib is eased (15 to 23°) and the main with it (3 to 12° from 8 to 16 m/s), as a
    crew drops the traveller when overpowered. This is the trim of the sportsboat tuning guides: boom on or just
    above the centreline in light air, traveller down as the breeze builds (North Sails, "J/70 light air speed
    notes", 2018; North Sails, J/70 tuning guide: boom near the centreline until overpowered, slightly above
    it to point; Doyle Sails, J/70 tuning guide: traveller to weather, boom on or just above the centreline up
    to 8 kn, car above the centreline as it builds; Ullman Sails, Melges 24 guide: boom on the centreline until
    overpowered, then drop the traveller). The slot itself: Gentry (1971), "The aerodynamics of sail
    interaction", AIAA Symposium on the Aero/Hydronautics of Sailing; Marchaj (1979), Aero-Hydrodynamics of
    Sailing.
  - With an asymmetric spinnaker or a code zero the main trims to the kite: it follows the apparent wind inside
    the kite (wm7 at 4 m/s: 10° up to about 70° AWA, held by the floor below, 30° at 90°, 51° from 120°
    with the kite fully eased), as on a real boat where the main is eased until the kite's flow starts to
    backwind it and the mainsheet follows the kite sheet (never eased alone: it closes the slot). Trim guides
    describe it in these terms, without boom angles: the kite's flow "attaches to the backside of the main", the
    main is eased until it starts to luff and trimmed until the luff stops, with a small bubble accepted in a
    breeze, and the boat is steered to keep the apparent wind near 90° in reach-to-VMG mode (M. Ingham,
    "Optimizing wind flow across your asymmetric", Sailing World, 2015; North Sails, "Trim an asymmetric
    spinnaker on a sport boat"). So the boom follows the apparent wind through the kite's angle: a slow boat
    with the apparent wind aft eases, a fast one with it drawn forward sails the main sheeted in.
    The main is never trimmed closer than 10° with a kite or code zero set (the backwind floor): with the kite at
    its inboard stop on a close reach its flow would put the main near the centreline, where it only backwinds;
    the crew eases it until it luffs and trims until the luff stops (Ingham 2015), which keeps it off the
    centreline. So `m_opt[main] = max(10°, best angle of the main for the wind angle min(β_e, m_opt[F]))`.
  - A jib or genoa, and a symmetric spinnaker set to windward on its pole, fall into the main's lee abaft the
    beam: the slot fades out from 110° to 180° effective AWA (the blanketing range of §6) and the main returns to
    its own best angle (eased to the shrouds running).

### 5.2 Sheet target magnitude `m_s`
- `auto_trim` on: `m_s = m_opt`.
- `auto_trim` off (manual sheet `u = sheet_cmd`):
  - every front sail: `m_s = sheet_min + u*(sheet_max − sheet_min)`;
  - the main with no front sail up: the same with the main's range;
  - the main with front sail `F` up: `m_s = clamp((m_s[F] − m_opt[F]) + m_opt[main], sheet_min[main],
    sheet_max[main])`. One sheet control therefore trims both sails and the main keeps its trim relative to the
    headsail: hard in (`u = 0`) close-hauled the main is on the centreline or on the traveller to windward, and
    eased from there it passes through its slot trim to the depowered and fully eased angles.

### 5.3 Let-fly
While `let_fly` is held: `m_s = sheet_max` for every sail. The sheets are let run to their fully eased position at
once: no sail ever goes beyond it (the heel limit of §5.4 still holds the boom off the water), and where the wind
line lies inside it (apparent wind forward of about the beam) the wind-line clamp of §5.4 holds the sail on the wind
line, where it flogs. The drive changes at once: while `let_fly` is held every sail's trim error is taken at its
target, not at its drawn angle (§5.6), so the trim tables give the drive of the fully eased sail plan from the
first tick, while the drawn sail swings out to it at its normal easing rate (§5.5). Downwind a fully eased sail
still draws (the boat keeps sailing at the table's speed for that trim); upwind it luffs and the drive collapses.

### 5.4 Target angle
```
lim  = sheet_max_by_heel ? min(sheet_max, sheet_max_by_heel(fabsf(phi))) : sheet_max
m    = clamp(m_s, sheet_min, lim)                      // let fly too: never beyond the fully eased angle
k_h  = hoist_factor(sail)              // down, prepare_hoist, dropping: 0.1
                                       // hoisting: clamp(2*progress*progress, 0.1, 1)
                                       // up, prepare_drop: 1 ; spinnaker_sym: always 1
beta_t = -sgn(awa) * m * k_h
if type == spinnaker_asym and beta * beta_t < -1e-5:
    beta_t = (beta >= 0 ? 1 : -1) * 4.71238898f          // gybe: drive round the bow (3π/2)
elif m > 0 and fabsf(awa) < fabsf(beta_t):
    beta_t = sgn(beta_t) * fabsf(awa)                     // cannot be eased past the wind line
```
- The target sits to leeward; when the wind crosses the bow or the stern `sgn(awa)` flips and the target jumps to
  the other side, which is how tacks and gybes move the sails.
- A sail whose sheet is eased beyond the wind line stops at the wind line: it luffs, it cannot fly forward of it.
  A main on the traveller to windward (`m < 0`) is not eased and keeps its angle.
- **Asymmetric spinnaker gybe**: while the sail is still on the old side, its target is pushed to ±270° on its own
  side, so it travels forward, passes the bow (`|β| = π`, where `wrap_pi` carries it to the new side) and then
  comes back aft to the normal target, as a kite gybed round the front of the forestay does.
- `k_h` holds a sail that is not fully up near the centreline (for drawing: a sail being hoisted fills out as it
  goes up).

### 5.5 Sail motion
```
D = beta_t - beta
motion = idle
if type == spinnaker_sym and the sail has a pole_angle table:   // the kite rides on its pole (below)
    pass
elif fabsf(D) <= 1e-5 or type == spinnaker_sym:
    beta = beta_t                                             // a symmetric kite without a pole table is re-set
else:
    if (-awa - beta) * D <= 0: rate = rate_in  ; motion = sheeting   // moving away from the wind line
    else:                      rate = rate_out ; motion = easing
    step = ((fabsf(D) + 0.0872664626f) * DT) * rate               // (|D| + 5°) · dt · rate
    if fabsf(D) < 0.0174532924f: motion = idle                     // within 1°: settled
    beta = wrap_pi(beta + sgn(D) * min(step, fabsf(D)))
if the sail has a pole_angle table:
    pole_t = -sgn(awa) * pole_angle(tws, fabsf(awa))
    pole_0 = pole
    pole = pole + ((pole_t * k_h) - pole) * (DT * pole_rate)
    if type == spinnaker_sym:                                 // the kite rides on its pole (2026-11-07)
        o_t = wrap_pi(beta_t - pole_t * k_h) ; o = wrap_pi(beta - pole_0)          // the kite's angle off its pole
        D_o = o_t - o ; step = ((fabsf(D_o) + 5°) * DT) * (rate_in, rate_out as above)
        o = o + sgn(D_o) * min(step, fabsf(D_o))
        beta = place ? beta_t : wrap_pi(pole + o)
else:
    pole = beta
```
A symmetric kite on a pole rides on it: its angle is the pole's plus its own angle off the pole, which follows its
target at the sheeting rates. In a gybe the core turns the pole target to the other side at once and the pole
swings across ahead of the mast at `pole_rate` (end for end), carrying the kite with it, while the kite's angle
off the pole goes over to the new side at the sheeting rates; the drawn kite and pole move continuously. Until
2026-11-07 the kite was re-set to its target at once while the pole swung, so the drawn kite jumped across in one
tick.
The motion is fast for big corrections and slows as the sail nears its target (a first-order approach plus a
5° floor so it does arrive), so a tack swings the headsail across in 1–2 s and trim corrections settle smoothly.
`motion` drives crew and winch animation and sounds.

### 5.6 Trim error
```
b   = (let_fly and beta_t is not the gybe target of §5.4) ? beta_t : beta
eps = -sgn(awa) * wrap_pi(b - beta_opt)
```
With let fly held the error is the target's, so the drive of the fully eased sails applies at once (§5.3); released,
it is the drawn sail's again, and the drive comes back as the sail is sheeted in from fully eased.
For a sail on the leeward side `eps = |β| − |β_opt|`: **positive = eased beyond the optimum** (toward luffing),
**negative = sheeted in beyond it** (toward stall). The driving sail's `eps` (`boat.md` §5.4) enters the trim
tables. A sail swinging across in a tack or gybe has a large error for a moment, which is the drive lost in the
manoeuvre. At reset (`boat.md` §6.6) `beta = beta_t`, `pole = pole_t · k_h`, so boats start trimmed.

## 6. Performance tables per config

Each config (main only, main + each front sail) has these tables in the performance file (`data_format.md`
§4.3). They are generated by the VPP tool from the class file; axes and units are fixed.

| table | axes | unit | meaning |
| --- | --- | --- | --- |
| `polar` | `tws`, `twa_abs` | m/s | steady boat speed at optimal trim, flat water, heel as in `heel` and at `heel_speed_factor = 1`; negative inside the no-go zone (`boat.md` §7.4) |
| `heel` | `tws`, `twa_abs` | rad | steady heel magnitude at optimal trim |
| `accel` | `tws`, `twa_abs` | m/s² | acceleration toward the polar when below it |
| `accel_rest` | `tws`, `twa_abs` | m/s² | acceleration from rest (optional, `accel`) |
| `trim_speed` | `tws`, `awa_abs`, `trim_error` | – | speed factor for a trim error `eps` (optional, 1) |
| `trim_heel` | `tws`, `awa_abs`, `trim_error` | – | heel and weather-helm factor for `eps` (optional, 1) |
| `weather_helm` | `tws`, `twa_abs` | rad/s | helm balance: turning rate the sail plan imposes, + toward the wind (optional, 0) |
| `fall_off` | `boat_speed`, `twa_abs` | rad/s | turning away from the wind at low speed and in sternway (optional, 0) |
| `flog_drag` | `aws`, `awa_abs` | m/s² | deceleration from the sails flogging on free sheets (optional, 0) |
| `drift`, `drift_flog` | `tws`, `twa_abs` | m/s | sideways drift at rest, sails luffing / flogging (optional, 0; `boat.md` §6.4) |
| `leeway` | `tws`, `twa_abs` | rad | leeway of the sailing boat, only with `full_leeway` (`boat.md` §6.4) |
| `optimal_angle.<sail>` | `tws`, `awa_abs` | rad | optimal sail angle magnitude of the main and of the config's front sail |

Semantics and reference shapes:
- **polar**: rows TWS 0–40 kn (the 0 row holds 0), columns TWA 0–180°. Reference S, main + genoa at 10 kn TWS:
  4.5 kn at 38°, 4.9 kn at 45°, 5.4 kn at 60°, 5.2 kn at 90°, 4.5 kn at 120°, 3.0 kn at 180°; main + spinnaker at
  10 kn: 8.0 kn at 80°, 8.5 kn at 90°, 7.7 kn at 125°, 5.5 kn at 150°, 4.0 kn at 180°. The no-go zone below the
  first sailing angle holds the sternway drift (`boat.md` §7.4), with a step (two equal breakpoints) at the edge.
  Downwind and reaching the shipped classes follow ORC velocity predictions of their nearest real boats within
  about 5 % from 16 to 20 kn, and wm7 from 12 kn (wm7: Melges 24 and J/70; wm12: Farr 40; best sail in each cell,
  run VMG and 135 to 150°; `tools/vpp/README.md` "Calibration against ORC"). Lighter they sit 5 to 10 % below
  (the open light-air deficit).
- **Which config is fastest** (the crossover, best polar speed per TWA): the jib or genoa upwind and close
  reaching, the spinnaker from a broad reach, and the code zero, where a class has one, on tight reaches between
  them. The code zero is the ORC headsail set flying of HHW/HLP 62.5 % (a flat reacher; ORC VPP Documentation
  2023 §5.2.5 and Table 5.9), with the main in its slot behind it and almost no depowering (reef no lower than
  0.91, the ORC value; the code zero itself is never reefed). wm12 flies it from about 45 to 110° TWA in 6 kn,
  60 to 110° in 10 kn, 82 to 114° in 12 kn, and only from about 100 to 120° from 16 kn, where the asymmetric
  kite is overpowered and the jib is slower; it never wins running. Real crossovers: North Sails, code zero 55 to 90° AWA;
  UK Sailmakers, 50 to 125° TWA; ORC speed guides (Tripp 40), flying headsail best from 60 to 90° TWA in every
  wind.
- **heel**: reference S main + genoa at 10 kn: 14° at 39°, peaking about 18° at 40°, 0 at 180°; spinnaker at
  10 kn: 13° at 80°, 5° at 136°.
- **accel**: small close to the wind (0.005 m/s² from 15° to 30°), larger reaching (S jib at 10 kn: 0.09 m/s² at
  40°, 0.23 at 60°, 0.34 at 90°; spinnaker 0.35 m/s² at 90°, 0.5 at 120°), growing with TWS. It is the constant
  acceleration that takes the boat from half its polar speed to 90 % of it in the time the physics does (the speeds
  a boat rebuilds through after a tack or a gybe); the approach to the polar is still limited by `err/DT`
  (`boat.md` §5.8).
- **accel_rest**: the drive of the trimmed sail plan in the true wind at rest over the mass with added mass (the
  hull has no resistance ahead at rest), with the no-go and floor rules of `accel`. Reference S jib at 10 kn:
  0.2 m/s² at 40°, 0.36 at 60°, 0.5 at 90°. The core blends from it to `accel` below half the target speed
  (`boat.md` §5.8).
- **trim_speed**: 1 on a plateau around `eps = 0` (width grows with `awa_abs`: ±0.5° at 45° AWA, about −3.8°/+1.2°
  at 180°), falling to 0 when eased to the wind line (reference +15° at 45° AWA, +120° at 180°) and to 0.6–0.75
  when over-sheeted (reference −13° at 45°, −41° at 180°). Spinnakers: 0.7–0.8 over-sheeted (a kite keeps some
  drive when mistrimmed). Let fly holds the driving sail at its fully eased angle (§5.3), so the core looks the
  table up at `eps = min(lim, awa_abs) − m_opt`: where the fully eased angle lies beyond the wind line that is the
  wind line, elsewhere it is the regular value of the fully eased sail, which downwind still draws (reference S
  running in 10 kn: the optimum of the jib and the kite there is their fully eased angle, so letting fly costs
  nothing). With the driving sail on the wind
  line (`eps = awa_abs − m_opt`, let fly or eased that far) the flogging sails give no drive: with the apparent wind forward of the beam (`awa_abs` up to 90°) the
  value is **exactly 0** wherever the core looks it up, so a boat that lets fly there coasts to rest. Abaft the
  beam the windage of hull, rig and flogging sails still pushes the boat along, and the value is the **let-fly
  share**: the steady speed that push drives against the upright hull, over the polar (reference S running in
  10 kn: about 0.7), resampled per TWS row with the apparent wind angle at that speed as the abscissa, so the
  core, which looks it up at the boat's own apparent wind, finds the let-fly speed when the boat sails at it (only
  a sail whose fully eased angle lies abaft the beam, a code zero or an asymmetric kite with a long sheet range,
  can reach the wind line there). The
  VPP writes the wind-line value from the `trim_error` point at or below the smallest wind-line error of the
  neighbouring table points, so the interpolation between them holds it; the drive is cut at most one axis step
  (5°) before the line.
- **trim_heel**: the heel of the sail plan sheeted `eps` away from its optimum over the trimmed heel, **both at the
  same boat speed and apparent wind** (the trimmed boat's at that `tws` and `awa_abs`): 1 at `eps = 0`, 0 on the
  wind line (as `trim_speed`), rising when over-sheeted as the stalled sails push sideways harder than drawing
  ones. A sail sheeted in past its stall keeps at least the normal force it had at the stall (or at its optimum,
  where that is itself stalled), as a separated plate does; only this table uses that, `trim_speed` and the
  trimmed envelopes are unchanged. Reference S jib config on a beam reach: about 1.4 fully sheeted in at 10 kn;
  less where the trimmed boat already heels near the heel of its greatest righting moment, which caps it.
  Over-sheeted the core reads it at the trimmed boat's apparent wind angle and scales the heel with the boat's own
  apparent wind speed (`boat.md` §5.5), so the heel is what the stalled sails push at the speed the boat is
  making, not at a settled speed: on a reach sheeting hard in lays the boat over at once, and as it slows the heel
  follows its lighter apparent wind back down (`boat.md` §6.2, §10.10).
- **weather_helm**: the yaw moment of the sail plan about the centre of lateral resistance, as the turn rate of
  the helm that holds it at the polar speed. The moment: the drive acting at the centre of effort, which the sheet
  angle (each sail's centre of effort swung about its luff) and the heel carry out to leeward (luffing), and the
  side force acting at the centre of effort ahead of the centre of lateral resistance (bearing away). The centre
  of lateral resistance is the class's balance point: where the upwind (start) config's moment vanishes
  close-hauled at its VMG angle in 12 kn, as a racing boat is designed and its rig raked to sail straight to
  windward with the helm centred; every config balances about the same point. The helm `h_e` that holds the moment
  on a straight course is its ratio to the rudder's yaw moment per unit helm (linear range, the whole rudder angle
  reaching the blade: a few degrees of rudder on a well-balanced boat); the rate is `v/R(h_e)` on the radius law
  (`boat.md` §5.9), which is also the rate at which the boat turns with the helm centred (the centred blade damps
  the free turn as much as a helm turn loses of its rudder angle to the turn's cross-flow), growing as
  `v·h_e/R_full` beyond full helm (a boat the rudder cannot hold broaches); `h_e` is held to ±3. Broached cells
  (`vpp.broached`) from 45° TWA where the heel is what failed are **overpowered**: the boat lies over at its heel
  limit and rounds up at the full-helm turn rate of its broached speed, `v_b/R_full` (a full helm at speed can
  still catch it); the other broached cells (pinching in a strong breeze) take the value of the last wind the
  config holds at that angle; 0 in the no-go zone and in no wind. Resulting shapes: upwind config 0 at the
  balance point, a little lee helm in light air and pinching, a slight weather helm reaching (reference S jib at
  10 kn: +1°/s from 60° to 110°, a helm of about 0.02; at 16 kn +1.5°/s at 60°, +3 to +5°/s from 80° to 110°
  heeled near its limit, a helm of about 0.05); main alone: weather helm (S at 10 kn about +1.5°/s); spinnakers:
  negative close reaching in light air (the kite, far forward, pulls the bow off: S at 10 kn −3 to −6°/s from 50°
  to 80°, where the kite is the wrong sail), small across the normal range, a moderate weather helm broad reaching
  in a breeze (S at 22 kn about +4°/s at 130°, L about +8°/s: the crew holds the heel within the spinnaker heel
  limit, `tools/vpp/README.md` "Heel and depowering"), and a broach where the kite is overpowered (S
  from 50° at 14 kn and on a reach from about 20 kn: +10 to +20°/s). Scaled by `trim_heel` (`boat.md` §5.5,
  §5.9), so an over-sheeted sail plan rounds up sooner and flogging sails have none.
- **fall_off**: the same for every config (the sails are flogging). Speed axis from sternway to a crawl ahead
  (reference −6, 0, `v_f`/2, `v_f` m/s with `v_f` at Froude number 0.05, `0.05·sqrt(g·lwl)`: S 0.4 m/s, L 0.7 m/s),
  full from sternway to 0, 0.75 at `v_f`/2, zero from `v_f` (the keel holds the heading once the boat moves);
  reference S 8°/s, L 5°/s between 20° and 60° TWA, fading to 0 at 90° (a stopped boat lies beam on), zero below
  10° TWA (a boat right head to wind stays in irons, `boat.md` §7.4). Light-air sailing speeds stay above `v_f`, so the table never turns a
  sailing boat.
- **flog_drag**: the extra drag of the config's sails flogging on free sheets over luffing on their sheets (which
  the windage term of `boat.md` §5.8 holds), along the heading, per apparent wind speed and angle: `0.5 ρ_air aws² (CD_flog − CD_luff)
  A_sails cos(awa) / (m + m_a)` with the wind profile factor at the centre of effort, 0 from 90° AWA (abaft the
  beam the flogging sails push instead: the let-fly share of `trim_speed`). `CD_flog` 0.30 and `CD_luff` 0.06 on
  the sail area (`tools/vpp/README.md`). Reference S jib config at 8 m/s apparent wind head to wind: about
  0.24 m/s². Used only with free sheets (`boat.md` §5.8).
- **drift**, **drift_flog**: the steady sideways drift to leeward of the boat at rest with the config's sails on
  the wind line, luffing on their sheets (`CD_luff`) or flogging on free sheets (`CD_flog`): the cross-wind part of
  the windage of hull, rig and sails at the apparent wind the drifting boat feels, against the cross-flow drag of
  hull, keel and rudder (`tools/vpp/README.md`, "Sideways drift"). Rows TWS 0–40 kn (0 row 0), columns TWA 0–180°
  every 5°, 0 at both ends. Reference S jib config in 10 kn: 0.4 kn at 30°, 0.6 kn at 90° luffing, 0.8 kn at 90°
  flogging; it grows in proportion to the TWS. Used by the core only at a crawl (`boat.md` §6.4).
- **leeway**: the VPP's leeway angle at the polar's equilibrium (keel and rudder lift against the side force), 0
  in the no-go zone; written only for a class with `full_leeway` on (`boat.md` §6.4).
- **optimal_angle**: main alone: its own best angle, 10–20° close-hauled rising to the shrouds from about 90°
  AWA; behind a front sail the slot trim of §5.1 (jib: −3 to 2° close-hauled up to 6 m/s TWS, 3–12° from 8 m/s
  where the VPP depowers; kite: following the apparent wind inside the kite, at least 10°, about 30° at 90° AWA); jib/genoa 14–25° close hauled rising to 55–70°; spinnakers 12–30° at their lowest AWA rising to 85–90° dead downwind.

## 7. Outputs for drawing, crew and sound

Per sail, each tick:

| output | meaning |
| --- | --- |
| `phase`, `progress` | hoist/drop state for the hoisting animation (halyard or furler; see the renderer spec) |
| `beta`, `pole` | sail and boom/pole angles (renderers interpolate them between ticks with `angle_lerp`) |
| `beta_t` | optional: the target angle of the sail motion (§5.4); `fabsf(beta_t − beta)` tells winch and crew sounds how much trimming is still to come |
| `k_h` | how filled a hoisting sail is (§5.4) |
| `motion` | idle / sheeting / easing (winch and crew animation, sheet sounds) |
| `trim_error` | `eps` (HUD trim indicator) |
| `luff_shiver` | luff flutter intensity 0..1, below |
| `backed` | `sgn(beta) == sgn(awa)` and `fabsf(beta) > 0.02 + max(−sheet_min, 0)` (the sail is aback on the windward side; a main on its traveller to windward is not) |

```
luff_shiver:
  d = beta + awa                                     // angle between the sail and the wind line
  if !shiver_free and fabsf(d) >= HALF_PI: I = 0
  else: q = clamp(fabsf(sin(d)) / (sin(shiver_angle(tws)) + 1e-4f), 0, 1) ; I = 1 - q*q
```
`I = 1` when the sail lies on the wind line (let fly, or eased too far), 0 once it is more than `shiver_angle` off
it. A hoisted spinnaker shivers at least its flogging share beyond its usable angle, `I = max(I, f_k)` (`boat.md`
§5.8): the boat sets it after the trim each tick (`Sails::set_kite_flog`). Events: every phase change emits `sail_phase(boat, sail, phase)` for crew actions and sounds.

## 8. Tests

1. Peel timing: at 10 kn TWS, 90° TWA, hoist the spinnaker with a jib up: the spinnaker drives from exactly
   `prepare_hoist_time + hoist_time` after the request, the jib reaches `down` after the sum of all six steps
   ("exactly" = in the tick that reaches that time: at or after it, less than one tick after).
2. Cancel: cancel a hoist halfway through `hoisting`: the sail's `progress` falls from 0.5 to 0 over half the hoist
   time and ends `down`; `front` never changes.
3. Tack: sails swing to the new side within 2 s at S reference rates; `eps` returns within ±1° of 0 with auto-trim.
4. Asym gybe: the sail angle passes through ±π and settles on the new side, never through 0.
5. Manual sheet: with `u` fixed, turning from 45° to 90° AWA makes `eps` grow negative (over-sheeted) and the
   speed fall below the polar by the `trim_speed` factor.
6. Cancel a first hoist: with no front sail up, `drop_front()` halfway through `hoisting` brings the sail down
   along its hoist; during `prepare_hoist` it is down in the next tick; `front` stays −1.
7. Wind line: for every config, TWS 0.25–20 m/s and AWA 3°–180° on a fine grid, `trim_heel` is 0 at the driving
   sail's wind-line error (where that is at least 0.5° past the optimum), and `trim_speed` too up to 90° AWA (below
   1 beyond: the let-fly share); with let-fly held on a reach the boat's `trim_speed` output is 0 and it slows
   down.
8. Let-fly limit: with let-fly held close-hauled, reaching and running, no sail's angle is ever beyond its fully
   eased angle (`sheet_max`, the heel limit); the driving sail's `eps` is the target's from the first tick (the
   boat's `trim_speed` drops in that tick, not as the sail swings out); running, the boat keeps sailing.
