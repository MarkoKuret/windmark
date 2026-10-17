class_name BowWave
extends RefCounted
## Bow spray (water_render.md §5): the drivers of a boat's bow (speed, plunge, impact), the soft mist clouds and the
## burst droplet sheets thrown off the bow wave's crest at speed or when the bow meets a wave. The bow wave itself is
## not drawn (removed 2026-10-16: the sheet read as a knife edge); its crest size places the spray. World coordinates
## are ENU metres.

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
	## the impact: the bow's sink speed into the sea, quick (rise 0.05 s, decay 0.25 s), m/s
	var impact := 0.0
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
		if p > impact:
			impact += (p - impact) * (1.0 - exp(-dt / 0.05))
		else:
			impact *= exp(-dt / 0.25)


## The bow wave crest height (m) and length along the hull (m), where the spray leaves it.
static func size(d: Drivers, lwl: float) -> Vector2:
	var pl := minf(d.plunge, 1.5)
	var h := minf(0.08 * lwl, 0.55 * d.v * d.v / (2.0 * GRAVITY)) * (1.0 + 0.6 * pl)
	var l := lwl * (0.18 + 0.22 * minf(d.ratio, 1.3)) * (1.0 + 0.3 * pl)
	return Vector2(h, l)


## The impact burst I (0..2): the bow meeting the sea fast, at speed (water_render.md §5).
static func burst(d: Drivers) -> float:
	return clampf(d.impact / 0.6, 0.0, 2.0) * smoothstep(0.3, 1.0, d.ratio)


## Mist sprites to launch over dt (s): the rate grows above ratio 0.55 (with the spray pulse), with the plunge and
## with the impact burst.
static func mist_count(d: Drivers, pulse: float, dt: float) -> int:
	var rate := MIST_RATE * (clampf((d.ratio - 0.55) / 0.5, 0.0, 1.0) * pulse + 0.8 * clampf(d.plunge, 0.0, 1.5)
			+ 3.0 * burst(d))
	d.mist_acc += rate * dt
	var n := int(floor(d.mist_acc))
	d.mist_acc -= n
	return n


## One mist sprite on the crest of a boat's bow wave: {pos, vel (ENU), age, life, s0, s1, seed}, and for a burst's
## droplet sheet also {a: alpha scale, g: gravity, drag, k: 1 (the droplet look)}.
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
	var bi := burst(d)
	if bi > 0.0 and rng.randf() < bi / (1.0 + bi):
		# a sheet of droplets thrown off the flare: outboard and a little aft, flat, falling like water
		var sp := rng.randf_range(2.5, 4.5) * (0.5 + 0.5 * minf(d.ratio, 1.5)) * (0.6 + 0.4 * bi)
		var hz := port * sgn * sp - fwd * (0.15 * sp) + boat_vel * 0.85
		var vz := rng.randf_range(0.8, 1.6) * (0.5 + 0.5 * bi)
		return {
			"pos": Vector3(q.x, q.y, sea_z + 0.75 * hl.x), "vel": Vector3(hz.x, hz.y, vz), "age": 0.0,
			"life": rng.randf_range(0.35, 0.6), "s0": 0.25, "s1": rng.randf_range(0.6, 0.9), "seed": rng.randf(),
			"a": minf(1.0 + bi, 2.2), "g": GRAVITY, "drag": 1.0, "k": 1.0,
		}
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
	var v: Vector3 = m["vel"] * exp(-float(m.get("drag", MIST_DRAG)) * dt)
	v.z -= float(m.get("g", MIST_GRAVITY)) * dt
	m["vel"] = v
	m["pos"] += v * dt
	return true


## Size (m) and alpha of a mist sprite now.
static func mist_look(m: Dictionary) -> Vector2:
	var f: float = m["age"] / m["life"]
	var a := MIST_ALPHA * float(m.get("a", 1.0)) * clampf(m["age"] / 0.12, 0.0, 1.0) * (1.0 - f) * (1.0 - f)
	return Vector2(lerpf(m["s0"], m["s1"], sqrt(f)), a)
