class_name SailShapeRef
extends RefCounted
## The per-vertex sail shapes of docs/specs/sail_visuals.md (§3 to §9) in GDScript: the test reference of the
## native `SailShape` (game/native/src/sail_shape.cpp) and the fallback when the GDExtension is not built. Both have
## the same calls; keep them in step.
##
## Works in any right-handed frame given by `fwd`, `port` and `up` (the body x, y and z axes in that frame): the
## boat node uses the generated model's axes (port +X, up +Y, bow +Z), the tests the body frame itself.
##
##   configure(rest_mid, rows, cols, params)   once: the rest mid-surface in grid order (row-major from the foot,
##                                             luff to leech) and the look and rig numbers (keys below)
##   advance(dt, aws, awa, backed)             every frame, drawn or not: flutter phase, backed factor, twist side
##   update(phase, progress, beta, gamma, luff_shiver, awa, aws)   the shape, its placement and both layers
##   attach_mesh(rid) / write_mesh()           the grid-order mesh (sail_visuals.md §3.1, §11) and its update
##
## params: kind (Kind), mode (Mode), furling, fill_gain, fill_curve, flutter_amp, flutter_rate, flutter_rate_max,
## twist_top, depth, tack_line_max, furl_radius, boom_pivot, boom_axis, mast_step, mast_axis, fwd, port, up, phi.

enum Kind { MAIN, HEADSAIL, ASYM, SYM }
## BOOM: the main about the boom axis; LUFF: jib, genoa, code zero about the luff; SPRIT: asymmetric on a fixed
## sprit; POLE: a flying sail on a pole (sail_visuals.md §7)
enum Mode { BOOM, LUFF, SPRIT, POLE }

const KNOT := 1852.0 / 3600.0
const C_HOOK := 0.0369260386
const TAU_SMOOTH := 0.25
const DT_MAX := 0.1

var rows := 0
var cols := 0
var n := 0
var kind := 0
var mode := 0
var furling := false
var fill_gain := 0.6
var fill_curve := 4.0
var flutter_amp := 0.15
var flutter_rate := 0.6
var flutter_rate_max := 10.0
var twist_top := 0.0
var depth := 0.3
var tack_line_max := 0.0
var furl_radius := 0.05
var fwd := Vector3(0, 0, 1)
var port := Vector3(1, 0, 0)
var up := Vector3(0, 1, 0)
var boom_pivot := Vector3.ZERO
var boom_axis := Vector3.UP
var mast_step := Vector3.ZERO
var mast_axis := Vector3.UP

## sail frame (§3.2)
var tack := Vector3.ZERO
var head := Vector3.ZERO
var lh := Vector3.UP
var ah := Vector3.BACK
var nh := Vector3.RIGHT
var sa := 1.0
var sl := 1.0
var a_min := 0.0
var l_min := 0.0
var r_h := 1.0
var kappa := 0.0

## per vertex and per row
var _a := PackedFloat32Array()
var _l := PackedFloat32Array()
var _u := PackedFloat32Array()
var _h := PackedFloat32Array()
var _uc := PackedFloat32Array()
var _c := PackedFloat32Array()
var _amid := PackedFloat32Array()
var _hrow := PackedFloat32Array()

## drivers kept between frames
var phi := 0.0
var s_b := 1.0
var tl := 0.0
var _tl_set := false

## results of the last update
var _loc := PackedVector3Array()
var _mid := PackedVector3Array()
var _pos := PackedVector3Array()
var _nrm := PackedVector3Array()

## mesh
var _rid := RID()
var _bytes := PackedByteArray()
var _noff := 0
var _nstride := 0


