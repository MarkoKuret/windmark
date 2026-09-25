class_name FreeCamera
extends RefCounted
## cameras.md §5: a fly camera for looking around the course.

const MOUSE_RATE := deg_to_rad(0.15)
const STICK_YAW_RATE := deg_to_rad(90.0)
const STICK_PITCH_RATE := deg_to_rad(60.0)
const PITCH_MAX := deg_to_rad(89.0)
const TAU_V := 0.15
const BOOST := 4.0
const MIN_CLEARANCE := 1.0
const RANGE := 10000.0
const START_BACK := 60.0
const START_UP := 40.0

var pos := Vector3.ZERO
var yaw := 0.0  # compass of the view
var pitch := 0.0  # + up
var fov := 60.0
var vel := Vector3.ZERO
var _started := false


func params() -> Dictionary:
	return {"pos": pos, "yaw": yaw, "pitch": pitch, "fov": fov}


func set_params(p: Dictionary) -> void:
	pos = p.get("pos", pos)
	yaw = p.get("yaw", yaw)
	pitch = p.get("pitch", pitch)
	fov = p.get("fov", fov)
	_started = true


## 60 m astern of and 40 m above the viewed boat, looking at it
func recentre(t: CamTypes.Target) -> void:
	var target := t.point(t.pose.z)
	pos = target - Frames.compass_dir(t.pose.psi) * START_BACK + Vector3(0, START_UP, 0)
	var d := target - pos
	yaw = Frames.compass(d.x, -d.z)
	pitch = atan2(d.y, Vector2(d.x, d.z).length())
	vel = Vector3.ZERO
	_started = true


func snap(t: CamTypes.Target) -> void:
	recentre(t)


func basis() -> Basis:
	return Basis(Vector3.UP, -yaw) * Basis(Vector3.RIGHT, pitch)


func handle_input(c: CameraInput, o: CamTypes.Options, dt: float) -> void:
	var sx := -1.0 if o.invert_look_x else 1.0
	var sy := -1.0 if o.invert_look_y else 1.0
	yaw += (c.look.x + c.keys.x) * STICK_YAW_RATE * o.speed * dt * sx
	pitch += (c.look.y + c.keys.y) * STICK_PITCH_RATE * o.speed * dt * sy
	if c.dragging:
		yaw += c.mouse.x * MOUSE_RATE * o.speed * sx
		pitch -= c.mouse.y * MOUSE_RATE * o.speed * sy
	yaw = Frames.wrap_2pi(yaw)
	pitch = clampf(pitch, -PITCH_MAX, PITCH_MAX)
	var zoom := pow(ChaseCamera.NOTCH, c.zoom_notches)
	fov = clampf(fov / zoom, 25.0, 90.0)
	_move = c.move
	_boost = c.boost


var _move := Vector3.ZERO
var _boost := false


func update(t: CamTypes.Target, _o: CamTypes.Options, dt: float) -> CamTypes.View:
	if not _started:
		snap(t)
	var b := basis()
	var h := maxf(pos.y - t.sea_at(pos), 0.0)
	var speed := 10.0 * (1.0 + h / 20.0) * (BOOST if _boost else 1.0)
	var want := (-b.z * _move.z + b.x * _move.x + Vector3.UP * _move.y) * speed
	vel += (want - vel) * Frames.smooth_k(dt, TAU_V)
	pos += vel * dt
	var floor_y := maxf(t.sea_at(pos), t.ground_at(pos)) + MIN_CLEARANCE
	if pos.y < floor_y:
		pos.y = floor_y
		vel.y = maxf(vel.y, 0.0)
	var flat := Vector2(pos.x, pos.z)
	if flat.length() > RANGE:
		flat = flat.normalized() * RANGE
		pos = Vector3(flat.x, pos.y, flat.y)
	var v := CamTypes.View.new()
	v.xform = Transform3D(b, pos)
	v.fov = fov
	v.near = CamTypes.near_for(pos.y)
	return v
