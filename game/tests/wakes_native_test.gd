extends SceneTree
## Headless checks of the native wakes (game/native/src/sea_wakes.h, water_render.md §5) against their GDScript
## references, run by tests/run_water_test.sh when the GDExtension is built:
##   SeaSampler.height = SeaModel.height (the core's sea components and exposure);
##   WakeRibbon = WakeRibbonRef (rows, spray on a wavy sea, current, arrays: positions, UV, UV2, colours, indices);
##   BowWaveSheets = BowWave.build_arrays; MistCloud = BowWave.mist_step and SeaWakes.mist_buffer;
##   the in-place buffers byte for byte against Godot's own encoding of the same arrays;
##   SeaWakes drawing natively and with the references give the same ribbons, bow waves and mist;
##   and the cost per boat of both paths.
## Exit code 0 when every check passes (or the extension is not built: then it says so and passes).

const SAMPLES := "res://generated/sea/sea_render_samples.json"
## positions are world metres in float32 on both sides: allow a few float ulps at a few hundred metres
const POS_TOL := 1e-4
const ATTR_TOL := 1e-5

var t := TestLog.new()
var _models: Array = []


func _init() -> void:
	# the nodes need the tree: run on the first frame
	process_frame.connect(_run, CONNECT_ONE_SHOT)


## A check that also prints what it measured.
func _report(cond: bool, what: String) -> void:
	print("  %s  %s" % ["ok" if cond else "--", what])
	t.ok(cond, what)


func _run() -> void:
	if not ClassDB.class_exists("WakeRibbon"):
		print("native wakes: the GDExtension is not built (game/native/build.sh); nothing to compare")
		quit(0)
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAMPLES)) if FileAccess.file_exists(SAMPLES) else null
	_report(data is Dictionary, "core samples at %s (run tests/run_water_test.sh)" % SAMPLES)
	if data is Dictionary:
		for sc in data["scenarios"]:
			var m := SeaModel.new()
			m.set_components(sc["components"])
			m.set_exposure(sc["exposure"] if sc["exposure"] is Dictionary else {})
			_models.append(m)
	_sampler()
	_ribbon()
	_ribbon_bytes()
	_bow()
	_mist()
	_sea_wakes()
	_cost()
	t.finish(self, "native wakes")


func _native_sampler(m: SeaModel) -> Object:
	var s: Object = ClassDB.instantiate("SeaSampler")
	s.set_components(m.components)
	s.set_exposure(m.exposure)
	return s


## SeaSampler.height against SeaModel.height at points up to 8 km and times up to 4 h.
func _sampler() -> void:
	t.begin("sea height")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var worst := 0.0
	var n := 0
	for m in _models:
		var s := _native_sampler(m)
		for k in 2000:
			var x := rng.randf_range(-8000.0, 8000.0) if k % 2 == 0 else rng.randf_range(-3000.0, 3000.0)
			var y := rng.randf_range(-8000.0, 8000.0) if k % 2 == 0 else rng.randf_range(-3000.0, 3000.0)
			var tm := rng.randf_range(0.0, 4.0 * 3600.0 * 1000.0)
			worst = maxf(worst, absf(s.height(x, y, tm) - m.height(x, y, tm)))
			n += 1
	_report(_models.size() > 0 and worst < 1e-9, "%d points on %d seas: native within %s m of SeaModel.height" % [
		n, _models.size(), String.num_scientific(worst)])


