# Cameras

The in-race cameras: chase (the default), onboard, aerial and free, with the TV director and the replay cameras to
come later. How each is computed from the boat's render pose, how it is smoothed, how it stays above the water, how
players move, zoom, recentre, store presets and switch. Keys and sticks are in `controls.md`; what the cameras look
at is drawn per `water_render.md` and `sail_visuals.md`. Presentation only: nothing here feeds the simulation.

## 1. Frames and inputs

**Frames.** The Godot scene axes, the generated model's axes and the boat node's basis are those of
`conventions.md` §11 (`X` = east, `Y` = up, `Z` = south; the bow is the boat node's local `+Z`). Positions near the
camera are made camera-relative for the sea (`water_render.md` §2); cameras work in plain scene coordinates.

**Inputs per frame**: the viewed boat's render pose (position, heave `z`, `ψ`, `θ`, `φ`, interpolated between ticks,
`networking.md` §6), its `twa`, the class's `loa`, `beam_max`, and the sidecar rig points; the sea height function
(`sea.md` §7); the frame time `dt` (clamped to 0.1 s); the camera actions of `controls.md` §4. Every rate below is per
second and scaled by `dt`, so the cameras behave the same at any frame rate.

**Smoothing** means the exponential filter `y += (x − y)·(1 − exp(−dt/τ))`, angles through `angle_diff`, directions
as unit vectors. `τ = 0` means no smoothing.

**Viewed boat**: the player's own boat; after finishing, retiring or as a spectator, the player can step through the
boats (`controls.md`), jump to the leader, or to the boat nearest the camera.

## 2. Chase camera (default)

An orbit around the boat that turns with the boat's heading but ignores heel and pitch, so the horizon stays level
and the boat heels in the frame.

| parameter | default | range | meaning |
| --- | --- | --- | --- |
| `R` | `R0 = max(loa + 16, beam_max + 22)` m | 8 m – 1000 m | distance from the target |
| `el` | 13.5° | 2° – 85° | elevation above the horizon |
| `az` | 0 | any | azimuth offset from astern, + = clockwise seen from above (from astern toward the port quarter) |
| `fov` | 40° vertical | 25° – 75° | vertical field of view (Godot `keep_height`) |
| `tau_yaw` | 0.35 s | 0 – 2 s | how the camera follows the heading |
| `tau_heave` | 0.3 s | 0 – 1 s | how the target follows the boat's heave |
| `lift` | 1.0 m | | eye raised parallel to the view direction |

```
psi_c   = smoothed heading (tau_yaw)                    // on a tack the view swings round, it does not snap
zt      = smoothed heave (tau_heave)
target  = boat reference point at height zt
azw     = psi_c + PI + az                               // compass direction from the target to the eye
eye     = target + R * (sin(azw)*cos(el), sin(el), -cos(azw)*cos(el)) + (0, lift, 0)
view    = look along (target - eye + (0, lift, 0)), up = +Y   // the lift moves the eye, not the aim
```
- With the defaults the boat sits a little below the centre of the frame with the rig and the sails in view; a 7 m
  sportsboat is seen from about 24 m, a 12 m boat from about 28 m.
- Heel and pitch are not followed. The heave is followed only through `tau_heave`, so the camera does not bob with
  each wave; a "follow the waves" option sets `tau_heave = 0`.
- Player input: orbit `az` at 120°/s and `el` at 60°/s at full deflection (keys, stick) or 0.3° per pixel of mouse
  drag (drag right = `az` +, drag down = `el` +); zoom `R` by ×1.12 per wheel notch or ×2 per second held (keys,
  triggers); `fov` with the `camera_fov` modifier (Alt, `controls.md` §3) + zoom, by the same factors.
- **Recentre** (`controls.md`): `R = R0`, `el = 13.5°`, `az = 0`, `fov = 40°`. Optional auto-recentre of `az` after
  5 s without camera input (off by default), with `τ = 1 s`.

## 3. Onboard camera

The helmsman's eye, fixed in the heeled, pitching boat, looking forward past the sails.

