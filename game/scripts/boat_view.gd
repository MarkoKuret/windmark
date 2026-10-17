class_name BoatView
extends Node3D
## The generated boat in the scene (conventions.md §11): the boatgen GLB under a node placed at the render pose,
## the rudder (with the tiller it carries) and the wheel turned by the helm, the boom and the mainsheet following
## the main's sail angle, and the sails bent and placed per vertex every frame (docs/specs/sail_visuals.md): fill,
## camber, twist, flutter, backing, hoist and drop and the flying spinnaker shapes, from the sail state and the
## apparent wind. The per-vertex work runs in the native `SailShape` (game/native) when the GDExtension is loaded,
## else in its GDScript reference `SailShapeRef`; each sail is its own grid-order mesh (§3.1) whose vertex buffer
## is rewritten in one call per update, at a rate set by the distance to the camera (§11). The running sheets follow
## the sails (BoatSheets, §11.3), and the generated levels of detail switch by distance (§11.4).

enum Mode { BOOM, LUFF, SPRIT, POLE }

const SAIL_SHADER := preload("res://shaders/sail.gdshader")

## sail_visuals.md §11 update intervals by distance to the camera and size on screen, s
const NEAR_M := 200.0
const MID_M := 800.0
const MID_INTERVAL := 1.0 / 15.0
const FAR_INTERVAL := 0.25
## every frame for a sail whose bounding sphere spans this fraction of the screen height or more
const FULL_RATE_SCREEN := 0.2
## the near sails smaller on screen, s: 30 Hz (the scene sets 20 Hz on tier L, NEAR_INTERVAL_L)
const NEAR_INTERVAL := 1.0 / 30.0
const NEAR_INTERVAL_L := 1.0 / 20.0
static var near_interval := NEAR_INTERVAL

## one sail of the class and how it is placed
## §7.6 steps of the main's angle scanned out from the centreline, and bisection steps of its stop
const STOP_SCAN := 24
const STOP_STEPS := 10


class SailPart:
	var index := 0
	var id := ""
	var type := ""
	var node: Node3D
	var rest := Transform3D.IDENTITY
	## sail frame in model axes (sail_visuals.md §3.2): tack, head, luff (tack to head), aft, port normal
	var tack := Vector3.ZERO
	var head := Vector3.ZERO
	var lh := Vector3.UP
	var ah := Vector3.BACK
	var nh := Vector3.RIGHT
	var sl := 1.0  # luff extent, m
	## the main's region for its stop on a flying sail's sheet (§7.6): rest foot direction (horizontal, from the
	## gooseneck), its length, and the heights of the rest tack and head along the boom axis from the gooseneck
	var stop_aft := Vector3.BACK
	var stop_span := 0.0
	var stop_z0 := 0.0
	var stop_z1 := 0.0
	## BOOM (the main), LUFF (about the stay or sprit line), SPRIT (asymmetric on a bowsprit), POLE
	var mode := 0
	var tack_line_max := 0.0
	var r_h := 1.0  # horizontal distance from the head to the rest tack
	## the per-vertex shape (SailShape or SailShapeRef), null when the sail mesh is not a usable grid
	var shape: Variant = null
	var mesh: ArrayMesh
	## the mesh arrays when its vertex buffer cannot be rewritten in place (rebuilt instead, §11 fallback)
	var arrays: Array = []
	var rows := 0
	var cols := 0
	## the rest grid's uv0 in grid order (port layer first): the cloth plan of the livery (sail_visuals.md §11.2)
	var uv0 := PackedVector2Array()
	## a sphere around the sail at any angle (model axes), for the custom AABB, the distance and the frustum
	var centre := Vector3.ZERO
	var radius := 1.0
	var since := INF  # s since the last shape update
	var updates := 0
	## drawn this frame (tests): sail angle, pole angle, hoisted fraction of the luff and fill of the flying shape
	var beta := 0.0
	var gamma := 0.0
	var luff_scale := 1.0
	var chord_scale := 1.0
	## the grid indices of the outline its drawn shadow uses (BoatShadows.sail_indices)
	var shadow_idx := PackedInt32Array()
	## the newer snapshot's phase and the interpolated luff shiver drawn this frame (the sheets, §11.3)
	var phase := 0
	var shiver := 0.0

	## the rest mid-surface in grid order (model axes), and the look and the kite set parameters (§4, §4.1) the
	## shape was configured with (the class file's over the sidecar's); a kite's tack rise in m (§4.1)
	var rest_mid := PackedVector3Array()
	var furling := false
	var look := {}
	var kset := {}
	var tack_rise_m := 0.0

	## the placed clew (mid-surface, model axes)
	func clew() -> Vector3:
		return shape.mid()[cols - 1] if shape != null else Vector3.ZERO


var info: SimSource.ClassInfo
## the imported boat root (the GLB's child named after the class), null when the GLB is missing
var model: Node3D
var sail_parts: Array[SailPart] = []
## the boom angle drawn this frame (the main's interpolated beta)
var boom_angle := 0.0
var _rudder: Node3D
var _rudder_rest := Transform3D.IDENTITY
var _rudder_axis := Vector3.UP
## twin rudders: each blade's node name -> its stock axis (model frame), from the sidecar's `rig.rudders`; the blades
## of the shown level, [{"node", "rest", "axis"}], turn with the helm like the rudder node
var _blade_axes := {}
var _blades: Array = []
var _wheel: Node3D
var _wheel_rest := Transform3D.IDENTITY
## the second wheel of a twin-wheel class (data_format.md §3.7.3), null on the others
var _wheel2: Node3D
var _wheel2_rest := Transform3D.IDENTITY
var _wheel_axis := Vector3.BACK
var _rudder_max := 0.6
var _boom: Node3D
var _boom_rest := Transform3D.IDENTITY
var _boom_axis := Vector3.UP
var _boom_pivot := Vector3.ZERO
var _pole: Node3D
var _pole_rest := Transform3D.IDENTITY
var _pole_axis := Vector3.UP
## §4.1 the pole's tilt about its heel that lifts its end with a kite's raised tack: the axis (pole frame) and the
## pole's length from heel to end; the tilt drawn last
var _pole_tilt_axis := Vector3.ZERO
var _pole_len := 0.0
var _pole_tilt := 0.0
var _mast_step := Vector3.ZERO
var _mast_head := Vector3.ZERO
## the forestay, tack fitting and hounds (model axes), for a flying sail on a pole (sail_visuals.md §7.4)
var _stay0 := Vector3.ZERO
var _stay1 := Vector3.ZERO
var _has_stay := false
var _mast_axis := Vector3.UP
## §7.5 the flying sails' sheet lead block on starboard (model axes; the sidecar's rig.sheet_leads.flying.lead)
var _flying_lead := Vector3.ZERO
var _has_flying_lead := false
## §7.6 the main's drawn angle less the core's, the last update (tests)
var main_stop := 0.0
var _sheet: MeshInstance3D
var _sheet_mesh: ArrayMesh
var _sheet_arrays: Array = []
var _sheet_rest := PackedVector3Array()
var _sheet_w := PackedFloat32Array()
var _sheet_top := Vector3.ZERO
var _sheet_angle := 0.0
## the mainsheet's vertex positions rewritten in place (its custom AABB set), or rebuilt (false)
var _sheet_in_place := false
## the sails of the fleet update out of step: this boat's share of an update interval (0 to 1)
var _stagger := 0.0
## frame time since the sails were last placed, s; the wait added to the next interval (the boat's place in the
## fleet's rhythm); whether the next update in view comes at once (none yet, or the boat was out of view)
var _sail_dt := 0.0
var _sail_wait := 0.0
var _sail_fresh := true
## the sails placed every frame, in view or not (the scene sets it for the viewed boat: a camera cut never shows
## them a frame late)
var full_rate := false
## a sphere around every sail at any angle (model axes; radius < 0: not made yet)
var _sail_centre := Vector3.ZERO
var _sail_radius := -1.0
static var _views_made := 0
## the camera's frustum, shared by every sail of the frame (begin_frame)
static var _frustum: Array[Plane] = []
static var _frustum_cam: Camera3D = null
static var _frustum_frame := -1
## the camera's tan(fov / 2) (perspective), or 0 with the orthogonal size in _cam_size
static var _cam_tan := 1.0
static var _cam_size := 0.0
## the sail materials (§11) by imported slot material, shared by the fleet
static var _sail_mats := {}
## the levels of detail and the running sheets (off: the boat as before them, for cost comparisons)
static var use_lods := true
static var draw_sheets := true
## measured runs only (the sail scene's run-only flags, game/README.md "Measuring performance"): a level of detail
## for every distance (-1: by distance), model part nodes never shown (by name: "rigging", "hardware", ...), the
## sails not drawn, the sails drawn once and then left in their first shape
static var forced_lod := -1
static var hidden_parts: Array[String] = []
static var draw_sails := true
static var animate_sails := true
## the GDScript reference shapes even when the native SailShape is loaded (set by create)
var use_reference := false
## the class file as read at set-up ({} when there is none: a generator test class); its `visual.sails.<id>`
## `look` and `set` blocks go over the sidecar's copies (sail_visuals.md §4.1)
var class_file := {}
## the hull and mast of the drawn shadow on the water (BoatShadows.caster_from_physics), built on first use
var _shadow_caster: Variant = null
## sun shadows (sail_visuals.md §11.4): beyond this distance from the camera (m) the shadow proxies and sails of
## boats other than the own boat cast none; 0: no limit (the quality tier's `boat_cast_distance`)
static var cast_distance := 0.0
## the player's own boat: casts at any distance, and its meshes keep the full detail at chase range (lod_bias)
var own := false:
	set(v):
		own = v
		_apply_lod_bias()
