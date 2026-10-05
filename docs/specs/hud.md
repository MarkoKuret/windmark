# HUD semantics

What every in-race indicator means, how its value is computed, how it is rounded, and when it is shown.
This file is the contract for the numbers and states behind them, so every front end (desktop, Steam Deck, a future
browser client) shows the same values, and (§16) for what the player chooses to see: the instrument density levels,
the colour meanings, the world tags and the cameras that draw the penalty turn. The exact layout and art are the
front end's (`game/`, after `docs/design/hud_direction.md`).

Conventions: `conventions.md` and `race.md` §0 (`twa` positive = wind from starboard). Knots: `m/s / KNOT`.
Player-facing strings below contain no em dashes (project rule). Values come from the core: a `HudValues` record computed per
viewed boat each tick by a pure function of the boat state, the course, the race state and the rules records.
Online the client computes it from its predicted own boat and the interpolated other boats with the same core
function; race and rules states (rank, penalties, right-of-way colours) come from the server (`networking.md` §8).

## 1. Update, smoothing, formatting

- **No display smoothing**: the instruments show the core's values of the tick as they are (the boat's own filtered
  outputs `v_filt`, `sog_filt_x`, `sog_filt_y` are the core's, `boat.md` §5.10). A HUD filter would only add lag: a
  2 s filter on TWA, for example, showed the old tack for about 2 s after a tack and then crept to the new angle over
  another 6 s. The only HUD filters are the wind references that are averages by definition: the clean-wind direction
  for the leg type (2 s, `ai.md` §4.1), the laylines and the start-line bias (10 s), and the shift meter (5 s against
  180 s). "Smoothed τ" there means an exponential filter updated every tick, `y += (x − y)·k` with
  `k = 1 − wm_exp(−DT/τ)`; directions are filtered as unit vectors.
- **Refresh**: numeric text refreshes at 4 Hz (so digits do not flicker at the tick rate); needles, arrows and lines
  follow the latest tick every frame.
- **Formats**:

| Quantity | Format |
| --- | --- |
| speed | knots, 1 decimal (`7.4`); below 0.05 shows `0.0` |
| angle | integer degrees; headings and bearings `000`–`359` (3 digits); signed angles with a side letter (`42° P`, `38° S`) |
| distance | < 200 m: metres, integer (`85 m`); 200 m–0.2 nm: metres rounded to 5 m; ≥ 0.2 nm: nautical miles, 2 decimals (`0.43 nm`) |
| time | race clock and gaps `m:ss`; countdown `m:ss`, with tenths in the last 10 s (`0:07.4`); finish times `h:mm:ss.ss` |
| percent | integer |

- Rounding is to nearest (half away from zero). Truncation is never used for display.

## 2. Boat instruments

| Indicator | Definition |
| --- | --- |
| Boat speed (BSP) | the boat's `v_filt` (`boat.md` §5.10: speed through the water along the heading, filtered by the core) |
| Speed over ground (SOG) | length of the boat's filtered ground velocity (`sog_filt_x`, `sog_filt_y`) |
| Heading (HDG) | ψ, compass |
| Course over ground (COG) | `compass(sog_filt_x, sog_filt_y)` (shown only when SOG > 0.3 kn) |
| Heel | `|φ|`, degrees, with the letter of the side that is down (φ > 0: starboard down, `conventions.md` §3) |
| Rudder | helm `h` as a bar, −1 … +1 (positive turns the bow to starboard), with a second mark at `h_cmd` |
| Sail | the front sail that is up (or "Main only"), and the one being hoisted during a change with its progress |

The player's own commands (the `h_cmd` mark, the sheet setting and its bar, `AUTO`, `LET FLY`) show the local
command of the rendered frame, not the value the simulation last applied, so they answer the key at once; the
simulation takes the command at its next tick. For any other boat (spectating, replays) they come from its
controls record.

## 3. Wind

### 3.1 Numbers

| Indicator | Definition |
| --- | --- |
| TWS | the boat's `tws`: true wind the boat feels, relative to the water, with puffs and other boats' shadow (`boat.md` §5.1) |
| TWA | the boat's `twa = wrap_pi(twd_from − ψ)` (`boat.md` §5.1: the heading against the true wind direction, not the course over ground), shown as `|twa|` with the tack letter (`S` for `twa > 0`, `P` otherwise) |
| TWD | the boat's `twd_from`, compass |
| AWS, AWA | apparent wind at the masthead (`sails.md`), AWA with side letter |
| Shadow | `d = 1 − wind_speed / wind_speed_clean` (`boat.md` §2) as a percentage, shown only when ≥ 3 % ("Bad air −8 %") |

### 3.2 Wind indicators

- **Masthead vane** (on the boat model): points into the apparent wind, unsmoothed apart from the physics.
- **True wind arrow** (on the water around the boat, or at the radar edge): felt TWD. Its length scales
  with TWS (clamped between 0.6× and 1.5× of its base length over 0–30 kn).
