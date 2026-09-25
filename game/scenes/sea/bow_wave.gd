class_name BowWave
extends RefCounted
## Bow wave sheets and mist (water_render.md §5): per boat, a sheet of water on each side that peels off the stem
## into a foam crest, rebuilt every frame from the boat pose (draped on the drawn sea by shaders/bow_wave.gdshader),
## and the soft mist clouds thrown off it at speed or when the bow plunges. World coordinates are ENU metres.

const NS := 14
const NT := 7
const TAU_CREST := 0.45
const GRAVITY := 9.81
const MIST_RATE := 14.0
const MIST_MAX := 256
const MIST_GRAVITY := 2.0
const MIST_DRAG := 2.5
const MIST_ALPHA := 0.16


## Smoothed drivers of one boat, advanced at every wake emission: speed v (m/s), speed ratio, plunge (m/s).
class Drivers:
	var v := 0.0
	var ratio := 0.0
	var plunge := 0.0
	var last_rel := NAN
	var mist_acc := 0.0

	## dt: time since the last emission (s); rel: the bow's height above the sea (m).
	func advance(dt: float, v_new: float, ratio_new: float, rel: float) -> void:
		var k := 1.0 - exp(-dt / 0.3)
		v += (v_new - v) * k
		ratio += (ratio_new - ratio) * k
		var p := 0.0
		if not is_nan(last_rel) and dt > 0.0:
			p = maxf(0.0, -(rel - last_rel) / dt)
		last_rel = rel
		plunge += (p - plunge) * k


## Visibility of the bow wave at a speed ratio (none at low speed).
static func strength(ratio: float) -> float:
	return smoothstep(0.25, 0.6, ratio)


## Crest height (m) and length along the hull (m).
static func size(d: Drivers, lwl: float) -> Vector2:
	var pl := minf(d.plunge, 1.5)
	var h := minf(0.08 * lwl, 0.55 * d.v * d.v / (2.0 * GRAVITY)) * (1.0 + 0.6 * pl)
	var l := lwl * (0.18 + 0.22 * minf(d.ratio, 1.3)) * (1.0 + 0.3 * pl)
	return Vector2(h, l)


## Mesh arrays of both sheets (port first) for a boat state (SeaWakes.update_boat keys) and its drivers; empty
## arrays when the wave is not visible. Scene axes with y = 0 (the shader drapes it): UV (tau, sigma),
## UV2 (lift above the sea, distance aft of the stem), COLOR.a the alpha.
static func build_arrays(st: Dictionary, d: Drivers) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var k := strength(d.ratio)
	if k <= 0.0:
		return arrays
	var lwl: float = st.get("lwl", 6.0)
	var bwl: float = st.get("bwl", 2.0)
	var psi: float = st.get("psi", 0.0)
	var heel: float = st.get("heel", 0.0)
	var fwd := Vector2(sin(psi), cos(psi))
	var port := Vector2(-fwd.y, fwd.x)
	var pos := Vector2(st.get("x", 0.0), st.get("y", 0.0))
	var stem := pos + fwd * float(st.get("bow_x", 0.5 * lwl))
	var hl := size(d, lwl)
	var sh := absf(sin(heel))
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for side in 2:
		var sgn := 1.0 if side == 0 else -1.0
		# heel > 0 puts the starboard side down: the lee side there has the bigger wave
		var lee := (-1.0 if heel > 0.0 else 1.0) * sgn
		var hs := 1.0 + 0.6 * lee * sh
		var base := verts.size()
		for i in NS:
			var sg := float(i) / float(NS - 1)
			var along := sg * hl.y
			var yh := 0.5 * bwl * pow(minf(1.0, along / (0.5 * lwl)), 0.7) * (1.0 + 0.5 * lee * sh)
			var width := (0.12 + 0.5 * along) * (1.0 + 0.3 * d.ratio)
			var li := hl.x * hs * pow(1.0 - sg, 1.6)
			var lc := 0.75 * hl.x * hs * pow(1.0 - sg, 0.7)
			var a := k * smoothstep(0.0, 0.08, sg) * (1.0 - smoothstep(0.7, 1.0, sg))
			for j in NT:
				var tau := float(j) / float(NT - 1)
				var lift := lerpf(li, lc, smoothstep(0.0, TAU_CREST, tau)) if tau <= TAU_CREST \
						else lc * (1.0 - smoothstep(TAU_CREST, 1.0, tau))
				var q := stem - fwd * along + port * sgn * (yh - 0.02 + tau * width)
				verts.append(Vector3(q.x, 0.0, -q.y))
				uvs.append(Vector2(tau, sg))
				uv2s.append(Vector2(lift + 0.1, along))
				cols.append(Color(0.0, 0.0, 0.0, a))
		for i in NS - 1:
			for j in NT - 1:
				var v0 := base + i * NT + j
				idx.append_array([v0, v0 + NT, v0 + 1, v0 + 1, v0 + NT, v0 + NT + 1])
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays


