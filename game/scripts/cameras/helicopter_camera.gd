class_name HelicopterCamera
extends RefCounted
## cameras.md §9 helicopter shot: a slow orbit about the viewed boat, 120 m out and 60 m up, starting astern and
## turning clockwise (seen from above) at 5°/s on the frame time. The orbit keys add to the angle at 120°/s, the
## zoom scales radius and height together (0.25× to 4×).

const RADIUS := 120.0
const HEIGHT := 60.0
const RATE := deg_to_rad(5.0)
const FOV := 35.0
const SCALE_MIN := 0.25
const SCALE_MAX := 4.0

## compass angle from the boat to the eye
var alpha := PI
var scale := 1.0
var clearance := CamTypes.Clearance.new()
var land := CamTypes.LandAvoid.new()
var _fresh := true


func params() -> Dictionary:
	return {"scale": scale}


func set_params(p: Dictionary) -> void:
	scale = p.get("scale", scale)


func recentre(t: CamTypes.Target) -> void:
	scale = 1.0
	snap(t)


## starts astern of the boat; the frame it is selected does not turn yet
func snap(t: CamTypes.Target) -> void:
	alpha = Frames.wrap_2pi(t.pose.psi + PI)
	clearance.reset()
	land.reset()
	_fresh = true


func handle_input(c: CameraInput, o: CamTypes.Options, dt: float) -> void:
	var sx := -1.0 if o.invert_orbit_x else 1.0
	var turn := c.orbit.x * ChaseCamera.ORBIT_AZ_RATE * o.speed * dt * sx
	if c.dragging:
		turn += c.mouse.x * ChaseCamera.MOUSE_RATE * o.speed * sx
	alpha = Frames.wrap_2pi(alpha + turn)
	var zoom := pow(ChaseCamera.NOTCH, c.zoom_notches) * pow(2.0, c.zoom_held * dt)
	scale = clampf(scale / zoom, SCALE_MIN, SCALE_MAX)


func update(t: CamTypes.Target, _o: CamTypes.Options, dt: float) -> CamTypes.View:
	if _fresh:
		_fresh = false
	else:
		alpha = Frames.wrap_2pi(alpha + RATE * dt)
	var target := t.point(0.0)
	var r := RADIUS * scale
	var eye := target + Vector3(r * sin(alpha), HEIGHT * scale, -r * cos(alpha))
	eye = land.apply(eye, target, t, dt)
	eye = clearance.apply(eye, t, dt)
	var v := CamTypes.View.new()
	v.xform = CamTypes.look(eye, target)
	v.fov = FOV
	v.near = CamTypes.near_for(eye.y)
	return v
