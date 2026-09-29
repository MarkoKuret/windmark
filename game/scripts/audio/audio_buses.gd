class_name AudioBuses
extends RefCounted
## The buses of audio.md §1.1, made at run time (ensure()) so every scene has them: each feeds Master and carries
## an Amplify effect first ("duck", for the signal and pause ducking of §1.1), the wind bus a Panner after it (§4).
## The player's volumes are the buses' own volumes (Settings.apply_audio); the ducking stays in the effect, so the
## two never fight.

const NAMES := ["own_boat", "fleet", "wind", "race", "voice", "ambience", "venue", "ui"]
const DUCK := 0
const PAN := 1


## Adds the buses that are missing. Safe to call any number of times.
static func ensure() -> void:
	for n in NAMES:
		if AudioServer.get_bus_index(n) >= 0:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, n)
		AudioServer.set_bus_send(i, "Master")
		var amp := AudioEffectAmplify.new()
		amp.resource_name = "duck"
		AudioServer.add_bus_effect(i, amp, DUCK)
		if n == "wind":
			AudioServer.add_bus_effect(i, AudioEffectPanner.new(), PAN)


## The ducking of a bus, dB (0: none).
static func set_duck(bus: String, db: float) -> void:
	var fx := _effect(bus, DUCK) as AudioEffectAmplify
	if fx:
		fx.volume_db = db


static func duck(bus: String) -> float:
	var fx := _effect(bus, DUCK) as AudioEffectAmplify
	return fx.volume_db if fx else 0.0


## The wind's stereo balance, -1 (left) to 1 (right).
static func set_wind_pan(pan: float) -> void:
	var fx := _effect("wind", PAN) as AudioEffectPanner
	if fx:
		fx.pan = clampf(pan, -1.0, 1.0)


static func wind_pan() -> float:
	var fx := _effect("wind", PAN) as AudioEffectPanner
	return fx.pan if fx else 0.0


static func _effect(bus: String, slot: int) -> AudioEffect:
	var i := AudioServer.get_bus_index(bus)
	if i < 0 or AudioServer.get_bus_effect_count(i) <= slot:
		return null
	return AudioServer.get_bus_effect(i, slot)
