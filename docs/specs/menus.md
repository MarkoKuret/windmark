# Menus

The front end's menus before the phase 4 online screens: the main menu, the session setup it writes, the settings
and the in-race pause menu. The session setup is `GameSetup` (`game/scripts/game_setup.gd`); the options are those
of `controls.md` §6, `cameras.md` §3 and §6, `hud.md` §14, `water_render.md` §7 and `audio.md` §1.1.

## 1. Main menu

The project's main scene. Items, top to bottom: **Quick race**, **Free sail**, **Settings**, **Quit**.

- **Quick race**: class, sail number, venue, course, fleet size, AI level, wind speed, wind direction, then
  **Start**.
- **Free sail**: class, sail number, venue, wind speed, wind direction, then **Start**.
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

## 2. Pause menu

Opened by `pause_menu` in a race or free sail (`controls.md` §7). Offline the simulation stops while it is open.
Items: **Resume**, **Restart** (the same session from its start), **Settings**, **Quit to menu**. `pause_menu`
again resumes. While it is open the boat's controls are held as in `controls.md` §7 (held let-fly and
hold-to-steer keys count as released). Settings changed here apply to the running scene when the settings
screen closes.

## 3. Settings

Five sections: **Controls**, **Cameras**, **HUD**, **Graphics**, **Audio**. A change applies at once where the
game has the setting and is saved when the settings screen closes, to one file per player
(`user://settings.cfg`, a Godot ConfigFile with a `version`).

| section | settings |
| --- | --- |
| Controls | helm key mode, stick dead zone, stick curve, sheet key rate, hold or toggle for let fly, fine helm, rankings and camera boost, sheet turns auto trim off, vibration (off, 10 % to 100 %), the bindings (shown; rebinding comes later) |
| Cameras | camera and look speed, invert orbit X and Y, invert look X and Y, onboard heel follow, smooth switch, reduced motion |
| HUD | assist preset (Full, Standard, Minimal; online lobbies may force a lower one), instruments (Auto, Glance, Race, Data: the density of `hud.md` §16.1; Auto picks the device default, the `hud_density` key stores its choice here), UI scale (80 % to 130 %), colour-blind palette (standard, deuteranopia, protanopia, tritanopia), captions |
| Graphics | quality (Low, Medium, High: the tiers of `water_render.md` §7, default Medium), render scale (Auto, 50 %, 67 %, 75 %, 85 %, 100 %; default Auto; below), display (windowed, fullscreen), vsync, frame rate limit (off, 30, 60, 90, 120, 144), capture preset (Off, Portrait 9:16; below) |
| Audio | master, effects, signals, voice, ambience, interface volumes, 0 to 100 % (default 100 %, master 80 %) |

**Reset section** restores the section's defaults.

**Render scale.** The 3D view is drawn at that fraction of the window's pixels in each direction and upscaled to
the window; the HUD, the menus and everything 2D stay at the window's native resolution. The upscaler is AMD FSR
1.0 (edge-adaptive upscale and sharpening) on the Forward+ and Mobile renderers, bilinear where FSR is not there
(Compatibility); at 100 % nothing is upscaled. **Auto** picks 67 % when the window is larger than 1920 × 1200
pixels (wider than 1920 or taller than 1200), or larger than 1280 × 800 on a HiDPI screen (the system scales the
screen, as on Retina Macs); otherwise 100 %. So a MacBook's 2560 × 1600 Retina screen renders the 3D at
1715 × 1072 and the Steam Deck's 1280 × 800 at full size. Auto is resolved again whenever the display settings
apply and when the window changes size. The setting is independent of the quality tier.

**Capture preset.** For recording vertical clips. **Portrait 9:16** makes the window 1080 × 1920 pixels (windowed,
centred on its screen; on a screen too small for that, the largest 9:16 window that fits its usable area) and the HUD
takes its portrait layout (`hud.md` §16.5); the display row has no effect while it is on and render scale Auto picks
100 % (clips want the full detail). On a HiDPI screen the pixels are the screen's, so a Retina MacBook shows it at
540 × 960 points. **Off** (default) puts the window back to the size it had before and the display setting applies
again. Saved like the other settings; Reset section turns it off. The menus work in the portrait window too (they fit
its width at every UI scale; the main menu puts the page under the menu).

## 4. Look and input

- A calm sea and sky backdrop, a light sail-cloth panel, navy text, one accent colour; no stock widgets' look.
- Every screen works with the mouse, the keyboard (arrows, Enter, Esc) and the gamepad (D-pad or left stick, A,
  B), through Godot's built-in `ui_*` navigation actions. On a setting, left and right change the value; Enter or
  A steps it forward. B or Esc goes back one level (Esc in the pause menu resumes, it is `pause_menu`).
- Fits 1280 × 800 (Steam Deck) at every UI scale; lists scroll with the focus.
- Player-facing text has no em dashes.