- **Shift meter**: how the wind has shifted for the current tack, from the boat's own history (what a sailor knows
  from the compass):
  - `TWD_ref` = the direction of the boat's clean wind (`wind_clean` at its position) averaged with τ = 180 s;
    `Δ = wrap_pi(TWD_clean,5s − TWD_ref)`.
  - On a beat or run, the shift is a **lift** when it turns the current tack's optimal heading towards the next mark
    and a **header** when away: header ⇔ `Δ · sgn(wrap_pi(ψ_opt − compass(R − c))) > 0` (the same rule the AI uses,
    `ai.md` §4.4), with `ψ_opt` the VMG heading of the current tack.
  - Shown as `LIFT 6°` (green) or `HEADER 4°` (red) when `|Δ| ≥ 2°`, else `--`. Hidden on reaches.

### 3.3 Wind shadow view (assist)

With the assist on, each boat's blanket and backwind outlines (`wind_shadow.md` §7 `shadow_zones`) are drawn on the
water, shaded by the loss `l` sampled at the outline's interior points; the part where `l ≥ d_bad` (`ai.md` §8) is
drawn darker. The own boat's shadow is drawn fainter.

## 4. Performance

With `θ_up`, `V_up`, `θ_dn`, `V_dn` the polar VMG optima of the boat's class at the felt TWS (`ai.md` §3.1) and
`V_pol` the boat's `polar_speed` output (`boat.md` §5.4: the polar of the active config at the present `tws`, `twa`).
A human boat's `performance_scale` is 1.

| Indicator | Definition |
| --- | --- |
| VMG | on a beat: the boat's `vmg` (`v·cos(twa)`, `boat.md` §5.10); on a run: `−vmg`; so the display is positive for progress along the wind towards the mark. On a reach VMG is replaced by VMC. |
| VMC | velocity made good on course: `dot((sog_filt_x, sog_filt_y), unit(R − c))`, R = the next step's target point (`race.md` §5; gate: the chosen buoy, see §7) |
| Target speed | beat: `V_up`; run: `V_dn`; reach: `V_pol` at the current TWA with the best sail |
| Target TWA | beat: `θ_up`; run: `θ_dn`; reach: none |
| VMG % | `100 · VMG / (V_up·cos θ_up)` on a beat, `100 · VMG / (−V_dn·cos θ_dn)` on a run |
| Polar % | `100 · v / polar_speed`: how well the boat is sailed at the angle she is on, whatever the angle; `--` while `polar_speed` is below 0.3 kn (head to wind) |
| Sail hint | when the best config for the present TWA and TWS (`ai.md` §3.1) is ≥ 3 % faster than the current one for 5 s: "Code zero +6 %" (the gain in polar speed) |

The leg type is `ai.md` §4.1 (beat / run / reach). Polar % above 100 is possible (surfing, a puff before the boat has
picked up speed, the carried speed of a tack); it is not clipped. VMG % measures the angle choice as well as the speed;
polar % the speed only.

## 5. Trim gauge

One gauge per trimmable sail (the main and the front sail that is up), fed by the sail model (`sails.md` §5.6, §7):

- `eps` = the sail's `trim_error` (rad): **positive = eased beyond the optimum** (towards luffing), negative = sheeted
  in beyond it (towards stall).
- Tolerance: `eps_tol+` and `eps_tol−` = the positive and negative trim errors at which the config's `trim_speed`
  table (`sails.md` §6) falls to 0.98 at the present `tws` and `|awa|`, found by stepping `eps` in 0.1° steps out to
  ±30° (cached per 0.5 m/s of TWS and 1° of AWA). Without a `trim_speed` table: ±2°.
- Normalised error `e = eps / eps_tol+` if `eps ≥ 0`, else `eps / |eps_tol−|`, clamped to [−2, +2].
- **Needle** at `e`. **Colour** from `|e|`: ≤ 0.5 green, ≤ 1.0 yellow, > 1.0 red.
- **Tell-tales** (text or icons): `e > 1.0` or `luff_shiver > 0.5` → "Luffing: sheet in"; `e < −1.0` →
  "Stalled: ease"; `backed` → "Aback"; else "Flowing".
- With `auto_trim` on (assist, and always for AI), the gauge shows a neutral needle at 0 labelled `AUTO` and no
  colour; a manual sheet control is hidden.
- While a sail is in `prepare_hoist`, `hoisting`, `prepare_drop` or `dropping` its gauge is greyed.

## 6. Laylines

Shown for the next step when the leg is a beat or a run (for a gate, one pair per buoy; for the finish on a beat,
one pair per end) and the assist level allows (§14):

- Wind for the laylines: the direction of the viewed boat's clean wind smoothed with τ = 10 s and its `tws`
  smoothed 10 s, so the lines are steady and do not jump with each puff. Angles `θ_up` / `θ_dn` from the polar at
  that TWS (`ai.md` §3.1).
- Each layline is the ray from the mark backwards along the course over ground a boat would make on that tack:
  `COG_t = compass(V_t·dir(ψ_t) + current)` with `ψ_t = TWD ± θ` and the current at the mark (`wind.md` §7); the
  boat model has no leeway (`boat.md` §6.4), so without current it is simply `ψ_t`.
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

