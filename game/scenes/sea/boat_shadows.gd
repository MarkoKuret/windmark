class_name BoatShadows
extends Node3D
## Drawn boat shadows on the water (water_render.md §4.7) where the sea takes no real shadows (tiers L and M): per
## boat one grid draped on the drawn sea that darkens the water under the boat's hull, mast and sails as projected
## along the sun, soft-edged, never under the hull.
##
## Feed it every frame with update_boat(id, state), where state holds
##   xform        Transform3D, the boat's body frame (x forward, y port, z up, origin at the DWL) to the scene,
##                at the render pose; its origin's height is the plane the shadow lies on (the heave)
##   caster       caster_from_physics(physics sidecar), the same Dictionary every frame
##   sails        PackedVector3Array, the outline points of every sail shown (scene; BoatView.shadow_sails)
##   sail_counts  PackedInt32Array, points per sail
##   own          bool, the player's boat
## and remove_boat(id) when a boat leaves. The geometry runs in the GDExtension (BoatShadowShape, native/src/
## boat_shadow.h) when it is loaded, else (or with use_reference) in build() here; both give the same polygons
## (tests/boat_shadow_test.gd). Every boat's polygons are one row of a small RGBA32F texture (pack_row, read by
## boat_shadow_common.gdshaderinc), uploaded once per frame; all boats share one material and the grid mesh, each
## instance names its row.

const SHADER := preload("res://shaders/boat_shadow.gdshader")
const MAX_POLYS := 8
const MAX_PLANES := 96
const MAX_EXCL := 40
## a boat's row of the data texture (boat_shadow_common.gdshaderinc), texels
const ROW_POLY := 3
const ROW_BOUND := 11
const ROW_PLANE := 19
const ROW_EXCL := 115
const ROW_WIDTH := 160
const GRID_U := 32
const GRID_V := 16
## m around the polygons
const MARGIN := 0.5
## half penumbra: a base for the soft shadow filter, plus half the sun's 0.53 deg disc over the caster's height
const PENUMBRA_BASE := 0.03
const PENUMBRA_K := 0.0047
## the sun's height (sin of 3 deg) under which nothing is drawn
const SUN_MIN_Y := 0.0523
## faded out over the last 20 % of the shadow distance, as the real shadows
const FADE_START := 0.8
## every Nth point of the DWL waterline goes into the hull caster
const WATERLINE_STEP := 8

@export var sea_path: NodePath
@export var sky_path: NodePath

var sea: Sea
## the SkyRig (sun direction); without one, the sea's sun_dir uniform
var sky: Node
## the geometry in GDScript even when the native BoatShadowShape is loaded (tests). Set before the first update.
var use_reference := false
## off: nothing is drawn (the sail scene's --no-drawn-shadows)
var enabled := true

## id -> {mi: MeshInstance3D, slot: its row, state: Dictionary, shape: BoatShadowShape or null, caster: the caster
## the shape was configured with, sun: the sun of the last build, strength: float}
var _boats := {}
static var _grid: ArrayMesh
var _material: ShaderMaterial
var _rows := 0
var _slots: Array[bool] = []
var _row_data: Array[PackedFloat32Array] = []
var _image: Image
var _texture: ImageTexture
var _zero_row := PackedFloat32Array()
var _shader_checked: Shader
var _sea_unshadowed := false


func _ready() -> void:
	if sea == null and not sea_path.is_empty():
		sea = get_node_or_null(sea_path) as Sea
	if sky == null and not sky_path.is_empty():
		sky = get_node_or_null(sky_path)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.render_priority = -1  # before the wakes, mist and bow waves, which take no shadows on tier H either
	_zero_row.resize(ROW_WIDTH * 4)
	_grow(8)


## Whether this node builds the polygons natively.
func is_native() -> bool:
	return not use_reference and ClassDB.class_exists("BoatShadowShape")


