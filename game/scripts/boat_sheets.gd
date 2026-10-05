class_name BoatSheets
extends RefCounted
## The running sheets of one boat (docs/specs/sail_visuals.md §11.3): the jib or genoa sheets, the flying sail's
## sheets (or sheet and guy) and the tack line, from the placed clew through the lead blocks of the sidecar's
## `rig.sheet_leads` to the winches, with the sag of their tension, the swing and whip of a flogging sail, the flying
## sail's lines routed outside the main, the boom, the headsail and the rail, the lazy sheets draped on the deck, and
## the fixed turns on the drums and the tails. One mesh per boat with two surfaces
## (headsail lines, flying-sail lines), written in place by the native SheetRopes (SheetRopesRef without the
## GDExtension, rebuilding the mesh). BoatView owns it: `setup` at load, `advance` every frame, `update` when a sail
## was redrawn, `set_detail` with the boat's level of detail.

const TAU_SAG := 0.3
const LAZY_SAG := 0.22
## the deepest a lazy line hangs below its straight run (m): a long kite sheet loops, it does not trail in the sea
const LAZY_DEPTH := 0.5
## how far across the centreline (m) the clew is when a lazy line runs fully round its obstacle
const WAY_REACH := 0.4
## the deck height field (§11.3 "Deck"): grid (m), the cells it reaches out over the hull side (a line drapes over the
## rail), the cells it is widened by (more than the drape's step), the tallest fitting it counts (m above the deck)
const DECK_CELL := 0.025
const DECK_SKIRT := 8
const DECK_DILATE := 1
const FIT_MAX := 0.07
## §11.3 "Outside route": the rail's station step (m), the margin of the sails and the boom (m, plus the rope
## diameter), the rail's margin (m, plus the rope radius) and its fade forward of the lead (m), the pivot's offset to
## the other side (of the beam), the waypoints of a working line and of each leg of a lazy one
const RAIL_STEP := 0.1
const SAIL_MARGIN := 0.05
const RAIL_MARGIN := 0.01
const RAIL_FADE := 0.6
const PIVOT_SIDE := 0.15
const WAYS_WORK := 12
const WAYS_LEG := 7
const LAZY_SHIVER := 0.3
const T_MIN := 5.0
const RHO := 1.225
const G := 9.81
const SIDES := [6, 4]
## rings per line by detail level: free run, lead run; the drum turns and tail only at level 0
const FREE_RINGS := [16, 8]
const LEAD_RINGS := [4, 2]
const DRUM_RINGS := 24
const TURNS := 3.0
const TILE := 0.05

enum Surface { HEADSAIL, FLYING }

## the class's deck height fields (class id -> {"heights", "origin", "cell", "nx", "nz"})
static var _decks := {}

var bv: BoatView
var mesh: ArrayMesh
var node: MeshInstance3D
## per surface: the SheetRopes (or SheetRopesRef), its line descriptions and the lines' eased sag (free, lead)
var shapes: Array = [null, null]
var line_specs: Array = [[], []]
var sag := [PackedFloat32Array(), PackedFloat32Array()]
var detail := 0
var native := false
var use_reference := false
## drawn this update (tests): per surface the starts, waypoints and drive
var last_starts: Array = [PackedVector3Array(), PackedVector3Array()]
var last_ways: Array = [PackedVector3Array(), PackedVector3Array()]
var last_drive: Array = [PackedFloat32Array(), PackedFloat32Array()]
## the sail each surface follows this update (null: none shown)
var followed: Array = [null, null]
var updates := 0

