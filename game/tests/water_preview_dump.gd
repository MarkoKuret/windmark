extends SceneTree
## Offline preview, step 1 (headless): runs scenes/water_test.tscn for a few seconds of render time per shot and
## writes everything the water, wake and sky shaders receive (uniforms, grid and ribbon meshes, textures, camera,
## sun, fog) plus the boat triangles to generated/water_preview/<shot>/. Step 2, tests/water_preview.py,
## renders them with the same shader functions (sea_common, sky_common, wake_common) on an offscreen GL context.
##   godot --headless --path game -s res://tests/water_preview_dump.gd [-- --sky=late] [shot ...]
##   godot --headless --path game -s res://tests/water_preview_dump.gd -- --time=08:00 --conditions=fair --tag=d0800 bay20_chase_M
## `--sky=<name>` lights the shots with an old preset name (SkyRig.set_preset_name) and names them `<name>_<shot>`;
## `--time=HH:MM` and `--conditions=` set the daylight (water_render.md §4.5) and `--tag=` names them `<tag>_<shot>`;
## with shot names after `--`, only those (or the shots starting with them) are dumped. Each shot's folder also gets
## its colour grade as a LUT strip (lut.png) and the vignette constants (look.json) for tests/daylight_preview.py.

const OUT := "res://generated/water_preview"
const FRAMES := 260
const DT_MS := 1000.0 / 60.0

## name, env mode, scenario or wind (kn), camera mode, tier, and optionally {puffs: placeholder puffs on,
## seq: dump that many frames step_ms apart (<name>_00, _01, ...), light: after the first frame only the uniforms
## (scene.json, the meshes are the first frame's), speed: the test boat's speed (0: it and the camera stay put)}
const SHOTS := [
	["bay20_chase_M", SeaEnvSource.Mode.CORE_SAMPLES, "practice_waters_20kn", 0, SeaQuality.Tier.M],
	["bay20_aerial_M", SeaEnvSource.Mode.CORE_SAMPLES, "practice_waters_20kn", 1, SeaQuality.Tier.M],
	["bay20_overview_M", SeaEnvSource.Mode.CORE_SAMPLES, "practice_waters_20kn", 2, SeaQuality.Tier.M],
	["bay20_sun_M", SeaEnvSource.Mode.CORE_SAMPLES, "practice_waters_20kn", 3, SeaQuality.Tier.M],
	["bay10_chase_M", SeaEnvSource.Mode.CORE_SAMPLES, "practice_waters_10kn", 0, SeaQuality.Tier.M],
	["calm_chase_M", SeaEnvSource.Mode.PLACEHOLDER, 2.0, 0, SeaQuality.Tier.M],
	["bay20_chase_L", SeaEnvSource.Mode.CORE_SAMPLES, "practice_waters_20kn", 0, SeaQuality.Tier.L],
	["bay20_bow_M", SeaEnvSource.Mode.CORE_SAMPLES, "practice_waters_20kn", 4, SeaQuality.Tier.M],
	["calm_bow_M", SeaEnvSource.Mode.PLACEHOLDER, 2.0, 4, SeaQuality.Tier.M],
	# whitecaps (water_render.md §4.4) at 12, 18 and 24 kn, and a time sequence at 20 kn from a still camera
	["whitecaps_12kn_chase", SeaEnvSource.Mode.PLACEHOLDER, 12.0, 0, SeaQuality.Tier.M, {"puffs": true}],
	["whitecaps_18kn_chase", SeaEnvSource.Mode.PLACEHOLDER, 18.0, 0, SeaQuality.Tier.M, {"puffs": true}],
	["whitecaps_24kn_chase", SeaEnvSource.Mode.PLACEHOLDER, 24.0, 0, SeaQuality.Tier.M, {"puffs": true}],
	["whitecaps_20kn_seq", SeaEnvSource.Mode.PLACEHOLDER, 20.0, 0, SeaQuality.Tier.M,
			{"puffs": true, "seq": 6, "step_ms": 500.0, "speed": 0.0}],
	["whitecaps_20kn_60s", SeaEnvSource.Mode.PLACEHOLDER, 20.0, 0, SeaQuality.Tier.M,
			{"puffs": true, "seq": 120, "step_ms": 500.0, "speed": 0.0, "light": true}],
]

var _shot := -1
var _frames := 0
var _scene: Node
var _sky := ""
var _time := -1.0
var _conditions := ""
var _tag := ""
var _only: PackedStringArray = []
var _seq := 0
var _dumped := 0


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sky="):
			_sky = a.trim_prefix("--sky=")
		elif a.begins_with("--time="):
			_time = Daylight.parse_hour(a.trim_prefix("--time="))
		elif a.begins_with("--conditions="):
			_conditions = a.trim_prefix("--conditions=")
		elif a.begins_with("--tag="):
			_tag = a.trim_prefix("--tag=")
		else:
			_only.append(a)
	_next()