## Largest differences between two sets of mesh arrays: {size, index, pos, uv, uv2, col}.
func _diff(a: Array, b: Array) -> Dictionary:
	var out := {"size": true, "index": true, "pos": 0.0, "uv": 0.0, "uv2": 0.0, "col": 0.0}
	var pa: PackedVector3Array = a[Mesh.ARRAY_VERTEX] if a[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
	var pb: PackedVector3Array = b[Mesh.ARRAY_VERTEX] if b[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
	if pa.size() != pb.size():
		out["size"] = false
		return out
	var ia: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var ib: PackedInt32Array = b[Mesh.ARRAY_INDEX] if b[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	out["index"] = ia == ib
	for k in pa.size():
		out["pos"] = maxf(out["pos"], pa[k].distance_to(pb[k]))
		out["uv"] = maxf(out["uv"], (a[Mesh.ARRAY_TEX_UV][k] as Vector2).distance_to(b[Mesh.ARRAY_TEX_UV][k]))
		out["uv2"] = maxf(out["uv2"], (a[Mesh.ARRAY_TEX_UV2][k] as Vector2).distance_to(b[Mesh.ARRAY_TEX_UV2][k]))
		var ca: Color = a[Mesh.ARRAY_COLOR][k]
		var cb: Color = b[Mesh.ARRAY_COLOR][k]
		out["col"] = maxf(out["col"], maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), maxf(absf(ca.b - cb.b), absf(ca.a - cb.a))))
	return out


func _merge_worst(w: Dictionary, d: Dictionary) -> void:
	w["size"] = w["size"] and d["size"]
	w["index"] = w["index"] and d["index"]
	for k in ["pos", "uv", "uv2", "col"]:
		w[k] = maxf(w[k], d[k])


func _worst_text(w: Dictionary) -> String:
	return "positions %s m, uv %s, uv2 %s, colour %s" % [String.num_scientific(w["pos"]),
		String.num_scientific(w["uv"]), String.num_scientific(w["uv2"]), String.num_scientific(w["col"])]


func _parity_ok(w: Dictionary) -> bool:
	return w["size"] and w["index"] and w["pos"] <= POS_TOL and w["uv"] <= ATTR_TOL and w["uv2"] <= ATTR_TOL \
		and w["col"] <= ATTR_TOL


## A ribbon pair sailed the same way: bursts of spray on a wavy sea (landing on it), turns, speed changes, rows
## hidden (a bow out of the water) and, in one run, a current. Arrays compared every frame.
func _ribbon() -> void:
	t.begin("wake ribbon")
	var worst := {"size": true, "index": true, "pos": 0.0, "uv": 0.0, "uv2": 0.0, "col": 0.0}
	var frames := 0
	var landed := 0
	var hidden := 0
	var rows_same := true
	for run in 3:
		var m: SeaModel = _models[run % _models.size()] if not _models.is_empty() else SeaModel.new()
		var s := _native_sampler(m)
		var ref := WakeRibbonRef.new()
		var nat: Object = ClassDB.instantiate("WakeRibbon")
		var rng := RandomNumberGenerator.new()
		rng.seed = 100 + run
		var cur = null
		if run == 2:
			cur = func(x, y): return Vector2(0.3 + 0.001 * y, -0.2 + 0.0005 * x)
		var t_s := 50.0 + 13.7 * run
		var t_ms := t_s * 1000.0
		var pos := Vector2(120.0 * run - 80.0, 40.0 * run + 250.0)
		var psi := rng.randf_range(-PI, PI)
		var v := 3.0
		var last_emit := -1.0
		for f in 400:
			var dt := rng.randf_range(0.008, 0.034)
			t_s += dt
			t_ms = t_s * 1000.0
			# lambdas capture locals by value: a new one for this frame's time
			var h := func(x, y): return m.height(x, y, t_ms)
			psi += rng.randf_range(-0.02, 0.02)
			v = clampf(v + rng.randf_range(-0.2, 0.2), 0.0, 6.0)
			pos += Vector2(sin(psi), cos(psi)) * v * dt
			if last_emit < 0.0 or t_s - last_emit >= 0.05:
				last_emit = t_s
				var visible := rng.randf() > 0.05
				hidden += 0 if visible else 1
				var ratio := v / 3.5
				var w0 := 0.35 * 2.2 * minf(1.0, ratio + 0.2)
				ref.emit(t_s, pos, psi, v, w0, ratio, visible, 3.0 * t_s)
				nat.emit(t_s, pos, psi, v, w0, ratio, visible, 3.0 * t_s)
				if visible and rng.randf() < 0.8:
					var e: Array = ref.last_edges(t_s)
					var ne: PackedVector2Array = nat.last_edges(t_s)
					rows_same = rows_same and ne.size() == 2 and ne[0].is_equal_approx(e[0]) and ne[1].is_equal_approx(e[1])
					var zp: float = m.height(e[0].x, e[0].y, t_ms) + 0.1
					var zs: float = m.height(e[1].x, e[1].y, t_ms) + 0.1
					var speed := 2.5 * ratio * ratio * rng.randf_range(0.01, 1.8)
					var heel := rng.randf_range(-0.5, 0.5)
					ref.launch_last_spray(speed, heel, zp, zs)
					nat.launch_last_spray(speed, heel, zp, zs)
			ref.step(t_s, dt, h, cur)
			nat.step(t_s, dt, s, t_ms, cur)
			_merge_worst(worst, _diff(ref.build_arrays(t_s), nat.build_arrays(t_s)))
			frames += 1
		rows_same = rows_same and ref.rows.size() == nat.row_count()
		for k in mini(ref.rows.size(), nat.row_count()):
			var rr: Dictionary = ref.rows[k]
			var nr: Dictionary = nat.row(k)
			rows_same = rows_same and (rr["p"] as Vector2).distance_to(nr["p"]) < POS_TOL
			for sp in rr["spray"]:
				landed += 1 if sp["landed"] else 0
	_report(rows_same, "rows, edges and drift as the reference")
	_report(landed > 20 and hidden > 3, "spray landed on the sea (%d particles) and hidden rows (%d) exercised" % [landed, hidden])
	_report(_parity_ok(worst), "%d frames in 3 runs, same vertices and indices: %s" % [frames, _worst_text(worst)])


## The in-place buffers against Godot's encoding of the same arrays padded to the fixed size.
func _pad(arrays: Array, n_vert: int, n_index: int) -> Array:
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	v.resize(n_vert)
	uv.resize(n_vert)
	uv2.resize(n_vert)
	col.resize(n_vert)
	idx.resize(n_index)
	out[Mesh.ARRAY_VERTEX] = v
	out[Mesh.ARRAY_TEX_UV] = uv
	out[Mesh.ARRAY_TEX_UV2] = uv2
	out[Mesh.ARRAY_COLOR] = col
	out[Mesh.ARRAY_INDEX] = idx
	return out


func _godot_bytes(arrays: Array) -> Dictionary:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return RenderingServer.mesh_get_surface(mesh.get_rid(), 0)


func _ribbon_bytes() -> void:
	t.begin("in-place buffers")
	var nat: Object = ClassDB.instantiate("WakeRibbon")
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, nat.blank_arrays())
	_report(nat.attach_mesh(mesh.get_rid()), "a ribbon attaches to its fixed-size mesh")
	var n_vert := WakeRibbonRef.N_ROWS * 15
	var n_index := (WakeRibbonRef.N_ROWS - 1) * 14 * 6
	var ok := true
	var nv := 0
	var t_s := 10.0
	for f in 120:
		t_s += 0.05
		nat.emit(t_s, Vector2(5.0, 3.0 * t_s), 0.3, 3.0, 0.8, 0.4 + 0.3 * sin(f * 0.1), f % 17 != 5, 3.0 * t_s)
		nat.launch_last_spray(1.5, 0.1, 0.1, 0.1)
		nat.step(t_s, 0.05, null, 0.0, null)
		var arrays: Array = nat.build_arrays(t_s)
		nv = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		nat.write_mesh(t_s)
		if f % 20 != 19:
			continue
		var g := _godot_bytes(_pad(arrays, n_vert, n_index))
		var vb: PackedByteArray = nat.vertex_bytes()
		var ab: PackedByteArray = nat.attribute_bytes()
		var stride := ab.size() / n_vert
		ok = ok and vb.slice(0, 12 * nv) == (g["vertex_data"] as PackedByteArray).slice(0, 12 * nv)
		ok = ok and ab.slice(0, stride * nv) == (g["attribute_data"] as PackedByteArray).slice(0, stride * nv)
		ok = ok and nat.index_bytes() == g["index_data"]
	_report(ok and nv > 0, "ribbon: positions, colours, UVs and indices byte for byte as Godot encodes them (%d vertices in use)" % nv)
	var bw: Object = ClassDB.instantiate("BowWaveSheets")
	var bm := ArrayMesh.new()
	bm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bw.blank_arrays())
	_report(bw.attach_mesh(bm.get_rid()), "a bow wave attaches to its fixed-size mesh")
	var st := {"x": 12.0, "y": -40.0, "psi": 0.7, "heel": 0.25, "lwl": 6.8, "bwl": 2.2, "bow_x": 3.4}
	_report(bw.write_mesh(st, 3.2, 0.9, 0.4), "the bow wave is drawn at speed ratio 0.9")
	var g2 := _godot_bytes(bw.build_arrays(st, 3.2, 0.9, 0.4))
	_report(bw.vertex_bytes() == g2["vertex_data"] and bw.attribute_bytes() == g2["attribute_data"],
		"bow wave: vertex and attribute buffers byte for byte as Godot encodes them")
	_report(not bw.write_mesh(st, 0.5, 0.1, 0.0), "no bow wave at speed ratio 0.1")


