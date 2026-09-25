class_name BoatView
extends Node3D
## The generated boat in the scene (conventions.md §11): the boatgen GLB under a node placed at the render pose,
## the rudder (with the tiller it carries) and the wheel turned by the helm, the boom and the mainsheet following
## the main's sail angle, and the sails placed rigidly from the sail state (sail_visuals.md §7, the static
## generated shape; the per-vertex shapes of §6 and §8 come with the sail visuals task, WM-016.09). Hoisting and
## dropping (§8) are shown by scaling the flat sail in its own frame: a headsail on a halyard grows up its luff
## from the deck, a spinnaker climbs the luff as a thin bundle and widens over the last tenth, a drop runs back.

## the flattest a sail is drawn while it lies on deck or climbs as a bundle (fraction of its luff or chord)
const MIN_SCALE := 0.02
const BUNDLE := 0.05

enum Mode { BOOM, LUFF, SPRIT, POLE }

## one sail of the class and how it is placed
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
	## BOOM (the main), LUFF (about the stay or sprit line), SPRIT (asymmetric on a bowsprit), POLE
	var mode := 0
	var tack_line_max := 0.0
	var r_h := 1.0  # horizontal distance from the head to the rest tack
	## drawn this frame (tests): sail angle, pole angle, luff and chord scale
	var beta := 0.0
	var gamma := 0.0
	var luff_scale := 1.0
	var chord_scale := 1.0


var info: SimSource.ClassInfo
## the imported boat root (the GLB's child named after the class), null when the GLB is missing
var model: Node3D
var sail_parts: Array[SailPart] = []
## the boom angle drawn this frame (the main's interpolated beta)
var boom_angle := 0.0
var _rudder: Node3D
var _rudder_rest := Transform3D.IDENTITY
var _rudder_axis := Vector3.UP
var _wheel: Node3D
var _wheel_rest := Transform3D.IDENTITY
var _wheel_axis := Vector3.BACK
var _rudder_max := 0.6
var _boom: Node3D
var _boom_rest := Transform3D.IDENTITY
var _boom_axis := Vector3.UP
var _boom_pivot := Vector3.ZERO
var _pole: Node3D
var _pole_rest := Transform3D.IDENTITY
var _pole_axis := Vector3.UP
var _mast_step := Vector3.ZERO
var _mast_axis := Vector3.UP
var _sheet: MeshInstance3D
var _sheet_mesh: ArrayMesh
var _sheet_arrays: Array = []
var _sheet_rest := PackedVector3Array()
var _sheet_w := PackedFloat32Array()
var _sheet_top := Vector3.ZERO
var _sheet_angle := 0.0


static func create(class_info: SimSource.ClassInfo, rudder_max: float) -> BoatView:
	var b := BoatView.new()
	b.name = "Boat_" + class_info.id
	b.info = class_info
	b._rudder_max = rudder_max
	var path := "res://generated/boats/%s.glb" % class_info.id
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		var wrapper := scene.instantiate() as Node3D
		b.add_child(wrapper)
		b.model = wrapper.get_child(0) as Node3D if wrapper.get_child_count() > 0 else wrapper
	else:
		push_warning("%s not generated (run game/tests/run_boat_import_test.sh); drawing a box" % path)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(class_info.beam_max, 1.0, class_info.loa)
		mi.mesh = bm
		b.add_child(mi)
	b._find_parts()
	return b


func _find_parts() -> void:
	if model == null:
		return
	var rig: Dictionary = info.physics.get("rig", {})
	_rudder = model.find_child("rudder", true, false) as Node3D
	if _rudder:
		_rudder_rest = _rudder.transform
		if rig.has("rudder_axis"):
			_rudder_axis = Frames.body_to_model(_vec(rig["rudder_axis"])).normalized()
	_wheel = model.find_child("wheel", true, false) as Node3D
	if _wheel:
		_wheel_rest = _wheel.transform
		if rig.has("wheel_axis"):
			_wheel_axis = Frames.body_to_model(_vec(rig["wheel_axis"])).normalized()
	_boom = model.find_child("boom", true, false) as Node3D
	if _boom:
		_boom_rest = _boom.transform
		_boom_pivot = _boom_rest.origin
	if rig.has("boom_axis"):
		_boom_axis = Frames.body_to_model(_vec(rig["boom_axis"])).normalized()
	if rig.has("boom_pivot"):
		_boom_pivot = Frames.body_to_model(_vec(rig["boom_pivot"]))
	if rig.has("mast_step") and rig.has("masthead"):
		_mast_step = Frames.body_to_model(_vec(rig["mast_step"]))
		_mast_axis = (Frames.body_to_model(_vec(rig["masthead"])) - _mast_step).normalized()
	_pole = model.find_child("pole", true, false) as Node3D
	if _pole:
		_pole_rest = _pole.transform
		if rig.has("pole_axis"):
			_pole_axis = Frames.body_to_model(_vec(rig["pole_axis"])).normalized()
	_find_sheet()
	var side_sails: Dictionary = info.physics.get("sails", {})
	var pole_class := _pole != null or float(rig.get("pole_length", 0.0)) > 0.0
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
		sail_parts.append(sp)