func _name(s: Array) -> String:
	if _tag != "":
		return "%s_%s" % [_tag, s[0]]
	return s[0] if _sky == "" else "%s_%s" % [_sky, s[0]]


func _wanted(name: String) -> bool:
	if _only.is_empty():
		return true
	for o in _only:
		if name.begins_with(o):
			return true
	return false


func _opt(key: String, default: Variant) -> Variant:
	var s: Array = SHOTS[_shot]
	return s[5].get(key, default) if s.size() > 5 else default


func _next() -> void:
	_shot += 1
	while _shot < SHOTS.size() and not _wanted(SHOTS[_shot][0]):
		_shot += 1
	if _shot >= SHOTS.size():
		print("water preview dump: %d shots in %s" % [_dumped, ProjectSettings.globalize_path(OUT)])
		quit(0)
		return
	_seq = 0
	var s: Array = SHOTS[_shot]
	_scene = (load("res://scenes/water_test.tscn") as PackedScene).instantiate()
	var rig: SkyRig = _scene.get_node("SkyDay")
	if _sky != "":
		rig.set_preset_name(_sky)
	if _time >= 0.0 or _conditions != "":
		rig.set_light(_time if _time >= 0.0 else rig.hour, _conditions if _conditions != "" else rig.conditions)
	var src: SeaEnvSource = _scene.get_node("EnvSource")
	src.mode = s[1]
	if s[1] == SeaEnvSource.Mode.CORE_SAMPLES:
		src.scenario = s[2]
	else:
		src.wind_kn = s[2]
		src.puffs_enabled = _opt("puffs", false)
	_scene.camera_mode = s[3]
	_scene.boat_speed = _opt("speed", _scene.boat_speed)
	var sea: Sea = _scene.get_node("Sea")
	sea.quality = s[4]
	sea.use_internal_clock = false
	# headless meshes do not keep the native wakes' in-place updates: dump the references' meshes (the same
	# geometry, tests/wakes_native_test.gd)
	(_scene.get_node("Wakes") as SeaWakes).use_reference = true
	root.add_child(_scene)
	_frames = 0


func _process(_delta: float) -> bool:
	if _scene == null:
		return false
	var sea: Sea = _scene.get_node("Sea")
	sea.render_time_ms += DT_MS
	_frames += 1
	var n_seq: int = _opt("seq", 0)
	var step := int(round(float(_opt("step_ms", 500.0)) / DT_MS))
	if _frames < FRAMES or (n_seq > 0 and (_frames - FRAMES) % step != 0):
		return false
	if n_seq > 0:
		_dump("%s_%03d" % [_name(SHOTS[_shot]), _seq] if n_seq > 100 else "%s_%02d" % [_name(SHOTS[_shot]), _seq],
				_seq > 0 and _opt("light", false))
		_seq += 1
		if _seq < n_seq:
			return false
	else:
		_dump(_name(SHOTS[_shot]))
	_scene.queue_free()
	_scene = null
	_next()
	return false


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


func _write_arrays(dir: String, name: String, arrays: Array, xform: Transform3D = Transform3D.IDENTITY) -> Dictionary:
	var info := {}
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var world := PackedVector3Array()
	world.resize(verts.size())
	for i in verts.size():
		world[i] = xform * verts[i]
	_save(dir, name + "_pos.bin", world.to_byte_array())
	info["count"] = verts.size()
	for k in [[Mesh.ARRAY_TEX_UV, "uv"], [Mesh.ARRAY_TEX_UV2, "uv2"], [Mesh.ARRAY_COLOR, "color"],
			[Mesh.ARRAY_NORMAL, "normal"]]:
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


## Material factors of a boat surface for the preview: linear albedo, roughness, metallic, uv scale, AO share,
## albedo and metallic-roughness texture files (written once per texture).
func _boat_material(mat: Material, dir: String, tex_files: Dictionary) -> Dictionary:
	var out := {"albedo": [0.8, 0.8, 0.8, 1.0], "roughness": 0.5, "metallic": 0.0, "uv_scale": [1.0, 1.0], "ao": 0.0}
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader == BoatMaterials.SHADER:
		var m := mat as ShaderMaterial
		out["albedo"] = _v((m.get_shader_parameter("albedo_color") as Color).srgb_to_linear())
		out["roughness"] = m.get_shader_parameter("roughness")
		out["metallic"] = m.get_shader_parameter("metallic")
		out["uv_scale"] = _v(m.get_shader_parameter("uv_scale"))
		out["ao"] = m.get_shader_parameter("ao_strength")
		out["albedo_max"] = m.get_shader_parameter("albedo_max") if m.get_shader_parameter("albedo_max") != null else 0.8
		for k in [["albedo_tex", "albedo_tex"], ["mr_tex", "mr_tex"]]:
			var t = m.get_shader_parameter(k[0])
			if t is Texture2D:
				var id: int = t.get_instance_id()
				if not tex_files.has(id):
					tex_files[id] = "tex%d.png" % tex_files.size()
					(t as Texture2D).get_image().save_png(dir.path_join(tex_files[id]))
				out[k[1]] = tex_files[id]
	elif mat is BaseMaterial3D:
		var b := mat as BaseMaterial3D
		out["albedo"] = _v(b.albedo_color.srgb_to_linear())
		out["roughness"] = b.roughness
		out["metallic"] = b.metallic
	return out


