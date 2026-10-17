extends SceneTree
## Headless checks of the fleet boat materials (scripts/boat_materials.gd, sail_visuals.md §11.4) on the generated
## boats: one boat material and one shared tiling atlas (three VRAM-compressed textures) for a fleet of both classes,
## the imported copies released, every opaque surface on the boat material, the sails on their own, and the baked
## AO (COLOR_0 red) on the ambient light only. Run by tests/run_boat_import_test.sh.

const CLASSES := ["wm7", "wm12", "wm9", "wm16", "wm21", "wm10"]

var failures := 0


func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok  ", what)
	else:
		failures += 1
		print("FAIL  ", what)


func _init() -> void:
	print("boat materials checks")
	var originals := []
	var fleet := Node3D.new()
	root.add_child(fleet)
	for id in CLASSES:
		var path := "res://generated/boats/%s.glb" % id
		if not ResourceLoader.exists(path):
			check(false, "%s generated (run tests/run_boat_import_test.sh)" % path)
			continue
		var scene := load(path) as PackedScene
		for k in 3:
			var inst := scene.instantiate()
			if k == 0:
				_collect_originals(inst, originals)
			var n := BoatMaterials.apply(inst)
			check(k > 0 or n > 0, "%s boat %d: %d imported surfaces replaced" % [id, k, n])
			fleet.add_child(inst)
	var textures := {}
	var mats := {}
	var surfaces := 0
	var on_shader := 0
	var ao_slots := 0
	var stack: Array[Node] = [fleet]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or String(mi.name).begins_with("shadow"):
			continue
		for s in mi.mesh.get_surface_count():
			surfaces += 1
			var m := mi.get_active_material(s) as ShaderMaterial
			if m == null:
				continue
			if String(mi.name).begins_with("sail_"):
				on_shader += 1 if m.shader == BoatMaterials.SHADER else 0
				continue
			if m.shader != BoatMaterials.ATLAS_SHADER:
				continue
			on_shader += 1
			mats[m.get_instance_id()] = true
			for map in ["tile_color", "tile_mr", "tile_normal"]:
				var t = m.get_shader_parameter(map)
				if t is Texture2D:
					textures[t.get_instance_id()] = t
			var cols = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR]
			if cols != null and (cols as PackedColorArray).size() > 0:
				ao_slots += 1
	check(surfaces > 0 and on_shader == surfaces, "every boat surface on the boat or sail material (%d of %d)" % [on_shader, surfaces])
	check(mats.size() == 1, "one boat material for a fleet of %d boats of %d classes (%d)" % [3 * CLASSES.size(),
			CLASSES.size(), mats.size()])
	check(textures.size() == 3, "one shared tiling atlas: %d textures" % textures.size())
	var compressed := 0
	for t in textures.values():
		var img := (t as Texture2D).get_image()
		if img != null and img.is_compressed():
			compressed += 1
	check(compressed == textures.size(), "the tiling atlas is VRAM-compressed (%d of %d)" % [compressed, textures.size()])
	check(ao_slots > 0, "baked AO and slot colours present on %d surfaces" % ao_slots)
	# the imported materials and every class's own texture copies other than the kept set are released
	var alive := 0
	var shared_ids := {}
	for t in BoatMaterials.shared_textures().values():
		shared_ids[t.get_instance_id()] = true
	for w in originals:
		var o = w.get_ref()
		if o != null and not shared_ids.has(o.get_instance_id()):
			alive += 1
	check(alive == 0, "imported materials and duplicate textures released (%d of %d still alive)" % [alive, originals.size()])
	var names := []
	for u in BoatMaterials.ATLAS_SHADER.get_shader_uniform_list():
		names.append(u["name"])
	check(names.has("slot_color") and names.has("tile_color") and names.has("bk_albedo") and names.has("albedo_max"),
			"boat material shader parses (%d uniforms)" % names.size())
	var code := BoatMaterials.ATLAS_SHADER.code
	check(code.contains("AO = mix(1.0, COLOR.r") and code.contains("AO_LIGHT_AFFECT = 0.0"),
			"boat material: baked AO on the ambient light only (AO, AO_LIGHT_AFFECT 0)")
	var albedo_line := ""
	for l in code.split("\n"):
		if l.strip_edges().begins_with("ALBEDO"):
			albedo_line += l
	check(albedo_line != "" and not albedo_line.contains("COLOR"), "boat material: albedo not multiplied by the vertex colour")
	fleet.queue_free()
	print("boat materials checks: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	quit(0 if failures == 0 else 1)


## Weak references to the imported StandardMaterial3D slots and their textures of one instance.
func _collect_originals(inst: Node, out: Array) -> void:
	var stack: Array[Node] = [inst]
	var seen := {}
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if m == null or seen.has(m.get_instance_id()) or m.resource_name == "shadow":
				continue
			seen[m.get_instance_id()] = true
			out.append(weakref(m))
			for t in [m.albedo_texture, m.roughness_texture, m.normal_texture]:
				if t:
					out.append(weakref(t))