**Eye position** (body frame, computed at load from the generated boat):
```
tiller steering: xh = rudder_stock.x + 0.12 * loa ; zh = deck(xh, yh) + 0.95   // sitting out, eye height
wheel steering:  xh = wheel_hub.x - 0.45          ; zh = deck(xh, yh) + 1.65   // standing behind the wheel
yh_abs = 0.85 * half-beam of the deck at xh
deck(x, y) = height of the deck mesh under (x, y), found by a vertical ray at load
```
The helmsman sits to windward: `yh = −sgn(twa)·yh_abs` (starboard tack: wind from starboard, eye on the starboard
side, `y < 0`). When the tack sign changes and has held for 0.6 s (the helmsman waits for the boom), the eye crosses
at the same `x` in `2·yh_abs / 1.5 m/s` seconds along a smoothstep, dipping 0.3 m at the centreline. A tack back
during the crossing reverses it from where it is.

**View**:
```
eye   = boat pose applied to (xh, yh, zh)                       // moves with heel, pitch and heave
yaw   = psi + look_yaw
pitch = 0.5 * theta + look_pitch                                // half the boat's pitch
roll  = heel_follow * phi                                       // horizon: level by default
```
| parameter | default | range |
| --- | --- | --- |
| `fov` | 65° vertical | 50° – 90° |
| `heel_follow` | 0 (horizon level) | 0 – 1 (accessibility, `controls.md` §6) |
| `look_yaw` | 0 | ±150° |
| `look_pitch` | 0 | −60° … +75° |

- Looking around: mouse drag (0.15° per pixel) or right stick as an absolute look (stick direction = look direction
  scaled to the limits), or the orbit keys as a rate (90°/s yaw, 60°/s pitch); on release the look returns to
  centre with `τ = 0.6 s` (option: stay).
- Zoom changes `fov` within its range (×1.12 per notch, ×2 per second held).
- The near plane is 0.1 m (the boom, the backstay and the crew pass close to the eye).
- The own boat is drawn; nothing of it is hidden.

## 4. Aerial camera

A top view for tactics: the fleet, the laylines on the water and the marks.

| parameter | default | range | meaning |
| --- | --- | --- | --- |
| `H` | 250 m | 40 – 3000 m | height above the target |
| `tilt` | 90° (straight down) | 50° – 90° | 90 = top-down, lower = a raked tactical view from astern of the up direction |
| `up` | north | north, boat, wind | what points to the top of the screen: north, the boat's heading, or the direction the true wind comes from (smoothed 10 s) |
| `fov` | 45° vertical | | |
| `frame` | boat | boat, boat + next mark | `boat + next mark` centres on the midpoint and raises `H` so both stay inside 80 % of the frame |

```
upd    = compass of the chosen up direction (smoothed: boat heading τ = 0.5 s, wind τ = 10 s)
eye    = target + H * (sin(upd + PI)*cos(tilt), sin(tilt), -cos(upd + PI)*cos(tilt))   // tilt < 90: from astern of up
view   = look at target; screen up = the horizontal direction upd (for tilt = 90)
```
Zoom changes `H` (×1.12 per notch, ×2 per second held); the orbit keys turn `up` by hand at 120°/s (which sets `up`
to a fixed compass angle until recentred) and change `tilt` at 60°/s within its range. Recentre: `H = 250 m`, `tilt = 90°`, `up` = the player's chosen default.

## 5. Free camera

A fly camera for looking around the course, spectating and replays.
- Translation along the view (forward/back, strafe, up/down; keys in `controls.md` §3 "Free camera flying") at `v = 10·(1 + h/20)` m/s at full input, `h` = height
  above the sea; ×4 with the boost modifier. No inertia beyond a 0.15 s smoothing of the velocity.
- Mouse look (0.15° per pixel) or right stick (90°/s yaw, 60°/s pitch); pitch limited to ±89°; roll 0.
- Kept at least 1 m above the sea (§7) and within 10 km of the venue origin.
- First selection in a race: 60 m behind and 40 m above the viewed boat, looking at it. Recentre: back to that pose.
- The free and aerial cameras are available in every mode, ranked play included (`networking.md` §12).

## 6. Switching and presets

- **Cycle**: chase → onboard → aerial → free → chase. Direct keys select a mode (`controls.md` §3).
- **Cuts** by default. Option "smooth switch": chase ↔ aerial blend over 0.4 s (position `lerp`, orientation
  `slerp`, `fov` `lerp`, smoothstep weight); other pairs always cut.
- Each mode keeps its parameters across switches and across races (saved in the player profile); **recentre** resets
  only the current mode.
- **Presets**: 8 slots. Recall = select the stored mode with its stored parameters; store = the current mode and
  parameters (`controls.md`). Factory presets, all chase at `R = 1.6·R0`, `el = 13.5°`: `az` = 0° (astern), 45°, 90°
  (abeam to port), 135°, 180° (ahead, looking back), 225°, 270° (abeam to starboard), 315°.

