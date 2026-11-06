extends SceneTree
## Offline preview of the sails, step 1 (headless, no window): sails a boat on the core (the GDExtension) into a set
## of situations (trimmed upwind, eased, let fly, mid-tack with the jib aback, kite hoist, reach, run, drop, jib
## hoist, the wm12 code zero), bends the sails with BoatView exactly as the scene does, and dumps every mesh of the
## boat (the sails from their SailShape) with a camera to generated/sail_preview/<shot>/. Step 2,
## tests/sail_preview.py, renders them offscreen with OpenGL.
##   godot --headless --path game -s res://tests/sail_preview_dump.gd [-- shot ...]
##   godot --headless --path game -s res://tests/sail_preview_dump.gd -- kite_loft    (the comparison of
##       sail_visuals.md §6.5: wm7's kite on the hinge and the lofted model, tests/kite_loft_preview.py)
##   godot --headless --path game -s res://tests/sail_preview_dump.gd -- kite_ac      (wm7 and wm21 on the hinge
##       model and on the measured surfaces of §6.5, tests/kite_ac_preview.py)

const KNOT := 1852.0 / 3600.0
const OUT := "res://generated/sail_preview"

## shots: class, true wind (kn), the first leg's true wind angle, then legs of {t (s), twa (held by a helm
## controller) or h (fixed helm), auto, sheet, let_fly, req (sail request at the start of the leg), until (stop
## condition)}, and the camera: side (+1 leeward, -1 windward), fwd and up (fractions of the distance), dist (m)
var SHOTS := [
	{"name": "upwind_trimmed", "cls": "wm7", "tws": 12.0, "twa": 42.0, "legs": [{"t": 20.0, "twa": 42.0}],
		"cam": {"side": 1, "fwd": -0.45, "up": 0.3, "dist": 21.0}},
	{"name": "upwind_windward", "cls": "wm7", "tws": 12.0, "twa": 42.0, "legs": [{"t": 20.0, "twa": 42.0}],
		"cam": {"side": -1, "fwd": 0.55, "up": 0.25, "dist": 21.0}},
	{"name": "upwind_eased", "cls": "wm7", "tws": 12.0, "twa": 42.0,
		"legs": [{"t": 15.0, "twa": 42.0}, {"t": 2.5, "twa": 42.0, "auto": false, "sheet": 0.75}],
		"cam": {"side": 1, "fwd": -0.45, "up": 0.3, "dist": 21.0}},
	{"name": "let_fly", "cls": "wm7", "tws": 12.0, "twa": 42.0,
		"legs": [{"t": 15.0, "twa": 42.0}, {"t": 3.0, "h": 0.0, "let_fly": true}],
		"cam": {"side": 1, "fwd": -0.45, "up": 0.3, "dist": 21.0}},
	{"name": "tack_jib_aback", "cls": "wm7", "tws": 12.0, "twa": 42.0,
		"legs": [{"t": 15.0, "twa": 42.0}, {"t": 8.0, "h": 1.0, "until": "backed"}, {"t": 0.3, "h": 1.0}],
		"cam": {"side": -1, "fwd": 0.6, "up": 0.3, "dist": 21.0}},
	{"name": "kite_hoist_50", "cls": "wm7", "tws": 12.0, "twa": 110.0,
		"legs": [{"t": 10.0, "twa": 110.0}, {"t": 30.0, "twa": 110.0, "req": "kite", "until": "hoist:kite:0.5"}],
		"cam": {"side": 1, "fwd": 0.2, "up": 0.3, "dist": 24.0}},
	{"name": "kite_hoist_95", "cls": "wm7", "tws": 12.0, "twa": 110.0,
		"legs": [{"t": 10.0, "twa": 110.0}, {"t": 30.0, "twa": 110.0, "req": "kite", "until": "hoist:kite:0.95"}],
		"cam": {"side": 1, "fwd": 0.2, "up": 0.3, "dist": 24.0}},
	{"name": "reach_kite", "cls": "wm7", "tws": 12.0, "twa": 110.0,
		"legs": [{"t": 10.0, "twa": 110.0}, {"t": 40.0, "twa": 110.0, "req": "kite"}],
		"cam": {"side": 1, "fwd": 0.2, "up": 0.3, "dist": 24.0}},
	{"name": "run_kite", "cls": "wm7", "tws": 12.0, "twa": 150.0,
		"legs": [{"t": 10.0, "twa": 150.0}, {"t": 40.0, "twa": 150.0, "req": "kite"}],
		"cam": {"side": 1, "fwd": 0.55, "up": 0.3, "dist": 24.0}},
	{"name": "kite_drop_40", "cls": "wm7", "tws": 12.0, "twa": 140.0,
		"legs": [{"t": 10.0, "twa": 140.0}, {"t": 40.0, "twa": 140.0, "req": "kite"},
			{"t": 30.0, "twa": 140.0, "req": "jib", "until": "drop:kite:0.4"}],
		"cam": {"side": 1, "fwd": 0.3, "up": 0.3, "dist": 24.0}},
	{"name": "jib_hoist_50", "cls": "wm7", "tws": 12.0, "twa": 140.0,
		"legs": [{"t": 10.0, "twa": 140.0}, {"t": 40.0, "twa": 140.0, "req": "kite"},
			{"t": 40.0, "twa": 140.0, "req": "jib", "until": "hoist:jib:0.5"}],
		"cam": {"side": -1, "fwd": 0.5, "up": 0.3, "dist": 21.0}},
	{"name": "cloth_main_close", "cls": "wm7", "tws": 12.0, "twa": 42.0, "legs": [{"t": 20.0, "twa": 42.0}],
		"cam": {"side": 1, "fwd": -0.75, "up": 0.05, "dist": 7.5}},
	{"name": "cloth_backlit", "cls": "wm7", "tws": 12.0, "twa": 42.0, "legs": [{"t": 20.0, "twa": 42.0}],
		"cam": {"side": -1, "fwd": -0.3, "up": 0.15, "dist": 14.0, "sun": "back"}},
	{"name": "wm12_upwind", "cls": "wm12", "tws": 12.0, "twa": 40.0, "legs": [{"t": 20.0, "twa": 40.0}],
		"cam": {"side": 1, "fwd": -0.45, "up": 0.3, "dist": 32.0}},
	{"name": "wm12_reach_kite", "cls": "wm12", "tws": 12.0, "twa": 110.0,
		"legs": [{"t": 10.0, "twa": 110.0}, {"t": 40.0, "twa": 110.0, "req": "a2"}],
		"cam": {"side": 1, "fwd": 0.2, "up": 0.3, "dist": 36.0}},
	{"name": "wm12_run_kite", "cls": "wm12", "tws": 12.0, "twa": 150.0,
		"legs": [{"t": 10.0, "twa": 150.0}, {"t": 40.0, "twa": 150.0, "req": "a2"}],
		"cam": {"side": 1, "fwd": 0.55, "up": 0.3, "dist": 36.0}},
	{"name": "wm12_code0", "cls": "wm12", "tws": 10.0, "twa": 75.0,
		"legs": [{"t": 10.0, "twa": 75.0}, {"t": 40.0, "twa": 75.0, "req": "code0"}],
		"cam": {"side": 1, "fwd": 0.25, "up": 0.3, "dist": 32.0}},
	{"name": "cloth_kite_close", "cls": "wm7", "tws": 12.0, "twa": 110.0,
		"legs": [{"t": 10.0, "twa": 110.0}, {"t": 40.0, "twa": 110.0, "req": "kite"}],
		"cam": {"side": 1, "fwd": 0.35, "up": 0.1, "dist": 11.0}},
	# the running sheets (sail_visuals.md §11.3): the kite sheet's route round the main from aft and from above,
	# and the lazy sheets on the deck close up
	{"name": "sheets_reach_aft", "cls": "wm7", "tws": 12.0, "twa": 110.0,
		"legs": [{"t": 10.0, "twa": 110.0}, {"t": 40.0, "twa": 110.0, "req": "kite"}],
		"cam": {"side": 0.3, "fwd": -0.94, "up": 0.4, "dist": 11.0, "tup": 1.5, "tside": 1.0, "rope_hi": 0.02}},
	{"name": "sheets_reach_above", "cls": "wm7", "tws": 12.0, "twa": 110.0,
		"legs": [{"t": 10.0, "twa": 110.0}, {"t": 40.0, "twa": 110.0, "req": "kite"}],
		"cam": {"side": 0.1, "fwd": -0.15, "up": 1.0, "dist": 19.0, "tup": 0.0, "tside": 1.5, "tfwd": -0.3, "rope_hi": 0.025}},
	{"name": "sheets_run_aft", "cls": "wm7", "tws": 12.0, "twa": 150.0,
		"legs": [{"t": 10.0, "twa": 150.0}, {"t": 40.0, "twa": 150.0, "req": "kite"}],
		"cam": {"side": 0.3, "fwd": -0.94, "up": 0.4, "dist": 11.0, "tup": 1.5, "tside": 1.0, "rope_hi": 0.02}},
	{"name": "sheets_run_above", "cls": "wm7", "tws": 12.0, "twa": 150.0,
		"legs": [{"t": 10.0, "twa": 150.0}, {"t": 40.0, "twa": 150.0, "req": "kite"}],
		"cam": {"side": 0.1, "fwd": -0.15, "up": 1.0, "dist": 19.0, "tup": 0.0, "tside": 1.5, "tfwd": -0.3, "rope_hi": 0.025}},
	{"name": "sheets_wm12_reach_above", "cls": "wm12", "tws": 12.0, "twa": 110.0,
		"legs": [{"t": 10.0, "twa": 110.0}, {"t": 40.0, "twa": 110.0, "req": "a2"}],
		"cam": {"side": 0.1, "fwd": -0.15, "up": 1.0, "dist": 30.0, "tup": 0.0, "tside": 2.5, "tfwd": -0.5, "rope_hi": 0.035}},
	{"name": "sheets_lazy_deck", "cls": "wm7", "tws": 12.0, "twa": 42.0, "legs": [{"t": 20.0, "twa": 42.0}],
		"cam": {"side": -0.55, "fwd": -0.3, "up": 0.75, "dist": 3.4, "tup": 0.5, "tfwd": 0.0, "tside": -0.5, "rope_hi": 0.0001}},
	{"name": "sheets_lazy_kite_deck", "cls": "wm7", "tws": 12.0, "twa": 110.0,
		"legs": [{"t": 10.0, "twa": 110.0}, {"t": 40.0, "twa": 110.0, "req": "kite"}],
		"cam": {"side": -0.6, "fwd": -0.5, "up": 0.6, "dist": 4.5, "tup": 0.5, "tfwd": -1.2, "tside": -0.6, "rope_hi": 0.0001}},
	{"name": "sheets_wm12_lazy_deck", "cls": "wm12", "tws": 12.0, "twa": 40.0, "legs": [{"t": 20.0, "twa": 40.0}],
		"cam": {"side": -0.55, "fwd": -0.3, "up": 0.75, "dist": 5.0, "tup": 0.8, "tside": -0.7, "rope_hi": 0.0001}},
	{"name": "cloth_wm12_close", "cls": "wm12", "tws": 12.0, "twa": 40.0, "legs": [{"t": 20.0, "twa": 40.0}],
		"cam": {"side": 1, "fwd": -0.7, "up": 0.1, "dist": 11.0}},
]


