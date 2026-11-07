class_name ShaderWarmup
extends RefCounted
## The shader warm-up behind the navy fade (menus.md §5 Warm-up, PERFORMANCE.md A8): a tiny copy of every mesh and
## material a scene holds, put just in front of the camera that draws it, so each shader and its passes (colour,
## depth, shadow) compile on a frame the player does not see. One copy per new combination of the viewport, the
## surface's vertex format and primitive, the shader (a ShaderMaterial's shader, another material itself), the
## overlay, multimesh drawing and shadow casting; hidden nodes count too (the levels of detail, the course's guides,
## the shadows on the water), and so do the meshes of a SubViewport (the wake buffer), copied under its own camera.
## start() makes the copies, finish() frees them.

## the copy's size (m) and its distance past the camera's near plane
const COPY_SIZE := 0.02
const COPY_AHEAD := 0.3
## the most copies one warm-up makes
const MAX_COPIES := 400

## the copies, each a child of a camera
var copies: Array[GeometryInstance3D] = []
## the combinations seen (the copy keys), for tests
var keys := {}


## Copies the meshes under `top` in front of their cameras; an empty warm-up when nothing there draws.
static func start(top: Node) -> ShaderWarmup:
	var w := ShaderWarmup.new()
	if top != null and top.is_inside_tree():
		w._collect(top)
	return w


## Frees the copies (safe to call twice).
func finish() -> void:
	for c in copies:
		if is_instance_valid(c):
			c.queue_free()
	copies.clear()


func _collect(top: Node) -> void:
	var stack: Array[Node] = [top]
	while not stack.is_empty() and copies.size() < MAX_COPIES:
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D:
			_consider(n as MeshInstance3D, (n as MeshInstance3D).mesh, false)
		elif n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm != null:
				_consider(n as GeometryInstance3D, mm.mesh, true)


## The copy keys of `gi`'s surfaces that are new, as one copy of the whole node when any is.
func _consider(gi: GeometryInstance3D, mesh: Mesh, multi: bool) -> void:
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var cam := gi.get_viewport().get_camera_3d() if gi.get_viewport() != null else null
	if cam == null or gi.is_ancestor_of(cam) or cam.is_ancestor_of(gi):
		return
	var am := mesh as ArrayMesh
	var fresh := false
	for s in mesh.get_surface_count():
		var mat := gi.material_override
		if mat == null and gi is MeshInstance3D:
			mat = (gi as MeshInstance3D).get_surface_override_material(s)
		if mat == null:
			mat = mesh.surface_get_material(s)
		var fmt := "%d/%d" % [am.surface_get_format(s), am.surface_get_primitive_type(s)] if am != null \
				else mesh.get_class()
		var key := "%d|%s|%s|%s|%d|%d" % [cam.get_viewport().get_instance_id(), fmt, _shader_key(mat),
				_shader_key(gi.material_overlay), int(multi), int(gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)]
		if not keys.has(key):
			keys[key] = true
			fresh = true
	if fresh:
		_copy(gi, mesh, multi, cam)


static func _shader_key(m: Material) -> String:
	if m == null:
		return "-"
	if m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		return "s%d" % sh.get_rid().get_id() if sh != null else "-"
	return "m%d" % m.get_rid().get_id()


func _copy(gi: GeometryInstance3D, mesh: Mesh, multi: bool, cam: Camera3D) -> void:
	var c: GeometryInstance3D
	if multi:
		var src := (gi as MultiMeshInstance3D).multimesh
		var mm := MultiMesh.new()
		mm.transform_format = src.transform_format
		mm.use_colors = src.use_colors
		mm.use_custom_data = src.use_custom_data
		mm.mesh = mesh
		mm.instance_count = 1
		if mm.transform_format == MultiMesh.TRANSFORM_3D:
			mm.set_instance_transform(0, Transform3D.IDENTITY)
		else:
			mm.set_instance_transform_2d(0, Transform2D.IDENTITY)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		c = mmi
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var src := gi as MeshInstance3D
		for s in mesh.get_surface_count():
			var o := src.get_surface_override_material(s)
			if o != null:
				mi.set_surface_override_material(s, o)
		c = mi
	c.name = "Warmup%d" % copies.size()
	c.material_override = gi.material_override
	c.material_overlay = gi.material_overlay
	c.cast_shadow = gi.cast_shadow
	c.layers = gi.layers
	var aabb := mesh.get_aabb()
	var big := maxf(aabb.get_longest_axis_size(), 1e-3)
	var k := COPY_SIZE / big
	var basis := Basis.from_scale(Vector3(k, k, k))
	c.transform = Transform3D(basis, Vector3(0.0, 0.0, -(cam.near + COPY_AHEAD)) - basis * aabb.get_center())
	c.extra_cull_margin = 1.0
	cam.add_child(c)
	copies.append(c)
