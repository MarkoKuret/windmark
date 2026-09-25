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
