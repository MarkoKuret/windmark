extends SceneTree
## Offline preview of the liveries, step 1 (headless, no window): sails a fleet on the core, paints every boat with
## BoatLivery as the sail scene does (the fleet rule from a seed, or a chosen livery for the close-ups), bends the
## sails with BoatView and dumps every mesh with its livery uniforms and each boat's text texture to
## generated/livery_preview/<shot>/. Step 2, tests/livery_preview.py, renders them offscreen with the same
## hull_livery, sail_livery, livery_text and sail_cloth shader files.
##   godot --headless --path game -s res://tests/livery_preview_dump.gd [-- shot ...]

## `-- procedural`: the procedural fallback (no baked textures), dumped to generated/livery_preview_procedural
var OUT := "res://generated/livery_preview"
const KNOT := 1852.0 / 3600.0
const SEED := 2026

## n boats of `cls` in a line abreast square to the wind, `gap` LOAs apart with a stagger, sailing at `twa` (deg,
## negative: port tack; kite:
## the spinnaker hoisted); `liveries`: ids for the boats in order, else the fleet rule from SEED. Camera "boat":
## eye and target in boat 0's heading frame (port, up, fwd), m, level with the sea; "line": eye from the starboard
## (east) end of the line ("mid": from the fleet's middle) and target from the fleet's middle, in world east,
## north, up, m.
var SHOTS := [
	{"name": "start_wm7", "cls": "wm7", "n": 10, "twa": 42.0, "gap": 1.9, "t": 25.0,
		"cam": {"mode": "mid", "eye": [80.0, 42.0, 3.5], "at": [30.0, 0.0, 3.2], "fov": 38.0}},
	{"name": "start_wm12", "cls": "wm12", "n": 9, "twa": 40.0, "gap": 1.8, "t": 25.0,
		"cam": {"mode": "mid", "eye": [120.0, 62.0, 5.0], "at": [45.0, 0.0, 5.0], "fov": 38.0}},
	{"name": "kites_wm7", "cls": "wm7", "n": 8, "twa": 135.0, "gap": 2.2, "t": 40.0, "kite": true,
		"cam": {"mode": "mid", "eye": [10.0, -62.0, 4.0], "at": [-4.0, 0.0, 4.5], "fov": 44.0}},
	{"name": "kites_wm12", "cls": "wm12", "n": 8, "twa": 120.0, "gap": 2.2, "t": 40.0, "kite": true,
		"cam": {"mode": "mid", "eye": [14.0, -95.0, 6.0], "at": [-6.0, 0.0, 7.0], "fov": 44.0}},
	{"name": "hull_wm7_stbd", "cls": "wm7", "n": 1, "twa": 42.0, "t": 20.0, "liveries": ["northern_star"],
		"cam": {"mode": "boat", "eye": [-6.0, 1.1, 0.8], "at": [0.0, 0.35, 0.3], "fov": 50.0}},
	{"name": "hull_wm7_port", "cls": "wm7", "n": 1, "twa": -42.0, "t": 20.0, "liveries": ["sirocco"],
		"cam": {"mode": "boat", "eye": [6.5, 1.4, -0.5], "at": [0.0, 0.5, 0.0], "fov": 50.0}},
	{"name": "hull_wm12_stbd", "cls": "wm12", "n": 1, "twa": 40.0, "t": 20.0, "liveries": ["nightjar"],
		"cam": {"mode": "boat", "eye": [-10.0, 1.6, 1.0], "at": [0.0, 0.6, 0.0], "fov": 50.0}},
	{"name": "bow_wm12_waterline", "cls": "wm12", "n": 1, "twa": 40.0, "t": 20.0, "liveries": ["nightjar"],
		"cam": {"mode": "boat", "eye": [-3.2, 0.7, 4.6], "at": [0.0, 0.25, 3.6], "fov": 45.0}},
	{"name": "stern_wm7", "cls": "wm7", "n": 1, "twa": 42.0, "t": 20.0, "liveries": ["kestrel"],
		"cam": {"mode": "boat", "eye": [-4.2, 1.6, -6.0], "at": [0.0, 0.4, -2.2], "fov": 50.0}},
	{"name": "stern_wm12", "cls": "wm12", "n": 1, "twa": 40.0, "t": 20.0, "liveries": ["seraphine"],
		"cam": {"mode": "boat", "eye": [-6.5, 2.2, -9.5], "at": [0.0, 0.8, -3.5], "fov": 50.0}},
	{"name": "keel_wm12_dry", "cls": "wm12", "n": 1, "twa": 40.0, "t": 20.0, "liveries": ["seraphine"], "sea": false,
		"cam": {"mode": "boat", "eye": [-5.5, -1.4, 3.2], "at": [0.0, -1.4, 0.4], "fov": 50.0}},
	{"name": "main_wm7_stbd", "cls": "wm7", "n": 1, "twa": 42.0, "t": 20.0, "liveries": ["kestrel"],
		"cam": {"mode": "boat", "eye": [-13.0, 6.0, -3.0], "at": [0.0, 6.0, -0.5], "fov": 50.0}},
	{"name": "main_wm7_port", "cls": "wm7", "n": 1, "twa": -42.0, "t": 20.0, "liveries": ["kestrel"],
		"cam": {"mode": "boat", "eye": [14.0, 6.0, -3.0], "at": [0.0, 6.0, -0.5], "fov": 50.0}},
	{"name": "main_wm12_stbd", "cls": "wm12", "n": 1, "twa": 40.0, "t": 20.0, "liveries": ["nightjar"],
		"cam": {"mode": "boat", "eye": [-20.0, 9.0, -4.0], "at": [0.0, 9.0, -1.0], "fov": 50.0}},
	{"name": "main_wm7_close", "cls": "wm7", "n": 1, "twa": 42.0, "t": 20.0, "liveries": ["bora"],
		"cam": {"mode": "boat", "eye": [-4.5, 3.4, -2.6], "at": [-0.6, 3.2, -1.2], "fov": 50.0}},
	{"name": "jib_wm12_laminate", "cls": "wm12", "n": 1, "twa": 40.0, "t": 20.0, "liveries": ["nightjar"],
		"cam": {"mode": "boat", "eye": [-9.0, 4.0, 7.5], "at": [0.0, 4.5, 2.5], "fov": 50.0}},
	{"name": "kite_wm7", "cls": "wm7", "n": 1, "twa": 135.0, "t": 40.0, "kite": true, "liveries": ["kestrel"],
		"cam": {"mode": "boat", "eye": [-6.0, 4.0, 13.0], "at": [-1.5, 4.5, 3.5], "fov": 55.0}},
	{"name": "main_wm7_backlit", "cls": "wm7", "n": 1, "twa": 42.0, "t": 20.0, "liveries": ["swift"],
		"cam": {"mode": "boat", "eye": [13.0, 5.0, -3.0], "at": [0.0, 6.0, -0.5], "fov": 50.0, "sun": "back"}},
]


