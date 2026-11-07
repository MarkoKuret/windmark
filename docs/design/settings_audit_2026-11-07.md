# Settings audit, 2026-11-07 (WM-193)

Every field of `game/scripts/settings.gd` and every row of `game/scenes/menu/settings_panel.gd` before the change,
where the game reads it (`grep -rn` over `game/`), and the decision. The rule: a row stays when the game reads it
and a player would look for it; a row that only tunes a design decision, or that another row already covers, goes.
Kept on the owner's word whatever the audit says: the helm mode (Set and hold default), SMAA/FXAA with the
integrated-GPU default, the quality tiers, render scale, the capture preset, HUD density and assists, the bindings.

Decisions: **keep**, **merge** (into one row), **drop** (the behaviour stays at its default in the code).

## Controls

| key | row | read by | class | decision |
| --- | --- | --- | --- | --- |
| `helm_mode` | Helm keys | `controls/player_controls.gd` (hold-to-steer release, set-and-hold) | used, worth a row | keep (owner's default, Set and hold) |
| `stick_dead_zone` | Stick dead zone | `player_controls.gd` stick input | used, worth a row (a drifting stick is a hardware fault the player must fix here) | keep |
| `stick_curve` | Stick curve | `player_controls.gd` `stick_gamma` | used, obscure: a taste knob on the helm's response curve nobody will tune without a plot | drop; `stick_gamma` stays 1.6 |
| `sheet_rate` | Sheet key rate | `player_controls.gd` `sheet_rate_scale` | used, obscure: scales the sheet keys' speed, a design decision (`controls.md` §2) | drop; the scale stays 1.0 |
| `sheet_turns_auto_trim_off` | Sheeting turns auto trim off | `player_controls.gd` `_sheet` | used, obscure: the auto-trim key is the way to hand the trim back | drop; stays off |
| `let_fly_toggle` | Let fly: Hold / Toggle | `player_controls.gd` | used | merge into **Held keys** |
| `helm_fine_toggle` | Fine helm: Hold / Toggle | `player_controls.gd` | used | merge into **Held keys** |
| `rankings_toggle` | Rankings: Hold / Toggle | `hud/hud.gd` `ui_input` | used | merge into **Held keys** |
| `camera_boost_toggle` | Camera boost: Hold / Toggle | `cameras/free_camera.gd` via `CamTypes.Options.boost_toggle` | used | merge into **Held keys** |
| `keys_toggle` (new) | Held keys: Hold / Toggle | the four above | one accessibility choice for every held key (a player who cannot hold a key wants all four as toggles) | the merged row, default Hold |
| `vibration` | Vibration | `controls/rumble.gd` `strength` | used, worth a row | keep (owner's range: Off, 10 % to 100 %) |
| `bindings` | Bindings list | `controls/bindings.gd` apply | used | keep |

## Cameras

| key | row | read by | class | decision |
| --- | --- | --- | --- | --- |
| `camera_speed` | Camera and look speed | every camera (`o.speed`) | used, worth a row | keep, named **Camera speed** |
| `invert_orbit_x` | Invert orbit, left and right | chase, aerial, helicopter cameras | used | merge into **Invert left and right** |
| `invert_orbit_y` | Invert orbit, up and down | chase, aerial cameras | used | merge into **Invert up and down** |
| `invert_look_x` | Invert look, left and right | onboard, free cameras | used, duplicates the orbit inversion for the player (one preference per axis, as every game offers) | merge into **Invert left and right** |
| `invert_look_y` | Invert look, up and down | onboard, free cameras | used, duplicates the orbit inversion | merge into **Invert up and down** |
| `invert_x`, `invert_y` (new) | Invert left and right, Invert up and down | set the orbit and the look inversion of the axis together | the merged rows | default off |
| `heel_follow` | Onboard heel follow | `cameras/onboard_camera.gd` | used, worth a row (feel and accessibility, `cameras.md` §3) | keep |
| `smooth_switch` | Smooth camera switch | `cameras/camera_rig.gd` (chase to aerial blend) | used, obscure: a 0.4 s blend between two of the four cameras | drop; cuts, the default of `cameras.md` §6 |
| `reduced_motion` | Reduced motion | camera rig, chase, onboard, finish cameras, the menu stage | used, accessibility | keep |

## HUD

| key | row | read by | class | decision |
| --- | --- | --- | --- | --- |
| `assist` | Assists | `hud.gd`, `sail_test.gd` (laylines, zone, countdown beeps) | used | keep (owner's) |
| `hud_density` | Instruments | `hud.gd` density, `density_auto` | used | keep (owner's) |
| `ui_scale` | Interface scale | `apply_display` (the window's content scale) | used | keep |
| `palette` | Colour palette | `hud/hud_style.gd` `set_palette` | used, accessibility | keep |

## Graphics

| key | row | read by | class | decision |
| --- | --- | --- | --- | --- |
| `quality` | Quality | sea, sky, boat view, mesh LOD, the menu stage | used | keep (owner's tiers L, M, H) |
| `render_scale` | Render scale | `apply_render_scale` (the viewport's 3D scale and upscaler) | used | keep (owner's) |
| `aa` | Anti-aliasing | `screen_space_aa` | used | keep (owner's SMAA/FXAA with the integrated-GPU default) |
| `fullscreen` | Display | `apply_display`, `sync_window_mode` | used | keep |
| `vsync` | Vertical sync | `apply_display` | used | keep |
| `fps_limit` | Frame rate limit | `apply_display`, the menu stage's cap | used | keep |
| `capture_preset` | Capture preset | `apply_capture`, `effective_render_scale`, the HUD's portrait layout | used, session only | keep (owner's) |
| `keep_window` | none | `sail_test.gd` shot scripts | session only, no row | keep (not a setting) |

## Audio

| key | row | read by | class | decision |
| --- | --- | --- | --- | --- |
| `master_volume` | Master | the Master bus | used | keep |
| `effects_volume` | Effects | `own_boat`, `fleet`, `wind` | used | keep |
| `signals_volume` | Signals | `race`, `voice` | used | keep |
| `ambience_volume` | Ambience | `ambience`, `venue` | used | keep |
| `interface_volume` | Interface | `ui` (the menu sounds) | used | keep |

## Menu and bindings sections of the file

| key | read by | decision |
| --- | --- | --- |
| `menu.last_setup` | the main menu's Continue and the setup pages, the results screen's Change setup | keep (no row) |
| `menu.welcomed` | the first-launch screen | keep (no row) |
| `bindings.bindings` | `Bindings.apply` | keep (the Bindings list) |

## Result

Before: 10 rows and the bindings in Controls, 8 in Cameras, 4 in HUD, 7 in Graphics, 5 in Audio (34 rows).
After: 4 and the bindings, 5, 4, 7, 5 (25 rows). Nothing was dead: every field was read somewhere, so the cuts
are taste knobs and duplicates. A settings file from an older build with the dropped keys loads without errors
(unknown keys are ignored) and the next save drops them; the merged keys start at their defaults (Hold, not
inverted), which is what every player but one who had set the old toggles had.

Follow-up outside this task's files: `controls.md` §6 still lists the stick curve, the sheet key rate scale and
the per-action hold or toggle; the game keeps those behaviours at their defaults and the settings screen no longer
offers them, so the table there wants the same cut.