In the 3-D view: an arrow on the mark on the rounding side, the zone circle (radius `zone_lengths·L` of the viewed
boat plus the mark's radius, measured from the mark: `3·L` in a fleet race unless the course says otherwise, `2·L`
in a match race, `rules.md` §7.1; drawn at the finishing line's ends too on the last leg) drawn on the water when she
is within `6·L`, and a bouncing marker over the next mark when it is more than 500 m away.
The mark tag (§16.4) carries the name, distance, ETA and bearing on the mark itself; the distance to the layline is
shown at the tack point on the water (the point along the current COG where she meets the other tack's layline).

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
- **Signal banner**: "Preparatory signal, I flag: over in the last minute means round an end" etc. for 3 s at each
  signal.

### 9.2 Start line panel (from the warning signal until the boat starts)

| Field | Definition |
| --- | --- |
| Distance to line | `s(bow)` (`race.md` §3.3): negative behind the line, positive over, when the bow's `u` is within [0, 1]; otherwise the distance to the nearer end, labelled "(end)" |
| Time to line | the time to reach the line segment along the current COG at the current SOG: `t_line = distance along COG to the segment / SOG`; `--` if the COG ray misses the segment or SOG < 0.5 kn |
| Time to burn | `(−t) − t_line`: positive = early by that much (burn it), negative = late |
| Bias | `β = wrap_pi(compass(n̂) − TWD)` from the viewed boat's clean wind smoothed 10 s (`ai.md` §5.2 formula), shown as the favoured end and its advantage: `PIN +7° · 30 m` (the upwind distance `|Δu|` by which that end is ahead) |
| Over | in the last minute and after the gun until started: `OVER` in red when the boat is over under the active flag rule (P: in the line band; I: course side incl. extensions; Z/U/black: in the triangle), with the consequence ("I flag: round an end") |
| OCS | after the gun, when the boat is OCS: `OCS: return` with the specific instruction (`race.md` §4.3), until returned |

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
| I am the giver, state `Breach` | `KEEP CLEAR: <rule text>` with the other boat's name and a pointer to her | red |
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
- **Turn progress**: a ring filling with the tracker's `|Θ|` (`rules.md` §9.3) to 360° (every penalty is one turn),
  with a tack tick and a gybe tick that light when done; state text: `Turn: 210°`, `Turn reset: paused`, and in a
  match race only `Not counted: inside the zone` (a fleet-race turn counts anywhere). With nothing turning yet:
  `Sail clear and turn: one tack and one gybe`.
- **Deadline**: `rules.md` §9.4 countdown `1:32` to the time the turn must be **completed** (120 s after the
  incident), red below 30 s (a turn takes 10 to 25 s); hidden when there is no deadline (match race single penalty).
- **Disqualification warning**: `One more penalty = disqualification` when pending = `dsq_pending − 1` or
  received = `dsq_total − 1`.
- **Finish blocked**: `Take your penalty before finishing` on a `FinishBlocked` event.
- **Turn on the water**: while the panel shows a pending or running turn, a ring around the viewed boat (radius
  `1.5·L`) fills with the same `|Θ|`, with a head at the filled end. Drawn in the chase and aerial cameras only, never
  onboard (the boat is underneath the camera there) nor in the free camera; the panel carries it in every camera.

### 12.2 Messages

On a `Penalty` event for the viewed boat: a 4 s banner `PENALTY: <rule text> (<other boat>)` and a sound; for other
boats, a fleet feed line `<boat> penalised, rule 10 (<other>)`. `PenaltyServed`: `Penalty done` banner 2 s.
`PenaltyLate`: no banner of its own; the `Disqualified` event that follows it shows the full-width banner with the
reason, `DISQUALIFIED: penalty not taken within 2 minutes`.

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
| 21.1 | Returning starter keeps clear |
| 21.2 | Boat taking a penalty keeps clear |
| 31 | Touched a mark |
| 44.2-late | Penalty not taken within 2 minutes |

| C-prep | Not outside the line at the preparatory signal |
| C-entry | Did not enter through the line in time |
| SI-boundary | Outside the race area |
| 29.1 / 30.1 / 30.2 / 30.3 / 30.4 | Over early (P / I / Z / U / black flag) |

The in-game rules help explains each rule at length in our own words, with a diagram, and lists Windmark's two
penalty departures from the rules (one 360° turn, completed within 120 s, `rules.md` intro) and what the automatic
umpire does not judge (`rules.md` §15). Rule numbers are those of the 2025-2028 rules.

## 13. Event feed and results

- **Feed** (bottom corner, 6 lines, 8 s each): signals, starts (`12 boats started, 2 OCS`), roundings of the first
  three boats, penalties, finishes, joins and leaves, retirements.
- **Results screen** (`menus.md` §5): place, sail number and boat, skipper, AI badge, finish time, gap to winner,
  code, points; series standings if a series. Projected AI finishes are marked `proj.`. Before `RaceClosed`
  (`race.md` §9) it is the live **finishing** table, which fills in as boats finish. Where there is no results
  screen (a front end without the menus, tests), the HUD draws the same rows as its own centred table
  (`Provisional results` until the close, then `Results`); the sail scene turns that table off and uses the screen.

### 13.1 Finish card

The finish beat of the player's boat (the boat the HUD is the player's own, not a spectated one), in the alert lane
where the countdown was (§16.5 in portrait):

- On her `Finished` event: the finish horn (`audio.md`, `race.horn_finish`), and the card: the caption `FINISHED`
  (15 px, mist), the place as a caps ordinal at the countdown's size (128 px, `3RD`; `mark` yellow for a win, paper
  otherwise) with the gap to the winner beside it on the same baseline (48 px, mist, `+0:42`; nothing for the
  winner), and the finish time under them (20 px, `0:23:32.35`). A finish that scores no place (an `OCS` boat
  released onto the course, `race.md` §4.3) shows the code instead of the place. The line of the card,
  `Finished 3rd · 0:23:32.35 · +0:42`, is what the old finish banner said; there is no banner as well.
