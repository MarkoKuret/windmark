extends SceneTree
## Offline preview of the venue land and the course, step 1 (headless): runs scenes/sail_test.tscn on the core
## (free sailing near the island, or race mode through the start) for each shot, puts the camera where the shot
## wants it and writes what tests/course_preview.py needs to render it: the water, wake and sky uniforms (as
## tests/water_preview_dump.gd does), and the triangles of the land, trees, quay, rock, marks, committee and
## mark boats, flags, guides and the boat, with their vertex colours or albedo, to generated/course_preview/<shot>.
##   godot --headless --path game -s res://tests/course_preview_dump.gd [-- shot ...]

const OUT := "res://generated/course_preview"
const DT := 0.1

## name, race mode, start (x, y, twa deg), seconds to run, camera: ["chase"] or ["look", eye ENU, at ENU, fov],
## optional: {"fleet": boats, "seed": world seed, "sky": weather preset}. The haze shots (water_render.md §4.5) see
## the same fleet from 1, 3 and 10 km downwind at one image scale (["from_boat", distance, eye height, fov]).
const HAZE := {"fleet": 8, "seed": 84}
const GARDA := {"fleet": 8, "seed": 84, "venue": "garda", "course": "garda/garda_wl", "wind": 195.0}
const SHOTS := [
	["island_chase", false, [140.0, 1800.0, 50.0], 20.0, ["chase", 1.35, 0.14, 0.4]],
	["island_wide", false, [600.0, 1300.0, 45.0], 4.0, ["look", Vector3(760, 1500, 38), Vector3(60, 2380, 20), 45.0]],
	["pier_rock", false, [-400.0, 1500.0, 45.0], 4.0, ["look", Vector3(210, 1600, 6), Vector3(210, 1970, 2), 45.0]],
	["start_line", true, [], 185.0, ["look_boat", Vector3(-150, -330, 7), 0.0, 50.0]],
	["committee", true, [], 150.0, ["look_mark", "rc", Vector3(-30, -24, 5), 50.0]],
	["committee_close", true, [], 150.0, ["look_mark", "rc", Vector3(16, 12, 5), 50.0]],
	["mark_boat", true, [], 150.0, ["look_mark", "fb", Vector3(-9, -7, 3), 50.0]],
	["windward", true, [], 330.0, ["look_mark", "w", Vector3(-50, -170, 45), 50.0]],
	["race_aerial", true, [], 262.0, ["aerial", 700.0]],
	["haze_chase", true, [], 262.0, ["chase", 1.35, 0.14, 0.4], HAZE],
	["haze_1km", true, [], 262.0, ["from_boat", 1000.0, 8.0, 20.0], HAZE],
	["haze_3km", true, [], 262.0, ["from_boat", 3000.0, 15.0, 6.7], HAZE],
	["haze_10km", true, [], 262.0, ["from_boat", 10000.0, 30.0, 2.0], HAZE],
	["haze_3km_clear", true, [], 262.0, ["from_boat", 3000.0, 15.0, 6.7], {"fleet": 8, "seed": 84, "sky": "clear"}],
	["haze_3km_hazy", true, [], 262.0, ["from_boat", 3000.0, 15.0, 6.7], {"fleet": 8, "seed": 84, "sky": "hazy"}],
	# the fleet seen from behind and above the own boat (the boat pick frames of tests/race_hud_preview_dump.gd)
	["fleet", true, [], 262.0, ["chase", 3.2, 0.3, 0.5], HAZE],
	# Lake Garda (WM-106): the drawn terrain from the race cameras and from the water
	["garda_chase", true, [], 185.0, ["chase", 1.35, 0.14, 0.4], GARDA],
	["garda_start", true, [], 185.0, ["look_boat", Vector3(300, -400, 7), 0.0, 50.0], GARDA],
	["garda_north", true, [], 20.0, ["look", Vector3(100, -1800, 8), Vector3(0, 2600, 250), 55.0], GARDA],
	["garda_west", true, [], 20.0, ["look", Vector3(900, -300, 8), Vector3(-1800, 300, 350), 55.0], GARDA],
	["garda_shore", true, [], 20.0, ["look", Vector3(-1100, 600, 5), Vector3(-1500, 1100, 40), 55.0], GARDA],
	["garda_south", true, [], 20.0, ["look", Vector3(0, 1500, 12), Vector3(-2500, -15000, 150), 55.0], GARDA],
	["garda_aerial", true, [], 262.0, ["aerial", 700.0], GARDA],
]