## the own boat's mesh LOD bias (sail_visuals.md §11.4): the engine's automatic LOD drops detail only when its error
## is under 1 / OWN_LOD_BIAS of the viewport's mesh LOD threshold (the full model to about 70 m)
const OWN_LOD_BIAS := 32.0
## the boat casts the sun's shadows at all (the look panel's "Boat sun shadows", `--no-boat-shadows`)
var sun_shadows := true:
	set(v):
		sun_shadows = v
		_apply_casting()
## the shadow-only proxies (`shadow`, `shadow_boom`, `shadow_rudder`), per level, and whether this boat is within
## `cast_distance` of the camera now
var _proxies: Array[GeometryInstance3D] = []
var _casting := true
## the levels of detail (sail_visuals.md §11.4), finest first: {"lod", "from", "root" (the GLB wrapper), "model",
## "parts" (the non-sail part nodes), "rudder", "rudder_rest", "wheel", "wheel_rest", "wheel_2", "wheel_2_rest",
## "boom", "boom_rest", "pole",
## "pole_rest", "sheet" (the mainsheet's rebuild data)}; the sails are LOD0's at every level
var levels: Array[Dictionary] = []
## the level shown
var lod := 0
## a class whose flying sail is on a pole (sail_visuals.md §7.3)
var pole_class := false
## the running sheets (BoatSheets), null for a class without headsail or flying sail
var sheets: BoatSheets
## the helm and pole drawn last (a level that comes in is set at once)
var _helm := 0.0
var _pole_gamma := 0.0
var _pole_shown := false
var _sheets_since := 0.0
## the boat's livery (data_format.md §8) and its text texture, set by set_livery; null: the class's plain look
var livery: Livery
var livery_text: LiveryText
## the per-boat livery materials, held here so they outlive the mesh instances that use them when the boat is freed
var livery_materials: Array[Material] = []

## the body frame (x forward, y port, z up) in model axes (Frames.body_to_model)
const BODY_TO_MODEL := Transform3D(Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)), Vector3.ZERO)


## `reference`: bend the sails with the GDScript SailShapeRef even when the native SailShape is loaded (tests).
static func create(class_info: SimSource.ClassInfo, rudder_max: float, reference := false) -> BoatView:
	_views_made += 1
	var b := BoatView.new()
	b._stagger = fposmod(_views_made * 0.618034, 1.0)
	b.name = "Boat_" + class_info.id
	b.info = class_info
	b.use_reference = reference
	b._rudder_max = rudder_max
	var path := "res://generated/boats/%s.glb" % class_info.id
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		var wrapper := scene.instantiate() as Node3D
		b.add_child(wrapper)
		b.model = wrapper.get_child(0) as Node3D if wrapper.get_child_count() > 0 else wrapper
		BoatMaterials.apply(wrapper)
		b.levels.append({"lod": 0, "from": 0.0, "root": wrapper, "model": b.model})
		if use_lods:
			b._load_lods()
	else:
		push_warning("%s not generated (run game/tests/run_boat_import_test.sh); drawing a box" % path)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(class_info.beam_max, 1.0, class_info.loa)
		mi.mesh = bm
		b.add_child(mi)
	b._find_parts()
	b._setup_shadows()
	if forced_lod == 0:
		b._apply_lod_bias()
	if b.model != null and draw_sheets:
		b.sheets = BoatSheets.create(b, reference)
	return b


## The coarser levels of the sidecar's model.lods that are generated (sail_visuals.md §11.4), hidden until shown;
## their sail nodes go (the sails are LOD0's at every level).
func _load_lods() -> void:
	var lods: Array = info.physics.get("model", {}).get("lods", [])
	var sail_nodes := {}
	for s in info.physics.get("sails", {}).values():
		sail_nodes[String(s.get("node", ""))] = true
	for e in lods:
		var k := int(e.get("lod", 0))
		if k <= 0:
			continue
		var path := "res://generated/boats/%s" % String(e.get("file", ""))
		if not ResourceLoader.exists(path):
			continue
		var wrapper := (load(path) as PackedScene).instantiate() as Node3D
		var m := wrapper.get_child(0) as Node3D if wrapper.get_child_count() > 0 else wrapper
		for c in m.get_children():
			if sail_nodes.has(String(c.name)):
				m.remove_child(c)
				c.free()
		add_child(wrapper)
		BoatMaterials.apply(wrapper)
		levels.append({"lod": k, "from": float(e.get("from_m", 0.0)), "root": wrapper, "model": m})
	levels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["lod"] < b["lod"])


## Paints the boat in `lv` (BoatLivery: per-boat materials over the shared meshes; no mesh is rebuilt).
func set_livery(lv: Livery) -> void:
	BoatLivery.apply(self, lv)


