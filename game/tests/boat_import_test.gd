extends SceneTree
## Headless import test for boatgen models.
##
## Loads every `<id>.glb` and `<id>_collision.glb` in res://generated/boats/ (staged there by
## tests/run_boat_import_test.sh) and checks them against the class file (data/classes/<id>.boat.json, or
## tools/boatgen/tests/fixtures/<id>.boat.json for generator test classes) and the
## physics sidecar (<id>.physics.json) that boatgen writes next to the GLB:
##   - scale and axes: glTF +Y up, bow toward +Z, port toward +X, origin on the DWL at mid LWL
##   - node set, triangle and surface counts match the sidecar (sail_visuals.md §11.4: `body` and the moving parts),
##     the engine's automatic levels of detail generated on import, with the triangles drawn at 25 to 400 m
##   - one boat material (slot table and shared tiling atlas in its extras), every vertex on a known slot; the
##     sails' own material; the shadow proxy (shadow, shadow_boom under the boom)
##   - pivot nodes (rudder, boom, wheel, pole) sit on the sidecar pivots, with geometry around them
##   - sails: every node of the two-layer grid survives the import and maps back to its grid index by uv1 and
##     the layer side (SailGrid), the contract that run-time deformation relies on
##   - collision GLB imports as static bodies with convex shapes and no visible meshes
##
## Run: godot --headless --path game -s res://tests/boat_import_test.gd
## Exit code 0 when every check passes, 1 otherwise.

const BOAT_DIR := "res://generated/boats"
const KNOWN_MATERIALS := ["boat", "sailcloth", "shadow"]
## slots of the boat material every LOD0 has (data_format.md §8.5)
const REQUIRED_SLOTS := ["hull_gelcoat", "hull_boottop", "hull_antifouling", "deck_gelcoat", "deck_nonslip", "transom",
	"keel", "carbon", "metal", "rope_mainsheet", "deck_face"]
## sail_visuals.md §11.4: surfaces drawn without the sails (body and the moving parts)
const MAX_SURFACES := 6
## the camera the automatic levels are read for: 1920 pixels wide, 60 deg vertical field of view at 16:9, the
## default mesh LOD threshold of 1 pixel (Godot picks the coarsest level whose error is under it)
const SCREEN_W := 1920.0
const LOD_MULT := 2.0 * 1.7778 * 0.57735
const DISTANCES := [25.0, 50.0, 100.0, 250.0, 400.0]
## Positions come through the importer's 16-bit vertex compression; 5 mm is well above its error for a 20 m boat.
const POS_TOL := 0.005
## Hull extent against the class-file dimensions (stem rounding, toe rail and rub strake stand proud a little).
const HULL_TOL := 0.06

var failures := 0
var checks := 0
## {class id: {lod: {"triangles", "surfaces", "vertices"}}} for the fleet cost
var lod_stats := {}
var warnings := 0


func _initialize() -> void:
	var ids := _class_ids()
	if ids.is_empty():
		_fail("no boat GLBs in %s (run tests/run_boat_import_test.sh)" % BOAT_DIR)
	for id in ids:
		print("== %s" % id)
		_test_model(id)
		_test_auto_lods(id)
		_test_collision(id)
	_fleet_cost()
	print("%d checks, %d failures, %d warnings (known boatgen issues)" % [checks, failures, warnings])
	quit(1 if failures > 0 else 0)


func _class_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(BOAT_DIR):
		if f.ends_with(".glb") and not f.ends_with("_collision.glb") and not _is_lod_file(f):
			out.append(f.get_basename())
	out.sort()
	return out


## `<id>_lod<n>.glb`: a lower level of detail of <id> (checked with its class, not as a class of its own).
func _is_lod_file(f: String) -> bool:
	var b := f.get_basename()
	var i := b.rfind("_lod")
	return i > 0 and b.substr(i + 4).is_valid_int()


# ---------------------------------------------------------------- helpers

func _check(ok: bool, what: String) -> bool:
	checks += 1
	if not ok:
		_fail(what)
	return ok


func _warn(what: String) -> void:
	warnings += 1
	print("WARN: " + what)


