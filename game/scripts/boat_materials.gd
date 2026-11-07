class_name BoatMaterials
extends RefCounted
## Boat materials for a fleet. The generator draws every opaque surface of a boat but the sails with one material,
## `boat` (sail_visuals.md §11.4, data_format.md §8.5): its slot table (in the material's extras) and the shared
## tiling atlas (generated/boats/_tex, imported once for every class and level) go into one ShaderMaterial on
## shaders/boat_atlas.gdshader, shared by every class and boat until a livery gives a boat its own copy
## (BoatLivery). The sails' own material (`sailcloth`) becomes a ShaderMaterial on shaders/boat.gdshader with its
## tiling set, the base of the sail shaders. The baked ambient occlusion (COLOR_0 red) darkens the ambient and
## reflected light only. The meshes are changed in place (they are the imported resources, shared by every
## instance of a class), so a second call is a no-op.
##
##   BoatMaterials.apply(model_root)

const SHADER := preload("res://shaders/boat.gdshader")
const ATLAS_SHADER := preload("res://shaders/boat_atlas.gdshader")
## livery regions of the slot table (data_format.md §8.5)
const REGIONS := ["", "hull", "deck", "transom", "keel", "keel_colour"]
## the shader's slot arrays
const SLOTS := 32

## "<texture_set>/<map>" -> Texture2D, map in albedo, mr, normal
static var _textures := {}
## factor signature -> ShaderMaterial
static var _materials := {}
## the shared boat material, the slot names by id and the slot ids by name
static var _atlas: ShaderMaterial
static var _slot_names: Array[String] = []
static var _slot_ids := {}


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
				var rn := (m as StandardMaterial3D).resource_name
				if rn == "boat":
					mi.mesh.surface_set_material(s, atlas_for(m))
				elif rn == "shadow":
					continue
				else:
					mi.mesh.surface_set_material(s, material_for(m))
				n += 1
	return n


## The shared boat material (shaders/boat_atlas.gdshader) for the imported `boat` slot material.
static func atlas_for(src: StandardMaterial3D) -> ShaderMaterial:
	if _atlas != null:
		return _atlas
	var extras: Dictionary = src.get_meta("extras", {}) if src.has_meta("extras") else {}
	var m := ShaderMaterial.new()
	m.shader = ATLAS_SHADER
	m.resource_name = "boat"
	m.set_meta("extras", extras)
	var col := PackedVector4Array()
	var pbr := PackedVector4Array()
	var map := PackedVector4Array()
	col.resize(SLOTS)
	pbr.resize(SLOTS)
	map.resize(SLOTS)
	_slot_names.clear()
	_slot_ids.clear()
	var slots: Array = extras.get("slots", [])
	for i in mini(slots.size(), SLOTS):
		var sl: Dictionary = slots[i]
		var c: Array = sl.get("color", [0.5, 0.5, 0.5])
		col[i] = Vector4(c[0], c[1], c[2], float(sl.get("normal_scale", 1.0)))
		pbr[i] = Vector4(float(sl.get("roughness", 0.5)), float(sl.get("metallic", 0.0)), float(sl.get("tile", 7)),
				1.0 / maxf(float(sl.get("tiling_m", 1.0)), 1e-3))
		map[i] = Vector4(float(REGIONS.find(String(sl.get("region", "")))), 1.0, 0.5,
				1.0 if bool(sl.get("steep_map", false)) else 0.0)
		_slot_names.append(String(sl.get("name", "")))
		_slot_ids[String(sl.get("name", ""))] = i
	m.set_shader_parameter("slot_color", col)
	m.set_shader_parameter("slot_pbr", pbr)
	m.set_shader_parameter("slot_map", map)
	var at: Dictionary = extras.get("atlas", {})
	m.set_shader_parameter("tile_grid", Vector2(float(at.get("cols", 4)), float(at.get("rows", 2))))
	m.set_shader_parameter("tile_inset", 1.0 / maxf(float(at.get("tile_px", 512)), 1.0))
	m.set_shader_parameter("detail_mean", float(extras.get("detail_mean", 0.92)))
	m.set_shader_parameter("rough_mean", float(extras.get("rough_mean", 0.8)))
	var g := slot_id("deck_gelcoat")
	var ns := slot_id("deck_nonslip")
	if g >= 0 and ns >= 0:
		m.set_shader_parameter("deck_tiles", Vector4(pbr[g].z, pbr[g].w, pbr[ns].z, pbr[ns].w))
		m.set_shader_parameter("ns_normal_scale", col[ns].w)
	m.set_shader_parameter("tile_color", _shared("_atlas", "albedo", src.albedo_texture))
	var mr := src.roughness_texture if src.roughness_texture else src.metallic_texture
	m.set_shader_parameter("tile_mr", _shared("_atlas", "mr", mr))
	m.set_shader_parameter("tile_normal", _shared("_atlas", "normal", src.normal_texture if src.normal_enabled else null))
	_atlas = m
	return m