func configure(rest_mid: PackedVector3Array, r: int, c: int, p: Dictionary) -> bool:
	if r < 2 or c < 2 or rest_mid.size() != r * c:
		return false
	rows = r
	cols = c
	n = r * c
	kind = int(p.get("kind", Kind.MAIN))
	mode = int(p.get("mode", Mode.BOOM))
	furling = bool(p.get("furling", false))
	fill_gain = float(p.get("fill_gain", fill_gain))
	fill_curve = float(p.get("fill_curve", fill_curve))
	flutter_amp = float(p.get("flutter_amp", flutter_amp))
	flutter_rate = float(p.get("flutter_rate", flutter_rate))
	flutter_rate_max = float(p.get("flutter_rate_max", flutter_rate_max))
	twist_top = float(p.get("twist_top", twist_top))
	depth = float(p.get("depth", depth))
	tack_line_max = float(p.get("tack_line_max", tack_line_max))
	fwd = p.get("fwd", fwd)
	port = p.get("port", port)
	up = p.get("up", up)
	boom_pivot = p.get("boom_pivot", boom_pivot)
	boom_axis = (p.get("boom_axis", up) as Vector3).normalized()
	mast_step = p.get("mast_step", mast_step)
	mast_axis = (p.get("mast_axis", up) as Vector3).normalized()
	phi = float(p.get("phi", 0.0))
	tack = rest_mid[0]
	head = rest_mid[(rows - 1) * cols]
	lh = (head - tack).normalized()
	nh = port.normalized()
	ah = lh.cross(nh).normalized()
	_a.resize(n)
	_l.resize(n)
	_u.resize(n)
	_h.resize(n)
	_uc.resize(n)
	var amin := INF
	var amax := -INF
	var lmin := INF
	var lmax := -INF
	for k in n:
		var d := rest_mid[k] - tack
		_a[k] = d.dot(ah)
		_l[k] = d.dot(lh)
		amin = minf(amin, _a[k])
		amax = maxf(amax, _a[k])
		lmin = minf(lmin, _l[k])
		lmax = maxf(lmax, _l[k])
	a_min = amin
	l_min = lmin
	sa = maxf(amax - amin, 1e-3)
	sl = maxf(lmax - lmin, 1e-3)
	_c.resize(rows)
	_amid.resize(rows)
	_hrow.resize(rows)
	for i in rows:
		for j in cols:
			var k := i * cols + j
			_u[k] = (_a[k] - a_min) / sa
			_h[k] = (_l[k] - l_min) / sl
			_uc[k] = float(j) / (cols - 1)
		_c[i] = rest_mid[i * cols + cols - 1].distance_to(rest_mid[i * cols])
		_amid[i] = 0.5 * (_a[i * cols] + _a[i * cols + cols - 1])
		_hrow[i] = _h[i * cols]
	furl_radius = float(p.get("furl_radius", 0.02 + 0.006 * sa))
	var dh := tack - head
	r_h = maxf((dh - up * dh.dot(up)).length(), 1e-3)
	var hz := -fwd
	var den := hz.dot(ah)
	kappa = hz.dot(lh) / den if absf(den) > 1e-6 else 0.0
	_loc.resize(n)
	_mid.resize(n)
	_pos.resize(2 * n)
	_nrm.resize(2 * n)
	for k in n:
		_loc[k] = Vector3(_a[k], _l[k], 0.0)
		_mid[k] = rest_mid[k]
		_pos[k] = rest_mid[k] + nh * 0.001
		_pos[n + k] = rest_mid[k] - nh * 0.001
		_nrm[k] = nh
		_nrm[n + k] = -nh
	return true


## sail_visuals.md §5.1
static func fill(v: float, g: float, k: float) -> float:
	var x := absf(v)
	var m := clampf(pow(x, 0.75 / k) * exp(-0.01 / (x + 1e-6)), 0.0, 1.0)
	return (1.0 if v >= 0.0 else -1.0) * 0.75 * g * m


static func _sgn(x: float) -> float:
	return 1.0 if x >= 0.0 else -1.0


static func _wrap_pi(x: float) -> float:
	return fposmod(x + PI, TAU) - PI


## sail_visuals.md §5.2, §5.3 and the twist side of §7.1; every frame, paused with the game.
func advance(dt: float, aws: float, awa: float, backed: bool) -> void:
	dt = clampf(dt, 0.0, DT_MAX)
	var w := minf(flutter_rate * aws, flutter_rate_max)
	phi = fposmod(phi + w * dt, TAU)
	var k := 1.0 - exp(-dt / TAU_SMOOTH)
	s_b += ((-1.0 if backed else 1.0) - s_b) * k
	if not _tl_set:
		tl = -_sgn(awa)
		_tl_set = true
	else:
		tl += (-_sgn(awa) - tl) * k