func _fail(what: String) -> void:
	failures += 1
	printerr("FAIL: " + what)


func _near(a: float, b: float, tol: float, what: String) -> bool:
	return _check(absf(a - b) <= tol, "%s: %.4f, expected %.4f (tol %.3f)" % [what, a, b, tol])


func _near_v(a: Vector3, b: Vector3, tol: float, what: String) -> bool:
	return _check(a.distance_to(b) <= tol, "%s: %s, expected %s (tol %.3f)" % [what, a, b, tol])


func _read_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		_fail("cannot read JSON " + path)
		return {}
	return data


## Body frame (x forward, y port, z up) to the glTF/Godot model frame (+X port, +Y up, +Z forward).
func _body_to_model(p: Array) -> Vector3:
	return Vector3(float(p[1]), float(p[2]), float(p[0]))


func _mesh_aabb(mi: MeshInstance3D) -> AABB:
	return mi.transform * mi.mesh.get_aabb()


func _triangles(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		n += (idx.size() / 3) if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _surface_material_name(mesh: Mesh, s: int) -> String:
	var m := mesh.surface_get_material(s)
	return m.resource_name if m else ""


## The class file: data/classes/<id>.boat.json, or a boatgen test fixture.
func _class_file(id: String) -> String:
	var repo := ProjectSettings.globalize_path("res://").path_join("..")
	var path := repo.path_join("data/classes/%s.boat.json" % id)
	if not FileAccess.file_exists(path):
		path = repo.path_join("tools/boatgen/tests/fixtures/%s.boat.json" % id)
	return path


# ---------------------------------------------------------------- levels of detail

## Counts of one imported model: model triangles without the sails and the shadow proxy, surfaces drawn (one
## draw call each, before any batching; the sails counted apart), vertices, and the shadow proxy's triangles.
func _model_stats(root: Node) -> Dictionary:
	var st := {"triangles": 0, "surfaces": 0, "vertices": 0, "sail_surfaces": 0, "shadow": 0}
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var n := String(mi.name)
		if n.begins_with("shadow"):
			st["shadow"] += _triangles(mi.mesh)
			continue
		if n.begins_with("sail_"):
			st["sail_surfaces"] += mi.mesh.get_surface_count()
			continue
		st["triangles"] += _triangles(mi.mesh)
		st["surfaces"] += mi.mesh.get_surface_count()
		for s in mi.mesh.get_surface_count():
			st["vertices"] += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return st


## The slot names (BoatMaterials' table, the GLB's boat material extras) used by a mesh's boat surfaces.
func _slots_of(mesh: Mesh) -> Dictionary:
	var out := {}
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		if m == null or m.resource_name != "boat" or not m.has_meta("extras"):
			continue
		var table: Array = m.get_meta("extras").get("slots", [])
		var col = mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR]
		if col == null:
			continue
		for c in (col as PackedColorArray):
			var k := roundi(c.g * 255.0)
			out[String(table[k]["name"]) if k < table.size() else "?%d" % k] = true
	return out


## The triangles the renderer draws of a mesh at `dist` m (sail_visuals.md §11.4): the coarsest of the mesh's
## automatic levels (ArrayMesh `_surfaces` lods: error, index bytes) whose error stays under a pixel, times `bias`.
func _lod_triangles(mesh: Mesh, dist: float, bias := 1.0) -> int:
	var n := 0
	var surfs: Variant = mesh.get("_surfaces")
	if not (surfs is Array):
		return _triangles(mesh)
	for d: Dictionary in surfs:
		var count := int(d.get("index_count", 0))
		var lods: Array = d.get("lods", [])
		var stride := 4 if int(d.get("vertex_count", 0)) > 65535 else 2
		for k in range(0, lods.size(), 2):
			if float(lods[k]) * bias / (dist * LOD_MULT) > 1.0 / SCREEN_W:
				break
			count = (lods[k + 1] as PackedByteArray).size() / stride
		n += count / 3
	return n


