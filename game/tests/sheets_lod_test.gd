extends SceneTree
## Headless tests of the running sheets, the levels of detail and the rope materials (docs/specs/sail_visuals.md
## §11.3, §11.4 and §12 tests 21, 22; data_format.md §8.7): native SheetRopes against SheetRopesRef and against
## Godot's own vertex encoding, the sheets of the generated wm7 and wm12 following the clew to the lead and the winch,
## sag by load, lazy lines on the deck, hidden with their sail, continuity through a tack, the level switch with its
## hysteresis and the livery on every level, and the rope materials by function. Run by run_sail_visuals_test.sh.
##   godot --headless --path game -s res://tests/sheets_lod_test.gd

const UP := 3
const DOWN := 0
const KNOT := 1852.0 / 3600.0

var t := TestLog.new()
var native := false


func _init() -> void:
	_main()


func _main() -> void:
	await process_frame
	native = ClassDB.class_exists("SheetRopes")
	print("native SheetRopes: ", "loaded" if native else "not built (reference only)")
	if native:
		_native_vs_ref()
		_bytes()
	for id in ["wm7", "wm12"]:
		if not FileAccess.file_exists("res://generated/boats/%s.glb" % id):
			t.ok(false, "%s generated (run tests/run_boat_import_test.sh)" % id)
			continue
		for reference in ([false, true] if native else [true]):
			_sheets(id, reference)
		_routes(id)
		_lods(id)
		_ropes(id)
	_cost()
	t.finish(self, "sheets and LOD test")


# ---- helpers ------------------------------------------------------------------------------------------------

static func _params() -> Dictionary:
	var fixed := PackedVector3Array()
	for k in 10:
		var th := -TAU * 3.0 * k / 9.0
		fixed.append(Vector3(1.0 + 0.04 * sin(th), 0.7 + 0.02 * k, -2.0 + 0.04 * cos(th)))
	return {"sides": 6, "tile": 0.05, "lines": [
		{"radius": 0.0045, "free_rings": 16, "lead_rings": 4, "anchor": Vector3(0.7, 0.8, -0.1), "fixed": fixed},
		{"radius": 0.004, "free_rings": 3, "lead_rings": 0, "anchor": Vector3(0.0, 0.8, 5.0)}]}


static func _drive(shown: Array) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	for s in shown:
		d.append_array([1.0 if s else 0.0, 0.08, 0.01, 0.3, 0.1, 1.2])
	return d


func _sv(info: SimSource.ClassInfo, phases: Dictionary, beta: float, awa: float, aws: float, shiver := 0.0) -> SimSource.SailsView:
	var sv := SimSource.SailsView.new()
	sv.awa = awa
	sv.aws = aws
	for i in info.sails.size():
		var st := SimSource.SailState.new()
		st.phase = phases.get(info.sails[i].type, DOWN)
		st.beta = beta if info.sails[i].type != "main" else beta * 1.3
		sv.sails.append(st)
		var o := SimSource.SailOutput.new()
		o.luff_shiver = shiver
		sv.out.append(o)
	return sv


func _run(bv: BoatView, sv: SimSource.SailsView, frames: int) -> void:
	for f in frames:
		bv.apply_sails(sv, sv, 1.0, 1.0 / 60.0)


## Largest distance of the free run's rings from its straight polyline (start, waypoint, anchor), over its length.
static func _sag(c: PackedVector3Array, nf: int, way: Vector3) -> float:
	var a := c[0]
	var b := c[nf - 1]
	var pts := [a, b] if is_nan(way.x) else [a, way, b]
	var length := 0.0
	for k in range(1, pts.size()):
		length += (pts[k] - pts[k - 1]).length()
	var worst := 0.0
	for k in nf:
		var d := INF
		for s in range(1, pts.size()):
			var p: Vector3 = Geometry3D.get_closest_point_to_segment(c[k], pts[s - 1], pts[s])
			d = minf(d, p.distance_to(c[k]))
		worst = maxf(worst, d)
	return worst / maxf(length, 1e-3)


# ---- tests --------------------------------------------------------------------------------------------------