## The source parts merged into a model's `body` node (data_format.md §8.5: COLOR_0 blue = part id / 255)
const BODY_PARTS := {"hull": 1, "deck": 2, "keel": 3, "mast": 4, "rigging": 5, "hardware": 6}


## The triangles of one source part of a boat model (`hull`, `deck`, `keel`, `mast`, `rigging`, `hardware`): from
## the merged `body` node by the part id of its vertices, or from a node of that name. Each entry {"positions" (in
## the frame of `model`), "indices" (the part's triangles), "uv2", "colors"}; `slots` keeps only those slots (by
## name).
static func part_surfaces(model: Node3D, part: String, slots: Array = []) -> Array:
	var out := []
	if model == null:
		return out
	var mi := model.find_child(part, true, false) as MeshInstance3D
	var pid := -1
	if mi == null:
		mi = model.find_child("body", true, false) as MeshInstance3D
		pid = int(BODY_PARTS.get(part, -1))
	if mi == null or mi.mesh == null:
		return out
	var xf := Transform3D.IDENTITY
	var x: Node = mi
	while x != null and x != model:
		if x is Node3D:
			xf = (x as Node3D).transform * xf
		x = x.get_parent()
	var ids := {}
	for k in slots:
		ids[slot_id(String(k))] = true
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		if idx == null:
			continue
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var keep := idx as PackedInt32Array
		if (pid >= 0 or not ids.is_empty()) and not cols.is_empty():
			keep = PackedInt32Array()
			var src := idx as PackedInt32Array
			for t in range(0, src.size(), 3):
				var c := cols[src[t]]
				if pid >= 0 and roundi(c.b * 255.0) != pid:
					continue
				if not ids.is_empty() and not ids.has(roundi(c.g * 255.0)):
					continue
				keep.append(src[t])
				keep.append(src[t + 1])
				keep.append(src[t + 2])
		if keep.is_empty():
			continue
		out.append({"positions": xf * (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array), "indices": keep,
			"uv2": arr[Mesh.ARRAY_TEX_UV2], "normals": arr[Mesh.ARRAY_NORMAL], "colors": cols})
	return out


## The shared boat material once a boat is loaded (null before).
static func atlas() -> ShaderMaterial:
	return _atlas


## The slot id of a slot name of the boat material (-1 when unknown).
static func slot_id(slot_name: String) -> int:
	return int(_slot_ids.get(slot_name, -1))


## The boat material's colour of a slot (linear) and its tile, for code that draws a slot elsewhere (the sheets).
static func slot_color(slot_name: String) -> Color:
	var i := slot_id(slot_name)
	if _atlas == null or i < 0:
		return Color(0.34, 0.33, 0.31)
	var v: Vector4 = (_atlas.get_shader_parameter("slot_color") as PackedVector4Array)[i]
	return Color(v.x, v.y, v.z)


## A rope material on shaders/boat.gdshader in the boat material's `rope` slot colour, the base of the sheets'
## materials (BoatLivery.rope_material puts the class's braid on it): one braid tile per 0.05 m of uv0.
static var _rope_base: ShaderMaterial


static func rope_base() -> ShaderMaterial:
	if _rope_base != null:
		return _rope_base
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.resource_name = "rope"
	m.set_shader_parameter("albedo_color", slot_color("rope").linear_to_srgb())
	m.set_shader_parameter("roughness", 0.85)
	m.set_shader_parameter("metallic", 0.0)
	m.set_shader_parameter("uv_scale", Vector2(20.0, 20.0))
	m.set_shader_parameter("ao_strength", 0.0)
	_rope_base = m
	return m


## The shared ShaderMaterial for an imported slot material with its own tiling set (the sails' `sailcloth`).
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
		"roughness": [0.82, 0.55, 0.68][style],
		"weave": [0.6, 0.15, 0.2][style],
		"fibre_amount": [0.0, 0.35, 0.06][style],
	}
	return params