func _find_parts() -> void:
	if model == null:
		return
	var rig: Dictionary = info.physics.get("rig", {})
	var sail_names := {}
	for s in info.physics.get("sails", {}).values():
		sail_names[String(s.get("node", ""))] = true
	for r in rig.get("rudders", []):
		_blade_axes[String(r["node"])] = Frames.body_to_model(_vec(r["axis"])).normalized()
	for lv in levels:
		_level_parts(lv, sail_names)
	_rudder = levels[0]["rudder"]
	_rudder_rest = levels[0]["rudder_rest"]
	_blades = levels[0]["blades"]
	if rig.has("rudder_axis"):
		_rudder_axis = Frames.body_to_model(_vec(rig["rudder_axis"])).normalized()
	_wheel = levels[0]["wheel"]
	_wheel_rest = levels[0]["wheel_rest"]
	_wheel2 = levels[0]["wheel_2"]
	_wheel2_rest = levels[0]["wheel_2_rest"]
	if rig.has("wheel_axis"):
		_wheel_axis = Frames.body_to_model(_vec(rig["wheel_axis"])).normalized()
	_boom = levels[0]["boom"]
	if _boom:
		_boom_rest = _boom.transform
		_boom_pivot = _boom_rest.origin
	if rig.has("boom_axis"):
		_boom_axis = Frames.body_to_model(_vec(rig["boom_axis"])).normalized()
	if rig.has("boom_pivot"):
		_boom_pivot = Frames.body_to_model(_vec(rig["boom_pivot"]))
	if rig.has("mast_step") and rig.has("masthead"):
		_mast_step = Frames.body_to_model(_vec(rig["mast_step"]))
		_mast_head = Frames.body_to_model(_vec(rig["masthead"]))
		_mast_axis = (_mast_head - _mast_step).normalized()
	if rig.has("forestay_tack") and rig.has("hounds"):  # §7.4: a kite on a pole flies forward of the forestay
		_stay0 = Frames.body_to_model(_vec(rig["forestay_tack"]))
		_stay1 = Frames.body_to_model(_vec(rig["hounds"]))
		_has_stay = true
	if rig.has("sheet_leads") and rig["sheet_leads"] is Dictionary and rig["sheet_leads"].has("flying"):
		_flying_lead = Frames.body_to_model(_vec(rig["sheet_leads"]["flying"]["lead"]))
		_has_flying_lead = true
	_pole = levels[0]["pole"]
	if _pole:
		_pole_rest = _pole.transform
		if rig.has("pole_axis"):
			_pole_axis = Frames.body_to_model(_vec(rig["pole_axis"])).normalized()
	_use_sheet(levels[0]["sheet"])
	for k in range(1, levels.size()):
		for n: Node3D in levels[k]["parts"]:
			n.visible = false
	for n: Node3D in levels[0]["parts"]:
		if hidden_parts.has(String(n.name)):
			n.visible = false
	var side_sails: Dictionary = info.physics.get("sails", {})
	pole_class = _pole != null or float(rig.get("pole_length", 0.0)) > 0.0
	var furling := {}
	var cls: Variant = BoatClassData._read_json(BoatClassData.repo_path("data/classes/%s.boat.json" % info.id))
	if cls is Dictionary:
		for cs in cls.get("sails", []):
			furling[String(cs.get("id", ""))] = bool(cs.get("furling", false))
	class_file = cls if cls is Dictionary else {}
	for i in info.sails.size():
		var si: SimSource.SailInfo = info.sails[i]
		var sp := SailPart.new()
		sp.index = i
		sp.id = si.name
		sp.type = si.type
		var side: Dictionary = side_sails.get(si.name, {})
		sp.node = model.find_child(String(side.get("node", "sail_" + si.name)), true, false) as Node3D
		if sp.node == null:
			continue
		sp.rest = sp.node.transform
		var corners: Dictionary = side.get("corners", {}) if side.get("corners") is Dictionary else {}
		if corners.has("tack") and corners.has("head"):
			sp.tack = Frames.body_to_model(_vec(corners["tack"]["position"]))
			sp.head = Frames.body_to_model(_vec(corners["head"]["position"]))
		else:
			sp.tack = _boom_pivot
			sp.head = _boom_pivot + _boom_axis
		sp.lh = (sp.head - sp.tack).normalized()
		sp.nh = Frames.body_to_model(Vector3(0, 1, 0))
		sp.ah = sp.lh.cross(sp.nh).normalized()
		var ls := [0.0, (sp.head - sp.tack).dot(sp.lh)]
		if corners.has("clew"):
			ls.append((Frames.body_to_model(_vec(corners["clew"]["position"])) - sp.tack).dot(sp.lh))
		sp.sl = maxf(float(ls.max()) - float(ls.min()), 0.1)
		sp.tack_line_max = float(side.get("look", {}).get("tack_line_max", 0.0))
		var dh := sp.tack - sp.head
		sp.r_h = maxf(Vector2(dh.x, dh.z).length(), 0.1)
		if si.type == "main":
			sp.mode = Mode.BOOM
		elif si.type == "spinnaker_sym" or (si.type == "spinnaker_asym" and pole_class \
				and not rig.has("bowsprit_end")):
			sp.mode = Mode.POLE
		elif si.type == "spinnaker_asym":
			sp.mode = Mode.SPRIT
		else:
			sp.mode = Mode.LUFF  # jib, genoa, code zero (tacked hard to the sprit end)
		_setup_shape(sp, side, bool(furling.get(sp.id, false)))
		sail_parts.append(sp)
		if sp.mode == Mode.POLE and _pole and sp.shape != null:  # §4.1 the pole tilts with a raised tack
			var end := _pole_rest.affine_inverse() * sp.tack
			_pole_len = end.length()
			var k := end.cross(_pole_axis)
			_pole_tilt_axis = k.normalized() if k.length_squared() > 1e-9 else Vector3.ZERO


## The moving parts and the non-sail part nodes of one level (sail_visuals.md §11.4).
func _level_parts(lv: Dictionary, sail_names: Dictionary) -> void:
	var m: Node3D = lv["model"]
	var parts: Array[Node3D] = []
	for c in m.get_children():
		if c is Node3D and not sail_names.has(String(c.name)) and not String(c.name).begins_with("shadow"):
			parts.append(c)
	lv["parts"] = parts
	for k in ["rudder", "wheel", "wheel_2", "boom", "pole"]:
		var n := m.find_child(k, true, false) as Node3D
		lv[k] = n
		lv[k + "_rest"] = n.transform if n else Transform3D.IDENTITY
	var blades := []
	for k: String in _blade_axes:
		var b := m.find_child(k, true, false) as Node3D
		if b:
			blades.append({"node": b, "rest": b.transform, "axis": _blade_axes[k]})
	lv["blades"] = blades
	lv["sheet"] = _find_sheet(m)


## The mainsheet tackle of a level, rebuilt as the boom moves: its vertices shear toward the boom end in proportion
## to their height, so the lower block stays on the traveller and the upper one follows the boom. Returns its
## rebuild data ({} without one).
static func _find_sheet(m: Node3D) -> Dictionary:
	var sh := m.find_child("mainsheet", true, false) as MeshInstance3D
	if sh == null or sh.mesh == null or sh.mesh.get_surface_count() != 1:
		return {}
	var arrays := sh.mesh.surface_get_arrays(0)
	var rest: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if rest.is_empty():
		return {}
	var y0 := INF
	var y1 := -INF
	for p in rest:
		y0 = minf(y0, p.y)
		y1 = maxf(y1, p.y)
	var n := 0
	var w := PackedFloat32Array()
	var top := Vector3.ZERO
	w.resize(rest.size())
	for k in rest.size():
		w[k] = (rest[k].y - y0) / maxf(y1 - y0, 1e-3)
		if w[k] > 0.9:
			top += rest[k]
			n += 1
	top /= maxf(n, 1)
	var mat := sh.get_active_material(0)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	sh.mesh = mesh
	return {"node": sh, "mesh": mesh, "arrays": arrays, "rest": rest, "w": w, "top": top}


func _use_sheet(d: Dictionary) -> void:
	_sheet = d.get("node", null)
	_sheet_mesh = d.get("mesh", null)
	_sheet_arrays = d.get("arrays", [])
	_sheet_rest = d.get("rest", PackedVector3Array())
	_sheet_w = d.get("w", PackedFloat32Array())
	_sheet_top = d.get("top", Vector3.ZERO)
	_sheet_angle = INF


## The level of detail for a camera at `dist` m (sail_visuals.md §11.4): coarser past a level's distance plus 5 %,
## finer below it minus 5 %, from the level shown now.
func lod_for(dist: float) -> int:
	var k := lod
	while k + 1 < levels.size() and dist > float(levels[k + 1]["from"]) * 1.05:
		k += 1
	while k > 0 and dist < float(levels[k]["from"]) * 0.95:
		k -= 1
	return k