func _save(dir: String, file: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(dir.path_join(file), FileAccess.WRITE)
	f.store_buffer(bytes)


func _dump(name: String, light := false) -> void:
	var dir := ProjectSettings.globalize_path(OUT).path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	var sea: Sea = _scene.get_node("Sea")
	if light:
		var first := name.substr(0, name.rfind("_")) + "_000"
		var fl := FileAccess.open(dir.path_join("scene.json"), FileAccess.WRITE)
		fl.store_string(JSON.stringify({"shot": name, "meshes_from": first, "render_time_ms": sea.render_time_ms,
				"water": _uniforms(sea.material)}, "  "))
		_dumped += 1
		return
	var cam: Camera3D = _scene.get_node("Camera")
	var sky: SkyRig = _scene.get_node("SkyDay")
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
	}
	var surf: MeshInstance3D = sea.get_node("Surface")
	data["grid"] = _write_arrays(dir, "grid", surf.mesh.surface_get_arrays(0))
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
	# wakes
	var wakes: SeaWakes = _scene.get_node("Wakes")
	var ribbons := []
	var wake_uniforms := {}
	var waves := []
	for mi in wakes.get_children():
		if not (mi is MeshInstance3D and mi.mesh is ArrayMesh and mi.mesh.get_surface_count() > 0 and mi.visible):
			continue
		var sh: Shader = (mi.material_override as ShaderMaterial).shader
		if sh == SeaWakes.WAKE_SHADER:
			var n := "wake%d" % ribbons.size()
			ribbons.append(_write_arrays(dir, n, mi.mesh.surface_get_arrays(0)))
			ribbons[-1]["name"] = n
			wake_uniforms = _uniforms(mi.material_override)
		elif sh == SeaWakes.BOW_SHADER:
			var n := "wave%d" % waves.size()
			waves.append(_write_arrays(dir, n, mi.mesh.surface_get_arrays(0)))
			waves[-1]["name"] = n
			waves[-1]["flow"] = mi.get_instance_shader_parameter("flow")
	data["wakes"] = ribbons
	data["wake_uniforms"] = wake_uniforms
	data["bow_waves"] = waves
	# drawn boat shadows (§4.7, tiers L and M): the grid in the scene and the material's uniforms
	# and their data texture (RGBA32F rows, one per boat)
	var drawn := []
	var bs: BoatShadows = _scene.get_node("BoatShadows")
	for mi in bs.get_children():
		if not (mi is MeshInstance3D and mi.visible):
			continue
		var n := "shadow%d" % drawn.size()
		drawn.append(_write_arrays(dir, n, mi.mesh.surface_get_arrays(0), mi.global_transform))
		drawn[-1]["name"] = n
		drawn[-1]["row"] = int(mi.get_instance_shader_parameter("shadow_row"))
	data["drawn_shadows"] = drawn
	data["drawn_uniforms"] = _uniforms(bs.material())
	var img := bs.data_image()
	data["drawn_tex"] = [img.get_width(), img.get_height()]
	_save(dir, "drawn_tex.bin", img.get_data())
	# mist sprites: world ENU centre, size, alpha, seed
	var mist := []
	for m in wakes.mist_sprites():
		var look := BowWave.mist_look(m)
		mist.append([m["pos"].x, m["pos"].y, m["pos"].z, look.x, look.y, m["seed"]])
	data["mist"] = mist
	# boat triangles (world), one entry per mesh surface with its material (boat shader or a BaseMaterial3D)
	var boats := []
	var tex_files := {}
	var stack: Array = [_scene.get_node("Boat")]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and n.mesh and n.visible:
			for si in n.mesh.get_surface_count():
				var mat: Material = n.get_active_material(si)
				var info := _write_arrays(dir, "boat%d" % boats.size(), n.mesh.surface_get_arrays(si), n.global_transform)
				info["name"] = "boat%d" % boats.size()
				info.merge(_boat_material(mat, dir, tex_files))
				boats.append(info)
	data["boat"] = boats
	data["light"] = {"hour": sky.hour, "conditions": sky.conditions, "sun_elevation_deg": sky.sun_elevation_deg,
		"sun_azimuth_deg": sky.sun_azimuth_deg}
	LookFx.lut_strip(LookFx.scaled(sky.grade, LookFx.grade_strength)).save_png(dir.path_join("lut.png"))
	var lf := FileAccess.open(dir.path_join("look.json"), FileAccess.WRITE)
	lf.store_string(JSON.stringify(LookFx.look_constants(), "  "))
	var f := FileAccess.open(dir.path_join("scene.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))
	_dumped += 1
	print("  dumped ", name)
