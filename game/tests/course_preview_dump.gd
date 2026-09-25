extends SceneTree
## Offline preview of the venue land and the course, step 1 (headless): runs scenes/sail_test.tscn on the core
## (free sailing near the island, or race mode through the start) for each shot, puts the camera where the shot
## wants it and writes what tests/course_preview.py needs to render it: the water, wake and sky uniforms (as
## tests/water_preview_dump.gd does), and the triangles of the land, trees, quay, rock, marks, committee and
## mark boats, flags, guides and the boat, with their vertex colours or albedo, to generated/course_preview/<shot>.
##   godot --headless --path game -s res://tests/course_preview_dump.gd

const OUT := "res://generated/course_preview"
const DT := 0.1

## name, race mode, start (x, y, twa deg), seconds to run, camera: ["chase"] or ["look", eye ENU, at ENU, fov]
const SHOTS := [
	["island_chase", false, [140.0, 1800.0, 50.0], 20.0, ["chase", 1.35, 0.14, 0.4]],
	["island_wide", false, [600.0, 1300.0, 45.0], 4.0, ["look", Vector3(760, 1500, 38), Vector3(60, 2380, 20), 45.0]],
	["pier_rock", false, [230.0, 1880.0, 45.0], 4.0, ["look", Vector3(250, 1860, 9), Vector3(160, 1990, 3), 55.0]],
	["start_line", true, [], 185.0, ["look_boat", Vector3(-150, -330, 7), 0.0, 50.0]],
	["committee", true, [], 150.0, ["look_mark", "rc", Vector3(-30, -24, 5), 50.0]],
	["windward", true, [], 330.0, ["look_mark", "w", Vector3(-50, -170, 45), 50.0]],
	["race_aerial", true, [], 262.0, ["aerial", 700.0]],
]

var _shot := -1
var _scene: Node
var _t := 0.0


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_next()


