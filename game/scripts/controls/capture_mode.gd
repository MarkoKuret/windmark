class_name CaptureMode
extends RefCounted
## controls.md §7 capture: the clean pause and the slow-motion rate of offline sessions, and the world tags
## toggle. The scene feeds its SimRunner with sim_dt(frame dt); the cameras, the HUD smoothing and the sound keep
## the real frame time. Online (`allowed` off) the two capture actions do nothing; the world tags toggle works in
## every session.

## the slow-motion rates `capture_slow` cycles through, ×1 first
const RATES: Array[float] = [1.0, 0.5, 0.25]

## offline: the capture actions take effect
var allowed := true
## clean pause: no ticks, no menu, no label
var frozen := false
## index into RATES
var rate_index := 0
## the world tags and the on-water guides are shown
var world_tags := true


## The actions of one frame. Returns true when the world tags toggle changed.
func handle(r: RawInput) -> bool:
	if allowed:
		if r.was_pressed(&"capture_pause"):
			frozen = not frozen
		if r.was_pressed(&"capture_slow"):
			rate_index = (rate_index + 1) % RATES.size()
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


## A restart (reset_boat, the pause menu): back to ×1 and running; the world tags choice stays.
func reset() -> void:
	frozen = false
	rate_index = 0