## BowWaveSheets against BowWave.build_arrays on random states and drivers.
func _bow() -> void:
	t.begin("bow wave")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var bw: Object = ClassDB.instantiate("BowWaveSheets")
	var worst := {"size": true, "index": true, "pos": 0.0, "uv": 0.0, "uv2": 0.0, "col": 0.0}
	var drawn := 0
	for k in 500:
		var st := {"x": rng.randf_range(-500.0, 500.0), "y": rng.randf_range(-500.0, 500.0),
			"psi": rng.randf_range(-PI, PI), "heel": rng.randf_range(-0.6, 0.6), "lwl": rng.randf_range(5.0, 12.0),
			"bwl": rng.randf_range(1.5, 3.5), "own": false}
		st["bow_x"] = 0.5 * st["lwl"]
		var d := BowWave.Drivers.new()
		d.v = rng.randf_range(0.0, 7.0)
		d.ratio = rng.randf_range(0.0, 1.4)
		d.plunge = rng.randf_range(0.0, 2.0) if rng.randf() < 0.5 else 0.0
		var a := BowWave.build_arrays(st, d)
		var b: Array = bw.build_arrays(st, d.v, d.ratio, d.plunge)
		if a[Mesh.ARRAY_VERTEX] == null:
			worst["size"] = worst["size"] and b[Mesh.ARRAY_VERTEX] == null
			continue
		drawn += 1
		_merge_worst(worst, _diff(a, b))
	_report(drawn > 200 and _parity_ok(worst), "500 random boats (%d drawn), same vertices and indices: %s" % [drawn,
		_worst_text(worst)])