## The engine's automatic levels of detail (sail_visuals.md §11.4): generated on import for the model's meshes,
## fewer triangles with distance; printed per distance (the model without sails, and the own boat's at its bias).
func _test_auto_lods(id: String) -> void:
	var scene := load("%s/%s.glb" % [BOAT_DIR, id]) as PackedScene
	if scene == null:
		return
	var inst := scene.instantiate()
	var root := inst.get_child(0) as Node3D
	var body := root.find_child("body", false, false) as MeshInstance3D
	var surfs: Variant = body.mesh.get("_surfaces") if body else null
	_check(surfs is Array and not ((surfs as Array)[0] as Dictionary).get("lods", []).is_empty(),
		"%s: the body has the engine's automatic levels of detail" % id)
	var line := "  automatic levels, model triangles drawn (own boat):"
	var prev := 1 << 30
	var row := {}
	for dist in DISTANCES:
		var t := 0
		var own := 0
		for c in root.get_children():
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null or String(mi.name).begins_with("sail_") or String(mi.name).begins_with("shadow"):
				continue
			t += _lod_triangles(mi.mesh, dist)
			own += _lod_triangles(mi.mesh, dist, BoatView.OWN_LOD_BIAS)
		line += " %d m %d (%d)," % [int(dist), t, own]
		_check(t <= prev, "%s: no more triangles at %d m than nearer" % [id, int(dist)])
		prev = t
		row[dist] = t
	print(line)
	lod_stats[id] = row
	inst.free()


## Fleet cost: a 16-boat fleet of each class at a start as the chase camera sees it (1 boat at 25 m, 5 at 50 m, 6
## at 100 m, 4 at 250 m), model triangles from the automatic levels.
func _fleet_cost() -> void:
	var mix := {25.0: 1, 50.0: 5, 100.0: 6, 250.0: 4}
	for id in lod_stats:
		var row: Dictionary = lod_stats[id]
		var tris := 0
		for d in mix:
			tris += int(mix[d]) * int(row.get(d, 0))
		print("fleet %s x16 at a start: %d model triangles (16 at 25 m: %d)" % [id, tris, 16 * int(row.get(25.0, 0))])
		_check(tris < 16 * int(row.get(25.0, 0)), "%s: the fleet costs less than 16 boats at 25 m" % id)


# ---------------------------------------------------------------- model

func _test_model(id: String) -> void:
	var path := "%s/%s.glb" % [BOAT_DIR, id]
	var scene := load(path) as PackedScene
	if not _check(scene != null, "%s loads as PackedScene" % path):
		return
	var scene_root := scene.instantiate()
	var boat := _read_json(_class_file(id))
	var side := _read_json("%s/%s.physics.json" % [BOAT_DIR, id])
	if boat.is_empty() or side.is_empty():
		scene_root.free()
		return

	# Godot wraps the glTF scene in its own root (named after the file); the glTF root node, named after the
	# class id, is its only child. Both sit at identity.
	_check(scene_root.get_child_count() == 1 and scene_root.get_child(0).name == id,
		"the glTF root node %s is the only child of the scene root" % id)
	var root := scene_root.get_child(0) as Node3D
	if not _check(root != null, "glTF root is a Node3D"):
		scene_root.free()
		return
	_check((scene_root as Node3D).transform == Transform3D.IDENTITY and root.transform == Transform3D.IDENTITY,
		"scene root and glTF root transforms are identity")
	if root.has_meta("extras"):
		print("  root extras: %s" % JSON.stringify(root.get_meta("extras")))

	# Node set: one MeshInstance3D per sidecar node, directly under the root, with no rotation or scale.
	var parts := {}
	for c in root.get_children():
		if _check(c is MeshInstance3D, "%s is a MeshInstance3D (%s)" % [c.name, c.get_class()]):
			parts[String(c.name)] = c
			_check((c as Node3D).basis == Basis.IDENTITY, "%s has no rotation or scale" % c.name)
	var expected: Array = side["model"]["nodes"]
	var names := parts.keys()
	names.sort()
	expected.sort()
	_check(names == expected, "nodes %s match the sidecar %s" % [names, expected])
	var st := _model_stats(root)
	_check(st["surfaces"] == int(side["model"].get("surfaces", -1)) and st["surfaces"] <= MAX_SURFACES,
		"%s: %d surfaces without the sails (sidecar %d, at most %d)" % [id, st["surfaces"],
		int(side["model"].get("surfaces", -1)), MAX_SURFACES])
	_check(st["shadow"] > 0 and st["shadow"] < 1000, "%s: a shadow proxy of %d triangles" % [id, st["shadow"]])
	_check(parts.has("boom") and (parts["boom"] as Node).find_child("shadow_boom", false, false) != null,
		"%s: the boom's shadow proxy swings with the boom" % id)
	for mv in ["rudder", "boom", "mainsheet"]:
		_check(parts.has(mv), "%s: the moving part %s is its own node" % [id, mv])
	print("  %d surfaces + %d sails, %d model triangles, %d vertices, shadow proxy %d" % [st["surfaces"],
		st["sail_surfaces"], st["triangles"], st["vertices"], st["shadow"]])

	_test_axes(boat, parts)
	_test_materials(id, parts)
	_test_pivots(side, parts)
	_test_sails(side, parts)

	# Triangle counts (the model without the sails and the shadow proxy).
	var total := 0
	var line := "  triangles:"
	for n in names:
		var t := _triangles((parts[n] as MeshInstance3D).mesh)
		if not (String(n).begins_with("sail_") or String(n).begins_with("shadow")):
			total += t
		line += " %s %d," % [n, t]
	print(line + " total %d" % total)
	_check(total == int(side["model"]["triangles"]), "triangle total %d matches the sidecar %d" % [total, int(side["model"]["triangles"])])
	scene_root.free()