- On her retirement (`Retired`, the pause menu's Retire): `RET` with the caption `RETIRED` and no time.
- When the race closes with her still racing (the finishing window, `race.md` §7.3; `DNF`): `DNF`, caption
  `RACE CLOSED`.
- A disqualification keeps its full-width banner of §12.2 and has no card; an abandoned race keeps its banner.
- **Time**: 5 s of race time (it slows with the capture rate and stops in a pause), fading in over 0.3 s and out
  over the last 0.8 s. The rest of the HUD stays as it is.

### 13.2 Race end

The player's race is **over** at her finish, her retirement, her disqualification (any ghost reason), or when the
race closes or is abandoned with her still racing. From then the boat sails on by herself offline (`race.md` §6.2)
and the camera eases into the finish view (`cameras.md` §9.1). 5 s of race time after the race is over (as the
finish card ends) the results screen fades in (`menus.md` §5) and the HUD hides under it; it does not come back in
this session (Race again starts a new one).

### 13.3 Race summary

What the results screen says about the player's own race, recorded by the race HUD from the readers and events it
already has; nothing else is shown, and an item without data is left out:

| Item | Recorded from | Shown as |
| --- | --- | --- |
| Start | her `Started` event: `t_start` after the gun; an `OCS` event before it | `+0:04 after the gun`; `OCS, returned and started +0:31` |
| Roundings | her `Rounded` events: the step's label (with the lap on a course of more laps), her place in the order of that step's splits, the gap to the first | `Windward 2` `4th  ·  +0:18`, one line per rounding |
| Places | her place at the first rounding and her final place (or projected rank) | `+2 since the first mark`, `-1 since the first mark`, `Held 3rd since the first mark` |
| Penalties | her `Penalty` events (rule, other boat), `PenaltyServed`, `PenaltyLate`, `Disqualified` (reason) | `Rule 10: Port tack keeps clear of starboard (Nora), done`; none: `No penalties` |
| Top speed | the largest boat speed through the water while racing (started, not finished or a ghost) | `7.4 kn` (§1 speed format) |
| Distance sailed | the sum of her ground track over the ticks from the start signal to her finish or race end | `3.21 nm` (§1 distance format) |

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

Online lobbies may force a maximum preset (e.g. ranked "Minimal"). The assist preset is independent of the instrument
density of §16.1: an item shows only when both allow it.

## 15. Tests

- For a scripted boat state, `HudValues` matches hand-computed values for every field of §2–§7 and §9.2 (within
  the display rounding).
- Through a scripted tack the shown TWA equals the core's `twa` every tick (no lag, no overshoot) and its tack letter
  changes on the tick the sign of `twa` does.
- VMG on a run is positive when sailing towards the leeward mark; VMC is negative when sailing away from the mark.
- Layline test: a boat placed on the computed starboard layline, sailing at `θ_up` with no current, reaches the mark
  within 0.5 L in a steady wind (headless sim).
- Radar colours follow the pair records for the port–starboard, windward–leeward and mark-room scenarios of
  `rules.md` §13.
- Time to burn: a boat 100 m behind the line at 5 m/s heading straight at it, 30 s before the gun, shows `t_line` 20 s
  and `+10 s` to burn.
- Density (§16.1): for each level and phase the table's items are shown and no others; the density key cycles
  Glance, Race, Data, Glance and the choice survives a restart; the defaults are Race at 1920 x 1080 and Glance at
  1280 x 800.
- Name tags (§16.4): a boat at 45 m has a tag, one at 55 m has none until it is selected; the penalty ring is drawn in
  the chase and aerial cameras and not onboard.
- Selecting (§16.4.1): a click on a far boat's hull or rig selects her and draws her bracket and tag, a click on the
  water or on her again clears, a click on another boat replaces her, a press dragged 20 px picks nothing
  (`controls.md` §8 test 10), Esc clears it without pausing, `boat_select` goes nearest first, then the next, then
  none; the radar marks her.
- Boat card (§16.7): for a scripted race state every row matches the boat states, race and rules records it comes
  from; at 1280 x 800 and 1080 x 1920 for UI scales 80 % to 130 % at every density, with a boat selected, every
  text is on screen and no two blocks overlap.
- Tack point (§16.4): the point and its `TACK IN` label are drawn, and no line runs from the boat to it.
- Every text of the HUD fits its block at 1280 x 800 for UI scales 80 % to 130 %.
- Portrait (§16.5): at 1080 x 1920 for UI scales 80 % to 130 %, in the pre-start, beat and penalty states at every
  density, every text is on screen and no two texts overlap, and no two blocks' drawn areas overlap (world tags
  aside); the default density is Glance; the radar is compact.
- Race end (§13.1 to §13.3): on the player's finish the card shows the place, the gap and the time, fades in and
  out and is gone after 5 s of race time; RET and DNF get their card, DSQ its banner; the race is over at each of
  them; the finishing rows fill in as boats finish before the close and are the core's results after it; the
  summary has the start, every rounding with its place, the places gained, each penalty with its rule text, the
  top speed and the distance sailed of a scripted race.
