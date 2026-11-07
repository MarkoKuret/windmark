class_name AerialCamera
extends RefCounted
## cameras.md §4: a top view for tactics.

enum Up { NORTH, BOAT, WIND, FIXED }
enum Framing { BOAT, BOAT_AND_MARK }

const H_DEFAULT := 250.0
const TILT_DEFAULT := PI * 0.5
const FOV_DEFAULT := 45.0
const TAU_BOAT := 0.5
const TAU_WIND := 10.0

var H := H_DEFAULT
var tilt := TILT_DEFAULT
var up := Up.NORTH
## the player's default `up` (recentre goes back to it)
var up_default := Up.NORTH
## compass angle of `up` when FIXED (turned by hand)
var up_angle := 0.0
var fov := FOV_DEFAULT
var framing := Framing.BOAT
## next mark position (scene), for BOAT_AND_MARK; null until the race layer provides marks
var next_mark: Variant = null

var _upd := 0.0
var _started := false
var clearance := CamTypes.Clearance.new()
var land := CamTypes.LandAvoid.new()


func params() -> Dictionary:
	return {"H": H, "tilt": tilt, "up": up, "up_angle": up_angle, "fov": fov, "framing": framing}


func set_params(p: Dictionary) -> void:
	H = p.get("H", H)
	tilt = p.get("tilt", tilt)
	up = p.get("up", up)
	up_angle = p.get("up_angle", up_angle)
	fov = p.get("fov", fov)
	framing = p.get("framing", framing)


func recentre(_t: CamTypes.Target) -> void:
	H = H_DEFAULT
	tilt = TILT_DEFAULT
	up = up_default
	up_angle = 0.0


func snap(t: CamTypes.Target) -> void:
	_upd = _up_goal(t)
	clearance.reset()
	land.reset()
	_started = true


func _up_goal(t: CamTypes.Target) -> float:
	match up:
		Up.BOAT:
			return t.pose.psi
		Up.WIND:
			return t.pose.twd_from
		Up.FIXED:
			return up_angle
	return 0.0


func handle_input(c: CameraInput, o: CamTypes.Options, dt: float) -> void:
	var sx := -1.0 if o.invert_orbit_x else 1.0
	var sy := -1.0 if o.invert_orbit_y else 1.0
	var turn := c.orbit.x * ChaseCamera.ORBIT_AZ_RATE * o.speed * dt * sx
	if c.dragging:
		turn += c.mouse.x * ChaseCamera.MOUSE_RATE * o.speed * sx
	if turn != 0.0:
		if up != Up.FIXED:
			up_angle = _upd
			up = Up.FIXED
		up_angle = Frames.wrap_2pi(up_angle + turn)
	tilt = clampf(tilt + c.orbit.y * ChaseCamera.ORBIT_EL_RATE * o.speed * dt * sy, deg_to_rad(50.0), PI * 0.5)
	var zoom := pow(ChaseCamera.NOTCH, c.zoom_notches) * pow(2.0, c.zoom_held * dt)
	H = clampf(H / zoom, 40.0, 3000.0)


func update(t: CamTypes.Target, _o: CamTypes.Options, dt: float) -> CamTypes.View:
	if not _started:
		snap(t)
	var goal := _up_goal(t)
	match up:
		Up.BOAT:
			_upd = Frames.smooth_angle(_upd, goal, dt, TAU_BOAT)
		Up.WIND:
			_upd = Frames.smooth_angle(_upd, goal, dt, TAU_WIND)
		_:
			_upd = goal
	var target := t.point(t.pose.z)
	var h := H
	if framing == Framing.BOAT_AND_MARK and next_mark is Vector3:
		var mark: Vector3 = next_mark
		var half := (mark - target) * 0.5
		target += half
		# both inside 80 % of the frame height: half-extent <= 0.8 * H * tan(fov / 2)
		h = maxf(H, half.length() / (0.8 * tan(deg_to_rad(fov) * 0.5)))
	var eye := target + h * Vector3(sin(_upd + PI) * cos(tilt), sin(tilt), -cos(_upd + PI) * cos(tilt))
	eye = land.apply(eye, target, t, dt)
	eye = clearance.apply(eye, t, dt)
	var v := CamTypes.View.new()
	v.xform = CamTypes.look(eye, target, Frames.compass_dir(_upd))
	v.fov = fov
	v.near = CamTypes.near_for(eye.y)
	return v