## The extent of a source part of the model (a node, or a part of the merged body), in the model frame.
func _part_aabb(root: Node3D, part: String) -> AABB:
	var box := AABB()
	var first := true
	for e in BoatMaterials.part_surfaces(root, part):
		var pos: PackedVector3Array = e["positions"]
		for i in (e["indices"] as PackedInt32Array):
			if first:
				box = AABB(pos[i], Vector3.ZERO)
				first = false
			else:
				box = box.expand(pos[i])
	return box


func _test_axes(boat: Dictionary, parts: Dictionary) -> void:
	var root := (parts.values()[0] as Node).get_parent() as Node3D
	var hull: Dictionary = boat["hull"]
	var h := _part_aabb(root, "hull")
	print("  hull aabb %s .. %s" % [h.position, h.end])
	# Bow toward +Z, transom toward -Z, origin at mid LWL: the hull spans transom_x..stem_x along Z.
	_near(h.end.z, float(hull["stem_x"]), HULL_TOL, "hull stem along +Z")
	_near(h.position.z, float(hull["transom_x"]), HULL_TOL, "hull transom along -Z")
	# Beam along X, symmetric about the centreline.
	_near(h.size.x, float(hull["beam_max"]), HULL_TOL, "hull beam along X")
	_near(h.get_center().x, 0.0, 0.01, "hull centred on X = 0")
	# +Y up, origin on the DWL: canoe body below Y = 0 by draft_canoe, sheer above it.
	_near(h.position.y, -float(hull["draft_canoe"]), 0.02, "canoe body bottom below the DWL")
	_check(h.end.y > 0.3, "sheer above the DWL (%.3f)" % h.end.y)
	# Appendages and rig: total draft and masthead height set the vertical scale.
	_near(_part_aabb(root, "keel").position.y, -float(boat["keel"]["depth"]), 0.02, "keel bottom at -keel.depth")
	# twin rudders (rudder.count 2): each blade on its own node, the tiller alone in `rudder`
	for rn in (["rudder_port", "rudder_starboard"] if int(boat["rudder"].get("count", 1)) == 2 else ["rudder"]):
		_near(_mesh_aabb(parts[rn]).position.y, -float(boat["rudder"]["depth"]), 0.02, "%s tip at -rudder.depth" % rn)
	# The masthead carries a wind wand up to about 1 m above mast_height.
	var mast_top := _part_aabb(root, "mast").end.y
	var mh := float(boat["rig"]["mast_height"])
	_check(mast_top >= mh and mast_top <= mh + 1.2, "mast top %.3f just above mast_height %.3f" % [mast_top, mh])
	# Handedness: uv1 of the hull puts the starboard side in v 0..0.5; starboard must be -X (port is +X), so a
	# mirrored import would show up here.
	var wrong := 0
	var n := 0
	for e in BoatMaterials.part_surfaces(root, "hull"):
		var p: PackedVector3Array = e["positions"]
		var uv2: PackedVector2Array = e["uv2"]
		for i in (e["indices"] as PackedInt32Array):
			# Skip the centreline and the band edges (sheer at v = 0 and 0.5, keel at 0.5 and 1), where the
			# importer's 16-bit uv storage can land on either side of 0.5.
			var v := fmod(uv2[i].y, 0.5)
			if absf(p[i].x) < 0.02 or v < 0.005 or v > 0.495:
				continue
			n += 1
			if (uv2[i].y < 0.5) != (p[i].x < 0.0):
				wrong += 1
	_check(n > 0 and wrong == 0, "hull uv1 starboard band is on -X (%d of %d vertex uses on the wrong side)" % [wrong, n])


