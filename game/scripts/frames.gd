class_name Frames
## Frames, angles and smoothing shared by the front end (conventions.md §2, §3, §6.5, §11; cameras.md §1).
##
## World (ENU): x east, y north, z up. Scene (Godot): X east, Y up, Z south, so a world point (x, y, z) is drawn
## at (x, z, -y). Compass angles are clockwise from north. The generated model's axes are (X, Y, Z) =
## (body y, body z, body x): port, up, bow.


## wrap to [-PI, PI)
static func wrap_pi(a: float) -> float:
	return fposmod(a + PI, TAU) - PI


## wrap to [0, 2 PI)
static func wrap_2pi(a: float) -> float:
	return fposmod(a, TAU)


## signed shortest difference a - b, in [-PI, PI)
static func angle_diff(a: float, b: float) -> float:
	return wrap_pi(a - b)


## conventions.md §2: compass angle of an (east, north) vector
static func compass(vx: float, vy: float) -> float:
	return wrap_2pi(atan2(vx, vy))


## sgn with sgn(0) = +1 (conventions.md §3)
static func sgn(x: float) -> float:
	return 1.0 if x >= 0.0 else -1.0


## cameras.md §1 smoothing weight: y += (x - y) * k
static func smooth_k(dt: float, tau: float) -> float:
	if tau <= 0.0:
		return 1.0
	return 1.0 - exp(-dt / tau)


## exponential filter of an angle through angle_diff
static func smooth_angle(y: float, x: float, dt: float, tau: float) -> float:
	return wrap_2pi(y + angle_diff(x, y) * smooth_k(dt, tau))


## world ENU point to scene
static func enu_to_scene(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)


## scene point to world ENU
static func scene_to_enu(p: Vector3) -> Vector3:
	return Vector3(p.x, -p.z, p.y)


## compass direction as a horizontal scene vector (sin psi, 0, -cos psi)
static func compass_dir(psi: float) -> Vector3:
	return Vector3(sin(psi), 0.0, -cos(psi))


## conventions.md §3 attitude matrix R = Rz(PI/2 - psi) Ry(-theta) Rx(phi), body -> world, in ENU components
static func attitude_enu(psi: float, theta: float, phi: float) -> Basis:
	var rz := Basis(Vector3(0, 0, 1), PI * 0.5 - psi)
	var ry := Basis(Vector3(0, 1, 0), -theta)
	var rx := Basis(Vector3(1, 0, 0), phi)
	return rz * ry * rx


## conventions.md §11 boat node basis M R C^-1: its columns are M R applied to the body y, z and x axes
static func boat_basis(psi: float, theta: float, phi: float) -> Basis:
	var r := attitude_enu(psi, theta, phi)
	var by := r * Vector3(0, 1, 0)
	var bz := r * Vector3(0, 0, 1)
	var bx := r * Vector3(1, 0, 0)
	return Basis(_m(by), _m(bz), _m(bx))


static func _m(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)


## body-frame point (x fwd, y port, z up) to model axes
static func body_to_model(p: Vector3) -> Vector3:
	return Vector3(p.y, p.z, p.x)


## boat node transform for a pose (hull reference point at (pos_x, pos_y, z))
static func boat_transform(pos_x: float, pos_y: float, z: float, psi: float, theta: float, phi: float) -> Transform3D:
	return Transform3D(boat_basis(psi, theta, phi), enu_to_scene(pos_x, pos_y, z))


## the rotation by `angle` about `axis` through the point `p` (p stays in place)
static func about(p: Vector3, axis: Vector3, angle: float) -> Transform3D:
	var b := Basis(axis, angle)
	return Transform3D(b, p - b * p)


## smoothstep on [0, 1]
static func smoothstep01(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
