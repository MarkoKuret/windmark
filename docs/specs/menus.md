# Menus

The front end's menus before the phase 4 online screens: the main menu, the session setup it writes, the settings
and the in-race pause menu. The session setup is `GameSetup` (`game/scripts/game_setup.gd`); the options are those
of `controls.md` §6, `cameras.md` §3 and §6, `hud.md` §14, `water_render.md` §7 and `audio.md` §1.1.

## 1. Main menu

The project's main scene. Items, top to bottom: **Continue**, **Quick race**, **Free sail**, **Settings**,
**Quit**.

- **Continue** starts the last remembered session again (§1: the setup Start last wrote, its mode, quick race or
  free sail, with a new seed), straight to the sail scene, and has the focus when the menu opens. A line under it
  says what it starts (`Quick race · Example Bay · 10 boats` or `Free sail · Example Bay`). Hidden on the first
  launch, and whenever the remembered setup cannot start any more (a class, venue or course no longer on disk);
  the focus then starts on Quick race.
- **Wordmark**: the game's logo, `WINDMARK` with the tagline bar under it (§1.2), in the top-left corner. It is
  one scene (`scenes/menu/wordmark.tscn`), so a later logo replaces it without touching the menu.
- **Version**: the bottom-right corner shows the build, small and dim: `v<version>` from the project settings
  (`application/config/version`), followed by the export stamp when the build has one (`game/build.txt`, written
  by `tools/stamp_build.sh` before an export from `git describe --tags --always --dirty`), else `dev`.
- **First launch**: the first time the game starts (the settings file has no `menu.welcomed`), a short screen comes
  before the menu: a heading, one line (`Two choices to start with. Both are in Settings later.`), two rows,
  **Steering** (the helm key mode of `controls.md` §5.2: Set and hold or Hold to steer; the controls preset, since
  the gamepad needs no choice) and **Quality** (Low, Medium, High; the settings' value preselected, Medium on a first
  start), and **Let's sail** (keeps them) and **Skip** (keeps the defaults; Esc or B too). Either
  saves the settings with `welcomed` set, so it shows once.

- **Quick race**: class, sail number, venue, course, fleet size, AI level, wind speed, wind direction, then
  **Start**, on one screen, the **race card** (§1.1).
- **Free sail**: class, sail number, venue, wind speed, wind direction, then **Start** (in the card's footer, as
  on the race card, without the preview).
- Lists come from the data on disk: classes from `data/classes/*.boat.json` (name from the file), venues from
  `data/venues/*.venue.json`, courses from `game/data/courses/<venue>/*.course.json` that list the chosen class
  in their `classes` (a course without `classes` suits every class). A venue without a course for the class cannot
  start a quick race.
- **Sail number**: the player's boat, from the boats of the class's livery file (`data_format.md` §8.4, in file
  order, shown as sail number and name, for example `7  Kestrel`); the list follows the class. Every boat wears the
  class livery and sails; the AI boats get the other sail numbers and names by the fleet rule of
  `data_format.md` §8.4.
- Ranges: fleet size 2 to 40 boats including the player (default 10); AI level Easy, Intermediate (default),
  Expert, Pro (`ai.md` §13); wind 4 to 25 kn (default 12) in 1 kn steps, from 0° to 355° in 5° steps (default
  0°, north).
- **Start** fills `GameSetup.current()` (mode `race` or `free`, seed 0: from the clock) and changes to the sail
  scene, which reads it. The last choices are remembered in the settings file (§3) for the next visit.
- **Backdrop** (§4): the live sail scene behind the menu.
- Rules scenarios (`race.md` §14) have no menu item: they start from the command line of the sail scene,
  `--scenario=<id>`, which sets `GameSetup` mode `scenario` with the scenario id.

### 1.1 Race card

The quick race is one screen: a header (the heading and one line), the body and a footer.

- **Body**: the setup rows on the left, the **preview** on the right; when the page is narrower than 760 px
  (logical, after the UI scale: a large UI scale on the Steam Deck, a narrow window) the preview goes under the
  rows. The body scrolls with the focus when it does not fit; the header and the footer never scroll.
