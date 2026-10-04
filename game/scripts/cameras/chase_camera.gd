class_name ChaseCamera
extends RefCounted
## cameras.md §2: an orbit around the boat that follows the heading, not heel or pitch, and breathes with the boat
## (§2.1): an eased heading follow, a slight bank in turns, the target trailing a little on speed changes and leaning
## with the heel.

const EL_DEFAULT := deg_to_rad(13.5)
const FOV_DEFAULT := 40.0
const ORBIT_AZ_RATE := deg_to_rad(120.0)
const ORBIT_EL_RATE := deg_to_rad(60.0)
const MOUSE_RATE := deg_to_rad(0.3)
const NOTCH := 1.12
const AUTO_RECENTRE_AFTER := 5.0

## cameras.md §2.1 breathing. The heading follow is critically damped with this natural frequency times 1/tau_yaw:
## 5/3 puts it within 4 % of a heading step after 3·tau_yaw (test 2) and starts the swing gently.
const YAW_W_TAU := 5.0 / 3.0
## bank into a turn: this many seconds times the camera's own yaw rate (rad/s), at most BANK_MAX
const BANK_K := 0.06
const BANK_MAX := deg_to_rad(1.5)
## the target trails a speed change: (smoothed velocity - velocity) times SURGE_K, at most SURGE_MAX, the offset
## itself smoothed with SURGE_TAU_OFFSET
const SURGE_K := 0.8
const SURGE_MAX := 0.8
const SURGE_TAU_V := 0.6
const SURGE_TAU_OFFSET := 0.15
## the target leans with the heel toward the masthead side: LEAN_K · loa · sin(smoothed heel)
const LEAN_K := 0.2
const LEAN_TAU := 0.6
## a pose jump faster than this (reset, another boat) snaps instead of trailing
const SNAP_SPEED := 40.0

var R := 24.5
var el := EL_DEFAULT
var az := 0.0
var fov := FOV_DEFAULT
var tau_yaw := 0.35
var tau_heave := 0.3
var lift := 1.0
## the fov range of the zoom, and whether the zoom always changes fov (the long lens, cameras.md §9)
var fov_min := 25.0
var fov_max := 75.0
var zoom_is_fov := false

## smoothed heading and heave (state, not parameters)
var psi_c := 0.0
var zt := 0.0
## §2.1 state: heading rate of the camera, the bank, the target's velocity and its smoothing, the surge and lean
## offsets (scene metres) and the smoothed heel
var psi_rate := 0.0
var bank := 0.0
var surge := Vector3.ZERO
var lean := Vector3.ZERO
var phi_s := 0.0
var _vel_s := Vector3.ZERO
var _prev_pos := Vector3.ZERO
var _started := false
var _idle := 0.0
var clearance := CamTypes.Clearance.new()
var land := CamTypes.LandAvoid.new()


func params() -> Dictionary:
	return {"R": R, "el": el, "az": az, "fov": fov, "tau_yaw": tau_yaw, "tau_heave": tau_heave, "lift": lift}


func set_params(p: Dictionary) -> void:
	R = p.get("R", R)
	el = p.get("el", el)
	az = p.get("az", az)
	fov = p.get("fov", fov)
	tau_yaw = p.get("tau_yaw", tau_yaw)
	tau_heave = p.get("tau_heave", tau_heave)
	lift = p.get("lift", lift)


func recentre(t: CamTypes.Target) -> void:
	R = t.r0()
	el = EL_DEFAULT
	az = 0.0
	fov = FOV_DEFAULT


## jump the smoothing to the boat (first frame, spectating another boat)
func snap(t: CamTypes.Target) -> void:
	psi_c = t.pose.psi
	zt = t.pose.z
	psi_rate = 0.0
	bank = 0.0
	surge = Vector3.ZERO
	lean = Vector3.ZERO
	phi_s = t.pose.phi
	_vel_s = Vector3.ZERO
	_prev_pos = t.point(0.0)
	clearance.reset()
	land.reset()
	_started = true


func handle_input(c: CameraInput, o: CamTypes.Options, dt: float) -> void:
	var sx := -1.0 if o.invert_orbit_x else 1.0
	var sy := -1.0 if o.invert_orbit_y else 1.0
	az += c.orbit.x * ORBIT_AZ_RATE * o.speed * dt * sx
	el += c.orbit.y * ORBIT_EL_RATE * o.speed * dt * sy
	if c.dragging:
		az += c.mouse.x * MOUSE_RATE * o.speed * sx
		el += c.mouse.y * MOUSE_RATE * o.speed * sy
	var zoom := pow(NOTCH, c.zoom_notches) * pow(2.0, c.zoom_held * dt)
	if c.fov_modifier or zoom_is_fov:
		fov = clampf(fov / zoom, fov_min, fov_max)
	else:
		R = clampf(R / zoom, 8.0, 1000.0)
	el = clampf(el, deg_to_rad(2.0), deg_to_rad(85.0))
	az = Frames.wrap_pi(az)
	var any := c.orbit != Vector2.ZERO or (c.dragging and c.mouse != Vector2.ZERO) or c.zoom_notches != 0 \
		or c.zoom_held != 0.0
	_idle = 0.0 if any else _idle + dt
	if o.auto_recentre and _idle > AUTO_RECENTRE_AFTER:
		az = Frames.wrap_pi(az * (1.0 - Frames.smooth_k(dt, 1.0)))