func _test_materials(id: String, parts: Dictionary) -> void:
	var found := {}
	var slots := {}
	var meshes: Array = parts.values()
	if parts.has("boom"):
		for c in (parts["boom"] as Node).get_children():
			meshes.append(c)
	for part in meshes:
		var mesh: Mesh = (part as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			var nm := _surface_material_name(mesh, s)
			if not _check(m is StandardMaterial3D, "%s surface %d material %s is StandardMaterial3D" % [part.name, s, nm]):
				continue
			_check(nm in KNOWN_MATERIALS, "%s surface %d material '%s' is a boatgen material" % [part.name, s, nm])
			if found.has(nm):
				_check(found[nm] == m, "material %s is one shared resource" % nm)
			found[nm] = m
			var col = mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR]
			if nm == "boat":
				# slot ids (green) and baked AO (red) as vertex colours (data_format.md §8.5)
				if _check(col != null and (col as PackedColorArray).size() > 0, "%s surface %d carries slot and AO colours" % [part.name, s]):
					for k in _slots_of(mesh):
						slots[k] = true
			elif nm == "shadow":
				_check(String(part.name).begins_with("shadow"), "%s: the shadow material only on the proxy" % part.name)
	_check(found.size() == 3, "%s: the boat, sailcloth and shadow materials (%s)" % [id, found.keys()])
	for k in slots:
		_check(not String(k).begins_with("?"), "%s: slot %s is in the table" % [id, k])
	for k in REQUIRED_SLOTS:
		_check(slots.has(k), "%s has slot %s" % [id, k])
	if found.has("boat"):
		var m: StandardMaterial3D = found["boat"]
		var ex: Dictionary = m.get_meta("extras", {}) if m.has_meta("extras") else {}
		_check(ex.get("slots", []).size() >= 20 and ex.has("atlas"), "%s: the boat material's slot table and atlas in its extras" % id)
		_check(m.albedo_texture != null and m.roughness_texture != null and m.normal_texture != null,
			"%s: the boat material has the shared tiling atlas" % id)
		if m.albedo_texture != null:
			_check(m.albedo_texture.resource_path.begins_with("res://generated/boats/_tex/"),
				"%s: the tiling atlas is the shared file %s" % [id, m.albedo_texture.resource_path])
			var img := m.albedo_texture.get_image()
			_check(img != null and img.is_compressed(), "%s: the tiling atlas is VRAM-compressed" % id)
		_check(m.cull_mode == BaseMaterial3D.CULL_BACK and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
			"%s: the boat material is opaque and culls back faces" % id)
	print("  materials: %s; slots: %s" % [found.keys(), slots.keys()])