- Capture rate note (§16.6): each `capture_slow` press shows the note for the new rate, also with the HUD hidden;
  it is gone 1.5 s of frames later and fades over the last 0.4 s; `capture_pause` shows nothing.

## 16. Presentation

What the player can choose to see and what the colours mean; the layout, sizes and motion follow
`docs/design/hud_direction.md`. Player-facing strings contain no em dashes.

### 16.1 Instrument density

Three levels, **Glance**, **Race** and **Data**, cycled in that order by the `hud_density` action (`controls.md`
§2). Density decides how many instrument values show. It never hides a contextual item (countdown, OVER and OCS,
the rules line, the penalty panel, banners, protest and hail prompts) or anything in the world (start line, mark
tag, laylines, tack point, zone circle, rounding arrow, name tags, edge pointers, penalty turn) or the selected
boat's card (§16.7). The radar, the helm strip and, under manual trim, the trim gauges show at every level.

| Phase | Glance | Race | Data |
| --- | --- | --- | --- |
| Pre-start (race sequence, not started) | boat speed, TWA dial; start block: countdown, time to burn with its late/early bar, the flag rule in one line; no race bug, no wind page | + polar % with its meter, heading, target speed; full start block (distance and time to line, burn, bias, flags); wind page; race bug (fleet); feed 3 lines | + VMG, AWA, SOG, COG, AWS, heel bar; race bug adds laps and legs; feed 6 lines |
| Beat or run | boat speed, TWA dial with the target ticks, VMG % with its meter; race bug: clock and rank | + heading, target angle and speed; wind page and shift meter; lap, leg and leg type; feed 3 lines | + VMG, AWA, SOG, COG, AWS, polar %, heel bar; leader gap, ahead and behind; feed 6 lines; sail hint |
| Reach | as a beat, with polar % as the cue and no target ticks; target is the target speed | as a beat | as a beat, with VMC in place of VMG |
| Rounding (within `6·L` of the next mark, and 6 s after a rounding) | boat speed, TWA dial | as the leg | as the leg |
| Penalty (panel shown) | boat speed, TWA dial | as the leg | as the leg |

- At Glance the radar is drawn at 72 % of its size without the range and orientation labels, the helm strip has no
  labels, and the feed shows only the viewed boat's own events.
- Free sailing (no race): the instrument page and the helm strip as in the table's beat row without the race items.
- **Defaults**: Race; Glance on the Steam Deck and on any screen under 900 px tall (after the UI scale). The player's
  last choice is kept in the settings file (per device, `menus.md` §3) and wins over the default.
- A change shows an `INSTRUMENTS · <LEVEL>` chip above the instrument page for 1.5 s; three small squares on the page
  show the level at all times.

### 16.2 Colour tokens

| Token | Value | Meaning |
| --- | --- | --- |
| `ink` | `#06121B` | scrims, glass pages (14 % to 44 %), chips (80 % to 90 %) |
| `paper` | `#F5F8FA` | every number, primary text; boats with no relation |
| `mist` | paper at 66 % | labels, units, secondary text |
| `hair` | paper at 42 % | hairlines, rings, ticks, dividers (at 45 % of `hair`) |
| `mark` | `#FFD23F` | the course and the viewed boat: next mark, zone circle, rounding arrow, own boat on the radar, the number to act on; the rule-17 line |
| `stbd` | `#27D17C` | starboard layline, tack letter S, lift, she keeps clear of me, right of way |
| `port` | `#FF4438` | port layline, tack letter P, header, I keep clear of her, OVER, OCS, breach, penalty |
| `owe` | `#FF8A1F` | I owe room; keep-clear warning |
| `have` | `#2FD8EE` | she owes me room; "You have mark-room" |
| `ghost` | paper at 35 % | finished and cleared, retired, disqualified, disconnected |

These are the colours of §6, §8 and §11 (red = `port`, green = `stbd`, orange = `owe`, cyan = `have`, white =
`paper`, yellow = `mark`). Colour is never the only signal: each coloured state also has a word or a letter.

#### 16.2.1 Colour-blind palettes

The settings' colour palette (`controls.md` §6, `menus.md` §3) swaps the four rules colours; `ink`, `paper`,
`mist`, `hair`, `mark` and `ghost` never change, and neither do the words and letters that go with every colour.

| Palette | `stbd` | `port` | `owe` | `have` |
| --- | --- | --- | --- | --- |
| Standard (default) | `#27D17C` | `#FF4438` | `#FF8A1F` | `#2FD8EE` |
| Deuteranopia | `#4D8EFF` | `#FF7A66` | `#FF4D9F` | `#19E0FF` |
| Protanopia | `#33CCFF` | `#FF974D` | `#FF338D` | `#A480FF` |
| Tritanopia | `#80FF81` | `#FF667C` | `#E64DFF` | `#4D94FF` |