## sail_visuals.md §6.5: wm7's kite drawn on the hinge model and on the lofted one at AWA about 64, 95 and 124 deg
## (12 kn, the helm holding the apparent wind), each from the leeward side, the stern quarter and the bow quarter
var KITE_LOFT_VIEWS := {
	"side": {"side": 1, "fwd": 0.05, "up": 0.1, "dist": 15.5},
	"stern": {"side": 1, "fwd": -0.72, "up": 0.2, "dist": 15.5},
	"bow": {"side": 1, "fwd": 0.72, "up": 0.12, "dist": 15.5},
}


func _kite_loft_shots() -> Array:
	var out := []
	for awa in [64, 95, 124]:
		for model in ["hinge", "loft"]:
			out.append({"name": "kite_loft_%d_%s" % [awa, model], "cls": "wm7", "tws": 12.0, "twa": float(awa) + 30.0,
				"model": model, "views": KITE_LOFT_VIEWS,
				"legs": [{"t": 12.0, "awa": float(awa)}, {"t": 45.0, "awa": float(awa), "req": "kite"}],
				"cam": KITE_LOFT_VIEWS["side"]})
	return out


## sail_visuals.md §6.5: the kites from measured surfaces (wm7 the AC33 asymmetric at AWA about 60, 95 and 130 deg;
## wm21 the IACC symmetric series at TWA about 150 and 180 deg), each on the hinge model and on the fixed surface
## shape, from the leeward side, the stern quarter and the bow quarter (tests/kite_ac_preview.py)
func _kite_ac_shots() -> Array:
	var out := []
	for awa in [60, 95, 130]:
		for model in ["hinge", "loft"]:
			out.append({"name": "kite_ac_wm7_awa%d_%s" % [awa, model], "cls": "wm7", "tws": 12.0,
				"twa": float(awa) + 30.0, "model": model, "views": KITE_LOFT_VIEWS,
				"legs": [{"t": 12.0, "awa": float(awa)}, {"t": 45.0, "awa": float(awa), "req": "kite"}],
				"cam": KITE_LOFT_VIEWS["side"]})
	var big := {}
	for v in KITE_LOFT_VIEWS:
		big[v] = KITE_LOFT_VIEWS[v].duplicate()
		big[v]["dist"] = 46.0
	for twa in [150, 177]:
		for model in ["hinge", "loft"]:
			out.append({"name": "kite_ac_wm21_twa%d_%s" % [twa, model], "cls": "wm21", "tws": 12.0,
				"twa": float(twa), "model": model, "views": big,
				"legs": [{"t": 15.0, "twa": float(twa)}, {"t": 60.0, "twa": float(twa), "req": "spin"}],
				"cam": big["side"]})
	return out


