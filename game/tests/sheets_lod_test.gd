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
			t.ok(sag < 0.01, "the trimmed working sheet is nearly straight (sag %.4f of the span)" % sag)
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
		t.ok(not is_nan((sh.last_ways[1] as PackedVector3Array)[1].x), "the lazy kite sheet runs round the forestay")
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
	t.ok(bv.levels.size() == 3, "three levels loaded (%d)" % bv.levels.size())
	var lv := Livery.load_class(id)[0]
	bv.set_livery(lv)
	_run(bv, _sv(data.info, {"main": UP, "jib": UP}, -0.35, 0.8, 5.0), 10)
	var seq := [[25.0, 0], [35.0, 1], [29.0, 1], [28.0, 0], [90.0, 1], [110.0, 2], [96.0, 2], [94.0, 1]]
	for e in seq:
		bv.update_lod(e[0])
		t.ok(bv.lod == e[1], "camera at %.0f m: LOD%d (%d)" % [e[0], e[1], bv.lod])
		var shown := 0
		for k in bv.levels.size():
			for n: Node3D in bv.levels[k]["parts"]:
				if n.visible and n.name != "pole":
					shown += 1 if k == bv.lod else 100
		t.ok(shown > 0 and shown < 100, "only LOD%d's parts are shown" % bv.lod)
		t.ok(bv.sheets.detail == bv.lod and bv.sheets.node.visible == (bv.lod < 2),
			"sheets at detail %d, %s" % [bv.sheets.detail, "shown" if bv.sheets.node.visible else "hidden"])
	# the livery on every level: the same material objects by part and slot
	var by_slot := {}
	var missing := []
	for k in bv.levels.size():
		for part in ["hull", "keel", "deck"]:
			var mi := (bv.levels[k]["model"] as Node3D).find_child(part, true, false) as MeshInstance3D
			if mi == null:
				missing.append("%s@%d" % [part, k])
				continue
			for s in mi.mesh.get_surface_count():
				var slot := mi.mesh.surface_get_material(s).resource_name
				var key: String = part + "/" + slot
				var m := mi.get_surface_override_material(s)
				if k == 0:
					by_slot[key] = m
				elif by_slot.has(key) and by_slot[key] != m:
					missing.append("%s@%d" % [key, k])
	t.ok(missing.is_empty(), "every level's hull, keel and deck carry the boat's livery materials (%s)" % [missing])
	for key in ["hull/gelcoat", "hull/antifouling", "keel/antifouling", "deck/transom", "deck/gelcoat"]:
		if by_slot.has(key):
			t.ok(by_slot[key] != null, "%s painted on every level" % key)
	# the moving parts of the level shown follow the boom
	bv.update_lod(50.0)
	_run(bv, _sv(data.info, {"main": UP, "jib": UP}, -0.5, 0.8, 5.0), 3)
	var b1: Node3D = bv.levels[1]["boom"]
	var b0: Node3D = bv.levels[0]["boom"]
	t.ok(b1 != null and b1.transform.basis.is_equal_approx(b1.transform.basis) and
		(b1.transform.basis * Vector3.BACK).dot(Basis(Vector3.UP, bv.boom_angle) * (bv.levels[1]["boom_rest"] as Transform3D).basis * Vector3.BACK) > 0.999,
		"LOD1's boom at the main's angle")
	t.ok(b0 != null, "LOD0 keeps its boom for when it comes back")
	bv.queue_free()


func _ropes(id: String) -> void:
	t.begin("%s rope materials" % id)
	var data := BoatClassData.load_class(id)
	var lv := Livery.load_class(id)[0]
	var rs := BakedLivery.rope_set(id)
	t.ok(rs.get("albedo", {}).size() == Livery.ROPES.size(), "baked rope set: %d functions" % rs.get("albedo", {}).size())
	var bv := BoatView.create(data.info, 0.5)
	bv.set_livery(lv)
	var found := {}
	for k in bv.levels.size():
		var stack: Array[Node] = [bv.levels[k]["model"]]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			stack.append_array(node.get_children())
			var mi := node as MeshInstance3D
			if mi == null or mi.mesh == null or mi == bv.sheets.node:
				continue
			for s in mi.mesh.get_surface_count():
				var slot := mi.mesh.surface_get_material(s).resource_name
				if slot.begins_with("rope_"):
					var m := mi.get_surface_override_material(s) as ShaderMaterial
					var fn := slot.trim_prefix("rope_")
					var key: String = "%d/%s/%s" % [k, mi.name, slot]
					if not found.has(key):
						t.ok(m != null and m.get_shader_parameter("albedo_tex") == rs["albedo"][fn],
							"LOD%d %s/%s: the baked %s braid" % [k, mi.name, slot, fn])
					found[key] = true
					found[fn] = true
	for fn in ["mainsheet", "halyard", "control"]:
		t.ok(found.has(fn), "the model carries %s ropes" % fn)
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
		var t0 := Time.get_ticks_usec()
		for r in reps:
			bv.sheets.step(5.0, 1.0 / 60.0, true)
		var us := float(Time.get_ticks_usec() - t0) / reps
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
