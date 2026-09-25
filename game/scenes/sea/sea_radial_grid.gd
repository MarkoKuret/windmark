class_name SeaRadialGrid
extends RefCounted
## The camera-centred radial grid of water_render.md §3.1: a centre fan and n_rings rings of n_segments at
## geometric radii r_k = r0 * q^k up to r_max. UV.x holds the local vertex spacing s (m) for the wave fade of
## §3.2. The mesh lies in the node's XZ plane (scene axes, Y up); the vertex shader sets the height.

const R0 := 0.6
const R_MAX := 24000.0


static func ratio(n_rings: int, r0: float = R0, r_max: float = R_MAX) -> float:
	return pow(r_max / r0, 1.0 / float(n_rings - 1))


## Spacing used for the fade at ring radius r: the larger of the radial and the tangential spacing.
static func spacing(r: float, q: float, n_segments: int) -> float:
	return maxf(r * (q - 1.0), TAU * r / float(n_segments))


static func build(n_rings: int, n_segments: int, r0: float = R0, r_max: float = R_MAX) -> ArrayMesh:
	var q := ratio(n_rings, r0, r_max)
	var n := 1 + n_rings * n_segments
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	verts.resize(n)
	uvs.resize(n)
	normals.resize(n)
	verts[0] = Vector3.ZERO
	uvs[0] = Vector2(r0, 0.0)
	normals[0] = Vector3.UP
	var cs := PackedFloat64Array()
	var sn := PackedFloat64Array()
	cs.resize(n_segments)
	sn.resize(n_segments)
	for j in n_segments:
		var a := TAU * j / n_segments
		cs[j] = cos(a)
		sn[j] = sin(a)
	for k in n_rings:
		var r := r0 * pow(q, k)
		var s := spacing(r, q, n_segments)
		if k == 0:
			s = maxf(s, r0)
		for j in n_segments:
			var v := 1 + k * n_segments + j
			verts[v] = Vector3(r * cs[j], 0.0, r * sn[j])
			uvs[v] = Vector2(s, float(k))
			normals[v] = Vector3.UP
	# Clockwise seen from above (+Y) is front-facing in Godot: angle grows from +X toward +Z.
	var idx := PackedInt32Array()
	idx.resize(3 * n_segments + 6 * (n_rings - 1) * n_segments)
	var w := 0
	for j in n_segments:
		var j1 := (j + 1) % n_segments
		idx[w] = 0
		idx[w + 1] = 1 + j
		idx[w + 2] = 1 + j1
		w += 3
	for k in n_rings - 1:
		var a0 := 1 + k * n_segments
		var b0 := a0 + n_segments
		for j in n_segments:
			var j1 := (j + 1) % n_segments
			idx[w] = a0 + j
			idx[w + 1] = b0 + j
			idx[w + 2] = b0 + j1
			idx[w + 3] = a0 + j
			idx[w + 4] = b0 + j1
			idx[w + 5] = a0 + j1
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
