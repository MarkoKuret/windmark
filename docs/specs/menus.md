# Menus

The front end's menus before the phase 4 online screens: the main menu, the session setup it writes, the settings
the in-race pause menu and the race end with its results screen (§5). The session setup is `GameSetup` (`game/scripts/game_setup.gd`); the options are those
of `controls.md` §6, `cameras.md` §3 and §6, `hud.md` §14, `water_render.md` §7 and `audio.md` §1.1.

## 1. Main menu

The project's main scene. Items, top to bottom: **Continue**, **Quick race**, **Free sail**, **Settings**,
**Quit**.

- **Continue** starts the last remembered session again (§1: the setup Start last wrote, its mode, quick race or
  free sail, with a new seed), straight to the sail scene, and has the focus when the menu opens. A line under it
  says what it starts (`Quick race · Practice Waters · 10 boats` or `Free sail · Practice Waters`). Hidden on the first
  launch, and whenever the remembered setup cannot start any more (a class, venue or course no longer on disk);
  the focus then starts on Quick race.
- **Wordmark**: the game's logo, `WINDMARK` with the tagline bar under it (§1.2), in the top-left corner. It is
  one scene (`scenes/menu/wordmark.tscn`), so a later logo replaces it without touching the menu.
- **Version**: the bottom-right corner shows the build, small and dim: `v<version>` from the project settings
  (`application/config/version`), followed by the export stamp when the build has one (`game/build.txt`, written
  by `tools/stamp_build.sh` before an export from `git describe --tags --always --dirty`), else `dev`.
- **First launch**: the first time the game starts (the settings file has no `menu.welcomed`), a short screen comes
  before the menu: a heading, two rows,
  **Steering** (the helm key mode of `controls.md` §5.2: Set and hold or Hold to steer; the controls preset, since
  the gamepad needs no choice) and **Quality** (Low, Medium, High; the settings' value preselected, on a first
  start the device default of §3), the help line of the focused row (§3), and **Let's sail** (keeps them, the
  primary action) and **Skip** (keeps the defaults, the device's for quality; Esc or B too). Either
  saves the settings with `welcomed` set, so it shows once.

- **Quick race**: class, sail number, venue, course, fleet size, AI level, weather (and in Custom: wind speed, wind
  direction, shifts, gusts), time and sky, then **Start**, on one screen, the **race card** (§1.1).
- **Free sail**: class, sail number, venue, weather, time and sky (as on the race card), then **Start** (in the card's footer, as
  on the race card, without the preview or the briefing).
- Lists come from the data on disk: classes from `data/classes/*.boat.json` (name from the file), venues from
  `data/venues/*.venue.json`, courses from `game/data/courses/<venue>/*.course.json` that list the chosen class
  in their `classes` (a course without `classes` suits every class). A venue without a course for the class cannot
  start a quick race.
- **Sail number**: the player's boat, from the boats of the class's livery file (`data_format.md` §8.4, in file
  order, shown as sail number and name, for example `7  Kestrel`); the list follows the class. Every boat wears the
  class livery and sails; the AI boats get the other sail numbers and names by the fleet rule of
  `data_format.md` §8.4.
- Ranges: fleet size 2 to 40 boats including the player (default 10); AI level Easy, Intermediate (default),
  Expert, Pro (`ai.md` §13).
- **Weather**: **Local** (default), **Random** or **Custom** (`race.md` §2.1).
  - **Local**: the venue's own conditions, drawn within its ranges from the seed. Nothing to adjust; the card shows
    the full briefing with the Tip.
  - **Random**: a surprise day from everything the venue can produce. Nothing to adjust and **no briefing**, ever:
    the card shows only `Weather  Unknown: read it on the water` (key `briefing.unknown`), and nothing before the
    start or in the race tells the conditions; the player reads them from the instruments and the water. After the
    finish the results screen reveals them (§ results panel, `Today:` line).
  - **Custom**: four more rows. **Wind speed** 4 to 25 kn in 1 kn steps and **wind direction** 0° to 355° in 5°
    steps (defaults: the middle of the venue's range, rounded, and its typical direction rounded to 5°); **Shifts**
    Steady, Stable, Oscillating, Shifty, Unstable (the shift presets of `wind.md` §1); **Gusts** None, Light,
    Moderate, Very strong (the puff presets `none`, `light`, `standard`, `gusty` of `wind.md` §6.1, named after the
    word the briefing gives them). Shifts and Gusts default to the venue's (for an explicit venue shift, the preset
    whose band in §1.3 holds it). The shifts themselves still come from the seed; current, tide and sea stay the
    venue's. The card shows the briefing without the Tip.
  - A venue without `conditions` (`data_format.md` §6.9) offers Custom only, at 12 kn, 0°, Shifty, Moderate.
  - Choosing another venue sets the Custom rows to that venue's defaults and offers its modes (a mode it lacks
    falls back to its first, Custom for a venue without `conditions`).