func _native_vs_ref() -> void:
	t.begin("native SheetRopes against the reference")
	var a: Variant = ClassDB.instantiate("SheetRopes")
	var b := SheetRopesRef.new()
	t.ok(a.configure(_params()) and b.configure(_params()), "both configure")
	t.ok(a.get_vertex_count() == b.get_vertex_count() and a.indices() == b.indices(),
		"same topology (%d vertices)" % a.get_vertex_count())
	var starts := PackedVector3Array([Vector3(0.9, 1.1, 0.4), Vector3(0.3, 1.0, 5.0)])
	var ways := PackedVector3Array([Vector3(0.0, 1.0, 0.9), Vector3(NAN, NAN, NAN)])
	for shown in [[true, true], [true, false], [false, true]]:
		a.update(starts, ways, _drive(shown), Vector3(0.1, -1, 0))
		b.update(starts, ways, _drive(shown), Vector3(0.1, -1, 0))
		var pa: PackedVector3Array = a.positions()
		var pb: PackedVector3Array = b.positions()
		var na: PackedVector3Array = a.normals()
		var nb: PackedVector3Array = b.normals()
		var ua: PackedVector2Array = a.uvs()
		var ub: PackedVector2Array = b.uvs()
		var dp := 0.0
		var dn := 0.0
		var du := 0.0
		for k in pa.size():
			dp = maxf(dp, pa[k].distance_to(pb[k]))
			dn = maxf(dn, na[k].distance_to(nb[k]))
			du = maxf(du, ua[k].distance_to(ub[k]))
		t.ok(dp < 1e-4 and dn < 1e-3 and du < 1e-4, "shown %s: positions %.7f m, normals %.6f, uv %.7f" % [shown, dp, dn, du])
	# the deck field builder: a deck plane with a raised box (a cabin) and a low and a tall fitting
	var plane := PackedVector3Array([Vector3(-1, 0.5, -2), Vector3(1, 0.5, -2), Vector3(1, 0.6, 2), Vector3(-1, 0.6, 2)])
	var cabin := PackedVector3Array([Vector3(-0.4, 0.8, -0.5), Vector3(0.4, 0.8, -0.5), Vector3(0.4, 0.8, 0.5),
		Vector3(-0.4, 0.8, 0.5)])
	var low := PackedVector3Array([Vector3(0.6, 0.6, 0.0), Vector3(0.8, 0.6, 0.0), Vector3(0.7, 0.6, 0.3)])
	var tall := PackedVector3Array([Vector3(-0.8, 0.9, 0.0), Vector3(-0.6, 0.9, 0.0), Vector3(-0.7, 0.9, 0.3)])
	var quad := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var surfs := [{"positions": plane, "indices": quad, "cap": -1.0}, {"positions": cabin, "indices": quad, "cap": -1.0},
		{"positions": low, "indices": PackedInt32Array([0, 1, 2]), "cap": 0.07},
		{"positions": tall, "indices": PackedInt32Array([0, 1, 2]), "cap": 0.07}]
	var fa: Dictionary = a.build_deck(surfs, 0.025, 8, 1)
	var fb: Dictionary = b.build_deck(surfs, 0.025, 8, 1)
	var dh := 0.0
	var ha: PackedFloat32Array = fa["heights"]
	var hb: PackedFloat32Array = fb["heights"]
	for k in mini(ha.size(), hb.size()):
		dh = maxf(dh, absf(ha[k] - hb[k]))
	t.ok(fa["nx"] == fb["nx"] and fa["nz"] == fb["nz"] and ha.size() == hb.size() and dh < 1e-4,
		"deck field: native and reference agree (%dx%d, %.6f m)" % [fa["nx"], fa["nz"], dh])
	var probe := SheetRopesRef.new()
	probe.configure({"lines": _params()["lines"], "deck": fa})
	t.near(probe.deck_height(0.0, 0.0), 0.8, 1e-4, "deck field: the cabin top")
	t.near(probe.deck_height(0.7, 0.1), 0.6, 2e-3, "deck field: a low fitting counts")
	t.ok(probe.deck_height(-0.7, 0.1) < 0.6, "deck field: a tall fitting does not")
	t.near(probe.deck_height(1.15, 0.0), 0.55, 0.03, "deck field: the skirt holds the edge's height out over the side")
	a.update(starts, ways, _drive([true, true]), Vector3(0.1, -1, 0))
	var c: PackedVector3Array = a.centre(0)
	t.near_v(c[0], starts[0], 1e-4, "the line starts at the clew")
	t.near_v(c[15], Vector3(0.7, 0.8, -0.1), 1e-4, "it passes the lead block")
	t.near_v(c[c.size() - 1], (_params()["lines"][0]["fixed"] as PackedVector3Array)[9], 1e-4, "it ends at the tail")


func _bytes() -> void:
	t.begin("sheet vertex buffer")
	var sh: Variant = ClassDB.instantiate("SheetRopes")
	sh.configure(_params())
	var starts := PackedVector3Array([Vector3(0.9, 1.1, 0.4), Vector3(0.3, 1.0, 5.0)])
	var ways := PackedVector3Array([Vector3(NAN, NAN, NAN), Vector3(NAN, NAN, NAN)])
	sh.update(starts, ways, _drive([true, true]), Vector3.DOWN)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = sh.positions()
	arrays[Mesh.ARRAY_NORMAL] = sh.normals()
	arrays[Mesh.ARRAY_TANGENT] = sh.tangents()
	arrays[Mesh.ARRAY_TEX_UV] = sh.uvs()
	arrays[Mesh.ARRAY_INDEX] = sh.indices()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	t.ok(sh.attach_mesh(mesh.get_rid(), 0), "attach to the uncompressed sheet mesh")
	var d := _drive([true, true])
	d[3] = -0.4
	sh.update(starts, ways, d, Vector3(0, -1, 0.2))
	var mine: PackedByteArray = sh.vertex_bytes()
	var mine_a: PackedByteArray = sh.attribute_bytes()
	arrays[Mesh.ARRAY_VERTEX] = sh.positions()
	arrays[Mesh.ARRAY_NORMAL] = sh.normals()
	arrays[Mesh.ARRAY_TANGENT] = sh.tangents()
	arrays[Mesh.ARRAY_TEX_UV] = sh.uvs()
	var ref := ArrayMesh.new()
	ref.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var sd := RenderingServer.mesh_get_surface(ref.get_rid(), 0)
	var theirs: PackedByteArray = sd["vertex_data"]
	var theirs_a: PackedByteArray = sd["attribute_data"]
	var n: int = sh.get_vertex_count()
	t.ok(mine.size() == theirs.size() and mine.slice(0, 12 * n) == theirs.slice(0, 12 * n), "positions byte for byte")
	var fmt := ref.surface_get_format(0)
	var noff := RenderingServer.mesh_surface_get_format_offset(fmt, n, Mesh.ARRAY_NORMAL)
	var nst := RenderingServer.mesh_surface_get_format_normal_tangent_stride(fmt, n)
	var dn := 0
	var dt := 0
	for k in n:
		for c in 2:
			dn = maxi(dn, absi(mine.decode_u16(noff + nst * k + 2 * c) - theirs.decode_u16(noff + nst * k + 2 * c)))
			dt = maxi(dt, absi(mine.decode_u16(noff + nst * k + 4 + 2 * c) - theirs.decode_u16(noff + nst * k + 4 + 2 * c)))
	t.ok(dn <= 1 and dt <= 1, "normals and tangents as Godot encodes them (largest differences %d, %d units)" % [dn, dt])
	t.ok(mine_a == theirs_a, "uv0 attributes byte for byte (%d bytes)" % mine_a.size())


