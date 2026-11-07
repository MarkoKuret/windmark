# Tonal one-shots in the default sound set, 2026-11-07 (WM-196 follow-up)

The owner still hears "the penalty signal" often in solo free sail after the sheet-load creak of `d4cdb57` (which
they did not notice as a change, and they liked the old sheet-load sound, so it is restored here). The race signals
cannot fire in free sail (`game/tests/free_sail_test.gd`), so the sound is one of the set's other one-shots. This
note measures every one-shot so the ones that could pass for a signal are visible.

## Method

Each Ogg is decoded with ffmpeg to mono 22.05 kHz. **Spectral flatness** is the geometric mean over the arithmetic
mean of the power spectrum (Hann windows of 1024 samples, hop 256) averaged over the frames within 30 dB of the
loudest one, taken over 200 Hz to 8 kHz (the Vorbis encoder leaves nothing above about 9 kHz, which would drag the
geometric mean to zero). A pure tone or a chord scores near 0, white noise near 1; the race signals all score
0.000 on this scale and the noise one-shots 0.2 or more. **Peak** is the loudest bin over the whole band, so a
thump's peak sits below 200 Hz. Loops (`*_loop`, the ambience beds, the luff flogs, `sheet_run`) are left out: they
do not read as a signal. `ui/focus` (45 ms) is measured from the generator's WAV because ffmpeg decodes no
samples from an Ogg that short.

Script: a NumPy script over `game/audio/default/*/*.ogg`; the same measure on 60 ms windows at each hit gives the
per-hit numbers below.

## The halyard clink, before and after

`amb/halyard_1` (`halyard_clink` in `tools/soundgen/soundgen.py`) plays in every mode, every 20 to 60 s at a random
bearing 30 m away (`audio.md` §6). Since `bbe5f97` the menu ambience (`menu_ambience.gd`) plays it too, so it is
heard before any race as well. It was three pure-tone pings at 1600 to 2000 Hz with 1.62x and 2.31x partials
and a 120 ms decay: a small bell. `race/penalty_done` is two pure pings at 659 and 880 Hz, `race/beep` a 1 kHz
tone, so a bell ping heard out of a race reads as a signal.

| file | flatness | peak Hz | peak dBFS | note |
| --- | --- | --- | --- | --- |
| `amb/halyard_1` before (`c172ad0`) | 0.000 | 1723 | -5.9 | three pure pings, bell |
| `amb/halyard_1` after | 0.357 | 1787 | -6.3 | three noise-burst hits through a resonant band |

The new recipe: a white-noise burst through a broad resonance (Q 1.2) at 1300 to 2400 Hz inside a 700 to 4500 Hz
band, with a 20 to 38 ms decay time constant, over a short low knock (250 to 1500 Hz, 7 ms); three or four hits at
0.12 to 0.45 s spacing. The rendered file has three hits at 0.08, 0.48 and 0.84 s; per hit (60 ms window):
flatness 0.18, 0.25 and 0.17, peak 1417, 1817 and 2183 Hz, 20 dB down in about 40 to 45 ms. The output is
deterministic (the same MD5 on two runs) and peaks at -6.3 dBFS.

## Every one-shot

| file | flatness | peak Hz | peak dBFS | s | reads as |
| --- | --- | --- | --- | --- | --- |
| `amb/engine_1` | 0.000 | 43 | -7.8 | 6.00 | low diesel rumble, tonal but far below the signals |
| `amb/gull_1` | 0.016 | 1464 | -5.6 | 1.40 | **flag**: a tonal chirp at 1 to 2 kHz, the only remaining tonal sound in the signal range outside `race/` and `ui/` |
| `amb/halyard_1` | 0.357 | 1787 | -6.3 | 1.60 | metallic slaps (this change) |
| `boat/boom_cross` | 0.531 | 108 | -1.7 | 0.93 | bang |
| `boat/collide_boat_1` | 0.016 | 151 | -1.0 | 0.93 | thud with a sine knock at 350 to 480 Hz; contact only |
| `boat/collide_boat_2` | 0.016 | 129 | -1.6 | 0.93 | same |
| `boat/collide_boat_3` | 0.024 | 108 | -1.0 | 0.93 | same |
| `boat/collide_hard` | 0.212 | 86 | -0.8 | 1.30 | crunch |
| `boat/collide_mark` | 0.001 | 151 | -2.0 | 0.74 | thump with a 700 to 500 Hz squeak; contact only |
| `boat/fill` | 0.486 | 65 | -2.6 | 1.00 | cloth snap |
| `boat/sheet_load` | 0.000 | 194 | -3.8 | 0.56 | restored buzz (240 to 150 Hz square wave, low-passed): tonal, below the signal range, fires on every trim settle |
| `boat/slap_1` | 0.580 | 108 | -3.2 | 0.46 | wave slap |
| `boat/slap_2` | 0.566 | 86 | -3.1 | 0.46 | wave slap |
| `boat/slap_3` | 0.572 | 108 | -2.9 | 0.46 | wave slap |
| `boat/slap_4` | 0.570 | 108 | -3.2 | 0.46 | wave slap |
| `race/beep` | 0.000 | 991 | -5.8 | 0.14 | signal |
| `race/horn` | 0.000 | 560 | -1.9 | 1.00 | signal |
| `race/horn_finish` | 0.000 | 495 | -1.9 | 1.00 | signal |
| `race/horn_long` | 0.000 | 560 | -1.9 | 2.50 | signal |
| `race/penalty` | 0.000 | 388 | -8.4 | 0.79 | signal |
| `race/penalty_done` | 0.000 | 883 | -4.1 | 0.93 | signal |
| `ui/accept` | 0.001 | 883 | -12.2 | 0.09 | menu |
| `ui/back` | 0.001 | 581 | -15.1 | 0.09 | menu |
| `ui/focus` | 0.001 | 1314 | -18.0 | 0.04 | menu |

Tonal (flatness below 0.05) outside `race/` and `ui/`: `amb/engine_1`, `amb/gull_1`, `boat/collide_boat_1..3`,
`boat/collide_mark`, `boat/sheet_load`. Of these only `amb/gull_1` sits in the signals' pitch range and plays
without the player doing anything (every 20 to 60 s, like the halyard); the contact sounds need a collision and
the engine and the sheet buzz are an octave or more below the lowest signal (388 Hz). If the owner still hears a
"signal" after this change, the gull is the next candidate; the fix would be the same kind (a breathier, noisier
cry) or a lower rate.

## Changes

- `game/audio/default/boat/sheet_load.ogg` and the `sheet_load` recipe are the pre-`d4cdb57` ones again (the WAV
  from the restored recipe is byte-identical to the old generator's).
- `amb/halyard_1.ogg` regenerated from the new `halyard_clink` recipe
  (`python3 tools/soundgen/soundgen.py --only amb/halyard_1`).
- The paused signal queue and `free_sail_test.gd` from `d4cdb57` stay.