func update_boat(id: int, state: Dictionary) -> void:
	if not _boats.has(id):
		var slot := _slots.find(false)
		if slot < 0:
			slot = _rows
			_grow(_rows * 2)
		_slots[slot] = true
		var mi := MeshInstance3D.new()
		mi.name = "Shadow%d" % id
		mi.mesh = grid_mesh()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _material
		mi.set_instance_shader_parameter("shadow_row", float(slot))
		mi.visible = false
		add_child(mi)
		_boats[id] = {"mi": mi, "slot": slot, "shape": null, "caster": null, "sun": Vector3.UP, "strength": 0.0}
	_boats[id]["state"] = state


func remove_boat(id: int) -> void:
	if _boats.has(id):
		_boats[id]["mi"].queue_free()
		_slots[_boats[id]["slot"]] = false
		_row_data[_boats[id]["slot"]] = PackedFloat32Array()
		_boats.erase(id)


## The boat's shadow as last drawn (tests): build()'s Dictionary plus strength, {} when none is drawn.
func shadow_of(id: int) -> Dictionary:
	if not _boats.has(id) or not _boats[id]["mi"].visible:
		return {}
	var b: Dictionary = _boats[id]
	var st: Dictionary = b["state"]
	var d: Dictionary
	if b["shape"] != null:
		d = b["shape"].build(st["xform"], b["sun"], st.get("sails", PackedVector3Array()),
				st.get("sail_counts", PackedInt32Array()))
	else:
		d = build(st["caster"], st["xform"], b["sun"], st.get("sails", PackedVector3Array()),
				st.get("sail_counts", PackedInt32Array()))
	d["strength"] = b["strength"]
	return d


## The boat's shadow mesh instance (tests), null when there is none.
func shadow_node(id: int) -> MeshInstance3D:
	return _boats[id]["mi"] if _boats.has(id) else null


## The shared material and data texture (tests, the offline preview); a boat's row is shadow_slot(id).
func material() -> ShaderMaterial:
	return _material


func shadow_slot(id: int) -> int:
	return _boats[id]["slot"] if _boats.has(id) else -1


## The data texture's rows as last uploaded (RGBA32F, ROW_WIDTH x rows).
func data_image() -> Image:
	return _image


func _grow(rows: int) -> void:
	_rows = rows
	_slots.resize(rows)
	_row_data.resize(rows)
	_image = Image.create_empty(ROW_WIDTH, rows, false, Image.FORMAT_RGBAF)
	_texture = ImageTexture.create_from_image(_image)
	_material.set_shader_parameter("shadow_tex", _texture)


## A build() result as the boat's row of the data texture (the shader's layout, boat_shadow_common), the fade
## strength in texel 0.
static func pack_row(d: Dictionary, strength: float) -> PackedFloat32Array:
	var r := PackedFloat32Array()
	r.resize(ROW_WIDTH * 4)
	var o: Vector3 = d["origin"]
	var sun: Vector3 = d["sun"]
	var put := func(texel: int, v: Vector4) -> void:
		r[4 * texel] = v.x
		r[4 * texel + 1] = v.y
		r[4 * texel + 2] = v.z
		r[4 * texel + 3] = v.w
	put.call(0, Vector4(o.x, o.y, o.z, strength))
	put.call(1, Vector4(sun.x, sun.y, sun.z, d["n_poly"]))
	put.call(2, Vector4(d["n_excl"], 0.0, 0.0, 0.0))
	for i in int(d["n_poly"]):
		put.call(ROW_POLY + i, d["poly"][i])
		put.call(ROW_BOUND + i, d["bound"][i])
	var n_planes := int((d["poly"][int(d["n_poly"]) - 1] as Vector4).x + 0.5) if int(d["n_poly"]) > 0 else 0
	for j in n_planes:
		put.call(ROW_PLANE + j, d["planes"][j])
	for j in int(d["n_excl"]):
		put.call(ROW_EXCL + j, d["excl"][j])
	return r


