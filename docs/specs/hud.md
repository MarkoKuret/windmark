# HUD semantics

What every in-race indicator means, how its value is computed, how it is smoothed and rounded, and when it is shown.
Layout, art and fonts belong to the front end (`game/`); this file is the contract for the numbers and states behind
them, so every front end (desktop, Steam Deck, a future browser client) shows the same values.

Conventions: `race.md` §0. Knots `kn = m/s × 3600/1852`. Values come from the core: a `HudValues` record computed per
viewed boat each tick by a pure function of the boat state, the course, the race state and the rules records.
Online the client computes it from its predicted own boat and the interpolated other boats with the same core
function; race and rules states (rank, penalties, right-of-way colours) come from the server (`networking.md` §8).

## 1. Update, smoothing, formatting

- **Filters**: "smoothed τ" means an exponential filter updated every tick, `y += (x − y)·(1 − e^(−Δt/τ))`; angles are
  filtered as unit vectors. Each value below states its τ.
- **Refresh**: numeric text refreshes at 4 Hz from the filtered value (so digits do not flicker); needles, arrows and
  lines move every frame, interpolated between ticks.
- **Formats**:

| Quantity | Format |
| --- | --- |
| speed | knots, 1 decimal (`7.4`); below 0.05 shows `0.0` |
| angle | integer degrees; headings and bearings `000`–`359` (3 digits); signed angles with a side letter (`42° P`, `38° S`) |
| distance | < 200 m: metres, integer (`85 m`); 200 m–0.2 nm: metres rounded to 5 m; ≥ 0.2 nm: nautical miles, 2 decimals (`0.43 nm`) |
| time | race clock and gaps `m:ss`; countdown `m:ss`, with tenths in the last 10 s (`0:07.4`); finish times `h:mm:ss.ss` |
| percent | integer |

- Rounding is to nearest (half away from zero) after smoothing. Truncation is never used for display.

## 2. Boat instruments

| Indicator | Definition | τ |
| --- | --- | --- |
| Boat speed (BSP) | speed through the water along the heading (`boat.md` surge speed) | 1.0 s |
| Speed over ground (SOG) | `|v_ground|` | 1.0 s |
| Heading (HDG) | ψ, compass | 0.3 s |
| Course over ground (COG) | `bearing(v_ground)` (shown only when SOG > 0.3 kn) | 1.0 s |
| Heel | heel angle, degrees, with side letter (the side that is down) | 0.5 s |
| Rudder | rudder angle as a bar, −1 … +1 of full travel, and the target from the input (two marks: actual and target) | none |
| Sail | current headsail / downwind sail name, and the one being hoisted during a change with its progress | none |

## 3. Wind

### 3.1 Numbers

| Indicator | Definition | τ |
| --- | --- | --- |
| TWS | true wind speed the boat feels: the local wind with puffs and other boats' shadow (`wind.md`, `wind_shadow.md`) | 2.0 s |
| TWA | `|a|` with the tack letter, from the felt wind | 2.0 s |
| TWD | felt true wind direction, compass FROM | 2.0 s |
| AWS, AWA | apparent wind at the masthead (`sails.md`), AWA with side letter | 1.0 s |
| Shadow | `d = 1 − TWS_felt / TWS_free` as a percentage, shown only when ≥ 3 % ("Bad air −8 %") | 2.0 s |

### 3.2 Wind indicators

- **Masthead vane** (on the boat model): points into the apparent wind, unsmoothed apart from the physics.
- **True wind arrow** (on the water around the boat, or at the radar edge): felt TWD, τ = 2 s. Its length scales
  with TWS (clamped between 0.6× and 1.5× of its base length over 0–30 kn).