var _twa := 0.0


func _init() -> void:
	_main()


func _main() -> void:
	await process_frame
	if not CoreSimSource.available():
		print("sail preview: the GDExtension is not built (game/native/build.sh)")
		quit(1)
		return
	var want := OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var names := []
	var shots := SHOTS
	if want.has("kite_loft"):
		shots = _kite_loft_shots()
		want = []
	elif want.has("kite_ac"):
		shots = _kite_ac_shots()
		want = []
	for spec in shots:
		if want.is_empty() or want.has(spec["name"]):
			_shot(spec)
		for v in spec.get("views", {"": null}):
			var nm: String = spec["name"] + ("_" + v if v != "" else "")
			if FileAccess.file_exists(OUT.path_join(nm).path_join("scene.json")):
				names.append(nm)
	var f := FileAccess.open(OUT.path_join("index.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(names))
	quit(0)


func _shot(spec: Dictionary) -> void:
	var sim := CoreSimSource.new()
	sim.settings = {"wind_speed": float(spec["tws"]) * KNOT, "wind_from": 0.0, "shift_preset": 0, "puffs": false,
		"seed": 11}
	if not sim.create():
		print("create failed: ", sim.last_error())
		return
	var b := sim.add_boat(spec["cls"], 0.0, 0.0, Frames.wrap_2pi(-deg_to_rad(float(spec["twa"]))))
	var info := sim.class_info(b)
	var idx := {}
	for i in info.sails.size():
		idx[info.sails[i].name] = i
	var bv := BoatView.create(info, info.rudder_max)
	var prev := sim.sails(b)
	var cur := prev
	var note := ""
	for leg in spec["legs"]:
		var ticks := int(float(leg["t"]) / SimSource.DT)
		var req := InputFrame.SAIL_NONE
		if leg.has("req"):
			req = InputFrame.hoist_req(idx[leg["req"]])
		for k in ticks:
			var s := sim.state(b)
			var f := InputFrame.new()
			f.tick = sim.tick()
			if leg.has("h"):
				f.h_cmd = float(leg["h"])
			elif leg.has("awa"):  # hold the apparent wind angle
				f.h_cmd = clampf(1.0 * Frames.angle_diff(s.awa, deg_to_rad(float(leg["awa"]))), -1.0, 1.0)
			else:
				f.h_cmd = clampf(1.5 * Frames.angle_diff(s.twa, deg_to_rad(float(leg["twa"]))), -1.0, 1.0)
			var auto: bool = leg.get("auto", true)
			f.flags = InputFrame.FLAG_AUTO_TRIM if auto else 0
			if leg.get("let_fly", false):
				f.flags |= InputFrame.FLAG_LET_FLY
			f.sheet_cmd = float(leg.get("sheet", 0.5))
			f.sail_req = req if k == 0 else InputFrame.SAIL_NONE
			sim.apply_input(b, f)
			sim.step()
			prev = cur
			cur = sim.sails(b)
			_twa = sim.state(b).twa
			# the shapes' drivers (flutter phase, backed factor) run every tick as in the scene
			bv.apply_sails(prev, cur, 1.0, SimSource.DT)
			if _until(String(leg.get("until", "")), cur, idx):
				break
	if spec.has("model"):  # sail_visuals.md §6.5: the kite on the model asked for
		for sp in bv.sail_parts:
			if KiteSet.is_kite(sp.type):
				var ks := sp.kset.duplicate()
				ks["model"] = spec["model"]
				bv.reshape_kite(sp.id, {}, ks)
	bv.apply(sim.render_pose(b, 1.0))
	for k in 3:  # the main's stop (§7.6) reads the kite's clew as last placed
		bv.apply_sails(prev, cur, 1.0, 1.0 / 60.0)
	var st := sim.state(b)
	var sails_note := []
	for sp in bv.sail_parts:
		var ss: SimSource.SailState = cur.sails[sp.index]
		var so: SimSource.SailOutput = cur.out[sp.index]
		sails_note.append("%s %s p%.2f beta %.0f I %.2f%s%s" % [sp.id, ["down", "prep", "hoist", "up", "prep_drop",
			"drop"][ss.phase], ss.progress, rad_to_deg(ss.beta), so.luff_shiver, " backed" if so.backed else "",
			(" gamma %.0f ease %.0f" % [rad_to_deg(ss.pole), rad_to_deg(sp.shape.get_ease())]) if KiteSet.is_kite(sp.type) else ""])
	note = "%s: twa %.0f awa %.0f aws %.1f kn heel %.0f | %s" % [spec["name"], rad_to_deg(st.twa), rad_to_deg(st.awa),
		st.aws / KNOT, rad_to_deg(st.phi), ", ".join(sails_note)]
	print(note)
	if spec.has("views"):
		for v in spec["views"]:
			var sv := spec.duplicate()
			sv["name"] = spec["name"] + "_" + v
			sv["cam"] = spec["views"][v]
			_dump(sv, bv, st, note + " | " + spec.get("model", "") + ", " + v)
	else:
		_dump(spec, bv, st, note)
	bv.free()


func _until(cond: String, cur: SimSource.SailsView, idx: Dictionary) -> bool:
	if cond == "":
		return false
	var p := cond.split(":")
	if p[0] == "twa_below":
		return _twa < deg_to_rad(float(p[1]))
	if p[0] == "backed":
		for i in cur.out.size():
			if cur.out[i].backed and cur.sails[i].phase == SimSource.Phase.UP and i != 0:
				return true
		return false
	var s: SimSource.SailState = cur.sails[idx[p[1]]]
	var ph := SimSource.Phase.HOISTING if p[0] == "hoist" else SimSource.Phase.DROPPING
	return s.phase == ph and s.progress >= float(p[2])


static func _chain(n: Node, top: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var x := n
	while x != null and x != top:
		if x is Node3D:
			t = (x as Node3D).transform * t
		x = x.get_parent()
	return t


func _dump(spec: Dictionary, bv: BoatView, st: SimSource.BoatState, note: String) -> void:
	var dir := OUT.path_join(spec["name"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var sail_nodes := {}
	for sp in bv.sail_parts:
		sail_nodes[sp.node] = sp
	var meshes := []
	var stack: Array = [bv]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not (n is MeshInstance3D) or not (n as MeshInstance3D).visible or (n as MeshInstance3D).mesh == null:
			continue
		if not _visible_chain(n, bv):
			continue
		var mi := n as MeshInstance3D
		var xf := bv.transform * _chain(mi, bv)
		for si in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(si)
			var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var is_sail := sail_nodes.has(mi) and sail_nodes[mi].shape != null
			if is_sail:
				pos = sail_nodes[mi].shape.positions()
				nrm = sail_nodes[mi].shape.normals()
			if bv.sheets != null and mi == bv.sheets.node:
				# headless keeps no in-place writes: the sheets as last drawn, from their shapes
				var shp: Variant = bv.sheets.surface_shape(si)
				pos = shp.positions()
				nrm = shp.normals()
			var ind: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if ind.is_empty():
				ind.resize(pos.size())
				for k in pos.size():
					ind[k] = k
			var wp := PackedFloat32Array()
			wp.resize(pos.size() * 6)
			var nb := xf.basis.inverse().transposed()
			# "rope_hi": the running sheets drawn fatter (by that many m) and coloured by surface, to see their route
			var hi := float(spec["cam"].get("rope_hi", 0.0)) if bv.sheets != null and mi == bv.sheets.node else 0.0
			for k in pos.size():
				var q := (nb * nrm[k]).normalized() if nrm.size() == pos.size() else Vector3.UP
				var p := xf * pos[k] + q * hi
				wp[6 * k] = p.x
				wp[6 * k + 1] = p.y
				wp[6 * k + 2] = p.z
				wp[6 * k + 3] = q.x
				wp[6 * k + 4] = q.y
				wp[6 * k + 5] = q.z
			var mat := mi.get_active_material(si)
			var col := Color(0.8, 0.8, 0.8)
			if mat is BaseMaterial3D:
				col = (mat as BaseMaterial3D).albedo_color
			elif mat is ShaderMaterial and (mat as ShaderMaterial).get_shader_parameter("albedo_color") is Color:
				col = (mat as ShaderMaterial).get_shader_parameter("albedo_color")
			col = Color(minf(col.r, 0.8), minf(col.g, 0.8), minf(col.b, 0.8))  # the shaders' albedo cap
			if hi > 0.0:
				col = Color(0.8, 0.25, 0.05) if si == mi.mesh.get_surface_count() - 1 else Color(0.05, 0.3, 0.8)
			var nm := "m%d" % meshes.size()
			var fv := FileAccess.open(dir.path_join(nm + "_v.bin"), FileAccess.WRITE)
			fv.store_buffer(wp.to_byte_array())
			var fi := FileAccess.open(dir.path_join(nm + "_i.bin"), FileAccess.WRITE)
			fi.store_buffer(ind.to_byte_array())
			var entry := {"name": nm, "node": String(mi.name), "sail": is_sail, "albedo": [col.r, col.g, col.b]}
			if is_sail and mat is ShaderMaterial:
				entry["cloth"] = _cloth_uniforms(mat as ShaderMaterial)
				var uvs := PackedFloat32Array()
				var u0: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				var u1: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
				uvs.resize(pos.size() * 4)
				for k in pos.size():
					uvs[4 * k] = u0[k].x
					uvs[4 * k + 1] = u0[k].y
					uvs[4 * k + 2] = u1[k].x
					uvs[4 * k + 3] = u1[k].y
				FileAccess.open(dir.path_join(nm + "_uv.bin"), FileAccess.WRITE).store_buffer(uvs.to_byte_array())
			meshes.append(entry)
	# the camera in the boat's yaw frame: side +1 = leeward (port when the wind is from starboard)
	var cam: Dictionary = spec["cam"]
	var o := bv.transform.origin
	var bow := Frames.compass_dir(st.psi)
	var port := Vector3(bow.z, 0.0, -bow.x)  # bow turned a quarter anticlockwise seen from above (west of north)
	var lee := port * (1.0 if st.awa >= 0.0 else -1.0)
	var d := float(cam["dist"])
	var eye := o + lee * float(cam["side"]) * d * sqrt(maxf(0.0, 1.0 - pow(float(cam["fwd"]), 2))) \
		+ bow * float(cam["fwd"]) * d + Vector3.UP * float(cam["up"]) * d
	var mast_h := 0.45 * float(bv.info.physics.get("rig", {}).get("masthead", [0, 0, 10])[2])
	var target := o + Vector3.UP * float(cam.get("tup", mast_h)) + bow * float(cam.get("tfwd", 0.0)) \
		+ lee * float(cam.get("tside", 0.0))
	var scene := {"meshes": meshes, "eye": [eye.x, eye.y, eye.z], "target": [target.x, target.y, target.z],
		"note": note, "sun": cam.get("sun", "side"), "light": _daylight()}
	var f := FileAccess.open(dir.path_join("scene.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(scene, "  "))


## The default daytime preset (SkyRig, water_render.md §4.5): the preview lights the boat as the game does, with
## the sun's direction its own (from the side or behind the sails).
static func _daylight() -> Dictionary:
	var rig: SkyRig = load("res://scenes/sea/sky_day.tscn").instantiate()
	var env := rig.environment()
	var s := rig.sun_radiance()
	var h := rig.horizon_linear()
	var z := rig.zenith_linear()
	var out := {"sun_color": [s.x, s.y, s.z], "horizon": [h.x, h.y, h.z], "zenith": [z.x, z.y, z.z],
		"cloud_cover": rig.cloud_cover, "cloud_offset": [rig.cloud_offset.x, rig.cloud_offset.y],
		"exposure": rig.exposure, "white": env.tonemap_white if env else 6.0,
		"ambient": env.ambient_light_energy if env else 1.0}
	rig.free()
	return out


## The sail material's uniforms for the preview's copy of the sail shader (JSON: vectors as lists).
static func _cloth_uniforms(m: ShaderMaterial) -> Dictionary:
	var out := {}
	for u in m.shader.get_shader_uniform_list():
		var n: String = u["name"]
		var v: Variant = m.get_shader_parameter(n)
		if v is Vector2:
			out[n] = [v.x, v.y]
		elif v is Vector3:
			out[n] = [v.x, v.y, v.z]
		elif v is Color:
			out[n] = [v.r, v.g, v.b, v.a]
		elif v is PackedFloat32Array:
			out[n] = Array(v)
		elif v is Texture2D:
			out[n] = ProjectSettings.globalize_path((v as Texture2D).resource_path.get_slice("::", 0))
		elif v is float or v is int or v is bool:
			out[n] = v
	return out


static func _visible_chain(n: Node, top: Node) -> bool:
	var x := n
	while x != null and x != top:
		if x is Node3D and not (x as Node3D).visible:
			return false
		x = x.get_parent()
	return true