var _last_aws := 0.0
## per surface the lines' sag targets (free, lead) of the last redraw
var _targets: Array = [PackedFloat32Array(), PackedFloat32Array()]
var _r := 0.005
var _s := 1.0
var _leads := {}
var _mast_front := Vector3.ZERO
var _stay_front := Vector3.ZERO
var _sprit_end := Vector3.ZERO
var _has_sprit := false
var _pole := false
var _areas := {}
var _deck := {}
## the rail of the outside route per side (0 starboard, 1 port), the boom's box corners in the boom node and the
## boom node's parent transform in the model (LOD0), the mast step (model axes)
var _rail: Array = [PackedVector3Array(), PackedVector3Array()]
var _boom_box := PackedVector3Array()
var _boom_parent := Transform3D.IDENTITY
var _boom_rest := Transform3D.IDENTITY
var _mast_step := Vector3.ZERO
## the native SheetRopes (or the reference) that routes and builds the deck field
var _router: Variant = null
var _materials: Array[Material] = [null, null]
## the model's rope slot material the sheets' materials are made from (BoatLivery.rope_material)
var base_material: ShaderMaterial
var _aabb := AABB()


## The sheets of `view` (its sail parts set up), null when the class has no headsail or flying sail or no
## sheet leads in its sidecar.
static func create(view: BoatView, reference := false) -> BoatSheets:
	var rig: Dictionary = view.info.physics.get("rig", {})
	if not rig.has("sheet_leads") or view.model == null:
		return null
	var any := false
	for sp in view.sail_parts:
		any = any or sp.type != "main"
	if not any:
		return null
	var b := BoatSheets.new()
	b.bv = view
	b.use_reference = reference
	b._setup(rig)
	return b


func _setup(rig: Dictionary) -> void:
	var loa := bv.info.loa
	_s = pow(loa / 12.0, 0.7)
	_r = maxf(0.0045, 0.0055 * _s)
	var sl: Dictionary = rig["sheet_leads"]
	for k in ["headsail", "flying"]:
		var e: Dictionary = sl.get(k, sl.get("headsail", {}))
		var lead := Frames.body_to_model(BoatView._vec(e["lead"]))
		var winch := Frames.body_to_model(BoatView._vec(e["winch"]))
		var mirror := Vector3(-1, 1, 1)
		# model +X is port: the sidecar gives the starboard side (x < 0); index 0 starboard, 1 port
		_leads[k] = {"lead": [lead, lead * mirror], "winch": [winch, winch * mirror],
			"drum": float(e.get("drum_diameter", 0.06))}
	native = not use_reference and ClassDB.class_exists("SheetRopes")
	_router = ClassDB.instantiate("SheetRopes") if native else SheetRopesRef.new()
	_deck = deck_field(bv)
	var step := Frames.body_to_model(BoatView._vec(rig.get("mast_step", [0, 0, 0])))
	_mast_step = step
	_setup_route(sl)
	var chord := float(rig.get("mast_chord", 0.12))
	var zf := step.z + 0.6 * chord
	_mast_front = Vector3(0.0, _deck_h(0.0, zf, step.y) + _r, zf)
	var tack := Frames.body_to_model(BoatView._vec(rig.get("forestay_tack", [loa * 0.45, 0, 1])))
	_stay_front = tack + Vector3(0.0, 0.5, 0.15 * sqrt(loa))
	_has_sprit = rig.get("bowsprit_end") is Array
	if _has_sprit:
		_sprit_end = Frames.body_to_model(BoatView._vec(rig["bowsprit_end"]))
	_pole = bv.pole_class
	var sails: Dictionary = bv.info.physics.get("sails", {})
	for sp in bv.sail_parts:
		_areas[sp.id] = float(sails.get(sp.id, {}).get("area_m2", 10.0))
	var h := float(rig.get("masthead", [0, 0, 12.0])[2])
	var bw := bv.info.beam_max
	_aabb = AABB(Vector3(-bw - 4.0, -2.0, -loa), Vector3(2.0 * bw + 8.0, h + 4.0, 2.0 * loa + 4.0))
	base_material = _rope_slot(bv.model)
	if base_material == null:
		base_material = BoatMaterials.rope_base()  # the boat material has no rope slot material of its own
	if base_material != null:
		_materials[Surface.HEADSAIL] = BoatLivery.rope_material(bv.info.id, base_material, "sheet", {})
		_materials[Surface.FLYING] = BoatLivery.rope_material(bv.info.id, base_material, "kite_sheet", {})
	mesh = ArrayMesh.new()
	node = MeshInstance3D.new()
	node.name = "sheets"
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bv.model.add_child(node)
	_build()


