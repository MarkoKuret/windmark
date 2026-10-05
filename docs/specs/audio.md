# Audio

What a race sounds like and how each sound is driven by the simulation: the boats (water, wind, sails, winches,
hoists, collisions), the race signals, the ambience and the venue. Every sound is described by a **sound map**, a
data file that names the files and holds the formulas, so the whole sound set can be swapped without code changes.
Presentation only: nothing here feeds the simulation. Values come from the render state (`boat.md` §9, `sails.md`
§7) and the event streams of `race.md` §11, `rules.md` §11 and `collisions.md` §5.

## 1. Engine model

- **Listener** = the active camera (`cameras.md`). Onboard, the listener is the helmsman's eye, so the boat's own
  sounds come from where they are on deck.
- **Sources** are 3-D point sources (Godot `AudioStreamPlayer3D`) attached to boats, marks and venue objects, or
  2-D sounds (`AudioStreamPlayer`) for the wind at the listener, signals, ambience and UI.
- **Distance law** (every 3-D source): full level up to `d_min`, then `d_min/d` (−6 dB per doubling), silent from
  `50·d_min` (Godot: inverse-distance attenuation, `unit_size = d_min`, `max_db = 0`, `max_distance = 50·d_min`, no
  distance filter). Extended sources (a shore, a long ship) measure `d` to the nearest point of their box.
- **Gain** of a sound = `file_volume · formula_volume · bus_volume · setting_volume`, converted with
  `20·log10(g)`; a gain at or below 0.01 is silent and the player is stopped.
- **Pitch** = the formula pitch (Godot `pitch_scale`, clamped to 0.5–2). **Doppler off** by default (option: on,
  with the velocities scaled by 0.3 so passing boats swoosh without a siren effect).
- **Updates**: formulas, gates, the voice choice, ducking and the players' positions and buses are evaluated at
  30 Hz from the interpolated render state (the boat inputs at each tick); every frame each driven parameter is
  smoothed toward its last target with its own `tau` (default 0.1 s) so nothing clicks, and a player's volume or
  pitch is set only when it moved (by more than 0.05 dB or 0.1 %). Loops start at a random point in the file so the
  same loop on several boats never phases.
- **Voices**: at most 48 at once. Priority: the own boat, signals, then other boats by distance. Other boats get
  their full set within 150 m and only wake and collisions beyond; at most the 6 nearest other boats are voiced.

### 1.1 Buses and settings

| bus | contents | player setting |
| --- | --- | --- |
| `own_boat` | the viewed boat's sounds | effects |
| `fleet` | other boats | effects |
| `wind` | wind at the listener | effects |
| `race` | signals, finish, penalty and rule sounds | signals |
| `voice` | hails | voice |
| `ambience` | the ambience bed and its one-shots | ambience |
| `venue` | placed venue and course-object sources | ambience |
| `ui` | menus and HUD clicks | interface |

All buses feed `master`. A race signal ducks `ambience` and `venue` by 6 dB for 1.5 s. Pausing offline
(`controls.md` §7) ducks everything but `ambience` and `ui` by 12 dB.

## 2. Formula language

A driven value (volume or pitch) is a product of **terms**, each a clamped power law of one input:
```
term(in) = clamp(c + k * pow(fabs(x), p), lo, hi)       // x = the input's value; p defaults to 1
value    = product of the terms (1 when there are none)
```
A **gate** switches a looping sound on while its condition holds (`above`, `below`, `equals`, with a hold time
`hold_s` so it does not chatter), and a **trigger** plays a one-shot on an event or on a crossing of a value
(`rises_above`, `falls_below`, with a `cooldown_s`). In the map:

- a gate is one condition `{"in", "above" | "below" | "equals", "hold_s"}` or `{"all": [conditions], "hold_s"}`
  (every condition holds); `equals` takes a number or a list of numbers (any of them). The gate opens once its
  condition has held for `hold_s` and closes once it has failed for `hold_s` (default 0). A loop without a gate
  plays while its gain is above 0.01.
- a trigger is `{"in", "rises_above" | "falls_below": x}` (the value crosses x between two updates),
  `{"in", "changes_sign": true}`, `{"in", "from": a, "to": b}` (the value was a and is now b) or
  `{"event": name}`, each with an optional `when` (conditions that must hold at that moment) and `cooldown_s`
  (default 0): a trigger inside the cooldown of the last play is dropped.

