# Cameras

The in-race cameras: chase (the default), onboard, aerial and free, the clip cameras of offline sessions (start
line, mark, long lens, helicopter), with the TV director and the replay cameras to come later. How each is computed from the boat's render pose, how it is smoothed, how it stays above the water, how
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

- **Cycle**: chase → onboard → aerial → free → chase. Direct keys select a mode (`controls.md` §3). The clip
  cameras (§9) have their own key and are outside this cycle: `camera_next` from a clip camera selects chase.
- **Cuts** by default. Option "smooth switch": chase ↔ aerial blend over 0.4 s (position `lerp`, orientation
  `slerp`, `fov` `lerp`, smoothstep weight); other pairs always cut.
- Each mode keeps its parameters across switches and across races (saved in the player profile); **recentre** resets
  only the current mode. A session always starts in a regular camera: a clip camera is never saved as the mode.
- **Presets**: 8 slots, for the four regular cameras (store does nothing while a clip camera is shown). Recall = select the stored mode with its stored parameters; store = the current mode and
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
  toward the target to 2 m short of the crossing at once (further, in 2 m steps, while that point is still below
  the ground, as on a segment that grazes a slope), and eased back out with `τ = 0.5 s` (chase and aerial).
  The free camera keeps 1 m above the drawn ground as it does above the water. A high camera above land is not
  pulled in: only a segment that passes below the ground is. Other boats are not avoided.
- **Near and far planes**: near = 0.1 m onboard; otherwise `0.5 + 119.5·clamp((eye.y − 80)/2000, 0, 1)` m (sharper
  depth at height). Far = 30 km (the horizon, `water_render.md` §5).

## 8. Camera shake

On a contact `begin` event of the viewed boat (`collisions.md` §5) with `closing_speed ≥ 0.3 m/s`: a positional shake
of amplitude `min(0.25, 0.04·closing_speed)` m and an angular one of `min(1.5°, 0.25°·closing_speed)`, value noise at
12 Hz, decaying with `τ = 0.3 s`; overlapping events take the larger amplitude. Chase and onboard only. Off with the
reduced-motion option (`controls.md` §6).

## 9. Clip cameras (offline)

Four broadcast shots for clips, chosen by hand in offline sessions (`camera_clip`, `controls.md` §3) before the
replay exists; online the key does nothing (the TV director of §11 will use the same shots for spectators and
replays). They show the viewed boat (§1) and the course around her. Their motion runs on the rendered frame time,
so in a clean pause or in slow motion (`controls.md` §7) they keep moving at their normal rate.

**Choosing.** `camera_clip` steps start line → mark → long lens → helicopter → start line, skipping a shot that
cannot be placed (no start line or no next mark: free sailing offers the long lens and the helicopter only). From
a regular camera it selects the clip camera used last, or the first one that can be placed. Selecting a clip
camera, and stepping between them, always cuts. Recentre puts the long lens and the helicopter back to their
defaults.

**The course inputs**, read every frame from the race (scene coordinates from the world positions):
- the start line ends: `C` the committee boat end and `P` the other one (when neither end is a committee boat, the
  starboard end, the right one seen from the pre-start side, counts as `C`);
- the viewed boat's next mark `M` (for a gate the buoy nearer to her, for a finish line the nearer end; before she
  has started, the first mark), the point `Q` she comes from (the previous mark, the nearer buoy of a previous
  gate, the start line's midpoint on the first leg), and the side `s` the mark is left to (+1 port, −1
  starboard; at a finish line end +1 when the other end is on the right of `Q → M`, else −1, so the camera stands
  outside the line);
- the zone radius `3·loa` (`rules.md` §1) and the boats' positions in race order (race.md §8).

| shot | eye | aim | fov |
| --- | --- | --- | --- |
| **start line** | `C + 20·û` at 6 m above the still water, `û` the horizontal unit vector from `P` to `C` (20 m outside the committee boat end, on the line's extension) | `P` on the still water: looking down the line | 30° |
| **mark** | `M + 40·(sin β, cos β)` (east, north) at 6 m, `β = bearing(M → Q) + 45°·s`: on the approach side, 45° off the approach line, away from the side the boats pass | the leading boat (race order) inside the zone (within `3·loa` of `M`), else the viewed boat: her reference point 2 m up, smoothed with `τ = 0.5 s` (cut to it when the shot is selected) | 35° |
| **long lens** | a chase camera (§2) with its own parameters: `R = 150` m, `el = 5°`, `az = 0`, `tau_yaw = 1.5 s`, `tau_heave = 0.3 s`, `lift = 1` m | as §2 | 12° |
| **helicopter** | an orbit about the viewed boat at radius `r = 120` m and height `h = 60` m: `eye = target + (r·sin α, h, −r·cos α)`, `α` (compass, from the boat to the eye) starts astern (`ψ + 180°`) when the shot is selected and turns at 5°/s clockwise seen from above | the boat's reference point on the still water | 35° |

- **Fixed shots** (start line, mark) do not move with the boat. When the next mark changes (she has rounded), the
  mark camera cuts to the new one. When there is no next mark any more (finished, retired), it keeps its last eye
  and aims at the viewed boat.
- **Input**: the long lens orbits and zooms as the chase camera (§2), its zoom changing `fov` within 6° – 25°;
  the helicopter's orbit keys add to `α` at 120°/s and its zoom scales `r` and `h` together (×1.12 per notch, ×2
  per second held, 0.25× to 4×); the fixed shots take no input.
- **Clearance**: §7 applies to every clip camera (water for all four; the land pull-in from the target for the
  long lens and the helicopter). Near and far planes as §7.

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
9. Start line shot: with `P` at (0, 0) and the committee boat end `C` at (100, 0) (east, north), the eye is at
   east 120 m, north 0, 6 m up, and looks at `P` within 0.1°.
10. Mark shot: `M` at (0, 500) approached from `Q` = (0, 0): left to port the eye is at bearing 225° from `M`
   (east −28.28, north 471.72, 6 m up), left to starboard at 135°; with two boats in the zone it aims at the one
   ahead in race order, with the zone empty at the viewed boat.
11. Long lens and helicopter: boat at the origin, `ψ = 0`: the long lens eye at `(0, 150·sin 5° + 1,
   150·cos 5°)` with `fov` 12°; the helicopter eye 120 m astern and 60 m up when selected, and after 18 s at
   60 fps 120 m to the west (90° clockwise), within 1 cm.
12. Choosing: without a course `camera_clip` gives long lens, helicopter, long lens; with one start line, mark,
   long lens, helicopter, start line; `camera_next` from a clip camera gives chase; with clip cameras not allowed
   (online) the key changes nothing; store while a clip camera is shown leaves the presets as they were.

## 11. Later: TV director and replay

- **Replay** (`networking.md` §14): the four regular cameras and the clip cameras on the re-simulated race, plus a timeline (pause, ×0.25 to
  ×8, scrub, jump to events), the viewed boat free to choose, and scripted camera paths for clips (keyframes of eye,
  aim and `fov`, Catmull-Rom through them, constant speed along the path).
- **TV director** for spectators and replays. Shots: the four clip cameras of §9 (start line, mark,
  long lens, helicopter) and the *onboard* of the boat in the action. The action is scored per second: boats within their
  zone at a mark, pairs with a keep-clear relation in `Warning` or `Breach` (`rules.md` §11), lead changes, starts
  and finishes. A shot lasts 6–12 s, never less than 3 s; a new shot keeps the camera on the same side of the
  boats' line of travel as the last one.