## The shared grid: GRID_U x GRID_V cells over the unit square of the local (x, z) plane; each boat's transform
## stretches it over its shadow rectangle.
static func grid_mesh() -> ArrayMesh:
	if _grid:
		return _grid
	var v := PackedVector3Array()
	for j in GRID_V + 1:
		for i in GRID_U + 1:
			v.append(Vector3(float(i) / GRID_U, 0.0, float(j) / GRID_V))
	var idx := PackedInt32Array()
	for j in GRID_V:
		for i in GRID_U:
			var a := j * (GRID_U + 1) + i
			idx.append_array([a, a + 1, a + GRID_U + 1, a + 1, a + GRID_U + 2, a + GRID_U + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_INDEX] = idx
	_grid = ArrayMesh.new()
	_grid.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# the drape moves the grid up and down with the waves (the local y is metres)
	_grid.custom_aabb = AABB(Vector3(0.0, -30.0, 0.0), Vector3(1.0, 60.0, 1.0))
	return _grid


## The hull and mast of a class for its shadow (§4.7), in the body frame (x forward, y port, z up), from the
## physics sidecar: the sheer outline, each point at the height of the collision hull there, and every
## WATERLINE_STEP-th point of the DWL. {hull: PackedVector3Array, mast_step, mast_head: Vector3, mast_r: float};
## {} without the data.
static func caster_from_physics(physics: Dictionary) -> Dictionary:
	var outline: Array = physics.get("perf_inputs", {}).get("collision", {}).get("outline", [])
	var verts: Array = physics.get("collision_meshes", {}).get("hull", {}).get("vertices", [])
	if outline.size() < 3 or verts.is_empty():
		return {}
	var hull := PackedVector3Array()
	for o in outline:
		# the deck edge: the highest vertex of the collision hull near the outline point in plan
		var best := INF
		for v in verts:
			best = minf(best, Vector2(v[0] - o[0], v[1] - o[1]).length())
		var z := 0.0
		for v in verts:
			if Vector2(v[0] - o[0], v[1] - o[1]).length() <= best + 0.1:
				z = maxf(z, float(v[2]))
		hull.append(Vector3(o[0], o[1], z))
	var wl: Dictionary = physics.get("waterline", {})
	for side in ["port", "starboard"]:
		var pts: Array = wl.get(side, [])
		for k in range(0, pts.size(), WATERLINE_STEP):
			hull.append(Vector3(pts[k][0], pts[k][1], 0.0))
	var rig: Dictionary = physics.get("rig", {})
	var out := {"hull": hull, "mast_r": 0.0, "mast_step": Vector3.ZERO, "mast_head": Vector3.ZERO}
	if rig.has("mast_step") and rig.has("masthead"):
		out["mast_step"] = Vector3(rig["mast_step"][0], rig["mast_step"][1], rig["mast_step"][2])
		out["mast_head"] = Vector3(rig["masthead"][0], rig["masthead"][1], rig["masthead"][2])
		out["mast_r"] = 0.5 * maxf(float(rig.get("mast_chord", 0.1)), float(rig.get("mast_width", 0.1)))
	return out


## The grid indices of a sail's outline for its shadow (§4.7): luff and leech at the foot, a third, two thirds and
## the head row, mid-chord at the foot, a third and two thirds (row-major, as SailShape.mid()).
static func sail_indices(rows: int, cols: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r1 := roundi((rows - 1) / 3.0)
	var r2 := roundi(2.0 * (rows - 1) / 3.0)
	for i in [0, r1, r2, rows - 1]:
		out.append(i * cols)
		out.append(i * cols + cols - 1)
	for i in [0, r1, r2]:
		out.append(i * cols + (cols - 1) / 2)
	return out


## The shadow polygons of one boat (§4.7); the GDScript reference of the native BoatShadowShape.build.
## caster: caster_from_physics(); xform: body frame to scene; sun: toward the sun (scene, unit); sails: the outline
## points of the sails shown (scene), sail_counts: points per sail. {} when the sun is too low, else
##   origin       Vector3, the boat's (x, z) and the plane height y0; sun: the sun direction used
##   planes, poly, bound, excl: PackedVector4Array of MAX_PLANES, MAX_POLYS, MAX_POLYS, MAX_EXCL (pack_row puts
##                them in the data texture), n_poly, n_excl: int
##   rect         Transform3D of the grid (unit square to the shadow rectangle, on the plane)
##   corners      PackedVector2Array, every polygon's corners relative to the origin (scene x, z), and
##   corner_end   PackedInt32Array, the end of each polygon's corners
static func build(caster: Dictionary, xform: Transform3D, sun: Vector3, sails: PackedVector3Array,
		sail_counts: PackedInt32Array) -> Dictionary:
	if sun.y < SUN_MIN_Y or caster.is_empty():
		return {}
	var o := xform.origin
	var kx := sun.x / sun.y
	var kz := sun.z / sun.y
	var groups: Array[PackedVector3Array] = []
	var hull: PackedVector3Array = xform * (caster["hull"] as PackedVector3Array)
	groups.append(hull)
	var masts := PackedVector3Array()
	if caster["mast_r"] > 0.0:
		masts.append(xform * (caster["mast_step"] as Vector3))
		masts.append(xform * (caster["mast_head"] as Vector3))
	groups.append(masts)
	var at := 0
	for n in sail_counts:
		groups.append(sails.slice(at, at + n))
		at += n
	var planes := PackedVector4Array()
	var poly := PackedVector4Array()
	var bound := PackedVector4Array()
	var corners := PackedVector2Array()
	var corner_end := PackedInt32Array()
	for g in groups.size():
		var pts: PackedVector3Array = groups[g]
		if pts.size() < 2 or poly.size() >= MAX_POLYS:
			continue
		var p2 := PackedVector2Array()
		p2.resize(pts.size())
		var h := 0.0
		for k in pts.size():
			var p: Vector3 = pts[k]
			var dy := p.y - o.y
			p2[k] = Vector2(p.x - o.x - kx * dy, p.z - o.z - kz * dy)
			h += maxf(dy, 0.0)
		h /= pts.size()
		if g == 1:
			# the mast: a strip of its width along the projected spar
			var a: Vector2 = p2[0]
			var b: Vector2 = p2[1]
			var t := (b - a).normalized() if a.distance_to(b) > 1e-4 else Vector2.RIGHT
			var nr := Vector2(-t.y, t.x) * float(caster["mast_r"])
			p2 = PackedVector2Array([a + nr, a - nr, b - nr, b + nr])
		var ring := convex_ring(p2)
		if ring.size() < 3 or planes.size() + ring.size() > MAX_PLANES:
			continue
		var c := Vector2.ZERO
		for q in ring:
			c += q
		c /= ring.size()
		var rad := 0.0
		for q in ring:
			rad = maxf(rad, q.distance_to(c))
		_add_planes(ring, planes)
		corners.append_array(ring)
		corner_end.append(corners.size())
		poly.append(Vector4(planes.size(), PENUMBRA_BASE + PENUMBRA_K * h / sun.y, 0.0, 0.0))
		bound.append(Vector4(c.x, c.y, rad, 0.0))
	# the hull footprint: its points dropped straight down
	var foot := PackedVector2Array()
	foot.resize(hull.size())
	for k in hull.size():
		foot[k] = Vector2(hull[k].x - o.x, hull[k].z - o.z)
	var excl := PackedVector4Array()
	var fring := convex_ring(foot)
	if fring.size() >= 3 and fring.size() <= MAX_EXCL:
		_add_planes(fring, excl)
	# the grid's rectangle: one side along the shadow
	var u := -Vector2(sun.x, sun.z)
	u = u.normalized() if u.length() > 1e-3 else Vector2.RIGHT
	var v := Vector2(-u.y, u.x)
	var lo := Vector2(INF, INF)
	var hi := -lo
	for q in corners + fring:
		var w := Vector2(q.dot(u), q.dot(v))
		lo = lo.min(w)
		hi = hi.max(w)
	var fmax := 0.0
	for p in poly:
		fmax = maxf(fmax, p.y)
	var m := MARGIN + 2.0 * fmax
	lo -= Vector2(m, m)
	hi += Vector2(m, m)
	var n_poly := poly.size()
	var n_excl := excl.size()
	planes.resize(MAX_PLANES)
	poly.resize(MAX_POLYS)
	bound.resize(MAX_POLYS)
	excl.resize(MAX_EXCL)
	var u3 := Vector3(u.x, 0.0, u.y)
	var v3 := Vector3(v.x, 0.0, v.y)
	var rect := Transform3D(Basis(u3 * (hi.x - lo.x), Vector3.UP, v3 * (hi.y - lo.y)),
			Vector3(o.x, o.y, o.z) + u3 * lo.x + v3 * lo.y)
	return {
		"origin": o, "sun": sun, "planes": planes, "poly": poly, "bound": bound, "n_poly": n_poly, "excl": excl,
		"n_excl": n_excl, "rect": rect, "corners": corners, "corner_end": corner_end,
	}


## The convex hull of points, counter-clockwise in (x, z) seen with x right and z up, without the closing point.
static func convex_ring(p: PackedVector2Array) -> PackedVector2Array:
	var h := Geometry2D.convex_hull(p)
	if h.size() > 1 and h[0] == h[h.size() - 1]:
		h.resize(h.size() - 1)
	return h


## Edge lines (outward unit normal, offset) of a counter-clockwise ring.
static func _add_planes(ring: PackedVector2Array, out: PackedVector4Array) -> void:
	for k in ring.size():
		var a := ring[k]
		var b := ring[(k + 1) % ring.size()]
		var e := b - a
		var n := Vector2(e.y, -e.x)
		var l := n.length()
		if l < 1e-6:
			n = (a - _centre(ring)).normalized()
		else:
			n /= l
		out.append(Vector4(n.x, n.y, n.dot(a), 0.0))


static func _centre(ring: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for q in ring:
		c += q
	return c / maxf(ring.size(), 1)


## The shader's coverage (wm_boat_shadow) at the water point P (scene) for a build() result, on the CPU (tests).
static func coverage(d: Dictionary, P: Vector3, px := 0.0, strength := 1.0) -> float:
	if d.is_empty():
		return 0.0
	var o: Vector3 = d["origin"]
	var q := Vector2(P.x - o.x, P.z - o.z)
	var sun: Vector3 = d.get("sun", Vector3.UP)
	var r := q + Vector2(sun.x, sun.z) * ((o.y - P.y) / maxf(sun.y, 0.05))
	var s := 0.0
	var k := 0
	for i in int(d["n_poly"]):
		var pl: Vector4 = d["poly"][i]
		var j_end := int(pl.x + 0.5)
		var f := pl.y + px
		var b: Vector4 = d["bound"][i]
		if r.distance_to(Vector2(b.x, b.y)) - b.z < f:
			var dist := -1e6
			for j in range(k, j_end):
				var e: Vector4 = d["planes"][j]
				dist = maxf(dist, e.x * r.x + e.y * r.y - e.z)
			s = maxf(s, 1.0 - smoothstep(-f, f, dist))
		k = j_end
	if s > 0.0 and int(d["n_excl"]) > 0:
		var dist := -1e6
		for j in int(d["n_excl"]):
			var e: Vector4 = d["excl"][j]
			dist = maxf(dist, e.x * q.x + e.y * q.y - e.z)
		s *= smoothstep(-0.04, 0.0, dist)
	return s * strength




func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_frame()
	PerfStats.add(&"wakes", Time.get_ticks_usec() - t0)


## Whether the sea's shader takes no shadows (it defines WM_NO_SHADOWS): only then are shadows drawn.
func _sea_takes_no_shadows() -> bool:
	var sh := sea.material.shader if sea and sea.material else null
	if sh != _shader_checked:
		_shader_checked = sh
		_sea_unshadowed = sh != null and sh.code.contains("WM_NO_SHADOWS")
	return _sea_unshadowed


## The boats that get a drawn shadow on this tier and their strength: the own boat always (1), the nearest
## others within the shadow distance of the camera, faded over its last 20 %. id -> strength.
func select(tier: Dictionary, cam: Vector3) -> Dictionary:
	var out := {}
	var n: int = int(tier.get("drawn_shadow_boats", 0)) if enabled and _sea_takes_no_shadows() else 0
	if n <= 0:
		return out
	var rmax: float = tier["shadow_distance"]
	var others := []
	for id in _boats:
		var st: Dictionary = _boats[id].get("state", {})
		if st.is_empty():
			continue
		if st.get("own", false):
			out[id] = 1.0
		else:
			others.append([(st["xform"] as Transform3D).origin.distance_to(cam), id])
	others.sort_custom(func(a, b): return a[0] < b[0])
	n -= out.size()
	for e in others:
		if n <= 0 or e[0] >= rmax:
			break
		out[e[1]] = 1.0 - smoothstep(FADE_START * rmax, rmax, e[0])
		n -= 1
	return out


func _frame() -> void:
	if sea == null or sea.material == null:
		for id in _boats:
			_boats[id]["mi"].visible = false
		return
	var tier := sea.get_tier()
	var cam_node: Camera3D = sea.camera if sea.camera else get_viewport().get_camera_3d()
	var cam := cam_node.global_position if cam_node else Vector3(sea.origin.x, 0.0, -sea.origin.y)
	var active := select(tier, cam)
	# the Sea hands its sky's sun to the water every frame (the cheaper read)
	var sun_v: Variant = sea.material.get_shader_parameter("sun_dir") if sea.sky or sky == null \
			else sky.sun_direction()
	var sun: Vector3 = sun_v if sun_v is Vector3 else Vector3(0.0, 0.5, -0.866)
	sun = sun.normalized()
	var nat := is_native()
	var drawn := 0
	for id in _boats:
		var b: Dictionary = _boats[id]
		var mi: MeshInstance3D = b["mi"]
		var slot: int = b["slot"]
		if not active.has(id):
			mi.visible = false
			_row_data[slot] = PackedFloat32Array()
			continue
		var st: Dictionary = b["state"]
		var sails: PackedVector3Array = st.get("sails", PackedVector3Array())
		var counts: PackedInt32Array = st.get("sail_counts", PackedInt32Array())
		var row := PackedFloat32Array()
		var rect := Transform3D.IDENTITY
		if nat:
			if b["shape"] == null or not is_same(b["caster"], st["caster"]):
				b["shape"] = ClassDB.instantiate("BoatShadowShape")
				b["shape"].configure(st["caster"])
				b["caster"] = st["caster"]
			row = b["shape"].build_row(st["xform"], sun, sails, counts, active[id])
			rect = b["shape"].last_rect()
		else:
			b["shape"] = null
			var d := build(st["caster"], st["xform"], sun, sails, counts)
			if not d.is_empty():
				row = pack_row(d, active[id])
				rect = d["rect"]
		b["sun"] = sun
		b["strength"] = active[id]
		_row_data[slot] = row
		mi.visible = not row.is_empty()
		if mi.visible:
			mi.transform = rect
			drawn += 1
	if drawn == 0:
		return
	# one upload of every row, and the sea's uniforms the drape needs, once for all boats
	var buf := PackedFloat32Array()
	for r in _row_data:
		buf.append_array(r if not r.is_empty() else _zero_row)
	_image.set_data(ROW_WIDTH, _rows, false, Image.FORMAT_RGBAF, buf.to_byte_array())
	_texture.update(_image)
	for n in SeaWakes.SHARED_UNIFORMS:
		_material.set_shader_parameter(n, sea.material.get_shader_parameter(n))
	for n in ["sky_horizon", "sky_zenith", "sun_color"]:
		_material.set_shader_parameter(n, sea.material.get_shader_parameter(n))
	_material.set_shader_parameter("grid_q", sea.grid_ratio())
	_material.set_shader_parameter("grid_segments", float(tier["segments"]))
