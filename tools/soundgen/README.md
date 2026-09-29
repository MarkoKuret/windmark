# soundgen: the synthesised default sound set

Writes the default sound set of `docs/specs/audio.md` (§10) into `game/audio/default`: every boat, wind, race,
ambience and course-object sound the default map (`game/data/sound_map.json`) names, made from shaped noise, tones
and impulses. No samples or recordings go in, so the files are our own.

```
python3 tools/soundgen/soundgen.py                  # all files, Ogg Vorbis
python3 tools/soundgen/soundgen.py --only race/horn # one file
python3 tools/soundgen/soundgen.py --wav --out DIR  # WAV, no ffmpeg needed
```

Needs NumPy, and ffmpeg for the Ogg output (its built-in Vorbis encoder, quality 2; it writes two identical
channels for the mono sounds). 22.05 kHz, about 770 kB for the whole set. The output is deterministic (a fixed
seed per file name). Loops are built on a circular buffer (noise shaped in the frequency domain, modulations with
whole cycles over the loop), so they repeat without a seam; every file peaks at or below -1 dBFS.

A recording replaces a synthesised file by writing over it with the same name, or through the map (a different
file name, more variants). After changing files, `godot --headless --path game --import` (the test runners do it).
