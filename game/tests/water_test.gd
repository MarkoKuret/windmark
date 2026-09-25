extends SceneTree
## Headless checks of the water renderer (water_render.md §9) against the core's samples written by
## core/tools/gen_sea_render_samples.cpp (run through tests/run_water_test.sh):
##   shaders parse; height parity (double mirror and a float32 emulation of the shader path) within 1 mm;
##   slope parity; far-field fade; puff parity within 1e-3; exposure parity within 1e-3; wake geometry;
##   the test scene runs on every tier.
## Exit code 0 when every check passes.

const SAMPLES := "res://generated/sea/sea_render_samples.json"
const SHADERS := {
	"res://shaders/water_l.gdshader": ["comp", "puff", "expo_tex", "detail_layer"],
	"res://shaders/water_m.gdshader": ["comp", "puff", "expo_tex", "wake_tex"],
	"res://shaders/water_h.gdshader": ["comp", "puff", "expo_tex", "wake_tex"],
	"res://shaders/sky.gdshader": ["sky_horizon", "sky_zenith", "sun_dir"],
	"res://shaders/wake.gdshader": ["comp", "grid_q"],
	"res://shaders/wake_normal.gdshader": [],
}

var failures := 0
var _f := PackedFloat32Array([0.0])
var _scene_frames := 0
var _scene: Node
var _tiers_left: Array = []


func f32(x: float) -> float:
	_f[0] = x
	return _f[0]


func sci(x: float) -> String:
	return String.num_scientific(x) if x != 0.0 else "0"


func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok  ", what)
	else:
		failures += 1
		print("FAIL  ", what)


func _init() -> void:
	print("water renderer checks")
	check_shaders()
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAMPLES)) if FileAccess.file_exists(SAMPLES) else null
	check(data is Dictionary, "core samples at %s (run tests/run_water_test.sh)" % SAMPLES)
	if data is Dictionary:
		for sc in data["scenarios"]:
			check_heights(sc)
			if sc.has("puffs"):
				check_puffs(sc)
				check_exposure(sc)
	check_fade()
	check_wake_ribbon()
	_tiers_left = [SeaQuality.Tier.L, SeaQuality.Tier.M, SeaQuality.Tier.H]
	_start_scene()


func check_shaders() -> void:
	for path in SHADERS:
		var s := load(path) as Shader
		var names := []
		for u in s.get_shader_uniform_list():
			names.append(u["name"])
		var ok: bool = s != null and (names.size() > 0 or SHADERS[path].is_empty())
		for n in SHADERS[path]:
			ok = ok and names.has(n)
		check(ok, "shader %s parses (%d uniforms)" % [path.get_file(), names.size()])


## §9.1 height parity at tick times, points up to 8 km, times up to 4 h.
func check_heights(sc: Dictionary) -> void:
	var m := SeaModel.new()
	m.set_components(sc["components"])
	m.set_exposure(sc["exposure"] if sc["exposure"] is Dictionary else {})
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst_d := 0.0
	var worst_s := 0.0
	var worst_slope := 0.0
	for h in sc["heights"]:
		var x: float = h[0]
		var y: float = h[1]
		var t: float = h[2]
		var core: float = h[3]
		worst_d = maxf(worst_d, absf(m.height(x, y, t) - core))
		# shader path: camera within 25 m of the point, phases in double then float, float arithmetic
		var ox := float(f32(x + rng.randf_range(-25.0, 25.0)))
		var oy := float(f32(y + rng.randf_range(-25.0, 25.0)))
		var ph := m.phases(t, ox, oy)
		var xl := f32(x - ox)
		var yl := f32(y - oy)
		var eta := 0.0
		for i in m.components.size():
			var c: Array = m.components[i]
			var arg := f32(f32(f32(f32(c[1]) * xl) + f32(f32(c[2]) * yl)) + f32(ph[i]))
			var fr := f32(arg - floor(arg))
			eta = f32(eta + f32(f32(c[0]) * f32(cos(f32(f32(TAU) * fr)))))
		var e := f32(m.exposure_at(float(f32(ox + xl)), float(f32(oy + yl))))
		worst_s = maxf(worst_s, absf(f32(eta * e) - core))
		var sl := m.slope(x, y, t)
		worst_slope = maxf(worst_slope, maxf(absf(sl.x - h[4]), absf(sl.y - h[5])))
	check(worst_d <= 0.001, "%s: double mirror height within 1 mm of the core (worst %s m, %d points)" % [
			sc["name"], sci(worst_d), sc["heights"].size()])
	check(worst_s <= 0.001, "%s: float shader path within 1 mm of the core (worst %s m)" % [sc["name"], sci(worst_s)])
	check(worst_slope <= 1e-3, "%s: slope within 1e-3 of the core (worst %s)" % [sc["name"], sci(worst_slope)])