func _init() -> void:
	_main()


func _main() -> void:
	await process_frame
	if not CoreSimSource.available():
		print("livery preview: the GDExtension is not built (game/native/build.sh)")
		quit(1)
		return
	var want := OS.get_cmdline_user_args()
	if want.has("procedural"):
		want.erase("procedural")
		BakedLivery.enabled = false
		OUT = "res://generated/livery_preview_procedural"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var names := []
	for spec in SHOTS:
		if want.is_empty() or want.has(spec["name"]):
			await _shot(spec)
		if FileAccess.file_exists(OUT.path_join(spec["name"]).path_join("scene.json")):
			names.append(spec["name"])
	FileAccess.open(OUT.path_join("index.json"), FileAccess.WRITE).store_string(JSON.stringify(names))
	quit(0)


func _shot(spec: Dictionary) -> void:
	var sim := CoreSimSource.new()
	sim.settings = {"wind_speed": 12.0 * KNOT, "wind_from": 0.0, "shift_preset": 0, "puffs": false, "seed": 11}
	if not sim.create():
		print("create failed: ", sim.last_error())
		return
	var n: int = spec["n"]
	var twa := deg_to_rad(float(spec["twa"]))
	var psi := Frames.wrap_2pi(-twa)
	var boats := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in n:
		var loa := 7.2 if spec["cls"] == "wm7" else 12.0
		var x := (k - 0.5 * (n - 1)) * float(spec.get("gap", 2.0)) * loa
		var y := rng.randf_range(-0.6, 0.6) * loa
		boats.append(sim.add_boat(spec["cls"], x, y, psi))
	var info := sim.class_info(boats[0])
	var list := Livery.load_class(spec["cls"])
	var lvs: Array = []
	if spec.has("liveries"):
		for id in spec["liveries"]:
			for l in list:
				if l.id == id:
					lvs.append(l)
	else:
		var entries := [{"human": true, "choice": ""}]
		for k in n - 1:
			entries.append({"human": false})
		lvs = Livery.assign(list, entries, SEED)
	var views := []
	var holder := Node3D.new()
	root.add_child(holder)
	for k in n:
		var bv := BoatView.create(info, info.rudder_max)
		holder.add_child(bv)
		bv.set_livery(lvs[k % lvs.size()])
		views.append(bv)
	var kite := -1
	for i in info.sails.size():
		if info.sails[i].type.begins_with("spinnaker"):
			kite = i
	var prev := []
	var cur := []
	for b in boats:
		prev.append(sim.sails(b))
		cur.append(sim.sails(b))
	var ticks := int(float(spec["t"]) / SimSource.DT)
	for t in ticks:
		for k in n:
			var b: int = boats[k]
			var s := sim.state(b)
			var f := InputFrame.new()
			f.tick = sim.tick()
			f.h_cmd = clampf(1.5 * Frames.angle_diff(s.twa, twa), -1.0, 1.0)
			f.flags = InputFrame.FLAG_AUTO_TRIM
			f.sheet_cmd = 0.5
			f.sail_req = InputFrame.hoist_req(kite) if spec.get("kite", false) and kite >= 0 and t == 0 else InputFrame.SAIL_NONE
			sim.apply_input(b, f)
		sim.step()
		for k in n:
			prev[k] = cur[k]
			cur[k] = sim.sails(boats[k])
			views[k].apply_sails(prev[k], cur[k], 1.0, SimSource.DT)
	for k in n:
		views[k].apply(sim.render_pose(boats[k], 1.0))
		views[k].apply_sails(prev[k], cur[k], 1.0, 1.0 / 60.0)
	_dump(spec, views)
	holder.queue_free()
	await process_frame


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


