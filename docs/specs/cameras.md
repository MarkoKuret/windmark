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
  triggers); `fov` with the `camera_fov` modifier (Alt, `controls.md` §3) + zoom, by the same factors. A trackpad's
  two-finger vertical scroll and pinch zoom continuously (fractional notches, `controls.md` §4) and its horizontal
  scroll orbits as a mouse drag; the same gestures zoom and turn every camera that takes the wheel and the drag
  (onboard and free `fov`, aerial `H`, the clip cameras of §9).
- **Recentre** (`controls.md`): `R = R0`, `el = 13.5°`, `az = 0`, `fov = 40°`. Optional auto-recentre of `az` after
  5 s without camera input (off by default), with `τ = 1 s`.

### 2.1 Follow without lag, bank into turns

The chase camera follows the boat tightly (owner decision 2026-10-16: no camera lag). The heading follow is the
first-order filter of §2 with `tau_yaw` (0.35 s by default: in a steady turn the camera trails the heading by
`tau_yaw` of the turn, and less with a smaller `tau_yaw`); the target is the boat's reference point, never offset by
the speed or the heel. The one effect on top is a bank, an offset of the view's roll taken from the same frame's
follow, so it adds no delay:

| effect | rule | constants |
| --- | --- | --- |
| bank | after the look-at the view rolls into the turn by `0.06 s · ω_c`, `ω_c` the camera's own yaw rate this frame (right side down in a turn to starboard) | at most 1.5° |

Reduced motion (`controls.md` §6) turns the bank off and keeps `tau_yaw` at 0.5 s or more. The look panel's Chase
bank row (`hud.md` §18, `--chase-bank=off`) turns the bank off. The long lens (§9) is a chase camera and banks too.

The cinematic pass of 2026-10-04 (a critically damped heading spring, about 20 % more lag in a steady turn, the
target trailing speed changes and leaning with the heel) is removed: the spring and the trail are lag by nature, and
the heel lean followed a smoothed heel, so it moved the aim behind the boat's motion.

## 3. Onboard camera

The helmsman's eye, fixed in the heeled, pitching boat, looking forward past the sails.

**Eye position** (body frame, computed at load from the generated boat): the skipper's own eyes at the helm, so the
player sees what the helmsman sees (owner decision 2026-10-15, replacing the earlier "further aft" eye):
```
tiller steering (sitting on the windward side deck, just forward of the tiller's end, hand on the extension):
  xh = tiller_tip.x + 0.15         ; yh_abs = 0.90 * half-beam of the deck at xh ; zh = deck(xh, yh) + 0.80
wheel steering (standing on the cockpit floor behind the windward half of the rim, looking over it):
  xh = wheel_hub.x - 0.70 * R      ; yh_abs = |wheel_hub.y| + 0.55 * R           ; zh = deck(xh, yh) + 1.60
  (twin wheels: behind the windward wheel, the hub's |y| from rig.wheel_hub; one wheel: on the centreline, 0)
tiller_tip = the forward end of the rudder part at rest (it carries the tiller); rudder_stock.x + 0.13 * loa
             without the mesh
R          = the wheel's rim radius, half the wheel part's athwartships extent; 0.07 * loa without the mesh
deck(x, y) = height of the deck mesh under (x, y), found by a vertical ray at load (for the wheel: the cockpit floor)
```
The heights are adult eye heights: about 0.80 m above the seat sitting upright on the deck edge, about 1.60 m above
the feet standing. On the classes this gives: `wm7` `xh ≈ −2.8 m`, on the side deck beside the cockpit's aft
end; `wm12` `xh ≈ −4.75 m`, 0.6 m behind the wheel's plane and 0.47 m to windward of the centreline, where the
helmsman's hands reach the rim's top. The gaze rests a little below the horizon (`look_down` in the view below:
4° tiller, 8° wheel), so the wheel's top and its windward rim sit in the lower part of the frame and the tiller
side deck shows low; the horizon stays level. The own boat is drawn whole for this camera (no part is hidden,
culled by layer or swapped for a coarser level near the eye; the near plane of 0.1 m clears the rim). The eye
stays clear of the boat: at least 0.3 m from any part of the model (wheel, tiller, lifelines, boom end, backstay)
where it sits and along its whole crossing path.
The helmsman sits to windward: `yh = −sgn(twa)·yh_abs` (starboard tack: wind from starboard, eye on the starboard
side, `y < 0`). When the tack sign changes and has held for 0.6 s (the helmsman waits for the boom), the eye crosses
at the same `x` in `2·yh_abs / 1.5 m/s` seconds along a smoothstep, dipping 0.3 m at the centreline. A tack back
during the crossing reverses it from where it is.

