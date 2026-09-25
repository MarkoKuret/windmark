# Race HUD: design direction

*WM-016.27, phase 1 (mock-ups for the owner's review). The numbers, states and formats stay as `docs/specs/hud.md`
defines them; this file is layout, type, colour and motion. Mock-ups: `hud_mockups.html` (open it in a browser; the frames are in
`frames/`).*

**In one line:** the precision of a mast display (big exact numerals, units small, nothing decorative) set in the
language of a race broadcast (strong type, a few bold colours that mean something, hairlines, data on the scene and
on the water, not in boxes).

## 1. Principles

1. **The numeral is the interface.** Every value is a big tabular numeral with a small caps label above it and a small
   dim unit after it. Nothing sits inline as "BSP 5.3 kn".
2. **Hierarchy is decided, not implied.** Three sizes of numbers, each for a known set of values (§4). Boat speed is the
   hero; the rest earns its size.
3. **No grey boxes.** Data sits on the scene over soft edge scrims (ink gradients in the corners and along the top) and
   a light text shadow. Solid ink is used only for a few small chips: the race bug, name tags, the rules line and the
   penalty panel.
4. **Colour means something or it isn't there.** The chrome is ink and paper. Colour appears only for the course and
   you (yellow) and for the rules colours of `hud.md` §8 (§3 below). If everything is white, nothing needs your attention.
5. **Put it where it belongs.** Mark distance sits on the mark, tack distance on the layline, the start line numbers
   under the countdown, the penalty turn around your boat. Corner blocks keep only what has no place in the world:
   speed, wind, clock, rank.
6. **Always on vs contextual.** A small constant frame; everything else appears when it applies and leaves when it
   doesn't (§6).
7. **Own identity.** Hairline plus numeral plus square chip, one yellow. No copied broadcast marks, logos or layouts;
   no rounded pills, glows, bevels or gradients on type.

## 2. Type

- **Barlow Semi Condensed** (SIL Open Font License 1.1, Google Fonts), weights 500, 600 and 700. One family for
  everything: condensed enough for numbers side by side, open counters for legibility at small sizes, a slightly
  technical, road-sign character that suits instruments. Recorded in `docs/THIRD_PARTY.md`.
- **Tabular figures are mandatory for numbers.** Barlow's default figures are proportional; the `tnum` feature is in
  the font. In Godot set it on the `FontVariation` (`opentype_features = {"tnum": 1}`) so digits do not shift as values
  change.
- Labels: 600, all caps, tracking +14 %. Messages: 700, caps, tracking +6 %. Names in tables: 600, caps, tracking +8 %.
- Sentence text (penalty rule text, feed, results notes) stays in sentence case, weight 500 or 600.

## 3. Colour tokens

| Token | Value | Use |
| --- | --- | --- |
| `ink` | `#06121B` | Scrims (at 40 to 60 %), chips (at 80 to 90 %) |
| `paper` | `#F5F8FA` | Every number, primary text |
| `mist` | paper at 66 % | Labels, units, secondary text |
| `hair` | paper at 42 % | Hairline rules, rings, ticks (1.5 px at 1080p) |
| `mark` | `#FFD23F` | **Signature.** The course and you: next mark, zone circle, rounding arrow, your course line, your row, the number to act on (burn) |
| `stbd` | `#27D17C` | Starboard layline, tack letter S, lift, "she must keep clear of me", right-of-way hint |
| `port` | `#FF4438` | Port layline, tack letter P, header, "I must keep clear of her", breach, OVER, OCS, penalty |
| `owe` | `#FF8A1F` | I owe room; keep-clear warning line |
| `have` | `#2FD8EE` | She owes me room; "You have mark-room" |
| `rule17` | `mark` | "Don't sail above your proper course" |
| `ghost` | paper at 35 % | Finished and cleared, retired, disqualified, disconnected |

Rules states (`hud.md` §8, §11): **Warning** pulses the boat's tag and radar icon at 2 Hz; **Breach** pulses at 4 Hz and
adds an outline. Room colours win over keep-clear colours. With the Minimal assist every boat is paper.
Colour is never the only signal: every coloured state also has a word (the rules line, the tag note, the tack letter).

## 4. Numerals

| Size (1080p) | Deck (800 px) | Values |
| --- | --- | --- |
| 128 px | 105 px | Hero: boat speed; the countdown before the start |
| 52 to 72 px | 43 to 59 px | Primary: VMG % (or polar % on reaches and before the start), TWA, HDG, VMG, TWS, deadline, mark distance (44) |
| 22 to 40 px | 18 to 33 px | Tertiary row (SOG, COG, AWS, AWA, heel, polar %), clock and rank in the bug (40), table values |
| 15 px labels | 12 px | Caps labels; 11 px (Deck 11 px) is the floor for any text |

- Units at about 22 % of the number's size, in `mist`, with a small gap: `5.3 KN`, `197 M`, `97 %`.
- Side letters after angles in the tack colour: `44° P` (red P), `41° S` (green S).
- Signs are true minus signs (`−23 M`). Missing values show `--` as the spec says, never a dash of any other kind.
- Numbers never tween or roll; they change at the spec's 4 Hz refresh. Needles, bars and on-water lines move every frame.

## 5. Layout grid

Reference 1920 x 1080 (scale uniformly for other 16:9 sizes). Margins 56 px left and right, 44 px top and bottom.
Four corners, a top-centre alert lane, a bottom-centre helm strip, and the world between.

```
+-------------------------------------------------------------------------------+
| RACE BUG (clock, rank)          ALERT LANE              WIND (TWS, TWD, shift) |
| lap, leg, gaps                  countdown / penalty       feed (events)        |
| [live order, contextual]        rules line                                     |
|                                                                                |
|                  world tags: marks, boats, laylines, tack point                |
| edge pointers <                                               > edge pointers  |
|                                                                                |
| INSTRUMENTS (hero BSP, VMG %)                                          RADAR   |
| TWA  HDG  VMG                        trim gauges (manual)                      |
| sog cog aws awa heel polar           HELM ------+------ SAIL                   |
+-------------------------------------------------------------------------------+
```

- **Top left, race bug:** the one solid chip: yellow tick, clock (or class and fleet before the start), rank. Under it:
  lap, leg and leg type, then leader gap and the boats ahead and behind.
- **Top centre, alert lane:** before the start the countdown and the four start numbers; in the race the penalty panel
  and the one rules line (stacked, penalty first). Nothing else ever goes here.
- **Top right, wind:** TWS big, a north-up hairline dial with the true wind arrow, TWD, the shift chip. The event feed
  hangs under it, right-aligned, and fades.
- **Bottom left, instruments:** the deck display. Row 1: boat speed (hero) and VMG to target with a meter (target
  tick at 100 %, yellow bar to the value) and target speed and angle. Row 2: TWA, HDG, VMG. Row 3: small values.
- **Bottom right, radar:** heading-up, hairline rings, a soft ink disc (38 %), boats as rule-coloured triangles, the
  next mark as a yellow diamond, laylines, wind arrow outside the ring, range under it.
- **Bottom centre, helm strip:** one hairline for the helm with the command mark in yellow, the sail on the right;
  manual trim adds two short gauges above it; auto trim collapses to "SHEETS AUTO".
- **World:** the next mark's tag (name, distance, ETA, bearing, rounding side, ZONE chip inside the zone), name tags on
  mast tops (paper on ink when there is no relation, solid rule colour when there is), laylines, zone circle, rounding
  arrow, start line, course to the tack point or to the line, penalty turn around your boat. Anything worth pointing at
  that is off screen gets an edge pointer with name and distance.

**Steam Deck (1280 x 800, 16:10):** margins 32 px left and right, 28 px top and bottom. The same layout scaled by 0.82 of
the 1080p sizes (not the 0.74 that pure height would give), so text stays at 11 px or more and numbers at 18 px or
more on the 7" screen. The extra height of 16:10 goes to the world. The tertiary row keeps four values (SOG, COG, heel,
polar %); AWS and AWA move to an instrument page on a button. For 16:10 desktops use the Deck layout at 1080p scale.

