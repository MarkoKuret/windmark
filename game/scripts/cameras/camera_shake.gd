class_name CameraShake
extends RefCounted
## cameras.md §8: shake on a contact of the viewed boat, value noise at 12 Hz decaying with tau = 0.3 s.
## The positional offset has exactly the envelope's length (its direction wanders), so its peak is the amplitude.

const RATE := 12.0
const TAU := 0.3
const MIN_SPEED := 0.3

var amp_pos := 0.0  # m
var amp_rot := 0.0  # rad
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _keys_p: Array[Vector3] = []
var _keys_r: Array[Vector3] = []
var _k := -1


func _init(seed_value := 1) -> void:
	_rng.seed = seed_value


## a contact `begin` event with its closing speed (m/s)
func contact(closing_speed: float) -> void:
	if closing_speed < MIN_SPEED:
		return
	amp_pos = maxf(amp_pos, minf(0.25, 0.04 * closing_speed))
	amp_rot = maxf(amp_rot, deg_to_rad(minf(1.5, 0.25 * closing_speed)))


func _rand_unit() -> Vector3:
	var v := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
	return v.normalized() if v.length() > 1e-3 else Vector3.RIGHT


## Advances by dt; returns [position offset, rotation offset (euler, rad)].
func advance(dt: float) -> Array:
	_t += dt
	var k := int(floor(_t * RATE))
	while _k < k + 1:
		_keys_p.append(_rand_unit())
		_keys_r.append(_rand_unit())
		_k += 1
		if _keys_p.size() > 3:
			_keys_p.pop_front()
			_keys_r.pop_front()
	var f := _t * RATE - k
	var n := _keys_p.size()
	var pl := _keys_p[n - 2].lerp(_keys_p[n - 1], f)
	var p := pl.normalized() if pl.length() > 1e-3 else _keys_p[n - 1]
	var r := _keys_r[n - 2].lerp(_keys_r[n - 1], f)
	var out := [p * amp_pos, r * amp_rot]
	var decay := exp(-dt / TAU)
	amp_pos *= decay
	amp_rot *= decay
	return out


func active() -> bool:
	return amp_pos > 1e-5 or amp_rot > 1e-6