func _dump(spec: Dictionary, views: Array) -> void:
	var dir := OUT.path_join(spec["name"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var meshes := []
	for bi in views.size():
		var bv: BoatView = views[bi]
		var text_png := "text%d.png" % bi
		var timg := bv.livery_text.image.duplicate() as Image
		timg.clear_mipmaps()
		# the R8 coverage bytes as grey (convert() would weight R as luminance)
		timg = Image.create_from_data(timg.get_width(), timg.get_height(), false, Image.FORMAT_L8, timg.get_data())
		timg.save_png(ProjectSettings.globalize_path(dir.path_join(text_png)))
		var sail_nodes := {}
		for sp in bv.sail_parts:
			sail_nodes[sp.node] = sp
		var stack: Array = [bv]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			stack.append_array(node.get_children())
			var mi := node as MeshInstance3D
			if mi == null or mi.mesh == null or not _visible_chain(mi, bv):
				continue
			var xf := bv.transform * _chain(mi, bv)
			var local := _chain(mi, bv)
			var is_sail := sail_nodes.has(mi) and sail_nodes[mi].shape != null
			for si in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(si)
				var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				if is_sail:
					pos = sail_nodes[mi].shape.positions()
					nrm = sail_nodes[mi].shape.normals()
				var ind: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				if ind.is_empty():
					ind.resize(pos.size())
					for k in pos.size():
						ind[k] = k
				var u0: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
				var u1: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
				var mat := mi.get_active_material(si)
				# baked side or top views (keel, deck): their image coordinates in place of uv1, as the shader's vertex()
				var proj := 0
				var rect := Vector4.ZERO
				if mat is ShaderMaterial and (mat as ShaderMaterial).shader == BoatLivery.BAKED_BOAT:
					proj = int((mat as ShaderMaterial).get_shader_parameter("bk_proj"))
					var r_: Variant = (mat as ShaderMaterial).get_shader_parameter("bk_rect")
					rect = r_ if r_ is Vector4 else Vector4.ZERO
				# position, normal (world), uv0, uv1, port side (model x > 0)
				var w := PackedFloat32Array()
				w.resize(pos.size() * 11)
				var nb := xf.basis.inverse().transposed()
				for k in pos.size():
					var p := xf * pos[k]
					var q := (nb * nrm[k]).normalized() if nrm.size() == pos.size() else Vector3.UP
					var a := u0[k] if u0.size() == pos.size() else Vector2.ZERO
					var c := u1[k] if u1.size() == pos.size() else Vector2.ZERO
					if proj == 1:
						c = Vector2((pos[k].z - rect.x) / rect.z, (rect.y - pos[k].y) / rect.w)
					elif proj == 2:
						c = Vector2((pos[k].z - rect.x) / rect.z, (rect.y - pos[k].x) / rect.w)
					var o := 11 * k
					w[o] = p.x; w[o + 1] = p.y; w[o + 2] = p.z
					w[o + 3] = q.x; w[o + 4] = q.y; w[o + 5] = q.z
					w[o + 6] = a.x; w[o + 7] = a.y; w[o + 8] = c.x; w[o + 9] = c.y
					w[o + 10] = 1.0 if (local * pos[k]).x > 0.0 else 0.0
				var nm := "m%d" % meshes.size()
				FileAccess.open(dir.path_join(nm + "_v.bin"), FileAccess.WRITE).store_buffer(w.to_byte_array())
				FileAccess.open(dir.path_join(nm + "_i.bin"), FileAccess.WRITE).store_buffer(ind.to_byte_array())
				var entry := {"name": nm, "node": String(mi.name), "kind": "flat", "albedo": [0.6, 0.6, 0.6], "rough": 0.5}
				if mat is ShaderMaterial:
					var sm := mat as ShaderMaterial
					var u := _uniforms(sm)
					if sm.shader == BoatLivery.BAKED_SAIL:
						entry["kind"] = "sail_baked"
						entry["uniforms"] = u
						entry["text"] = text_png
					elif sm.shader == BoatLivery.BAKED_BOAT:
						entry["kind"] = "boat_baked"
						entry["uniforms"] = u
						entry["text"] = text_png
						entry["slot"] = sm.resource_name
					elif is_sail:
						entry["kind"] = "sail"
						entry["uniforms"] = u
						entry["text"] = text_png
					elif sm.get_shader_parameter("hl_on") == 1:
						entry["kind"] = "hull"
						entry["uniforms"] = u
						entry["text"] = text_png
					if sm.get_shader_parameter("albedo_color") is Color:
						var col: Color = (sm.get_shader_parameter("albedo_color") as Color).srgb_to_linear()
						var mean := BoatLivery.texture_mean(sm.get_shader_parameter("albedo_tex")) if not is_sail else 1.0
						entry["albedo"] = [minf(col.r * mean, 0.8), minf(col.g * mean, 0.8), minf(col.b * mean, 0.8)]
					var r: Variant = sm.get_shader_parameter("roughness")
					if r is float:
						entry["rough"] = r
					var me: Variant = sm.get_shader_parameter("metallic")
					if me is float:
						entry["metal"] = me
				meshes.append(entry)
	var cam: Dictionary = spec["cam"]
	var frame: Transform3D = (views[0] as BoatView).transform
	if cam["mode"] == "fleet" or cam["mode"] == "line":
		var c := Vector3.ZERO
		for v in views:
			c += (v as BoatView).transform.origin
		frame.origin = c / views.size()
	# the boat's heading only (no heel or pitch), level with the sea
	var fwd := frame.basis.z
	frame.basis = Basis.looking_at(-Vector3(fwd.x, 0.0, fwd.z).normalized(), Vector3.UP)
	frame.origin.y = 0.0
	var e: Array = cam["eye"]
	var at: Array = cam["at"]
	var eye := frame * Vector3(e[0], e[1], e[2])
	var target := frame * Vector3(at[0], at[1], at[2])
	if cam["mode"] == "line" or cam["mode"] == "mid":
		var east_end: Vector3 = (views[0] as BoatView).transform.origin
		var mid := Vector3.ZERO
		for v in views:
			var o: Vector3 = (v as BoatView).transform.origin
			mid += o / views.size()
			if o.x > east_end.x:
				east_end = o
		var base := east_end if cam["mode"] == "line" else mid
		eye = Vector3(base.x, 0.0, base.z) + Frames.enu_to_scene(e[0], e[1], e[2])
		target = Vector3(mid.x, 0.0, mid.z) + Frames.enu_to_scene(at[0], at[1], at[2])
	var scene := {"meshes": meshes, "eye": [eye.x, eye.y, eye.z], "target": [target.x, target.y, target.z],
		"fov": cam["fov"], "sun": cam.get("sun", "side"), "sea": spec.get("sea", true),
		"note": "%s: %s" % [spec["name"], ", ".join(views.map(func(v: BoatView) -> String: return "%s %s" % [v.livery.boat_name, v.livery.sail_number]))]}
	FileAccess.open(dir.path_join("scene.json"), FileAccess.WRITE).store_string(JSON.stringify(scene, "  "))
	print("  dumped ", spec["name"], " (", meshes.size(), " meshes)")


## A material's uniforms as JSON (vectors and arrays as lists, textures as file paths).
static func _uniforms(m: ShaderMaterial) -> Dictionary:
	var out := {}
	for u in m.shader.get_shader_uniform_list():
		var n: String = u["name"]
		var v: Variant = m.get_shader_parameter(n)
		if v is Vector2:
			out[n] = [v.x, v.y]
		elif v is Vector3:
			out[n] = [v.x, v.y, v.z]
		elif v is Vector4:
			out[n] = [v.x, v.y, v.z, v.w]
		elif v is Color:
			var l := (v as Color).srgb_to_linear()
			out[n] = [l.r, l.g, l.b, l.a]
		elif v is PackedFloat32Array or v is Array:
			out[n] = Array(v)
		elif v is PackedVector4Array:
			out[n] = Array(v).map(func(q: Vector4) -> Array: return [q.x, q.y, q.z, q.w])
		elif v is Texture2D:
			out[n] = ProjectSettings.globalize_path((v as Texture2D).resource_path.get_slice("::", 0))
		elif v is float or v is int or v is bool:
			out[n] = v
	return out