## Shows the level of detail for a camera at `dist` m (every frame; tests call it directly).
func update_lod(dist: float) -> void:
	_update_casting(dist)
	if sheets:
		sheets.set_detail(sheet_detail_for(dist))
	if levels.size() > 1:
		_show_level(lod_for(dist) if forced_lod < 0 else mini(forced_lod, levels.size() - 1))


func _show_level(k: int) -> void:
	if k == lod or k < 0 or k >= levels.size():
		return
	for n: Node3D in levels[lod]["parts"]:
		n.visible = false
	lod = k
	var lv := levels[k]
	for n: Node3D in lv["parts"]:
		n.visible = not hidden_parts.has(String(n.name))
	_apply_casting()
	_rudder = lv["rudder"]
	_rudder_rest = lv["rudder_rest"]
	_blades = lv["blades"]
	_wheel = lv["wheel"]
	_wheel_rest = lv["wheel_rest"]
	_wheel2 = lv["wheel_2"]
	_wheel2_rest = lv["wheel_2_rest"]
	_boom = lv["boom"]
	_boom_rest = lv["boom_rest"]
	_pole = lv["pole"]
	_pole_rest = lv["pole_rest"]
	_use_sheet(lv["sheet"])
	# the moving parts of the level coming in, at once
	_turn_rudders(_helm)
	if _wheel:
		_wheel.transform = _wheel_rest * Transform3D(Basis(_wheel_axis, _helm * PI), Vector3.ZERO)
	if _wheel2:
		_wheel2.transform = _wheel2_rest * Transform3D(Basis(_wheel_axis, _helm * PI), Vector3.ZERO)
	if _boom:
		_boom.transform = _boom_rest * Transform3D(Basis(_boom_axis, boom_angle), Vector3.ZERO)
	_update_sheet(boom_angle)
	if _pole:
		_pole.visible = _pole_shown
		_pole.transform = _pole_xf(_pole_gamma)


## Sun shadows (sail_visuals.md §11.4): the visible boat meshes cast none, each level's shadow proxy (`shadow`,
## `shadow_boom`, `shadow_rudder`) casts only into the shadow maps, the sails cast their own.
func _setup_shadows() -> void:
	var sails := {}
	for sp in sail_parts:
		sails[sp.node] = true
	for k in levels.size():
		var lv := levels[k]
		var proxies: Array[GeometryInstance3D] = []
		var stack: Array[Node] = [lv["model"]]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			stack.append_array(node.get_children())
			var gi := node as GeometryInstance3D
			if gi == null:
				continue
			if String(gi.name).begins_with("shadow"):
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				proxies.append(gi)
				_proxies.append(gi)
			elif sails.has(gi):
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			else:
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lv["proxies"] = proxies
	_apply_casting()


## Turns this boat's shadow proxies and sails off as casters beyond `cast_distance` (not the own boat).
func _update_casting(dist: float) -> void:
	var on := own or cast_distance <= 0.0 or dist <= cast_distance
	if on == _casting:
		return
	_casting = on
	_apply_casting()


## Whether this boat casts now: `sun_shadows` and within `cast_distance`. A proxy stays SHADOWS_ONLY in every state
## and is hidden when it must not cast (OFF would draw it in the colour pass); only the level shown has its proxies
## shown. The sails go between ON and OFF.
func _apply_casting() -> void:
	var on := sun_shadows and _casting
	for k in levels.size():
		for gi: GeometryInstance3D in levels[k].get("proxies", []):
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			gi.visible = on and k == lod
	for sp in sail_parts:
		if sp.node is GeometryInstance3D:
			(sp.node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Every shadow proxy of this boat, all levels (tests).
func shadow_proxies() -> Array[GeometryInstance3D]:
	return _proxies


## The running sheets' detail for a camera at `dist` m (§11.3), by the size of a metre on screen: full while a metre
## is at least SHEET_PX_FULL pixels tall (about 30 m at 1080 lines and 60 deg), thin lines to SHEET_PX_THIN (about
## 100 m), none beyond. The camera of the frame (begin_frame) gives the field of view, else 60 deg.
const SHEET_PX_FULL := 31.0
const SHEET_PX_THIN := 9.4
const SHEET_SCREEN_LINES := 1080.0


func sheet_detail_for(dist: float) -> int:
	var t := _cam_tan if is_instance_valid(_frustum_cam) and _cam_tan > 0.0 else tan(deg_to_rad(30.0))
	var px := SHEET_SCREEN_LINES / maxf(2.0 * dist * t, 1e-3)
	return 0 if px >= SHEET_PX_FULL else (1 if px >= SHEET_PX_THIN else 2)


func _apply_lod_bias() -> void:
	for gi in find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).lod_bias = OWN_LOD_BIAS if own or forced_lod == 0 else 1.0


## The engine's levels of detail of a sail (§11.4): the index buffers of every 2nd and every 4th row and column of
## its grid over the same vertex buffer (the per-vertex update keeps writing it whole), keyed by their geometric
## error: a cambered row of n segments deviates from its arc by about camber / n² of the chord, taken three times
## over for the shading. The renderer picks one by its size on screen.
func _sail_lods(sp: SailPart, idx: PackedInt32Array, rest_mid: PackedVector3Array, camber: float) -> Dictionary:
	var chord := 0.0
	for i in sp.rows:
		chord = maxf(chord, rest_mid[i * sp.cols].distance_to(rest_mid[i * sp.cols + sp.cols - 1]))
	var out := {}
	for step in [2, 4]:
		var segs := maxf((sp.cols - 1) / float(step), 1.0)
		if segs < 2.0 and step > 2:
			continue
		out[3.0 * camber * chord / (segs * segs)] = sail_indices(idx, sp.rows, sp.cols, step)
	return out


## The triangles of a two-layer sail grid (§3.1: layer k's vertex (i, j) is k·rows·cols + i·cols + j) on every
## `step`-th row and column and the last ones, wound as the full grid `full` winds each layer.
static func sail_indices(full: PackedInt32Array, rows: int, cols: int, step: int) -> PackedInt32Array:
	if step <= 1 or full.size() < 3:
		return full
	var rs: Array[int] = []
	for i in range(0, rows, step):
		rs.append(i)
	if rs[-1] != rows - 1:
		rs.append(rows - 1)
	var cs: Array[int] = []
	for j in range(0, cols, step):
		cs.append(j)
	if cs[-1] != cols - 1:
		cs.append(cols - 1)
	var n := rows * cols
	var out := PackedInt32Array()
	for layer in 2:
		# the full grid's winding on this layer: the sign of its first non-degenerate triangle in (column, row)
		var flip := false
		for t in range(0, full.size(), 3):
			if (full[t] >= n) != (layer == 1):
				continue
			var p: Array[Vector2] = []
			for q in 3:
				var g := full[t + q] - layer * n
				p.append(Vector2(g % cols, g / cols))
			var c := (p[1] - p[0]).cross(p[2] - p[0])
			if absf(c) > 1e-6:
				flip = c < 0.0
				break
		var base := layer * n
		for a in rs.size() - 1:
			for b in cs.size() - 1:
				var i0 := base + rs[a] * cols
				var i1 := base + rs[a + 1] * cols
				var v00 := i0 + cs[b]
				var v01 := i0 + cs[b + 1]
				var v11 := i1 + cs[b + 1]
				var v10 := i1 + cs[b]
				if flip:
					out.append_array(PackedInt32Array([v00, v11, v01, v00, v10, v11]))
				else:
					out.append_array(PackedInt32Array([v00, v01, v11, v00, v11, v10]))
	return out