- **Shift meter**: how the wind has shifted for the current tack, from the boat's own history (what a sailor knows
  from the compass):
  - `TWD_ref` = the boat's free-stream TWD averaged with τ = 180 s; `Δ = wrap(TWD_free,5s − TWD_ref)`.
  - On a beat or run, the shift is a **lift** when it turns the current tack's optimal heading towards the next mark
    and a **header** when away: header ⇔ `Δ · sign(wrap(ψ_opt − bearing(R − c))) > 0` (the same rule the AI uses,
    `ai.md` §4.4), with `ψ_opt` the VMG heading of the current tack.
  - Shown as `LIFT 6°` (green) or `HEADER 4°` (red) when `|Δ| ≥ 2°`, else `—`. Hidden on reaches.

### 3.3 Wind shadow view (assist)

With the assist on, each boat's shadow is drawn on the water as the region where its deficit exceeds `d_bad`
(`ai.md` §8) for a boat sailing through it, from the shadow model (`wind_shadow.md` exposes the field). Own shadow
is drawn fainter.

## 4. Performance

With `θ_up`, `V_up`, `θ_dn`, `V_dn` the polar VMG optima of the boat's class at the felt TWS (`ai.md` §3.1) and
`V_pol(TWS, TWA, sail)` the polar speed of the current sail. A human boat's speed factor is 1.

| Indicator | Definition | τ |
| --- | --- | --- |
| VMG | on a beat: `BSP·cos(TWA)`; on a run: `−BSP·cos(TWA)`; positive = progress along the wind towards the mark. On a reach VMG is replaced by VMC. | 2.0 s |
| VMC | velocity made good on course: `dot(v_ground, unit(R − c))`, R = the next step's target point (`race.md` §5; gate: the chosen buoy, see §7) | 2.0 s |
| Target speed | beat: `V_up`; run: `V_dn`; reach: `V_pol` at the current TWA with the best sail | 2.0 s |
| Target TWA | beat: `θ_up`; run: `θ_dn`; reach: none | 2.0 s |
| VMG % | `100 · VMG / (V_up·cos θ_up)` on a beat, `100 · VMG / (−V_dn·cos θ_dn)` on a run | 3.0 s |
| Polar % | `100 · BSP / V_pol(TWS_felt, TWA, current sail)`: how well the boat is sailed at the angle she is on, whatever the angle | 3.0 s |
| Sail hint | when the best sail for the present TWA and TWS is ≥ 3 % faster than the current one for 5 s: "Gennaker +6 %" (the gain in polar speed) | — |

The leg type is `ai.md` §4.1 (beat / run / reach). Polar % above 100 is possible (surfing, puffs in the smoothing
window); it is not clipped. VMG % measures the angle choice as well as the speed; polar % the speed only.

## 5. Trim gauge

One gauge per trimmable sail (main and the current headsail or downwind sail), fed by the sail model (`sails.md`):

- `δ` = the sail's current sheet angle (angle of the boom or clew line to the centreline), `δ_opt(AWA, AWS)` = the
  optimal sheet angle, and `δ_tol` = the half-width of the trim window in which the sail's drive is at least 95 % of
  its maximum at this apparent wind (`sails.md` must publish all three; if the window is asymmetric, use the side the
  error is on).
- Error `e = (δ − δ_opt) / δ_tol`, clamped to [−2, +2]. Positive = eased too much, negative = sheeted too hard.
- **Needle** at `e`, τ = 0.3 s. **Colour** from `|e|`: ≤ 0.5 green, ≤ 1.0 yellow, > 1.0 red.
- **Tell-tales** (text or icons): `e > 1.0` → "Luffing — sheet in"; `e < −1.0` → "Stalled — ease"; else "Flowing".
- With **auto-trim** on (assist or AI), the gauge shows a neutral needle at 0 labelled `AUTO` and no colour.
- While a sail is being hoisted or dropped its gauge is greyed.

## 6. Laylines

Shown for the next step when the leg is a beat or a run (for a gate, one pair per buoy; for the finish on a beat,
one pair per end) and the assist level allows (§14):

- Wind for the laylines: the viewed boat's free-stream TWD smoothed with τ = 10 s and its felt TWS smoothed 10 s —
  steady lines, not jumping with each puff. Angles `θ_up` / `θ_dn` from the polar at that TWS.
