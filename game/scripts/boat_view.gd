class_name BoatView
extends Node3D
## The generated boat in the scene (conventions.md §11): the boatgen GLB under a node placed at the render pose,
## the rudder (and wheel) turned by the helm. Sails are drawn as generated for now (sail visuals: WM-016.09).

var info: SimSource.ClassInfo
## the imported boat root (the GLB's child named after the class), null when the GLB is missing
var model: Node3D
var _rudder: Node3D
var _rudder_rest := Transform3D.IDENTITY
var _rudder_axis := Vector3.UP
var _wheel: Node3D
var _wheel_rest := Transform3D.IDENTITY
var _wheel_axis := Vector3.BACK
var _rudder_max := 0.6


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


static func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func apply(p: SimSource.RenderPose) -> void:
	transform = Frames.boat_transform(p.pos_x, p.pos_y, p.z, p.psi, p.theta, p.phi)
	# helm h > 0 turns the bow to starboard: the blade swings to port, a turn of -h * rudder_max about the stock
	if _rudder:
		_rudder.transform = _rudder_rest * Transform3D(Basis(_rudder_axis, -p.h * _rudder_max), Vector3.ZERO)
	if _wheel:
		_wheel.transform = _wheel_rest * Transform3D(Basis(_wheel_axis, p.h * PI), Vector3.ZERO)
