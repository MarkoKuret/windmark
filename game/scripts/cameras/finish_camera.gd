class_name FinishCamera
extends RefCounted
## cameras.md §9.1 finish view: the slow cinematic drift of the menu's backdrop (menus.md §4) on the viewed boat
## once the player's race is over. It circles her at 45 to 70 m and 5 to 11 m above the water at 1.5° a second, the
## distance and height breathing over 40 s, aimed 2 m above her reference point; with reduced motion a third of that
## speed. `offset` frames her left of centre (rad, eased with tau 1.4 s) while the results panel is on the right.
## The rig eases into it from the camera in use (CameraRig.ease_to). Takes no input.

const RATE := deg_to_rad(1.5)
const DIST := Vector2(45.0, 70.0)
const HEIGHT := Vector2(5.0, 11.0)
const BREATH_S := 40.0
const AIM_UP := 2.0
const FOV := 35.0
const OFFSET_TAU := 1.4
## the framing offset while the results panel is on the right, rad (cameras.md §9.1)
const PANEL_OFFSET := deg_to_rad(-12.0)

## compass angle from the boat to the eye (the helicopter's convention: eye = boat + (r sin a, h, -r cos a))
var alpha := PI
## the wanted framing offset (rad, + turns the camera left so the boat sits right of centre) and the eased one
var offset := 0.0
var offset_now := 0.0
var clearance := CamTypes.Clearance.new()
var land := CamTypes.LandAvoid.new()
var _t := 0.0


func params() -> Dictionary:
	return {}


func set_params(_p: Dictionary) -> void:
	pass


func recentre(_t: CamTypes.Target) -> void:
	pass


func snap(_t: CamTypes.Target) -> void:
	clearance.reset()
	land.reset()


func handle_input(_c: CameraInput, _o: CamTypes.Options, _dt: float) -> void:
	pass


## Starts the drift with the eye on the side of `eye` (scene), so the ease into it is short.
func start_from(t: CamTypes.Target, eye: Vector3) -> void:
	var d := eye - t.point(0.0)
	alpha = Frames.wrap_2pi(atan2(d.x, -d.z)) if Vector2(d.x, d.z).length() > 0.5 else Frames.wrap_2pi(t.pose.psi + PI)
	_t = 0.0
	offset_now = offset
	snap(t)


## the distance and height of the drift at its time `time` (s): from the near, low end breathing out and up
static func reach(time: float) -> Vector2:
	var breath := 0.5 - 0.5 * cos(TAU * time / BREATH_S)
	return Vector2(lerpf(DIST.x, DIST.y, breath), lerpf(HEIGHT.y, HEIGHT.x, breath))


func update(t: CamTypes.Target, o: CamTypes.Options, dt: float) -> CamTypes.View:
	var rate := 1.0 / 3.0 if o.reduced_motion else 1.0
	_t += dt * rate
	alpha = Frames.wrap_2pi(alpha + RATE * rate * dt)
	offset_now += (offset - offset_now) * Frames.smooth_k(dt, OFFSET_TAU)
	var aim := t.point(0.0) + Vector3(0, AIM_UP, 0)
	var rh := reach(_t)
	var eye := t.point(0.0) + Vector3(rh.x * sin(alpha), rh.y, -rh.x * cos(alpha))
	eye = land.apply(eye, aim, t, dt)
	eye = clearance.apply(eye, t, dt)
	var v := CamTypes.View.new()
	v.xform = CamTypes.look(eye, aim)
	v.xform.basis = v.xform.basis * Basis(Vector3.UP, offset_now)
	v.fov = FOV
	v.near = CamTypes.near_for(eye.y)
	return v