static func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## Rotation by `angle` about the line through `p` along `axis` (right-handed).
static func _about(p: Vector3, axis: Vector3, angle: float) -> Transform3D:
	var b := Basis(axis, angle)
	return Transform3D(b, p - b * p)


## The rudder node (blade and tiller, or the tiller alone) and any twin blades turned to helm h: +h * rudder_max
## about each one's own upward stock axis.
func _turn_rudders(h: float) -> void:
	if _rudder:
		_rudder.transform = _rudder_rest * Transform3D(Basis(_rudder_axis, h * _rudder_max), Vector3.ZERO)
	for b: Dictionary in _blades:
		(b["node"] as Node3D).transform = (b["rest"] as Transform3D) * Transform3D(Basis(b["axis"], h * _rudder_max), Vector3.ZERO)


func apply(p: SimSource.RenderPose) -> void:
	transform = Frames.boat_transform(p.pos_x, p.pos_y, p.z, p.psi, p.theta, p.phi)
	_helm = p.h
	# helm h > 0 turns the bow to starboard: the blade's trailing edge swings to starboard (model -X) and a tiller
	# on the stock to port, a turn of +h * rudder_max about the upward stock axis
	_turn_rudders(p.h)
	if _wheel:
		_wheel.transform = _wheel_rest * Transform3D(Basis(_wheel_axis, p.h * PI), Vector3.ZERO)
	if _wheel2:
		_wheel2.transform = _wheel2_rest * Transform3D(Basis(_wheel_axis, p.h * PI), Vector3.ZERO)