Inputs:

| input | meaning | unit |
| --- | --- | --- |
| `v_kn` | boat speed through the water | kn |
| `sog_kn` | speed over ground | kn |
| `aws`, `tws` | apparent / true wind speed | m/s |
| `aws_kn`, `tws_kn` | the same | kn |
| `awa_abs` | `fabs(awa)` | rad |
| `heel_abs`, `pitch_rate` | `fabs(φ)`, `dθ/dt` | rad, rad/s |
| `helm_abs`, `helm_rate` | `fabs(h)`, `fabs(dh/dt)` | –, 1/s |
| `bow_dz` | vertical speed of the bow point relative to the sea surface under it (negative = bow dropping into the water) | m/s |
| `sail.<k>.luff` | `luff_shiver` of sail slot `k` (`main`, `front`, or a sail id) | 0..1 |
| `sail.<k>.motion` | 0 idle, 1 sheeting, 2 easing | – |
| `sail.<k>.beta_rate` | `fabs(dβ/dt)` | rad/s |
| `sail.<k>.phase`, `sail.<k>.progress` | hoist phase and progress | – |
| `sail.<k>.beta` | the sail angle β (signed) | rad |
| `sail.<k>.kite`, `sail.<k>.furling` | 1 for a spinnaker, 1 for a sail on a furler (class file) | – |
| `cam_height` | listener height above the sea | m |
| `cam_onboard` | 1 when the onboard camera is active | – |
| `cam_wind` | the camera factor `cam` of §4 | – |
| `closing_speed` | of the contact that fired an event trigger | m/s |
| `rub_v` | sliding speed of a contact still in contact (§3 `boat.rub`), 0 without one | m/s |
| `one` | 1 | – |

Sail slots `k`: `main`, `front` (the front sail that is up, sails.md §3.2), `change` (the front sail of the
running change step: the one being hoisted or dropped), or a sail id. A slot with no sail reads 0 everywhere.
The boat inputs are read once per tick from the tick's records (rates are the change over the tick), the camera
inputs every frame.

Events: `sail_phase(boat, sail, phase)` (`sails.md` §7), contact `begin` with `closing_speed` and `other_kind`
(`collisions.md` §5), race events (`race.md` §11), rules events (`rules.md` §11). Event triggers in the map:
`contact_boat`, `contact_mark` (a mark or course object), `contact_hard` (an obstacle or land).

## 3. Boat sounds

Positions are in the boat frame from the physics sidecar (`tools/boatgen/README.md`): `masthead`, `boom_pivot`,
`forestay_tack`, `rudder_stock`, the sails' centroids, and the bow and stern ends of the waterline. Defaults
(`d_min` in m); `x` below is `clamp(1.5·v_kn/20, 0, 1)`.

