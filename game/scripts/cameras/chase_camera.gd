class_name ChaseCamera
extends RefCounted
## cameras.md §2: an orbit around the boat that follows the heading tightly (one first-order lag of tau_yaw), not
## heel or pitch, with a slight bank into turns (§2.1) that adds no lag.

const EL_DEFAULT := deg_to_rad(13.5)
const FOV_DEFAULT := 40.0
const ORBIT_AZ_RATE := deg_to_rad(120.0)
const ORBIT_EL_RATE := deg_to_rad(60.0)
const MOUSE_RATE := deg_to_rad(0.3)
const NOTCH := 1.12
const AUTO_RECENTRE_AFTER := 5.0

## cameras.md §2.1 bank into a turn: this many seconds times the camera's own yaw rate (rad/s), at most BANK_MAX.
## An offset of the view's roll in the same frame, never a delay.
const BANK_K := 0.06
const BANK_MAX := deg_to_rad(1.5)

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

## §2.1 the bank into turns on; off (`--chase-bank=off`, the look panel) keeps the horizon level in turns too
var banking := true
## smoothed heading and heave (state, not parameters)
var psi_c := 0.0
var zt := 0.0
## §2.1 state: the camera's heading rate (rad/s, from the follow) and the bank (rad)
var psi_rate := 0.0
var bank := 0.0
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
	zt += (t.pose.z - zt) * Frames.smooth_k(dt, 0.0 if o.follow_waves else tau_heave)
	var prev := psi_c
	psi_c = Frames.smooth_angle(psi_c, t.pose.psi, dt, ty)
	psi_rate = Frames.angle_diff(psi_c, prev) / dt if dt > 0.0 else 0.0
	bank = clampf(BANK_K * psi_rate, -BANK_MAX, BANK_MAX) if banking and not o.reduced_motion else 0.0
	var target := t.point(zt)
	var v := CamTypes.View.new()
	v.xform = frame(target, t, dt)
	if bank != 0.0:
		v.xform.basis = v.xform.basis * Basis(Vector3(0, 0, 1), -bank)
	v.fov = fov
	v.near = CamTypes.near_for(v.xform.origin.y)
	v.focus = v.xform.origin.distance_to(target + Vector3(0, lift, 0))
	return v


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