func _sheets(id: String, reference: bool) -> void:
	t.begin("%s sheets (%s)" % [id, "reference" if reference else "native"])
	var data := BoatClassData.load_class(id)
	var bv := BoatView.create(data.info, 0.5, reference)
	root.add_child(bv)
	var sh := bv.sheets
	if not t.ok(sh != null, "the boat has sheets"):
		bv.queue_free()
		return
	t.ok(sh.native == (not reference), "drawn by %s" % ("SheetRopesRef" if reference else "the native SheetRopes"))
	var rig: Dictionary = data.info.physics["rig"]
	var leads: Dictionary = rig["sheet_leads"]
	var aws := 10.0 * KNOT
	# jib trimmed on port (beta < 0: the sail to port, the port line works), main up
	_run(bv, _sv(data.info, {"main": UP, "jib": UP}, -0.35, 0.8, aws), 90)
	var jib: BoatView.SailPart = sh.followed[BoatSheets.Surface.HEADSAIL]
	t.ok(jib != null and jib.type == "jib", "the headsail lines follow the jib")
	var shape: Variant = sh.shapes[BoatSheets.Surface.HEADSAIL]
	var clew: Vector3 = jib.shape.mid_points(PackedInt32Array([jib.cols - 1]))[0]
	var nf: int = BoatSheets.FREE_RINGS[0]
	var nl: int = BoatSheets.LEAD_RINGS[0]
	var drum := float(leads["headsail"]["drum_diameter"])
	for side in 2:
		var c: PackedVector3Array = shape.centre(side)
		var lead := Frames.body_to_model(BoatView._vec(leads["headsail"]["lead"])) * (Vector3(-1, 1, 1) if side == 1 else Vector3.ONE)
		var winch := Frames.body_to_model(BoatView._vec(leads["headsail"]["winch"])) * (Vector3(-1, 1, 1) if side == 1 else Vector3.ONE)
		var what := "starboard" if side == 0 else "port"
		t.near_v(c[0], clew, 1e-3, "%s line starts at the placed clew" % what)
		t.near_v(c[nf - 1], lead, 1e-3, "%s line passes its lead block" % what)
		var e := c[nf - 1 + nl]
		var rr := Vector2(e.x - winch.x, e.z - winch.z).length()
		t.near(rr, 0.5 * drum + sh._r, 1e-3, "%s line meets the drum at its radius" % what)
		var way: Vector3 = (sh.last_ways[0] as PackedVector3Array)[side]
		var sag := _sag(c, nf, way)
		if side == 1:
			# its hang (the drape over a cabin edge near the lead is not sag)
			var hang: float = (sh.last_drive[0] as PackedFloat32Array)[side * SheetRopesRef.DRIVE + 1]
			t.ok(hang < 0.01, "the trimmed working sheet is nearly straight (sag %.4f of the span, %.4f drawn)" % [hang, sag])
		else:
			var below := 0
			for k in range(1, nf - 1):
				var h: float = shape.deck_height(c[k].x, c[k].z)
				if h > SheetRopesRef.NO_DECK and c[k].y < h + sh._r - 1e-4:
					below += 1
			t.ok(below == 0, "the lazy sheet never lies below the deck (%d rings under)" % below)
			t.ok(sag > 0.02, "the lazy sheet is slack (sag %.3f)" % sag)
	# flogging: let fly, the working sheet sags and swings
	_run(bv, _sv(data.info, {"main": UP, "jib": UP}, -0.35, 0.8, aws, 1.0), 120)
	var dv: PackedFloat32Array = sh.last_drive[0]
	t.ok(dv[SheetRopesRef.DRIVE + 1] > 0.08, "a flogging working sheet sags over 8 %% of its span (%.3f)" % dv[SheetRopesRef.DRIVE + 1])
	# a tack: the clew crosses, the lines move smoothly
	var sa: float = jib.shape.frame()["sa"]
	var prev := PackedVector3Array()
	var worst := 0.0
	for f in 240:
		var u := float(f) / 239.0
		bv.apply_sails(_sv(data.info, {"main": UP, "jib": UP}, lerpf(-0.35, 0.35, u), lerpf(0.8, -0.8, u), aws),
			_sv(data.info, {"main": UP, "jib": UP}, lerpf(-0.35, 0.35, u), lerpf(0.8, -0.8, u), aws), 1.0, 1.0 / 60.0)
		var cur := PackedVector3Array()
		for side in 2:
			cur.append_array(shape.centre(side).slice(0, nf))
		if not prev.is_empty():
			for k in cur.size():
				worst = maxf(worst, cur[k].distance_to(prev[k]))
		prev = cur
	t.ok(worst <= 0.05 * sa, "through a tack no ring moves more than 0.05 Sa a frame (%.3f m <= %.3f)" % [worst, 0.05 * sa])
	# the jib down hides its lines
	_run(bv, _sv(data.info, {"main": UP}, 0.3, -0.8, aws), 2)
	var c0: PackedVector3Array = shape.centre(0)
	t.ok(sh.followed[0] == null and c0[0].distance_to(c0[c0.size() - 1]) < 1e-6, "the jib down hides its lines")
	# the kite: sheet, lazy sheet round the forestay and the tack line
	_run(bv, _sv(data.info, {"main": UP, "spinnaker_asym": UP}, 0.6, -2.1, aws), 60)
	var kite: BoatView.SailPart = sh.followed[BoatSheets.Surface.FLYING]
	if t.ok(kite != null, "the flying lines follow the kite"):
		var ks: Variant = sh.shapes[BoatSheets.Surface.FLYING]
		var corners: PackedVector3Array = kite.shape.mid_points(PackedInt32Array([kite.cols - 1, 0]))
		var fl := Frames.body_to_model(BoatView._vec(leads["flying"]["lead"]))
		t.near_v(ks.centre(0)[0], corners[0], 1e-3, "the kite sheet starts at the clew")
		t.near_v(ks.centre(0)[nf - 1], fl, 1e-3, "and runs to the quarter block")
		var lw: PackedVector3Array = sh.last_ways[1]
		var slots: int = lw.size() / int(ks.get_line_count())
		var round_stay := false
		for j in slots:
			var w := lw[slots + j]
			var stay := Frames.body_to_model(BoatView._vec(rig["forestay_tack"]))
			round_stay = round_stay or (not is_nan(w.x) and absf(w.x) < 1.0 and w.z > stay.z)
		t.ok(round_stay, "the lazy kite sheet runs round the forestay")
		if ks.get_line_count() == 3:
			var tl: PackedVector3Array = ks.centre(2)
			t.near_v(tl[0], corners[1], 1e-3, "the tack line starts at the tack")
			t.near_v(tl[tl.size() - 1], Frames.body_to_model(BoatView._vec(rig["bowsprit_end"])), 1e-3, "and ends at the sprit")
	bv.queue_free()