## 6. Always on screen vs contextual

| Always (Standard preset) | Contextual |
| --- | --- |
| Race bug: clock, rank, lap and leg | Start panel: sequence only, gone when the boat has started (OCS keeps it with the return instruction) |
| Wind: TWS, TWD dial | Shift chip: on a beat or run when the shift is 2° or more |
| Instruments rows 1 to 3 | Leader gap, ahead and behind: after the start |
| Next mark tag or its edge pointer | Laylines and the tack point: beats and runs, assist allowing |
| Radar | Zone circle: within 6 L of the next mark; ZONE chip inside it |
| Helm strip | Rounding arrow: from 500 m out; far marker beyond 500 m |
| | Name tags: boats within 150 m or with a relation; edge pointers for those off screen |
| | Rules line: while a condition of `hud.md` §11 holds, one line |
| | Penalty panel and the turn on the water: while a penalty is pending or being taken, and 5 s after |
| | Live order: within 6 L of a mark and 6 s after each rounding; full ranking on Tab |
| | Trim gauges: manual trim only |
| | Feed: 6 lines, 8 s each; signal banner 3 s under the countdown |
| | Sail hint (Full preset): one line under the helm strip |

## 7. Motion

- **Honest data.** Numbers refresh at 4 Hz with no tween; needles, meters and world graphics move every frame.
- **Enter:** 180 ms, fade plus 12 px slide from the nearest edge. **Exit:** 240 ms fade. No scale pops, no bounce,
  no overshoot.