## MistCloud against BowWave.mist_step, mist_look and SeaWakes.mist_buffer.
func _mist() -> void:
	t.begin("mist")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var cloud: Object = ClassDB.instantiate("MistCloud")
	var ref: Array = []
	var worst := 0.0
	var same_count := true
	var most := 0
	for f in 300:
		for k in rng.randi_range(0, 3):
			var m := {"pos": Vector3(rng.randf_range(-300, 300), rng.randf_range(-300, 300), rng.randf_range(0, 1)),
				"vel": Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(0.5, 2.5)), "age": 0.0,
				"life": rng.randf_range(0.8, 1.3), "s0": 0.5, "s1": rng.randf_range(1.2, 2.2), "seed": rng.randf()}
			if ref.size() < BowWave.MIST_MAX:
				ref.append(m.duplicate())
				cloud.add(m)
		var dt := rng.randf_range(0.008, 0.034)
		var live := []
		for m in ref:
			if BowWave.mist_step(m, dt):
				live.append(m)
		ref = live
		cloud.step(dt)
		same_count = same_count and cloud.count() == ref.size()
		most = maxi(most, ref.size())
		var a := SeaWakes.mist_buffer(ref)
		var b: PackedFloat32Array = cloud.buffer()
		if a.size() != b.size():
			same_count = false
			continue
		for i in a.size():
			worst = maxf(worst, absf(a[i] - b[i]))
	_report(same_count and most > 20 and worst <= POS_TOL, "300 frames, up to %d sprites: same sprites, buffer within %s" % [
		most, String.num_scientific(worst)])


