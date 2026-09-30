extends SceneTree
## Headless checks of the water renderer (water_render.md §9) against the core's samples written by
## core/tools/gen_sea_render_samples.cpp (run through tests/run_water_test.sh):
##   shaders parse; height parity (double mirror and a float32 emulation of the shader path) within 1 mm;
##   slope parity; far-field fade; puff parity within 1e-3; exposure parity within 1e-3; the venue land factor
##   (wind.md §8) against the core's wind within 1e-3 (when the GDExtension is built) and the shader's texture path
##   against the mirror; wake geometry; the test scene runs on every tier.
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
	check_land_core()
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


## §4.3 venue land factor: SeaModel.land_factor_at (the mirror of wind.md §8 on the venue file) against the
## core's clean wind over its base speed (puffs off) at random points and directions. Skipped without the core.
func check_land_core() -> void:
	if not CoreSimSource.available():
		print("  --  land factor against the core: skipped (no GDExtension, game/native/build.sh)")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0.0
	var n := 0
	var lo := 1.0
	for from_deg in [0.0, 10.0, 44.0, 100.0, 181.0, 225.0, 300.0, 359.0]:
		var cs := CoreSimSource.new()
		cs.settings = {"puffs": false, "wind_speed": 8.0, "wind_from": deg_to_rad(from_deg)}
		if not cs.create("example_bay"):
			check(false, "land factor: core world on example_bay (%s)" % cs.last_error())
			return
		var w := cs.wind_state(0)
		var m := SeaModel.new()
		m.set_wind_field(SeaEnvSource.read_wind_field(cs.venue_path))
		for i in 250:
			var x := rng.randf_range(-3200.0, 3200.0)
			var y := rng.randf_range(-3200.0, 3200.0)
			var f := m.land_factor_at(x, y, w["global_from"])
			worst = maxf(worst, absf(cs.wind_clean(x, y).x / w["base_speed"] - f))
			lo = minf(lo, f)
			n += 1
	check(lo < 0.9, "land factor: the example bay field slows the wind somewhere (lowest %.3f)" % lo)
	check(worst <= 1e-3, "land factor within 1e-3 of the core's wind (worst %s, %d points)" % [sci(worst), n])