## The sail's own grid-order mesh (sail_visuals.md §3.1) and its per-vertex shape. The imported flat sail gives
## the rest positions and the uv sets, SailGrid maps each imported vertex to its grid index, the triangles are the
## imported ones re-indexed, and the node's transform is folded into the vertices (the node stays the identity).
func _setup_shape(sp: SailPart, side: Dictionary, furling: bool) -> void:
	var mi := sp.node as MeshInstance3D
	sp.rows = int(side.get("grid_rows", 0))
	sp.cols = int(side.get("grid_cols", 0))
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() < 1 or sp.rows < 2 or sp.cols < 2:
		return
	var src := mi.mesh
	var arrays := src.surface_get_arrays(0)
	var gi := SailGrid.grid_index(src, sp.rows, sp.cols)
	var n := sp.rows * sp.cols
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	pos.resize(2 * n)
	uv.resize(2 * n)
	uv2.resize(2 * n)
	var seen := PackedByteArray()
	seen.resize(2 * n)
	var ipos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var iuv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var iuv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	for v in ipos.size():
		var g := gi[v]
		if g < 0:
			push_warning("%s: vertex %d is not on the sail grid; the sail stays flat" % [sp.node.name, v])
			return
		pos[g] = sp.rest * ipos[v]
		if iuv.size() == ipos.size():
			uv[g] = iuv[v]
		uv2[g] = iuv2[v]
		seen[g] = 1
	if seen.count(1) != 2 * n:
		push_warning("%s: the imported sail misses grid vertices; the sail stays flat" % sp.node.name)
		return
	var idx := PackedInt32Array()
	var iidx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	idx.resize(iidx.size())
	for t in iidx.size():
		idx[t] = gi[iidx[t]]
	var nrm := PackedVector3Array()
	nrm.resize(2 * n)
	var rest_mid := PackedVector3Array()
	rest_mid.resize(n)
	for k in n:
		rest_mid[k] = 0.5 * (pos[k] + pos[n + k])
		nrm[k] = sp.nh
		nrm[n + k] = -sp.nh
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = pos
	out[Mesh.ARRAY_NORMAL] = nrm
	out[Mesh.ARRAY_TEX_UV] = uv
	out[Mesh.ARRAY_TEX_UV2] = uv2
	out[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	var look0: Dictionary = side.get("look", {}) if side.get("look") is Dictionary else {}
	var camber := float(look0.get("camber", 0.27 if sp.type.begins_with("spinnaker") else 0.12))
	# no compression flags: plain floats (§11); the engine's levels of detail on reduced grids (§11.4)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], _sail_lods(sp, idx, rest_mid, camber))
	mesh.surface_set_material(0, BoatMaterials.sail_cloth(_sail_material(mi.get_active_material(0)), sp.type, info,
			String(sp.node.name), pos, uv, uv2, sp.rows, sp.cols))
	# a sphere around the sail at any angle: the rest sail about its luff centre, plus the belly, the swing
	# and the twist
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for q in rest_mid:
		lo = lo.min(q)
		hi = hi.max(q)
	sp.centre = 0.5 * (sp.tack + sp.head)
	var r := 0.0
	for q in rest_mid:
		r = maxf(r, q.distance_to(sp.centre))
	var extra := 0.0
	if sp.mode == Mode.POLE:
		extra = 2.0 * _mast_step.distance_to(sp.tack)
	elif sp.mode == Mode.BOOM:
		extra = _boom_pivot.distance_to(sp.tack)
	sp.radius = r * 1.25 + extra + 0.5
	mesh.custom_aabb = AABB(sp.centre - Vector3.ONE * sp.radius, Vector3.ONE * 2.0 * sp.radius)
	# §4, §4.1: the look and a kite's set parameters, the class file's blocks over the sidecar's copies
	var look: Dictionary = (side.get("look", {}) as Dictionary).duplicate() if side.get("look") is Dictionary else {}
	var entry := KiteSet.class_entry(class_file, sp.id)
	if entry.get("look") is Dictionary:
		look.merge(entry["look"], true)
	sp.look = look
	sp.rest_mid = rest_mid
	sp.furling = furling
	if KiteSet.is_kite(sp.type):
		sp.kset = KiteSet.resolve(sp.type, entry["set"] if entry.get("set") is Dictionary else side.get("set", {}))
	var params := _shape_params(sp, look, furling)
	var shape: Variant = null
	if not use_reference and ClassDB.class_exists("SailShape"):
		shape = ClassDB.instantiate("SailShape")
	else:
		shape = SailShapeRef.new()
	if sp.mode == Mode.BOOM:  # §7.6 the main's region for its stop on a flying sail's sheet
		var foot := rest_mid[sp.cols - 1] - _boom_pivot
		foot -= _boom_axis * foot.dot(_boom_axis)
		sp.stop_aft = foot / maxf(foot.length(), 1e-6)
		sp.stop_span = 0.0
		for q in rest_mid:  # the farthest the rest sail reaches aft (the roach)
			sp.stop_span = maxf(sp.stop_span, (q - _boom_pivot).dot(sp.stop_aft))
		sp.stop_z0 = (rest_mid[0] - _boom_pivot).dot(_boom_axis)
		sp.stop_z1 = (rest_mid[(sp.rows - 1) * sp.cols] - _boom_pivot).dot(_boom_axis)
	if not shape.configure(rest_mid, sp.rows, sp.cols, params):
		push_warning("%s: sail shape set-up failed; the sail stays flat" % sp.node.name)
		return
	mi.mesh = mesh
	mi.transform = Transform3D.IDENTITY
	sp.rest = Transform3D.IDENTITY
	sp.tack_rise_m = float(sp.kset.get("tack_rise", 0.0)) * float(shape.frame()["sl"])
	if not shape.attach_mesh(mesh.get_rid()):
		push_warning("%s: sail mesh layout not writable in place; rebuilding it each update" % sp.node.name)
		sp.arrays = out
	sp.mesh = mesh
	sp.shape = shape
	sp.uv0 = uv


## sail_visuals.md §4: the look block of the sidecar (the generator fills the defaults), with the table's
## defaults and size rules for anything missing, and the rig numbers of §7.
func _shape_params(sp: SailPart, look: Dictionary, furling: bool) -> Dictionary:
	var kind := SailShapeRef.Kind.HEADSAIL
	var t := sp.type
	var d := {"fill_gain": 0.75, "fill_curve": 1.2, "flutter_amp": 0.07, "twist_top": 0.175}
	if t == "main":
		kind = SailShapeRef.Kind.MAIN
		d = {"fill_gain": 0.6, "fill_curve": 4.0, "flutter_amp": 0.15, "twist_top": 0.070}
	elif t == "code_zero":
		d = {"fill_gain": 0.7, "fill_curve": 1.3, "flutter_amp": 0.08, "twist_top": 0.140, "camber": 0.12}
	elif t == "spinnaker_asym":
		kind = SailShapeRef.Kind.ASYM
		d = {"fill_gain": 1.0, "fill_curve": 1.0, "flutter_amp": 1.0, "twist_top": 0.45, "camber": 0.27,
			"tack_line_max": 0.0}
	elif t == "spinnaker_sym":
		kind = SailShapeRef.Kind.SYM
		d = {"fill_gain": 1.5, "fill_curve": 1.5, "flutter_amp": 1.0, "twist_top": 0.0, "camber": 0.30}
	var loa := info.loa
	d["flutter_rate"] = 0.6 + 2.4 * clampf((12.0 - loa) / 5.0, 0.0, 1.0)
	d["flutter_rate_max"] = 9.0 + clampf((loa - 7.0) / 5.0, 0.0, 1.0)
	var p := {}
	for k in d:
		p[k] = float(look.get(k, d[k]))
	# sail_visuals.md §4: a look block's old `depth` key is ignored
	for k in ["camber", "tack_line_max", "furl_radius"]:
		if look.has(k):
			p[k] = float(look[k])
	p["kind"] = kind
	p["mode"] = sp.mode
	p["furling"] = furling and kind == SailShapeRef.Kind.HEADSAIL
	p["boom_pivot"] = _boom_pivot
	p["boom_axis"] = _boom_axis
	p["mast_step"] = _mast_step
	p["mast_axis"] = _mast_axis
	p["fwd"] = Frames.body_to_model(Vector3(1, 0, 0))
	p["port"] = Frames.body_to_model(Vector3(0, 1, 0))
	p["up"] = Frames.body_to_model(Vector3(0, 0, 1))
	p["phi"] = randf() * TAU  # §5.2: boats and sails do not flutter in step
	p.merge(sp.kset, true)  # §4.1 a kite's set parameters (every key, filled from the defaults of its type)
	if is_flying(t):  # §7.4: kept clear of the other sails and the mast
		p["clearance"] = 0.042 * loa
		p["mast_head"] = _mast_head
		if _has_flying_lead:  # §7.5, §7.6 its sheet's lead block
			p["sheet_lead"] = _flying_lead
		if _has_stay and sp.mode == Mode.POLE:  # §7.4 forward of the forestay
			p["forestay_tack"] = _stay0
			p["hounds"] = _stay1
	return p


## sail_visuals.md §4.1: shape a kite again with a look and set parameters (the kite tuner): `look_over` goes over
## its look as configured, `kset` over the defaults of its type. Keeps its flutter phase; false when the sail is not
## a kite with a shape.
func reshape_kite(sail_id: String, look_over: Dictionary, kset: Dictionary) -> bool:
	for sp in sail_parts:
		if sp.id != sail_id or sp.shape == null or not KiteSet.is_kite(sp.type):
			continue
		var look := sp.look.duplicate()
		look.merge(look_over, true)
		var old_kset := sp.kset
		sp.kset = KiteSet.resolve(sp.type, kset)
		var p := _shape_params(sp, look, sp.furling)
		p["phi"] = sp.shape.get_phase()
		if not sp.shape.configure(sp.rest_mid, sp.rows, sp.cols, p):
			sp.kset = old_kset
			return false
		sp.tack_rise_m = float(sp.kset["tack_rise"]) * float(sp.shape.frame()["sl"])
		sp.updates = 0
		return true
	return false


## The pole at its angle gamma, tilted about its heel by the raised tack of the kite on it (§4.1).
func _pole_xf(gamma: float) -> Transform3D:
	var t := _pole_rest * Transform3D(Basis(_pole_axis, gamma), Vector3.ZERO)
	if _pole_tilt != 0.0 and _pole_tilt_axis != Vector3.ZERO:
		t = t * Transform3D(Basis(_pole_tilt_axis, _pole_tilt), Vector3.ZERO)
	return t


## sail_visuals.md §7.4: the sails that keep clear of the others (spinnakers and the code zero).
static func is_flying(type: String) -> bool:
	return type.begins_with("spinnaker") or type == "code_zero"


## §7.4: the obstacles of a flying sail, the other sails that are shown, as last placed.
func _obstacles(sp: SailPart) -> Array:
	var out := []
	for o in sail_parts:
		if o != sp and o.shape != null and o.node.visible and not is_flying(o.type):
			out.append(o.shape)
	return out


## §11: the generator's sailcloth on shaders/sail.gdshader: opaque, back faces culled, roughness about 0.55 and a
## back-light of about 0.3 of the albedo so the sun shows through the cloth. Takes the colour, texture and tiling of
## the imported slot (a StandardMaterial3D, or the boat ShaderMaterial BoatMaterials put in its place).
func _sail_material(m: Material) -> Material:
	if m == null:
		return m
	if _sail_mats.has(m):
		return _sail_mats[m]
	var s := ShaderMaterial.new()
	s.shader = SAIL_SHADER
	s.resource_name = m.resource_name
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		s.set_shader_parameter("albedo_color", b.albedo_color)
		s.set_shader_parameter("albedo_tex", b.albedo_texture)
		s.set_shader_parameter("uv_scale", Vector2(b.uv1_scale.x, b.uv1_scale.y))
	elif m is ShaderMaterial:
		for k in ["albedo_color", "albedo_tex", "uv_scale"]:
			var v: Variant = (m as ShaderMaterial).get_shader_parameter(k)
			if v != null:
				s.set_shader_parameter(k, v)
	_sail_mats[m] = s
	return s


## Places the boom, the mainsheet, the pole and the sails at the render fraction `alpha` between the sail states
## of the last two ticks (`prev` may be null: the newest only). sail_visuals.md §2: beta, pole and awa with angle
## lerp, progress with lerp when both have the same phase, luff shiver and the apparent wind speed with lerp, the
## phase and backed the newer one's. `dt` is the frame time (s; negative: the node's process delta).
func apply_sails(prev: SimSource.SailsView, cur: SimSource.SailsView, alpha: float, dt: float = -1.0) -> void:
	if model == null or cur == null:
		return
	if dt < 0.0:
		dt = get_process_delta_time() if is_inside_tree() else 0.0
	dt = clampf(dt, 0.0, 0.1)
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		update_lod(cam.global_position.distance_to(global_position))
	# §11: the boat's sails, boom, pole and sheets at the rate of its size on screen and distance; between updates
	# nothing is placed and the frame times add up for the next one
	_sail_dt += dt
	if cam != null and draw_sails and not full_rate and not _sails_due(cam):
		return
	dt = minf(_sail_dt, FAR_INTERVAL)
	_sail_dt = 0.0
	var p0 := prev if prev != null else cur
	var awa := Frames.wrap_pi(p0.awa + Frames.angle_diff(cur.awa, p0.awa) * alpha)
	var aws := lerpf(p0.aws, cur.aws, alpha)
	var drawn := false
	for sp in sail_parts:
		if sp.index >= cur.sails.size():
			continue
		var s1: SimSource.SailState = cur.sails[sp.index]
		var s0: SimSource.SailState = s1
		if sp.index < p0.sails.size():
			s0 = p0.sails[sp.index]
		sp.beta = Frames.wrap_pi(s0.beta + Frames.angle_diff(s1.beta, s0.beta) * alpha)
		sp.gamma = Frames.wrap_pi(s0.pole + Frames.angle_diff(s1.pole, s0.pole) * alpha)
		var prog := lerpf(s0.progress, s1.progress, alpha) if s0.phase == s1.phase else s1.progress
		var shiver := 0.0
		var backed := false
		if sp.index < cur.out.size():
			var o1: SimSource.SailOutput = cur.out[sp.index]
			var o0: SimSource.SailOutput = p0.out[sp.index] if sp.index < p0.out.size() else o1
			shiver = lerpf(o0.luff_shiver, o1.luff_shiver, alpha)
			backed = o1.backed
		sp.phase = s1.phase
		sp.shiver = shiver
		if sp.mode == Mode.BOOM:
			var core_beta := sp.beta
			sp.beta = _main_stopped(sp)
			main_stop = sp.beta - core_beta
		var placed := _place(sp, s1.phase, prog, shiver, backed, awa, aws, dt)
		drawn = placed or drawn
		if sp.mode == Mode.BOOM:
			boom_angle = sp.beta
			if _boom:
				_boom.transform = _boom_rest * Transform3D(Basis(_boom_axis, sp.beta), Vector3.ZERO)
			if placed or sp.shape == null:
				_update_sheet(sp.beta)  # §11.3: the mainsheet tackle at the main's rate
		elif sp.mode == Mode.POLE:
			_pole_shown = s1.phase != SimSource.Phase.DOWN
			_pole_gamma = sp.gamma
			_pole_tilt = 0.0
			if sp.tack_rise_m > 0.0 and _pole_len > 1e-3 and sp.shape != null:
				_pole_tilt = asin(clampf(sp.tack_rise_m * float(sp.shape.sheet_weight()) / _pole_len, 0.0, 1.0))
			if _pole:
				_pole.visible = _pole_shown
				if _pole.visible:
					_pole.transform = _pole_xf(sp.gamma)
	if sheets:
		# §11.3: with the sails; thin (sub-pixel ropes) at most at the 15 Hz of §11
		_sheets_since += dt
		var due := drawn and (sheets.detail == 0 or _sheets_since + 1e-6 >= MID_INTERVAL)
		if due:
			_sheets_since = 0.0
		sheets.step(aws, dt, due)


## §7.6: the main's drawn angle: it stops on the straight sheet of the flying sail shown (its clew and angle as last
## placed), `c` short of it; the core's angle when no flying sail is set.
func _main_stopped(main: SailPart) -> float:
	var fl: SailPart = null
	var w := 0.0
	for o in sail_parts:
		if o == main or o.shape == null or not is_flying(o.type) or not o.node.visible or o.updates == 0:
			continue
		var wo: float = o.shape.sheet_weight() if o.shape.has_method("sheet_weight") else 0.0
		if wo > w:
			w = wo
			fl = o
	if fl == null or main.stop_span <= 0.0 or not _has_flying_lead:
		return main.beta
	var c := 0.042 * info.loa
	return stop_angle(main.beta, fl.shape.sheet_clew(), fl.shape.working_lead(fl.beta), _boom_pivot, _boom_axis, main.stop_aft,
		main.stop_span, -main.stop_z0, main.stop_z1, c, w)


## §7.6: the main's angle eased out from the centreline up to |beta| until its region (the vertical rectangle through
## the gooseneck `g` along `aft` turned by the angle about `up`, `span` long, `z0` to `z1` up from `g`) first comes
## within `c` of the sheet `clew`-`lead`; blended in by `w`.
static func stop_angle(beta: float, clew: Vector3, lead: Vector3, g: Vector3, up: Vector3, aft: Vector3,
		span: float, z0: float, z1: float, c: float, w: float) -> float:
	if w <= 0.0 or c <= 0.0:
		return beta
	var p0 := clew - g
	var p1 := lead - g
	var sb := 1.0 if beta >= 0.0 else -1.0
	var b := absf(beta)
	var lo := -1.0
	var hi := 0.0
	for k in range(1, STOP_SCAN + 1):
		var th := b * k / STOP_SCAN
		if rect_gap(p0, p1, aft.rotated(up, sb * th), up, span, z0, z1) < c:
			lo = b * (k - 1) / STOP_SCAN
			hi = th
			break
	if lo < 0.0:
		return beta
	for _i in STOP_STEPS:
		var m := 0.5 * (lo + hi)
		if rect_gap(p0, p1, aft.rotated(up, sb * m), up, span, z0, z1) >= c:
			lo = m
		else:
			hi = m
	return sb * (b - w * (b - lo))


## §7.6: the distance of the segment p0-p1 (from the gooseneck) from the vertical rectangle along `u`, 0 to `span`
## long and `z0` to `z1` high; 0 when the segment passes through it.
static func rect_gap(p0: Vector3, p1: Vector3, u: Vector3, up: Vector3, span: float, z0: float, z1: float) -> float:
	var nv := up.cross(u)
	var n0 := p0.dot(nv)
	var n1 := p1.dot(nv)
	if n0 * n1 <= 0.0 and n0 != n1:
		var q := p0 + (p1 - p0) * (n0 / (n0 - n1))
		var qs := q.dot(u)
		var qz := q.dot(up)
		if qs >= 0.0 and qs <= span and qz >= z0 and qz <= z1:
			return 0.0
	var corners := [up * z0, u * span + up * z0, u * span + up * z1, up * z1]
	var best := minf(_rect_pt(p0, u, up, nv, span, z0, z1), _rect_pt(p1, u, up, nv, span, z0, z1))
	for e in 4:
		var pts := Geometry3D.get_closest_points_between_segments(p0, p1, corners[e], corners[(e + 1) % 4])
		best = minf(best, pts[0].distance_to(pts[1]))
	return best


static func _rect_pt(p: Vector3, u: Vector3, up: Vector3, nv: Vector3, span: float, z0: float, z1: float) -> float:
	var s := p.dot(u)
	var z := p.dot(up)
	var nn := p.dot(nv)
	var ds := maxf(0.0, maxf(-s, s - span))
	var dz := maxf(0.0, maxf(z0 - z, z - z1))
	return sqrt(nn * nn + ds * ds + dz * dz)


## Bends and places one sail; true when its mesh was redrawn (or it was shown or hidden) this frame.
func _place(sp: SailPart, phase: int, prog: float, shiver: float, backed: bool, awa: float, aws: float,
		dt: float) -> bool:
	var was := sp.node.visible
	if not draw_sails:
		sp.node.visible = false
		return was
	sp.node.visible = phase != SimSource.Phase.DOWN or sp.mode == Mode.BOOM
	_hoist_fractions(sp, phase, prog)
	if sp.shape == null:
		return was != sp.node.visible
	sp.shape.advance(dt, aws, awa, backed)  # the flutter phase and the backed factor run on, drawn or not
	sp.since += dt
	if not sp.node.visible or (not animate_sails and sp.updates > 0):
		return was != sp.node.visible
	sp.since = 0.0
	sp.updates += 1
	if is_flying(sp.type):
		sp.shape.set_obstacles(_obstacles(sp))
	sp.shape.update(phase, prog, sp.beta, sp.gamma, shiver, awa, aws)
	if sp.arrays.is_empty():
		sp.shape.write_mesh()
	else:
		var mat := sp.mesh.surface_get_material(0)
		sp.arrays[Mesh.ARRAY_VERTEX] = sp.shape.positions()
		sp.arrays[Mesh.ARRAY_NORMAL] = sp.shape.normals()
		sp.mesh.clear_surfaces()
		sp.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sp.arrays)
		sp.mesh.surface_set_material(0, mat)
	return true


