class_name SoundSynth
extends RefCounted
## The synthesised fallback of audio.md §10, made once at load as a looping or one-shot AudioStreamWAV: wind (pink
## noise through a band-pass at F_REF["wind"]), water (brown noise through a low-pass at F_REF["water"]), the horn
## (440 and 554 Hz with a slow attack, 1 s; `horn_long` 2.5 s). The players move the filter by pitch:
## pitch_factor(kind, inputs) = f / f_ref, with f = 300 + 25 aws (wind) or 600 + 60 v_kn (water).

const RATE := 22050
const LOOP_S := 2.0
const F_REF := {"wind": 800.0, "water": 1200.0}
const KINDS := ["wind", "water", "horn", "horn_long"]


static func has_kind(kind: String) -> bool:
	return kind in KINDS


static func is_loop(kind: String) -> bool:
	return kind == "wind" or kind == "water"


## The fallback stream of a kind, null for an unknown kind (made each call: SoundMap keeps it with the sound).
static func stream(kind: String) -> AudioStreamWAV:
	if not has_kind(kind):
		return null
	var s: PackedFloat32Array
	match kind:
		"wind":
			s = _noise_loop(true)
		"water":
			s = _noise_loop(false)
		"horn":
			s = _horn(1.0)
		"horn_long":
			s = _horn(2.5)
	return _wav(s, is_loop(kind))


## The pitch multiplier that moves the fallback's filter to its driven frequency (1 for the horn).
static func pitch_factor(kind: String, inputs: Dictionary) -> float:
	match kind:
		"wind":
			return (300.0 + 25.0 * float(inputs.get("aws", 0.0))) / F_REF["wind"]
		"water":
			return (600.0 + 60.0 * absf(float(inputs.get("v_kn", 0.0)))) / F_REF["water"]
	return 1.0


## Pink (wind) or brown (water) noise through its filter, LOOP_S long; the last 0.1 s is crossfaded into the
## start so it loops without a click.
static func _noise_loop(wind: bool) -> PackedFloat32Array:
	var r := RandomNumberGenerator.new()
	r.seed = 7 if wind else 11
	var n := int(LOOP_S * RATE)
	var fade := int(0.1 * RATE)
	var total := n + fade
	var raw := PackedFloat32Array()
	raw.resize(total)
	# pink: Paul Kellet's economy filter; brown: leaky integrator
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var br := 0.0
	for i in total:
		var w := r.randf_range(-1.0, 1.0)
		if wind:
			b0 = 0.99765 * b0 + w * 0.0990460
			b1 = 0.96300 * b1 + w * 0.2965164
			b2 = 0.57000 * b2 + w * 1.0526913
			raw[i] = b0 + b1 + b2 + w * 0.1848
		else:
			br = 0.995 * br + w * 0.1
			raw[i] = br
	# RBJ biquad: band-pass (Q 0.7) for the wind, low-pass (Q 0.707) for the water
	var f0: float = F_REF["wind" if wind else "water"]
	var w0 := TAU * f0 / RATE
	var q := 0.7
	var alpha := sin(w0) / (2.0 * q)
	var cw := cos(w0)
	var bb := [0.0, 0.0, 0.0]
	if wind:
		bb = [alpha, 0.0, -alpha]
	else:
		bb = [(1.0 - cw) / 2.0, 1.0 - cw, (1.0 - cw) / 2.0]
	var a0 := 1.0 + alpha
	var a1 := -2.0 * cw
	var a2 := 1.0 - alpha
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var peak := 1e-6
	for i in total:
		var x := raw[i]
		var y: float = (bb[0] * x + bb[1] * x1 + bb[2] * x2 - a1 * y1 - a2 * y2) / a0
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		raw[i] = y
		peak = maxf(peak, absf(y))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = raw[i]
	for i in fade:  # the tail over the head
		var k := float(i) / fade
		out[i] = raw[i] * k + raw[n + i] * (1.0 - k)
	for i in n:
		out[i] *= 0.7 / peak
	return out


static func _horn(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var y := 0.0
		for f in [440.0, 554.0]:
			for h in [1, 2, 3]:
				y += sin(TAU * f * h * t) / (h * h)
		var env := minf(t / 0.15, 1.0) * clampf((seconds - t) / 0.12, 0.0, 1.0)
		out[i] = 0.3 * y * env
	return out


static func _wav(s: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w