## §4.3 the shader's land path on the uploaded texture (float32 emulation of wm_land) against the mirror, and
## the texture following the wind direction.
func check_land_scene(sea: Sea, tier: String) -> void:
	if sea.model.wind_field.is_empty():
		check(false, "scene tier %s: the venue wind field reached the Sea" % tier)
		return
	var from: float = sea.wind.get("global_from", 0.0)
	var up := sea.land_upload()
	var s := SeaModel.land_sectors(from)
	check(up.size() == 3 and up[0] == s[0], "scene tier %s: land texture holds sectors %s for the wind from %.1f deg" % [
			tier, str(s.slice(0, 2)), rad_to_deg(from)])
	var rg: PackedFloat32Array = (up[2] as PackedByteArray).to_float32_array()
	var g := sea.model.wind_field
	var tw := f32(sea.material.get_shader_parameter("land_tw"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var worst := 0.0
	for i in 2000:
		var x := rng.randf_range(-3200.0, 3200.0)
		var y := rng.randf_range(-3200.0, 3200.0)
		worst = maxf(worst, absf(_land_emulated(x, y, g, rg, tw) - sea.model.land_factor_at(x, y, from)))
	check(worst <= 1e-3, "scene tier %s: shader land factor within 1e-3 of the mirror (worst %s)" % [tier, sci(worst)])
	# a direction a sector on uploads the next pair on the following frame
	sea.use_internal_clock = false
	var k_next: int = (int(s[0]) + 1) & 7
	sea._update_land(float(k_next) * PI * 0.25 + 0.1)
	check(sea.land_upload()[0] == k_next, "scene tier %s: land texture follows the wind into the next sector" % tier)


## §4.6 the sun's shadows follow the tier: cascades, distance, blend, bias; the sea takes shadows on M and H only;
## the sea, the wakes and the spray cast none.
func check_shadows(sea: Sea, t: Dictionary) -> void:
	var sun: DirectionalLight3D = (_scene.get_node("SkyDay") as SkyRig).sun()
	var want_mode := DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if t["shadow_splits"] == 4 \
			else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	var sp: Array = t["shadow_split"]
	var ok: bool = sun != null and sun.shadow_enabled and sun.directional_shadow_mode == want_mode \
			and is_equal_approx(sun.directional_shadow_max_distance, t["shadow_distance"]) \
			and is_equal_approx(sun.directional_shadow_split_1, sp[0]) \
			and (t["shadow_splits"] == 2 or (is_equal_approx(sun.directional_shadow_split_2, sp[1])
				and is_equal_approx(sun.directional_shadow_split_3, sp[2]))) \
			and sun.directional_shadow_blend_splits == t["shadow_blend"]
	check(ok, "scene tier %s: sun shadows %d cascades to %.0f m, splits %s" % [t["name"], t["shadow_splits"],
			t["shadow_distance"], sp])
	# the chase camera (24.5 m) sees its boat inside one cascade: the boat spans about 15 to 35 m
	var edges := [0.0]
	for k in t["shadow_splits"] - 1:
		edges.append(float(sp[k]) * float(t["shadow_distance"]))
	edges.append(float(t["shadow_distance"]))
	var one := false
	for k in edges.size() - 1:
		one = one or (edges[k] <= 15.0 and edges[k + 1] >= 35.0)
	check(one, "scene tier %s: the chase distance (15 to 35 m) lies in one cascade (edges %s m)" % [t["name"], edges])
	check(is_equal_approx(sun.shadow_bias, SeaQuality.SHADOW_BIAS) and is_equal_approx(sun.shadow_normal_bias,
			SeaQuality.SHADOW_NORMAL_BIAS) and sun.directional_shadow_pancake_size >= 30.0,
			"scene tier %s: shadow bias %.2f, normal bias %.1f, pancake %.0f m" % [t["name"], sun.shadow_bias,
			sun.shadow_normal_bias, sun.directional_shadow_pancake_size])
	var code: String = (sea.material.shader as Shader).code
	check(code.contains("WM_NO_SHADOWS") != bool(t["sea_shadows"]),
			"scene tier %s: the sea %s shadows" % [t["name"], "takes" if t["sea_shadows"] else "takes no"])
	var casts := 0
	for n in _scene.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and (g.get_parent() is Sea or g.get_parent() is SeaWakes):
			casts += 1
	check(casts == 0, "scene tier %s: sea, wakes and spray cast no shadows" % t["name"])


## §5 bow wave and mist: a boat sails straight on flat water at a set speed ratio for 3 s of render time on a
## tier; returns {wave: bow wave vertex count, mist: sprites alive, min_size, max_alpha, spray_nodes}.
func _sail_bow(tier: SeaQuality.Tier, ratio: float, heel := 0.0) -> Dictionary:
	var holder := Node3D.new()
	var sea := Sea.new()
	sea.quality = tier
	holder.add_child(sea)
	var wakes := SeaWakes.new()
	holder.add_child(wakes)
	wakes.sea = sea
	root.add_child(holder)
	var lwl := 6.8
	var v := ratio * 1.34 * sqrt(lwl / 0.3048) * 0.51444447
	var out := {"wave": 0, "mist": 0, "min_size": INF, "max_alpha": 0.0, "lift": 0.0, "lee_lift": 0.0, "wind_lift": 0.0}
	for f in 180:
		var t := f / 60.0
		sea.render_time_ms = 1000.0 * t
		sea.update_frame(Vector3(0.0, 5.0, -v * t + 15.0))
		wakes.update_boat(1, {"x": 0.0, "y": v * t, "z": 0.0, "psi": 0.0, "heel": heel, "pitch": 0.0, "lwl": lwl,
			"bwl": 2.0, "transom_width": 1.6, "bow_x": 0.5 * lwl, "stern_x": -0.5 * lwl, "own": true})
		wakes._process(1.0 / 60.0)
	var arrays := wakes.bow_wave_arrays(1)
	if not arrays.is_empty():
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		out["wave"] = pos.size()
		var half := pos.size() / 2
		for k in pos.size():
			out["lift"] = maxf(out["lift"], uv2[k].x)
			# port sheet first; heel > 0 puts starboard down (lee)
			if k < half:
				out["wind_lift"] = maxf(out["wind_lift"], uv2[k].x)
			else:
				out["lee_lift"] = maxf(out["lee_lift"], uv2[k].x)
	for m in wakes.mist_sprites():
		var look := BowWave.mist_look(m)
		out["min_size"] = minf(out["min_size"], look.x)
		out["max_alpha"] = maxf(out["max_alpha"], look.y)
	out["mist"] = wakes.mist_sprites().size()
	out["spray_nodes"] = wakes.get_node_or_null("Spray") != null
	holder.free()
	return out


func check_bow_spray() -> void:
	var slow := _sail_bow(SeaQuality.Tier.H, 0.2)
	check(slow["wave"] == 0 and slow["mist"] == 0, "bow: no bow wave and no mist at speed ratio 0.2")
	var mid := _sail_bow(SeaQuality.Tier.H, 0.45)
	check(mid["wave"] > 0 and mid["mist"] == 0, "bow: a bow wave and no mist at speed ratio 0.45 on flat water")
	var fast := _sail_bow(SeaQuality.Tier.H, 1.0, 0.3)
	check(fast["wave"] == 2 * BowWave.NS * BowWave.NT, "bow: two sheets of %d x %d at hull speed" % [BowWave.NS, BowWave.NT])
	check(fast["lift"] > mid["lift"] and fast["lift"] > 0.15 and fast["lift"] < 0.08 * 6.8 + 0.2,
		"bow: the crest rises with speed (%.2f m at 0.45, %.2f m at hull speed)" % [mid["lift"], fast["lift"]])
	check(fast["lee_lift"] > fast["wind_lift"], "bow: heeled, the lee sheet is higher (%.2f m, windward %.2f m)" % [
		fast["lee_lift"], fast["wind_lift"]])
	check(fast["mist"] > 5 and fast["min_size"] >= 0.5 and fast["max_alpha"] <= BowWave.MIST_ALPHA + 1e-6,
		"bow: mist at hull speed, %d soft sprites of at least 0.5 m (smallest %.2f m), alpha at most %.2f" % [
		fast["mist"], fast["min_size"], fast["max_alpha"]])
	check(not fast["spray_nodes"], "bow: no spray particles drawn (no dots)")
	var low_tier := _sail_bow(SeaQuality.Tier.L, 1.0)
	check(low_tier["wave"] > 0 and low_tier["mist"] == 0, "bow: tier L draws the bow wave without mist")


## A Sea with SeaWakes but no boat has no wake buffer; the first boat makes it, removing it drops it, and a tier
## change drops it until wakes are drawn again.
func check_wake_buffer_lifecycle() -> void:
	var holder := Node3D.new()
	var sea := Sea.new()
	sea.quality = SeaQuality.Tier.M
	holder.add_child(sea)
	var wakes := SeaWakes.new()
	holder.add_child(wakes)
	wakes.sea = sea
	root.add_child(holder)
	sea.update_frame(Vector3.ZERO)
	wakes._process(0.016)
	check(wakes.wake_buffer() == null, "wakes: no wake buffer without boats")
	wakes.update_boat(5, {"x": 0.0, "y": 0.0, "psi": 0.0, "own": true})
	sea.render_time_ms += 16.0
	wakes._process(0.016)
	check(wakes.wake_buffer() != null, "wakes: the first boat makes the wake buffer")
	sea.quality = SeaQuality.Tier.L
	wakes._process(0.016)
	check(wakes.wake_buffer() == null, "wakes: no wake buffer on tier L")
	sea.quality = SeaQuality.Tier.H
	wakes._process(0.016)
	check(wakes.wake_buffer() != null, "wakes: wake buffer again on tier H")
	wakes.remove_boat(5)
	wakes._process(0.016)
	check(wakes.wake_buffer() == null, "wakes: wake buffer dropped with the last boat")
	holder.queue_free()


func _land_emulated(x: float, y: float, g: Dictionary, rg: PackedFloat32Array, tw: float) -> float:
	var nx: int = g["nx"]
	var ny: int = g["ny"]
	var px := f32(x)
	var py := f32(y)
	if px < g["x0"] or py < g["y0"] or px > g["x0"] + (nx - 1) * g["dx"] or py > g["y0"] + (ny - 1) * g["dy"]:
		return 1.0
	var u := f32((px - g["x0"]) / g["dx"])
	var v := f32((py - g["y0"]) / g["dy"])
	var i := mini(int(u), nx - 2)
	var j := mini(int(v), ny - 2)
	var tx := f32(u - i)
	var ty := f32(v - j)
	var out := [0.0, 0.0]
	for c in 2:
		var r0 := lerpf(rg[2 * (j * nx + i) + c], rg[2 * (j * nx + i + 1) + c], tx)
		var r1 := lerpf(rg[2 * ((j + 1) * nx + i) + c], rg[2 * ((j + 1) * nx + i + 1) + c], tx)
		out[c] = f32(lerpf(r0, r1, ty))
	return f32(lerpf(out[0], out[1], tw))


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


## §9.6 wake geometry: a boat at a steady 3 m/s; the half width 2 s behind the bow is w0 + 2.12 m (5 %), and rows
## stay where they were laid without current.
func check_wake_ribbon() -> void:
	var r := WakeRibbonRef.new()
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
		if absf(WakeRibbonRef.age(k, t) - 2.0) < 1e-6:
			row = k
	check(row != null, "wake: a row 2 s old exists")
	if row:
		var hw := WakeRibbonRef.half_width(row, t)
		check(absf(hw - (w0 + 2.12)) <= 0.05 * (w0 + 2.12), "wake: half width 2 s behind the bow %.3f m (expected %.3f)" % [
				hw, w0 + 2.12])
		var p0: Vector2 = row["p"]
		for i in 10:
			r.step(t + 0.05 * (i + 1), 0.05, flat)
		check(row["p"] == p0 and absf(p0.y - v * 1.0) < 1e-6, "wake: rows stay where they were laid")
	check(r.rows.size() <= WakeRibbonRef.N_ROWS, "wake: at most 80 rows")
	check_wake_edges()


## No hard lines in the wakes: with bursts of spray (the pulse of §5) the ribbon's outer edge moves at most 0.15 m
## from row to row beyond the Kelvin opening (rows 0.15 m apart), and the ribbons never write depth, so they do
## not cut each other.
func check_wake_edges() -> void:
	var r := WakeRibbonRef.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var v := 3.0
	var t := 0.0
	var h := func(_x, _y): return 0.0
	while t <= 4.0001:
		var row := r.emit(t, Vector2(0.0, v * t), 0.0, v, 0.7, 0.9, true, v * t)
		# bursts: some rows throw hard, most barely
		r.launch_spray(row, 4.0 if rng.randf() < 0.3 else 0.3, 0.2, [0.1, 0.1])
		r.step(t, 0.05, h)
		t += 0.05
	t -= 0.05
	var arrays := r.build_arrays(t)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n := verts.size() / WakeRibbonRef.ACROSS
	var worst := 0.0
	var worst_raw := 0.0
	var visible_rows := []
	for k in range(r.rows.size() - 1, -1, -1):
		if WakeRibbonRef.alpha(r.rows[k], t) > 0.0:
			visible_rows.append(r.rows[k])
	for k in n - 1:
		var a := verts[k * WakeRibbonRef.ACROSS]
		var b := verts[(k + 1) * WakeRibbonRef.ACROSS]
		var ra: Dictionary = visible_rows[k]
		var rb: Dictionary = visible_rows[k + 1]
		var oa := Vector2(a.x, -a.z).distance_to(ra["p"]) - 1.25 * WakeRibbonRef.half_width(ra, t)
		var ob := Vector2(b.x, -b.z).distance_to(rb["p"]) - 1.25 * WakeRibbonRef.half_width(rb, t)
		worst = maxf(worst, absf(oa - ob))
		worst_raw = maxf(worst_raw, absf(WakeRibbonRef.spray_excess(ra, t).x - WakeRibbonRef.spray_excess(rb, t).x))
	check(n > 20 and worst <= 0.15, "wake: outer edge steps at most 0.15 m row to row with bursts of spray (%.3f m; %.3f m unsmoothed)" % [
			worst, worst_raw])
	var code := (load("res://shaders/wake.gdshader") as Shader).code
	check(code.contains("depth_draw_never"), "wake: ribbons do not write depth")


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
	check(rib.size() == 2 and rib[0].row_count() >= 5, "scene tier %s: wake ribbon laid (%d rows)" % [
			t["name"], rib[0].row_count() if rib.size() else 0])
	# the uploaded phases equal the model's for the camera origin
	var comp: PackedVector4Array = sea.material.get_shader_parameter("comp")
	var ph := sea.model.phases(sea.render_time_ms, sea.origin.x, sea.origin.y)
	var worst := 0.0
	for i in n_comp:
		worst = maxf(worst, absf(comp[i].w - ph[i]))
	check(worst < 1e-6, "scene tier %s: uploaded phases match (worst %s cycles)" % [t["name"], sci(worst)])
	check_land_scene(sea, t["name"])
	var wb: SubViewport = (_scene.get_node("Wakes") as SeaWakes).wake_buffer()
	check((wb != null) == bool(t["wake_buffer"]), "scene tier %s: wake buffer %s" % [t["name"],
			"made for the drawn wakes" if t["wake_buffer"] else "not made"])
	check_shadows(sea, t)
	if t["name"] == "M":
		check_wake_buffer_lifecycle()
		check_bow_spray()
	_scene.queue_free()
	_scene = null
	_start_scene()
	return false


func _finish() -> void:
	print("water renderer checks: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	quit(0 if failures == 0 else 1)