**View**:
```
eye   = boat pose applied to (xh, yh, zh)                       // moves with heel, pitch and heave
yaw   = psi + look_yaw
pitch = 0.5 * theta - look_down + look_pitch                    // half the boat's pitch
roll  = heel_follow * phi                                       // horizon: level by default
```
| parameter | default | range |
| --- | --- | --- |
| `fov` | 75° vertical (about 107° across at 16:9) | 50° – 90° |
| `heel_follow` | 0 (horizon level) | 0 – 1 (accessibility, `controls.md` §6) |
| `look_yaw` | 0 | ±150° |
| `look_pitch` | 0 | −60° … +75° |

- Looking around: mouse drag (0.15° per pixel) or right stick as an absolute look (stick direction = look direction
  scaled to the limits), or the orbit keys as a rate (90°/s yaw, 60°/s pitch); on release the look returns to
  centre with `τ = 0.6 s` (option: stay).
- Zoom changes `fov` within its range (×1.12 per notch, ×2 per second held). A profile saved with the earlier
  default of 65° (never zoomed) loads with the new default.
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
| **start line** | `C + 20·û + 12·p̂` at 8 m above the still water, `û` the horizontal unit vector from `P` to `C`, `p̂` the horizontal unit vector from the line to the pre-start side (20 m outside the committee boat end and 12 m behind the line, astern of the committee boat) | `P` on the still water: looking down the line | 30° |
| **mark** | `M + 40·(sin β, cos β)` (east, north) at 6 m, `β = bearing(M → Q) + 45°·s`: on the approach side, 45° off the approach line, away from the side the boats pass | the leading boat (race order) inside the zone (within `3·loa` of `M`), else the viewed boat: her reference point 2 m up, smoothed with `τ = 0.5 s` (cut to it when the shot is selected) | 35° |
| **long lens** | a chase camera (§2) with its own parameters: `R = 150` m, `el = 5°`, `az = 0`, `tau_yaw = 1.5 s`, `tau_heave = 0.3 s`, `lift = 1` m | as §2 | 12° |
| **helicopter** | an orbit about the viewed boat at radius `r = 120` m and height `h = 60` m: `eye = target + (r·sin α, h, −r·cos α)`, `α` (compass, from the boat to the eye) starts astern (`ψ + 180°`) when the shot is selected and turns at 5°/s clockwise seen from above | the boat's reference point on the still water | 35° |

- **Start line shot placement** (WM-159): a committee boat lies head to wind at its end, so her hull spans the
  line's extension on both sides (7 m of a 14 m boat astern of the line) and her flybridge, about 5 m up, sat right
  on the old sight line (20 m outside the end on the extension, 6 m up): the shot showed the cabin. From 12 m behind
  the line and 8 m up the sight line to the pin passes 11 m astern of the committee boat and 7 m above the water at
  her distance, so the fleet coming to the line is in view with the committee boat's stern low in the corner of
  the frame.
- **Fixed shots** (start line, mark) do not move with the boat. When the next mark changes (she has rounded), the
  mark camera cuts to the new one. When there is no next mark any more (finished, retired), it keeps its last eye
  and aims at the viewed boat.
- **Input**: the long lens orbits and zooms as the chase camera (§2), its zoom changing `fov` within 6° – 25°;
  the helicopter's orbit keys add to `α` at 120°/s and its zoom scales `r` and `h` together (×1.12 per notch, ×2
  per second held, 0.25× to 4×); the fixed shots take no input.