## A rope slot material of the model (BoatMaterials' shared ShaderMaterial), the base of the sheets' materials.
static func _rope_slot(m: Node) -> ShaderMaterial:
	var stack: Array[Node] = [m]
	var found: ShaderMaterial = null
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var sm := mi.mesh.surface_get_material(s) as ShaderMaterial
			if sm != null and sm.resource_name.begins_with("rope"):
				if sm.resource_name == "rope":
					return sm
				found = sm
	return found


## The class's deck height field (sail_visuals.md §11.3 "Deck"): the top of the deck meshes of every level and the low
## fittings of the hardware meshes, read at load in model axes (x port, z forward), with a skirt over the hull side and
## widened; built once per class, natively when the GDExtension is there.
static func deck_field(view: BoatView) -> Dictionary:
	var key := view.info.id
	if _decks.has(key):
		return _decks[key]
	var surfaces := []
	for lv in view.levels:
		var m: Node3D = lv["model"]
		if m == null:
			continue
		for part in ["deck", "hardware"]:
			var mi := m.find_child(part, true, false) as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var xf := Transform3D.IDENTITY
			var x: Node = mi
			while x != null and x != m:
				if x is Node3D:
					xf = (x as Node3D).transform * xf
				x = x.get_parent()
			for s in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(s)
				var idx: Variant = arr[Mesh.ARRAY_INDEX]
				if idx == null:
					continue
				surfaces.append({"positions": xf * (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array), "indices": idx,
					"cap": -1.0 if part == "deck" else FIT_MAX})
	var builder: Variant = ClassDB.instantiate("SheetRopes") if ClassDB.class_exists("SheetRopes") else SheetRopesRef.new()
	var out: Dictionary = builder.build_deck(surfaces, DECK_CELL, DECK_SKIRT, DECK_DILATE) if not surfaces.is_empty() else {}
	_decks[key] = out
	return out


## The rail of the outside route (§11.3) per side, from the deck field's outer edge every RAIL_STEP, out by its margin
## (fading in forward of the lead), and the boom's box for the route.
func _setup_route(sl: Dictionary) -> void:
	if not _deck.is_empty():
		var lead_z: float = (_leads["flying"]["lead"][0] as Vector3).z
		var m0 := RAIL_MARGIN + _r
		var nz: int = _deck["nz"]
		var o: Vector2 = _deck["origin"]
		var c: float = _deck["cell"]
		var every := maxi(1, roundi(RAIL_STEP / c))
		for side in 2:
			var edge: PackedFloat32Array = _deck["edge_hi" if side == 1 else "edge_lo"]
			var pts := PackedVector3Array()
			for k in range(0, nz, every):
				if is_nan(edge[k]):
					continue
				var z := o.y + k * c
				var m := m0 * smoothstep(lead_z, lead_z + RAIL_FADE, z)
				pts.append(Vector3(edge[k] + (m if side == 1 else -m), 0.0, z))
			_rail[side] = pts
	var boom: Node3D = bv.levels[0]["boom"] if not bv.levels.is_empty() else null
	var bm := boom as MeshInstance3D
	if bm == null and boom != null:
		bm = boom.find_child("*", true, false) as MeshInstance3D
	if bm != null and bm.mesh != null:
		var box := bm.mesh.get_aabb()
		var to_boom := Transform3D.IDENTITY
		var x: Node = bm
		while x != null and x != boom:
			to_boom = (x as Node3D).transform * to_boom
			x = x.get_parent()
		for k in 8:
			_boom_box.append(to_boom * box.get_endpoint(k))
		var pc := Transform3D.IDENTITY
		x = boom.get_parent()
		while x != null and x != bv.levels[0]["model"]:
			if x is Node3D:
				pc = (x as Node3D).transform * pc
			x = x.get_parent()
		_boom_parent = pc
		_boom_rest = bv.levels[0]["boom_rest"]


