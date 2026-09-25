class_name SailGrid
## Maps the vertices of an imported boatgen sail mesh back to the sail grid.
##
## boatgen writes each sail as a regular grid (rows from foot to head, columns from luff to leech) in two layers,
## port layer first, and the physics sidecar describes deformation in that order. Godot's glTF importer does
## not keep the vertex order: it re-indexes every surface, so vertices come out in order of first use by the
## triangles and unreferenced ones are dropped. The grid position is still in the data: uv1 is
## (chord fraction, 1 - height fraction), mirrored in u on the starboard layer, and the flat sail's port layer
## lies on +X. This rebuilds the index from those.


## For each vertex of `mesh` surface `surface`, its grid index `layer * rows * cols + row * cols + col`
## (layer 0 = port), or -1 when the vertex does not sit on a grid node. Call it on the flat sail as imported.
static func grid_index(mesh: Mesh, rows: int, cols: int, surface: int = 0) -> PackedInt32Array:
	var arrays := mesh.surface_get_arrays(surface)
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv1: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var out := PackedInt32Array()
	out.resize(pos.size())
	for i in pos.size():
		var layer := 0 if pos[i].x > 0.0 else 1
		var u := uv1[i].x if layer == 0 else 1.0 - uv1[i].x
		var fc := u * (cols - 1)
		var fr := (1.0 - uv1[i].y) * (rows - 1)
		var col := roundi(fc)
		var row := roundi(fr)
		# uv1 is exact to float precision in the file; the importer stores it in 16 bits, so allow a small
		# fraction of a cell.
		if absf(fc - col) > 0.05 or absf(fr - row) > 0.05 or col < 0 or col >= cols or row < 0 or row >= rows:
			out[i] = -1
		else:
			out[i] = layer * rows * cols + row * cols + col
	return out