- **Clearance**: §7 applies to every clip camera (water for all four; the land pull-in from the target for the
  long lens and the helicopter). Near and far planes as §7.
- **Depth of field** (long lens and mark shot only, like a broadcast telephoto): the subject boat sharp, the water
  and boats before and behind her softly blurred. Godot's practical camera attributes on the clip camera, focused
  on the subject: the distance from the eye to the long lens's aim (the target point plus `lift`, §2) or to
  the mark shot's aim, pulled with `τ = 0.25 s` (a cut takes it at once). Sharp zone `z = 0.6·loa + 2 m` either
  side of the focus distance `d`:

  | shot | near blur ends at | near ramp | far blur starts at | far ramp | amount |
  | --- | --- | --- | --- | --- | --- |
  | long lens | `d − z` | `0.25·d` | `d + z` | `0.5·d` | 0.08 |
  | mark | `d − z` | `0.3·d` | `d + z` | `0.6·d` | 0.06 |

  Bokeh circle, quality low on tier M and medium on H, off on tier L (`LookFx.dof_allowed`). The start line and
  helicopter shots and the regular cameras (chase, onboard, aerial, free) never have depth of field: the camera's
  attributes are cleared. No camera has a vignette, clip cameras included (owner decision 2026-10-11,
  `water_render.md` §4.5).

### 9.1 Finish view

When the player's race is over (`hud.md` §13.2: her finish, retirement or disqualification, or the race closing or
being abandoned with her still racing), the rig **eases** from the camera in use into the finish view over 2.5 s:
both views are computed every frame and blended (position and rotation slerped, the field of view mixed) by a
smoothstep of the time. The finish view is the slow cinematic drift of the menu's backdrop (`menus.md` §4) on the
viewed boat: it circles her at 45 to 70 m and 5 to 11 m above the water at 1.5° a second, its distance and height
breathing over 40 s, starting from the azimuth the previous camera had, aimed 2 m above her reference point, with
a 35° field of view; with reduced motion a third of that speed. While the results screen shows in its wide layout
the boat is framed 12° left of centre (eased with `τ = 1.4 s`), clear of the panel on the right; otherwise
centred. It takes no input; `camera_next` leaves it for the chase camera (the other camera keys as usual), and
there is no way back to it in that race. It is not a clip camera (no depth of field) and is
never saved as the profile's camera. Online the same (it is presentation only).

### 9.2 Shot scripts (offline)

For unattended clip capture (Godot's Movie Maker, `--write-movie` with `--fixed-fps`) an offline session can run a
**shot script**: `--shot=<path>` after `--` (a `res://` or file path, or an id of `game/data/shots/<id>.shot.json`)
on the sail scene, next to the session's own flags (`--scenario=<id>`, or `--race --fleet=6 --watch`, or free
sailing). It does in order, at set times, what the capture keys do by hand (`controls.md` §7, the clip cameras of
§9), and ends the run by itself. Online it is not read.

**The file** (`windmark.shot/1`, JSON):

