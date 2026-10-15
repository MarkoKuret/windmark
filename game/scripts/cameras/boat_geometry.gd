class_name BoatGeometry
extends RefCounted
## Onboard eye point of a class (cameras.md §3), computed once at load from the generated model's deck mesh and
## the physics sidecar's rig points. Body frame: x forward, y port, z up.

## eye x, the eye's |y| (yh_abs) and eye z, body frame
var xh := 0.0
var yh_abs := 0.0
var zh := 0.0
## half-beam of the deck at xh (the deck edge)
var deck_half_beam := 0.0

## cameras.md §3: tiller, the eye this fraction of loa forward of the transom, sitting; wheel, this fraction of loa
## aft of the wheel hub, standing (m above the deck)
const TILLER_FROM_TRANSOM := 0.05
const WHEEL_AFT := 0.08
const EYE_SITTING := 1.0
const EYE_STANDING := 1.65


## `model` is the imported boat root (the GLB's child named after the class) or null; without a deck mesh the
## deck is estimated from the class beam.
static func onboard(info: SimSource.ClassInfo, model: Node3D) -> BoatGeometry:
	var g := BoatGeometry.new()
	var rig: Dictionary = info.physics.get("rig", {})
	var wheel := info.steering == "wheel" and rig.has("wheel_hub")
	var tris := _deck_triangles(model)
	if wheel:
		g.xh = float(rig["wheel_hub"][0]) - WHEEL_AFT * info.loa
	else:
		g.xh = (_aft_end(tris) if tris.size() > 0 else -0.5 * info.loa) + TILLER_FROM_TRANSOM * info.loa
	g.deck_half_beam = _half_beam(tris, g.xh) if tris.size() > 0 else 0.45 * info.beam_max
	g.yh_abs = 0.85 * g.deck_half_beam
	var deck := _deck_height(tris, g.xh, g.yh_abs) if tris.size() > 0 else 0.6
	g.zh = deck + (EYE_STANDING if wheel else EYE_SITTING)
	return g


## the aft end of the deck (the transom), body x
static func _aft_end(tris: PackedVector3Array) -> float:
	var x := INF
	for p in tris:
		x = minf(x, p.x)
	return x


## deck triangles in body coordinates
static func _deck_triangles(model: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	if model == null:
		return out
	# the deck node, or the deck part of the merged body (BoatMaterials.part_surfaces, in the model's frame)
	for e in BoatMaterials.part_surfaces(model, "deck"):
		var verts: PackedVector3Array = e["positions"]
		var idx: PackedInt32Array = e["indices"]
		for k in idx.size():
			var m := verts[idx[k]]
			out.append(Vector3(m.z, m.x, m.y))  # model (port, up, bow) -> body (x, y, z)
	return out


static func _relative(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


## largest |y| of the deck within 0.15 m of x
static func _half_beam(tris: PackedVector3Array, x: float) -> float:
	var best := 0.0
	for p in tris:
		if absf(p.x - x) < 0.15:
			best = maxf(best, absf(p.y))
	return best


## height of the deck under (x, y): the highest crossing of a vertical line with the deck triangles
static func _deck_height(tris: PackedVector3Array, x: float, y: float) -> float:
	var best := -INF
	var i := 0
	while i + 2 < tris.size():
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		i += 3
		var den := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
		if absf(den) < 1e-12:
			continue
		var w1 := ((b.y - c.y) * (x - c.x) + (c.x - b.x) * (y - c.y)) / den
		var w2 := ((c.y - a.y) * (x - c.x) + (a.x - c.x) * (y - c.y)) / den
		var w3 := 1.0 - w1 - w2
		if w1 < -1e-6 or w2 < -1e-6 or w3 < -1e-6:
			continue
		best = maxf(best, w1 * a.z + w2 * b.z + w3 * c.z)
	return best if best > -INF else 0.6