func _test_pivots(side: Dictionary, parts: Dictionary) -> void:
	var rig: Dictionary = side["rig"]
	var pivots := {"rudder": "rudder_stock", "boom": "boom_pivot", "wheel": "wheel_hub", "pole": "pole_pivot"}
	var blades := {}                                  # twin rudders: node -> its stock (rig.rudders)
	for r in rig.get("rudders", []):
		blades[String(r["node"])] = r["stock"]
	for node in side["model"]["pivots"]:
		if not _check((pivots.has(node) or blades.has(node)) and parts.has(node), "pivot node %s is known and present" % node):
			continue
		var mi: MeshInstance3D = parts[node]
		_near_v(mi.position, _body_to_model(blades[node] if blades.has(node) else rig[pivots[node]]), POS_TOL, "%s pivot" % node)
		var local := mi.mesh.get_aabb()
		print("  %s pivot %s, local aabb %s .. %s" % [node, mi.position, local.position, local.end])
		match node:
			"rudder_port", "rudder_starboard":
				# Each twin blade hangs below its own stock, the axis through its top.
				_check(local.position.x < 0.0 and local.end.x > 0.0 and local.position.z < 0.0 and local.end.z > 0.0,
					"%s: its stock axis passes through the blade top" % node)
				_check(local.position.y < -0.3, "%s hangs below its pivot" % node)
			"rudder" when not blades.is_empty():
				# Twin rudders: the tiller alone, forward from its stock on the centreline.
				_check(local.end.z > 0.5 and local.position.y > -0.3, "the tiller runs forward from its stock")
			"rudder":
				# The stock (turning axis, local Y) runs through the blade.
				_check(local.position.x < 0.0 and local.end.x > 0.0 and local.position.z < 0.0 and local.end.z > 0.0,
					"rudder stock axis passes through the rudder")
				_check(local.position.y < -0.3, "rudder blade hangs below its pivot")
			"boom":
				# Boom runs aft from the gooseneck (local origin) along -Z.
				_near(local.position.z, -float(rig["boom_length"]), 0.35, "boom runs aft from the gooseneck")
				_check(local.end.z < 0.3 and absf(local.get_center().x) < 0.05, "boom starts at the gooseneck on the centreline")
			"pole":
				# Spinnaker pole runs forward from its pivot on the mast axis (local +Z) to the pole end.
				_near(local.end.z, float(rig["pole_length"]) + float(rig["mast_chord"]) / 2.0, 0.1, "pole reaches its end")
				_check(local.position.z > -0.2 and absf(local.get_center().x) < 0.05, "pole runs forward from the mast on the centreline")
			"wheel":
				# Wheel turns about fore and aft (local Z): round in X/Y about the hub, thin along Z.
				_near(local.get_center().x, 0.0, 0.02, "wheel centred on the hub in X")
				_near(local.get_center().y, 0.0, 0.05, "wheel centred on the hub in Y")
				_check(local.size.z < 0.5 * local.size.y, "wheel is thin along its fore-and-aft axle")