## A SeaWakes drawing natively and one on the references, the same boats on the same sea: the same ribbons, bow
## waves and mist (the native ribbons read back through build_arrays).
func _sea_wakes() -> void:
	t.begin("SeaWakes native = reference")
	var holder := Node3D.new()
	var sea := Sea.new()
	sea.quality = SeaQuality.Tier.H
	holder.add_child(sea)
	if not _models.is_empty():
		sea.set_sea(_models[1 % _models.size()].components, _models[1 % _models.size()].exposure)
	var ws := []
	for ref in [false, true]:
		var w := SeaWakes.new()
		w.use_reference = ref
		holder.add_child(w)
		w.sea = sea
		w._rng.seed = 21
		ws.append(w)
	root.add_child(holder)
	_report(ws[0].is_native() and not ws[1].is_native(), "one draws natively, one on the references")
	var worst := {"size": true, "index": true, "pos": 0.0, "uv": 0.0, "uv2": 0.0, "col": 0.0}
	var wave_worst := {"size": true, "index": true, "pos": 0.0, "uv": 0.0, "uv2": 0.0, "col": 0.0}
	var mist_worst := 0.0
	var mist_most := 0
	for f in 240:
		var tt := f / 60.0
		sea.render_time_ms = 20000.0 + 1000.0 * tt
		sea.update_frame(Vector3(0.0, 5.0, 15.0))
		for w in ws:
			for id in 3:
				var v := 2.5 + id
				seed(id + 1)
				w.update_boat(id, {"x": 8.0 * id, "y": v * tt, "z": 0.0, "psi": 0.05 * id, "heel": 0.2 * (id - 1),
					"pitch": 0.0, "lwl": 6.8, "bwl": 2.2, "transom_width": 1.6, "bow_x": 3.4, "stern_x": -3.4,
					"own": id == 0})
			w._process(1.0 / 60.0)
		var t_s: float = sea.render_time_ms * 0.001
		for id in 3:
			var ra: Array = ws[0].boat_ribbons(id)
			var rb: Array = ws[1].boat_ribbons(id)
			for k in 2:
				_merge_worst(worst, _diff(rb[k].build_arrays(t_s), ra[k].build_arrays(t_s)))
			var b0: Dictionary = ws[0]._boats[id]
			var b1: Dictionary = ws[1]._boats[id]
			var st: Dictionary = b1["state"]
			var d: BowWave.Drivers = b0["drv"]
			var wa: Array = b0["sheets"].build_arrays(st, d.v, d.ratio, d.plunge)
			var wb := BowWave.build_arrays(st, b1["drv"])
			if wb[Mesh.ARRAY_VERTEX] != null:
				_merge_worst(wave_worst, _diff(wb, wa))
			else:
				wave_worst["size"] = wave_worst["size"] and wa[Mesh.ARRAY_VERTEX] == null
		var ma: Array = ws[0].mist_sprites()
		var mb: Array = ws[1].mist_sprites()
		mist_most = maxi(mist_most, ma.size())
		if ma.size() != mb.size():
			mist_worst = INF
		else:
			for i in ma.size():
				mist_worst = maxf(mist_worst, (ma[i]["pos"] as Vector3).distance_to(mb[i]["pos"]))
	_report(_parity_ok(worst), "3 boats for 4 s on tier H: ribbons as the reference: %s" % _worst_text(worst))
	_report(_parity_ok(wave_worst), "bow waves as the reference: %s" % _worst_text(wave_worst))
	_report(mist_most > 5 and mist_worst <= POS_TOL, "mist as the reference (%d sprites, within %s m)" % [mist_most,
		String.num_scientific(mist_worst)])
	holder.free()


## The cost per boat with wakes of both paths: 10 boats at speed with spray and mist (tier H), 120 frames after
## 4 s of warm-up so every ribbon is full.
func _cost() -> void:
	t.begin("cost")
	var per := {}
	for ref in [false, true]:
		var holder := Node3D.new()
		var sea := Sea.new()
		sea.quality = SeaQuality.Tier.H
		holder.add_child(sea)
		if not _models.is_empty():
			sea.set_sea(_models[1 % _models.size()].components, _models[1 % _models.size()].exposure)
		var w := SeaWakes.new()
		w.use_reference = ref
		holder.add_child(w)
		w.sea = sea
		root.add_child(holder)
		var us := 0
		for f in 360:
			var tt := f / 60.0
			sea.render_time_ms = 1000.0 * tt
			sea.update_frame(Vector3(0.0, 5.0, 15.0))
			for id in 10:
				var v := 3.5 + 0.2 * id
				w.update_boat(id, {"x": 20.0 * id, "y": v * tt, "z": 0.0, "psi": 0.0, "heel": 0.25, "pitch": 0.0,
					"lwl": 6.8, "bwl": 2.2, "transom_width": 1.6, "bow_x": 3.4, "stern_x": -3.4, "own": id == 0})
			var t0 := Time.get_ticks_usec()
			w._frame()
			if f >= 240:
				us += Time.get_ticks_usec() - t0
		per[ref] = us / 120.0 / 10.0 / 1000.0
		holder.free()
	print("  cost per boat with wakes (tier H, spray and mist): native %.3f ms, reference %.3f ms" % [per[false], per[true]])
	_report(per[false] < per[true], "native is cheaper than the reference")