## The obstacles of the outside route on `side` (0 starboard, 1 port), as last placed: the main, the boom, the shown
## headsail (SheetRopes.route's [points, margin, ...]).
func _route_obstacles(side: int, jib: BoatView.SailPart) -> Array:
	return _route_sides(jib)[side]


## Both sides' obstacles at once (the sails and the boom read once).
func _route_sides(jib: BoatView.SailPart) -> Array:
	var ms := SAIL_MARGIN + 2.0 * _r
	var out := []
	for sp in bv.sail_parts:
		if sp.type == "main" and sp.shape != null and sp.node.visible:
			out.append_array([sp.shape.mid(), ms])
	if not _boom_box.is_empty():
		var xf := _boom_parent * _boom_rest * Transform3D(Basis(bv._boom_axis, bv.boom_angle), Vector3.ZERO)
		out.append_array([xf * _boom_box, ms])
	if jib != null and jib.shape != null and jib.node.visible:
		out.append_array([jib.shape.mid(), ms])
	var port := out.duplicate()
	out.append_array([_rail[0], 0.0])
	port.append_array([_rail[1], 0.0])
	return [out, port]


func _deck_h(x: float, z: float, def: float) -> float:
	if _deck.is_empty():
		return def
	var c: float = _deck["cell"]
	var o: Vector2 = _deck["origin"]
	var i := clampi(roundi((x - o.x) / c), 0, int(_deck["nx"]) - 1)
	var k := clampi(roundi((z - o.y) / c), 0, int(_deck["nz"]) - 1)
	var y: float = (_deck["heights"] as PackedFloat32Array)[k * int(_deck["nx"]) + i]
	return y if y > SheetRopesRef.NO_DECK else def