## A new frame for the sails (the scene calls it once before the boats; else the first sail of a frame does): the
## camera's frustum is read once for the fleet.
static func begin_frame(cam: Camera3D = null) -> void:
	_frustum_frame = -1
	if cam != null:
		_read_camera(cam)


static func _read_camera(cam: Camera3D) -> void:
	_frustum = cam.get_frustum()
	_frustum_cam = cam
	_frustum_frame = Engine.get_process_frames()
	if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		_cam_tan = 0.0
		_cam_size = cam.size
	else:
		_cam_tan = tan(deg_to_rad(cam.fov) * 0.5)


## §11 update rate of the boat's sails (a sphere around them all): every frame when large on screen (the sphere
## at least FULL_RATE_SCREEN of the screen height), at near_interval for the others nearer than 200 m, 15 Hz to
## 800 m, 4 Hz beyond, not at all outside the view frustum (the next update in view comes at once). The boats
## keep out of step (_stagger), so a rate's updates spread over its frames.
func _sails_due(cam: Camera3D) -> bool:
	if _frustum_frame != Engine.get_process_frames() or _frustum_cam != cam:
		_read_camera(cam)
	if _sail_radius < 0.0:
		_sail_sphere()
	var c := global_transform * _sail_centre
	for pl in _frustum:
		if pl.distance_to(c) > _sail_radius:
			_sail_fresh = true
			return false
	var dist := cam.global_position.distance_to(c)
	var interval := FAR_INTERVAL
	if dist < NEAR_M:
		var screen := 2.0 * _sail_radius / _cam_size if _cam_tan <= 0.0 \
				else _sail_radius / maxf(dist * _cam_tan, 1e-3)
		interval = 0.0 if screen >= FULL_RATE_SCREEN else near_interval
	elif dist < MID_M:
		interval = MID_INTERVAL
	if _sail_fresh:
		_sail_fresh = false
		_sail_wait = _stagger * interval  # the first update in a while starts the boat's place in the rhythm
		return true
	if _sail_dt + 1e-6 < interval + _sail_wait:
		return false
	_sail_wait = 0.0
	return true


