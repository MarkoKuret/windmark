# HUD semantics

What every in-race indicator means, how its value is computed, how it is rounded, and when it is shown.
This file is the contract for the numbers and states behind them, so every front end (desktop, Steam Deck, a future
browser client) shows the same values, and (§16) for what the player chooses to see: the instrument density levels,
the colour meanings, the world tags and the next-mark arrow. The exact layout and art are the
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
- **Drawing**: each shown block builds its drawing (its primitives) whenever what it reads may have changed (a
  tick, the text refresh, a player command, a setting, a selection, the camera coming or going) and is redrawn only
  when it differs from what it shows; the blocks that follow the camera or the frame time (the world tags, the
  radar, the course map, the next-mark arrow, the finish card while it fades) build every frame. A block that shows
  the same is not drawn again. The HUD's tick work (`Hud.tick`) may
  run one frame after the tick that it reads (`controls.md` §1.1: the tick's work is spread over the frames of a tick).
- **Formats**:

| Quantity | Format |
| --- | --- |
| speed | knots, 1 decimal (`7.4`); below 0.05 shows `0.0` |
| angle | integer degrees with the degree sign; headings and bearings `000°`–`359°` (3 digits); signed angles with a side letter (`42° P`, `38° S`) |
| distance | < 200 m: metres, integer (`85 m`); 200 m–0.2 nm: metres rounded to 5 m; ≥ 0.2 nm: nautical miles, 2 decimals (`0.43 nm`) |
| time | race clock and gaps `m:ss`, a gap signed (`+0:23`, the time to burn too: `+0:10`); countdown `m:ss`, with tenths in the last 10 s (`0:07.4`); finish times `h:mm:ss.ss`. No time is shown in bare seconds: an `S` after a number is always starboard |
| percent | integer with the `%` sign (`60 %`; the helm with its side letter, `35 % S`) |

- Rounding is to nearest (half away from zero). Truncation is never used for display.
- **One side convention**: the side letters are `P` (port) and `S` (starboard) everywhere: TWA, AWA, heel, the
  helm and the relative bearing of the next mark (`35° P`: 35° to port of the bow); never `L` and `R`.
- **Units**: every number carries its unit where its label does not say it, in a cell's unit corner (`KN`) or in
  the value itself (the degree sign, `%`, `m`, `nm`); times in `m:ss` need none.

## 2. Boat instruments

| Indicator | Definition |
| --- | --- |
| Boat speed (BSP) | the boat's `v_filt` (`boat.md` §5.10: speed through the water along the heading, filtered by the core) |
| Speed over ground (SOG) | length of the boat's filtered ground velocity (`sog_filt_x`, `sog_filt_y`) |
| Heading (HDG) | ψ, compass |
| Course over ground (COG) | `compass(sog_filt_x, sog_filt_y)` (shown only when SOG > 0.3 kn) |
| Heel | `|φ|`, degrees, with the letter of the side that is down (φ > 0: starboard down, `conventions.md` §3) |
| Rudder | helm `h` as a bar, −1 … +1 (positive turns the bow to starboard), with a second mark at `h_cmd`; as text (the helm strip at Data) the size of `h` in percent with the side the bow turns to (`35 % S`, `0 %` amidships) |
| Sail | the front sail that is up (or "Main only"), shown as the underlined slot of the sail strip (§5.3); the one being hoisted is the hoist cue's (§5.1), not this row's |

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
| Shadow | `d = 1 − wind_speed / wind_speed_clean` (`boat.md` §2, the boat's environment of `wind_shadow.md` §5) as a percentage, shown only when ≥ 3 % (`Bad air −8 %`): a line of the helm notes (§5.1), at every density, the only cue of another boat's shadow |

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
  - Shown as `LIFT 6°` (green) or `HEADER 4°` (red) when `|Δ| ≥ 2°`, else `--`. Hidden on reaches. On the HUD it
    is a chip in the heading cell of the instrument page (§16.3), at Race and Data.

### 3.3 Wind shadow view (later)

Not built yet, and no key is bound to it (`controls.md` §2): a later assist would draw each boat's blanket and
backwind outlines (`wind_shadow.md` §7 `shadow_zones`, which the core does not offer yet) on the water and in the
radar, shaded by the loss `l`, darker where `l ≥ d_bad` (`ai.md` §8), the own boat's fainter. Until then the
`Bad air` line of §3.1 is the shadow cue.

## 4. Performance

With `θ_up`, `V_up`, `θ_dn`, `V_dn` the polar VMG optima of the boat's class at the felt TWS (`ai.md` §3.1) and
`V_pol` the boat's `polar_speed` output (`boat.md` §5.4: the polar of the active config at the present `tws`, `twa`).
A human boat's `performance_scale` is 1.

| Indicator | Definition |
| --- | --- |
| VMG | on a beat: the boat's `vmg` (`v·cos(twa)`, `boat.md` §5.10); on a run: `−vmg`; so the display is positive for progress along the wind towards the mark. On a reach VMG is replaced by VMC. |
| VMC | velocity made good on course: `dot((sog_filt_x, sog_filt_y), unit(R − c))`, R = the next step's target point (`race.md` §5; gate: the chosen buoy, see §7) |
| VMG angles | `θ_up` and `θ_dn` at the felt TWS, always (racing or not): the angles the TWA dial marks (§16.3) |
| Angle reference | the VMG angle the TWA pointer is coloured against: on a beat `θ_up`, on a run `θ_dn`, on a reach none; before the start, free sailing and after the finish the nearer half: `θ_up` while `|twa| < (θ_up + θ_dn) / 2`, else `θ_dn` |
| Angle error | `Δ = ||twa| − reference|`, degrees |
| Sail hint | when the best config for the present TWA and TWS (`ai.md` §3.1) is ≥ 3 % faster than the current one for 5 s: "Code zero +6 %" (the gain in polar speed) |

The leg type is `ai.md` §4.1 (beat / run / reach). **No target speed is shown anywhere** (the owner's call,
2026-10-16: the speed against a target speed was dropped, as the VMG and polar percentages were before): the player
sails by the angle. The HUD shows the boat speed plain and, on the TWA dial, the VMG angles with the true wind
pointer coloured by the angle error (§16.3). No indicator is a percentage of a target.

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
- While a sail is in `prepare_hoist`, `hoisting`, `prepare_drop` or `dropping` its gauge is greyed and shows no
  tell-tale (the hoist cue says what is going on).

### 5.1 Hoist cue

While a front sail is being hoisted (`prepare_hoist` or `hoisting`, a change included) one cue says so, at every
density: `HOISTING <SAIL>` (the sail's name in caps, 16 design px semibold, `paper`) with a thin progress bar under
it (3 design px, the text's width, `hair` track, `mark` fill at the hoist's progress), as the first line of the helm
notes over the helm strip. It is the only text about the hoist: the sail strip (§5.3) marks the sail up, the
greyed gauges have no tell-tale, and the sail hint is not shown while it runs (the controls' message line stays,
under it). Before this the strip's sail value grew to `JIB, HOISTING SPINNAKER 45 %`, which ran into the sheet
value centred in the same row, while the greyed gauges kept their tell-tales.

### 5.2 Sail state

One word for how the sails are working, so a player on the defaults (auto trim on, which hides the gauges, Standard,
Race) still hears about a luff, a stall or a stop. The first that applies:

| Word | When | Colour |
| --- | --- | --- |
| `LET FLY` | the boat's `let_fly` command is on (the player's own command of the frame, §2) | `port` |
| `IN IRONS` | inside the no-go zone (the boat's `polar_speed` ≤ 0, `boat.md` §7.4) with boat speed under 1 kn, for 1 s | `port` |
| `LUFFING` | the driving sail (the front sail that is up, else the main, `boat.md` §5.4) has the tell-tale "Luffing" of §5 (`e > 1.0` or `luff_shiver > 0.5`), auto trim or not | `mark` |
| `STALLED` | the driving sail has the tell-tale "Stalled" (`e < −1.0`) | `mark` |

Otherwise nothing (sailing well needs no word), and nothing for a driving sail being hoisted or dropped (§5.1).
With auto trim the trim error stays near 0, so `LUFFING` then means the sails cannot be trimmed for the course: a
kite carried too close to the wind, a sail on the wind line. A tack carries way through the no-go zone and shows
no `IN IRONS`.

- **Where**: in the helm strip, 16 design px semibold caps: with auto trim centred in the trim gauges' row (the
  gauges are hidden then); with manual trim centred in the strip's text row, in the sheet value's place (the sheet
  bar still shows the sheet), so it never covers a gauge.
- **When**: at every density (a contextual item, §16.1) and assist preset; hidden with the strip (course map,
  `hud_hide`).

### 5.3 Sail strip

The front sails of the class in slot order (`controls.md` §5.4), one row under the helm strip's rudder bar, so the
player sees which number key hoists which sail: each slot's key and name, `1 JIB   2 CODE ZERO   3 SPINNAKER`
(13 design px caps, tracked, 22 design px apart, centred on the strip; smaller down to the 11 px floor when it
does not fit), the key as the player's bindings name it (`controls.md` §3 Prompts).

- **The sail up** in `paper` with a 2 px `paper` underline; the others in `label`; the sails of a running change
  (going up or coming down) in `paper`. With no front sail up ("Main only") no slot is underlined. The strip
  replaces the sail value the helm strip's text row had.
- **Gamepad** (the device used last): the slots show their names without keys (the pad has no sail keys); the
  slot the `sail_prev` and `sail_next` highlight is on gets the `sail_set` button before its name (`X SPINNAKER`)
  and a `mark` underline.
- **When**: at Race and Data always; at Glance (no labels there) for 3 s after a sail key, a sail step on the pad or
  a busy press; not for a class without front sails; hidden with the helm strip.
- **Busy flash**: a sail press that maps to nothing while a change runs (`controls.md` §5.4) flashes the running
  change for 1.2 s: the strip shows (at Glance too) and the slots of the change blink between `mark` and `paper`
  at 4 Hz, starting in `mark`.

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
- Lines refresh at 2 Hz and are drawn on the water (as light dashed lines, `water_render.md` §6) and in the radar.

## 7. Next mark

For the next step (`race.md` §5):

| Field | Definition |
| --- | --- |
| Name | the label from the course (`courses.md` §8) or the mark id, with the lap and leg (`Lap 2/2 · Leg 3/5`) |
| Rounding side | arrow: left arrow = leave to port, right arrow = leave to starboard; a gate shows both buoys' arrows |
| Distance | buoy: distance from the bow to the buoy centre minus its radius; gate: to the nearer buoy, and the gate line; line (finish): to the nearest point of the segment |
| Bearing | compass bearing from the boat to the mark (gate: nearer buoy; line: nearest point), integer, and the relative bearing to the bow with its side letter (`35° P`, §1) |
| Leg | Beat / Run / Reach |
| ETA | beat or run: axis distance `D` of the leg (`race.md` §8.2) / VMG; reach: distance / VMC; `--:--` when the divisor is below 0.3 kn |

In the 3-D view: an arrow on the mark on the rounding side, the zone circle (radius `zone_lengths·L` of the viewed
boat plus the mark's radius, measured from the mark: `3·L` in a fleet race unless the course says otherwise, `2·L`
in a match race, `rules.md` §7.1; drawn at the finishing line's ends too on the last leg) drawn on the water when she
is within `6·L`, and a bouncing marker over the next mark when it is more than 500 m away.
The mark tag (§16.4) carries the name and distance on the mark itself (the ETA at Race, the bearing at Data,
§16.1); the distance to the layline is shown at the tack point on the water (the point along the current COG where
she meets the other tack's layline).

### 7.1 Next-mark arrow

Outside the chase camera the view no longer follows the bow, so the player loses where the mark is. In the
**onboard, aerial and free cameras** (`cameras.md` §3 to §5) one arrow shows the way to the next mark; in the chase
camera it is not drawn (the mark tag and its edge pointer do that job there).

- **When**: while the mark tag would show (racing, a next step after the start, not finished, `world_tags` on, a
  3-D camera) and the next mark is **off screen** (the mark tag is on it when it is on screen, so the two never
  show together), at every density and assist preset. Hidden with the course map open (§8.1) and with `hud_hide`.
- **Direction**: the bearing from the viewed boat to the next mark's point (§7: the nearer buoy of a gate, the
  nearest point of a line) in the camera's frame on the water: straight up on the screen is the camera's forward
  direction projected on the water (its up direction when it looks straight down), right is the camera's right.
  Updated every frame (§1).
- **Look**: a solid arrow head in `mark`, 30 design px long, no ring, no backing plate; to its right the mark's name
  in `mark` caps (13 design px, tracked) and under it the distance in the §1 format in `paper` (24 design px, the
  unit at 45 %), on an `ink` 70 % chip just large enough for them so they read over bright water.
- **Where**: landscape, centred over the helm notes (8 design px above them); portrait (§16.5), centred under the
  alert lane at the top of the edge pointers' box, with the mark tag kept under it.
- **With it**: outside the chase camera the mark's off-screen edge pointer (§16.4) is not drawn, so one cue points
  at the mark: the arrow while the mark is off screen, the mark tag on the mark while it is on screen.

### 7.2 Free sail with a laid course

Free sail on a laid course (`courses.md` §6.4) leads the player round it with the race's course items, the next
step coming from the free sail's progress (`courses.md` §6.4) instead of the race:

- **Shown as in a race**: the mark tag with its name and distance (the ETA at Race, the bearing at Data), the
  next-mark arrow (§7.1), the laylines on the water and the radar and the distance to them with the tack point
  (§6), the zone circle and the rounding arrows, the far marker, the leg type, VMG or VMC, the shift chip and the
  sail hint as the density and the assist allow (§14, §16.1), the radar with the course's marks (§8) and the
  course map (§8.1, its header `Next  <name>  <distance>`, without `Finished`).
- **The start line is the first step**: named `Start`, a line like the finish (distance and bearing to its nearest
  point, no rounding arrow, no zone circle), drawn on the water in `paper` while it is the next step; the finish
  line is drawn blue while it is the next step, as in a race. The lap and leg line reads `Lap 1/2 · Leg 3/7` on the
  marks and is empty for the start line.
- **Not shown** (nothing of the race runs): the countdown and flags, the start line panel, OVER and OCS, the race
  bug (clock, rank, gaps), the event feed and banners, the rules line, prompts, penalties, the ranking, the finish
  card and the results. Passing a step makes no sound and no feed line; the mark tag simply moves on to the next
  step.

## 8. Radar / minimap

- Centred on the viewed boat; **heading-up** (default) or **north-up**; range 100 m – 3 km in steps of ×1.5; the
  last setting is remembered per player. Under the disc the range (`100 M`) and, only when north-up, `NORTH UP`
  (heading-up is the default and needs no label); none of them at Glance (§16.1).
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
- **Laylines** (§6) and the **true wind arrow** at the edge.
- The **course map** (§8.1, the `map` action) shows the whole course with every boat.

### 8.1 Course map

A full-screen overlay of the whole course, opened and closed with `map` (M, D-pad up on a gamepad, `controls.md` §2, §3). It is a view,
not a pause: the race and the simulation run on underneath, the boat answers the helm and the sheets as before, the
cameras keep moving and every sound plays. Offline and online alike.

- **Open and close**: `map` toggles it; Esc (`pause_menu`) with the map open closes it and does nothing else (before
  clearing a selection, §16.4.1, and before the pause menu: the next Esc does those as usual). It does not open
  while the pause menu or the chat line has the keys, and it closes by itself when the race is gone (the scene
  leaves race mode, a new race starts). In free sail it opens on a laid course (§7.2), not on empty water. It is
  not remembered: every race starts with it closed.
- **Frame**: **course up**, fixed for the race: the course axis, from the start line's middle to the first
  rounding step's point (the first windward mark on a windward-leeward course), points straight up the screen; a
  course without a start line or rounding step uses the race's mean wind (`twd_mean`, wind from the top). It does
  not turn with the boat or the wind and the radar's orientation setting does not apply. The view is fitted once per course
  to the bounds of every mark (start and finish line ends included, virtual marks excluded) with 12 % of the larger
  span added on each side, at least 300 m across, inside the screen's margins (§16.2.2, `hud_direction.md` §5) under
  a header row of 72 design px, over a footer row of 48 and clear of the alert lane while it shows something
  (below; in landscape the frame takes the full width between the margins when the lane is empty); the scale is the same
  on both axes and the course is centred. It does not follow the boats: a boat outside the frame is drawn as a small arrow on the frame's edge
  pointing towards her, in her colour.
- **Background**: an `ink` scrim at 82 % over the whole screen; no grid, no land.
- **Course** (in this order, bottom to top):
  - the course area boundary, if the course has one, as the radar draws it (`port` at 50 %, 1.5 px), clipped to the
    frame;
  - the **course line** through the steps (`race.md` §5): from the start line's middle through each mark and each
    gate's middle to the finish line's middle, laps included (a leg sailed twice is drawn twice on the same line).
    Legs the viewed boat has finished in `hair` at 45 %, the leg she sails now (from the step she last passed to
    the next step) in `mark` at 2 px, the legs after it in `hair` at 1.5 px. Before her start the current leg is the
    first one;
  - the **start line** dashed in `paper` (2 px) and the **finish line** checkered `paper` and `ink` (4 px), as the
    race card's map draws them (`menus.md` §1.1); the start line at full strength until the viewed boat has
    started and at 45 % after, the finish line at full strength on the last leg and at 45 % before it;
  - the **zone circle** (§7: `zone_lengths·L` of the viewed boat plus the mark's radius) round the next step's
    marks only, in `mark` at 50 % (the other marks' circles were clutter). A circle under 4 px across is not drawn;
  - **marks**: rounding marks (the sequence's marks and gate buoys) as round buoys, a disc of 5 design px radius
    with a 1.5 px `ink` rim so it reads where the course line runs through it, the next step's in `mark` and the
    others in `paper`; other buoys as `paper` dots at 60 %; the committee boat and mark boats as small `paper`
    hulls; virtual marks not drawn;
  - **mark names**: each rounding mark's label from the course (`courses.md` §8, the mark id without one) beside
    it, 13 design px, 14 design px right of the buoy and centred on it; a gate gets one label, `Gate 4S / 4P` as
    in §7 (a buoy label that starts with `Gate` loses that word), right of its right-hand buoy. The next step's
    in `mark`, the others in `mist`;
  - a **rounding arrow** on every rounding mark, as the radar draws it (a 0.6 π arc of 10 design px radius from the
    top of the mark, anticlockwise on the screen to leave it to port, clockwise to starboard, with a dot at its head):
    the next step's in `mark`, the others in `mist`. A mark rounded on more than one lap gets one arrow (its side
    is the same every lap).
- **Boats**: every boat of the race as an oriented icon, the radar's triangle (§8) at least 14 design px long (its
  true length when that is larger), coloured as on the radar: the rules relation with the viewed boat, `ghost` for
  ghosts, all `paper` with the Minimal assist, the same 2 Hz and 4 Hz pulses and the outline on `Breach`; a boat
  with no relation (white) at 70 %, so the boats that matter stand out. The viewed boat in `mark`, 1.6 times the
  size with a 2 px `ink` rim, drawn last, so she is never mistaken for the fleet. The selected boat (§16.4.1) gets the radar's four hairline corners.
- **Name tags**: the viewed boat always (her name, or `YOU` for the player's own boat), the selected boat, and every
  boat with a rules relation to the viewed boat (red, green, orange or cyan): a chip above the icon as the world
  name tags draw it (§16.4: solid in her colour with a relation, `paper` on `ink` otherwise, the viewed boat's in
  `mark`). `boat_names` off leaves only the viewed boat's tag. Tags never hide the icons: each sits 14 design px
  above its boat.
- **Header** (top left): `COURSE MAP` in `mist`, and under it the lap and leg (`Lap 1/2 · Leg 3/4`, §7) and the
  next step's name with its distance (`Next  Windward  420 m`, §7 and §1 formats), the name in `mark`. Before the
  start the second line reads `Start` with the distance to the line (§9.2). After the viewed boat finishes: `Finished`.
- **Wind** (top right): the viewed boat's true wind (§3.1, `twd` and `tws`) as an arrow blowing the way the wind
  goes on the map (turned with it), with `12 KN  000°` under it, and a small `N` with a tick pointing to north on the
  map, so the turned frame still reads.
- **Footer**: a **scale bar** bottom left, the longest of 10, 20, 50, 100 and 150 m and 0.2, 0.25, 0.5, 1, 2 and
  5 nm that is not longer than a fifth of the frame's width (10 m when none is), with its length in the §1 distance
  format (`150 m`, `0.25 nm`), so the label is always a round number; and `M  CLOSE` bottom right in `mist`: the `map` binding as the
  device used last names it (`controls.md` §3 Prompts: `M  CLOSE` after the keyboard, `D-PAD UP  CLOSE` after the
  pad, the new key after a rebinding).
- **The rest of the HUD**: while the map is open the alert lane stays above it (countdown and flags, the start
  numbers, OVER and OCS, the penalty panel, the rules line, banners and the protest and hail prompts: whatever
  needs an answer now) at its usual scale, moved clear of the course: in landscape to a column on the left under
  the map's header, kept only while the lane shows something (the frame then starts 24 design px right of it, and
  takes the full width again when the lane is empty: the owner's call, a course squeezed into the right half for
  an empty column was too small); in portrait centred under the header with a band of 440 design px kept for it
  above the frame whether it shows anything or not. Everything else is hidden: the instrument page and its chip, the helm strip and its
  notes, the race bug, the feed, the radar, the ranking list, the boat card and every world tag. The
  results table and the finish card (§13) are not hidden by it: the map closes when either shows.
- **Pointer**: with the map open, `boat_pick` picks on the map: a click within 24 design px of a boat's icon
  selects her (the nearest wins), a click on the selected boat again or anywhere else clears, as in §16.4.1. It
  never picks in the 3D view behind the map.
- **Assists and density** (§14, §16.1): the map follows the assist preset's rows: right-of-way colours (none with
  Minimal), the zone circle (none with Minimal; the rounding arrows always). The instrument density does not change
  it. `hud_hide` hides it with the rest of the HUD (and it stays open underneath); `world_tags` does not touch it.
- **Colours**: the tokens of §16.2 only, in the colour-blind palette in use (§16.2.1). `mark` is the course and
  the viewed boat; the rules colours mean what they mean on the radar.

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
| Time to burn | `(−t) − t_line`: positive = early by that much (burn it), negative = late; shown as a signed `m:ss` gap (`+0:10`, `-0:03`), never in bare seconds (an `S` would read as starboard) |
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
| Gap to leader | the leader by name, the distance `D_me − D_leader` and the time gap: `Leader  Nora  +120 m  +0:23 @ Windward` |
| Time gap | to the leader or the boat ahead: at the last common split (`race.md` §8.4, both boats' last rounding is the same step) the difference of the split times, with the step's label (`+0:23 @ Windward`); else the estimate, the distance difference over the viewed boat's `V_ref` (`race.md` §7.2), marked `~` (`~+0:25`, no label); with both finished the difference of the finish times (`@ Finish`) |
| Ahead | the boat directly ahead in the ranking: name, distance difference and time gap as the leader's (`Ahead  Kestrel  +45 m  ~+0:08`); not shown when she is the leader (the leader line names her) |
| Behind | the boat directly behind: name and distance difference (`Behind  Maja  -30 m`) |
| Race clock | time since the start signal |
| Split at rounding | on each `Rounded` event: `Mark 2 · 4th · +0:18` for 4 s |
| Finish | on the `Finished` event: place, time, gap to the winner |

The ranking list (Tab) shows every boat: rank, sail number (the one on her hull and sails, `data_format.md` §8.4),
boat name, skipper, gap, status code (OCS, pending penalties count, RET, DSQ, finished time). The sail number, boat
name and skipper read as in the results (§13, `menus.md` §5): the boat's livery name (the player's too), and in the
skipper column `You` for the player's own boat and the AI badge (`AI · Easy`) for an AI boat, so a boat is named the
same in the race bug's lines, the ranking list and the results (the race bug, the feed and the rules lines call the
player's own boat `You`).

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
- **Online only** (`controls.md` §2): offline the race has no protest mode and the core does not use the hail flags,
  so neither prompt below shows until online play exists (the code stays, behind the online switch).
- **Protest prompt** (protest mode, `rules.md` §10): `Protest <name> (rule 11)? [P]` with an 8 s countdown, the key
  as the device used last names the `protest` binding (`controls.md` §3 Prompts).
- **Hail for room to tack** (optional rule 20): action button when valid (`rules.md` §7.9) and the reply prompt for
  the hailed boat, with the `hail` binding named the same way.
- The texts use the table in §12.3.

## 12. Penalties

### 12.1 Panel

Visible while the boat has pending penalties, is taking one, or was penalised in the last 5 s. It is a compact
chip, not a dashboard (the owner's call, 2026-10-17: the first panel, 620 x 118, took too much of the screen):
540 x 76 design px, `ink` at 86 % with a 3 px `port` bar along its top, the ring on the left, three short lines in
the middle (a rule text too long for its room is set smaller, down to the 11 px floor), the deadline on the right.
It still reads at a glance; nothing in it is said twice.

- **Lines** (left-aligned after the ring): the caption `PENALTY · RULE 10` in `port` caps (13 design px; with more
  than one pending `PENALTY 1 OF 2 · RULE 10`), the rule's text of §12.3 (20 design px, `paper`), and a state line
  (13 design px, `mist`, caps): the other boat's name (`WITH NORA`) and, after a ` · `, the turn state, the first
  that applies:
  - `NOT COUNTED: INSIDE THE ZONE` while the core's `turn_in_zone` is set (match races only, `rules.md` §9.3; a
    fleet-race turn counts anywhere);
  - for 3 s after the core's last turn reset (`turn_reset`, `turn_reset_tick`, `rules.md` §11.2), by its reason:
    `TURN RESET: PAUSED`, `TURN RESET: TURNED BACK`, `TURN RESET: INSIDE THE ZONE`, `TURN RESET: MARK ROUNDED`;
  - with nothing turning yet: `SAIL CLEAR, THEN ONE FULL TURN` (the penalty of `rules.md`: one 360° turn, a tack
    and a gybe, within the deadline on the right);
  - while the turn has progress: nothing (the ring says how far).

  The HUD reads both states from the core and does not infer them. After the penalty is done the lines read
  `PENALTY` and `Penalty done` for the 5 s the panel stays.
- **Turn progress**: a small ring gauge at the panel's left: a ring of 22 design px radius, its track in `hair`
  (3 px), the progress arc in `paper` (3 px) from the top clockwise over `|Θ| / 360°` of the circle (the tracker's
  `|Θ|`, `rules.md` §9.3; every penalty is one turn of 360°), the number `210°` in its middle (14 design px); right
  of the ring the words `TACK` over `GYBE` (11 design px), each in `paper` once done and in `mist` at 45 % before.
  The ring is inside the panel only.
- **Deadline**: `rules.md` §9.4 countdown `1:32` to the time the turn must be **completed** (120 s after the
  incident), 40 design px right-aligned under a `DEADLINE` caption (11 design px, `mist`), red below 30 s (a turn
  takes 10 to 25 s); hidden when there is no deadline (match race single penalty). Under the number a thin bar
  (3 design px, 100 design px long, right-aligned with the number) shrinks towards 0:00: its track in `hair` at
  45 %, its fill from the left over `time left / 120 s` of it in the countdown's colour (`paper`, `port` below
  30 s).
- **Disqualification warning**: a fourth line, `ONE MORE PENALTY = DISQUALIFICATION` in `port` (13 design px; the
  panel grows by 20 design px for it), when pending = `dsq_pending − 1` or received = `dsq_total − 1`.
- **Finish blocked**: `Take your penalty before finishing` on a `FinishBlocked` event.
- **Nothing on the water**: the turn is not drawn round the boat in any camera (the owner's call: the ring on the
  water was ugly and hid the boat); the panel's small ring carries it in every camera.

### 12.2 Messages

On a `Penalty` event for the viewed boat: a 3 s banner `PENALTY · RULE 10` and a sound (the panel of §12.1 appears
at the same moment with the rule's text and the other boat, so the banner does not repeat them); for other boats, a
fleet feed line `<boat> penalised, rule 10 (<other>)`. `PenaltyServed`: `Penalty done` banner 2 s.
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
- **Results screen** (`menus.md` §5): place, sail number and boat, skipper (`You`, or the AI badge), finish time, gap to winner,
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
| Instruments, wind, VMG / VMC, VMG angles on the TWA dial and the pointer's colour | yes | yes | yes |
| Trim gauge colours and tell-tales | yes | yes | tell-tales only |
| Laylines (water and radar) | yes | yes | no |
| Distance / time to layline | yes | yes | no |
| Next-mark arrows and zone circle (3-D view, radar, course map) | yes | yes | arrows only |
| Radar and course map right-of-way colours | yes | yes | no (all white) |
| Rules awareness messages (§11) | all | all | `Breach` lines only |
| Start: time to burn, bias | yes | yes | distance to line only |
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
- VMG angles (§4, §16.3): the dial marks `±θ_up` and `±θ_dn` at every phase; the true wind pointer is `stbd` at
  the reference angle, `mark` 11° off and `port` 20° or more off, and neutral on a reach; no HUD text shows a target
  speed or a percentage of a target.
- Layline test: a boat placed on the computed starboard layline, sailing at `θ_up` with no current, reaches the mark
  within 0.5 L in a steady wind (headless sim).
- Radar colours follow the pair records for the port–starboard, windward–leeward and mark-room scenarios of
  `rules.md` §13.
- Time to burn: a boat 100 m behind the line at 5 m/s heading straight at it, 30 s before the gun, shows `t_line` 20 s
  and `+0:10` to burn.
- Density (§16.1): for each level and phase the table's items are shown and no others (at Race on a beat: no TWD,
  no VMG and SOG, no lap line, no boat behind; the leader gap with her name, the boat ahead with her time gap, the
  true wind speed, the heel bar and the shift chip yes); the density key cycles
  Glance, Race, Data, Glance and the choice survives a restart; the defaults are Race at 1920 x 1080 and Glance at
  1280 x 800.
- Name tags (§16.4): a boat at 45 m has a tag, one at 55 m has none until it is selected; with a penalty pending
  and a turn running nothing is drawn round the boat in any camera, and the panel shows the turn as a number in a
  small ring whose arc spans the turn; the deadline bar's length is the time left over 120 s.
- Next-mark arrow (§7.1): drawn in the onboard, aerial and free cameras and not in the chase camera, and only with
  the mark off screen (hidden with it ahead and on screen); to the camera's right it points right, behind it points
  down; outside the chase camera the mark's off-screen edge pointer is not drawn; it hides with `world_tags` and
  with the course map.
- Selecting (§16.4.1): a click on a far boat's hull or rig selects her and draws her pointer and tag over her
  masthead (following her heel), a click on the
  water or on her again clears, a click on another boat replaces her, a press dragged 20 px picks nothing
  (`controls.md` §8 test 10), Esc clears it without pausing, `boat_select` goes nearest first, then the next, then
  none; the radar marks her.
- Boat card (§16.7): for a scripted race state every row matches the race and rules records it comes from, and
  the card has no distance, bearing, speed or heading cell; at 1280 x 800 and 1080 x 1920 for UI scales 80 % to
  130 % at every density, with a boat selected, every text is on screen and no two blocks overlap.
- Tack point (§16.4): the point and its `TACK IN` label are drawn, and no line runs from the boat to it; with the
  point under a corner block the label moves under the ring or is not drawn, never over the block.
- Ladder lines (§16.4.2): with a boat selected two lines square to the axis, each from its boat's bow towards the
  other boat and past her line, own in `mark`; the gain label reads her distance along the axis in hull lengths;
  none with nothing selected.
- Penalty panel (§12.1): the panel is 540 x 76 design px, its ring 22 px in radius; the own penalty banner reads
  `PENALTY · RULE 10` and is gone after 3 s.
- Hoist cue (§5.1): during a hoist one `HOISTING <SAIL>` cue with its bar shows, and no two texts of the helm strip
  and its notes overlap.
- Sail state (§5.2): with auto trim on at Race the strip shows `LUFFING` for a luffing driving sail, `STALLED` for a
  stalled one, `IN IRONS` after 1 s inside the no-go zone under 1 kn and not before, nothing with way on, `LET FLY`
  at once on the key; at Glance too; with manual trim in the sheet value's place, overlapping nothing.
- Bad air (§3.1): nothing at 2 % of the wind lost, `Bad air −8 %` in the helm notes at 8 %.
- Sail strip (§5.3): at Race every slot's key and name with the sail up underlined; at Glance none until a sail key,
  then gone after 3 s; a busy press shows it and blinks the running change in `mark`; on the pad no keys and the
  highlighted slot with its set button.
- Every text of the HUD fits its block at 1920 x 1080 and 1280 x 800 for UI scales 80 % to 130 %, and no two blocks'
  drawn areas overlap there (world tags aside).
- Portrait (§16.5): at 1080 x 1920 for UI scales 80 % to 130 %, in the pre-start, beat and penalty states at every
  density, every text is on screen and no two texts overlap, and no two blocks' drawn areas overlap (world tags
  aside); the default density is Glance; the radar is compact.
- Race end (§13.1 to §13.3): on the player's finish the card shows the place, the gap and the time, fades in and
  out and is gone after 5 s of race time; RET and DNF get their card, DSQ its banner; the race is over at each of
  them; the finishing rows fill in as boats finish before the close and are the core's results after it; the
  summary has the start, every rounding with its place, the places gained, each penalty with its rule text, the
  top speed and the distance sailed of a scripted race.
- Course map (§8.1): `map` opens and closes it and Esc closes it without pausing or clearing the selection; the
  race runs on while it shows (the race time advances, the boat answers the helm); the frame fits every mark at
  1920 x 1080, 1280 x 800 and 1080 x 1920; the course axis points up the screen and the north tick and boat icons
  turn with it; every boat is drawn in its radar colour (ghosts grey, all white with
  Minimal) and the viewed boat in `mark`; the course line runs through every step with one rounding arrow per
  rounding mark on the side of the course; the next step's marks are in `mark` and only they have a zone circle;
  every rounding mark (one per gate) has its name; in landscape the frame takes the full width with the alert lane
  empty and starts right of the lane while it shows something; the scale bar's label matches its
  length; while it is open the alert lane shows and the radar, the instrument page and the world tags do not; a
  click on a boat's icon selects her.
- Capture rate note (§16.6): each `capture_slow` press shows the note for the new rate, also with the HUD hidden;
  it is gone 1.5 s of frames later and fades over the last 0.4 s; `capture_pause` shows nothing.

## 16. Presentation

What the player can choose to see and what the colours mean; the layout, sizes and motion follow
`docs/design/hud_direction.md`. Player-facing strings contain no em dashes.

### 16.1 Instrument density

Three levels, **Glance**, **Race** and **Data**, cycled in that order by the `hud_density` action (`controls.md`
§2). Density decides how many instrument values show. It never hides a contextual item (countdown, OVER and OCS,
the rules line, the penalty panel, banners, protest and hail prompts, the sail state of §5.2, the `Bad air` line) or anything in the world (start line, mark
tag, next-mark arrow, laylines, tack point, zone circle, rounding arrow, name tags, edge pointers) or the selected
boat's card (§16.7). The radar, the helm strip and, under manual trim, the trim gauges show at every level.

| Phase | Glance | Race | Data |
| --- | --- | --- | --- |
| Pre-start (race sequence, not started) | boat speed, true wind speed, TWA dial; start block: countdown, time to burn with its late/early bar, the flag rule in one line; no race bug | + heading, heel bar; full start block (distance and time to line, burn, bias, flags); feed (own events, 3 lines); no race bug | + VMG, SOG, AWA, COG, TWD, AWS; race bug (fleet, laps and legs); feed 6 lines (every event) |
| Beat or run | boat speed, true wind speed, TWA dial with the VMG angles and the coloured pointer; race bug: clock and rank; mark tag: name and distance | + heading, heel bar; the shift chip in the heading cell; the race bug adds the leader by name with her gap and the boat ahead with hers (§10); the mark tag adds the ETA; feed (own events, 3 lines) | + VMG, SOG, AWA, COG, TWD, AWS; lap, leg and leg type; the boat behind; the mark tag adds the bearing; feed 6 lines (every event); sail hint |
| Reach | as a beat, the pointer neutral | as a beat | as a beat, with VMC in place of VMG |
| Rounding (within `6·L` of the next mark, and 6 s after a rounding) | boat speed, true wind speed, TWA dial | as the leg | as the leg |
| Penalty (panel shown) | boat speed, true wind speed, TWA dial | as the leg | as the leg |

- Race is what a racer needs on each leg and nothing more (the owner's call, 2026-10-17: the HUD showed too many
  numbers at once): speed, the TWA dial with the VMG angles, heading, heel, the true wind speed, the next mark's
  distance and time, the countdown and line numbers before the start, rank, the leader and the boat ahead by name
  with their gaps (who she is racing). VMG, SOG, AWA, COG, TWD and AWS, the lap and leg line, the boat behind, the
  mark's bearing and the fleet's feed are Data.
- The wind sits with the boat instruments (the owner's call, 2026-11-07: a wind page in the top right corner felt
  out of place, and the page showed too many numbers): the TWA dial and the true wind speed at every level (the
  owner, 2026-11-07: the true wind speed is one of the most important parts, so Glance, the Deck's default, shows
  it beside the boat speed), TWD at Data, and the shift chip in the heading cell, where the compass tells a sailor
  about the shift. The top right corner holds race items only (the feed).
- At Glance the radar is drawn at 72 % of its size without the range and orientation labels, the helm strip has no
  labels (the sail state shows, and the sail strip for 3 s after a sail key, §5.2, §5.3). At Glance and Race the feed shows only the viewed boat's own events; Data shows every event.
- Free sailing (no race): the instrument page and the helm strip as in the table's beat row without the race items;
  on a laid course (§7.2) the rows of the leg phases (beat, run, reach, rounding) without the race bug and the feed.
- **Defaults**: Race; Glance on the Steam Deck and on any screen under 900 px tall (after the UI scale). The player's
  last choice is kept in the settings file (per device, `menus.md` §3) and wins over the default. Glance was
  considered as the default everywhere (2026-10-17) and rejected: with Race cut down to the racer's list, Glance only
  drops heading, the shift and the gap, which a new player on a large screen would miss without knowing the density
  key; on the small screens Glance stays the default because the page and the radar are drawn smaller there.
  Glance has the true wind speed since 2026-11-07 (it was Race and up before): a Glance player sees the wind.
- A change shows an `INSTRUMENTS · <LEVEL>` chip above the instrument page for 1.5 s; three small squares on the page
  show the level at all times.

### 16.2 Colour tokens

| Token | Value | Meaning |
| --- | --- | --- |
| `ink` | `#06121B` | scrims, glass pages (14 % to 44 %), chips (80 % to 90 %) |
| `paper` | `#F5F8FA` | every number, primary text; boats with no relation |
| `mist` | paper at 66 % | units, secondary text, the state lines |
| `label` | paper at 55 % | the caps labels and captions of every cell, chip and panel (quieter than the values they name) |
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
`mist`, `label`, `hair`, `mark` and `ghost` never change, and neither do the words and letters that go with every
colour.

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
The two analogue parts are the TWA dial and, at Race and Data, the heel bar (centre zero, ±30°, the bar in the
tack colour to the side that is down, the heel number at 26 beside it). The **TWA dial**: bow up,
the close-hauled sectors in `port` and `stbd`; the **VMG angles** of §4 on both sides, each a solid `mark` notch on
the rim (an inward triangle 11 design px deep and 12 wide) with a 2 px tick under it,
the reference pair (§4) at full strength and the other pair at 45 % (both at full strength on a reach); the true
wind pointer, **coloured by the angle error** `Δ` of §4 on a smooth gradient: `stbd` up to 2°, through `mark` at
11° to `port` at 20° and beyond (linear in between in RGB), with a thin `ink` edge so it reads over the sectors,
and `paper` with no reference (a reach); Data adds the
apparent wind pointer, hollow, in `paper`. No cell shows a target speed: Glance has boat speed, the true wind
speed and the dial (654 x 150 design px: the true wind cell, 168 wide with its value at 52, between the boat
speed and the dial, the two numbers on one baseline; the cell's width is what its label and unit need at the
11 px floor of §16.2.2 at UI scale 130 % on 1280 x 800); Race (630 x 246) adds heading under the boat speed and
moves the true wind speed over the heel bar; Data (760 x 298) adds VMG (VMC on a reach) over SOG beside them, the AWA
value under the dial and a small row of COG, TWD and AWS along the bottom (COG and TWD with the degree sign like
the heading, AWS with its `KN` in the cell's unit corner, §1). Every cell of the Race page keeps its
place at Data. The **shift chip** (§3.2) sits in the heading cell, left of the number, at Race and Data: the
text in `ink` on a `stbd` (lift) or `port` (header) chip, 13 px. Numbers keep the 4 Hz refresh of §1; dial and
bars move every frame.

**Type hierarchy** (design px at 1920 x 1080, `hud_direction.md` §4; every text is one of these sizes, so the eye
learns what a size means): numbers 112 (boat speed, the hero), 52 (heading, true wind, VMG, SOG), 40 (the TWA
value, the race bug, the start numbers, the mark distance, the tack point, the penalty deadline), 26 (the heel
number, the Data row of COG, TWD and AWS, the card's place and name); the countdown 128. Text 20 (alert lines, table rows, the
penalty's rule text, the gap lines), 16 (feed, helm notes, the card's standing, the next-mark arrow's distance in
24), 13 (every label, caption and chip: `label` for labels and captions, `paper` or the state's colour for chips);
11 is the floor (§16.2.2) and the deadline's caption. Labels sit in `label`, units in `mist`, values in `paper`.

### 16.4 World tags

- **Mark tag**: on the next mark (§7): name and distance; at Race the ETA under them; at Data the bearing and
  relative bearing too (§16.1: the tag is never hidden by the density, its second line follows it). Off screen it
  becomes an edge pointer at the screen edge towards the mark in the chase camera; in the other cameras the
  next-mark arrow (§7.1) takes its place.
- **Tack point**: on a beat or run with the layline distance of §6 shown, a point on the water where the current COG
  meets the other tack's layline (a ring in the colour of the tack she will sail after it), with
  `TACK IN <distance> <time>` on a beat and `GYBE IN <distance> <time>` on a run (the turn onto the other tack
  downwind is a gybe), or `OVERSTOOD <distance>` at the boat. Only the point and its label: no line is drawn from
  the boat to it (the owner's call: the forward path line was clutter in front of the bow).
- **Name tags**: another boat's name over her mast when she is within 50 m of the viewed boat **and has a rules
  relation to her** (a radar colour of §8 other than white: red, green, orange or cyan), or when the player has
  selected her (§16.4.1, at any distance). A crowded start is therefore not one chip per mast: the tags name the
  boats that matter now. The tag takes the radar colour of §8 (solid chip when there is a relation, paper on
  ink otherwise) and pulses as the radar icon does. A selected boat off screen gets an edge pointer with her name
  and distance. `boat_names` cycles three states, each noted in the helm notes for 3 s (`Name tags: every boat
  nearby`, `Name tags: off`, `Name tags: boats to watch`): **watch** (the default above), **all** (every boat
  within 50 m, relation or not, plus the selected one) and **off** (none, the selected boat's included; her
  bracket and card stay). The radar's and the course map's tags (§8) show in watch and all, only the viewed
  boat's when off. A session starts on watch.
- **Keep clear of the corners**: world labels never sit on the HUD's own blocks (the instrument page and its
  chip, the radar, the helm strip and its notes, the next-mark arrow, the race bug, the feed, the alert lane,
  the boat card), as the edge pointers keep to their box. The tack point's label goes above its ring,
  else under it, else it is not drawn (the ring stays); a name tag over a block is not drawn (the selected boat
  keeps her marker); the mark tag goes above-right of the mark, else under it, else left of it, and hides when
  none is clear (the mark's diamond stays).
- **Masthead**: the name tags and the selection marker stand at the masthead of the boat as she floats, heel and
  pitch included (`conventions.md` §3 attitude: the body point `(0, 0, 1.35·loa)` above the hull reference point),
  so they stay over the rig when she heels.
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
- **Marking**: the selected boat gets a small pointer over her masthead (§16.4, heel included): a solid downward
  triangle 12 design px wide and 9 tall, its tip 8 design px above the masthead, in her tag colour (paper with no
  relation) with a 1.5 px `ink` edge at 70 %; her name tag, when shown, stands on top of it instead of on its
  leader line. No box round the boat: a screen-aligned box looked wrong once she heeled. No glow, no fill. On the
  radar (§8) her icon gets four hairline corners in paper, 9 px from its centre.
- **Ladder lines** (§16.4.2) show while she is selected.
- The pointer picks only in the 3D view: not through the pause menu, the look panel (§18) or the chat line, and not
  while the simulation is paused with the menu open.

#### 16.4.2 Ladder lines

While a boat is selected (§16.4.1), two lines on the water show who is ahead on the leg, as a sailor reads the
ladder: one through the viewed boat and one through the selected boat, both square to the ladder axis.

- **Axis**: on a beat or a run, and before the start or free sailing, the wind: the viewed boat's clean wind
  direction smoothed 10 s (the laylines' wind, §6). On a reach, the bearing from the viewed boat to the next mark's
  point (§7), since across the wind says nothing there.
- **Lines**: each a straight line on the water (sea level) that starts at the boat's **bow** (the bow point of her
  hull as she floats, heel and pitch included, dropped to the water) and runs square to the axis towards the other
  boat's side, far enough to pass the other boat's line by 40 m (at least 80 m), so the two rungs overlap between
  the boats, where the eye compares them: the rung further along the axis is the boat ahead. Nothing runs through
  a hull: the line leaves the bow and is not drawn over any boat's hull and rig on screen (her pick triangle of
  §16.4.1 with 6 design px round it). Before this the lines ran through the hull reference points with a one-hull-length
  gap at each boat (owner, 2026-10-17: the bow is where a sailor sights the ladder from). The viewed boat's in
  `mark`, the selected boat's in `paper` at 75 %, hairlines (1.5 px). Drawn only where in front of the camera;
  nothing else (no fill between them).
- **Gain**: at the selected boat's line, two of her hull lengths from her bow along it, her distance ahead of or
  behind the viewed boat along the axis in hull lengths of the viewed boat, one decimal: `2.1 L AHEAD`,
  `0.4 L BEHIND` (`EVEN` under 0.05 L), 13 design px `paper` on an `ink` 70 % chip. Ahead means upwind on a beat
  (and before the start), downwind on a run, towards the mark on a reach.
- Hidden with no selection, with the course map open, with `world_tags` off and in the results; at every density
  and assist preset. A scene without a 3-D camera draws none.

### 16.5 Portrait layout (capture)

For native 9:16 clips (Reels, Shorts): the HUD takes this layout on any screen taller than it is wide, so the
portrait capture preset of `menus.md` §3 (a 1080 x 1920 window) and a window opened at that shape from the command
line (`--resolution 1080x1920`, also with Movie Maker's `--write-movie`) both get it. The rule text is the point of
these clips, so the alert lane is at the top and large; the instruments are compact at the bottom.

- **Scale and margins**: the design's px at 1080 x 1920, `k = width / 1080` (logical px, after the UI scale).
  Margins 48 px left and right, 140 px top, 200 px bottom: the top margin keeps the alert lane under the apps' title
  bar, the bottom margin keeps the instruments above most of their caption and button strip.
- **Top row**: the race bug top left (with its lap and gap lines); nothing top right (the feed sits over the
  helm notes, the shift chip is in the page's heading cell, §16.3).
- **Alert lane**, centred under the bug with its lines, 16 px below (at the top margin when there is no bug):
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

While a boat is selected (§16.4.1) a small card says who she is and how she stands against the viewed boat: what a
racer glances at, nothing to study. It uses only what the HUD already reads (the race and rules records, the
liveries); a field with no value is left out, never guessed. Numbers refresh at the 4 Hz of §1 with the rest.

| Row | Content | Source |
| --- | --- | --- |
| Header | sail number and skipper in caps (`SLO 7 · AI EXPERT`; a human skipper is `PLAYER`, or the skipper's name when the race has one), then the boat name large; on the right, after the start, `PLACE` over her place `3 / 6` (her finishing place once finished) | livery (sail number, boat name), the race's skipper and AI level, the shown ranking order of §10 |
| Standing | `Next <mark>` (the label of her next step: a mark's label, `Gate`, `Finish`; `Start` before she starts), or her status (`Finished`, `RET`, `DSQ`), with `OCS · ` before it while she must return; after a ` · `, how far she is ahead of or behind the viewed boat along the course: `45 m behind you`, `120 m ahead of you`, `level with you` (the difference of the two course distances to go `D` of `race.md` §8.2), only while both are racing on the course. On a beat or a run the ladder lines (§16.4.2) show the same standing on the water, in hull lengths | race record |
| Rules | while the pair record with the viewed boat has a relation (the radar colour of §8): one line in that colour, `YOU KEEP CLEAR`, `SHE KEEPS CLEAR`, `YOU GIVE ROOM` or `SHE GIVES YOU ROOM` (room wins over keep-clear, as on the radar), then `· RULE 10` (the rule's number of §12.3) and `· BREACH` when the state is Breach. The rule's text is not on the card: the rules line of §11 carries it while it matters, the rules help explains it. Not with the Minimal assist (§14), as the radar colours | pair record (`rules.md` §11.1) |
| Penalty | `1 PENALTY OWED` (or `2 PENALTIES OWED`) in `port` while she has penalties pending, `· TURNING` added while she is taking one | her rules record |

- **Dropped** (owner, 2026-10-17: too many numbers): the cells of her distance, bearing, speed and heading, and the
  rule's text under the rules line. Her distance still shows on her edge pointer when she is off screen (§16.4),
  and the radar has her position; her speed and heading are hers to know.
- **Look**: an ink chip at 86 %, 340 design px wide, a hairline along the top edge and a 4 px bar down the left
  side in her tag colour (`hair` with no relation); labels in `label`, values in `paper`, numbers tabular. The
  header's caption 13 design px, the name 26, the standing 16, the rules and penalty lines 15 caps. Text no
  smaller than the 11 px floor (§16.2.2): a line too long for the card is set smaller down to the floor, then cut
  with an ellipsis.
- **Place**: landscape, left, its bottom 48 px above the instrument page (clear of the density chip) and never
  higher than 16 px under the race bug; portrait (§16.5), left, its bottom 8 px over the helm notes, beside the
  feed. It is a panel, not a world tag: `world_tags` leaves it, `hud_hide` hides it.
- **Density**: it shows the same at every level (§16.1: density never hides it); it only appears on the player's
  request.
- The card goes when the selection clears and in the results. Without a race (free sailing) it has the header
  (without the place) only.

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
  the boat count, the renderer and driver, vsync and the frame rate limit, the camera mode; the log adds the video
  memory in use, the main thread's process step (every node's per-frame work, from a stamp before the first node)
  and the rest of the frame (physics, the renderer's CPU work on the main thread and any wait for the GPU).
- **Sections**: the game's own per-frame work in milliseconds per frame, timed around the calls: `input` (devices
  and controls), `sim` (the 50 ms ticks: the simulation step or taking in the tick that ran on the worker thread, starting the next
  one, and the sail snapshots), `hud` (`Hud.tick` and
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

| Row | Values | Flag | Applies | Where to look (the hint) |
| --- | --- | --- | --- | --- |
| Anti-aliasing | Off, FXAA, SMAA | `--aa=` | live (root viewport) | masts, stays and sheets against the sky; subtle on Retina |
| Grade | On, Off | `--look=` | live; off also drops SSAO and depth of field | the whole picture: compare the sea's blues |
| Grade strength | 0.0 to 1.5, step 0.1 | `--grade=` | live (the LUT is rebuilt) | sky and sea saturation, warm sunlit water, cool shadow sides; whites stay white |
| SSAO | Tier, Off, On | `--ssao=on\|off\|tier` | live (environment) | high tier only: deck at the foot of the mast, cockpit corners |
| Clip camera DOF | On, Off | `--dof=` | live (long lens and mark shots, tiers M and H) | clip cameras only: press X for the long lens |
| Time of day | the venue's date, 30 min steps over the hours with the sun at 6° or more | `--time=HH:MM` | live (sky, sun, haze, grade) | the sun's height and colour, shadow length on the water, the sky toward the sun |
| Conditions | Clear, Fair, Hazy, Overcast | `--conditions=` (`--sky=` the old names) | live (sky, sun, haze, grade, drawn shadows) | clouds, how far the land and far boats fade, shadow strength |
| Quality tier | L, M, H | `--quality=` | live: sea grid and water shader, wakes, drawn shadows, sun shadows, glow, SSAO, reflections; a short hitch while the shaders compile | water detail near the boat, wakes, shadows on the water |
| Haze | x0.0 to x1.5 of the light's haze, step 0.1 | `--haze=` | live; kept when the time or the conditions change | far boats, marks and the land at 1 to 10 km |
| Reset haze | action | | back to x1.0 | |
| Whitecaps | On, Off | `--caps=` | live | set the drawn wind to 20 kn or more |
| Drawn wind (sea) | Sim, 8 to 25 kn | `--drawn-wind=` | live: the wind the water draws (whitecaps, puffs); waves and boats keep the world's | puff patches and whitecaps on the water |
| Wind for restart | 4 to 30 kn | `--wind=` | the value for the next row | |
| Restart with wind | action | | restart only: the core takes its wind when the world is made, so the race or free sail starts again with that wind, every other setting kept (a rules scenario keeps its file's wind) | the waves and the boat speed after the restart |
| Chase bank | On, Off | `--chase-bank=` | live: off keeps the horizon level in turns too (the heading follow is the same) | chase camera in a tack or a gybe |
| Drawn boat shadows | On, Off | `--no-drawn-shadows` | live (tiers L and M) | tiers L and M: the boat's shadow on the water |
| Boat sun shadows | On, Off | `--no-boat-shadows` | live: the shadow proxies hidden and the sails not casting (`sail_visuals.md` §11.4) | the sails' and boom's shadows on the deck |
| Render scale | Setting, 50, 67, 75, 85, 100 % | `--render-scale=` | live (root viewport) | fine detail: rigging, sail numbers, the far fleet |
| Frame-time overlay | On, Off | `--perf` | live (§17) | top left |

There is no vignette row and no `--vignette=` flag: the game has no vignette (owner decision 2026-10-11,
`water_render.md` §4.5).

A readout line under the title shows the frame rate, the mean frame time over the last 0.25 s, the tier and the
3D scale. The selected row's lines at the bottom say how it applies and where to look; the Time of day row's value
also shows the sun's height (`14:30  sun 51°`).

- **Keys** while the panel has the focus: Up and Down pick a row, Left and Right change it, Enter or Space toggles a
  row or runs an action, Esc gives the keys back to the boat (the panel stays up), F9 closes it. F9 on an open
  panel without the focus takes the focus again. **Mouse**: a click on a row steps it forward (or runs it), a right
  click steps back, the wheel either way; a click on the panel takes the focus, a click outside gives it back.
- **Input**: while the panel has the focus (and in the frame that gave it back, so that Esc does not also open the
  pause menu) the scene hands the boat, the cameras and the scene keys no buttons, as the chat line does
  (`controls.md` §7); the simulation keeps running. With the pause menu or the chat open the panel takes no input.
- **Look**: HUD fonts and colours (`HudStyle`), an ink panel at 86 %, names in mist, values in paper, the selected
  row in the mark colour; scaled like the HUD.