## The fixed turns on a winch drum and the tail into the cockpit (§11.3), in model axes: the drum entry first.
func drum_and_tail(lead: Vector3, winch: Vector3, drum: float, with_tail: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	var rr := 0.5 * drum + _r
	var y0 := winch.y + 0.34 * drum
	# winches turn clockwise from above: the angle th about the drum (fwd cos, port sin) decreases; the line comes
	# on at the tangent point whose clockwise direction points away from the lead
	var af := lead.z - winch.z
	var ap := lead.x - winch.x
	var d := maxf(sqrt(af * af + ap * ap), rr * 1.001)
	var beta := atan2(ap, af)
	var al := acos(clampf(rr / d, -1.0, 1.0))
	var th0 := beta + al
	for cand in [beta + al, beta - al]:
		var p := Vector2(winch.z + rr * cos(cand), winch.x + rr * sin(cand))
		var dirv := Vector2(sin(cand), -cos(cand))
		if (p - Vector2(lead.z, lead.x)).dot(dirv) > 0.0:
			th0 = cand
	var n := DRUM_RINGS if with_tail else 1
	for k in n:
		var u := float(k) / float(maxi(n - 1, 1))
		var th := th0 - TAU * TURNS * u
		out.append(Vector3(winch.x + rr * sin(th), y0 + 0.25 * drum * u, winch.z + rr * cos(th)))
	if not with_tail:
		return out
	var top := out[out.size() - 1]
	var th_end := th0 - TAU * TURNS
	var radial := Vector3(sin(th_end), 0.0, cos(th_end))
	# over the self-tailer to the stripper arm, out and down into the cockpit, and a loose coil on the floor
	var jaw := Vector3(winch.x, winch.y + 0.95 * drum, winch.z) + radial * (0.3 * drum)
	var exit := jaw + radial * (0.5 * drum) + Vector3(0, 0.02, 0)
	var rc := 0.11 * _s
	var cx := 0.5 * winch.x
	var cz := winch.z - 0.35 * _s
	var floor_y := _deck_h(cx, cz, winch.y - 0.3) + _r
	out.append(top.lerp(jaw, 0.5) + Vector3(0, 0.01, 0))
	out.append(jaw)
	out.append(exit)
	# the coil starts on its outboard side; the drop is a quadratic from the stripper exit, its control above
	# the coil's start so the tail falls and then runs flat
	var side := signf(winch.x) if winch.x != 0.0 else 1.0
	var a0 := 0.0 if side > 0.0 else PI
	var start := Vector3(cx + rc * 1.25 * cos(a0), floor_y, cz + rc * sin(a0))
	var ctrl := Vector3(start.x, exit.y, start.z).lerp(exit, 0.35)
	for k in range(1, 5):
		var u := float(k) / 4.0
		var q := exit.lerp(ctrl, u).lerp(ctrl.lerp(start, u), u)
		q.y = maxf(q.y, _deck_h(q.x, q.z, -INF) + _r)
		out.append(q)
	var nc := 16
	for k in range(1, nc + 1):
		var th := a0 + side * TAU * 1.4 * float(k) / float(nc)
		var rr2 := rc * (1.0 - 0.1 * float(k) / float(nc)) * (1.0 + 0.07 * sin(3.1 * th))
		var px := cx + rr2 * 1.25 * cos(th)
		var pz := cz + rr2 * sin(th)
		out.append(Vector3(px, _deck_h(px, pz, floor_y - _r) + _r * (1.0 + 1.4 * float(k) / float(nc)), pz))
	return out


func _flying_lines() -> int:
	return 2 if _pole or not _has_sprit else 3


func _has_type(fly: bool) -> bool:
	for sp in bv.sail_parts:
		if sp.type != "main" and BoatView.is_flying(sp.type) == fly:
			return true
	return false


## (Re)builds the mesh and the shapes for the current detail level.
func _build() -> void:
	mesh.clear_surfaces()
	shapes = [null, null]
	line_specs = [[], []]
	if detail >= 2:
		node.visible = false
		return
	node.visible = true
	var full := detail == 0
	for surf in 2:
		var fly := surf == Surface.FLYING
		if not _has_type(fly):
			continue
		var k := "flying" if fly else "headsail"
		var lines := []
		for side in 2:
			var lead: Vector3 = _leads[k]["lead"][side]
			var winch: Vector3 = _leads[k]["winch"][side]
			var fixed := drum_and_tail(lead, winch, float(_leads[k]["drum"]), full)
			lines.append({"radius": _r, "free_rings": FREE_RINGS[detail], "lead_rings": LEAD_RINGS[detail],
				"anchor": lead, "fixed": fixed})
		if fly and _flying_lines() == 3:
			lines.append({"radius": 0.8 * _r, "free_rings": 3 if full else 2, "lead_rings": 0, "anchor": _sprit_end})
		var params := {"sides": SIDES[detail], "tile": TILE, "lines": lines}
		if not _deck.is_empty():
			params["deck"] = _deck
		var shape: Variant = ClassDB.instantiate("SheetRopes") if native else SheetRopesRef.new()
		if not shape.configure(params):
			continue
		line_specs[surf] = lines
		var hide := PackedFloat32Array()
		hide.resize(lines.size() * SheetRopesRef.DRIVE)
		var starts := PackedVector3Array()
		var ways := PackedVector3Array()
		for l in lines:
			starts.append(l["anchor"])
			ways.append(Vector3(NAN, NAN, NAN))
		shape.update(starts, ways, hide, Vector3.DOWN)
		if (sag[surf] as PackedFloat32Array).size() != 2 * lines.size():  # a level change keeps the eased sag
			var s := PackedFloat32Array()
			s.resize(2 * lines.size())
			s.fill(LAZY_SAG)
			sag[surf] = s
		shapes[surf] = shape
	_rebuild_mesh()
	for surf in 2:
		if shapes[surf] != null and native:
			if not shapes[surf].attach_mesh(mesh.get_rid(), _surface_index(surf)):
				push_warning("%s sheets: mesh layout not writable in place; rebuilding it each update" % bv.info.id)
				native = false


## The shape whose lines are mesh surface `si` (the preview dumps read the lines from it).
func surface_shape(si: int) -> Variant:
	for surf in 2:
		if shapes[surf] != null and _surface_index(surf) == si:
			return shapes[surf]
	return null


func _surface_index(surf: int) -> int:
	return 0 if surf == 0 or shapes[0] == null else 1


func _rebuild_mesh() -> void:
	mesh.clear_surfaces()
	for surf in 2:
		var shape: Variant = shapes[surf]
		if shape == null:
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = shape.positions()
		arr[Mesh.ARRAY_NORMAL] = shape.normals()
		arr[Mesh.ARRAY_TANGENT] = shape.tangents()
		arr[Mesh.ARRAY_TEX_UV] = shape.uvs()
		arr[Mesh.ARRAY_INDEX] = shape.indices()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _materials[surf])
	mesh.custom_aabb = _aabb