| sound | kind | where | `d_min` | drive |
| --- | --- | --- | --- | --- |
| `boat.hull` | loop | mid waterline | 15 | volume `clamp(0.5 + v_kn/20, 0.5, 1)`: water and hull knocks, present even at rest |
| `boat.wake` | loop | stern | 20 | volume `0.5 + 0.5·x`, pitch `0.8 + 0.3·x`: full at 13.3 kn |
| `boat.bow` | loop | bow | 15 | volume `clamp((v_kn − 2)/8, 0, 1)`: the bow wave, silent below 2 kn |
| `boat.slap` | one-shot, 4 variants | bow | 20 | trigger `bow_dz` falls below −0.4 m/s, cooldown 0.35 s; volume `clamp(fabs(bow_dz)/1.5, 0.2, 1)` |
| `boat.rig` | loop | masthead | 10 | volume `0.25·clamp(0.4 + aws/15, 0.4, 1)`: rig creak and humming stays |
| `boat.luff_main` | loop | main centroid | 15 | gate `sail.main.luff > 0.1`; volume `sail.main.luff`, pitch `tws_kn/30 + 0.7` |
| `boat.luff_front` | loop | front sail centroid | 15 | gate `sail.front.luff > 0.1`; volume `sail.front.luff`, pitch `tws_kn/30 + 0.7` (spinnakers: `+ 0.53`, a deeper flog, as the map entry `boat.luff_kite` gated on `sail.front.kite`) |
| `boat.winch` | loop | the sail's trimming winch (leeward primary for a front sail, the mainsheet block for the main) | 10 | gate `sail.<k>.motion == 1`; volume 0.6, pitch `0.95 + 0.1·clamp(sail.<k>.beta_rate/0.5, 0, 1)`: the ratchet |
| `boat.sheet_run` | loop | same | 10 | gate `sail.<k>.motion == 2`; volume `0.3 + 0.5·clamp(sail.<k>.beta_rate/0.8, 0, 1)`: rope running out |
| `boat.sheet_load` | one-shot | same | 10 | trigger when `motion` goes from 1 to 0: the sheet takes the load |
| `boat.boom_cross` | one-shot | boom pivot | 15 | trigger when the main's `β` changes sign with `beta_rate > 0.8`; volume `clamp(beta_rate/2, 0.3, 1)`: the gybe bang |
| `boat.halyard` | loop | mast foot | 10 | gate `phase == hoisting` of a front sail on a halyard (headsails, spinnakers): halyard running and the sail sliding up |
| `boat.fill` | one-shot | sail centroid | 15 | trigger spinnaker `progress` rises above 0.9 while `hoisting`: the kite filling |
| `boat.furl` | loop | forestay tack | 10 | gate `phase == hoisting` or `dropping` of a furling sail: the furler turning |
| `boat.drop` | loop | mast foot | 10 | gate `phase == dropping` of a sail on a halyard: cloth coming down and being gathered |
| `boat.collide_boat` | one-shot, 3 variants | contact point | 20 | trigger contact `begin` with another boat, `closing_speed ≥ 0.3`; volume `clamp(closing_speed/2.5, 0.25, 1)` |
| `boat.collide_mark` | one-shot | contact point | 15 | same with a mark or course object: fender thump and buoy |
| `boat.collide_hard` | one-shot | contact point | 25 | same with an obstacle or land |
| `boat.rub` | loop | contact point | 10 | gate: a contact pair still in contact (no `begin`) while the boats slide; volume `clamp(v_rel/2, 0.2, 0.8)` |

Only the viewed boat's sounds are on `own_boat`; the same map drives other boats on `fleet` with the voice rules of
§1. The **wind** is a listener sound, not a boat sound (§4). The sheet sounds (`boat.winch`, `boat.sheet_run`,
`boat.sheet_load`) are one map entry each with `"slots": ["main", "front"]` (§9). A contact sound plays at the
contact point on the bus of the boat it involves (`own_boat` when either boat is the viewed one).

## 4. Wind at the listener

2-D stereo on the `wind` bus, from the viewed boat's apparent wind:
```
base   = clamp(aws / 40, 0.2, 1)                          // full at 40 m/s, 0.2 below 8 m/s
cam    = cam_onboard ? 1.0 : clamp(1 - (cam_height - 5) / 200, 0.4, 0.8)
wind.bed      volume = base * cam
wind.whistle  volume = clamp((aws - 12) / 10, 0, 1) * cam  // rigging whistle from 23 kn apparent
```
The stereo balance turns with the apparent wind relative to the view: onboard, the wind is louder in the ear facing
`awa` (pan `0.6·sin(awa − look_yaw)`); in the other cameras it is centred.

## 5. Race signals and events

Signals come from the race event `Signal` (`race.md` §3.2, §11). Each kind maps to a sound and a count of sounds;
the default set uses a horn, the map can choose a gun. Signals play 2-D on the `race` bus when the signal event
happens, and also as a 3-D source at the committee boat (`d_min` 150 m) so it is heard from the right direction; a
late joiner does not hear past signals (`race.md` §3.2).

| event | sound | count | caption |
| --- | --- | --- | --- |
| warning signal | `race.horn` (1 s) | 1 | "Warning signal" |
| preparatory signal (flag up) | `race.horn` | 1 | "Preparatory signal" |
| one minute (prep flag down) | `race.horn_long` (2.5 s) | 1 | "One minute" |
| start | `race.horn` | 1 | "Start" |
| individual recall (X up) | `race.horn` | 1 | "Individual recall" |
| general recall | `race.horn` | 2, 0.8 s apart | "General recall" |
| own boat finishes | `race.horn_finish` | 1 | "Finished, 3rd" |
| other boat finishes | `race.horn_finish` at the committee boat, 3-D only | 1 | – |
| own penalty (`Penalty`) | `race.penalty` | 1 | "Penalty: rule 10" |
| penalty served (`PenaltyServed`) | `race.penalty_done` | 1 | "Penalty done" |
| rule warning, own boat has right of way (`RuleWarning`, `hud.md` §11) | `voice.hail_starboard`, `voice.hail_leeward`, `voice.hail_room` by the rule, 3-D at the own boat on `voice` | 1 per rising edge, cooldown 4 s | "Starboard!" |
| hail for room to tack (`Hail`) | `voice.hail_room_to_tack` at the hailing boat | 1 | "Room to tack!" |
| optional countdown assist (`hud.md` §14 Full) | `race.beep` at 30, 20, 10, 5, 4, 3, 2, 1 s before the start | 1 each | – |