- **Alerts:** the penalty panel and banners wipe in from the left over 200 ms, hold, and fade out. Warning pulse 2 Hz
  (opacity 100 to 55 %), breach 4 Hz plus outline.
- **World:** laylines draw out from the mark over 400 ms when a leg starts; the zone circle fades in over 300 ms at
  6 L; the rounding arrow does not move.
- **Start:** the last 10 s the countdown shows tenths and turns yellow; at the gun the line flashes paper once (300 ms)
  and turns green for boats still to start.
- A reduced-motion setting replaces pulses with a steady outline and removes slides.

## 8. What changes from the current HUD

- Eight grey panels go. Corners keep four blocks on scrims; one ink chip (the race bug) remains.
- One family (Barlow Semi Condensed, tabular) in three sizes instead of one system font at one size.
- Labels move above values; units get small and dim.
- The start panel becomes a countdown hero with four numbers under it; the start line, your course to it and the
  favoured end are drawn on the water.
- Next-mark data moves from a side panel onto the mark; the layline distance becomes a tack point on the water.
- Laylines become thin ribbons with a constant-width centre line, fading away from the mark, instead of thick pastel
  bands.
- The penalty panel gets a ring, tack and gybe ticks, and a deadline bar, and the turn is drawn around the boat.
- Other boats get name tags in rule colours; the radar gets hairline rings and a yellow own boat.
- The helm and trim panel shrinks to a hairline strip that hides the sheet gauges under auto trim.
- The results table becomes a full-screen broadcast table with place numerals, AI level tags and series columns.

## 9. Open questions for the owner

1. Signature colour: yellow (`mark`) for the course and for you. Alternative: keep yellow for marks only and give the
   player a separate accent.
2. Corner stack (recommended) or the broadcast strip (alternative in the mock-ups)?
3. Instrument pages: is a button that swaps the third row (for example AWS and AWA vs SOG and COG) acceptable, or must
   every value always be visible? Deck needs one of the two.
4. The penalty turn drawn on the water: keep it in every camera, or only in chase and aerial?
5. Name tags: skipper names (as mocked) or boat names, and within what range?