## The material of the headsail lines (`sheet`) or the flying-sail lines (`kite_sheet`), data_format.md §8.7.
func set_material(surf: int, m: Material) -> void:
	_materials[surf] = m
	if shapes[surf] != null and mesh.get_surface_count() > _surface_index(surf):
		mesh.surface_set_material(_surface_index(surf), m)


func get_material(surf: int) -> Material:
	return _materials[surf]


## LOD (sail_visuals.md §11.4): 0 full, 1 coarse, 2 none.
func set_detail(level: int) -> void:
	level = clampi(level, 0, 2)
	if level == detail:
		return
	detail = level
	native = not use_reference and ClassDB.class_exists("SheetRopes")
	_build()
	if updates > 0:
		step(_last_aws, 0.0, true)  # the new level's lines at once, from the sails as last placed


## The sail a surface follows: the shown headsail (or flying sail) furthest hoisted, `up` first.
func _pick(fly: bool) -> BoatView.SailPart:
	var best: BoatView.SailPart = null
	var score := -1.0
	for sp in bv.sail_parts:
		if sp.type == "main" or BoatView.is_flying(sp.type) != fly or sp.shape == null or not sp.node.visible:
			continue
		var sc := sp.luff_scale + (2.0 if sp.phase == SimSource.Phase.UP else 0.0)
		if sc > score:
			score = sc
			best = sp
	return best


## Line tension (N) of a working sheet or guy, §11.3.
func tension(sp: BoatView.SailPart, aws: float) -> float:
	var q := 0.5 * RHO * aws * aws
	var fs := 1.0 if sp.phase == SimSource.Phase.UP or sp.phase == SimSource.Phase.PREPARE_DROP else 0.1
	var a: float = _areas.get(sp.id, 10.0)
	return T_MIN + 0.35 * q * a * fs * pow(1.0 - clampf(sp.shiver, 0.0, 1.0), 2.0)


## Depth over span of a run of length `l` under tension `t`, with the luff slack `shiver`.
func sag_of(l: float, t: float, shiver: float) -> float:
	var d := 2.0 * _r
	var w := 700.0 * d * d
	return clampf(w * G * l / (8.0 * maxf(t, 0.1)) + 0.12 * shiver * shiver, 0.0005, 0.25)