- **Time** and **Sky**: the light of the session (`water_render.md` §4.5), two rows after the weather rows.
  - **Time**: `Venue default` (the venue look file's hour, `data_format.md` §6.11) or a clock time in 30 min steps
    across the venue's race window (`VenueLook.race_window`: at Practice Waters 10:00 to 18:30), shown as `14:30`.
  - **Sky**: `Venue default` (the look file's conditions), `Clear`, `Fair`, `Hazy` or `Overcast`.
  - With **Random** weather both rows show `Surprise` and do not step: the race seed draws the hour and the
    conditions (`water_render.md` §4.5). Leaving Random gives back the earlier picks.
  - Choosing another venue rebuilds the Time list for its window and keeps the time when the window has it, else
    `Venue default`. Both are remembered like the other rows (a remembered time the venue's window lacks falls back
    to `Venue default`).
  - Start writes `GameSetup.light_time` (the hour, or −1 for `Venue default` and in Random) and
    `GameSetup.light_conditions` (the conditions, or `""` for `Venue default` and in Random).
- **Start** fills `GameSetup.current()` (mode `race` or `free`, the weather mode and the Custom picks, and the card's
  race seed) and changes to the sail scene, which reads it and resolves the weather once (`race.md` §2.1). The last
  choices are remembered in the settings file (§3) for the next visit; a remembered choice that is no longer
  offered (a venue, class or mode gone) falls back to the default (Practice Waters, Local), else the first.
- **Race seed**: the card draws the race seed (non-zero, from the clock) when it opens and again after each start,
  and computes the briefing for it (§1.3), so the tide the briefing names is the one the race gets. Starts without
  the card (Continue, Race again) take a new seed from the clock and show no briefing.
- **Backdrop** (§4): the live sail scene behind the menu.
- Rules scenarios (`race.md` §14) have no menu item: they start from the command line of the sail scene,
  `--scenario=<id>`, which sets `GameSetup` mode `scenario` with the scenario id.

### 1.1 Race card

The quick race is one screen: a header (the heading alone), the body and a footer.

- **Body**: the setup rows on the left, the **briefing** (§1.3, Local and Custom) and the **preview** on the right; when the page is narrower than 760 px
  (logical, after the UI scale: a large UI scale on the Steam Deck, a narrow window) the preview goes under the
  rows. The body scrolls with the focus when it does not fit; the header and the footer never scroll.
- **Briefing**: the venue briefing of §1.3, at the top of the right column above the course map, following the
  rows as they change (venue, course, weather and the Custom rows). It moves with the preview when the preview goes
  under the rows. In Random its place holds the one `Unknown` line.
- **Preview**: the **course map** with its caption, following the rows as they change (no fleet summary: the
  fleet, AI level and boat are the rows beside it). In Local the
  map's wind arrow shows the venue's typical direction and the middle of its speed range; in Custom the chosen
  values; in Random the course is drawn on the venue's typical direction with no wind arrow and no numbers.
  - The course map is drawn from the course file (`courses.md`) on a dark chart (the HUD's `ink`), north up: the
    marks resolved as `courses.md` §3 resolves them with the course axis on the chosen wind direction, at the
    file's distances (the preview skips the scaling of §6.3, so it shows the course's shape, not its exact size);
    rounding marks as yellow diamonds (the HUD's `mark`, the course colour), other buoys as small paper dots, the
    committee and mark boats as small paper hulls; the start line (between its two ends) as a dashed paper line, the
    finish line as a checkered one; the course as a faint hairline from the start through the sequence's marks and
    gates to the finish; the wind as an arrow in the top-right corner, blowing the way the wind goes, with the speed
    and the direction under it (`12 KN  000°`), and a small N.
  - Under the map: the laps and legs (`2 laps, 6 legs`), muted; the course's name is the Course row's.
- **Footer**: **Start race**, the screen's one primary action (a menu-item sized yellow button, §4), always
  visible, and under it the reason it cannot start when it cannot (a venue without a course for the class), in
  red.
- Fits 1280 × 800 at every UI scale (80 % to 130 %) and the portrait capture window; the keyboard and the gamepad
  reach every row and Start (down from the last row is Start, up from Start the last row).

### 1.2 Logo and app icon

The logo is a wordmark only (no symbol, no badge). Colours: cream `#F4F1E8`, navy `#1A2A3A`, yellow `#FFD23F` (the
menus' cloth, navy and accent, §4).

- **WINDMARK**: Barlow Semi Condensed Black Italic (weight 900), all caps, letter spacing +3 %. Cream fill with a
  navy outline of 3 % of the font size (4 px at 132 px, 2.3 px at 76 px), and two hard (unblurred) drop shadows
  stacked behind it, each the outlined letters in one colour: navy offset (+3.8 %, +3.8 %) of the font size and
  yellow offset (+7.6 %, +7.6 %), the yellow one furthest back. In Godot: the outline is the label's outline
  (`outline_size` is 4 times the visible width: the engine strokes `outline_size / 4` px each side), the shadows
  are two copies of the label behind it (yellow, then navy, each with the outline in its own colour). Offsets and
  sizes are whole pixels, so it stays crisp at every UI scale.
- **Tagline bar**: `REGATTA SAILING SIMULATOR` in Barlow Semi Condensed ExtraBold Italic (800), tracking +30 %, at
  22 % of the WINDMARK size, navy on a yellow parallelogram slanted 14° (the text keeps its own italic, no extra
  slant), with a hard navy shadow offset 5.3 % of the WINDMARK size (4 px at 76 px). The bar starts under the left
  edge of WINDMARK, 4 % of its size below the yellow shadow.
- **Main menu**: WINDMARK at 76 px, the lockup 368 x 97 px, top-left. It scales down (a smaller font size, not a
  scaled image) to fit the window's width inside the menu's margins, and beside the page it leaves the race card
  its two columns (760 px, §1.1) when that costs it at most 10 % (73 px at 1280 x 800 and 100 % UI scale). It fits
  1280 x 800 at 80 % to 130 % UI scale and the portrait capture window.
- **App icon**: the owner's art, `docs/branding/app_icon_1080.png` (outside `game/` so it does not ship; 1080 x 1080, a rounded square with a
  transparent outside), is the master. Made from it (`tools/branding/make_icons.py`): `app_icon_512.png` (the
  project icon, `application/config/icon`, and the window icon), `app_icon_256.png`, `app_icon.icns` (macOS:
  `application/config/macos_native_icon`, the dock icon) and `app_icon.ico` (Windows, 16, 32, 48, 64, 128 and
  256 px: `application/config/windows_native_icon`). There are no export presets yet: when they are set up, the
  macOS preset's `application/icon` is `res://branding/app_icon.icns` and the Windows preset's
  `application/icon` is `res://branding/app_icon.ico`.
- Everything about the brand (files, colours, fonts) is listed in `docs/BRANDING.md`.

### 1.3 Venue briefing

A short, standard briefing of the conditions the race will have, on the quick race card only (not on the loading
screen, the free sail card or before the start), in the Local and Custom weather modes; Random has none (§1). Fixed lines in a fixed order, fixed rating words chosen by the
thresholds below from the venue's numbers (`data_format.md` §6.7) and the card's choices, plus one hand-written Tip.
Computed in the menu when a row changes; it reads exactly the settings the race will resolve (`race.md` §2.1), so
every line stays true for the race that starts.

```
SOLENT · Strong tide
Wind     10-16 kn from the SW
Shifts   Stable: small, slow (4°)
Gusts    Light: to +15 %, frequent
Current  Strong, 1.5 kn, flooding (sets E)
Sea      Flat to chop
Light    13:00, fair
Tip      The stream runs hardest mid-channel; cheat it along the shore.
```

Layout: a box on the course map's dark chart colour (the HUD's `ink`): the header line in the card's heading
style, then the labels in one column (dim) and the values beside them (paper), one line each; the Tip may wrap to
two lines. No em dashes anywhere in it. In Random the box holds the one line `Weather  Unknown: read it on the
water`.

**Inputs.** `S = [s0, s1]` the wind speed (Local: the venue's range; Custom: `[v, v]`), `θ` the direction (Local:
the venue's `from`; Custom: the chosen one), the shift and puff values (Local: the venue's after presets; Custom: the
chosen presets), the venue's current, tide and sea values
(`race.md` §2.1), the chosen course's `T_race` and `t_gun` (`race.md` §2.1; the card's sequence and
`free_sailing_s`), and the card's race seed (§1), which fixes the tide's phase.

**Number formats.** Knots: speeds as whole knots (`round_half_even`), current to 0.1 kn. Degrees: whole degrees.
Compass: 8 points, `N NE E SE S SW W NW`, point `round_half_even(deg / 45) mod 8`. Percentages: whole percent.
Ranges join with a hyphen (`10-16 kn`); equal ends show one value.

| Line | Text | Source and rule |
| --- | --- | --- |
| header | `<NAME> · <tag>` | venue `name` in capitals, a middle dot, `briefing.tag` (`data_format.md` §6.8) |
| Wind | `<s0>-<s1> kn from the <point>` | `S` and `θ`; e.g. `14 kn from the NE` with an explicit speed |
| Shifts | `<word>: <size>, <pace> (<A>°)` and, with a trend, `, veers <N>°` or `, backs <N>°` | `A` = `shift_amplitude`, `H` = `shift_hold_max`; `steady` alone when `A < 1.5°`; trend below |
| Gusts | `<word>: to +<g> %, <spread>`, or `None` | `g = min(puff_cap_up, puff_strength_max)`; `None` when puffs are off |
| Current | `<word>, <c> kn` and `, flooding (sets <point>)` or `, ebbing (sets <point>)` (a tide), or `, sets <point>` (a uniform current only); `Slack, turning` (a tide near slack); or `None` | `c` below |
| Sea | `<word>` or `<word> to <word>`, and `, swell <hs> m from the <point>` for each swell with `hs ≥ 0.3 m` | wind-sea `Hs` at `s0` and `s1` (below) |
| Light | `<HH:MM>, <conditions>` | the hour and the conditions the race will have: the Time and Sky rows, or the venue's defaults for `Venue default` (§1); the conditions word in lower case |
| Tip | `briefing.tip` | Local only (a tip is written for the venue's own weather); never in Custom, and none for a venue without `briefing` |

**Shifts.** Word by `A`: Steady `< 1.5°`, Stable `< 5.5°`, Oscillating `< 11.5°`, Shifty `< 20°`, Unstable
`≥ 20°` (the presets of `wind.md` §1 fall in their own band). Size by `A`: small `< 5.5°`, medium `< 11.5°`, large
`< 20°`, very large `≥ 20°`. Pace by `H`: slow `≥ 100 s`, regular `≥ 55 s`, fast `< 55 s`. Trend: the rotation during
the race, `N = |trend(t_gun + T_race) − trend(t_gun)|` (`wind.md` §3) in whole degrees, shown when the rounded `N`
is at least 3°, also after `Steady`; veers
for a positive rate, backs for a negative one. The oscillation is not rated (at most ±3°, texture).

**Gusts.** Word by `g`: Light `< 0.18`, Moderate `< 0.28`, Strong `< 0.40`, Very strong `≥ 0.40`. Spread by the
puff cover `k = puff_count · π · ((puff_diameter_min + puff_diameter_max) / 4)² / puff_tile²`: scattered `< 0.15`,
frequent `< 0.35`, everywhere `≥ 0.35`.

**Current.** The tide at the start signal of the race the card will start: the settings resolved for the card's
seed (`race.md` §2.1) give `τ = tide_scale · cos(2π · ((t_gun + tide_phase_ms) mod P) / P)` (`wind.md` §7; `τ = 0`
without a tide), the tidal stream `c_t = |τ| · ref_speed` and `c = |uniform| + c_t` (`data_format.md` §6.3; 0 for a
missing part), in knots. The tide keeps the real period, so the stream named holds through the race (in 20 minutes
`τ` moves by at most a sixth of the scale, and that only near slack). Word: None `< 0.2 kn` (the line is `None`), Light `< 0.6`, Moderate `< 1.2`,
Strong `< 2.0`, Very strong `≥ 2.0`. With a tide:
- `c_t < 0.3 kn` (near slack: about 50 minutes around each turn at the Solent's 1.5 kn) and `|uniform| < 0.2 kn`:
  `Slack, turning`; near slack with a uniform current the line is the uniform one below;
- otherwise `, flooding` for `τ > 0` (the field's own direction, the flood, `venues.md` §5.4) or `, ebbing` for
  `τ < 0`, then ` (sets <point>)` from `ref_to` (flooding) or `ref_to + π` (ebbing); a file without `ref_to` gives
  no set.

A uniform current alone gives `, sets <point>` from `current_to`.

**Sea.** `Hs` of the wind sea by `sea.md` §2 at the speed and the venue `fetch`, times `sea_scale`, at open-water
exposure. Word: Flat `< 0.25 m`, Chop `< 0.5 m`, Moderate `< 1.0 m`, Rough `≥ 1.0 m`; one word when `s0` and `s1`
give the same. Swell heights to 0.1 m, times `sea_scale`.

**Strings.** Every fixed text comes from the front end's string table by key, English as the source:
`briefing.label.<wind|shifts|gusts|current|sea|tip>`, `briefing.word.shifts.<steady|stable|oscillating|shifty|unstable>`,
`briefing.size.<small|medium|large|very_large>`, `briefing.pace.<slow|regular|fast>`,
`briefing.word.gusts.<none|light|moderate|strong|very_strong>`, `briefing.spread.<scattered|frequent|everywhere>`,
`briefing.word.current.<none|light|moderate|strong|very_strong>`, `briefing.tide.<flooding|ebbing>`,
`briefing.word.sea.<flat|chop|moderate|rough>`, `compass.<n|ne|e|se|s|sw|w|nw>`, `briefing.unknown` (Random),
`briefing.label.weather` (the Random line's label), `weather.mode.<local|random|custom>`,
`weather.<label|wind_speed|wind_from|shifts|gusts>` (the row names), `weather.shifts.<preset>`,
`weather.gusts.<none|light|moderate|very_strong>`, `briefing.trend.<veers|backs>`, and one template per line part
so a language can reorder them: `briefing.header` (`{name} · {tag}`), `briefing.line.wind` (`{lo}-{hi} kn from the
{point}`), `briefing.line.wind_one` (`{v} kn from the {point}`), `briefing.line.shifts`, `briefing.line.trend`,
`briefing.line.gusts`, `briefing.line.current`, `briefing.line.current_tide` (`{line}, {state} (sets {point})`),
`briefing.line.current_tide_noset` (`{line}, {state}`), `briefing.line.current_slack` (`Slack, turning`),
`briefing.line.current_sets`,
`briefing.line.sea_range`, `briefing.line.swell`, `briefing.label.light`, `briefing.line.light` (`{time}, {sky}`)
and `briefing.sky.<clear|fair|hazy|overcast>`; the Time and Sky rows' `light.time`, `light.sky`,
`light.venue_default`, `light.surprise` and `light.sky.<clear|fair|hazy|overcast>`; the results' `results.today` (`Today: {wind} · {shifts} ·
{gusts}`), `results.today.gusts` (`{word} gusts`) and `results.today.no_gusts`. The table is
`game/scripts/text/strings.gd`. The venue's
name, tag and tip come from the venue file with its translations (`data_format.md` §6.8).

## 2. Pause menu

Opened by `pause_menu` in a race or free sail (`controls.md` §7). Offline the simulation stops while it is open.
A card with the heading `PAUSED` and the items, menu-item sized (§4).
Items: **Resume** (the focus when it opens), **Restart** (the same session from its start), **Retire** (a quick race only, from the warning
signal until the player's race is over, `race.md` §6.4: red, as a destructive action; the first press turns it into
`Retire? Press again` for 3 s and a second press within them retires the boat and closes the menu), **Settings**,
**Quit to menu**. `pause_menu` again resumes. Over the results screen (§5) it works the same, Retire hidden, and
Resume goes back to the results. While it is open the boat's controls are held as in `controls.md` §7 (held let-fly and
hold-to-steer keys count as released). Settings changed here apply to the running scene when the settings
screen closes.

## 3. Settings

Five sections: **Controls**, **Cameras**, **HUD**, **Graphics**, **Audio**. A change applies at once where the
game has the setting and is saved when the settings screen closes, to one file per player
(`user://settings.cfg`, a Godot ConfigFile with a `version`); the capture preset alone is for the session only (below).

| section | settings |
| --- | --- |
| Controls | helm key mode, stick dead zone, stick curve, sheet key rate, hold or toggle for let fly, fine helm, rankings and camera boost, sheet turns auto trim off, vibration (off, 10 % to 100 %), the bindings (rebinding, below) |
| Cameras | camera and look speed, invert orbit X and Y, invert look X and Y, onboard heel follow, smooth switch, reduced motion |
| HUD | assist preset (Full, Standard, Minimal; online lobbies may force a lower one), instruments (Auto, Glance, Race, Data: the density of `hud.md` §16.1; Auto picks the device default, the `hud_density` key stores its choice here), UI scale (80 % to 130 %, `hud.md` §16.2.2), colour-blind palette (standard, deuteranopia, protanopia, tritanopia: `hud.md` §16.2.1) |
| Graphics | quality (Low, Medium, High: the tiers of `water_render.md` §7, default Medium or the device default, below), render scale (Auto, 50 %, 67 %, 75 %, 85 %, 100 %; default Auto or the device default; below), display (windowed, fullscreen), vsync, frame rate limit (off, 30, 60, 90, 120, 144), capture preset (Off, Portrait 9:16; below) |
| Audio | master, effects, signals (the race signals and the hails), ambience, interface volumes, 0 to 100 % (default 100 %, master 80 %) |

Only settings the game reads are offered. Captions (`controls.md` §6) and a separate voice volume come back when
the audio has caption lines and hail recordings (`audio.md` §8); a settings file from an older build that has them
keeps its other values, and the next save drops them (unknown keys are ignored on load).

**Window mode.** The display setting is the player's: the game sets the window mode at its start (from the settings file) and when the display or capture setting changes, never when a race, free sail or the menu opens. Entering or leaving fullscreen through the system (the window's green button on macOS, a system shortcut) becomes the new display setting and is saved at once, so the game never puts the old mode back. A new windowed game opens at 1280 × 800 (the Steam Deck's size; the system may cap it to the screen). While the engine loads, the boot splash shows the logo on navy (`game/branding/boot_splash.png`, background #1A2A3A).

**Reset section** restores the section's defaults (in Controls, the options; the bindings have their own reset;
in Graphics, the device defaults below).

**Device defaults** (WM-101, `PERFORMANCE.md` G1). At the first start (no settings file) the game picks quality and
render scale from the graphics adapter, so a cheap laptop starts on a frame rate it can hold; the player can change
both at once. The adapter's name and vendor (`RenderingServer.get_video_adapter_name()` and `_vendor()`) and the
RenderingDevice's device type (integrated, discrete, CPU; none on the Compatibility renderer) are read once:

| adapter | examples | quality | render scale |
| --- | --- | --- | --- |
| Steam Deck (the `SteamDeck` environment variable Steam sets, or an AMD Custom GPU 0405 / 0932, VanGogh or Sephiroth) | | Low | Auto (native on its 1280 × 800 screen) |
| Apple (Apple silicon: the adapter name says Apple) | Apple M1 to M5 | Medium | Auto |
| integrated Intel (any Intel but an Arc A or B card) | Intel UHD 620, Iris Xe, HD Graphics, Arc Graphics (Core Ultra) | Low | 67 % |
| integrated AMD (a Radeon whose name ends in `Graphics`, or a number with M or S and no RX or Pro) | Radeon Graphics, Radeon Vega 8 Graphics, Radeon RX Vega 10 Graphics, Radeon 780M | Low | 67 % |
| other integrated or software (Adreno, Mali, PowerVR, llvmpipe, SwiftShader, Microsoft Basic Render, or device type integrated or CPU) | | Low | 67 % |
| discrete (NVIDIA, AMD RX or Pro, Intel Arc A or B, or device type discrete) | GeForce RTX 3060, Radeon RX 6600 | Medium | Auto |
| unknown (headless, no name) | | Medium | Auto |

A settings file that exists keeps the player's values; the device defaults are not applied again (Reset section in
Graphics and Skip on the first-launch screen use them).

**Help line.** Under the rows, one line of help for whatever has the focus, only where the name does not say it
all: what the setting does, what its values mean, and for a binding how to change it or which action it conflicts
with. Self-explanatory rows (the volumes but effects, signals and ambience, display, frame rate limit, UI scale, the
orbit inversions, camera speed, sheet key rate) and the footer buttons have none; the line stays empty.

**Footer.** **Reset section** (red) on the left and **Done** (the primary action, saves and goes back) on the
right, both footer-action sized (§4).

**Where each setting goes.** Every setting is applied where the game has it: the controls' options to the boat's
controls (`PlayerControls`); rankings hold or toggle to the HUD's ranking list (toggle: `Tab` or a `View` press
opens and closes it, and `View` then no longer cycles the density, `controls.md` §3); camera boost hold or toggle to
the free camera (toggle: a press turns the boost on and the next off); vibration to the gamepad rumble of
`controls.md` §6 (scaled by the setting, none at Off, only while the player sails); the cameras' options to the
camera rig; assists, density and the colour-blind palette to the HUD (`hud.md` §16.2.1); UI scale, display,
render scale and the capture preset to the window; quality to the sea and sky; the volumes to the audio buses
(signals to the `race` and `voice` buses).

**Rebinding** (the Controls section, `controls.md` §3 and §6). Under the options, a **Bindings** list: one row per
action of `controls.md` §3, each with three slots, **Key 1**, **Key 2** (keyboard or mouse) and **Pad** (a
gamepad button, or a stick or trigger direction). (Actions whose defaults have three keyboard or mouse bindings, the zoom keys with the wheel, get a **Key 3**.) On a
row, left and right pick the slot; Enter or A listens for
the new binding (the slot reads `Press a key` or `Press a button`): the next key (with Shift, Ctrl or Alt held, the
combination; a modifier pressed and released alone is that key), mouse button, gamepad button or stick or
trigger pushed past halfway becomes the slot's binding. Esc cancels listening (so Esc itself cannot be bound
there; `pause_menu` keeps it), and so do 5 s without input. Delete, or the gamepad's X on a row, clears the
selected slot. A keyboard or mouse input goes to the picked Key slot (Key 1 when Pad is picked) and a gamepad input
to the Pad slot. **Conflicts**: a binding that another action also has is shown in red on both rows, with the other
action's name in the help line, unless the defaults already give both actions that input (the context pairs of
`controls.md` §3, such as Shift for fine helm and camera boost, or LB for fine helm, camera boost and spectate
previous); the binding is kept, and the player resolves it by rebinding one of them. **Reset bindings** (red, at
the top of the list) puts every action back to the defaults of `controls.md` §3. The bindings apply to the input
map at once and are saved with the other settings when the screen closes, as the actions that differ from the
defaults (section `bindings` of the settings file); at start-up the defaults are put in and the saved ones over
them.

