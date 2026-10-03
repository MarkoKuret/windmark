class_name StartLineCamera
extends RefCounted
## cameras.md §9 start line shot: fixed 20 m outside the committee boat end on the line's extension, 6 m above the
## still water, looking down the line at the other end. Takes no input; keeps its last eye when the line goes.

const OUTSIDE := 20.0
const HEIGHT := 6.0
const FOV := 30.0

## set by the rig every frame (null: no race)
var course: ClipCourse
var clearance := CamTypes.Clearance.new()
var _eye := Vector3(0, HEIGHT, 0)
var _aim := Vector3(0, 0, -1)


func params() -> Dictionary:
	return {}


func set_params(_p: Dictionary) -> void:
	pass


func recentre(_t: CamTypes.Target) -> void:
	pass


func snap(_t: CamTypes.Target) -> void:
	clearance.reset()


func handle_input(_c: CameraInput, _o: CamTypes.Options, _dt: float) -> void:
	pass


## the eye and aim of the shot for the line committee end `c`, other end `p` (scene, on the still water)
static func place(c: Vector3, p: Vector3) -> Array[Vector3]:
	var u := Vector3(c.x - p.x, 0.0, c.z - p.z).normalized()
	return [c + u * OUTSIDE + Vector3(0, HEIGHT, 0), Vector3(p.x, 0.0, p.z)]


func update(t: CamTypes.Target, _o: CamTypes.Options, dt: float) -> CamTypes.View:
	if course != null and course.has_line:
		var ea := place(course.committee, course.pin)
		_eye = ea[0]
		_aim = ea[1]
	var eye := clearance.apply(_eye, t, dt)
	var v := CamTypes.View.new()
	v.xform = CamTypes.look(eye, _aim)
	v.fov = FOV
	v.near = CamTypes.near_for(eye.y)
	return v
