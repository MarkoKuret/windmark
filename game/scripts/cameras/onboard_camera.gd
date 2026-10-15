class_name OnboardCamera
extends RefCounted
## cameras.md §3: the helmsman's eye, fixed in the heeled, pitching boat, sitting to windward.

const FOV_DEFAULT := 75.0
const FOV_OLD_DEFAULT := 65.0  # the default before 2026-10-15: a profile saved with it loads the new one
const LOOK_YAW_MAX := deg_to_rad(150.0)
const LOOK_PITCH_MIN := deg_to_rad(-60.0)
const LOOK_PITCH_MAX := deg_to_rad(75.0)
const MOUSE_RATE := deg_to_rad(0.15)
const KEY_YAW_RATE := deg_to_rad(90.0)
const KEY_PITCH_RATE := deg_to_rad(60.0)
const TACK_WAIT := 0.6  # s the new tack must hold before the helmsman moves
const CROSS_SPEED := 1.5  # m/s
const DIP := 0.3  # m at the centreline
const LOOK_RETURN_TAU := 0.6

var fov := FOV_DEFAULT
var heel_follow := 0.0
var look_yaw := 0.0
var look_pitch := 0.0

## windward side of the eye: +1 = port (y > 0), -1 = starboard
var side_from := -1.0
var side_to := -1.0
var cross := 1.0  # progress of the crossing from side_from to side_to, 1 = arrived
var _pending := 0.0  # time the tack has differed from side_to
var _started := false


func params() -> Dictionary:
	return {"fov": fov, "heel_follow": heel_follow}


func set_params(p: Dictionary) -> void:
	fov = p.get("fov", fov)
	if is_equal_approx(fov, FOV_OLD_DEFAULT):
		fov = FOV_DEFAULT
	heel_follow = p.get("heel_follow", heel_follow)


func recentre(_t: CamTypes.Target) -> void:
	fov = FOV_DEFAULT
	look_yaw = 0.0
	look_pitch = 0.0


func snap(t: CamTypes.Target) -> void:
	side_to = _windward(t.pose.twa)
	side_from = side_to
	cross = 1.0
	_pending = 0.0
	_started = true


## eye side: -sgn(twa) (starboard tack, wind from starboard: eye on the starboard side, y < 0)
static func _windward(twa: float) -> float:
	return -Frames.sgn(twa)


func handle_input(c: CameraInput, o: CamTypes.Options, dt: float) -> void:
	var sx := -1.0 if o.invert_look_x else 1.0
	var sy := -1.0 if o.invert_look_y else 1.0
	var active := false
	if c.look != Vector2.ZERO:  # right stick: absolute look
		look_yaw = c.look.x * sx * LOOK_YAW_MAX
		look_pitch = c.look.y * sy * (LOOK_PITCH_MAX if c.look.y * sy > 0.0 else -LOOK_PITCH_MIN)
		active = true
	if c.keys != Vector2.ZERO:
		look_yaw += c.keys.x * sx * KEY_YAW_RATE * o.speed * dt
		look_pitch += c.keys.y * sy * KEY_PITCH_RATE * o.speed * dt
		active = true
	if c.dragging:
		look_yaw += c.mouse.x * MOUSE_RATE * o.speed * sx
		look_pitch -= c.mouse.y * MOUSE_RATE * o.speed * sy
		active = true
	look_yaw = clampf(look_yaw, -LOOK_YAW_MAX, LOOK_YAW_MAX)
	look_pitch = clampf(look_pitch, LOOK_PITCH_MIN, LOOK_PITCH_MAX)
	if not active and not o.onboard_look_stays:
		var k := Frames.smooth_k(dt, LOOK_RETURN_TAU)
		look_yaw -= look_yaw * k
		look_pitch -= look_pitch * k
	var zoom := pow(ChaseCamera.NOTCH, c.zoom_notches) * pow(2.0, c.zoom_held * dt)
	fov = clampf(fov / zoom, 50.0, 90.0)


## Advances the side crossing; returns the eye's y in the body frame and the dip.
func advance_side(twa: float, yh_abs: float, dt: float) -> float:
	var want := _windward(twa)
	if want != side_to:
		_pending += dt
		if _pending >= TACK_WAIT:
			_pending = 0.0
			if cross < 1.0 and want == side_from:
				# a tack back during the crossing reverses it from where it is
				side_from = side_to
				side_to = want
				cross = 1.0 - cross
			else:
				side_from = side_to
				side_to = want
				cross = 0.0
	else:
		_pending = 0.0
	if cross < 1.0:
		var dur := 2.0 * yh_abs / CROSS_SPEED
		cross = minf(1.0, cross + (dt / dur if dur > 1e-6 else 1.0))
	return lerpf(side_from, side_to, Frames.smoothstep01(cross)) * yh_abs


func update(t: CamTypes.Target, o: CamTypes.Options, dt: float) -> CamTypes.View:
	if not _started:
		snap(t)
	var g := t.geometry
	var y := advance_side(t.pose.twa, g.yh_abs, dt)
	var q := y / g.yh_abs if g.yh_abs > 1e-6 else 0.0
	var eye_body := Vector3(g.xh, y, g.zh - DIP * (1.0 - q * q))
	var p := t.pose
	var boat := Frames.boat_transform(p.pos_x, p.pos_y, p.z, p.psi, p.theta, p.phi)
	var eye := boat * Frames.body_to_model(eye_body)
	var yaw := p.psi + look_yaw
	var pitch := 0.5 * p.theta + look_pitch
	var follow := 0.0 if o.reduced_motion else heel_follow
	var roll := -follow * p.phi  # starboard down (phi > 0) rolls the right of the frame down
	var b := Basis(Vector3.UP, -yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
	var v := CamTypes.View.new()
	v.xform = Transform3D(b, eye)
	v.fov = fov
	v.near = 0.1
	return v