func get_phase() -> float:
	return phi


func set_phase(v: float) -> void:
	phi = v


func get_backed_factor() -> float:
	return s_b


func set_backed_factor(v: float) -> void:
	s_b = v


func get_twist_side() -> float:
	return tl


func set_twist_side(v: float) -> void:
	tl = v
	_tl_set = true


## sail frame numbers for tests and the boat node
func frame() -> Dictionary:
	return {"tack": tack, "head": head, "lh": lh, "ah": ah, "nh": nh, "sa": sa, "sl": sl, "a_min": a_min,
		"l_min": l_min, "kappa": kappa, "r_h": r_h, "furl_radius": furl_radius}


## Copies, as the native class returns them.
## (a', l', n') of every mid vertex in the sail frame, before the placement (grid order)
func local_shape() -> PackedVector3Array:
	return _loc.duplicate()


## the placed mid-surface (grid order)
func mid() -> PackedVector3Array:
	return _mid.duplicate()


## both layers, port layer first (grid order, 2 * rows * cols)
func positions() -> PackedVector3Array:
	return _pos.duplicate()


func normals() -> PackedVector3Array:
	return _nrm.duplicate()


func update(phase: int, progress: float, beta: float, gamma: float, luff_shiver: float, awa: float,
		aws: float) -> void:
	if n == 0:
		return
	if not _tl_set:
		tl = -_sgn(awa)
		_tl_set = true
	var shiver := clampf(luff_shiver, 0.0, 1.0)
	var amp := flutter_amp * sa
	# §7: the swing S and the rotation about the (swung) luff or the boom axis
	var s_t := Transform3D.IDENTITY
	var ge := 0.0
	var piv := tack
	var ax := lh
	match mode:
		Mode.BOOM:
			piv = boom_pivot
			ax = boom_axis
		Mode.SPRIT:
			var lim := asin(minf(1.0, tack_line_max * sl / r_h))
			ge = _sgn(gamma) * minf(absf(gamma), lim)
			s_t = _about(head, up, ge)
		Mode.POLE:
			ge = gamma
			s_t = _about(mast_step, mast_axis, ge)
	if mode == Mode.SPRIT or mode == Mode.POLE:
		piv = s_t * tack
		ax = (s_t.basis * lh).normalized()
	var base := beta - ge
	var b0 := Basis(ax, base) * s_t.basis
	var ap := b0 * ah
	var lp := b0 * lh
	var np := b0 * nh
	# §5.1 drivers
	var d_cam := 0.0
	var f_fly := 0.0
	var wv := Vector3.ZERO
	if kind == Kind.MAIN:
		var b := fill(sin(_wrap_pi(beta + awa)), fill_gain, fill_curve)
		d_cam = _sgn(b) * 4.0 * sa * b * b
	elif kind == Kind.HEADSAIL:
		var b := fill(sin(beta), fill_gain, fill_curve) * s_b
		d_cam = _sgn(b) * 4.0 * sa * b * b
	else:
		if kind == Kind.SYM:
			f_fly = absf(fill(sin(beta), fill_gain, fill_curve))
		else:
			f_fly = fill_gain * clampf(aws / KNOT, 3.0, 6.0) / 6.0
		var uw := fwd * cos(awa) - port * sin(awa)
		wv = Vector3(uw.dot(ap) * 0.5 / fill_curve, uw.dot(lp) * 0.5, uw.dot(np))
		wv = wv.normalized() * f_fly if wv.length_squared() > 1e-12 else Vector3(0, 0, f_fly)
	# §8.1 which shape
	var up_shape := phase == 3 or phase == 4 or kind == Kind.MAIN
	var p := 1.0
	if not up_shape:
		if phase == 2:
			p = progress
		elif phase == 5:
			p = 1.0 - progress if kind == Kind.HEADSAIL else progress
		else:
			p = 0.0
		p = clampf(p, 0.0, 1.0)
	for k in n:
		var loc: Vector3
		@warning_ignore("integer_division")
		var i := k / cols
		if kind == Kind.MAIN:
			loc = _main(k, d_cam, amp, shiver)
		elif kind == Kind.HEADSAIL:
			if up_shape:
				loc = Vector3(_a[k], _l[k], _head_n(_u[k], _a[k], d_cam, amp, shiver))
			elif furling:
				loc = _furl(k, p, d_cam, amp, shiver)
			else:
				loc = _halyard(k, p, d_cam, amp, shiver)
		else:
			var fly := _fly(k, i, wv, shiver)
			if up_shape:
				loc = fly
			elif phase == 5:
				loc = _drop(k, p, fly)
			else:
				loc = _hoist(k, p, fly)
		_loc[k] = loc
	# §7 placement, row by row with the twist toward leeward
	for i in rows:
		var th := base + tl * twist_top * pow(_hrow[i], 1.5)
		var xr := _about(piv, ax, th) * s_t
		for j in cols:
			var k := i * cols + j
			var lc := _loc[k]
			_mid[k] = xr * (tack + ah * lc.x + lh * lc.y + nh * lc.z)
	_layers(np)