How they were chosen: the six colours that must tell apart (`paper`, `mark` and the four rules colours) were run
through the full-severity colour vision deficiency simulation of Machado, Oliveira and Fernandes (2009) and compared
in CIELAB. With the standard palette the closest pair is 15 ΔE apart for deuteranopia (`mark` and `owe`), 21 for
protanopia and 11 for tritanopia (`stbd` and `have`); each palette raises its own deficiency's closest pair to 32,
33 and 30, keeps at least 39 ΔE between any two for normal vision, and keeps every colour at 5.5:1 or more against
`ink`. For the red-green palettes starboard turns blue and port a warm orange-red; tritanopia keeps a green and a
red. The palette applies to the HUD, the radar and the course drawn on the water (laylines, the start line's
colours).

#### 16.2.2 UI scale

The settings' **UI scale** (`menus.md` §3) is 80 % to 130 % in 5 % steps, default 100 %: the root window's
content scale, so the HUD and the menus grow and shrink together (the 3D view is not affected; its resolution is
the render scale). The HUD's design px follow the logical size after it (§16.5, `hud_direction.md` §5), so every
text fits its block at every step (§15); 11 px stays the floor for any text.

### 16.3 Instrument pages

The instrument values of a corner sit on one page: ink glass from 14 % at the top to 44 % at the bottom, a hairline
along the top edge and hairline dividers between the cells; no blur, no corner ticks, no rounded corners. Each cell
has its label top left, the unit top right and the value right-aligned at the bottom. Numbers use tabular figures.
The two analogue parts are the TWA dial (bow up, the close-hauled sectors in `port` and `stbd`, the target angle
ticks in `mark` on a beat or run, the true wind pointer; Data adds the apparent wind pointer) and, at Data, the heel
bar (centre zero, ±30°). Numbers keep the 4 Hz refresh of §1; dial, bars and meters move every frame.

### 16.4 World tags

- **Mark tag**: on the next mark (§7): name, distance, ETA, bearing and relative bearing. Off screen it becomes an
  edge pointer at the screen edge towards the mark.