- Each layline is the ray from the mark backwards along the course over ground a boat would make on that tack:
  heading `TWD ± θ` plus the boat's current drift angle on that tack (leeway and current; 0 if the boat has none
  yet on that tack, then the leeway of the polar at `θ`).
- **Port-tack layline** (the line a boat sails on port tack to fetch the mark) in **red**, **starboard-tack** in
  **green**. Length `1.2 × max(|R − c|, 500 m)`.
- **Distance to layline**: along the current COG to the other tack's layline (`ai.md` §4.3 tack point); shown as
  `Layline 230 m · 0:41` (time = distance / SOG). When the boat is already past it: `OVERSTOOD 60 m` (her
  perpendicular distance beyond the line).
- Lines refresh at 2 Hz and are drawn on the water and in the radar.

## 7. Next mark

For the next step (`race.md` §5):

| Field | Definition |
| --- | --- |
| Name | the label from the course (`courses.md` §8) or the mark id, with the lap and leg (`Lap 2/2 · Leg 3/5`) |
| Rounding side | arrow: left arrow = leave to port, right arrow = leave to starboard; a gate shows both buoys' arrows |
| Distance | buoy: distance from the bow to the buoy centre minus its radius; gate: to the nearer buoy, and the gate line; line (finish): to the nearest point of the segment |
| Bearing | compass bearing from the boat to the mark (gate: nearer buoy; line: nearest point), integer, and the relative bearing to the bow (`35° L`) |
| Leg | Beat / Run / Reach |
| ETA | beat or run: axis distance `D` of the leg (`race.md` §8.2) / VMG; reach: distance / VMC; `--:--` when the divisor is below 0.3 kn |