**Render scale.** The 3D view is drawn at that fraction of the window's pixels in each direction and upscaled to
the window; the HUD, the menus and everything 2D stay at the window's native resolution. The upscaler is AMD FSR
1.0 (edge-adaptive upscale and sharpening) on the Forward+ and Mobile renderers, bilinear where FSR is not there
(Compatibility); at 100 % nothing is upscaled. **Auto** picks 67 % when the window is larger than 1920 × 1200
pixels (wider than 1920 or taller than 1200), or larger than 1280 × 800 on a HiDPI screen (the system scales the
screen, as on Retina Macs); otherwise 100 %. Auto then caps the 3D view at **2.33 million pixels** (the
1930 × 1206 measured at 60 fps on tier M on a MacBook Air M1, 2026-10-01): if the chosen scale would draw more, it
drops to `sqrt(2 330 000 / window pixels)`. So a MacBook's 2560 × 1600 Retina screen renders the 3D at 1715 × 1072,
a 3840 × 2160 window at 53 % (2035 × 1145), a 6880 × 2880 window (a 3440 × 1440 monitor that macOS runs at 2×) at
34 % (2359 × 987), and the Steam Deck's 1280 × 800 at full size. Auto is resolved again whenever the display settings
apply and when the window changes size. The setting is independent of the quality tier.