## Eases every line's sag toward its target (every frame, drawn or not) and, when `draw`, rewrites the lines from
## the sails as last placed. `aws` the interpolated apparent wind speed, `dt` the frame time.
func step(aws: float, dt: float, draw: bool) -> void:
	_last_aws = aws
	if detail >= 2:
		return
	var a := 1.0 - exp(-maxf(dt, 0.0) / TAU_SAG)
	if not draw:
		# between redraws only the sag eases, toward the targets of the last redraw
		for surf in 2:
			var se: PackedFloat32Array = sag[surf]
			var te: PackedFloat32Array = _targets[surf]
			if te.size() == se.size():
				for k in se.size():
					se[k] += (te[k] - se[k]) * a
				sag[surf] = se
		return
	var g := Vector3.DOWN
	var basis := bv.global_transform.basis if bv.is_inside_tree() else bv.transform.basis
	g = (basis.inverse() * Vector3.DOWN).normalized()
	for surf in 2:
		var shape: Variant = shapes[surf]
		if shape == null:
			continue
		var fly := surf == Surface.FLYING
		var sp := _pick(fly)
		followed[surf] = sp
		var lines: Array = line_specs[surf]
		var n := lines.size()
		var starts := PackedVector3Array()
		var ways := PackedVector3Array()
		var drive := PackedFloat32Array()
		starts.resize(n)
		ways.resize(n)
		drive.resize(n * SheetRopesRef.DRIVE)
		var slots := SheetRopesRef.MAX_WAYS if fly else 1
		var none := Vector3(NAN, NAN, NAN)
		ways.resize(n * slots)
		ways.fill(none)
		var s: PackedFloat32Array = sag[surf]
		var tg := PackedFloat32Array()
		tg.resize(s.size())
		tg.fill(LAZY_SAG)
		if sp == null:
			for i in n:
				starts[i] = lines[i]["anchor"]
				s[2 * i] = LAZY_SAG
				s[2 * i + 1] = LAZY_SAG
		else:
			var corners: PackedVector3Array = sp.shape.mid_points(PackedInt32Array([sp.cols - 1, 0]))
			var clew := corners[0]
			var tack := corners[1]
			var work := 0 if sp.beta > 0.0 else 1  # beta > 0: the sail to starboard, the starboard line works
			var t := tension(sp, aws)
			var phi: float = sp.shape.get_phase()
			var obs := [[], []]
			if fly:
				var jib := _pick(false)
				obs = _route_sides(jib)
			for i in n:
				var anchor: Vector3 = lines[i]["anchor"]
				var o := i * SheetRopesRef.DRIVE
				var working := i == work or i == 2
				var start := clew
				var way := Vector3(NAN, NAN, NAN)
				if i == 2:
					start = tack  # the tack line, from the tack to the sprit end
				elif not working and fly and _pole:
					start = tack  # the guy, from the tack at the pole end aft
					working = true
				elif not working:
					way = _waypoint(clew, anchor, _stay_front if fly else _mast_front)
				starts[i] = start
				var route := PackedVector3Array()
				if fly and i < 2:
					route = _route(start, anchor, way, obs)
				elif not is_nan(way.x):
					route.append(way)
				for j in mini(route.size(), slots):
					ways[i * slots + j] = route[j]
				var l_free := 0.0
				var prev_pt := start
				for w in route:
					l_free += prev_pt.distance_to(w)
					prev_pt = w
				l_free += prev_pt.distance_to(anchor)
				var l_lead := 0.0
				if (lines[i] as Dictionary).has("fixed") and not (lines[i]["fixed"] as PackedVector3Array).is_empty():
					l_lead = anchor.distance_to((lines[i]["fixed"] as PackedVector3Array)[0])
				var target_f := minf(LAZY_SAG, LAZY_DEPTH / maxf(l_free, 0.1))
				var target_l := sag_of(l_lead, T_MIN, 0.0)
				var shiver := LAZY_SHIVER * sp.shiver
				var whip := 0.0
				if working:
					var sh := sp.shiver if i != 2 else 0.0
					target_f = sag_of(l_free, t, sh)
					target_l = sag_of(l_lead, t, 0.0)
					shiver = sh
					whip = 0.15 * sh
				s[2 * i] += (target_f - s[2 * i]) * a
				s[2 * i + 1] += (target_l - s[2 * i + 1]) * a
				tg[2 * i] = target_f
				tg[2 * i + 1] = target_l
				drive[o] = 1.0
				drive[o + 1] = s[2 * i]
				drive[o + 2] = s[2 * i + 1]
				drive[o + 3] = 0.6 * shiver * sin(phi)
				drive[o + 4] = whip
				drive[o + 5] = phi
		sag[surf] = s
		_targets[surf] = tg
		if not draw:
			continue
		shape.update(starts, ways, drive, g)
		last_starts[surf] = starts
		last_ways[surf] = ways
		last_drive[surf] = drive
	if draw:
		updates += 1
		if native:
			for surf in 2:
				if shapes[surf] != null:
					shapes[surf].write_mesh()
		else:
			_rebuild_mesh()


