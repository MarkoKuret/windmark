class_name MarkCamera
extends RefCounted
## cameras.md §9 mark shot: fixed 40 m from the viewed boat's next mark on the approach side, 45° off the
## approach line away from the side the boats pass, 6 m above the still water; it tracks the leading boat inside
## the zone, or the viewed boat when the zone is empty (aim 2 m above the boat, smoothed with tau = 0.5 s). Without
## a next mark it keeps its last eye and aims at the viewed boat. Takes no input.

const DIST := 40.0
const HEIGHT := 6.0
const OFF_LINE := deg_to_rad(45.0)
const AIM_UP := 2.0
const TAU_AIM := 0.5
const FOV := 35.0

var course: ClipCourse
var clearance := CamTypes.Clearance.new()
var aim := Vector3.ZERO
var _eye := Vector3(0, HEIGHT, 0)
var _snap := true


func params() -> Dictionary:
	return {}


func set_params(_p: Dictionary) -> void:
	pass


func recentre(_t: CamTypes.Target) -> void:
	pass


func snap(_t: CamTypes.Target) -> void:
	clearance.reset()
	_snap = true


func handle_input(_c: CameraInput, _o: CamTypes.Options, _dt: float) -> void:
	pass


## the eye for mark `m`, approach point `q` (scene, still water) and side `s` (+1 left to port)
static func eye_for(m: Vector3, q: Vector3, s: int) -> Vector3:
	var to_q := Vector2(q.x - m.x, -(q.z - m.z))  # east, north
	var beta := Frames.compass(to_q.x, to_q.y) + OFF_LINE * s
	return Vector3(m.x + DIST * sin(beta), HEIGHT, m.z - DIST * cos(beta))


## the boat the shot tracks: the first in race order within the zone, else the viewed boat (scene, still water)
static func tracked(c: ClipCourse, viewed: Vector3) -> Vector3:
	if c != null and c.has_mark:
		for b in c.boats:
			if Vector2(b.x - c.mark.x, b.z - c.mark.z).length() <= c.zone_r:
				return b
	return viewed


func update(t: CamTypes.Target, _o: CamTypes.Options, dt: float) -> CamTypes.View:
	if course != null and course.has_mark:
		_eye = eye_for(course.mark, course.approach, course.side)
	var goal := tracked(course, t.point(0.0)) + Vector3(0, AIM_UP, 0)
	if _snap:
		aim = goal
		_snap = false
	else:
		aim += (goal - aim) * Frames.smooth_k(dt, TAU_AIM)
	var eye := clearance.apply(_eye, t, dt)
	var v := CamTypes.View.new()
	v.xform = CamTypes.look(eye, aim)
	v.fov = FOV
	v.near = CamTypes.near_for(eye.y)
	v.focus = eye.distance_to(aim)
	return v