The race sounds follow the HUD's `hud_event` (`game/README.md`, Race HUD): `signal`, `penalty` (only when its boat
is the viewed one), `penalty_served`, `rule_warning` (only when the viewed boat is the holder), `finished` (the own
finish). Other boats' finishes come from the race events. The hails are picked by the rule's code name through the
map's `hails` table (§9); a rule or sound the map does not name stays silent without a warning.

Mark roundings are silent by default (option: a soft tick on the own boat's `Rounded`).

## 6. Ambience

- **Bed**: a 2-D stereo loop on `ambience`, one of four by the true wind the viewed boat feels, smoothed with
  `τ = 10 s`: calm below 6 kn, moderate 6–14 kn, fresh 14–22 kn, strong above 22 kn; neighbouring beds crossfade over
  the 2 kn around each boundary. Volume 0.4.
- **One-shots**: gulls, distant engines, a halyard slapping on a moored boat: each venue lists its own, played
  every 20–60 s (uniform) at a random pan and 0.3–0.6 volume. Until venues have look files (§7) the map's
  `ambience.one_shots` list serves every venue; the random pan is a 3-D source 30 m from the listener at a
  random bearing, `d_min` 30 m.

## 7. Venue and course objects

- **Placed sources** from the venue's look file (a front-end file next to the venue physics file,
  `data_format.md` §6): each `{sound, pos, half_extents (optional box), d_min}`: surf on a beach or rocks, a harbour,
  a town, a road bridge, cicadas. All loop from load.
- **Course objects**: every mark carries `venue.buoy` (a bell or the water lapping on it, `d_min` 5 m); the
  committee boat `venue.committee` (idling engine, `d_min` 20 m); spectator and traffic boats `venue.motorboat`
  (`d_min` 25 m) with their own wake loop. The map names the course sounds in `course`:
  `{"buoy": id, "committee": id}`.

Venue look files do not exist yet, so the placed sources wait for them; the course objects play in race mode.

## 8. Captions

With captions on (`controls.md` §6) every sound with a caption in §5, plus contacts ("Contact with <boat>") and
flogging sails of the own boat ("Sails flogging" while `luff > 0.8` for 2 s), shows a caption line with the
direction of its source (an arrow on the screen edge) for 3 s. Captions are player-facing text: no em dashes.

## 9. The sound map

`game/data/sound_map.json` is the only place that names sound files. A different set is a folder with its own map,
chosen in the settings (`sound_set`). A missing file disables that sound with one warning in the log; everything
else keeps working, headless runs included.
```json
{
  "schema": "windmark.soundmap/1",
  "root": "res://audio/default",
  "sounds": {
    "boat.wake": {
      "files": ["boat/wake_loop.ogg"], "loop": true, "bus": "own_boat", "volume": 0.5,
      "space": "3d", "anchor": "stern", "d_min": 20,
      "volume_terms": [{"in": "v_kn", "c": 0.5, "k": 0.0375, "lo": 0.5, "hi": 1.0}],
      "pitch_terms":  [{"in": "v_kn", "c": 0.8, "k": 0.0225, "lo": 0.8, "hi": 1.1}]
    },
    "boat.luff_main": {
      "files": ["boat/luff_main.ogg"], "loop": true, "bus": "own_boat", "volume": 0.7,
      "space": "3d", "anchor": "sail:main", "d_min": 15,
      "gate": {"in": "sail.main.luff", "above": 0.1, "hold_s": 0.2},
      "volume_terms": [{"in": "sail.main.luff", "c": 0, "k": 1, "lo": 0, "hi": 1}],
      "pitch_terms":  [{"in": "tws_kn", "c": 0.7, "k": 0.0333, "lo": 0.5, "hi": 2.0}]
    },
    "boat.slap": {
      "files": ["boat/slap_1.ogg", "boat/slap_2.ogg", "boat/slap_3.ogg", "boat/slap_4.ogg"],
      "loop": false, "bus": "own_boat", "space": "3d", "anchor": "bow", "d_min": 20,
      "trigger": {"in": "bow_dz", "falls_below": -0.4, "cooldown_s": 0.35},
      "volume_terms": [{"in": "bow_dz", "c": 0, "k": 0.6667, "lo": 0.2, "hi": 1.0}]
    },
    "race.horn": {"files": ["race/horn.ogg"], "loop": false, "bus": "race", "space": "2d", "volume": 1.0}
  },
  "signals": {"warning": ["race.horn", 1], "prep_up": ["race.horn", 1], "prep_down": ["race.horn_long", 1],
              "start": ["race.horn", 1], "x_up": ["race.horn", 1], "general_recall": ["race.horn", 2]},
  "ambience": {"beds": ["amb/calm.ogg", "amb/moderate.ogg", "amb/fresh.ogg", "amb/strong.ogg"],
               "bounds_kn": [6, 14, 22], "crossfade_kn": 2, "volume": 0.4}
}
```
- `files` with more than one entry pick a random variant per play (never the same twice in a row).
- `anchor`: `bow`, `stern`, `mid`, `masthead`, `mast_foot`, `boom_pivot`, `forestay_tack`, `sail:<slot or id>`,
  `winch:<slot>`, `contact`, `listener`, or an explicit `[x, y, z]` in the boat frame.
