class_name CaptureMode
extends RefCounted
## controls.md §7 capture: the clean pause and the slow-motion rate of offline sessions, and the world tags
## toggle. The scene feeds its SimRunner with sim_dt(frame dt); the cameras, the HUD smoothing and the sound keep
## the real frame time. Online (`allowed` off) the two capture actions do nothing; the world tags toggle works in
## every session. A rate change leaves a brief note (hud.md §16.6) that expires on the real frame time.

## the slow-motion rates `capture_slow` cycles through, ×1 first
const RATES: Array[float] = [1.0, 0.5, 0.25]
## the rate note of each rate (hud.md §16.6), player-facing
const RATE_NOTES: Array[String] = ["Normal speed", "Slow motion x0.5", "Slow motion x0.25"]
## s of real time the rate note shows, and the last part of it over which it fades out
const NOTE_TIME := 1.5
const NOTE_FADE := 0.4

## offline: the capture actions take effect
var allowed := true
## the capture keys are live (controls.md §7): the capture preset is on, a shot script runs, or the scene was
## started with --capture-keys; otherwise `capture_pause` and `capture_slow` do nothing (a stray key never freezes
## a race without a word). The world tags key always works. The scene sets it every frame.
var keys := true
## clean pause: no ticks, no menu, no label
var frozen := false
## index into RATES
var rate_index := 0
## the world tags and the on-water guides are shown
var world_tags := true
## the rate note on screen, "" for none, and its time left (s)
var note := ""
var note_t := 0.0


## The actions of one frame. Returns true when the world tags toggle changed.
func handle(r: RawInput) -> bool:
	if allowed and keys:
		if r.was_pressed(&"capture_pause"):
			frozen = not frozen
		if r.was_pressed(&"capture_slow"):
			rate_index = (rate_index + 1) % RATES.size()
			note = RATE_NOTES[rate_index]
			note_t = NOTE_TIME
	if r.was_pressed(&"world_tags"):
		world_tags = not world_tags
		return true
	return false


func rate() -> float:
	return RATES[rate_index] if allowed else 1.0


## The frame time the simulation is advanced by: 0 in a clean pause, else dt times the rate.
func sim_dt(dt: float) -> float:
	if allowed and frozen:
		return 0.0
	return dt * rate()


## Every frame, with the real frame time (not slowed by the rate, running in a clean pause): ages the rate note.
func frame(dt: float) -> void:
	note_t = maxf(note_t - dt, 0.0)
	if note_t <= 0.0:
		note = ""


## The rate note's opacity: 1 until its last NOTE_FADE s, then down to 0; 0 without a note.
func note_alpha() -> float:
	if note == "":
		return 0.0
	return clampf(note_t / NOTE_FADE, 0.0, 1.0)


## A restart (reset_boat, the pause menu): back to ×1 and running, no note; the world tags choice stays.
func reset() -> void:
	frozen = false
	rate_index = 0
	note = ""
	note_t = 0.0
