extends SceneTree
## Offline preview of the running sheets through their edge cases, step 1 (headless, no window): sails a class through
## a scenario of tests/ropes_test.gd (the kite upwind, a hoist, a drop, a gybe) as the scene draws it at 60 frames a
## second, and at the shot times dumps every mesh of the boat (the sails from their SailShape, the sheets from their
## SheetRopes) with a close camera to generated/ropes_preview/<tag>/<shot>_<k>/. Step 2, tests/ropes_preview.py,
## renders them with tests/sail_preview.py and sets the tags side by side.
##   godot --headless --path game -s res://tests/ropes_preview_dump.gd -- <tag> [shot ...]

const OUT := "res://generated/ropes_preview"
const Ropes := preload("res://tests/ropes_test.gd")
const ROPE_HI := 0.008

## shots: class, scenario (ropes_test.gd), times (s into the recorded part), camera in the boat's yaw frame in units
## of the class scale k = loa / 7.2: eye and target [x to leeward, y up, z forward]
var SHOTS := [
	{"name": "wm7_kite_upwind", "cls": "wm7", "sc": "kite_upwind", "times": [5.6, 6.0, 6.4, 6.8, 7.2],
		"eye": [4.6, 2.4, -3.2], "target": [1.4, 1.2, 1.4]},
	{"name": "wm7_hoist", "cls": "wm7", "sc": "hoist", "times": [3.0, 4.5, 5.8, 8.56, 10.0],
		"eye": [3.8, 3.4, -4.4], "target": [0.6, 0.9, 1.4]},
	{"name": "wm7_drop", "cls": "wm7", "sc": "drop", "times": [2.0, 3.6, 4.8, 6.0, 7.4],
		"eye": [3.8, 3.4, -4.4], "target": [0.6, 0.9, 1.4]},
	{"name": "wm21_hoist", "cls": "wm21", "sc": "hoist", "times": [3.0, 5.5, 8.0, 10.7, 13.0],
		"eye": [3.8, 3.4, -4.4], "target": [0.6, 0.9, 1.4]},
	{"name": "wm21_drop", "cls": "wm21", "sc": "drop", "times": [3.0, 4.5, 6.0, 7.5, 9.0],
		"eye": [3.8, 3.4, -4.4], "target": [0.6, 0.9, 1.4]},
	{"name": "wm21_gybe", "cls": "wm21", "sc": "gybe", "times": [2.0, 3.0, 3.6, 3.7, 4.6],
		"eye": [0.8, 4.6, -6.0], "target": [0.0, 0.9, 2.0]},
]

var _tag := "now"
var _spec := {}
var _frames := {}
var _lee := 1.0


func _init() -> void:
	_main()


func _main() -> void:
	await process_frame
	if not CoreSimSource.available():
		print("ropes preview: the GDExtension is not built (game/native/build.sh)")
		quit(1)
		return
	var want := OS.get_cmdline_user_args()
	if not want.is_empty():
		_tag = want[0]
		want = want.slice(1)
	var names := []
	for spec in SHOTS:
		if not want.is_empty() and not want.has(spec["name"]):
			continue
		_spec = spec
		_frames = {}
		for k in (spec["times"] as Array).size():
			_frames[int(round(float(spec["times"][k]) * Ropes.FPS))] = k
		var legs: Array = []
		var probe := CoreSimSource.new()
		probe.settings = {"wind_speed": 12.0 * Ropes.KNOT, "wind_from": 0.0, "shift_preset": 0, "puffs": false,
			"seed": 11}
		probe.create()
		var info := probe.class_info(probe.add_boat(spec["cls"], 0.0, 0.0, 0.0))
		var kite := ""
		var front := ""
		for s in info.sails:
			if BoatView.is_flying(s.type) and s.type != "code_zero":
				kite = s.name
			elif s.type != "main" and not BoatView.is_flying(s.type) and front == "":
				front = s.name
		for sc in Ropes.scenarios(kite, front):
			if sc[0] == spec["sc"]:
				legs = sc[1]
		Ropes.run(spec["cls"], spec["sc"], legs, 12.0, "", _shot)
		for k in (spec["times"] as Array).size():
			names.append("%s_%d" % [spec["name"], k])
	var f := FileAccess.open(OUT.path_join(_tag).path_join("index.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(names))
	quit(0)


func _shot(bv: BoatView, sim: CoreSimSource, b: int, frame: int) -> void:
	if not _frames.has(frame):
		return
	var k: int = _frames[frame]
	var st := sim.state(b)
	_lee = 1.0 if st.awa >= 0.0 else -1.0
	var name := "%s_%d" % [_spec["name"], k]
	var notes := []
	for sp in bv.sail_parts:
		if sp.node.visible:
			notes.append("%s %s" % [sp.id, ["down", "prep", "hoisting", "up", "prep drop", "dropping"][sp.phase]])
	_dump(name, bv, st, "%s %.1f s: twa %.0f, %s" % [_spec["name"], frame / Ropes.FPS, rad_to_deg(st.twa),
		", ".join(notes)])


func _dump(name: String, bv: BoatView, st: SimSource.BoatState, note: String) -> void:
	var dir := OUT.path_join(_tag).path_join(name)
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
			var rope := bv.sheets != null and mi == bv.sheets.node
			if rope:
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
			# the sheets drawn ROPE_HI m fatter so they read at this size (their lines are the game's)
			var hi := ROPE_HI * bv.info.loa / 7.2 if rope else 0.0
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
			col = Color(minf(col.r, 0.8), minf(col.g, 0.8), minf(col.b, 0.8))
			if rope:  # the sheets in a strong colour so they read against the deck and the sails
				col = Color(0.75, 0.2, 0.05) if si == mi.mesh.get_surface_count() - 1 else Color(0.05, 0.25, 0.75)
			var nm := "m%d" % meshes.size()
			FileAccess.open(dir.path_join(nm + "_v.bin"), FileAccess.WRITE).store_buffer(wp.to_byte_array())
			FileAccess.open(dir.path_join(nm + "_i.bin"), FileAccess.WRITE).store_buffer(ind.to_byte_array())
			var entry := {"name": nm, "node": String(mi.name), "sail": is_sail, "albedo": [col.r, col.g, col.b]}
			meshes.append(entry)
	var o := bv.transform.origin
	var bow := Frames.compass_dir(st.psi)
	var port := Vector3(bow.z, 0.0, -bow.x)
	var lee := port * _lee
	var kk := bv.info.loa / 7.2
	var e: Array = _spec["eye"]
	var tg: Array = _spec["target"]
	var eye := o + (lee * float(e[0]) + Vector3.UP * float(e[1]) + bow * float(e[2])) * kk
	var target := o + (lee * float(tg[0]) + Vector3.UP * float(tg[1]) + bow * float(tg[2])) * kk
	var scene := {"meshes": meshes, "eye": [eye.x, eye.y, eye.z], "target": [target.x, target.y, target.z],
		"note": note, "sun": "side"}
	FileAccess.open(dir.path_join("scene.json"), FileAccess.WRITE).store_string(JSON.stringify(scene, "  "))


static func _chain(n: Node, top: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var x := n
	while x != null and x != top:
		if x is Node3D:
			t = (x as Node3D).transform * t
		x = x.get_parent()
	return t


static func _visible_chain(n: Node, top: Node) -> bool:
	var x := n
	while x != null and x != top:
		if x is Node3D and not (x as Node3D).visible:
			return false
		x = x.get_parent()
	return true
