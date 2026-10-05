# Controls

The player's actions, their default keyboard, mouse, gamepad and Steam Deck bindings, how analog inputs and held
keys become the boat's commands, and the accessibility options. The boat commands themselves are the core's
(`boat.md` §2, `sails.md` §4.2) and travel in the input frame of `networking.md` §4.1; the cameras are
`cameras.md`, the indicators `hud.md`.

## 1. From input to the boat

- Input devices are read **every rendered frame** into a controls state. At each tick boundary the controls module
  stamps the input frame for that tick from the latest state (`networking.md` §4): `h_cmd`, `sheet_cmd`, the flags
  `let_fly`, `auto_trim`, hail, hail reply, protest, and at most one sail request.
- **Discrete actions** (sail requests, hail, hail reply, protest) are latched on the press and sent in the next
  stamped frame; a second one before that frame waits for the one after. Retire, chat and menu actions go on the
  reliable channel (`networking.md` §4.4).
- The core rate-limits the rudder (`helm_rate`, `boat.md` §5.2) and moves the sails at their sheet rates
  (`sails.md` §5.5): controls set targets, they never move the boat directly.
- Commands are clamped to their ranges before they are stamped (`h_cmd` ∈ [−1, 1], `sheet_cmd` ∈ [0, 1]).

## 2. Actions

| action | kind | effect |
| --- | --- | --- |
| `helm` | axis −1…+1 | `h_cmd` from a stick (§5.1); + turns the bow to starboard |
| `helm_left`, `helm_right` | button | keyboard helm (§5.2) |
| `helm_centre` | button | `h_cmd = 0` |
| `helm_fine` | modifier (hold or toggle) | keyboard and stick helm limited to 0.35 |
| `sheet_in`, `sheet_out` | button or trigger | move `sheet_cmd` (§5.3); ignored while auto-trim is on |
| `sheet` | absolute axis (optional) | `sheet_cmd = (axis + 1)/2` for a slider, throttle or trackpad |
| `let_fly` | hold (option: toggle) | `let_fly` flag while held |
| `auto_trim` | toggle | the auto-trim assist, when the lobby allows it (`hud.md` §14) |
| `sail_1` … `sail_9` | button | front sail by slot (§5.4) |
| `sail_prev`, `sail_next`, `sail_set` | button | gamepad sail selection (§5.4) |
| `drop_front` | button | `drop_front()` |
| `hail` | button | hail for room to tack, or answer "you tack" to a hail (`rules.md` §7.9, `hud.md` §11) |
| `protest` | button | protest while the protest prompt shows (`rules.md` §10) |
| `camera_next`, `camera_chase`, `camera_onboard`, `camera_aerial`, `camera_free` | button | `cameras.md` §6 |
| `camera_orbit` | 2 axes / 4 buttons | orbit or look (`cameras.md` §2–§5) |
| `camera_zoom_in`, `camera_zoom_out` | button / wheel | zoom |
| `camera_fov` | modifier | with zoom: changes the chase camera's `fov` instead of its distance (`cameras.md` §2) |
| `camera_recentre` | button | recentre the current camera |
| `camera_preset_1` … `8` | button | recall; with the store modifier: store |
| `camera_boost` | modifier | free camera ×4 |
| `camera_clip` | button | offline: the next clip camera (start line, mark, long lens, helicopter, `cameras.md` §9) |
| `rankings` | hold (option: toggle) | ranking list (`hud.md` §10) |
| `map` | toggle | full course map (`hud.md` §8) |
| `radar_zoom_in`, `radar_zoom_out`, `radar_orientation` | button | radar range ×1.5 steps, heading-up / north-up |
| `wind_shadow_view` | toggle | the wind shadow assist, when allowed (`hud.md` §3.3) |
| `hud_hide` | toggle | hide every HUD element |
| `world_tags` | toggle | hide or show the world tags and the on-water guides (§7, `hud.md` §16.4) |
| `hud_density` | button | cycle the instrument density Glance, Race, Data (`hud.md` §16.1) |
| `boat_names` | toggle | name tags over boats |
| `boat_select` | button | select the next boat for her tag and card, nearest first, then none (`hud.md` §16.4.1) |
| `boat_pick` | pointer | a click or tap without a drag: select the boat under the pointer, or clear on open water or on the selected boat (`hud.md` §16.4.1) |
| `spectate_next`, `spectate_prev`, `spectate_leader` | button | viewed boat, when not racing (`cameras.md` §1) |
| `chat` | button | open the chat line |
| `pause_menu` | button | pause offline, menu online (§7); with a boat selected it first clears the selection (`hud.md` §16.4.1) |
| `capture_pause` | toggle | offline: clean pause, no menu and no label (§7) |
| `capture_slow` | button | offline: slow motion, cycling ×1, ×0.5, ×0.25 (§7) |
| `screenshot` | button | save a screenshot |
| `reset_boat` | button | offline practice only: free sailing re-places the boat at its start point, sailing with its start sail and the helm centred; an offline race restarts from the spawn. No effect online or in a ranked or timed session |