func _test_sails(side: Dictionary, parts: Dictionary) -> void:
	for sid in side["sails"]:
		var sail: Dictionary = side["sails"][sid]
		var node := String(sail["node"])
		if not _check(parts.has(node), "sail node %s present" % node):
			continue
		var mesh: Mesh = (parts[node] as MeshInstance3D).mesh
		if not _check(mesh.get_surface_count() == 1 and _surface_material_name(mesh, 0) == "sailcloth",
				"%s is one sailcloth surface" % node):
			continue
		var rows := int(sail["grid_rows"])
		var cols := int(sail["grid_cols"])
		var layer := rows * cols
		var a := mesh.surface_get_arrays(0)
		var p: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var full_tris := 4 * (rows - 1) * (cols - 1)
		print("  %s: grid %d x %d, %d of %d vertices, %d of %d triangles" % [node, rows, cols, p.size(), 2 * layer,
			idx.size() / 3, full_tris])
		# Full grid topology: every node referenced (zero-area head cells kept), so the importer drops none.
		_check(p.size() == 2 * layer, "%s vertex count %d is 2 x %d x %d" % [node, p.size(), rows, cols])
		_check(idx.size() / 3 == full_tris, "%s has %d triangles, the full grid's %d" % [node, idx.size() / 3, full_tris])
		# The importer reorders vertices; SailGrid recovers each one's grid node from uv1 and the layer side.
		var g := SailGrid.grid_index(mesh, rows, cols)
		var at := {}
		var off_grid := 0
		for i in g.size():
			if g[i] < 0 or at.has(g[i]):
				off_grid += 1
			else:
				at[g[i]] = i
		_check(off_grid == 0, "%s: every vertex maps to its own grid node (%d do not)" % [node, off_grid])
		if p.size() < 2 * layer:
			var missing := []
			for k in 2 * layer:
				if not at.has(k):
					missing.append("L%d r%d c%d" % [k / layer, (k % layer) / cols, k % cols])
			_check(false, "%s: grid nodes missing after import (unreferenced in the GLB): %s" % [node, ", ".join(missing)])
		# Corners from the sidecar.
		for corner in sail["corners"]:
			var c: Dictionary = sail["corners"][corner]
			var k := int(c["row"]) * cols + int(c["col"])
			var want := _body_to_model(c["position"])
			for l in 2:
				if not at.has(k + l * layer):
					_check(false, "%s %s corner (grid node %d) is in the imported mesh" % [node, corner, k + l * layer])
					continue
				_near_v(p[at[k + l * layer]], want, 0.01, "%s %s on the %s layer" % [node, corner, ["port", "starboard"][l]])
		# Layers pair node by node, 2 mm apart, port on +X, normals outward.
		var bad := 0
		var pairs := 0
		for k in layer:
			if not (at.has(k) and at.has(k + layer)):
				continue
			pairs += 1
			var ip: int = at[k]
			var i_s: int = at[k + layer]
			var d := p[ip] - p[i_s]
			if absf(d.length() - 0.002) > 0.001 or d.x <= 0.0 or nrm[ip].x < 0.99 or nrm[i_s].x > -0.99:
				bad += 1
		_check(pairs > 0 and bad == 0, "%s: %d node pairs 2 mm apart, port layer on +X, normals outward (%d bad)" % [node, pairs, bad])


# ---------------------------------------------------------------- collision

func _test_collision(id: String) -> void:
	var path := "%s/%s_collision.glb" % [BOAT_DIR, id]
	var scene := load(path) as PackedScene
	if not _check(scene != null, "%s loads as PackedScene" % path):
		return
	var root := scene.instantiate()
	var side := _read_json("%s/%s.physics.json" % [BOAT_DIR, id])
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	_check(meshes.is_empty(), "collision GLB has no visible meshes (%d)" % meshes.size())
	var bodies := {}
	for b in root.find_children("*", "StaticBody3D", true, false):
		bodies[String(b.name)] = b
	var expected: Array = side["collision_meshes"].keys()
	var names := bodies.keys()
	names.sort()
	expected.sort()
	_check(names == expected, "collision bodies %s match the sidecar %s" % [names, expected])
	var line := "  collision:"
	for n in names:
		var shapes := (bodies[n] as Node).find_children("*", "CollisionShape3D", false, false)
		if not _check(shapes.size() == 1, "%s has one CollisionShape3D" % n):
			continue
		var shape := (shapes[0] as CollisionShape3D).shape
		if not _check(shape is ConvexPolygonShape3D, "%s shape is ConvexPolygonShape3D (%s)" % [n, shape.get_class() if shape else "none"]):
			continue
		var pts := (shape as ConvexPolygonShape3D).points
		line += " %s %d points," % [n, pts.size()]
		# The shape stays in the model frame: its extent along Z matches the sidecar vertices.
		var zmin := INF
		var zmax := -INF
		for v in side["collision_meshes"][n]["vertices"]:
			zmin = minf(zmin, float(v[0]))
			zmax = maxf(zmax, float(v[0]))
		var t := _chain(shapes[0])
		var pz_min := INF
		var pz_max := -INF
		for q in pts:
			var w := t * q
			pz_min = minf(pz_min, w.z)
			pz_max = maxf(pz_max, w.z)
		_near(pz_min, zmin, POS_TOL, "%s collision aft end" % n)
		_near(pz_max, zmax, POS_TOL, "%s collision forward end" % n)
	print(line)
	root.free()


## Transform of a node relative to the scene root (the instance is not in the tree).
func _chain(n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != null:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