## 7. Staying out of the water and the land

- **Water clearance** (chase, aerial with low tilt, free): after the eye is computed,
  ```
  floor = sea_height(eye) + c_w          // c_w = 1.0 m; sea_height evaluated as in sea.md §7.2
  if eye.y < floor: eye.y raised to floor at once
  else: the correction decays with τ = 0.25 s
  ```
  and for the chase camera the aim point is kept, so the camera tilts down a little instead of dipping. At the 2°
  minimum elevation the chase eye is `R·sin 2° + lift` above the target, which the clearance only touches in a
  swell.
- **Land and obstacles**: if the segment target → eye enters the drawn land (the venue's land polygons and obstacles
  of `data_format.md` §6.5 with the height the front end draws them at: terrain, quays, rocks), the eye is pulled
  toward the target to 2 m short of the crossing at once, and eased back out with `τ = 0.5 s` (chase and aerial).
  The free camera keeps 1 m above the drawn ground as it does above the water. A high camera above land is not
  pulled in: only a segment that passes below the ground is. Other boats are not avoided.
- **Near and far planes**: near = 0.1 m onboard; otherwise `0.5 + 119.5·clamp((eye.y − 80)/2000, 0, 1)` m (sharper
  depth at height). Far = 30 km (the horizon, `water_render.md` §5).

## 8. Camera shake

On a contact `begin` event of the viewed boat (`collisions.md` §5) with `closing_speed ≥ 0.3 m/s`: a positional shake
of amplitude `min(0.25, 0.04·closing_speed)` m and an angular one of `min(1.5°, 0.25°·closing_speed)`, value noise at
12 Hz, decaying with `τ = 0.3 s`; overlapping events take the larger amplitude. Chase and onboard only. Off with the
reduced-motion option (`controls.md` §6).

## 9. Later: TV director and replay

- **Replay** (`networking.md` §14): the same four cameras on the re-simulated race, plus a timeline (pause, ×0.25 to
  ×8, scrub, jump to events), the viewed boat free to choose, and scripted camera paths for clips (keyframes of eye,
  aim and `fov`, Catmull-Rom through them, constant speed along the path).
- **TV director** for spectators and replays. Shots: *start line* (fixed, 20 m outside the committee boat end at 6 m,
  looking down the line), *mark cam* (fixed 40 m outside the next mark on the approach side at 6 m, tracking the
  leading boat in the zone), *long lens* (chase at `R` = 150 m, `fov` 12°), *helicopter* (orbit at 60 m height and
  120 m radius at 5°/s), *onboard* of the boat in the action. The action is scored per second: boats within their
  zone at a mark, pairs with a keep-clear relation in `Warning` or `Breach` (`rules.md` §11), lead changes, starts
  and finishes. A shot lasts 6–12 s, never less than 3 s; a new shot keeps the camera on the same side of the
  boats' line of travel as the last one.

## 10. Tests (headless)

1. Chase geometry: boat at the origin, `ψ = 0`, defaults, `wm7` (`R0 = 24.5` m): eye at
   `(0, 24.5·sin 13.5° + 1, 24.5·cos 13.5°)` in scene axes (astern = south = `+Z`), within 1 mm.
2. Heading follow: after a heading step of 90°, the chase azimuth is within 5 % of the new heading after
   `3·tau_yaw` = 1.05 s; with `tau_yaw = 0` at once.
3. Frame-rate independence: holding orbit for 1 s gives 120° ± 0.5° at 30, 60 and 144 fps.
4. Water clearance: 10 minutes of chase at `el = 2°` in `Hs = 1.5 m`: the eye is never below `sea_height + 0.99`.
5. Onboard side: a tack at `t = 0` (tack sign flips) puts the eye on the new windward side by
   `0.6 + 2·yh_abs/1.5` s (±1 frame) and never crosses outside the deck edge.
6. Aerial up modes: with `up = north` the scene `−Z` direction points to the top of the screen; with `up = wind` the
   true wind comes from the top of the screen within 1°.
7. Presets: store in slot 3, change every parameter, recall slot 3: all parameters and the mode restored exactly;
   factory reset restores the eight chase presets.
8. Shake: a contact at 2 m/s gives a peak offset of 0.08 m and less than 5 % of it after 0.9 s.
