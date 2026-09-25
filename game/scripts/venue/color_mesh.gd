class_name ColorMesh
extends RefCounted
## A small builder for vertex-coloured meshes (venue props, marks, committee boats): positions, normals, linear
## colours and triangles, wound so that Godot's front face (clockwise seen from the viewer) faces `outward`.
## Colours are linear; the materials read them unconverted (vertex_color_is_srgb off, or the land shader).

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()


func vertex(p: Vector3, n: Vector3, c: Color) -> int:
	verts.append(p)
	normals.append(n)
	colors.append(c)
	return verts.size() - 1


## A triangle of existing vertices facing `outward` (any vector on the visible side).
func tri(a: int, b: int, c: int, outward: Vector3) -> void:
	var n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if n.dot(outward) > 0.0:
		indices.append_array([a, c, b])
	else:
		indices.append_array([a, b, c])


## A flat-shaded triangle with its own vertices.
func flat_tri(a: Vector3, b: Vector3, c: Vector3, col: Color, outward := Vector3.ZERO) -> void:
	var n := (b - a).cross(c - a).normalized()
	if outward != Vector3.ZERO and n.dot(outward) < 0.0:
		n = -n
	var i := vertex(a, n, col)
	vertex(b, n, col)
	vertex(c, n, col)
	tri(i, i + 1, i + 2, n)


## A flat quad a, b, c, d (in order around it).
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, outward := Vector3.ZERO) -> void:
	var n := (b - a).cross(c - a).normalized()
	if outward != Vector3.ZERO and n.dot(outward) < 0.0:
		n = -n
	var i := vertex(a, n, col)
	vertex(b, n, col)
	vertex(c, n, col)
	vertex(d, n, col)
	tri(i, i + 1, i + 2, n)
	tri(i, i + 2, i + 3, n)


## A two-sided flat quad (flags): both faces, 1 cm apart along the normal.
func card(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, lift := 0.0) -> void:
	var n := (b - a).cross(c - a).normalized()
	var o := n * (0.005 + lift)
	quad(a + o, b + o, c + o, d + o, col, n)
	quad(a - o, b - o, c - o, d - o, col, -n)


## A two-sided flat triangle.
func card_tri(a: Vector3, b: Vector3, c: Vector3, col: Color, lift := 0.0) -> void:
	var n := (b - a).cross(c - a).normalized()
	var o := n * (0.005 + lift)
	flat_tri(a + o, b + o, c + o, col, n)
	flat_tri(a - o, b - o, c - o, col, -n)


## A vertical cylinder (smooth sides, flat caps) from y0 to y1 about (cx, cz).
func cylinder(centre: Vector3, r0: float, r1: float, h: float, sides: int, col: Color, cap_col := Color(-1, 0, 0)) -> void:
	var top := col if cap_col.r < 0.0 else cap_col
	var base := verts.size()
	for k in sides + 1:
		var a := TAU * k / sides
		var dir := Vector3(cos(a), 0.0, sin(a))
		var slope := (r0 - r1) / maxf(h, 1e-4)
		var n := (dir + Vector3(0, slope, 0)).normalized()
		vertex(centre + dir * r0, n, col)
		vertex(centre + dir * r1 + Vector3(0, h, 0), n, col)
	for k in sides:
		var i := base + 2 * k
		tri(i, i + 2, i + 1, verts[i] - centre)
		tri(i + 1, i + 2, i + 3, verts[i + 1] - centre - Vector3(0, h, 0))
	var c := vertex(centre + Vector3(0, h, 0), Vector3.UP, top)
	var ring := verts.size()
	for k in sides:
		var a := TAU * k / sides
		vertex(centre + Vector3(cos(a) * r1, h, sin(a) * r1), Vector3.UP, top)
	for k in sides:
		tri(c, ring + k, ring + (k + 1) % sides, Vector3.UP)


## An axis-aligned box in a local frame `xf` (size along the basis axes, centred).
func box(xf: Transform3D, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var p := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x * h.x, y * h.y, z * h.z)
	var faces := [
		[Vector3(1, 0, 0), [p.call(1, -1, -1), p.call(1, 1, -1), p.call(1, 1, 1), p.call(1, -1, 1)]],
		[Vector3(-1, 0, 0), [p.call(-1, -1, -1), p.call(-1, -1, 1), p.call(-1, 1, 1), p.call(-1, 1, -1)]],
		[Vector3(0, 1, 0), [p.call(-1, 1, -1), p.call(-1, 1, 1), p.call(1, 1, 1), p.call(1, 1, -1)]],
		[Vector3(0, -1, 0), [p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, -1, 1), p.call(-1, -1, 1)]],
		[Vector3(0, 0, 1), [p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1)]],
		[Vector3(0, 0, -1), [p.call(-1, -1, -1), p.call(-1, 1, -1), p.call(1, 1, -1), p.call(1, -1, -1)]],
	]
	for f in faces:
		var q: Array = f[1]
		quad(q[0], q[1], q[2], q[3], col, xf.basis * f[0])


## A squashed low-poly sphere (tree crowns, shrubs) with jittered radius; `rng` for the jitter.
func blob(centre: Vector3, r: Vector3, rings: int, segs: int, col_top: Color, col_bottom: Color,
		rng: RandomNumberGenerator, jitter := 0.18) -> void:
	var base := verts.size()
	for i in rings + 1:
		var v := PI * i / rings
		for k in segs:
			var a := TAU * k / segs
			var d := Vector3(sin(v) * cos(a), cos(v), sin(v) * sin(a))
			var j := 1.0 + (rng.randf() - 0.5) * 2.0 * jitter if i > 0 and i < rings else 1.0
			var c := col_bottom.lerp(col_top, 0.5 + 0.5 * d.y)
			vertex(centre + d * r * j, (d / r).normalized(), c)
	for i in rings:
		for k in segs:
			var a := base + i * segs + k
			var b := base + i * segs + (k + 1) % segs
			var c := a + segs
			var d := b + segs
			var out := verts[a] - centre
			if i > 0:
				tri(a, b, c, out)
			if i < rings - 1:
				tri(b, d, c, out)


func mesh() -> ArrayMesh:
	var m := ArrayMesh.new()
	if verts.is_empty():
		return m
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = verts
	a[Mesh.ARRAY_NORMAL] = normals
	a[Mesh.ARRAY_COLOR] = colors
	a[Mesh.ARRAY_INDEX] = indices
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return m


## The vertex-coloured material of the props.
static func material(roughness := 0.8, metallic := 0.0, double_sided := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = false
	m.roughness = roughness
	m.metallic = metallic
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