- `slots` (a list of sail slots) makes one sound per slot from the entry: `<k>` in its inputs and anchor is
  replaced by the slot, and the sound is named `<id>:<slot>`.
- `synth` (`wind`, `water`, `horn`, or `horn_long` for the 2.5 s horn): the synthesised fallback of §10 when none
  of the entry's files exists.
- `hails`: rule code name (`hud.md` §12.3, e.g. `"10"`) to a `voice.*` sound; `course` (§7); `ambience.one_shots`
  (§6).
- A path that is not under `res://` (a sound set in `user://` or on disk) loads `.ogg` and `.wav` at run time.
- Unknown keys are ignored, so a newer map loads in an older build.

## 10. Assets

The default set must be our own recordings or permissively licensed (CC0 or CC-BY, `docs/THIRD_PARTY.md` gets a
row per file or pack; packs under custom "royalty-free" licences are not used). Until recordings exist, the default
set (`game/audio/default`) is **synthesised by our own tool** (`tools/soundgen`: filtered noise, tones and
impulses written as Ogg Vorbis, 22.05 kHz), so it is ours; a recording replaces a file by name or through the map.
The menu sounds (`ui/focus`, `ui/accept`, `ui/back`, `menus.md` §4) come from the same tool and play on the `ui`
bus outside the sound map.

A **synthesised fallback** keeps a sound audible when its files are missing (the map entry's `synth`): wind as
pink noise through a band-pass at `300 + 25·aws` Hz, water as brown noise through a low-pass at `600 + 60·v_kn` Hz,
the horn as a 440 Hz and 554 Hz pair with a slow attack; each fallback uses the same map entry and formulas. The
noise is made once at load with the filter at a reference frequency (wind 800 Hz, water 1200 Hz) and played with
its pitch multiplied by `f / f_ref` (moving the filter with it), within the pitch clamp of §1. A missing file still
warns once.

Not in the default set yet: the voice hails (`voice.*`) and the venue placed sources, which need recordings.

## 11. Tests (headless)

1. Formula evaluation: the `boat.wake` terms at 0, 6.67, 13.3, 20 kn give volume 0.5, 0.75, 1.0, 1.0 and pitch 0.8,
   0.95, 1.1, 1.1.
2. Gates: `boat.luff_main` starts when `luff` rises above 0.1 and has held 0.2 s, and stops the same way; a
   `luff` of 0.09 never starts it.
3. Triggers: a scripted `bow_dz` series crossing −0.4 m/s at 0, 0.2, 0.4, 0.6 and 0.8 s plays slaps at 0, 0.4 and 0.8 s (cooldown).
4. Signals: a 5-4-1-0 sequence produces horn, horn, long horn, horn at the signal ticks; a general recall two horns.
5. Swap: loading a second map with different files plays those files with no code change; a map with a missing file
   warns once and the race runs.
6. Voices: with 20 boats around the listener no more than 48 players are active and the own boat's sounds are never
   the ones dropped.