func _main(k: int, d_cam: float, amp: float, shiver: float) -> Vector3:
	var h := _h[k]
	var u := _u[k]
	var f := 1.0 - exp(-8.0 * h)
	return Vector3(_a[k], _l[k], f * d_cam * u * (1.0 - u) + amp * shiver * h * u * sin(phi - _a[k]))


func _head_n(u: float, a: float, d_cam: float, amp: float, shiver: float) -> float:
	return 0.5 * d_cam * (pow(u, 4) - C_HOOK * u) + amp * shiver * u * sin(phi - a)


## §8.2
func _halyard(k: int, p: float, d_cam: float, amp: float, shiver: float) -> Vector3:
	var hc := 1.0 - p
	if _h[k] >= hc:
		return Vector3(_a[k], _l[k] - hc * sl, _head_n(_u[k], _a[k], d_cam, amp, shiver))
	return Vector3(_a[k], _a[k] * kappa + 0.03, 0.02 * sl * sin(12.0 * _h[k]))


## §8.3
func _furl(k: int, p: float, d_cam: float, amp: float, shiver: float) -> Vector3:
	var ac := (1.0 - p) * sa
	var r := furl_radius * (0.4 + 0.6 * (1.0 - p))
	if _a[k] - a_min < ac:
		var t := 6.0 * PI * _uc[k]
		return Vector3(a_min + r * (1.0 - cos(t)), _l[k], r * sin(t))
	var a2 := _a[k] - ac
	return Vector3(a2, _l[k], _head_n((a2 - a_min) / sa, a2, d_cam, amp, shiver))


## §6.3, §6.4 the flying shape
func _fly(k: int, i: int, wv: Vector3, shiver: float) -> Vector3:
	var uc := _uc[k]
	var e := depth * _c[i] * 4.0 * uc * (1.0 - uc)
	var i2 := 0.33 * flutter_amp * shiver
	var q := phi - 7.0 * uc
	var m := Vector3(wv.x + 0.1 * i2 * sin(q), wv.y, wv.z + i2 * cos(q))
	var r := Vector3(_a[k], _l[k], 0.0) - m * e
	if kind == Kind.SYM:
		var h := _h[k]
		var g := maxf(0.0, shiver - uc) * (1.0 - (2.0 * h - 1.0) * (2.0 * h - 1.0))
		r.x += (_amid[i] - r.x) * 0.5 * g
		r.z += g * flutter_amp * 0.1 * sa * sin(phi - _a[k])
	return r