## §11.3 "Outside route": the waypoints of a flying sail's line from `start` to its lead `anchor` (through the lazy
## line's forestay waypoint `way` when it has one), outside the obstacles `obs` per side.
func _route(start: Vector3, anchor: Vector3, way: Vector3, obs: Array) -> PackedVector3Array:
	var side := 1 if anchor.x > 0.0 else 0
	var sg := 1.0 if side == 1 else -1.0
	var span := start.distance_to(anchor) if is_nan(way.x) else start.distance_to(way) + way.distance_to(anchor)
	var h := span / float(FREE_RINGS[detail] - 1)
	if is_nan(way.x):
		return _router.route(start, anchor, _pivot(sg), sg, obs[side], h, WAYS_WORK)
	# the forestay waypoint out along its bisector by the corner allowance (and the margin, as it turns), so the
	# straight tube between the rings either side of it stays ahead of the stay and the headsail's tack
	var d1 := Vector2(way.x - start.x, way.z - start.z).normalized()
	var d2 := Vector2(anchor.x - way.x, anchor.z - way.z).normalized()
	var al := acos(clampf(d1.dot(d2), -1.0, 1.0))
	var bis := d1 - d2
	if bis.length_squared() > 1e-12:
		bis = bis.normalized()
		var push := (0.5 * h * sin(0.5 * al) + (SAIL_MARGIN + 2.0 * _r) * sin(0.5 * al)) / maxf(cos(0.5 * al), 0.3)
		way += Vector3(bis.x, 0.0, bis.y) * push
	var out: PackedVector3Array = _router.route(start, way, _pivot(-sg), -sg, obs[1 - side], h, WAYS_LEG)
	out.append(way)
	out.append_array(_router.route(way, anchor, _pivot(sg), sg, obs[side], h, WAYS_LEG))
	return out


func _pivot(sg: float) -> Vector3:
	return Vector3(-sg * PIVOT_SIDE * bv.info.beam_max, 0.0, _mast_step.z)


## The lazy line's waypoint round the front of `obstacle` (§11.3): where the straight line from the clew to the lead
## crosses the centreline, moved forward to the obstacle when it lies aft of it (at the crossing's height), by a
## share growing smoothly from 0 with the clew on the centreline to 1 at WAY_REACH across it, so the waypoint moves
## continuously as the clew crosses; none (NAN) when the clew is on the lead's side.
static func _waypoint(clew: Vector3, lead: Vector3, obstacle: Vector3) -> Vector3:
	if signf(clew.x) == signf(lead.x) or absf(clew.x - lead.x) < 1e-6:
		return Vector3(NAN, NAN, NAN)
	var t := clew.x / (clew.x - lead.x)
	var c := clew.lerp(lead, t)
	var k := smoothstep(0.0, WAY_REACH, absf(clew.x))
	return Vector3(0.0, c.y, lerpf(c.z, maxf(c.z, obstacle.z), k))