In the 3-D view: an arrow on the mark on the rounding side, the zone circle (the viewed boat's `3·L`, `rules.md` §7.1)
drawn on the water when she is within `6·L`, and a bouncing marker over the next mark when it is more than 500 m away.

## 8. Radar / minimap

- Centred on the viewed boat; **heading-up** (default) or **north-up**; range 100 m – 3 km in steps of ×1.5; the
  last setting is remembered per player.
- **Boats** as oriented icons, scaled to at least 6 px. Colour from the rules engine's pair record between the viewed
  boat (me) and that boat (`rules.md` §11.1):

| Colour | Meaning |
| --- | --- |
| red | I must keep clear of her (she has right of way over me) |
| green | she must keep clear of me |
| orange | I owe her room (mark-room or room at an obstruction) |
| cyan | she owes me room |
| white | racing, no current relation (out of range or none) |
| grey, translucent | ghost (finished and cleared, retired, disqualified, disconnected) |

  When the pair's keep-clear or room state is `Warning`, the icon pulses at 2 Hz; `Breach` pulses at 4 Hz with an
  outline. Room colours take precedence over keep-clear colours when both apply.
- **Marks**: the next step in yellow with its rounding arrow and zone circle; the following step in white; other
  marks as small grey dots; start and finish lines (start line until the boat has started; finish line on the last
  leg); the course area boundary if any.
- **Laylines** (§6), **true wind arrow** at the edge, and the viewed boat's **shadow** (assist §3.3).
- The full map view (a separate screen) shows the whole course with every boat, the course line through the steps
  with rounding arrows, and the same colours.

## 9. Start

### 9.1 Countdown and flags

- **Countdown**: `−t` (race time, `race.md` §0) from the warning signal to the start, then the race clock counting
  up. Before the warning signal: "Warning in m:ss".
- **Flags row**: class flag (up from the warning signal to the start); the prep flag with its letter (`P`, `I`, `Z`,
  `U`, black) from the preparatory signal to one minute; `X` (individual recall) while shown (`race.md` §4.3);
  first substitute during a general recall. Each signal plays its sound (`race.md` §3.2).
- **Signal banner**: "Preparatory — I flag: over in the last minute = round an end" etc. for 3 s at each signal.

### 9.2 Start line panel (from the warning signal until the boat starts)

| Field | Definition |
| --- | --- |
| Distance to line | `s(bow)` (`race.md` §3.3): negative behind the line, positive over, when the bow's `u` is within [0, 1]; otherwise the distance to the nearer end, labelled "(end)" |
| Time to line | the time to reach the line segment along the current COG at the current SOG: `t_line = distance along COG to the segment / SOG`; `--` if the COG ray misses the segment or SOG < 0.5 kn |
| Time to burn | `(−t) − t_line`: positive = early by that much (burn it), negative = late |
| Bias | `β = wrap(bearing(n̂) − TWD)` from the viewed boat's free-stream wind smoothed 10 s (`ai.md` §5.2 formula), shown as the favoured end and its advantage: `PIN +7° · 30 m` (the upwind distance `|Δu|` by which that end is ahead) |
| Over | in the last minute and after the gun until started: `OVER` in red when the boat is over under the active flag rule (P: in the line band; I: course side incl. extensions; Z/U/black: in the triangle), with the consequence ("I flag: round an end") |
| OCS | after the gun, when the boat is OCS: `OCS — return` with the specific instruction (`race.md` §4.3), until returned |

### 9.3 Line in the 3-D view

The start line is drawn as a thin ribbon on the water between its ends: white from the warning signal, red on the
viewed boat's screen while she is over in the last minute, green after the gun until she has started, then hidden. The
committee boat flies the flags of §9.1.

## 10. Race position

| Field | Definition |
| --- | --- |
| Rank | the live rank (`race.md` §8.3) as `3 / 12`; the displayed rank changes only after the new order has held for 2 s (finishes change it at once) |
| Gap to leader | distance `D_me − D_leader` and the last common split (`race.md` §8.4) as `+0:23 @ mark 2`; between splits the estimate, marked `~` |
| Ahead / behind | the boats directly ahead and behind in the ranking with the distance difference |
| Race clock | time since the start signal |
| Split at rounding | on each `Rounded` event: `Mark 2 · 4th · +0:18` for 4 s |
| Finish | on the `Finished` event: place, time, gap to the winner |

The ranking list (Tab) shows every boat: rank, name, AI level badge for AI boats, gap, status code (OCS, pending
penalties count, RET, DSQ, finished time).

## 11. Rules awareness

From the pair records of the viewed boat (`rules.md` §11.1), highest-priority first, one line at a time:

| Condition | Message | Colour |
| --- | --- | --- |
| I am the giver, state `Breach` | `KEEP CLEAR — <rule text>` with the other boat's name and a pointer to her | red |
| I am the giver, state `Warning` | `Keep clear: <rule text>` | orange |
| I owe room, room `Warning`/`Breach` | `Give mark-room to <name>` / `Give room at the obstruction` | orange / red |
| I am entitled to room | `You have mark-room` (while the status holds) | cyan |
| rule-17 flag with me as holder | `Don't sail above your proper course (rule 17)` | yellow |
| I have right of way and the other is in `Warning` | `Starboard!` / `Leeward!` / `Right of way` (the name of the rule in plain words) | green |

- A **hail** sound can play on the rising edge of a right-of-way warning (option).
- **Protest prompt** (protest mode, `rules.md` §10): `Protest <name> (rule 11)? [P]` with an 8 s countdown.
- **Hail for room to tack** (optional rule 20): action button when valid (`rules.md` §7.9) and the reply prompt for
  the hailed boat.
- The texts use the table in §12.3.

## 12. Penalties

### 12.1 Panel

Visible while the boat has pending penalties, is taking one, or was penalised in the last 5 s:

- **Pending count** and the current one's rule text (§12.3) and the other boat's name.
- **Turn progress**: a ring filling with the tracker's `|Θ|` (`rules.md` §9.3) to 360° (or 720°), with a tack tick and a
  gybe tick that light when done; state text: `Turn: 210°`, `Not counted: inside the zone`, `Turn reset: paused`.
- **Deadline**: `rules.md` §9.4 countdown `0:32`, red below 10 s; hidden when there is no deadline (match race single
  penalty).
- **Disqualification warning**: `One more penalty = disqualification` when pending = `dsq_pending − 1` or
  received = `dsq_total − 1`.
- **Finish blocked**: `Take your penalty before finishing` on a `FinishBlocked` event.

### 12.2 Messages

On a `Penalty` event for the viewed boat: a 4 s banner `PENALTY — <rule text> (<other boat>)` and a sound; for other
boats, a fleet feed line `<boat> penalised, rule 10 (<other>)`. `PenaltyServed`: `Penalty done` banner 2 s.
`PenaltyLate`: `Penalty not taken in time: +1 turn`. `Disqualified`: full-width banner with the reason.

### 12.3 Rule texts

| Code | Short text |
| --- | --- |
| 10 | Port tack keeps clear of starboard |
| 11 | Windward boat keeps clear |
| 12 | Boat clear astern keeps clear |
| 13 | Tacking boat keeps clear |
| 14 | Avoid contact |
| 15 | Give room after gaining right of way |
| 16.1 | Changing course: give room to keep clear |
| 16.2 | Don't bear away onto a ducking port boat |
| 17 | Don't sail above your proper course |
| 18.2 | Give mark-room |
| 18.3 | Tacked in the zone: keep clear |
| 18.4 | Gybe at the mark, don't sail wide |
| 19 | Give room at the obstruction |
| 20 | Room to tack at an obstruction |
| 22.1 | Returning starter keeps clear |
| 22.2 | Boat taking a penalty keeps clear |
| 31 | Touched a mark |
| 44.1-late | Penalty not taken in time |
| C-prep | Not outside the line at the preparatory signal |
| C-entry | Did not enter through the line in time |
| SI-boundary | Outside the race area |
| 29.1 / 30.1 / 30.2 / 30.3 / 30.4 | Over early (P / I / Z / U / black flag) |

The in-game rules help explains each rule at length in our own words, with a diagram, and lists Windmark's
simplifications (`rules.md` §7.8–§7.10).

## 13. Event feed and results

- **Feed** (bottom corner, 6 lines, 8 s each): signals, starts (`12 boats started, 2 OCS`), roundings of the first
  three boats, penalties, finishes, joins and leaves, retirements.
- **Results screen** (on `RaceClosed`, `race.md` §9): place, boat, skipper, AI badge, finish time, gap to winner,
  code, points; series standings if a series. Projected AI finishes are marked `proj.`.

## 14. Assist presets

Assists change what is shown, never the physics or the rules.

| Indicator | Full | Standard | Minimal |
| --- | --- | --- | --- |
| Instruments, wind, VMG / polar % | yes | yes | yes |
| Trim gauge colours and tell-tales | yes | yes | tell-tales only |
| Laylines (water and radar) | yes | yes | no |
| Distance / time to layline | yes | yes | no |
| Next-mark arrows and zone circle | yes | yes | arrows only |
| Radar right-of-way colours | yes | yes | no (all white) |
| Rules awareness messages (§11) | all | all | `Breach` lines only |
| Start: time to burn, bias | yes | yes | distance to line only |
| Wind shadow view | yes | no | no |
| Sail hint | yes | no | no |
| Shift meter | yes | yes | no |

Online lobbies may force a maximum preset (e.g. ranked "Minimal").

## 15. Tests

- For a scripted boat state, `HudValues` matches hand-computed values for every field of §2–§7 and §9.2 (within
  the display rounding).
- VMG on a run is positive when sailing towards the leeward mark; VMC is negative when sailing away from the mark.
- Layline test: a boat placed on the computed starboard layline, sailing at `θ_up` with zero drift, reaches the mark
  within 0.5 L in a steady wind (headless sim).
- Radar colours follow the pair records for the port–starboard, windward–leeward and mark-room scenarios of
  `rules.md` §13.
- Time to burn: a boat 100 m behind the line at 5 m/s heading straight at it, 30 s before the gun, shows `t_line` 20 s
  and `+10 s` to burn.