- **Preview**: the **course map** and the **fleet summary**, both following the rows as they change.
  - The course map is drawn from the course file (`courses.md`) on a dark chart (the HUD's `ink`), north up: the
    marks resolved as `courses.md` §3 resolves them with the course axis on the chosen wind direction, at the
    file's distances (the preview skips the scaling of §6.3, so it shows the course's shape, not its exact size);
    rounding marks as yellow diamonds (the HUD's `mark`, the course colour), other buoys as small paper dots, the
    committee and mark boats as small paper hulls; the start line (between its two ends) as a dashed paper line, the
    finish line as a checkered one; the course as a faint hairline from the start through the sequence's marks and
    gates to the finish; the wind as an arrow in the top-right corner, blowing the way the wind goes, with the speed
    and the direction under it (`12 KN  000°`), and a small N.
  - Under the map: the course's name, and the laps and legs (`2 laps, 6 legs`).
  - **Fleet summary**: fleet size (the player and the AI boats, `10 boats: you and 9 AI`), the AI level and the
    class.
- **Footer**: **Start race**, always visible, and under it the reason it cannot start when it cannot (a venue
  without a course for the class), in red.
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

## 2. Pause menu

Opened by `pause_menu` in a race or free sail (`controls.md` §7). Offline the simulation stops while it is open.
Items: **Resume**, **Restart** (the same session from its start), **Settings**, **Quit to menu**. `pause_menu`
again resumes. While it is open the boat's controls are held as in `controls.md` §7 (held let-fly and
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
| HUD | assist preset (Full, Standard, Minimal; online lobbies may force a lower one), instruments (Auto, Glance, Race, Data: the density of `hud.md` §16.1; Auto picks the device default, the `hud_density` key stores its choice here), UI scale (80 % to 130 %, `hud.md` §16.2.2), colour-blind palette (standard, deuteranopia, protanopia, tritanopia: `hud.md` §16.2.1), captions (stored; the audio has no caption lines yet, `audio.md` §8) |
| Graphics | quality (Low, Medium, High: the tiers of `water_render.md` §7, default Medium), render scale (Auto, 50 %, 67 %, 75 %, 85 %, 100 %; default Auto; below), display (windowed, fullscreen), vsync, frame rate limit (off, 30, 60, 90, 120, 144), capture preset (Off, Portrait 9:16; below) |
| Audio | master, effects, signals, voice, ambience, interface volumes, 0 to 100 % (default 100 %, master 80 %) |

**Window mode.** The display setting is the player's: the game sets the window mode at its start (from the settings file) and when the display or capture setting changes, never when a race, free sail or the menu opens. Entering or leaving fullscreen through the system (the window's green button on macOS, a system shortcut) becomes the new display setting and is saved at once, so the game never puts the old mode back. A new windowed game opens at 1280 × 800 (the Steam Deck's size; the system may cap it to the screen). While the engine loads, the boot splash shows the logo on navy (`game/branding/boot_splash.png`, background #1A2A3A).

**Reset section** restores the section's defaults (in Controls, the options; the bindings have their own reset).

**Help line.** Under the rows, one line of help for whatever has the focus: what the setting does, what its values
mean, and for a binding how to change it or which action it conflicts with. Every row has its line.

**Where each setting goes.** Every setting is applied where the game has it: the controls' options to the boat's
controls (`PlayerControls`); rankings hold or toggle to the HUD's ranking list (toggle: `Tab` or a `View` press
opens and closes it, and `View` then no longer cycles the density, `controls.md` §3); camera boost hold or toggle to
the free camera (toggle: a press turns the boost on and the next off); vibration to the gamepad rumble of
`controls.md` §6 (scaled by the setting, none at Off, only while the player sails); the cameras' options to the
camera rig; assists, density and the colour-blind palette to the HUD (`hud.md` §16.2.1); UI scale, display,
render scale and the capture preset to the window; quality to the sea and sky; the volumes to the audio buses.
Captions are stored only, until the audio has caption lines (`audio.md` §8).

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
  race): the example venue (`example_bay`), the default class, 12 kn from the north with the venue's puffs and
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
  the backdrop at once), 4 boats, no HUD and no audio: cheaper than a race, so it holds the race's frame rate on the
  Steam Deck at 1280 × 800. **Fallback**: when the sail scene is not there or does not load (a build without it, a
  missing boat file), the painted backdrop is drawn instead: a hazy sky over a calm sea with long swells and one
  distant sail, drawn without image files. Over either backdrop a soft haze in the top-left corner keeps the
  wordmark and the menu legible.
- **One accent across the game**: the HUD's `mark` yellow (`#FFD23F`, `hud.md` §16.2). Yellow on the cream cloth
  fails as text (1.3:1), so the menus use it as a **fill** with navy text on it (navy `#1A2A3A` on yellow is
  10:1): the focused row or button is a yellow bar with a 5 px navy edge on its left (the edge keeps the focus
  visible against the cloth); the heading rules, the selected settings section's underline and the scroll grabber
  are yellow bars. Navy text on the cloth is 13:1, the muted grey `#56646E` 5.4:1.
- **Red** (`#B8361C`, 5.2:1 on the cloth) only for warnings, destructive actions (**Quit**, **Reset section**,
  reset bindings) and penalties. A focused destructive button is a red bar with cloth-coloured text (5.2:1).
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