**Capture preset.** For recording vertical clips. **Portrait 9:16** makes the window 1080 × 1920 pixels (windowed,
centred on its screen; on a screen too small for that, the largest 9:16 window that fits its usable area) and the HUD
takes its portrait layout (`hud.md` §16.5); the display row has no effect while it is on and render scale Auto picks
100 % (clips want the full detail). On a HiDPI screen the pixels are the screen's, so a Retina MacBook shows it at
540 × 960 points. **Off** (default) puts the window back to the size it had before and the display setting applies
again. Session only: it is not saved, so the game always starts with it Off in the player's normal window (a
settings file from an older build that has it is ignored); turning it on and off within a session still restores the
window size it had before. Reset section turns it off. The menus work in the portrait window too (they fit its width
at every UI scale; the main menu puts the page under the menu). On a 1080p monitor the window is 590 × 1050 (the
largest 9:16 that fits the usable area); a full 1080 × 1920 capture wants a taller screen, a HiDPI one, or the
command line (`--resolution 1080x1920`).

## 4. Look and input

- A live sea backdrop, a light sail-cloth panel, navy text, one accent colour; no stock widgets' look.
- **Live backdrop.** Behind the main menu runs the sail scene itself (`scenes/sail_test.tscn`, the renderer of a
  race): the example venue (`practice_waters`), the default class, 12 kn from the north with the venue's puffs and
  shifts, a race on the venue's first course with **4 AI boats** of the Expert level and no player (the player's
  entry is taken over by the AI, `--watch`), the seed from the clock. The race starts from its sequence (the boats
  mill round the line, then beat up the course); 30 s after the first boat finishes it starts again. Nothing of the
  game's chrome shows: no HUD, no pause menu, no course guides on the water (laylines, start line, zone circles;
  the marks and the committee boat stay), no player input reaches the scene, and the scene is silent (the menu has
  its own sounds). **Camera**: a slow cinematic drift, not one of the game's cameras: it circles the boat it
  follows at 45 to 70 m and 5 to 11 m above the water, going round it at 1.5° a second, its distance and height
  breathing over 40 s, with the boat a little right of centre (clear of the menu); every 35 s it eases (over about
  4 s) on to the next boat of the fleet. With reduced motion (`cameras.md` §6) the drift is a third of that speed.
  **Cost**: the scene draws at the player's quality tier and render scale (§3; a change in the settings applies to
  the backdrop at once), 4 boats, no HUD and no audio: about two thirds of a race (3.2 ms a frame, 300 draws on an
  Apple M5, `PERFORMANCE.md` M1). On tier **Low** it is lighter still: **2 boats** (the fleet is set when the menu
  opens; a quality change applies to the boat count the next time the menu opens), **no sun shadows** (the boats'
  shadows drawn on the water stay, `water_render.md` §4.7) and the frame rate **capped at 30** while the menu shows
  (or the player's frame rate limit when that is lower); leaving the menu puts the player's limit back. **Fallback**: when the sail scene is not there or does not load (a build without it, a
  missing boat file), the painted backdrop is drawn instead: a hazy sky over a calm sea with long swells and one
  distant sail, drawn without image files. Over either backdrop a soft haze in the top-left corner keeps the
  wordmark and the menu legible.
- **One accent across the game**: the HUD's `mark` yellow (`#FFD23F`, `hud.md` §16.2). Yellow on the cream cloth
  fails as text (1.3:1), so the menus use it as a **fill** with navy text on it (navy `#1A2A3A` on yellow is
  10:1): the focused row or button is a yellow bar with a 5 px navy edge on its left (the edge keeps the focus
  visible against the cloth); each screen's one primary action (Start race, Set sail, Race again, Let's sail, Done)
  is a yellow bar at all times; the selected settings section's underline and the scroll grabber are yellow bars.
  Navy text on the cloth is 13:1, the muted grey `#56646E` 5.4:1.