func _next() -> void:
	_shot += 1
	if _shot >= SHOTS.size():
		print("course preview dump: %d shots in %s" % [SHOTS.size(), ProjectSettings.globalize_path(OUT)])
		quit(0)
		return
	var s: Array = SHOTS[_shot]
	_scene = (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	_scene.auto_process = false
	_scene.sim_kind = _scene.SimKind.CORE
	_scene.race_mode = s[1]
	_scene.core_settings = {"free_sailing_s": 10.0}
	_scene.puffs = true
	if not s[2].is_empty():
		_scene.start_x = s[2][0]
		_scene.start_y = s[2][1]
		_scene.start_twa_deg = s[2][2]
	root.add_child(_scene)
	_scene.scripted_input = RawInput.new()
	_t = 0.0


func _process(_delta: float) -> bool:
	if _scene == null or not _scene.is_inside_tree():
		return false
	var s: Array = SHOTS[_shot]
	for i in 10:
		if _scene.race_mode:
			CoursePilot.steer(_scene)
		_scene.step_frame(DT)
		_t += DT
		if _t >= s[3]:
			break
	if _t >= s[3]:
		_place_camera(s[4])
		_dump(s[0])
		_scene.queue_free()
		_scene = null
		_next()
	return false


func _place_camera(c: Array) -> void:
	var cam: Camera3D = _scene.rig.camera
	var sea: Sea = _scene.sea
	match c[0]:
		"chase":
			var ch: ChaseCamera = _scene.rig.chase
			ch.R = _scene.target.r0() * c[1]
			ch.el = c[2]
			ch.az = c[3]
			for i in 30:
				_scene.step_frame(1.0 / 60.0)
		"aerial":
			_scene.rig.select_mode(CameraRig.Mode.AERIAL, _scene.target)
			_scene.rig.aerial.H = c[1]
			_scene.rig.aerial.framing = AerialCamera.Framing.BOAT_AND_MARK
			for i in 30:
				_scene.step_frame(1.0 / 60.0)
		"look":
			_look(cam, c[1], c[2], c[3])
		"look_boat":
			var p: SimSource.RenderPose = _scene.target.pose
			_look(cam, c[1], Vector3(p.pos_x, p.pos_y, 1.5), c[3])
		"look_mark":
			var n: Node3D = _scene.course_view.mark_node(c[1])
			var at := Frames.scene_to_enu(n.global_position)
			_look(cam, at + c[2], at + Vector3(0, 0, 2.0), c[3])
	sea.update_frame(cam.global_position, cam)
	if _scene.course_view:
		_scene.course_view.frame(0.0, cam.global_position, _scene.target.pose)


func _look(cam: Camera3D, eye: Vector3, at: Vector3, fov: float) -> void:
	var e := Frames.enu_to_scene(eye.x, eye.y, eye.z)
	cam.global_transform = Transform3D(Basis.IDENTITY, e).looking_at(Frames.enu_to_scene(at.x, at.y, at.z), Vector3.UP)
	cam.fov = fov
	cam.near = 0.3


# ---- writing (as water_preview_dump.gd) ----------------------------------------------------------------------

func _v(x) -> Variant:
	match typeof(x):
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [x.x, x.y]
		TYPE_VECTOR3:
			return [x.x, x.y, x.z]
		TYPE_VECTOR4:
			return [x.x, x.y, x.z, x.w]
		TYPE_COLOR:
			return [x.r, x.g, x.b, x.a]
		TYPE_PACKED_VECTOR4_ARRAY:
			var out := []
			for e in x:
				out.append([e.x, e.y, e.z, e.w])
			return out
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
			return x
	return null


func _uniforms(mat: ShaderMaterial) -> Dictionary:
	var out := {}
	for u in mat.shader.get_shader_uniform_list():
		var v = _v(mat.get_shader_parameter(u["name"]))
		if v != null:
			out[u["name"]] = v
	return out


func _save(dir: String, file: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(dir.path_join(file), FileAccess.WRITE)
	f.store_buffer(bytes)


func _write_arrays(dir: String, name: String, arrays: Array, xform: Transform3D) -> Dictionary:
	var info := {}
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var world := PackedVector3Array()
	world.resize(verts.size())
	for i in verts.size():
		world[i] = xform * verts[i]
	_save(dir, name + "_pos.bin", world.to_byte_array())
	info["count"] = verts.size()
	for k in [[Mesh.ARRAY_TEX_UV, "uv"], [Mesh.ARRAY_COLOR, "color"], [Mesh.ARRAY_NORMAL, "normal"]]:
		var a = arrays[k[0]]
		if a == null or a.size() == 0:
			continue
		if k[1] == "normal":
			var n := PackedVector3Array()
			n.resize(a.size())
			for i in a.size():
				n[i] = (xform.basis * a[i]).normalized()
			a = n
		_save(dir, "%s_%s.bin" % [name, k[1]], a.to_byte_array())
		info[k[1]] = true
	var idx = arrays[Mesh.ARRAY_INDEX]
	if idx != null and idx.size() > 0:
		_save(dir, name + "_idx.bin", PackedInt32Array(idx).to_byte_array())
		info["indices"] = idx.size()
	return info


## Every visible MeshInstance3D under `node`: kind "land" (land shader), "unshaded", "prop" (vertex colours)
## or "albedo" (imported boat materials).
func _meshes(dir: String, node: Node, out: Array) -> void:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and not (n as Node3D).is_visible_in_tree():
			continue
		stack.append_array(n.get_children())
		if not (n is MeshInstance3D) or n.mesh == null:
			continue
		for si in n.mesh.get_surface_count():
			var mat: Material = n.material_override if n.material_override else n.get_active_material(si)
			var arrays: Array = n.mesh.surface_get_arrays(si)
			if arrays[Mesh.ARRAY_INDEX] == null or arrays[Mesh.ARRAY_NORMAL] == null:
				continue
			var name := "mesh%d" % out.size()
			var info := _write_arrays(dir, name, arrays, n.global_transform)
			info["name"] = name
			info["kind"] = "albedo"
			info["albedo"] = [0.6, 0.6, 0.6, 1.0]
			info["roughness"] = 0.6
			if mat is ShaderMaterial:
				info["kind"] = "land"
			elif mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				info["roughness"] = bm.roughness
				if bm.vertex_color_use_as_albedo and info.has("color"):
					info["kind"] = "unshaded" if bm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED else "prop"
				info["albedo"] = _v(bm.albedo_color.srgb_to_linear())
			out.append(info)


func _dump(name: String) -> void:
	var dir := ProjectSettings.globalize_path(OUT).path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	var sea: Sea = _scene.sea
	var cam: Camera3D = _scene.rig.camera
	var sky: SkyRig = _scene.sky
	var env := sky.environment()
	var data := {
		"shot": name, "tier": sea.get_tier()["name"], "detail_layers": {"L": 2, "M": 3, "H": 4}[sea.get_tier()["name"]],
		"render_time_ms": sea.render_time_ms,
		"camera": {
			"origin": _v(cam.global_position), "basis": [_v(cam.global_basis.x), _v(cam.global_basis.y), _v(cam.global_basis.z)],
			"fov": cam.fov, "near": cam.near, "far": cam.far,
		},
		"sea_position": _v(sea.global_position),
		"water": _uniforms(sea.material),
		"sky": _uniforms(env.sky.sky_material),
		"fog": {"density": env.fog_density, "color": _v(env.fog_light_color.srgb_to_linear())},
		"tonemap": {"mode": env.tonemap_mode, "exposure": env.tonemap_exposure, "white": env.tonemap_white},
		"ambient_energy": env.ambient_light_energy,
		"hud": _scene._race_label.text if _scene._race_label.visible else "",
	}
	var surf: MeshInstance3D = sea.get_node("Surface")
	data["grid"] = _write_arrays(dir, "grid", surf.mesh.surface_get_arrays(0), Transform3D.IDENTITY)
	var g := sea.model.exposure
	data["exposure"] = {} if g.is_empty() else {"nx": g["nx"], "ny": g["ny"]}
	if not g.is_empty():
		_save(dir, "expo.bin", (g["e"] as PackedFloat32Array).to_byte_array())
	SeaTextures.detail_image().save_png(dir.path_join("detail.png"))
	SeaTextures.foam_image().save_png(dir.path_join("foam.png"))
	var wakes: SeaWakes = _scene.wakes
	var ribbons := []
	var wake_uniforms := {}
	for mi in wakes.get_children():
		if mi is MeshInstance3D and mi.mesh is ArrayMesh and mi.mesh.get_surface_count() > 0 and mi.material_override is ShaderMaterial:
			var n := "wake%d" % ribbons.size()
			var info := _write_arrays(dir, n, mi.mesh.surface_get_arrays(0), Transform3D.IDENTITY)
			if not info.has("uv"):
				continue
			ribbons.append(info)
			ribbons[-1]["name"] = n
			wake_uniforms = _uniforms(mi.material_override)
	data["wakes"] = ribbons
	data["wake_uniforms"] = wake_uniforms
	var meshes := []
	_meshes(dir, _scene.venue_view, meshes)
	if _scene.course_view:
		_meshes(dir, _scene.course_view, meshes)
	_meshes(dir, _scene.boat_view, meshes)
	data["meshes"] = meshes
	var f := FileAccess.open(dir.path_join("scene.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))
	print("  dumped ", name, " (", meshes.size(), " meshes)")