## Mist sprites to launch over dt (s): the rate grows above ratio 0.55 (with the spray pulse) and with the plunge.
static func mist_count(d: Drivers, pulse: float, dt: float) -> int:
	var rate := MIST_RATE * (clampf((d.ratio - 0.55) / 0.5, 0.0, 1.0) * pulse + 0.8 * clampf(d.plunge, 0.0, 1.5))
	d.mist_acc += rate * dt
	var n := int(floor(d.mist_acc))
	d.mist_acc -= n
	return n


## One mist sprite on the crest of a boat's bow wave: {pos, vel (ENU), age, life, s0, s1, seed}.
static func mist_sprite(st: Dictionary, d: Drivers, sea_z: float, boat_vel: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var lwl: float = st.get("lwl", 6.0)
	var bwl: float = st.get("bwl", 2.0)
	var psi: float = st.get("psi", 0.0)
	var heel: float = st.get("heel", 0.0)
	var fwd := Vector2(sin(psi), cos(psi))
	var port := Vector2(-fwd.y, fwd.x)
	var hl := size(d, lwl)
	var sg := rng.randf_range(0.05, 0.35)
	var along := sg * hl.y
	# the lee side twice as often
	var p_port := 0.5
	if absf(heel) > 0.05:
		p_port = 0.67 if heel < 0.0 else 0.33
	var on_port := rng.randf() < p_port
	var sgn := 1.0 if on_port else -1.0
	var yh := 0.5 * bwl * pow(minf(1.0, along / (0.5 * lwl)), 0.7)
	var width := (0.12 + 0.5 * along) * (1.0 + 0.3 * d.ratio)
	var stem := Vector2(st.get("x", 0.0), st.get("y", 0.0)) + fwd * float(st.get("bow_x", 0.5 * lwl))
	var q := stem - fwd * along + port * sgn * (yh + TAU_CREST * width)
	var out := port * sgn * rng.randf_range(0.8, 2.0) * d.ratio + boat_vel * 0.7
	var up := rng.randf_range(0.5, 1.5) * (1.0 + minf(d.plunge, 1.5))
	return {
		"pos": Vector3(q.x, q.y, sea_z + 0.75 * hl.x), "vel": Vector3(out.x, out.y, up), "age": 0.0,
		"life": rng.randf_range(0.8, 1.3), "s0": 0.5, "s1": 1.2 + 0.8 * minf(d.ratio, 1.2), "seed": rng.randf(),
	}


## Advances a mist sprite by dt; false when it has lived out.
static func mist_step(m: Dictionary, dt: float) -> bool:
	m["age"] += dt
	if m["age"] >= m["life"]:
		return false
	var v: Vector3 = m["vel"] * exp(-MIST_DRAG * dt)
	v.z -= MIST_GRAVITY * dt
	m["vel"] = v
	m["pos"] += v * dt
	return true


## Size (m) and alpha of a mist sprite now.
static func mist_look(m: Dictionary) -> Vector2:
	var f: float = m["age"] / m["life"]
	var a := MIST_ALPHA * clampf(m["age"] / 0.12, 0.0, 1.0) * (1.0 - f) * (1.0 - f)
	return Vector2(lerpf(m["s0"], m["s1"], sqrt(f)), a)