var _shot := -1
var _only: PackedStringArray = OS.get_cmdline_user_args()
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
	if not _only.is_empty() and not _only.has(s[0]):
		_next()
		return
	_scene = (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	_scene.auto_process = false
	_scene.sim_kind = _scene.SimKind.CORE
	_scene.race_mode = s[1]
	_scene.core_settings = {"free_sailing_s": 10.0}
	_scene.puffs = true
	var opts: Dictionary = s[5] if s.size() > 5 else {}
	_scene.fleet_size = opts.get("fleet", _scene.fleet_size)
	_scene.venue = opts.get("venue", _scene.venue)
	_scene.course = opts.get("course", _scene.course)
	_scene.wind_from_deg = opts.get("wind", _scene.wind_from_deg)
	_scene.world_seed = opts.get("seed", _scene.world_seed)
	if not s[2].is_empty():
		_scene.start_x = s[2][0]
		_scene.start_y = s[2][1]
		_scene.start_twa_deg = s[2][2]
	# headless meshes do not keep the native wakes' in-place updates: dump the references' meshes (the same
	# geometry, tests/wakes_native_test.gd)
	(_scene.get_node("Wakes") as SeaWakes).use_reference = true
	root.add_child(_scene)
	if opts.has("sky"):
		_scene.sky.set_preset_name(opts["sky"])
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
		"from_boat":
			# downwind of the own boat (from the windward mark toward the start line), looking back at it
			var cv: CourseView = _scene.course_view
			var w := Frames.scene_to_enu(cv.mark_node("w").global_position)
			var mid := (Frames.scene_to_enu(cv.mark_node("rc").global_position)
					+ Frames.scene_to_enu(cv.mark_node("pin").global_position)) * 0.5
			var down := Vector3(mid.x - w.x, mid.y - w.y, 0.0).normalized()
			var p: SimSource.RenderPose = _scene.target.pose
			var boat := Vector3(p.pos_x, p.pos_y, 4.0)
			_look(cam, boat + down * c[1] + Vector3(0, 0, c[2]), boat, c[3])
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
		TYPE_PACKED_FLOAT32_ARRAY:
			return Array(x)
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


## Every visible MeshInstance3D under `node`: kind "land" (land shader), "boat" (committee and mark boats),
## "unshaded", "prop" (vertex colours) or "albedo" (imported boat materials).
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
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader.resource_path.ends_with("course_boat.gdshader"):
				# the boat-frame positions and normals the shared boat surface reads
				info["kind"] = "boat"
				_save(dir, name + "_opos.bin", (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array())
				_save(dir, name + "_onormal.bin", (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).to_byte_array())
			elif mat is ShaderMaterial:
				info["kind"] = "land"
				var br = (mat as ShaderMaterial).get_shader_parameter("bare_rock")
				info["bare_rock"] = 1.0 if br == null else float(br)
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
		"fog": {"density": env.fog_density, "color": _v(env.fog_light_color.srgb_to_linear()), "mode": env.fog_mode,
			"begin": env.fog_depth_begin, "end": env.fog_depth_end, "curve": env.fog_depth_curve,
			"sun_scatter": env.fog_sun_scatter},
		"tonemap": {"mode": env.tonemap_mode, "exposure": env.tonemap_exposure, "white": env.tonemap_white},
		"glow": {"enabled": env.glow_enabled, "threshold": env.glow_hdr_threshold, "scale": env.glow_hdr_scale,
			"intensity": env.glow_intensity},
		"ambient_energy": env.ambient_light_energy,
		"hud": "%s\n%s" % [_scene.hud.text_of("clock"), _scene.hud.text_of("next")] if _scene.hud.race.active else "",
	}
	var surf: MeshInstance3D = sea.get_node("Surface")
	data["grid"] = _write_arrays(dir, "grid", surf.mesh.surface_get_arrays(0), Transform3D.IDENTITY)
	var g := sea.model.exposure
	data["exposure"] = {} if g.is_empty() else {"nx": g["nx"], "ny": g["ny"]}
	if not g.is_empty():
		_save(dir, "expo.bin", (g["e"] as PackedFloat32Array).to_byte_array())
	var lu := sea.land_upload()
	data["land"] = {} if lu.is_empty() else {"nx": sea.model.wind_field["nx"], "ny": sea.model.wind_field["ny"], "k0": lu[0]}
	if not lu.is_empty():
		_save(dir, "land.bin", lu[2])
	SeaTextures.detail_image().save_png(dir.path_join("detail.png"))
	SeaTextures.foam_image().save_png(dir.path_join("foam.png"))
	SeaTextures.caps_image().save_png(dir.path_join("caps.png"))
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
	for v in _scene.boat_views:
		_meshes(dir, v, meshes)
	data["meshes"] = meshes
	var f := FileAccess.open(dir.path_join("scene.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))
	print("  dumped ", name, " (", meshes.size(), " meshes)")
