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
## the helmsman's gaze below the horizon at rest (rad, positive down; the horizon stays level)
var look_down := 0.0

## cameras.md §3, the helmsman's eyes. Tiller: sitting on the windward side deck just forward of the tiller's end
## (hand on the extension), seated eye height above the deck. Wheel: standing on the cockpit floor behind the
## windward half of the rim, standing eye height, looking forward over the rim.
const TILLER_AHEAD := 0.15  # m forward of the tiller's end
const TILLER_OUT := 0.9  # of the deck's half-beam
const EYE_SEATED := 0.80  # m, seated eye height (adult, upright on the deck edge)
const WHEEL_BEHIND := 0.7  # of the rim radius, aft of the wheel's plane
const WHEEL_OUT := 0.55  # of the rim radius, to windward of the centreline
const EYE_STANDING := 1.60  # m, standing eye height (adult)
const WHEEL_LOOK_DOWN := deg_to_rad(8.0)
const TILLER_LOOK_DOWN := deg_to_rad(4.0)


## `model` is the imported boat root (the GLB's child named after the class) or null; without a deck mesh the
## deck is estimated from the class beam, without a wheel or tiller mesh from the class length.
static func onboard(info: SimSource.ClassInfo, model: Node3D) -> BoatGeometry:
	var g := BoatGeometry.new()
	var rig: Dictionary = info.physics.get("rig", {})
	var wheel := info.steering == "wheel" and rig.has("wheel_hub")
	var tris := _deck_triangles(model)
	if wheel:
		var r := _rim_radius(model)
		if r <= 0.0:
			r = 0.07 * info.loa
		g.xh = float(rig["wheel_hub"][0]) - WHEEL_BEHIND * r
		# twin wheels: behind the windward one (its hub off the centreline)
		g.yh_abs = absf(float(rig["wheel_hub"][1])) + WHEEL_OUT * r
		g.look_down = WHEEL_LOOK_DOWN
	else:
		var box := _part_box(model, "rudder")  # the rudder carries the tiller: its forward end is the tiller's
		var stock := float(rig["rudder_stock"][0]) if rig.has("rudder_stock") else -0.5 * info.loa
		var tip := box.end.x if box.size.x > 0.0 else stock + 0.13 * info.loa
		g.xh = tip + TILLER_AHEAD
		g.look_down = TILLER_LOOK_DOWN
	g.deck_half_beam = _half_beam(tris, g.xh) if tris.size() > 0 else 0.45 * info.beam_max
	if not wheel:
		g.yh_abs = TILLER_OUT * g.deck_half_beam
	var deck := _deck_height(tris, g.xh, g.yh_abs) if tris.size() > 0 else 0.6
	g.zh = deck + (EYE_STANDING if wheel else EYE_SEATED)
	return g


## the body-frame box of the meshes under the model's node `part` (at rest), empty without it
static func _part_box(model: Node3D, part: String) -> AABB:
	if model == null:
		return AABB()
	var n := model.find_child(part, true, false)
	if n == null:
		return AABB()
	var box := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		stack.append_array(c.get_children())
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var a: AABB = _relative(model, mi) * mi.get_aabb()
		var b := AABB(Vector3(a.position.z, a.position.x, a.position.y), Vector3(a.size.z, a.size.x, a.size.y))
		box = b if first else box.merge(b)
		first = false
	return box


## the wheel's rim radius: half the largest extent of its mesh in its own frame (so turning it changes nothing)
static func _rim_radius(model: Node3D) -> float:
	var n := model.find_child("wheel", true, false) if model != null else null
	var r := 0.0
	var stack: Array = [n] if n != null else []
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		stack.append_array(c.get_children())
		var mi := c as MeshInstance3D
		if mi != null and mi.mesh != null:
			var sc := _relative(model, mi).basis.get_scale()
			var sz := mi.get_aabb().size * sc
			r = maxf(r, 0.5 * maxf(sz.x, maxf(sz.y, sz.z)))
	return r


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