## The mainsheet tackle, rebuilt as the boom moves: its vertices shear toward the boom end in proportion to
## their height, so the lower block stays on the traveller and the upper one follows the boom.
func _find_sheet() -> void:
	_sheet = model.find_child("mainsheet", true, false) as MeshInstance3D
	if _sheet == null or _sheet.mesh == null or _sheet.mesh.get_surface_count() != 1:
		_sheet = null
		return
	_sheet_arrays = _sheet.mesh.surface_get_arrays(0)
	_sheet_rest = _sheet_arrays[Mesh.ARRAY_VERTEX]
	if _sheet_rest.is_empty():
		_sheet = null
		return
	var y0 := INF
	var y1 := -INF
	for p in _sheet_rest:
		y0 = minf(y0, p.y)
		y1 = maxf(y1, p.y)
	var n := 0
	_sheet_w.resize(_sheet_rest.size())
	for k in _sheet_rest.size():
		var w := (_sheet_rest[k].y - y0) / maxf(y1 - y0, 1e-3)
		_sheet_w[k] = w
		if w > 0.9:
			_sheet_top += _sheet_rest[k]
			n += 1
	_sheet_top /= maxf(n, 1)
	var mat := _sheet.get_active_material(0)
	_sheet_mesh = ArrayMesh.new()
	_sheet_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _sheet_arrays)
	_sheet_mesh.surface_set_material(0, mat)
	_sheet.mesh = _sheet_mesh


static func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## Rotation by `angle` about the line through `p` along `axis` (right-handed).
static func _about(p: Vector3, axis: Vector3, angle: float) -> Transform3D:
	var b := Basis(axis, angle)
	return Transform3D(b, p - b * p)


func apply(p: SimSource.RenderPose) -> void:
	transform = Frames.boat_transform(p.pos_x, p.pos_y, p.z, p.psi, p.theta, p.phi)
	# helm h > 0 turns the bow to starboard: the blade swings to port, a turn of -h * rudder_max about the stock
	if _rudder:
		_rudder.transform = _rudder_rest * Transform3D(Basis(_rudder_axis, -p.h * _rudder_max), Vector3.ZERO)
	if _wheel:
		_wheel.transform = _wheel_rest * Transform3D(Basis(_wheel_axis, p.h * PI), Vector3.ZERO)


## Places the boom, the mainsheet, the pole and the sails at the render fraction `alpha` between the sail states
## of the last two ticks (`prev` may be null: the newest only). sail_visuals.md §2: beta and pole with angle
## lerp, progress with lerp when both have the same phase, the phase the newer one's.
func apply_sails(prev: SimSource.SailsView, cur: SimSource.SailsView, alpha: float) -> void:
	if model == null or cur == null:
		return
	for sp in sail_parts:
		if sp.index >= cur.sails.size():
			continue
		var s1: SimSource.SailState = cur.sails[sp.index]
		var s0: SimSource.SailState = s1
		if prev != null and sp.index < prev.sails.size():
			s0 = prev.sails[sp.index]
		sp.beta = Frames.wrap_pi(s0.beta + Frames.angle_diff(s1.beta, s0.beta) * alpha)
		sp.gamma = Frames.wrap_pi(s0.pole + Frames.angle_diff(s1.pole, s0.pole) * alpha)
		var prog := lerpf(s0.progress, s1.progress, alpha) if s0.phase == s1.phase else s1.progress
		_place(sp, s1.phase, prog)
		if sp.mode == Mode.BOOM:
			boom_angle = sp.beta
			if _boom:
				_boom.transform = _boom_rest * Transform3D(Basis(_boom_axis, sp.beta), Vector3.ZERO)
			_update_sheet(sp.beta)
		elif sp.mode == Mode.POLE and _pole:
			_pole.visible = s1.phase != SimSource.Phase.DOWN
			if _pole.visible:
				_pole.transform = _pole_rest * Transform3D(Basis(_pole_axis, sp.gamma), Vector3.ZERO)