| key | default | meaning |
| --- | --- | --- |
| `schema` | required | `"windmark.shot/1"` |
| `portrait` | `false` | the portrait capture preset (`menus.md` §3, 9:16, the HUD's portrait layout) for this run |
| `hud` | `true` | the HUD panels shown at the start (`hud_hide`) |
| `world_tags` | `true` | the world tags and on-water guides shown at the start (`world_tags`) |
| `start` | none | the shot time of the first frame: the world is stepped there before the first frame is drawn (a race shot starting at `-20` does not record the minutes of the sequence before it) |
| `cues` | `[]` | the cues, each `{"t": <shot s>, <one action>}`, run in time order (the file's order for equal times) |
| `note` | | free text, ignored |

**Shot time** (s): the simulation's time from the session's zero (a rules scenario: its clip time 0, `race.md` §14;
a race: the gun, so times before it are negative; free sailing: the world's start), taken at the rendered pose
(tick plus the interpolation fraction). It follows the simulation, so slow motion stretches it on screen, and under
`--fixed-fps` it advances by the same amount every frame. While the simulation does not run (a clean pause, the
pause menu) the shot time runs on the frame time instead, so a `resume` or `end` after a `pause` comes: after a
pause of `p` s every later cue is `p` s of shot time on from the simulation's clock. With a shot script a rules
scenario does not pause at its clip's end: the shot ends the run.

**Actions** (one per cue; the clip keys' notes and labels are not shown, so the frames stay clean):

| action | effect |
| --- | --- |
| `"camera": "<mode>"` | selects `chase`, `onboard`, `aerial`, `free`, `start_line`, `mark`, `long_lens` or `helicopter` (a cut, as the keys do); optional `"preset": 1..8` recalls that slot instead (its mode and parameters), optional `"params": {...}` sets the mode's own parameters over it (chase and long lens `R`, `el`, `az`, `fov`, `tau_yaw`, `tau_heave`, `lift`; aerial `H`, `tilt`, `fov`; onboard `fov`; free `yaw`, `pitch`, `fov`; helicopter `scale`); angle keys may be written in degrees with `_deg` (`el_deg`, `az_deg`, `tilt_deg`, `yaw_deg`, `pitch_deg`). A clip camera that cannot be placed now (§9 Choosing) leaves the camera as it was, with a warning |
| `"slow": 1 \| 0.5 \| 0.25` | the simulation rate (`capture_slow`) |
| `"pause": true`, `"resume": true` | the clean pause on and off (`capture_pause`; the cameras keep moving) |
| `"hud": true \| false` | the HUD panels shown or hidden |
| `"tags": true \| false` | the world tags and guides shown or hidden |
| `"view": <boat> \| "leader"` | views that boat (spectating, §1), the cameras cut to her |
| `"input": "<action>", "for": <s>` | holds a boat action of `controls.md` §2 (`let_fly`, `helm_left`, ...) for `for` s of shot time, as if its key were held (a press on the first frame); for the player's own boat |
| `"end": true` | quits the application cleanly (Movie Maker closes its file) |

`--quit-at=<s>` (with or without a shot) quits at that shot time, the fallback when a file has no `end`. A file that
does not load is reported and the session runs without it (nothing quits by itself then, save `--quit-at`). Shot
files are tuned by eye: their times are the best guesses of the clip, not rules.

## 10. Tests (headless)

1. Chase geometry: boat at the origin, `ψ = 0`, defaults, `wm7` (`R0 = 24.5` m): eye at
   `(0, 24.5·sin 13.5° + 1, 24.5·cos 13.5°)` in scene axes (astern = south = `+Z`), within 1 mm.
2. Heading follow: after a heading step of 90°, the chase azimuth is within 5 % of the new heading after
   `3·tau_yaw` = 1.05 s; with `tau_yaw = 0` at once.
3. Frame-rate independence: holding orbit for 1 s gives 120° ± 0.5° at 30, 60 and 144 fps.
4. Water clearance: 10 minutes of chase at `el = 2°` in `Hs = 1.5 m`: the eye is never below `sea_height + 0.99`.
5. Onboard side: a tack at `t = 0` (tack sign flips) puts the eye on the new windward side by
   `0.6 + 2·yh_abs/1.5` s (±1 frame) and never crosses outside the deck edge. On the generated `wm7` and `wm12`
   the eye follows §3 (tiller: 0.15 m forward of the tiller's tip, seated 0.80 m above the side deck; wheel: 0.7·R
   behind the hub and 0.55·R to windward, standing 1.60 m above the cockpit floor), is at least 0.3 m from the
   model's meshes (sails excluded) where it sits and along the crossing; on `wm12` the wheel's top and windward
   rim project into the lower half of the default frame, and the wheel and tiller meshes are visible; the
   default `fov` is 75°.
6. Aerial up modes: with `up = north` the scene `−Z` direction points to the top of the screen; with `up = wind` the
   true wind comes from the top of the screen within 1°.
7. Presets: store in slot 3, change every parameter, recall slot 3: all parameters and the mode restored exactly;
   factory reset restores the eight chase presets.
8. Shake: a contact at 2 m/s gives a peak offset of 0.08 m and less than 5 % of it after 0.9 s.
9. Start line shot: with `P` at (0, 0), the committee boat end `C` at (100, 0) (east, north) and the pre-start
   side to the south, the eye is at east 120 m, north −12 m, 8 m up, and looks at `P` within 0.1°.
10. Mark shot: `M` at (0, 500) approached from `Q` = (0, 0): left to port the eye is at bearing 225° from `M`
   (east −28.28, north 471.72, 6 m up), left to starboard at 135°; with two boats in the zone it aims at the one
   ahead in race order, with the zone empty at the viewed boat.
11. Long lens and helicopter: boat at the origin, `ψ = 0`: the long lens eye at `(0, 150·sin 5° + 1,
   150·cos 5°)` with `fov` 12°; the helicopter eye 120 m astern and 60 m up when selected, and after 18 s at
   60 fps 120 m to the west (90° clockwise), within 1 cm.
12. Choosing: without a course `camera_clip` gives long lens, helicopter, long lens; with one start line, mark,
   long lens, helicopter, start line; `camera_next` from a clip camera gives chase; with clip cameras not allowed
   (online) the key changes nothing; store while a clip camera is shown leaves the presets as they were.
13. Follow and bank (§2.1): a 90° heading step is followed at least as fast as a first-order filter of 0.35 s at
   every frame and never past the new heading; in a steady turn at 25°/s the camera lags by at most 0.35 s and banks
   right, never past 1.5°; speeding up at 1 m/s² for 2 s leaves the eye where it was behind the boat (within 1 mm);
   at 25° heel the eye and the aim are those of the upright boat; with the bank off or reduced motion no bank.
14. Lens: chase, onboard, aerial, free, start line and helicopter have no depth of field; the long lens focuses
   at about 150 m with the whole boat inside the sharp zone and follows the boat as she moves away; the mark shot
   has depth of field; none on tier L. No camera has a vignette: the rig adds no 2-D layer over the 3-D image.

15. Finish view: `ease_to` the finish view from the chase camera at a boat at the origin: the first frame's eye is
   the chase eye (within 1 cm), after 2.5 s the drift's (45 to 70 m from the boat, 5 to 11 m up), and halfway in
   between neither; `camera_next` from it gives chase; the profile keeps chase.

16. Shot scripts (§9.2): a file loads, a wrong schema, an unknown action, a cue without a time or with two
   actions is refused; cues run in time order; a camera cue selects its mode (a clip camera with the course); a
   `slow`, `pause`, `resume`, `hud`, `tags` and `input` cue act as their keys do and the shot time keeps running
   through the pause; `end` (and `--quit-at`) end the run; a race shot with `start` begins at that time from the gun.
17. Trackpad zoom: a camera input of −2.5 notches (a pan gesture, `controls.md` §8 test 11) sets the chase `R`
   to `R / 1.12^−2.5` within 1e-6 (fractional notches, no rounding), and +2.5 the inverse; the aerial `H` and the
   onboard `fov` follow the same factor.

## 11. Later: TV director and replay

- **Replay** (`networking.md` §14): the four regular cameras and the clip cameras on the re-simulated race, plus a timeline (pause, ×0.25 to
  ×8, scrub, jump to events), the viewed boat free to choose, and scripted camera paths for clips (keyframes of eye,
  aim and `fov`, Catmull-Rom through them, constant speed along the path).
- **TV director** for spectators and replays. Shots: the four clip cameras of §9 (start line, mark,
  long lens, helicopter) and the *onboard* of the boat in the action. The action is scored per second: boats within their
  zone at a mark, pairs with a keep-clear relation in `Warning` or `Breach` (`rules.md` §11), lead changes, starts
  and finishes. A shot lasts 6–12 s, never less than 3 s; a new shot keeps the camera on the same side of the
  boats' line of travel as the last one.
