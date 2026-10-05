# Race HUD: design direction

*WM-016.27, phase 1b (mock-ups for the owner's review, revised after the first round). The numbers, states and
formats stay as `docs/specs/hud.md` defines them; this file is layout, type, colour, density and motion. Mock-ups:
`hud_mockups.html` (open it in a browser; the frames are in `frames/`). The first version is kept as
`hud_mockups_v1.html`.*

Owner feedback on v1 (2026-09-29): keep the overlays on the water as they are; the instruments had too much going on,
especially on the Deck; give an option to show more or less data; a bit more instrument feel, just a bit. Hence §6
(density levels) and §4.1 (instrument pages).

**In one line:** the precision of a mast display (big exact numerals, units small, nothing decorative) set in the
language of a race broadcast (strong type, a few bold colours that mean something, hairlines, data on the scene and
on the water, not in boxes).

## 1. Principles

1. **The numeral is the interface.** Every value is a big tabular numeral in a cell, with a small caps label top left,
   the unit top right and the number right-aligned at the bottom, as a deck display does it. Nothing sits inline as
   "BSP 5.3 kn".
2. **Hierarchy is decided, not implied.** Three sizes of numbers, each for a known set of values (§4). Boat speed is the
   hero; the rest earns its size.
3. **No grey boxes.** Instruments sit on faint glass pages (§4.1), everything else on the scene over a soft top scrim
   and a light text shadow. Solid ink is used only for a few small chips: the race bug, name tags, the rules line and
   the penalty panel.
4. **Colour means something or it isn't there.** The chrome is ink and paper. Colour appears only for the course and
   you (yellow) and for the rules colours of `hud.md` §8 (§3 below). If everything is white, nothing needs your attention.
5. **Put it where it belongs.** Mark distance sits on the mark, tack distance on the layline, the start line numbers
   under the countdown, the penalty turn around your boat. Corner blocks keep only what has no place in the world:
   speed, wind, clock, rank.
6. **Always on vs contextual, and the player picks the density.** A small constant frame whose size the player chooses
   (§6); everything else appears when it applies and leaves when it doesn't (§7).
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
| 14 px labels | 11.5 px | Caps labels in instrument cells; 11 px is the floor for any text (smaller sizes clamp to it on the Deck) |

- In instrument cells the unit sits top right in `mist` at label size; the number is right-aligned in a fixed field, so
  `5.3` and `12.4` end in the same place. Outside the pages (mark tag, start numbers, tack point) units follow the
  number at about 22 % of its size: `197 M`, `−5 S`.
- Side letters after angles in the tack colour: `44° P` (red P), `41° S` (green S).
- Signs are true minus signs (`−23 M`). Missing values show `--` as the spec says, never a dash of any other kind.
- Numbers never tween or roll; they change at the spec's 4 Hz refresh. Needles, bars and on-water lines move every frame.

### 4.1 Instrument pages

A bit more instrument, no dashboard:

- **Pages.** The instrument values of each corner are grouped on one page: ink glass from 14 % at the top to 44 % at the
  bottom (no blur, cheap to draw), a 1.5 px hairline along the top edge, 9 px corner ticks (dropped in the build,
  owner 2026-09-29), hairline dividers between cells at 45 % of `hair`. No rounded corners, no bevels, no reflections.
- **Cells.** Label top left, unit top right, value right-aligned at the bottom; the same grid on every page and level.
- **Analogue parts, two only.** The **TWA dial** (bow up; red and green sectors for close-hauled on port and on
  starboard, 20° to 60°; yellow ticks at the target angle of the leg; the true wind as a solid pointer coming in from
  the rim; Data adds the apparent wind as a hollow pointer; a small hull outline in the centre). The **heel bar** in
  Data (centre zero, ±30°, bar in the tack colour to the side that is down). Both move every frame; the numbers beside
  them keep the 4 Hz refresh.
- **Level pips.** Three 7 px squares top right of the page, filled to the level.
- **Pages at 1080p:** Glance 486 x 200 (150 without the cue strip), Race 650 x 246, Data 720 x 298, all anchored at the
  bottom-left margin. The wind page (top right) is 312 x 112.

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
- **Top right, wind page** (Race and Data): TWS cell and a north-up TWD dial cell. The shift chip hangs under it, then
  the event feed, right-aligned, fading.
- **Bottom left, instrument page:** row 1: boat speed (hero), VMG to target (polar % before the start and on reaches)
  with a meter (target tick at 100 %, yellow bar to the value), the TWA dial spanning rows 1 and 2 with the TWA number
  under it. Row 2: heading (Data: HDG and VMG) and target angle with target speed as its unit. Row 3 (Data): SOG, COG,
  AWS, polar %, heel bar.
- **Bottom right, radar:** heading-up, hairline rings, a soft ink disc (38 %), boats as rule-coloured triangles, the
  next mark as a yellow diamond, laylines, wind arrow outside the ring, range under it.
- **Bottom centre, helm strip:** one hairline for the helm with the command mark in yellow, the sail on the right;
  manual trim adds two short gauges above it; auto trim collapses to "SHEETS AUTO".
- **World:** the next mark's tag (name, distance, ETA, bearing, rounding side, ZONE chip inside the zone), name tags on
  mast tops (paper on ink when there is no relation, solid rule colour when there is), laylines, zone circle, rounding
  arrow, start line, course to the line, the tack point (a ring and its label; no line from the boat to it, owner
  2026-10-05), penalty turn around your boat. A boat the player picks gets a hairline bracket and a small card
  (`hud.md` §16.4.1, §16.7). Anything worth pointing at that is off screen gets an edge pointer with name and distance.

**Steam Deck (1280 x 800, 16:10):** margins 32 px left and right, 28 px top and bottom. The same layout scaled by 0.82 of
the 1080p sizes (not the 0.74 that pure height would give), text clamped to 11 px, numbers 18 px or more on the 7"
screen. The extra height of 16:10 goes to the world. Default density Glance (§6); Race and Data use the same pages at
the same scale, so the v1 idea of a separate button page for AWS and AWA is dropped. For 16:10 desktops use the Deck
layout at 1080p scale.

## 6. Instrument density

The player cycles three levels with one key: **Glance**, **Race**, **Data**. Density decides how many instrument
values show; it never hides a contextual item (countdown, OVER and OCS, rules line, penalty panel, own-event banners,
protest and hail prompts) or anything on the water (start line and course to it, mark tag, laylines, tack or gybe
point, zone circle, rounding arrow, name tags, edge pointers, penalty turn). The radar, the helm strip and, under manual
trim, the trim gauges show at every level. Density is independent of the assist preset (`hud.md` §14): an item shows
only when both allow it.

| Phase | Glance | Race | Data |
| --- | --- | --- | --- |
| Pre-start | Boat speed, TWA dial. Start block: countdown and burn with the late/early bar, the flag rule in one line. No race bug, no wind page | + polar % with meter, heading, target speed. Full start block (line, to line, burn, bias, flags). Wind page. Race bug (class, fleet). Feed 3 lines | + VMG, AWA, SOG, COG, AWS, heel bar. Race bug adds laps and legs. Feed 6 lines |
| Upwind | Boat speed, TWA dial with target ticks, VMG % with meter (the one cue). Race bug: clock and rank | + heading, target angle and speed. Wind page, shift chip. Lap and leg line. Feed 3 lines | + VMG, AWA pointer and value, SOG, COG, AWS, polar %, heel bar. Leader gap, ahead and behind. Feed 6 lines. Sail hint (assist allowing) |
| Downwind | As upwind with the run targets; on a reach the cue is polar % and the dial has no target ticks | As upwind | As upwind |
| Rounding (within 6 L and 6 s after) | Boat speed, TWA dial. Live order cut to ahead, you, behind | + VMG %, heading, target. Full live order. Wind page, shift chip | + all of Data upwind; live order with rounded tags and the estimate note |
| Penalty | Boat speed, TWA dial; the panel and the turn on the water carry the rest | As the leg it is taken on | As the leg it is taken on |

In Glance the radar is drawn at 72 % size without its range and orientation labels, the helm strip loses its labels,
and the feed shows only the player's own events.

- **Defaults:** Race on 16:9; Glance on the Steam Deck and any screen under 900 px tall. The last choice is remembered
  per device.
- **Control:** keyboard `G`; gamepad and Deck a tap of `View` (a hold stays the ranking list); the Deck template also
  binds `R4`. `F10` (hide the HUD) is unchanged. After a press an "INSTRUMENTS · RACE" chip shows above the page for
  1.5 s (enter 180 ms, exit 240 ms); the pips on the page show the level at all times.
- **Spec work when approved:** a `hud_density` action in `controls.md` §2 and §3, and a density column next to the
  assist presets in `hud.md` §14.

## 7. Always on screen vs contextual

| Always (at the Race density, Standard assist) | Contextual |
| --- | --- |
| Race bug: clock, rank, lap and leg | Start panel: sequence only, gone when the boat has started (OCS keeps it with the return instruction) |
| Wind page: TWS, TWD dial | Shift chip: on a beat or run when the shift is 2° or more |
| Instrument page rows 1 and 2 | Leader gap, ahead and behind: after the start (Data) |
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

## 8. Motion

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

## 9. What changes from the current HUD

- Eight grey panels go. Instruments and wind sit on two faint glass pages, the rest on the scene; one ink chip (the race
  bug) remains.
- Three instrument densities replace one fixed set of values.
- One family (Barlow Semi Condensed, tabular) in three sizes instead of one system font at one size.
- Labels move above values; units get small and dim; a compact TWA dial and a heel bar are the only analogue parts.
- The start panel becomes a countdown hero with four numbers under it; the start line, your course to it and the
  favoured end are drawn on the water.
- Next-mark data moves from a side panel onto the mark; the layline distance becomes a tack point on the water.
- Laylines become thin ribbons with a constant-width centre line, fading away from the mark, instead of thick pastel
  bands.
- The penalty panel gets a ring, tack and gybe ticks, and a deadline bar, and the turn is drawn around the boat.
- Other boats get name tags in rule colours; the radar gets hairline rings and a yellow own boat.
- The helm and trim panel shrinks to a hairline strip that hides the sheet gauges under auto trim.
- The results table becomes a full-screen broadcast table with place numerals, AI level tags and series columns.

## 10. Open questions for the owner

Answered by the v1 round: the overlays on the water stay; instrument density is a player option (§6), which also settles
the v1 question about instrument pages on a button.

1. Signature colour: yellow (`mark`) for the course and for you. Alternative: keep yellow for marks only and give the
   player a separate accent.
2. Level names: Glance, Race, Data. "Minimal, Standard, Full" would clash with the assist presets of `hud.md` §14,
   which already use those words for something else.
3. Glance upwind shows VMG % as its one cue. The alternative is the shift (lift or header); VMG % was chosen because it
   is always meaningful, and the shift chip joins at Race.
4. The glass page: is 14 to 44 % ink the right amount, or should it be lighter still (the numbers keep their text
   shadow either way)?
5. Gamepad control: a tap of `View` (hold stays the ranking). If the ranking is set to toggle, the density needs its own
   button; which one?
6. The penalty turn drawn on the water: keep it in every camera, or only in chase and aerial?
7. Name tags: skipper names (as mocked) or boat names, and within what range?
8. Downwind has no mock-up frame yet (no run frame was rendered); it follows the upwind layout with the run targets.