There is no action for penalty turns (they are sailed), tacking or gybing (steered), or the main (always up).

## 3. Default bindings

Keys are bound by **physical position** (layout independent) and shown with the local key label. Every action takes
up to two keyboard or mouse bindings and one gamepad binding; all are rebindable.

| action | keyboard, mouse | gamepad (Xbox names) | Steam Deck (default template) |
| --- | --- | --- | --- |
| `helm` | – | left stick X | left stick X |
| `helm_left` / `helm_right` | ← / →, A / D | – | – |
| `helm_centre` | ↓ | L3 (click) | L3 |
| `helm_fine` | Shift (hold) | LB (hold) | L4 (hold) |
| `sheet_in` / `sheet_out` | W / S | RT / LT | R2 / L2 |
| `let_fly` | Space | A | A |
| `auto_trim` | T | D-pad down | D-pad down |
| `sail_1` … `sail_9` | 1 … 9 | – | – |
| `sail_prev` / `sail_next` / `sail_set` | – | D-pad left / right, X | D-pad left / right, X |
| `drop_front` | 0 | B | B |
| `hail` | H | D-pad up | D-pad up |
| `protest` | P | D-pad up while the protest prompt shows | same |
| `camera_next` | C | Y | Y |
| `camera_chase` … `camera_free` | F5, F6, F7, F8 | – | – |
| `camera_orbit` | right or left mouse drag; numpad 4/6/8/2; I/J/K/L | right stick | right stick, right trackpad, touch drag |
| `camera_zoom_in` / `out` | wheel; numpad 9 / 7; O / U | RB / RB + LB held | R1 / R1 + L1 held |
| `camera_recentre` | numpad 5, R | R3 (click) | R3 |
| `camera_preset_1` … `8` | F1 … F4, Shift+F1 … F4 recall; Ctrl + key stores | – | – |
| `camera_fov` | Alt (hold) | – | – |
| `camera_boost` | Shift (free camera) | LB (free camera) | L1 |
| `camera_clip` | X | – | – |
| `rankings` | Tab (hold) | View (hold) | View (hold) |
| `hud_density` | G | View (tap) | View (tap), R4 |
| `map` | M | – (in the pause menu) | – |
| `radar_zoom_in` / `out` | = / − | – | – |
| `radar_orientation` | Z | – | – |
| `wind_shadow_view` | V | – | – |
| `hud_hide` | F10 | – | – |
| `world_tags` | / | – | – |
| `boat_names` | N | – | – |
| `boat_select` | B | – | R5 |
| `boat_pick` | left mouse button | – | touch screen tap |
| `spectate_next` / `prev` / `leader` | ] / [ / Home | RB / LB / R3 (when not racing) | same |
| `chat` | Enter | – | – |
| `pause_menu` | Esc | Menu | Menu |
| `capture_pause` / `capture_slow` | . / , | – | – |
| `screenshot` | F12 | – | Steam button + R1 |
| `reset_boat` | Backspace | – (in the pause menu) | – (in the pause menu) |

**Click or drag.** The left mouse button (and a touch, which arrives as the left button) is both `boat_pick` and a
camera drag: a press that is released within 8 px of where it went down is a click and picks; once it has moved
further it is a drag, orbits (or looks) as the right button does from that point, and picks nothing on release. The
right button always drags. A press over a menu, the look panel or the chat line belongs to them.

Notes: `helm_fine` and `camera_boost` share Shift, which is fine because the free camera takes no helm input.
On the gamepad `View` is both `rankings` and `hud_density`: a press released within 0.3 s is a tap (density), a
longer one shows the ranking list while held; with the rankings toggle option the density keeps only the keyboard key
and R4. The
gamepad has no direct sail keys: D-pad left/right step a highlighted sail on the HUD sail strip, X sets it (§5.4).
F9 opens and closes the look panel (`hud.md` §18) and Shift+F9 toggles the frame-time overlay (`hud.md` §17):
development keys outside the action table, not rebindable and not listed in the settings. While the look panel has
the focus, Up, Down, Left, Right, Enter, Space and Esc are its own and the boat takes no keys (Esc gives them back,
F9 closes it).
The capture keys sit together on the bottom row (`,` slow motion, `.` clean pause, `/` world tags), next to `X`
for the clip cameras; they have no gamepad binding (a capture is made at the keyboard).

**Free camera flying.** While the free camera is selected the boat's helm and sheet inputs fly it and the boat
keeps its last `h_cmd` and `sheet_cmd` (a hold-to-steer key counts as released): `sheet_in` / `sheet_out` (W / S)
forward and back, `helm_left` / `helm_right` (← / →, A / D) strafe, the zoom keys (O / U, numpad 9 / 7) up and
down; gamepad: left stick forward, back and strafe, RT / LT (or RB / RB + LB) up and down, right stick look, LB
boost. Every other action (let fly, sails, auto-trim) keeps working.

## 4. Camera input rates

Stick and key rates are per second, mouse rates per pixel (`cameras.md`): chase orbit 120°/s azimuth and 60°/s
elevation at full stick or held key, 0.3°/px mouse; onboard and free look 0.15°/px, sticks 90°/s yaw and 60°/s
pitch (onboard stick look is absolute, `cameras.md` §3); zoom ×1.12 per wheel notch, ×2 per second held. Stick dead
zone 0.12 radial, response `((|s| − 0.12)/(0.95 − 0.12))^1.5` along the stick direction. Invert X and Y options per
camera kind (orbit, look).

## 5. Boat input processing

### 5.1 Helm stick
```
x    = helm axis value, [-1, 1]
dz   = 0.10          (option 0 – 0.30)
sat  = 0.95          (the stick counts as full from here)
gam  = 1.6           (option 1.0 – 3.0: higher = finer near the centre)
m    = clamp((fabs(x) - dz) / (sat - dz), 0, 1)
h_cmd = sgn(x) * pow(m, gam) * (helm_fine ? 0.35 : 1)
```
The stick is absolute: centred stick = centred helm. Reference: at `x = 0.5`, `h_cmd = 0.30`; at `x = 0.3`, `0.10`.
When the stick has been inside its dead zone for 0.5 s and a helm key is pressed, the keys take over (§5.2); moving
the stick out of its dead zone takes it back. The source that moved last wins.

### 5.2 Helm keys
Two modes (option, per player):
- **Set and hold** (default). A held key moves `h_cmd` linearly at `KEY_RATE = 0.85` per second (counting the
  frame the press is first read), with no ramp: a short press of 0.1 s gives 0.085 (about 3° of rudder), 0.5 s
  gives 0.425 and full helm from the centre takes about 1.18 s. The rudder follows at its own speed (`helm_rate`,
  `boat.md` §4), which is faster. Each frame moves `h_cmd` by `KEY_RATE · dt`, so the result is the same at any
  frame rate. With `helm_fine` the rate is divided by 3 and a key moves the helm no further out than ±0.35 (a helm
  already beyond it only comes back). On release the helm stays where it is. `helm_centre` (↓) eases `h_cmd` back
  to 0 at the same rate (0.425 is centred in 0.5 s, full helm in about 1.18 s), and stops there; a helm key
  pressed on the way takes over from where the helm is. Both keys held: they cancel. Suited to long reaches and to
  players who helm like a tiller.
- **Hold to steer.** While a helm key is held, `h_cmd = ±k(t)` with the ramp
  `k(t) = min(1, 0.25 + 0.75·t / 0.8 s)` (`t` = time held, counting the frame the press is first read), limited to 0.35 with `helm_fine`. On release `h_cmd = 0`
  and the core brings the rudder back at `helm_rate`. Both keys held: the later one wins.

### 5.3 Sheet
`sheet_cmd = u` ∈ [0, 1], 0 = sheeted hard in, 1 = fully eased (`sails.md` §5.2). Only used with auto-trim off.
- **Keys**, rate by hold time `e` (same for `sheet_in` with sign −1 and `sheet_out` with +1):
  ```
  r(e) = 0.06                            for e < 0.1 s
       = 0.06 + 0.39 * (e - 0.1) / 0.9   for 0.1 s <= e <= 1 s
       = 0.45                            for e > 1 s          // per second of u
  u = clamp(u + sign * r(e) * dt, 0, 1) ;  both keys held: they cancel
  ```
  so a tap trims by a fraction of a percent and a long press sweeps the whole range in about 2.7 s; `helm_fine`
  divides the rate by 3.
- **Triggers**: `u += (t_out' − t_in') · 0.5 · dt` with `t' = pow(clamp((t − 0.05)/0.95, 0, 1), 1.5)` for each
  trigger value `t`.
- **Absolute axis** (`sheet`, optional): `u = (axis + 1)/2`, dead zone 0.02 at both ends.
- Option "sheet turns auto-trim off": a sheet input while auto-trim is on switches it off (default off: the input is
  ignored and the HUD shows `AUTO`).
- When auto-trim is switched off, `u` starts from the value that matches the present trim (`sails.md` §5.2 inverted
  for the front sail, or the main if no front sail is up), so nothing jumps.

### 5.4 Sail requests
Slots are the class's front sails in class-file order (`data_format.md` §3.5, the main excluded); the HUD sail strip
shows each slot's name and key. With `F` the front sail that is up and the running change of `sails.md` §4.2:

| press | situation | request |
| --- | --- | --- |
| slot `X` | idle, `X ≠ F` | `hoist(X)` |
| slot `F` | idle | `drop_front()` |
| slot `F` | the new sail `S` is going up (peel) | `hoist(F)`: cancels the hoist |
| slot `S` | `S` is going up, `F ≥ 0` | `hoist(F)`: the same cancel |
| slot `S` | a lone drop of `S` is running | `hoist(S)`: cancels the drop |
| `drop_front` | idle, `F ≥ 0` | `drop_front()` |
| slot `S` or `drop_front` | a lone hoist of `S` is going up and no front sail is up (`F = −1`) | `drop_front()`: cancels the first hoist (`sails.md` §4.2) |
| anything else | busy | nothing sent; the HUD flashes the running change |

A latched press is mapped against the boat's sail state when its frame is stamped. A press that maps to nothing
still uses its frame (a later press waits for the next one).

Gamepad: `sail_prev`/`sail_next` move a highlight along the strip (wrapping), `sail_set` presses the highlighted
slot with the rules above. The highlight starts on the sail the HUD suggests (`hud.md` §4 sail hint) or the next
slot after `F`.

### 5.5 Let-fly, auto-trim, hail, protest
- `let_fly` sets the flag while held; with the toggle option one press sets it and the next clears it (the HUD then
  shows `LET FLY` until cleared).
- `auto_trim` toggles the assist; refused (with a HUD message) when the lobby's assist preset forbids it.
- `hail`: when a valid hail for room to tack is available (`hud.md` §11 shows the button), sends the hail flag; when
  this boat has been hailed, sends the reply "you tack" (tacking needs no key).
- `protest`: sends the protest flag only while the protest prompt is shown.

## 6. Accessibility and options

| option | default | range / values |
| --- | --- | --- |
| rebinding | defaults of §3 | every action, two keyboard/mouse bindings and one gamepad binding; conflicts shown |
| helm key mode | set and hold | set and hold, hold to steer (§5.2) |
| helm stick dead zone, curve | 0.10, 1.6 | 0–0.30, 1.0–3.0 |
| sheet key rate scale | 1.0 | 0.5–2.0 |
| hold or toggle | hold | per action: `let_fly`, `helm_fine`, `rankings`, `camera_boost` |
| mouse helm | off | while the left button is held, horizontal mouse offset from the press point sets `h_cmd` (300 px = full) |
| one-hand layout | off | left-hand keyboard set (A/D helm, W/S sheet, Q let fly, 1–5 sails, E camera) or mouse-only (mouse helm, wheel = sheet, buttons = let fly and camera) |
| camera invert X / Y | off | per camera kind |
| camera and look speed | 1.0 | 0.25–3.0 |
| reduced motion | off | on: no camera shake, onboard horizon always level (`heel_follow = 0`), chase `tau_yaw ≥ 0.5 s`, no smooth-switch overshoot |
| onboard heel follow | 0 | 0–1 (`cameras.md` §3) |
| vibration | on, 1.0 | off, 0–1: contact rumble `min(1, closing_speed/2)` for 0.2 s; a light buzz (0.1) while let fly or `luff_shiver > 0.8` on the driving sail |
| captions | off | on: every race sound that carries information (signals, hails, penalties, rule warnings) also shows a caption line (`audio.md` §8) |
| UI scale, colour-blind palette | 100 %, standard | `hud.md` |
| assists | from the lobby | auto-trim and the HUD presets of `hud.md` §14 |

The options are saved per player in the settings file and set in the settings screen (`menus.md` §3).

## 7. Pause, focus and menus

- **Offline** (solo against AI): `pause_menu` pauses the simulation (no ticks), audio ducks to ambience, the cameras
  can still orbit and zoom. Resuming continues from the same tick. The menu holds resume, restart, settings and
  quit to menu (`menus.md` §2).
- **Online**: `pause_menu` opens the menu over the running race (banner "Race continues"); the boat keeps its last
  helm, sheet and let-fly while the menu is open, except that a held let-fly key or hold-to-steer key counts as
  released. The menu holds retire (with a confirmation) and settings.
- **Capture** (offline), for freeze frames and slow crossings in clips:
  - `capture_pause` stops the simulation as the pause does (no ticks; resuming continues from the same tick), but
    opens no menu and shows no `Paused` label. The cameras keep moving on the frame time: they orbit, zoom, fly
    and switch, and the helicopter keeps turning (`cameras.md` §9). The audio ducks as in the pause. The boat's
    controls stay live and are applied when the simulation continues. `pause_menu` still opens the menu over a
    clean pause; closing the menu returns to the clean pause.
  - `capture_slow` cycles the simulation rate ×1 → ×0.5 → ×0.25 → ×1. The simulation still steps at its 50 ms
    tick, fed with the frame time times the rate, and the render pose is interpolated between ticks, so boats,
    sails, sea and wakes move smoothly at the slower pace (everything drawn from the simulation's clock slows
    with it). The cameras, the HUD's own smoothing and the sound run on the real frame time. Each press shows a
    brief rate note (`hud.md` §16.6: `Slow motion x0.5`, `Slow motion x0.25`, `Normal speed`) for 1.5 s of real
    time, fading out over its last 0.4 s, also with the HUD hidden and in a clean pause; after that nothing is on
    screen for the rate, so the frames stay clean. The clean pause itself shows nothing. A restart (`reset_boat`,
    the pause menu) sets the rate back to ×1, ends a clean pause and clears the note without showing one.
  - Online both actions do nothing: the race runs on the server's clock.
- **World tags** (`world_tags`, offline and online): hides or shows the world tags of `hud.md` §16.4 (mark tag,
  tack point, name tags, edge pointers, penalty turn) and the on-water guides of the course (the start, gate and
  finish lines drawn on the water, the laylines, the zone circle, the rounding arrows and the far next-mark
  marker). Marks, committee and mark boats and their flags stay. It is separate from `hud_hide`, which hides the
  HUD panels: with both off only the boats, the course objects, the water and the land are drawn. Not saved: a
  session starts with the world tags shown.
- **Chat focus**: typing blocks the boat's buttons and keys (held keys count as released); sticks and triggers keep
  working.
- **Window focus lost**: as chat focus. Held states are cleared so nothing stays pressed.

## 8. Tests (headless, scripted input)

1. Stick curve: `x` = 0.05, 0.3, 0.5, 0.95 give `h_cmd` = 0, 0.099, 0.299, 1.000 (±0.001).
2. Hold-to-steer ramp: after 0.4 s held, `h_cmd = 0.625`; after 0.8 s and later, 1.0; on release 0 in the next frame;
   the same at 30, 60 and 144 fps within 0.5 %.
3. Sheet keys: a 0.05 s tap moves `u` by 0.003; holding 3 s from `u = 0` reaches 1.0; the rate curve is continuous.
4. Latching: two sail presses within one tick send one request in the next frame and one in the frame after.
5. Sail mapping: each row of §5.4 produces its request against a scripted boat state; a press while busy that
   matches no row sends nothing.
6. Focus: with let-fly held, opening chat clears `let_fly` in the next stamped frame.
7. Last-moved source: a stick outside its dead zone overrides held helm keys; releasing the stick into its dead zone
   for 0.5 s gives the keys back.
8. Set and hold: holding → for 1/6 s from centre gives `h_cmd = 0.1417`, for 0.5 s 0.425 and it stays 0.425
   after release; ↓ then moves it by no more than a frame's step at once, is at 0.142 after 1/3 s and at 0 after
   0.5 s; holding ← from the centre for 1 s gives −0.85 and full helm by 1.2 s; a key during the easing stops it;
   `helm_fine` for 0.5 s gives 0.1417; the same at 30, 60 and 144 fps within 0.5 %.
9. Capture: offline, `capture_pause` stops the ticks with no menu and no `Paused` label while the camera still
   orbits, and a second press continues from the same tick; `capture_slow` gives rates 0.5, 0.25 and 1 in turn,
   and 2 s of frames at ×0.5 step 20 ticks (±1), at ×0.25 10 ticks (±1); each `capture_slow` press shows its rate
   note, gone after 1.5 s of frames (also in a clean pause), and `capture_pause` shows none; `world_tags` hides the HUD's world
   tags and the course's water overlays and shows them again; online the two capture actions change nothing.
10. Click or drag: a left press released after 3 px of motion is one pick at its point and orbits nothing; one
    dragged 20 px is a camera drag of the motion past the 8 px and picks nothing on release; in the race scene a
    click on a boat selects her (`hud.md` §16.4.1), Esc with a boat selected clears the selection and does not
    pause, the next Esc pauses, and a click while paused picks nothing.