## §8.4
func _hoist(k: int, c: float, fly: Vector3) -> Vector3:
	var hy := 1.0
	var kk := 0.0
	if c <= 0.9:
		hy = c / 0.9
	else:
		kk = (c - 0.9) / 0.1
	var h := _h[k]
	var sn := flutter_amp * 0.1 * sa * sin(15.0 * h + phi)
	var g := 0.05 + 0.1 * clampf(10.0 * pow((1.0 - h) * kk, 4), 0.0, 1.0)
	var bundle := Vector3(g * (fly.x + sn), l_min + (_l[k] - l_min) * hy, g * (fly.z - sn))
	return bundle + (fly - bundle) * kk * kk


## §8.5
func _drop(k: int, c: float, fly: Vector3) -> Vector3:
	var thr := l_min + sl * c
	var kk := pow(c, 0.3)
	var r := 1.0 - _h[k]
	var l := _l[k]
	var tg: Vector3
	if l <= thr:
		tg = Vector3(0.05 * sl * sin(4.0 * r), l_min, 0.0)
	else:
		var t2 := (l - thr) / sl
		var w := flutter_amp * 0.1 * sa * 0.63 * atan(8.0 * r) * (1.0 - t2) * 2.0 * sin(l + phi)
		tg = Vector3(_a[k] + (fly.x - _a[k]) * t2 + w, l - (thr - l_min), t2 * fly.z + w)
	return fly + (tg - fly) * kk


## §9 normals by finite differences and the two layers
func _layers(np: Vector3) -> void:
	for i in rows:
		var i0 := maxi(i - 1, 0)
		var i1 := mini(i + 1, rows - 1)
		for j in cols:
			var k := i * cols + j
			var tu := _mid[i * cols + mini(j + 1, cols - 1)] - _mid[i * cols + maxi(j - 1, 0)]
			var tv := _mid[i1 * cols + j] - _mid[i0 * cols + j]
			var nn := tu.cross(tv)
			if nn.length_squared() < 1e-12:
				nn = _nrm[k - cols] if i > 0 else np
			nn = nn.normalized()
			_nrm[k] = nn
			_nrm[n + k] = -nn
			_pos[k] = _mid[k] + nn * 0.001
			_pos[n + k] = _mid[k] - nn * 0.001


## Rotation by `angle` about the line through `p` along `axis` (right-handed).
static func _about(p: Vector3, axis: Vector3, angle: float) -> Transform3D:
	var b := Basis(axis, angle)
	return Transform3D(b, p - b * p)


## The grid-order mesh (sail_visuals.md §3.1) built uncompressed; its vertex buffer is rewritten by write_mesh.
func attach_mesh(rid: RID) -> bool:
	var sd := RenderingServer.mesh_get_surface(rid, 0)
	if int(sd.get("vertex_count", 0)) != 2 * n:
		return false
	var fmt := int(sd["format"])
	if fmt & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES:
		return false
	if RenderingServer.mesh_surface_get_format_vertex_stride(fmt, 2 * n) != 12:
		return false
	_rid = rid
	_bytes = sd["vertex_data"]
	_noff = RenderingServer.mesh_surface_get_format_offset(fmt, 2 * n, Mesh.ARRAY_NORMAL)
	_nstride = RenderingServer.mesh_surface_get_format_normal_tangent_stride(fmt, 2 * n)
	return true


## The vertex buffer as write_mesh sends it: positions (3 floats) then the normal-tangent stream (octahedral
## normal in two 16-bit units, the tangent as the mesh was built).
func vertex_bytes() -> PackedByteArray:
	for k in 2 * n:
		var o := 12 * k
		_bytes.encode_float(o, _pos[k].x)
		_bytes.encode_float(o + 4, _pos[k].y)
		_bytes.encode_float(o + 8, _pos[k].z)
		var e := _nrm[k].octahedron_encode()
		var on := _noff + _nstride * k
		_bytes.encode_u16(on, int(clampf(e.x * 65535.0, 0.0, 65535.0)))
		_bytes.encode_u16(on + 2, int(clampf(e.y * 65535.0, 0.0, 65535.0)))
	return _bytes


func write_mesh() -> void:
	if _rid.is_valid():
		RenderingServer.mesh_surface_update_vertex_region(_rid, 0, 0, vertex_bytes())