## The sphere around every sail of the boat (each sail's sphere, §11 custom AABB).
func _sail_sphere() -> void:
	var n := 0
	var c := Vector3.ZERO
	for sp in sail_parts:
		c += sp.centre
		n += 1
	_sail_centre = c / maxf(n, 1)
	_sail_radius = 1.0
	for sp in sail_parts:
		_sail_radius = maxf(_sail_radius, sp.centre.distance_to(_sail_centre) + sp.radius)


## §8.1 for the tests: how much of the luff is hoisted and how far the flying shape has filled.
func _hoist_fractions(sp: SailPart, phase: int, prog: float) -> void:
	sp.luff_scale = 1.0
	sp.chord_scale = 1.0
	if sp.mode == Mode.BOOM or phase == SimSource.Phase.UP or phase == SimSource.Phase.PREPARE_DROP:
		return
	if not sp.type.begins_with("spinnaker"):
		var p := 0.0
		if phase == SimSource.Phase.HOISTING:
			p = prog
		elif phase == SimSource.Phase.DROPPING:
			p = 1.0 - prog
		sp.luff_scale = clampf(p, 0.0, 1.0)
		return
	if phase == SimSource.Phase.DROPPING:
		sp.luff_scale = clampf(1.0 - prog, 0.0, 1.0)
		sp.chord_scale = 1.0 - pow(clampf(prog, 0.0, 1.0), 0.3)
		return
	var c := prog if phase == SimSource.Phase.HOISTING else 0.0
	sp.luff_scale = minf(c / 0.9, 1.0)
	var kk := clampf((c - 0.9) / 0.1, 0.0, 1.0)
	sp.chord_scale = kk * kk


func _update_sheet(beta: float) -> void:
	if _sheet == null or absf(beta - _sheet_angle) < 1e-3:
		return
	var first := is_inf(_sheet_angle)
	_sheet_angle = beta
	var d := _about(_boom_pivot, _boom_axis, beta) * _sheet_top - _sheet_top
	var v := PackedVector3Array()
	v.resize(_sheet_rest.size())
	for k in v.size():
		v[k] = _sheet_rest[k] + d * _sheet_w[k]
	if first:
		_sheet_in_place = _sheet_writable()
	if _sheet_in_place:
		# §11: the positions rewritten in place (the normals stay the rest ones, as when rebuilt)
		RenderingServer.mesh_surface_update_vertex_region(_sheet_mesh.get_rid(), 0, 0, v.to_byte_array())
		return
	var mat := _sheet_mesh.surface_get_material(0)
	_sheet_arrays[Mesh.ARRAY_VERTEX] = v
	_sheet_mesh.clear_surfaces()
	_sheet_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _sheet_arrays)
	_sheet_mesh.surface_set_material(0, mat)


## The mainsheet's positions as drawn now (model frame of its level): the rest tackle sheared toward the boom end at
## the boom angle drawn (tests and the offline previews; the renderer may hold them in place only).
func sheet_positions() -> PackedVector3Array:
	var v := PackedVector3Array()
	if _sheet == null:
		return v
	var d := _about(_boom_pivot, _boom_axis, boom_angle) * _sheet_top - _sheet_top
	v.resize(_sheet_rest.size())
	for k in v.size():
		v[k] = _sheet_rest[k] + d * _sheet_w[k]
	return v


## The mainsheet node shown now, null without one.
func sheet_node() -> MeshInstance3D:
	return _sheet


## Whether the mainsheet's positions can be rewritten in place: an uncompressed surface whose vertex stream is the
## positions alone (stride 12). Sets its custom AABB to cover the tackle at any boom angle.
func _sheet_writable() -> bool:
	if _sheet_mesh == null or _sheet_mesh.get_surface_count() != 1:
		return false
	var fmt := _sheet_mesh.surface_get_format(0)
	if fmt & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES:
		return false
	var n := _sheet_rest.size()
	if RenderingServer.mesh_surface_get_format_vertex_stride(fmt, n) != 12:
		return false
	var reach := 2.0 * _boom_pivot.distance_to(_sheet_top) + 0.5
	var box := AABB(_sheet_rest[0], Vector3.ZERO)
	for p in _sheet_rest:
		box = box.expand(p)
	_sheet_mesh.custom_aabb = box.grow(reach)
	return true


## The state of this boat's drawn shadow on the water (BoatShadows.update_boat, water_render.md §4.7): the body
## frame at the render pose, the hull and mast from the physics sidecar, and the outline of every sail shown.
func shadow_state(own: bool) -> Dictionary:
	if _shadow_caster == null:
		_shadow_caster = BoatShadows.caster_from_physics(info.physics)
	var pts := PackedVector3Array()
	var counts := PackedInt32Array()
	shadow_sails(pts, counts)
	return {
		"xform": (model.global_transform if model else global_transform) * BODY_TO_MODEL,
		"caster": _shadow_caster, "sails": pts, "sail_counts": counts, "own": own,
	}


## The outline points of every sail shown, in the scene (BoatShadows.sail_indices of its placed mid-surface).
func shadow_sails(points: PackedVector3Array, counts: PackedInt32Array) -> void:
	for sp in sail_parts:
		if sp.shape == null or not sp.node.visible:
			continue
		if sp.shadow_idx.is_empty():
			sp.shadow_idx = BoatShadows.sail_indices(sp.rows, sp.cols)
		points.append_array(sp.node.global_transform * (sp.shape.mid_points(sp.shadow_idx) as PackedVector3Array))
		counts.append(sp.shadow_idx.size())