- **Red** (`#B8361C`, 5.2:1 on the cloth) only for warnings, actions that throw something away (**Retire**,
  **Reset section**, reset bindings) and penalties; Quit and Quit to menu are plain items. A focused red button is a
  red bar with cloth-coloured text (5.2:1).
- **Plain surfaces**: the cloth panels are flat (no shadow, no edge line), headings have no rule under them, and
  there are no sub-lines restating a heading or a row; a screen says a thing once.
- **Sizes**: menu items (main menu, pause menu, Start race and Set sail) Bold caps 28 px, at least 58 px tall with
  22 px side padding; footer actions (Race again, Change setup, Main menu, Done, Reset section, Let's sail, Skip)
  24 px, at least 54 px tall; setting rows at least 46 px tall with 18 px side padding; sentence text (help, notes)
  at least 16 px.
- **Type**: Barlow Semi Condensed, the HUD's family (`docs/design/hud_direction.md` §2). Menu items and buttons:
  Bold, all caps, tracking +6 %. Setting names and section tabs: SemiBold, all caps, tracking +8 %. Values:
  SemiBold with tabular figures, as the HUD numerals. Headings: Bold caps; sentence text (sub-lines, notes, help)
  Medium in sentence case.
- Every screen works with the mouse, the keyboard (arrows, Enter, Esc) and the gamepad (D-pad or left stick, A,
  B), through Godot's built-in `ui_*` navigation actions. On a setting, left and right change the value; Enter or
  A steps it forward. B or Esc goes back one level (Esc in the pause menu resumes, it is `pause_menu`).
- Fits 1280 × 800 (Steam Deck) at every UI scale; lists scroll with the focus.
- **Sounds** on the `ui` bus (`audio.md` §1.1, the Interface volume): a soft tick when the focus moves or a value
  steps, a brighter click on accept (Enter, A, a click), a lower one on back (Esc, B). Made by `tools/soundgen`
  (`ui/focus`, `ui/accept`, `ui/back`), short (under 0.1 s) and quiet (peaks at -12 dBFS or lower).
- Player-facing text has no em dashes.

## 5. Race end

What follows the player's race (`hud.md` §13.1 to §13.3): the finish card, then the results screen over the live
scene, then the next race or the menu.

- **Timeline.** Crossing the line: the finish horn and the finish card in the HUD (5 s), the camera eases into the
  finish view (`cameras.md` §9.1) and the boat sails clear on the autopilot (`race.md` §6.2). Retiring, a
  disqualification or the race closing with her still racing end it the same way with their own card or banner.
  5 s of race time after the end the results screen fades in (0.5 s) and the HUD hides; the race keeps running
  behind it (the other boats finish, the camera drifts).
- **Title**, over the scene in the logo's styles (§1.2, the Wordmark lockup with other words): the place
  (`3RD`) or the code (`RET`, `DNF`, `DSQ`, `OCS`; `NO RACE` when the race was abandoned) as the title, and in the
  tagline bar the result in words: `FINISHED 0:23:32.35  +0:42`, `WINNER 0:23:32.35`, `RETIRED`,
  `DID NOT FINISH`, `DISQUALIFIED`, `RACE ABANDONED`. Top left at 76 px, scaled down by font size to fit.
- **Panel** (cloth, §4), beside the title on the right, or under it when the window is narrower than 1100 px or in
  portrait (there inside the HUD's portrait margins, `hud.md` §16.5), as tall as its content and at most the
  window's height, so the scene stays in view around it: the heading `RESULTS` with one line under it (`Practice Waters · Windward-leeward · 10 boats`; the venue is left out
  when the course's name starts with it), after a Random race a second line `Today: 18 kn from the SW · Shifty ·
  Very strong gusts` built from the race's actual settings with the briefing's rating words (the drawn speed and
  direction, the shift word, the gust word with `gusts`, or `No gusts`; keys `results.today`, `results.today.gusts`,
  `results.today.no_gusts`; Local and Custom show none), the
  **table**, the **summary** under the table, and a footer with the actions. The table and the summary scroll
  (mouse wheel, or up and down on the actions) when they do not fit; the heading and the footer never scroll.
- **Table**: Place, Sail (sail number), Boat (name), Skipper (`You` for the player; an AI boat shows the AI badge,
  `AI · Expert`, here), Time (finish time, `h:mm:ss.ss`, `proj.` after a projected one), Gap (to the winner),
  Code, Points (low point, `race.md` §9). The player's row is the accent: a yellow bar with navy text and the navy
  edge on its left (the focus look of §4); the other rows navy on the cloth, a faint navy tint on every other row.
- **Finishing** (before `RaceClosed`, e.g. while other humans race on): the heading reads `FINISHING` and the line
  `4 of 10 home · results when the race closes`; the rows are the live order (finished boats with place, time
  and gap, the others with their status: `Racing`, `RET`, `DSQ`, `OCS`) and fill in as boats finish; at the close
  it becomes the final table.
- **Summary** (`YOUR RACE`, a heading in caps and label value lines): the items of `hud.md` §13.3 that have data.
- **Actions** in the footer, footer-action sized (§4): **Race again** (primary, the focus when the screen opens): the same setup (class,
  sail number, venue, course, fleet, AI level, wind) with a new seed. **Change setup**: this setup becomes the
  remembered one (§1) and the main menu opens on the race card (§1.1) with it. **Main menu**: the main menu.
- **Input** (§4): left and right move between the actions, Enter or A accepts, the mouse focuses on hover and
  accepts on a click; up and down scroll the table and summary; `pause_menu` opens the pause menu over the screen
  (§2), and when it closes the focus is back on the action it was on.
- **Fit**: 1280 × 800 at every UI scale (80 % to 130 %) and the portrait capture window, every text inside the
  window (the table and summary may scroll); player-facing text has no em dashes.
- **Fades.** Scene changes from the results (Race again, Change setup, Main menu), the pause menu (Restart, Quit
  to menu) and the main menu (Start, Continue) fade to navy (`#0B1620`) over 0.35 s, change, and fade the new
  scene in over 0.45 s; the input is ignored while the screen is dark.
- The results screen is for the player's quick races: not in free sail, the rules scenarios (`race.md` §14) or
  the menu's backdrop (`--watch`).