func _place(sp: SailPart, phase: int, prog: float) -> void:
	sp.node.visible = phase != SimSource.Phase.DOWN or sp.mode == Mode.BOOM
	if not sp.node.visible:
		return
	_hoist_scale(sp, phase, prog)
	var f := Basis(sp.ah, sp.lh, sp.nh)
	var sb := f * Basis.from_scale(Vector3(sp.chord_scale, sp.luff_scale, sp.chord_scale)) * f.transposed()
	var shape := Transform3D(sb, sp.tack - sb * sp.tack)
	var place: Transform3D
	match sp.mode:
		Mode.BOOM:
			place = _about(_boom_pivot, _boom_axis, sp.beta)
		Mode.LUFF:
			place = _about(sp.tack, sp.lh, sp.beta)
		_:
			var swing: Transform3D
			var ge := sp.gamma
			if sp.mode == Mode.POLE:
				swing = _about(_mast_step, _mast_axis, ge)
			else:
				var lim := asin(minf(1.0, sp.tack_line_max * sp.sl / sp.r_h))
				ge = Frames.sgn(sp.gamma) * minf(absf(sp.gamma), lim)
				swing = _about(sp.head, Vector3.UP, ge)
			var t2 := swing * sp.tack
			place = _about(t2, (swing.basis * sp.lh).normalized(), sp.beta - ge) * swing
	sp.node.transform = place * shape * sp.rest


## sail_visuals.md §8.1 phases as a scale of the flat sail about its tack: luff (along Lh) and chord (Ah, Nh).
func _hoist_scale(sp: SailPart, phase: int, prog: float) -> void:
	sp.luff_scale = 1.0
	sp.chord_scale = 1.0
	if sp.mode == Mode.BOOM or phase == SimSource.Phase.UP or phase == SimSource.Phase.PREPARE_DROP:
		return
	if not sp.type.begins_with("spinnaker"):
		# §8.2 on a halyard: p = 0 flaked on deck, the head rises with the hoist, the drop runs it back
		var p := 0.0
		if phase == SimSource.Phase.HOISTING:
			p = prog
		elif phase == SimSource.Phase.DROPPING:
			p = 1.0 - prog
		sp.luff_scale = maxf(p, MIN_SCALE)
		return
	if phase == SimSource.Phase.DROPPING:
		# §8.5: slides down the luff and gathers at the tack, quick to start
		var k := pow(clampf(prog, 0.0, 1.0), 0.3)
		sp.luff_scale = maxf(1.0 - prog, MIN_SCALE)
		sp.chord_scale = lerpf(1.0, BUNDLE, k)
		return
	# §8.4: a thin bundle climbs the luff to 90 %, then fills over the last tenth (c = 0: a bag at the tack)
	var c := prog if phase == SimSource.Phase.HOISTING else 0.0
	var hy := minf(c / 0.9, 1.0)
	var kk := clampf((c - 0.9) / 0.1, 0.0, 1.0)
	sp.luff_scale = maxf(hy, MIN_SCALE)
	sp.chord_scale = lerpf(BUNDLE, 1.0, kk * kk)


func _update_sheet(beta: float) -> void:
	if _sheet == null or absf(beta - _sheet_angle) < 1e-3:
		return
	_sheet_angle = beta
	var d := _about(_boom_pivot, _boom_axis, beta) * _sheet_top - _sheet_top
	var v := PackedVector3Array()
	v.resize(_sheet_rest.size())
	for k in v.size():
		v[k] = _sheet_rest[k] + d * _sheet_w[k]
	var mat := _sheet_mesh.surface_get_material(0)
	_sheet_arrays[Mesh.ARRAY_VERTEX] = v
	_sheet_mesh.clear_surfaces()
	_sheet_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _sheet_arrays)
	_sheet_mesh.surface_set_material(0, mat)
