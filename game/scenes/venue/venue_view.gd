class_name VenueView
extends Node3D
## The venue's land and obstacles drawn where the core has them (data_format.md §6.5): every land polygon as a
## terrain mesh (LandTerrain: pebble beaches and low rocky shores whose waterline stays on or inside the
## polygon, low hills with dry grass, maquis and pines), every polygon obstacle as a concrete quay (a pier or a
## mole, with bollards and a harbour light at its seaward end) and every circle obstacle as a rock whose
## waterline is the circle. Presentation only; the cameras read the same ground through ground_height().
##
##   var v := VenueView.new(); add_child(v); v.build(VenueShapes.from_core(sim.core))

const GRID := 5.0
const QUAY_TOP := 1.3
const QUAY_FOOT := -4.0
const ROCK_HEIGHT := 3.4

var shapes: VenueShapes
var terrain: LandTerrain
## the MeshInstance3D nodes by role (tests, previews): land_<id>, trees_<id>, quay_<id>, rock_<id>
var parts := {}

var _land_material: ShaderMaterial
var _quay_tops: Array = []  # [{points, top}] for ground_height


func build(s: VenueShapes) -> void:
	for c in get_children():
		c.queue_free()
	parts.clear()
	_quay_tops.clear()
	shapes = s
	terrain = LandTerrain.new(s)
	_land_material = ShaderMaterial.new()
	_land_material.shader = load("res://scenes/venue/land.gdshader")
	for i in s.land.size():
		_build_land(i)
	var rng := RandomNumberGenerator.new()
	for o in s.obstacles:
		rng.seed = hash(o["id"])
		if o["circle"]:
			_build_rock(o, rng)
		else:
			_build_quay(o)


## Height of the drawn ground (land, quays, rocks) at a world point, -INF where there is only water
## (cameras.md §7 land avoidance).
func ground_height(x: float, y: float) -> float:
	if shapes == null:
		return -INF
	var p := Vector2(x, y)
	var h := terrain.height(x, y)
	for q in _quay_tops:
		if Geometry2D.is_point_in_polygon(p, q["points"]):
			h = maxf(h, q["top"])
	for o in shapes.obstacles:
		if o["circle"]:
			var d := p.distance_to(o["c"])
			if d < o["r"]:
				h = maxf(h, ROCK_HEIGHT * pow(1.0 - (d / o["r"]) * (d / o["r"]), 0.7))
	return h