- **Tack point**: on a beat or run with the layline distance of §6 shown, a point on the water where the current COG
  meets the other tack's layline (a ring in the colour of the tack she will sail after it), with
  `TACK IN <distance> <time>` on a beat and `GYBE IN <distance> <time>` on a run (the turn onto the other tack
  downwind is a gybe), or `OVERSTOOD <distance>` at the boat. Only the point and its label: no line is drawn from
  the boat to it (the owner's call: the forward path line was clutter in front of the bow).
- **Name tags**: another boat's name over her mast when she is within 50 m of the viewed boat, or when the player
  has selected her (§16.4.1). The tag takes the radar colour of §8 (solid chip when there is a relation, paper on
  ink otherwise) and pulses as the radar icon does. A selected boat off screen gets an edge pointer with her name
  and distance. `boat_names` turns all name tags off and on (the selected boat's included; her bracket and card
  stay).
- **Penalty turn**: §12.1, chase and aerial cameras only.
- `world_tags` (`controls.md` §7) hides and shows all of the above at once, with the course's on-water guides;
  it is independent of `hud_hide`.

#### 16.4.1 Selecting a boat

One other boat at a time can be selected, to keep her tag up whatever the distance and to read her card (§16.7).

- **Pointer** (`boat_pick`, `controls.md` §2): a click or a tap that does not move more than 8 px between press and
  release picks the boat under it. The hit area of a boat is the screen triangle from her bow and stern at the
  waterline to her masthead, grown by 40 design px (`k` of §16.2.2), so a small far boat is still easy to hit;
  when several are hit the one nearest that area wins, and between boats it covers, the one nearest the camera.
  A pick on a boat selects her (replacing any other); on the selected boat again, or on open water, it clears the
  selection. A press that moves further is a camera drag (`controls.md` §3) and never selects or clears.
- **Cycle** (`boat_select`): the boats other than the viewed one ordered by distance from the viewed boat at the
  press, nearest first; each press selects the next one after the selected boat, and after the farthest, none.
- **Clear**: Esc (`pause_menu`) with a boat selected clears the selection and does nothing else; the next Esc opens
  the pause menu as usual. Selecting the viewed boat (spectating) is not possible; when the viewed boat becomes the
  selected one, or she leaves the race's boats, the selection clears.
- **Marking**: the selected boat gets a bracket on the hull: four hairline corners (1.5 px, `hair` width rules)
  round the screen box of her hull and rig (at least 16 px square), 6 px outside it, each corner a quarter of the side and at most 14 px,
  in her tag colour (paper with no relation). No glow, no fill. On the radar (§8) her icon gets the same four
  corners in paper, 9 px from its centre.
- The pointer picks only in the 3D view: not through the pause menu, the look panel (§18) or the chat line, and not
  while the simulation is paused with the menu open.

### 16.5 Portrait layout (capture)

For native 9:16 clips (Reels, Shorts): the HUD takes this layout on any screen taller than it is wide, so the
portrait capture preset of `menus.md` §3 (a 1080 x 1920 window) and a window opened at that shape from the command
line (`--resolution 1080x1920`, also with Movie Maker's `--write-movie`) both get it. The rule text is the point of
these clips, so the alert lane is at the top and large; the instruments are compact at the bottom.

- **Scale and margins**: the design's px at 1080 x 1920, `k = width / 1080` (logical px, after the UI scale).
  Margins 48 px left and right, 140 px top, 200 px bottom: the top margin keeps the alert lane under the apps' title
  bar, the bottom margin keeps the instruments above most of their caption and button strip.
- **Top row**: the race bug top left (with its lap and gap lines), the wind page top right with the shift chip under
  it.
- **Alert lane**, centred under the taller of the two (bug with its lines, wind page with its chip), 16 px below:
  before the start the countdown, flags and start numbers; in the race the penalty panel, then the rules line, the
  banners and the prompts (stacked as in landscape). The lane is drawn up to 1.15 times larger than the rest, as
  large as its 900 px fits between the margins (1.09 at 1080 wide), so the rule text reads on a phone.
- **Bottom row**: the instrument page bottom left, the radar bottom right, always compact (72 %, no range and
  orientation labels) so the Data page fits beside it.
- **Above the bottom row**: the helm strip centred 12 px above the taller of page and radar, the sail hint and the
  controls' messages over it, the `INSTRUMENTS · <LEVEL>` chip over the page (left of the helm strip); the event
  feed right-aligned over the helm notes.
- **Density**: the default is Glance (the player's stored choice still wins, §16.1); the density key works as in
  landscape.
- **Selected boat card** (§16.7): left, over the helm notes, beside the feed; the edge pointers' box ends 56 px
  above it while it shows.
- **Tables** (ranking, results): centred and scaled down to fit between the margins.
- **World tags**: as in landscape, kept inside the margins; the mark tag also stays under the alert lane (its
  leader still points at the mark), so it never covers the rule text, and the edge pointers run along a box from
  under the alert lane to over the feed and helm notes; without a camera the mark tag docks under the alert lane,
  left.
- Nothing else changes: the same blocks, texts, colours and rules for what shows.
- Left as is until it is checked on a real clip: the radar bottom right (it may sit under an app's buttons).

### 16.6 Capture rate note

When `capture_slow` changes the simulation rate (`controls.md` §7), a small note says the new rate: `Slow motion
x0.5`, `Slow motion x0.25` or `Normal speed`. It is the only capture feedback; the clean pause shows nothing.

- **Look**: one line, 16 px semibold paper text on an ink chip (86 %), centred horizontally, 24 px under the top
  margin (`k` and margins of §16.5 in portrait). Small enough to leave the frame usable if it is caught.
- **Time**: shown for 1.5 s of real frame time (it does not slow down with the rate and runs in a clean pause), fully
  opaque until its last 0.4 s, then fading linearly to nothing. A new press restarts it with the new text. After
  it nothing stays on screen.
- **Hidden HUD**: it shows also with `hud_hide` and `world_tags` off, since that is how clips are captured; it
  belongs to the scene's overlay layer, not to the HUD blocks.
- A restart (`reset_boat`, the pause menu) clears it.

### 16.7 Selected boat card

While a boat is selected (§16.4.1) a small card says who she is and how she stands against the viewed boat. It
uses only what the HUD already reads (the race and rules records, the boat states, the liveries); a field with no
value is left out, never guessed. Numbers refresh at the 4 Hz of §1 with the rest.

| Row | Content | Source |
| --- | --- | --- |
| Header | sail number and skipper in caps (`SLO 7 · AI EXPERT`; a human skipper is `PLAYER`, or the skipper's name when the race has one), then the boat name large; on the right, after the start, `PLACE` over her place `3 / 6` (her finishing place once finished) | livery (sail number, boat name), the race's skipper and AI level, the shown ranking order of §10 |
| Cells | `DIST` her distance from the viewed boat; `BRG` the compass bearing to her with the relative bearing to the bow (`045 · 35° R`); `SPEED` her boat speed in knots; `HDG` her heading with her tack letter in the tack colour | the boat states of the tick, formats of §1 |
| Course | `Next <mark>` (the label of her next step: a mark's label, `Gate`, `Finish`; `Start` before she starts), or her status (`Finished`, `RET`, `DSQ`), with `OCS · ` before it while she must return; after a ` · `, how far she is ahead of or behind the viewed boat along the course: `45 m behind you`, `120 m ahead of you` (the difference of the two course distances to go `D` of `race.md` §8.2), only while both are racing on the course | race record |
| Rules | while the pair record with the viewed boat has a relation (the radar colour of §8): one line in that colour, `YOU KEEP CLEAR`, `SHE KEEPS CLEAR`, `YOU GIVE ROOM` or `SHE GIVES YOU ROOM` (room wins over keep-clear, as on the radar), with `· BREACH` when the state is Breach; under it the rule's text of §12.3 with its number (`Port tack keeps clear of starboard (10)`). Not with the Minimal assist (§14), as the radar colours | pair record (`rules.md` §11.1) |
| Penalty | `1 PENALTY OWED` (or `2 PENALTIES OWED`) in `port` while she has penalties pending, `TURNING` added while she is taking one | her rules record |

- **Look**: an ink chip at 86 %, 340 design px wide, a hairline along the top edge and a 4 px bar down the left
  side in her tag colour (`hair` with no relation); labels in `mist`, values in `paper`, numbers tabular. Text no
  smaller than the 11 px floor (§16.2.2): a line too long for the card is set smaller down to the floor, then cut
  with an ellipsis.
- **Place**: landscape, left, its bottom 48 px above the instrument page (clear of the density chip) and never
  higher than 16 px under the race bug; portrait (§16.5), left, its bottom 8 px over the helm notes, beside the
  feed. It is a panel, not a world tag: `world_tags` leaves it, `hud_hide` hides it.
- **Density**: it shows the same at every level (§16.1: density never hides it); it only appears on the player's
  request.
- The card goes when the selection clears and in the results. Without a race (free sailing) it has the header
  (without the place) and the cells only.

## 17. Frame-time overlay (development)

A measuring tool, not part of the race HUD: a small panel top left over everything, toggled with Shift+F9
(`controls.md` §3 notes) or the look panel's row (§18), or shown from the start with `--perf`, and a per-second CSV log (`--perf-log=PATH`) so a
windowed run can be measured without reading the screen. It measures only while shown or logging. Off by default,
and not saved.

- **Frame**: frames per second, the frame time (mean, and the 1 % worst: the 99th percentile over the last 5 s),
  the CPU time of the frame's process step, the render thread's CPU time, the GPU time of the main view (Godot's
  viewport render time measurement, `RenderingServer.viewport_get_measured_render_time_gpu`) and of the other
  viewports (the wake normal buffer), draw calls, primitives and objects drawn.
- **Set-up**: the render scale (`menus.md` §3) with the 3D and window sizes and the upscaler, the quality tier,
  the boat count, the renderer and driver, vsync and the frame rate limit, the camera mode.
- **Sections**: the game's own per-frame work in milliseconds per frame, timed around the calls: `input` (devices
  and controls), `sim` (the 50 ms ticks: the simulation step and the sail snapshots), `hud` (`Hud.tick` and
  `Hud.frame`), `audio`, `sails` (the per-vertex sail shapes of every boat), `boats` (the boat nodes' poses, rudder,
  boom), `wakes` (the wake ribbons, bow waves and spray, and the boat shadows drawn on the water), `sea` (the Sea's per-frame uniforms), `course` (the course
  view), `camera`.
- **Log**: a header line, then one line per second of the means over that second (the frame time's maximum
  too, and the 1 % worst over the last 5 s); `--perf-seconds=N` quits after N seconds. The GPU times are 0 where the
  driver does not measure (headless).

## 18. Look panel (development)

A developer tool for judging the picture in one session instead of restarting with flags: F9 in the race and free
sail scene opens a side column on the right, under the top margin, over the HUD and under the pause menu (and the
frame-time overlay). Not part of the player's settings, nothing saved; available in every build for now. Every row
changes the look live through the same function as its startup flag (`DevLook`), so the flags and the panel stay
the same:

| Row | Values | Flag | Applies |
| --- | --- | --- | --- |
| Anti-aliasing | Off, FXAA, SMAA | `--aa=` | live (root viewport) |
| Grade and vignette | On, Off | `--look=` | live; off also drops SSAO and depth of field |
| SSAO | Tier, Off, On | `--ssao=on\|off\|tier` | live (environment) |
| Clip camera DOF | On, Off | `--dof=` | live (long lens and mark shots, tiers M and H) |
| Light | Clear, Fair, Hazy, Late | `--sky=` | live (sky rig and its grade) |
| Quality tier | L, M, H | `--quality=` | live: sea grid and water shader, wakes, drawn shadows, sun shadows, glow, SSAO, reflections; a short hitch while the shaders compile |
| Haze | x0.0 to x1.5 of the preset's haze, step 0.1 | `--haze=` | live; kept when the preset changes |
| Reset haze | action | | back to x1.0 |
| Whitecaps | On, Off | `--caps=` | live |
| Drawn wind (sea) | Sim, 8 to 25 kn | `--drawn-wind=` | live: the wind the water draws (whitecaps, puffs); waves and boats keep the world's |
| Wind for restart | 4 to 30 kn | `--wind=` | the value for the next row |
| Restart with wind | action | | restart only: the core takes its wind when the world is made, so the race or free sail starts again with that wind, every other setting kept (a rules scenario keeps its file's wind) |
| Chase breathing | On, Off | `--breathing=` | live: off is the plain follow (one heading lag, no bank, trail or lean) |
| Drawn boat shadows | On, Off | `--no-drawn-shadows` | live (tiers L and M) |
| Boat sun shadows | On, Off | `--no-boat-shadows` | live |
| Render scale | Setting, 50, 67, 75, 85, 100 % | `--render-scale=` | live (root viewport) |
| Frame-time overlay | On, Off | `--perf` | live (§17) |

A readout line under the title shows the frame rate, the mean frame time over the last 0.25 s, the tier and the
3D scale. The selected row's line at the bottom says how it applies.

- **Keys** while the panel has the focus: Up and Down pick a row, Left and Right change it, Enter or Space toggles a
  row or runs an action, Esc gives the keys back to the boat (the panel stays up), F9 closes it. F9 on an open
  panel without the focus takes the focus again. **Mouse**: a click on a row steps it forward (or runs it), a right
  click steps back, the wheel either way; a click on the panel takes the focus, a click outside gives it back.
- **Input**: while the panel has the focus (and in the frame that gave it back, so that Esc does not also open the
  pause menu) the scene hands the boat, the cameras and the scene keys no buttons, as the chat line does
  (`controls.md` §7); the simulation keeps running. With the pause menu or the chat open the panel takes no input.
- **Look**: HUD fonts and colours (`HudStyle`), an ink panel at 86 %, names in mist, values in paper, the selected
  row in the mark colour; scaled like the HUD.