func _lods(id: String) -> void:
	t.begin("%s levels of detail" % id)
	var data := BoatClassData.load_class(id)
	var bv := BoatView.create(data.info, 0.5)
	root.add_child(bv)
	t.ok(bv.levels.size() == 1, "one model, the engine's levels of detail (%d)" % bv.levels.size())
	var lv := Livery.load_class(id)[0]
	bv.set_livery(lv)
	_run(bv, _sv(data.info, {"main": UP, "jib": UP}, -0.35, 0.8, 5.0), 10)
	# the sheets by the size of a metre on screen (§11.3): full, thin, none
	for e in [[25.0, 0], [50.0, 1], [150.0, 2], [20.0, 0]]:
		bv.update_lod(e[0])
		t.ok(bv.sheets.detail == e[1] and bv.sheets.node.visible == (e[1] < 2),
			"camera at %.0f m: sheets at detail %d, %s" % [e[0], bv.sheets.detail,
			"shown" if bv.sheets.node.visible else "hidden"])
	# §11.4: every sail mesh has the engine's levels on every 2nd and 4th row and column over the whole grid
	for sp in bv.sail_parts:
		if sp.mesh == null:
			continue
		var surfs: Array = sp.mesh.get("_surfaces")
		var lods: Array = (surfs[0] as Dictionary).get("lods", []) if not surfs.is_empty() else []
		var full := (sp.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		var ok := lods.size() >= 2 and float(lods[0]) > 0.0
		var sizes := []
		for k in range(0, lods.size(), 2):
			var stride := 4 if int((surfs[0] as Dictionary).get("vertex_count", 0)) > 65535 else 2
			sizes.append((lods[k + 1] as PackedByteArray).size() / stride)
			ok = ok and int(sizes[-1]) < full and (k == 0 or float(lods[k]) > float(lods[k - 2]))
		var verts := (sp.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		t.ok(ok and verts == 2 * sp.rows * sp.cols, "%s: engine levels %s of %d indices over the whole grid's %d vertices" % [
			sp.id, sizes, full, verts])
	# the boat's own meshes keep the full model at chase range (lod_bias)
	bv.own = true
	var body := bv.model.find_child("body", true, false) as GeometryInstance3D
	t.ok(body != null and body.lod_bias == BoatView.OWN_LOD_BIAS, "the own boat's meshes at LOD bias %.0f" % BoatView.OWN_LOD_BIAS)
	bv.own = false
	# the livery on every level: one material, the boat's own, on every non-sail surface
	var mats := {}
	var missing := []
	for k in bv.levels.size():
		for mi in (bv.levels[k]["model"] as Node).find_children("*", "MeshInstance3D", true, false):
			var nm := String(mi.name)
			if nm.begins_with("sail_") or nm.begins_with("shadow") or mi == bv.sheets.node:
				continue
			for s2 in (mi as MeshInstance3D).mesh.get_surface_count():
				var m := (mi as MeshInstance3D).get_surface_override_material(s2)
				if m == null:
					missing.append("%s@%d" % [nm, k])
				mats[m] = true
	t.ok(missing.is_empty() and mats.size() == 1, "every surface carries the boat's one livery material (%s, %d)" % [
		missing, mats.size()])
	# the moving parts follow the boom and the helm at every distance
	bv.update_lod(300.0)
	_run(bv, _sv(data.info, {"main": UP, "jib": UP}, -0.5, 0.8, 5.0), 3)
	var b0: Node3D = bv.levels[0]["boom"]
	t.ok(b0 != null and (b0.transform.basis * Vector3.BACK).dot(Basis(Vector3.UP, bv.boom_angle)
		* (bv.levels[0]["boom_rest"] as Transform3D).basis * Vector3.BACK) > 0.999, "the boom at the main's angle at 300 m")
	t.ok(bv.levels[0]["rudder"] != null, "the rudder is its own node")
	bv.queue_free()


func _ropes(id: String) -> void:
	t.begin("%s rope materials" % id)
	var data := BoatClassData.load_class(id)
	var lv := Livery.load_class(id)[0]
	var rs := BakedLivery.rope_set(id)
	t.ok(rs.get("albedo", {}).size() == Livery.ROPES.size(), "baked rope set: %d functions" % rs.get("albedo", {}).size())
	var bv := BoatView.create(data.info, 0.5)
	bv.set_livery(lv)
	# the model's ropes are slots of the boat material in the function's mean braid colour (data_format.md §8.7):
	# the mainsheet tackle drawn, the halyards, coils and control lines painted on the deck
	var bm := bv.livery_materials[0] as ShaderMaterial
	var col: PackedVector4Array = bm.get_shader_parameter("slot_color")
	for fn in ["mainsheet", "halyard", "control"]:
		var r: Dictionary = lv.ropes.get(fn, {}) if lv.ropes.has(fn) else Livery.rope_set_of({}, [])[fn]
		var c := Livery.rope_mean(r).srgb_to_linear()
		var v := col[BoatMaterials.slot_id("rope_" + fn)]
		t.ok(absf(v.x - c.r) < 0.01 and absf(v.y - c.g) < 0.01 and absf(v.z - c.b) < 0.01,
			"the boat material's rope_%s slot in the %s braid's colour" % [fn, fn])
	for surf in 2:
		var m := bv.sheets.get_material(surf) as ShaderMaterial
		var fn: String = ["sheet", "kite_sheet"][surf]
		t.ok(m != null and m.get_shader_parameter("albedo_tex") == rs["albedo"][fn] and m.get_shader_parameter("use_normal_tex"),
			"the %s lines on the baked %s braid with its relief" % [["headsail", "flying-sail"][surf], fn])
	bv.free()
	# without baked ropes: the slot tinted to the function's colour
	BakedLivery.enabled = false
	var pb := BoatView.create(data.info, 0.5)
	pb.set_livery(lv)
	var pm := pb.sheets.get_material(BoatSheets.Surface.HEADSAIL) as ShaderMaterial
	var base := pb.sheets.base_material
	t.ok(pm != null and pm != base and pm.get_shader_parameter("albedo_color") != base.get_shader_parameter("albedo_color"),
		"procedural fallback: the sheet tinted to its colour (%s)" % [pm.get_shader_parameter("albedo_color") if pm else null])
	pb.free()
	BakedLivery.enabled = true


func _cost() -> void:
	t.begin("cost")
	if not FileAccess.file_exists("res://generated/boats/wm7.glb"):
		return
	var data := BoatClassData.load_class("wm7")
	for reference in ([false, true] if native else [true]):
		var bv := BoatView.create(data.info, 0.5, reference)
		root.add_child(bv)
		_run(bv, _sv(data.info, {"main": UP, "jib": UP, "spinnaker_asym": UP}, -0.6, 2.0, 5.0), 5)
		var reps := 1000 if not reference else 50
		# the best of ten batches (the machine's other load out of it)
		var us := INF
		for batch in 10:
			var t0 := Time.get_ticks_usec()
			for r in reps / 10:
				bv.sheets.step(5.0, 1.0 / 60.0, true)
			us = minf(us, float(Time.get_ticks_usec() - t0) / (reps / 10))
		var t1 := Time.get_ticks_usec()
		for r in reps:
			bv.sheets.step(5.0, 1.0 / 60.0, false)
		var us_ease := float(Time.get_ticks_usec() - t1) / reps
		var nv := 0
		for s in bv.sheets.shapes:
			if s != null:
				nv += s.get_vertex_count()
		print("  %s: sheets of a wm7 with jib and kite (%d vertices) %.1f us per update, %.1f us easing only; 20 boats %.2f ms"
			% ["reference" if reference else "native", nv, us, us_ease, us * 20.0 / 1000.0])
		if not reference:
			t.ok(us < 120.0, "native: a boat's sheets cost %.1f us per update (< 120)" % us)
		bv.queue_free()


# ---- §12 test 21: clearance of the flying sail's lines and the lazy lines on the deck ----------------------------

## Over a sweep of configs and trims: no tube between two rings of a flying sail's sheet comes within the rope radius
## of the main's or the shown headsail's placed mid-surface or of the boom's box, every lazy line lies at or above the
## true top of the deck (the LOD0 deck mesh), native and reference agree, and the routes move smoothly through a
## kite trim sweep and a gybe.
func _routes(id: String) -> void:
	t.begin("%s sheet routes (test 21 clearance)" % id)
	var data := BoatClassData.load_class(id)
	var bv := BoatView.create(data.info, 0.5)
	root.add_child(bv)
	var ref: BoatView = BoatView.create(data.info, 0.5, true) if native else null
	if ref != null:
		root.add_child(ref)
	var sh := bv.sheets
	var deck := _true_deck(bv)
	var jib_i := int(data.sail_index.get("jib", -1))
	var kite_i := -1
	for sp in bv.sail_parts:
		if sp.type == "spinnaker_asym":
			kite_i = sp.index
	if not t.ok(kite_i >= 0 and sh != null and not deck.is_empty(), "%s has a kite, sheets and a deck" % id):
		bv.queue_free()
		return
	var r := {"n": 0, "near": INF, "near_at": "", "cross": 0, "first": "", "deep": INF, "deep_at": "", "under": 0,
		"under_first": "", "par": 0.0, "par_n": 0, "routed": 0}
	var t0 := Time.get_ticks_msec()
	for twa_deg in range(60, 171, 10):
		for kn in [6.0, 12.0, 22.0]:
			for side in [1.0, -1.0]:
				var tws: float = kn * KNOT
				var ap := _apparent(data, kite_i, tws, deg_to_rad(float(twa_deg)), side)
				for tr in [[1.0, 1.0], [1.0 / 1.15, 1.0 / 1.15], [1.25, 1.25]]:
					for jib_up in ([false, true] if jib_i >= 0 else [false]):
						var sv := _sails_view(data, ap.x, ap.y, tws, kite_i, jib_i if jib_up else -1, tr)
						var what := "twa %d tws %.0f %s trim %.2f jib %s" % [twa_deg, kn, "stbd" if side > 0 else "port",
							tr[0], "up" if jib_up else "down"]
						_run(bv, sv, 2)
						_check_lines(bv, deck, r, what)
						# native against the reference on a subset (the reference shapes are slow)
						if native and twa_deg % 30 == 0 and kn == 12.0:
							r["par"] = maxf(r["par"], _parity(bv))
							r["par_n"] += 1
	t.ok(r["cross"] == 0 and r["near"] >= sh._r - 1e-4,
		"%d configs (%d routed round an obstacle): the flying sail's lines keep %.4f m from the main, the headsail and the boom (>= the rope radius %.4f)%s" % [
		r["n"], r["routed"], r["near"], sh._r, "" if r["first"] == "" else ", first crossing at " + r["first"]])
	t.ok(r["under"] == 0, "the lazy lines lie on or above the true deck: deepest %.4f m below it at %s (%d samples under)%s" % [
		maxf(-r["deep"], 0.0), r["deep_at"], r["under"], "" if r["under_first"] == "" else ", first " + r["under_first"]])
	print("  %s: %d configs, %d routed; nearest %.4f m (%s); lazy lines lowest %.4f m above the deck (%s); %d ms" % [
		id, r["n"], r["routed"], r["near"], r["near_at"], r["deep"], r["deep_at"], Time.get_ticks_msec() - t0])
	if ref != null:
		t.ok(r["par_n"] > 0 and r["par"] < 1e-3, "native and reference routes agree within %.6f m over %d configs" % [
			r["par"], r["par_n"]])
	# continuity: the kite sheeted from 60 % to 130 % of its optimum over 2 s, the main eased 20 %, the jib up
	var kite: BoatView.SailPart = null
	for sp in bv.sail_parts:
		if sp.index == kite_i:
			kite = sp
	var sa: float = kite.shape.frame()["sa"]
	var tws := 12.0 * KNOT
	var ap := _apparent(data, kite_i, tws, deg_to_rad(100.0), 1.0)
	var worst := 0.0
	var at := ""
	var prev := PackedVector3Array()
	for f in 121:
		var sv := _sails_view(data, ap.x, ap.y, tws, kite_i, jib_i, [0.6 + 0.7 * f / 120.0, 1.2])
		_run(bv, sv, 90 if f == 0 else 1)  # the sag settled first
		var cur := _flying_rings(sh)
		if not prev.is_empty() and _max_move(prev, cur) > worst:
			worst = _max_move(prev, cur)
			at = "frame %d" % f
		prev = cur
	t.ok(worst <= 0.05 * sa, "kite sheeted from 60 to 130 %%: no ring moves more than %.3f m a frame (<= %.3f, at %s)" % [
		worst, 0.05 * sa, at])
	# a gybe: awa from 150 deg through 180 to -150 deg over 4 s, the kite round the bow, the main across
	worst = 0.0
	prev = PackedVector3Array()
	var a0 := _apparent(data, kite_i, tws, deg_to_rad(155.0), 1.0)
	var sv0 := _sails_view(data, a0.x, a0.y, tws, kite_i, -1, [1.0, 1.0])
	var kb: float = sv0.sails[kite_i].beta
	var mb: float = sv0.sails[data.info.main_sail].beta
	for f in 241:
		var u := float(f) / 240.0
		var sv := _sails_view(data, Frames.wrap_pi(a0.x + u * (TAU - 2.0 * a0.x)), a0.y, tws, kite_i, -1, [1.0, 1.0])
		sv.sails[kite_i].beta = Frames.wrap_pi(kb + signf(kb) * u * (TAU - 2.0 * absf(kb)))
		sv.sails[data.info.main_sail].beta = lerpf(mb, -mb, smoothstep(0.3, 0.7, u))
		_run(bv, sv, 90 if f == 0 else 1)
		_check_lines(bv, deck, r, "gybe %.2f" % u)
		var cur := _flying_rings(sh)
		if not prev.is_empty() and _max_move(prev, cur) > worst:
			worst = _max_move(prev, cur)
			at = "u %.3f" % u
		prev = cur
	t.ok(worst <= 0.05 * sa, "through a gybe no ring of the kite's lines moves more than %.3f m a frame (<= %.3f, at %s)" % [
		worst, 0.05 * sa, at])
	t.ok(r["cross"] == 0 and r["under"] == 0, "and the gybe keeps them clear (nearest %.4f m) and on the deck%s%s" % [r["near"],
		"" if r["first"] == "" else ", first crossing " + r["first"], "" if r["under_first"] == "" else ", under " + r["under_first"]])
	print("  %s: trim sweep and gybe, largest ring move %.3f m (0.05 Sa %.3f)" % [id, worst, 0.05 * sa])
	bv.queue_free()
	if ref != null:
		ref.queue_free()


## Native against the reference on the boat's current update: the routes of the kite's clew to both quarter blocks,
## and a SheetRopesRef given the same lines, inputs and deck field as each native surface. The largest difference (m).
static func _parity(bv: BoatView) -> float:
	var sh := bv.sheets
	var worst := 0.0
	var rr := SheetRopesRef.new()
	var kite: BoatView.SailPart = sh.followed[BoatSheets.Surface.FLYING]
	if kite != null:
		var clew: Vector3 = kite.shape.mid_points(PackedInt32Array([kite.cols - 1]))[0]
		var jib := sh._pick(false)
		for side in 2:
			var sg := 1.0 if side == 1 else -1.0
			var obs := sh._route_obstacles(side, jib)
			var lead: Vector3 = sh._leads["flying"]["lead"][side]
			var a: PackedVector3Array = sh._router.route(clew, lead, sh._pivot(sg), sg, obs, 0.5, BoatSheets.WAYS_WORK)
			var b: PackedVector3Array = rr.route(clew, lead, sh._pivot(sg), sg, obs, 0.5, BoatSheets.WAYS_WORK)
			if a.size() != b.size():
				return INF
			for k in a.size():
				worst = maxf(worst, a[k].distance_to(b[k]))
	for surf in 2:
		var shape: Variant = sh.shapes[surf]
		if shape == null:
			continue
		var ref := SheetRopesRef.new()
		ref.configure({"sides": BoatSheets.SIDES[sh.detail], "tile": BoatSheets.TILE, "lines": sh.line_specs[surf],
			"deck": sh._deck})
		ref.update(sh.last_starts[surf], sh.last_ways[surf], sh.last_drive[surf], Vector3.DOWN)
		var pa: PackedVector3Array = shape.positions()
		var pb := ref.positions()
		for k in pa.size():
			worst = maxf(worst, pa[k].distance_to(pb[k]))
	return worst


## The rings of the flying sail's sheets (the tack line left out), in one array.
static func _flying_rings(sh: BoatSheets) -> PackedVector3Array:
	var out := PackedVector3Array()
	var s: Variant = sh.shapes[BoatSheets.Surface.FLYING]
	if s != null:
		for i in mini(2, s.get_line_count()):
			out.append_array(s.centre(i))
	return out


static func _max_move(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var w := 0.0
	for k in mini(a.size(), b.size()):
		w = maxf(w, a[k].distance_to(b[k]))
	return w


## One drawn update: the flying sail's lines against the main, the shown headsail and the boom; the lazy lines
## against the true deck.
func _check_lines(bv: BoatView, deck: Dictionary, r: Dictionary, what: String) -> void:
	var sh := bv.sheets
	r["n"] += 1
	var rad: float = sh._r
	var nf: int = BoatSheets.FREE_RINGS[sh.detail]
	var nl: int = BoatSheets.LEAD_RINGS[sh.detail]
	# obstacles: triangles of the main and the shown headsail, the boom's box in its frame
	var tris := PackedVector3Array()
	for sp in bv.sail_parts:
		if sp.shape == null or not sp.node.visible or BoatView.is_flying(sp.type):
			continue
		if sp.type != "main" and sp != sh.followed[BoatSheets.Surface.HEADSAIL]:
			continue
		var m: PackedVector3Array = sp.shape.mid()
		for i in sp.rows - 1:
			for j in sp.cols - 1:
				var a := m[i * sp.cols + j]
				var b := m[(i + 1) * sp.cols + j]
				var c := m[(i + 1) * sp.cols + j + 1]
				var d := m[i * sp.cols + j + 1]
				tris.append_array([a, b, c, a, c, d])
	var boxes := []
	for k in tris.size() / 3:
		boxes.append(AABB(tris[3 * k], Vector3.ZERO).expand(tris[3 * k + 1]).expand(tris[3 * k + 2]).grow(rad + 0.02))
	var boom_xf: Transform3D = sh._boom_parent * sh._boom_rest * Transform3D(Basis(bv._boom_axis, bv.boom_angle), Vector3.ZERO)
	var boom_inv := boom_xf.affine_inverse()
	var boom_box := AABB(sh._boom_box[0], Vector3.ZERO)
	for p in sh._boom_box:
		boom_box = boom_box.expand(p)
	var fs: Variant = sh.shapes[BoatSheets.Surface.FLYING]
	var kite: BoatView.SailPart = sh.followed[BoatSheets.Surface.FLYING]
	if fs != null and kite != null:
		var lw: PackedVector3Array = sh.last_ways[BoatSheets.Surface.FLYING]
		for j in lw.size():
			if not is_nan(lw[j].x) and absf(lw[j].x) > 1e-3:
				r["routed"] += 1
				break
		for i in mini(2, fs.get_line_count()):
			var c: PackedVector3Array = fs.centre(i)
			for k in nf - 1:
				var p := c[k]
				var q := c[k + 1]
				var sb := AABB(p, Vector3.ZERO).expand(q)
				for ti in boxes.size():
					if not (boxes[ti] as AABB).intersects(sb):
						continue
					var d := _seg_tri(p, q, tris[3 * ti], tris[3 * ti + 1], tris[3 * ti + 2])
					if d < r["near"]:
						r["near"] = d
						r["near_at"] = "%s line %d ring %d" % [what, i, k]
					if d < rad - 1e-4:
						r["cross"] += 1
						if r["first"] == "":
							r["first"] = "%s line %d ring %d (%.4f m)" % [what, i, k, d]
				var ns := maxi(1, ceili(p.distance_to(q) / 0.01))
				for s in ns + 1:
					var lp: Vector3 = boom_inv * p.lerp(q, float(s) / ns)
					var d := _aabb_dist(boom_box, lp)
					if d < r["near"]:
						r["near"] = d
						r["near_at"] = "%s line %d ring %d (boom)" % [what, i, k]
					if d < rad - 1e-4:
						r["cross"] += 1
						if r["first"] == "":
							r["first"] = "%s line %d ring %d boom (%.4f m)" % [what, i, k, d]
	# the lazy lines over the deck, every 2 cm along the tube of the free and lead runs
	for surf in 2:
		var shape: Variant = sh.shapes[surf]
		var sp: BoatView.SailPart = sh.followed[surf]
		if shape == null or sp == null:
			continue
		var lazy := 1 if sp.beta > 0.0 else 0
		if surf == BoatSheets.Surface.FLYING and sh._pole:
			continue  # the guy works
		var c: PackedVector3Array = shape.centre(lazy)
		for k in mini(nf + nl, c.size()) - 1:
			var p := c[k]
			var q := c[k + 1]
			var ns := maxi(1, ceili(Vector2(q.x - p.x, q.z - p.z).length() / 0.02))
			for s in range(1, ns):
				var x := p.lerp(q, float(s) / ns)
				var h := _deck_at(deck, x.x, x.z)
				if h <= SheetRopesRef.NO_DECK:
					continue
				var above := x.y - rad - h
				if above < r["deep"]:
					r["deep"] = above
					r["deep_at"] = "%s %s lazy ring %d" % [what, ["headsail", "flying"][surf], k]
				if above < -2e-3:
					r["under"] += 1
					if r["under_first"] == "":
						r["under_first"] = "%s %s ring %d (%.4f m under)" % [what, ["headsail", "flying"][surf], k, -above]


## The true top of the model's deck (model axes; the deck part of the merged body), bucketed for lookups.
static func _true_deck(bv: BoatView) -> Dictionary:
	var m: Node3D = bv.levels[0]["model"]
	var tri := PackedVector3Array()
	var box := AABB()
	for e in BoatMaterials.part_surfaces(m, "deck"):
		var p: PackedVector3Array = e["positions"]
		for i in (e["indices"] as PackedInt32Array):
			box = AABB(p[i], Vector3.ZERO) if tri.is_empty() else box.expand(p[i])
			tri.append(p[i])
	if tri.is_empty():
		return {}
	var cell := 0.25
	var nx := int(ceil(box.size.x / cell)) + 1
	var nz := int(ceil(box.size.z / cell)) + 1
	var buckets := []
	buckets.resize(nx * nz)
	for k in buckets.size():
		buckets[k] = PackedInt32Array()
	for t3 in tri.size() / 3:
		var a := tri[3 * t3]
		var b := tri[3 * t3 + 1]
		var c := tri[3 * t3 + 2]
		var i0 := clampi(int((minf(a.x, minf(b.x, c.x)) - box.position.x) / cell), 0, nx - 1)
		var i1 := clampi(int((maxf(a.x, maxf(b.x, c.x)) - box.position.x) / cell), 0, nx - 1)
		var k0 := clampi(int((minf(a.z, minf(b.z, c.z)) - box.position.z) / cell), 0, nz - 1)
		var k1 := clampi(int((maxf(a.z, maxf(b.z, c.z)) - box.position.z) / cell), 0, nz - 1)
		for k in range(k0, k1 + 1):
			for i in range(i0, i1 + 1):
				var bk: PackedInt32Array = buckets[k * nx + i]
				bk.append(t3)
				buckets[k * nx + i] = bk
	return {"tri": tri, "buckets": buckets, "o": Vector2(box.position.x, box.position.z), "cell": cell, "nx": nx, "nz": nz}


static func _deck_at(d: Dictionary, x: float, z: float) -> float:
	var o: Vector2 = d["o"]
	var i := int((x - o.x) / float(d["cell"]))
	var k := int((z - o.y) / float(d["cell"]))
	if x < o.x or z < o.y or i >= int(d["nx"]) or k >= int(d["nz"]):
		return SheetRopesRef.NO_DECK
	var tri: PackedVector3Array = d["tri"]
	var best := SheetRopesRef.NO_DECK
	for t3 in (d["buckets"][k * int(d["nx"]) + i] as PackedInt32Array):
		var a := tri[3 * t3]
		var b := tri[3 * t3 + 1]
		var c := tri[3 * t3 + 2]
		var den := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(den) < 1e-12:
			continue
		var w0 := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / den
		var w1 := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / den
		var w2 := 1.0 - w0 - w1
		if w0 < 0.0 or w1 < 0.0 or w2 < 0.0:
			continue
		best = maxf(best, w0 * a.y + w1 * b.y + w2 * c.y)
	return best


static func _aabb_dist(b: AABB, p: Vector3) -> float:
	var q := p.clamp(b.position, b.end)
	return q.distance_to(p)


## Distance between a segment and a triangle (0 when they cross).
static func _seg_tri(p: Vector3, q: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	if Geometry3D.segment_intersects_triangle(p, q, a, b, c) != null:
		return 0.0
	var d := minf(_pt_tri(p, a, b, c).distance_to(p), _pt_tri(q, a, b, c).distance_to(q))
	for e in [[a, b], [b, c], [c, a]]:
		var cp := Geometry3D.get_closest_points_between_segments(p, q, e[0], e[1])
		d = minf(d, cp[0].distance_to(cp[1]))
	return d


## Closest point of triangle abc to p (Ericson, Real-Time Collision Detection 5.1.5).
static func _pt_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var den := 1.0 / (va + vb + vc)
	return a + ab * (vb * den) + ac * (vc * den)


## The apparent wind (awa, aws) over the config's polar speed at the true wind (tws m/s, twa rad) on a tack (side +1:
## wind from starboard). As tests/sail_visuals_test.gd.
static func _apparent(data: BoatClassData, fi: int, tws: float, twa: float, side: float) -> Vector2:
	var v: float = data.configs[fi]["polar"].at(tws, twa)
	var aw := Vector2(tws * cos(twa) + v, tws * sin(twa))
	return Vector2(side * aw.angle(), aw.length())


## The main and the flying sail up at trim factors `tr` (flying, main) of their optimum, the jib at its own when
## `jib_i` >= 0, the other sails down. As tests/sail_visuals_test.gd.
func _sails_view(data: BoatClassData, awa: float, aws: float, tws: float, fi: int, jib_i: int, tr: Array) -> SimSource.SailsView:
	var sv := SimSource.SailsView.new()
	sv.awa = awa
	sv.aws = aws
	sv.tws = tws
	var cfg: Dictionary = data.configs[fi]
	for i in data.info.sails.size():
		var st := SimSource.SailState.new()
		var si: SimSource.SailInfo = data.info.sails[i]
		var opt: PerfTable = null
		var f := 1.0
		if i == data.info.main_sail:
			opt = cfg["optimal"].get(i)
			f = tr[1]
		elif i == fi:
			opt = cfg["optimal"].get(i)
			f = tr[0]
		elif i == jib_i:
			opt = data.configs[jib_i]["optimal"].get(i)
		if i == data.info.main_sail or i == fi or i == jib_i:
			st.phase = UP
			var m: float = opt.at(tws, absf(awa)) if opt != null else si.sheet_min
			st.beta = -Frames.sgn(awa) * clampf(m * f, si.sheet_min, si.sheet_max)
		sv.sails.append(st)
		sv.out.append(SimSource.SailOutput.new())
	return sv