func _add(n: String, mesh: Mesh, mat: Material, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	parts[n] = mi
	return mi


# ---- land -----------------------------------------------------------------------------------------------------

func _build_land(i: int) -> void:
	var id: String = shapes.land[i]["id"]
	var box := shapes.land_box(i).grow(LandTerrain.MARGIN - GRID)
	var nx := int(ceil(box.size.x / GRID)) + 1
	var ny := int(ceil(box.size.y / GRID)) + 1
	var hs := PackedFloat32Array()
	hs.resize(nx * ny)
	var samples := []
	samples.resize(nx * ny)
	for j in ny:
		for k in nx:
			var p := box.position + Vector2(k * GRID, j * GRID)
			var s := terrain.sample(i, p)
			samples[j * nx + k] = s
			hs[j * nx + k] = s["h"]
	var m := ColorMesh.new()
	var index := PackedInt32Array()
	index.resize(nx * ny)
	for j in ny:
		for k in nx:
			var h := hs[j * nx + k]
			var dx := (hs[j * nx + mini(k + 1, nx - 1)] - hs[j * nx + maxi(k - 1, 0)]) / (2.0 * GRID)
			var dy := (hs[mini(j + 1, ny - 1) * nx + k] - hs[maxi(j - 1, 0) * nx + k]) / (2.0 * GRID)
			var n := Vector3(-dx, 1.0, dy).normalized()
			var p := box.position + Vector2(k * GRID, j * GRID)
			index[j * nx + k] = m.vertex(Frames.enu_to_scene(p.x, p.y, h), n,
				terrain.color(p, samples[j * nx + k], n.y))
	for j in ny - 1:
		for k in nx - 1:
			var a := j * nx + k
			var b := a + 1
			var c := a + nx
			var d := c + 1
			if maxf(maxf(hs[a], hs[b]), maxf(hs[c], hs[d])) < -2.5:
				continue  # deep water: never seen through the opaque sea
			m.tri(index[a], index[b], index[d], Vector3.UP)
			m.tri(index[a], index[d], index[c], Vector3.UP)
	_add("land_" + id, m.mesh(), _land_material)
	_build_trees(i, id, box, nx, ny, hs)


## Stone pines on the gentle upper ground and maquis shrubs, placed by a seeded generator and the terrain noise.
func _build_trees(i: int, id: String, box: Rect2, nx: int, ny: int, hs: PackedFloat32Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) ^ 0x5eed
	var m := ColorMesh.new()
	var trunk := Color(0.09, 0.065, 0.045)
	var crown_top := Color(0.055, 0.085, 0.03)
	var crown_low := Color(0.02, 0.035, 0.012)
	var shrub_top := Color(0.05, 0.07, 0.025)
	var shrub_low := Color(0.018, 0.028, 0.01)
	var area := box.size.x * box.size.y
	var tries := int(area / 180.0)
	for t in tries:
		var p := box.position + Vector2(rng.randf() * box.size.x, rng.randf() * box.size.y)
		var s := terrain.sample(i, p)
		var e: float = s["e"]
		var h: float = s["h"]
		if e < LandTerrain.BEACH_WIDTH + 8.0 or h < 2.5:
			continue
		var k := clampi(int((p.x - box.position.x) / GRID), 1, nx - 2)
		var j := clampi(int((p.y - box.position.y) / GRID), 1, ny - 2)
		var slope := Vector2(hs[j * nx + k + 1] - hs[j * nx + k - 1], hs[(j + 1) * nx + k] - hs[(j - 1) * nx + k]).length() / (2.0 * GRID)
		if slope > 0.45:
			continue
		var dens := terrain.mid_noise(p * 1.7) + 0.25 * (h / terrain.hill_height)
		var base := Frames.enu_to_scene(p.x, p.y, h - 0.3)
		if dens > 0.12 and rng.randf() < 0.55:
			var th := rng.randf_range(7.0, 12.5)
			m.cylinder(base, 0.28, 0.18, th * 0.78, 6, trunk)
			var cr := rng.randf_range(2.8, 4.6)
			var tint := rng.randf_range(0.85, 1.15)
			m.blob(base + Vector3(rng.randf_range(-0.6, 0.6), th * 0.83, rng.randf_range(-0.6, 0.6)),
				Vector3(cr, cr * rng.randf_range(0.42, 0.55), cr * rng.randf_range(0.85, 1.1)), 4, 9,
				crown_top * tint, crown_low * tint, rng, 0.2)
		elif dens > -0.35 and rng.randf() < 0.45:
			var sr := rng.randf_range(0.9, 2.1)
			m.blob(base + Vector3(0, sr * 0.3, 0), Vector3(sr, sr * 0.6, sr * rng.randf_range(0.8, 1.2)), 3, 7,
				shrub_top, shrub_low, rng, 0.25)
	var mat := ColorMesh.material(0.95)
	_add("trees_" + id, m.mesh(), mat)


# ---- obstacles ------------------------------------------------------------------------------------------------

## A concrete quay on a convex polygon: vertical walls from QUAY_FOOT to QUAY_TOP with a dark wet band, a
## slightly darker deck, a low curb, bollards along the long sides and a light at the seaward end.
func _build_quay(o: Dictionary) -> void:
	var pts: PackedVector2Array = o["points"]
	var n := pts.size()
	var m := ColorMesh.new()
	var wall := Color(0.30, 0.29, 0.26)
	var wet := Color(0.06, 0.06, 0.05)
	var weed := Color(0.05, 0.07, 0.035)
	var deck := Color(0.34, 0.33, 0.30)
	var c := LandTerrain._centroid(pts)
	for k in n:
		var a := pts[k]
		var b := pts[(k + 1) % n]
		var out := Frames.enu_to_scene(a.x + b.x - 2.0 * c.x, a.y + b.y - 2.0 * c.y, 0.0).normalized()
		var bands := [[QUAY_FOOT, -0.3, weed], [-0.3, 0.45, wet], [0.45, QUAY_TOP, wall]]
		for bd in bands:
			m.quad(Frames.enu_to_scene(a.x, a.y, bd[0]), Frames.enu_to_scene(b.x, b.y, bd[0]),
				Frames.enu_to_scene(b.x, b.y, bd[1]), Frames.enu_to_scene(a.x, a.y, bd[1]), bd[2], out)
	# deck: a fan from the centroid (the polygon is convex)
	var ci := m.vertex(Frames.enu_to_scene(c.x, c.y, QUAY_TOP), Vector3.UP, deck)
	var ring := []
	for k in n:
		ring.append(m.vertex(Frames.enu_to_scene(pts[k].x, pts[k].y, QUAY_TOP), Vector3.UP, deck))
	for k in n:
		m.tri(ci, ring[k], ring[(k + 1) % n], Vector3.UP)
	# curb along every edge, inset 0.25 m
	for k in n:
		var a := pts[k]
		var b := pts[(k + 1) % n]
		var ab := b - a
		var len := ab.length()
		var mid := (a + b) * 0.5
		var inward := (c - mid).normalized() * 0.2
		var xf := Transform3D(Basis(Vector3.UP, atan2(ab.y, ab.x)),
			Frames.enu_to_scene(mid.x + inward.x, mid.y + inward.y, QUAY_TOP + 0.12))
		m.box(xf, Vector3(len, 0.24, 0.3), wall)
	# bollards and the light: along the two longest edges; the light at the end farthest from land
	var edges := []
	for k in n:
		edges.append([pts[k].distance_to(pts[(k + 1) % n]), k])
	edges.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	var iron := Color(0.02, 0.02, 0.02)
	for ed in edges.slice(0, mini(2, n)):
		var a := pts[ed[1]]
		var b := pts[(ed[1] + 1) % n]
		var count := int(floor(ed[0] / 11.0))
		for q in count:
			var p := a.lerp(b, (q + 0.5) / count)
			p += (c - p).normalized() * 0.7
			m.cylinder(Frames.enu_to_scene(p.x, p.y, QUAY_TOP), 0.22, 0.16, 0.55, 8, iron)
	var far := pts[0]
	var far_d := INF
	for k in n:
		var mid := (pts[k] + pts[(k + 1) % n]) * 0.5
		var d := _land_distance(mid)
		if d < far_d:
			far_d = d
			far = mid
	far += (c - far).normalized() * 2.0
	var white := Color(0.75, 0.75, 0.72)
	var green := Color(0.02, 0.28, 0.08)
	var base := Frames.enu_to_scene(far.x, far.y, QUAY_TOP)
	m.cylinder(base, 0.75, 0.55, 3.6, 12, white)
	m.cylinder(base + Vector3(0, 3.6, 0), 0.55, 0.5, 1.1, 12, green)
	m.cylinder(base + Vector3(0, 4.7, 0), 0.32, 0.32, 0.55, 8, Color(0.6, 0.75, 0.55))
	m.cylinder(base + Vector3(0, 5.25, 0), 0.42, 0.05, 0.35, 8, green)
	_quay_tops.append({"points": pts, "top": QUAY_TOP})
	_add("quay_" + String(o["id"]), m.mesh(), ColorMesh.material(0.85))


func _land_distance(p: Vector2) -> float:
	var best := -INF
	for i in shapes.land.size():
		best = maxf(best, shapes.land_distance(i, p))
	return best


## A limestone rock on a circle obstacle: its waterline is the circle (the collision shape), a rounded top of
## about ROCK_HEIGHT m with noisy facets, dark wet stone near the water.
func _build_rock(o: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector2 = o["c"]
	var r: float = o["r"]
	var m := ColorMesh.new()
	var rings := 9
	var segs := 28
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.35
	var stone := Color(0.33, 0.32, 0.29)
	var pale := Color(0.45, 0.43, 0.39)
	var wet := Color(0.05, 0.05, 0.045)
	var height_k := rng.randf_range(0.85, 1.15)
	var grid := []
	# ring 0 is the top; ring `rings` the waterline; two more rings slope under the water to 1.35 r
	for i in rings + 3:
		var row := []
		for k in segs:
			var a := TAU * k / segs
			var u := minf(float(i) / rings, 1.0)
			var rr: float
			var h: float
			var wob := 0.5 if i == 0 else 0.5 + 0.5 * noise.get_noise_2d(cos(a) * 3.0, sin(a) * 3.0 + i * 0.7)
			if i <= rings:
				rr = r * u * (1.0 - 0.13 * wob * u)  # stays inside the circle
				h = ROCK_HEIGHT * height_k * pow(maxf(1.0 - u * u, 0.0), 0.7) * (0.8 + 0.4 * wob)
			else:
				rr = r * (1.0 + 0.18 * (i - rings))
				h = -1.4 * (i - rings)
			var p := c + Vector2(cos(a), sin(a)) * rr
			row.append([Frames.enu_to_scene(p.x, p.y, h), h, wob])
		grid.append(row)
	for i in rings + 2:
		for k in segs:
			var q := [grid[i][k], grid[i][(k + 1) % segs], grid[i + 1][(k + 1) % segs], grid[i + 1][k]]
			var hmean: float = (q[0][1] + q[1][1] + q[2][1] + q[3][1]) * 0.25
			var col := stone.lerp(pale, clampf(q[0][2] * 1.2 - 0.1, 0.0, 1.0))
			col = col.lerp(wet, 1.0 - LandTerrain._smooth(0.1, 0.7, hmean))
			var centre := Frames.enu_to_scene(c.x, c.y, -2.0)
			var mid: Vector3 = (q[0][0] + q[2][0]) * 0.5
			if i == 0:
				m.flat_tri(q[0][0], q[2][0], q[3][0], col, mid - centre)
			else:
				m.flat_tri(q[0][0], q[1][0], q[2][0], col, mid - centre)
				m.flat_tri(q[0][0], q[2][0], q[3][0], col, mid - centre)
	_add("rock_" + String(o["id"]), m.mesh(), ColorMesh.material(0.9))
