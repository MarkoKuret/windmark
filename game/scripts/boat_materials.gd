class_name BoatMaterials
extends RefCounted
## Boat materials for a fleet: every imported boatgen slot (a StandardMaterial3D with the class's tiling texture
## set) is replaced on the imported meshes by a ShaderMaterial on shaders/boat.gdshader that
##   - uses one shared texture per texture set and map for every boat of every class (the importer extracts each
##     GLB's embedded copy of the set; the first one loaded is kept, the others are released with their
##     StandardMaterial3D), and
##   - applies the baked ambient occlusion (COLOR_0) to the ambient and reflected light only, where Godot's glTF
##     import multiplies it into the albedo (vertex_color_use_as_albedo).
## Slots with the same factors share one ShaderMaterial across classes. The meshes are changed in place (they
## are the imported resources, shared by every instance of a class), so a second call is a no-op.
##
##   BoatMaterials.apply(model_root)

const SHADER := preload("res://shaders/boat.gdshader")

## "<texture_set>/<map>" -> Texture2D, map in albedo, mr, normal
static var _textures := {}
## factor signature -> ShaderMaterial
static var _materials := {}


## Replaces the boatgen materials on every mesh under `root`. Returns the number of surfaces changed.
static func apply(root: Node) -> int:
	var n := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m is StandardMaterial3D:
				mi.mesh.surface_set_material(s, material_for(m))
				n += 1
	return n


## The shared boat ShaderMaterial for an imported slot material.
static func material_for(src: StandardMaterial3D) -> ShaderMaterial:
	var extras: Dictionary = src.get_meta("extras", {}) if src.has_meta("extras") else {}
	var tex_set: String = extras.get("texture_set", "")
	var key := "%s|%s|%s|%.4f|%.4f|%s|%s" % [src.resource_name, tex_set, src.albedo_color.to_html(),
			src.roughness, src.metallic, src.uv1_scale, src.vertex_color_use_as_albedo]
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.resource_name = src.resource_name
	if src.has_meta("extras"):
		m.set_meta("extras", src.get_meta("extras"))
	m.set_shader_parameter("albedo_color", src.albedo_color)
	m.set_shader_parameter("roughness", src.roughness)
	m.set_shader_parameter("metallic", src.metallic)
	m.set_shader_parameter("specular", src.metallic_specular)
	m.set_shader_parameter("uv_scale", Vector2(src.uv1_scale.x, src.uv1_scale.y))
	m.set_shader_parameter("ao_strength", 1.0 if src.vertex_color_use_as_albedo else 0.0)
	m.set_shader_parameter("albedo_tex", _shared(tex_set, "albedo", src.albedo_texture))
	var mr := src.roughness_texture if src.roughness_texture else src.metallic_texture
	m.set_shader_parameter("mr_tex", _shared(tex_set, "mr", mr))
	var nt := src.normal_texture if src.normal_enabled else null
	m.set_shader_parameter("normal_tex", _shared(tex_set, "normal", nt))
	m.set_shader_parameter("use_normal_tex", nt != null)
	m.set_shader_parameter("normal_scale", src.normal_scale)
	_materials[key] = m
	return m


static func _shared(tex_set: String, map: String, tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	if tex_set == "":
		return tex
	var k := tex_set + "/" + map
	if not _textures.has(k):
		_textures[k] = tex
	return _textures[k]


## Textures held for the fleet, "<texture_set>/<map>" -> Texture2D (tests).
static func shared_textures() -> Dictionary:
	return _textures


## Sail cloth materials (sail_visuals.md §11.1) by "<class>/<sail node>/<base material id>".
static var _cloth := {}


## The cloth material of one sail: a copy of the sail's ShaderMaterial (shaders/sail.gdshader) with the cloth
## uniforms of sail_cloth.gdshaderinc taken from the sail's rest grid. `pos`, `uv`, `uv2`: the grid-order arrays
## (port layer first, row-major from the foot, luff to leech). Returns `base` when it is not a sail ShaderMaterial.
static func sail_cloth(base: Material, sail_type: String, info: SimSource.ClassInfo, key: String,
		pos: PackedVector3Array, uv: PackedVector2Array, _uv2: PackedVector2Array, rows: int, cols: int) -> Material:
	if not (base is ShaderMaterial) or rows < 2 or cols < 2 or uv.size() < rows * cols:
		return base
	var k := "%s/%s/%d" % [info.id if info else "", key, base.get_instance_id()]
	if _cloth.has(k):
		return _cloth[k]
	var m := (base as ShaderMaterial).duplicate() as ShaderMaterial
	var p := cloth_params(sail_type, info.loa if info else 8.0, pos, uv, rows, cols)
	for pname in p:
		m.set_shader_parameter(pname, p[pname])
	_cloth[k] = m
	return m


## The cloth uniforms of a sail (sail_visuals.md §11.1): style and kind, the flat plan (shear and corners), the
## row chords, panel width, patch radius, battens, tell-tales and the cloth's optical constants.
static func cloth_params(sail_type: String, loa: float, pos: PackedVector3Array, uv: PackedVector2Array,
		rows: int, cols: int) -> Dictionary:
	var n := rows * cols
	var kind := 0 if sail_type == "main" else (2 if sail_type.begins_with("spinnaker") else 1)
	var style := 2 if kind == 2 else (1 if sail_type == "code_zero" or loa >= 10.0 else 0)
	var chord := PackedFloat32Array()
	chord.resize(48)
	for i in mini(rows, 48):
		chord[i] = uv[i * cols + cols - 1].x
	var luff_len := uv[(rows - 1) * cols].y
	# the angle between the luff and the rows, from the rest mid-surface, weighted by the chord
	var mid := func(i: int, j: int) -> Vector3:
		var g := i * cols + j
		return 0.5 * (pos[g] + pos[n + g]) if pos.size() >= 2 * n else pos[g]
	var luff: Vector3 = (mid.call(rows - 1, 0) - mid.call(0, 0)).normalized()
	var cs := 0.0
	var wsum := 0.0
	for i in rows - 1:
		var r: Vector3 = mid.call(i, cols - 1) - mid.call(i, 0)
		if r.length() < 0.2:
			continue
		cs += luff.dot(r.normalized()) * r.length()
		wsum += r.length()
	cs = clampf(cs / wsum if wsum > 0.0 else 0.0, -0.9, 0.9)
	var sn := sqrt(1.0 - cs * cs)
	var plan := func(a: float, l: float) -> Vector2:
		return Vector2(a * sn, l + a * cs)
	var params := {
		"cloth_style": style, "cloth_kind": kind, "cloth_shear": Vector2(cs, sn),
		"cloth_tack": Vector2.ZERO, "cloth_clew": plan.call(chord[0], uv[cols - 1].y),
		"cloth_head": plan.call(0.0, luff_len), "cloth_head_aft": plan.call(chord[mini(rows, 48) - 1], luff_len),
		"cloth_rows": float(mini(rows, 48)), "cloth_chord": chord,
		"cloth_panel": [0.9, 1.1, 0.9 + 0.03 * clampf(loa - 7.0, 0.0, 10.0)][style],
		"cloth_patch": (0.045 if kind == 2 else 0.06) * luff_len,
		"cloth_battens": 4 if kind == 0 else 0,
		"cloth_telltales": 1 if sail_type == "jib" or sail_type == "genoa" else 0,
		"backlight": [0.3, 0.2, 0.5][style],
		"roughness": [0.55, 0.38, 0.45][style],
		"weave": [0.6, 0.15, 0.2][style],
		"fibre_amount": [0.0, 0.35, 0.06][style],
	}
	return params