## §9.3 puff parity: the shader's m (mirror, camera-relative uniforms) equals the core's puff_factor.
func check_puffs(sc: Dictionary) -> void:
	var w: Dictionary = sc["wind"]
	var tile: float = w["puff_tile"]
	var lo: float = 1.0 - w["cap_down"]
	var hi: float = 1.0 + w["cap_up"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var worst := 0.0
	var n := 0
	var inside := 0
	for p in sc["puffs"]:
		# a camera somewhere over the area, so the camera-relative packing and the tile wrap are exercised
		var ox := rng.randf_range(-1500.0, 1500.0)
		var oy := rng.randf_range(-1500.0, 1500.0)
		var packed := SeaModel.pack_puffs(p["patches"], ox, oy, tile)
		for s in p["samples"]:
			var mm := SeaModel.puff_factor_local(float(s[0]) - ox, float(s[1]) - oy, packed, tile, lo, hi)
			worst = maxf(worst, absf(mm - s[2]))
			n += 1
			if absf(s[2] - 1.0) > 1e-6:
				inside += 1
	check(worst <= 1e-3, "%s: puff factor within 1e-3 of the core (worst %s, %d points, %d in a patch)" % [
			sc["name"], sci(worst), n, inside])


## §9.4 exposure parity at random points.
func check_exposure(sc: Dictionary) -> void:
	var m := SeaModel.new()
	m.set_exposure(sc["exposure"])
	var worst := 0.0
	for s in sc["exposure_samples"]:
		worst = maxf(worst, absf(m.exposure_at(s[0], s[1]) - s[2]))
	check(worst <= 1e-3, "%s: exposure within 1e-3 of the core (worst %s, %d points)" % [
			sc["name"], sci(worst), sc["exposure_samples"].size()])


## §9.2 far-field fade: the typical height the grid fade removes (2 sigma of the removed components) in pixels
## of the tier's reference screen (60 deg vertical field of view), by distance from the camera, for the reference
## sea states (fetch 10 km at 10 to 25 kn, and 20 kn with a 0.8 m swell). Must stay below 3 px up to 3 km.
func check_fade() -> void:
	var src := SeaEnvSource.new()
	src.fetch_m = 10000.0
	var dists := [5.0, 10.0, 25.0, 50.0, 100.0, 200.0, 400.0, 800.0, 1600.0, 3000.0]
	var screen := {SeaQuality.Tier.L: 720.0, SeaQuality.Tier.M: 800.0, SeaQuality.Tier.H: 1080.0}
	var worst := 0.0
	print("  far-field fade: removed height (2 sigma) in pixels by distance (m)")
	print("      sea           tier " + " ".join(dists.map(func(d): return "%6d" % d)))
	for case in [[10.0, 0.0], [15.0, 0.0], [20.0, 0.0], [25.0, 0.0], [20.0, 0.8]]:
		src.wind_kn = case[0]
		var comps := src._placeholder_components()
		if case[1] > 0.0:
			comps.append_array(_swell(case[1], 8.0, 1.0))
		var m := SeaModel.new()
		m.set_components(comps)
		for tier in [SeaQuality.Tier.L, SeaQuality.Tier.M, SeaQuality.Tier.H]:
			var t := SeaQuality.get_tier(tier)
			var q := SeaRadialGrid.ratio(t["rings"])
			var row := []
			for d in dists:
				var s := SeaRadialGrid.spacing(d, q, t["segments"])
				var px: float = d * 2.0 * tan(deg_to_rad(30.0)) / screen[tier]
				var e := 2.0 * m.faded_sigma(s) / px
				worst = maxf(worst, e)
				row.append("%6.2f" % e)
			print("      %2d kn%s  %s    %s" % [case[0], " + swell" if case[1] > 0.0 else "        ", t["name"],
					" ".join(row)])
	src.free()
	check(worst < 3.0, "far-field fade: removed height below 3 px up to 3 km on every tier (worst %.2f px)" % worst)


## sea.md §3.2 swell components (random phases): r (0.92, 1, 1.08), w (0.5, 0.707, 0.5), +-8 deg.
func _swell(hs: float, tp: float, from: float) -> Array:
	var out := []
	var r := [0.92, 1.0, 1.08]
	var w := [0.5, 0.70710678, 0.5]
	var o := [-8.0, 0.0, 8.0]
	for i in 3:
		var T := int(tp * 1000.0 / r[i] + 0.5)
		var om := TAU * 1000.0 / T
		var kap := om * om / 9.81 / TAU
		var dir := from + PI + deg_to_rad(o[i])
		out.append([hs * 0.353553391 * w[i], kap * sin(dir), kap * cos(dir), 0.3 * i, T])
	return out


## §9.5 wake geometry: a boat at a steady 3 m/s; the half width 2 s behind the bow is w0 + 2.12 m (5 %), and rows
## stay where they were laid without current.
func check_wake_ribbon() -> void:
	var r := WakeRibbon.new()
	var flat := func(_x, _y): return 0.0
	var v := 3.0
	var w0 := 0.7
	var t := 0.0
	while t <= 3.0001:
		r.emit(t, Vector2(0.0, v * t), 0.0, v, w0, 0.5, true, v * t)
		r.step(t, 0.05, flat)
		t += 0.05
	t -= 0.05
	var row = null
	for k in r.rows:
		if absf(WakeRibbon.age(k, t) - 2.0) < 1e-6:
			row = k
	check(row != null, "wake: a row 2 s old exists")
	if row:
		var hw := WakeRibbon.half_width(row, t)
		check(absf(hw - (w0 + 2.12)) <= 0.05 * (w0 + 2.12), "wake: half width 2 s behind the bow %.3f m (expected %.3f)" % [
				hw, w0 + 2.12])
		var p0: Vector2 = row["p"]
		for i in 10:
			r.step(t + 0.05 * (i + 1), 0.05, flat)
		check(row["p"] == p0 and absf(p0.y - v * 1.0) < 1e-6, "wake: rows stay where they were laid")
	check(r.rows.size() <= WakeRibbon.N_ROWS, "wake: at most 80 rows")


func _start_scene() -> void:
	if _tiers_left.is_empty():
		_finish()
		return
	var tier: int = _tiers_left.pop_front()
	_scene = (load("res://scenes/water_test.tscn") as PackedScene).instantiate()
	_scene.get_node("Sea").quality = tier
	root.add_child(_scene)
	_scene_frames = 0


func _process(_delta: float) -> bool:
	if _scene == null:
		return false
	_scene_frames += 1
	if _scene_frames < 90:
		return false
	var sea: Sea = _scene.get_node("Sea")
	var t := sea.get_tier()
	var mesh: ArrayMesh = sea.get_node("Surface").mesh
	var nv: int = mesh.surface_get_array_len(0)
	check(nv == 1 + t["rings"] * t["segments"], "scene tier %s: grid %d vertices" % [t["name"], nv])
	var n_comp: int = sea.material.get_shader_parameter("n_comp")
	check(n_comp == sea.model.components.size() and n_comp > 0, "scene tier %s: %d sea components uploaded" % [
			t["name"], n_comp])
	var n_puff: int = sea.material.get_shader_parameter("n_puff")
	check(n_puff > 0, "scene tier %s: %d puff patches uploaded" % [t["name"], n_puff])
	var rib: Array = (_scene.get_node("Wakes") as SeaWakes).boat_ribbons(0)
	check(rib.size() == 2 and rib[0].rows.size() >= 5, "scene tier %s: wake ribbon laid (%d rows)" % [
			t["name"], rib[0].rows.size() if rib.size() else 0])
	# the uploaded phases equal the model's for the camera origin
	var comp: PackedVector4Array = sea.material.get_shader_parameter("comp")
	var ph := sea.model.phases(sea.render_time_ms, sea.origin.x, sea.origin.y)
	var worst := 0.0
	for i in n_comp:
		worst = maxf(worst, absf(comp[i].w - ph[i]))
	check(worst < 1e-6, "scene tier %s: uploaded phases match (worst %s cycles)" % [t["name"], sci(worst)])
	_scene.queue_free()
	_scene = null
	_start_scene()
	return false


func _finish() -> void:
	print("water renderer checks: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	quit(0 if failures == 0 else 1)