func update(t: CamTypes.Target, o: CamTypes.Options, dt: float) -> CamTypes.View:
	if not _started:
		snap(t)
	var ty := maxf(tau_yaw, 0.5) if o.reduced_motion else tau_yaw
	_follow_heading(t.pose.psi, dt, ty)
	zt += (t.pose.z - zt) * Frames.smooth_k(dt, 0.0 if o.follow_waves else tau_heave)
	_breathe(t, o, dt)
	var target := t.point(zt) + surge + lean
	var v := CamTypes.View.new()
	v.xform = frame(target, t, dt)
	if bank != 0.0:
		v.xform.basis = v.xform.basis * Basis(Vector3(0, 0, 1), -bank)
	v.fov = fov
	v.near = CamTypes.near_for(v.xform.origin.y)
	v.focus = v.xform.origin.distance_to(target + Vector3(0, lift, 0))
	return v


## §2.1: the heading followed by a critically damped spring (natural frequency YAW_W_TAU / tau), so a tack's swing
## eases in and out; tau = 0 follows at once.
func _follow_heading(psi: float, dt: float, tau: float) -> void:
	if tau <= 0.0 or dt <= 0.0:
		psi_c = Frames.wrap_2pi(psi)
		psi_rate = 0.0
		return
	var w := YAW_W_TAU / tau
	var e := Frames.angle_diff(psi_c, psi)  # camera minus boat
	# exact step of x'' = -2w x' - w² x over dt
	var ex := exp(-w * dt)
	var c := psi_rate + w * e
	var e1 := (e + c * dt) * ex
	psi_rate = (psi_rate - w * c * dt) * ex
	psi_c = Frames.wrap_2pi(psi + e1)


## §2.1: bank with the camera's yaw rate, the target trailing speed changes and leaning with the heel; all off with
## reduced motion.
func _breathe(t: CamTypes.Target, o: CamTypes.Options, dt: float) -> void:
	var p := t.point(0.0)
	var v := (p - _prev_pos) / dt if dt > 0.0 else Vector3.ZERO
	v.y = 0.0
	_prev_pos = p
	if v.length() > SNAP_SPEED:
		_vel_s = Vector3.ZERO
		surge = Vector3.ZERO
		v = Vector3.ZERO
	if o.reduced_motion:
		bank = 0.0
		surge = Vector3.ZERO
		lean = Vector3.ZERO
		_vel_s = v
		phi_s = t.pose.phi
		return
	bank = clampf(BANK_K * psi_rate, -BANK_MAX, BANK_MAX)
	if _vel_s == Vector3.ZERO and surge == Vector3.ZERO:
		_vel_s = v  # first moving frame: no trail from rest
	_vel_s += (v - _vel_s) * Frames.smooth_k(dt, SURGE_TAU_V)
	var want := (_vel_s - v) * SURGE_K
	if want.length() > SURGE_MAX:
		want = want.normalized() * SURGE_MAX
	surge += (want - surge) * Frames.smooth_k(dt, SURGE_TAU_OFFSET)
	phi_s += (t.pose.phi - phi_s) * Frames.smooth_k(dt, LEAN_TAU)
	var up := Frames.boat_basis(t.pose.psi, 0.0, phi_s).y
	lean = Vector3(up.x, 0.0, up.z) * (LEAN_K * t.loa)


## eye and view for a target point, with the water clearance (the aim point is kept)
func frame(target: Vector3, t: CamTypes.Target, dt: float) -> Transform3D:
	var azw := psi_c + PI + az
	var eye := target + R * Vector3(sin(azw) * cos(el), sin(el), -cos(azw) * cos(el)) + Vector3(0, lift, 0)
	var aim := target + Vector3(0, lift, 0)
	eye = land.apply(eye, aim, t, dt)
	eye = clearance.apply(eye, t, dt)
	return CamTypes.look(eye, aim)


## the eye without clearance or smoothing, for tests
func eye_for(target: Vector3, heading: float) -> Vector3:
	var azw := heading + PI + az
	return target + R * Vector3(sin(azw) * cos(el), sin(el), -cos(azw) * cos(el)) + Vector3(0, lift, 0)
