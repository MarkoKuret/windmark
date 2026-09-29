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
## twist_top, camber, tack_line_max, furl_radius, boom_pivot, boom_axis, mast_step, mast_axis, fwd, port, up, phi,
## clearance, mast_head (§7.4; set_obstacles(sails) before each update of a flying sail).

enum Kind { MAIN, HEADSAIL, ASYM, SYM }
## BOOM: the main about the boom axis; LUFF: jib, genoa, code zero about the luff; SPRIT: asymmetric on a fixed
## sprit; POLE: a flying sail on a pole (sail_visuals.md §7)
enum Mode { BOOM, LUFF, SPRIT, POLE }

const KNOT := 1852.0 / 3600.0
const C_HOOK := 0.0369260386
const TAU_SMOOTH := 0.25
const DT_MAX := 0.1
## §4, §7.4 clearance constants: push slope, ease threshold (in clearances), ease cap (rad)
const PUSH_SLOPE := 0.3
const PUSH_EASE := 3.0
const EASE_MAX := 0.35

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
var camber := 0.26
## the code zero cap of §6.2 (a headsail with a `camber` key), 0 = none
var cam_cap := 0.0
var tack_line_max := 0.0
var furl_radius := 0.05
## §7.4 margin off the other sails and the mast, m (0: no clearance)
var clearance := 0.0
var has_mast_head := false
var mast_head := Vector3.UP
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
## per row, per update: camber over chord and chord shortening (§6.3)
var _drow := PackedFloat32Array()
var _srow := PackedFloat32Array()

## drivers kept between frames
var phi := 0.0
var s_b := 1.0
var tl := 0.0
var _tl_set := false
## §7.4: the obstacles (SailShapeRef), their sections this update, and the ease of the last update
var _obs: Array = []
var _secs: Array = []
var _ease := 0.0
## §7.4 rest distances from vertex k to its neighbour along the row, up the column and the two diagonals up
var _ec := PackedFloat32Array()
var _er := PackedFloat32Array()
var _e1 := PackedFloat32Array()
var _e2 := PackedFloat32Array()

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
	# §4 camber: flying sails always; a headsail only with the key. `depth` is ignored.
	camber = float(p.get("camber", 0.26))
	cam_cap = camber if kind == Kind.HEADSAIL and p.has("camber") else 0.0
	tack_line_max = float(p.get("tack_line_max", tack_line_max))
	fwd = p.get("fwd", fwd)
	port = p.get("port", port)
	up = p.get("up", up)
	boom_pivot = p.get("boom_pivot", boom_pivot)
	boom_axis = (p.get("boom_axis", up) as Vector3).normalized()
	mast_step = p.get("mast_step", mast_step)
	mast_axis = (p.get("mast_axis", up) as Vector3).normalized()
	phi = float(p.get("phi", 0.0))
	clearance = float(p.get("clearance", 0.0))
	has_mast_head = p.has("mast_head")
	mast_head = p.get("mast_head", mast_step + mast_axis)
	_obs = []
	_ease = 0.0
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
	_drow.resize(rows)
	_drow.fill(0.0)
	_srow.resize(rows)
	_srow.fill(1.0)
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
	_ec.resize(n)
	_ec.fill(0.0)
	_er.resize(n)
	_er.fill(0.0)
	_e1.resize(n)
	_e1.fill(0.0)
	_e2.resize(n)
	_e2.fill(0.0)
	for i in rows:
		for j in cols:
			var k := i * cols + j
			if j + 1 < cols:
				_ec[k] = rest_mid[k].distance_to(rest_mid[k + 1])
			if i + 1 < rows:
				_er[k] = rest_mid[k].distance_to(rest_mid[k + cols])
				if j + 1 < cols:
					_e1[k] = rest_mid[k].distance_to(rest_mid[k + cols + 1])
				if j > 0:
					_e2[k] = rest_mid[k].distance_to(rest_mid[k + cols - 1])
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
		if cam_cap > 0.0:
			var dm := cam_cap * sa / 0.2362
			d_cam = dm * tanh(d_cam / dm)
	else:
		if kind == Kind.SYM:
			f_fly = absf(fill(sin(beta), fill_gain, fill_curve))
		else:
			f_fly = fill_gain * clampf(aws / KNOT, 3.0, 6.0) / 6.0
		var uw := fwd * cos(awa) - port * sin(awa)
		wv = Vector3(uw.dot(ap) * 0.5 / fill_curve, uw.dot(lp) * 0.5, uw.dot(np))
		wv = wv.normalized() if wv.length_squared() > 1e-12 else Vector3(0, 0, 1)
		var fc := camber * minf(f_fly, 1.15)
		for i in rows:
			var hh := 2.0 * _hrow[i] - 1.0
			_drow[i] = fc * (1.0 - 0.45 * hh * hh)
			_srow[i] = 1.0 / (1.0 + 8.0 / 3.0 * _drow[i] * _drow[i])
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
	# §7.4 the ease of a flying sail off the other sails (the head lies on the luff axis)
	var hd := s_t * head
	var clearing := clearance > 0.0 and (not _obs.is_empty() or has_mast_head)
	_ease = 0.0
	if clearing and not _obs.is_empty():
		_sections(s_t, piv, ax, base)
		_ease = _ease_for(beta, s_t, piv, ax, base, hd)
	var es := _sgn(beta) * _ease
	# §7 placement, row by row with the twist toward leeward
	for i in rows:
		var th := base + tl * twist_top * pow(_hrow[i], 1.5) + es
		var xr := _about(piv, ax, th) * s_t
		for j in cols:
			var k := i * cols + j
			var lc := _loc[k]
			_mid[k] = xr * (tack + ah * lc.x + lh * lc.y + nh * lc.z)
	if clearing:
		_push(awa, hd)
	_layers(np)


## §7.4: the other sails this (flying) sail keeps clear of, as last placed; set before each update.
func set_obstacles(obstacles: Array) -> void:
	_obs = []
	for o in obstacles:
		if o is SailShapeRef and o != self and o.n > 0:
			_obs.append(o)


func get_ease() -> float:
	return _ease


## §7.4: mean row heights and the bow-facing foot normal of each obstacle, the side from this sail's clew before
## the ease.
func _sections(s_t: Transform3D, piv: Vector3, ax: Vector3, base: float) -> void:
	var lc := _loc[cols - 1]
	var xr := _about(piv, ax, base + tl * twist_top * pow(_hrow[0], 1.5)) * s_t
	var cl := xr * (tack + ah * lc.x + lh * lc.y + nh * lc.z)
	var sk := _sgn((cl - mast_step).dot(port))
	var bow := fwd + port * (0.3 * sk)
	_secs = []
	for o in _obs:
		var sh: SailShapeRef = o
		var z := PackedFloat32Array()
		z.resize(sh.rows)
		var box := PackedFloat32Array()
		box.resize(4 * sh.rows)
		for i in sh.rows:
			var zz := 0.0
			var bx := [INF, -INF, INF, -INF]
			for j in sh.cols:
				var m := sh._mid[i * sh.cols + j]
				zz += m.dot(up)
				var x := m.dot(fwd)
				var y := m.dot(port)
				bx = [minf(bx[0], x), maxf(bx[1], x), minf(bx[2], y), maxf(bx[3], y)]
			z[i] = zz / sh.cols
			for q in 4:
				box[4 * i + q] = bx[q]
		for i in sh.rows - 1:  # row i's box covers rows i and i + 1
			box[4 * i] = minf(box[4 * i], box[4 * i + 4])
			box[4 * i + 1] = maxf(box[4 * i + 1], box[4 * i + 5])
			box[4 * i + 2] = minf(box[4 * i + 2], box[4 * i + 6])
			box[4 * i + 3] = maxf(box[4 * i + 3], box[4 * i + 7])
		var ch := sh._mid[sh.cols - 1] - sh._mid[0]
		var f := up.cross(ch - up * ch.dot(up))
		f = f.normalized() if f.length_squared() > 1e-12 else port
		_secs.append({"s": sh, "z": z, "f": f if f.dot(bow) >= 0.0 else -f, "box": box})


## §7.4: clearance of p from an obstacle's section at p's height (horizontal): [x, push direction]; INF when p
## is more than `reach` from the section's bounds.
func _clear_x(o: Dictionary, p: Vector3, reach: float) -> Array:
	var sh: SailShapeRef = o["s"]
	var z: PackedFloat32Array = o["z"]
	var rn := sh.rows
	var cn := sh.cols
	var pz := p.dot(up)
	if pz < z[0] - clearance or pz > z[rn - 1]:
		return [INF, Vector3.ZERO]
	var r := clampi(z.bsearch(pz, false) - 1, 0, rn - 2)
	var box: PackedFloat32Array = o["box"]
	var px := p.dot(fwd)
	var py := p.dot(port)
	if px < box[4 * r] - reach or px > box[4 * r + 1] + reach or py < box[4 * r + 2] - reach \
			or py > box[4 * r + 3] + reach:
		return [INF, Vector3.ZERO]
	var den := z[r + 1] - z[r]
	var t := clampf((pz - z[r]) / den, 0.0, 1.0) if den > 1e-6 else 0.0
	var ph := p - up * pz
	var best := INF
	var bs := 0.0
	var bj := 0
	var bq := Vector3.ZERO
	var bd := Vector3.ZERO
	var q0 := _sec_pt(sh, r, 0, t)
	for j in cn - 1:
		var q1 := _sec_pt(sh, r, j + 1, t)
		var d := q1 - q0
		var l2 := d.length_squared()
		var sp := clampf((ph - q0).dot(d) / l2, 0.0, 1.0) if l2 > 1e-12 else 0.0
		var q := q0 + d * sp
		var d2 := (ph - q).length_squared()
		if d2 < best:
			best = d2
			bj = j
			bs = sp
			bq = q
			bd = d
		q0 = q1
	if (bj == 0 and bs <= 0.0) or (bj == cn - 2 and bs >= 1.0) or bd.length_squared() < 1e-12:
		var v := ph - bq
		var ln := v.length()
		return [ln, v / ln if ln > 1e-6 else o["f"]]
	var g := up.cross(bd).normalized()
	if g.dot(o["f"]) < 0.0:
		g = -g
	return [(ph - bq).dot(g), g]


func _sec_pt(sh: SailShapeRef, r: int, j: int, t: float) -> Vector3:
	var a := sh._mid[r * sh.cols + j]
	var q := a + (sh._mid[(r + 1) * sh.cols + j] - a) * t
	return q - up * q.dot(up)


func _mast_x(p: Vector3, lee: Vector3) -> Array:
	var d := p - mast_step
	var axv := mast_head - mast_step
	var ln := axv.length()
	if ln < 1e-6:
		return [INF, Vector3.ZERO]
	var au := axv / ln
	var tz := d.dot(au)
	if tz < 0.0 or tz > ln:
		return [INF, Vector3.ZERO]
	var rad := d - au * tz
	var x := rad.length()
	return [x, rad / x if x > 1e-6 else lee]


func _margin_at(p: Vector3, hd: Vector3) -> float:
	var x := clampf(p.distance_to(hd) / (5.0 * clearance), 0.0, 1.0)
	return clearance * x * x * (3.0 - 2.0 * x)


## §7.4 the ease: the extra turn about the luff that brings the leech samples clear of the obstacles.
func _ease_for(beta: float, s_t: Transform3D, piv: Vector3, ax: Vector3, base: float, hd: Vector3) -> float:
	var delta := 0.0
	var es := _sgn(beta)
	for it in 4:
		var worst := INF
		var rr := 1.0
		var i := 0
		while true:  # rows 0, 3, 6, ... and the one below the head
			var lc := _loc[i * cols + cols - 1]
			var th := base + tl * twist_top * pow(_hrow[i], 1.5) + es * delta
			var pt := (_about(piv, ax, th) * s_t) * (tack + ah * lc.x + lh * lc.y + nh * lc.z)
			var cp := _margin_at(pt, hd)
			for o in _secs:
				var x: float = _clear_x(o, pt, cp)[0] - cp
				if x < worst:
					worst = x
					var d := pt - piv
					rr = (d - ax * d.dot(ax)).length()
			if i == rows - 2:
				break
			i = mini(i + 3, rows - 2)
		worst += PUSH_EASE * clearance  # the push takes up to P_e; the ease only the rest
		if worst >= 0.0:
			break
		delta = minf(delta + (-worst) / maxf(rr, 0.5), EASE_MAX)
	return delta


## §7.4 the spread of the push depths: d_k = max over k' of d_k' - k_p * (rest distance over the cloth), by two
## chamfer passes over the grid (row, column and diagonal neighbours).
func _spread(d: PackedFloat32Array) -> PackedFloat32Array:
	var s := PUSH_SLOPE
	for i in rows:
		for j in cols:
			var k := i * cols + j
			var v := d[k]
			if j > 0:
				v = maxf(v, d[k - 1] - s * _ec[k - 1])
			if i > 0:
				v = maxf(v, d[k - cols] - s * _er[k - cols])
				if j > 0:
					v = maxf(v, d[k - cols - 1] - s * _e1[k - cols - 1])
				if j + 1 < cols:
					v = maxf(v, d[k - cols + 1] - s * _e2[k - cols + 1])
			d[k] = v
	for i in range(rows - 1, -1, -1):
		for j in range(cols - 1, -1, -1):
			var k := i * cols + j
			var v := d[k]
			if j + 1 < cols:
				v = maxf(v, d[k + 1] - s * _ec[k])
			if i + 1 < rows:
				v = maxf(v, d[k + cols] - s * _er[k])
				if j + 1 < cols:
					v = maxf(v, d[k + cols + 1] - s * _e1[k])
				if j > 0:
					v = maxf(v, d[k + cols - 1] - s * _e2[k])
			d[k] = v
	return d


## §7.4 the push: per obstacle the local push (a smooth bump along the obstacle's bow-facing normal) and the
## margin push, then every vertex off the mast.
func _push(awa: float, hd: Vector3) -> void:
	var b := clearance
	var lee := port * _sgn(awa)
	var cp := PackedFloat32Array()
	cp.resize(n)
	for k in n:
		cp[k] = _margin_at(_mid[k], hd)
	var px := PackedFloat32Array()
	px.resize(n)
	var pg := PackedVector3Array()
	pg.resize(n)
	var pd := PackedFloat32Array()
	pd.resize(n)
	for o in _secs:
		var f: Vector3 = o["f"]
		var any := false
		for k in n:
			var xg := _clear_x(o, _mid[k], cp[k] + b)
			px[k] = xg[0]
			pg[k] = xg[1]
			if px[k] < cp[k] + b:
				pd[k] = cp[k] - px[k]
				any = true
			else:
				pd[k] = -INF
		if any:
			pd = _spread(pd)
			for k in n:
				var v := _smax(pd[k], b) * cp[k] / b
				if v > 0.0:
					_mid[k] += f * v
					var xg := _clear_x(o, _mid[k], cp[k] + b)
					px[k] = xg[0]
					pg[k] = xg[1]
		for k in n:
			var x := px[k]
			if x < cp[k] + b:
				_mid[k] += pg[k] * (cp[k] + _smax(x - cp[k], b) - x)
	if has_mast_head:
		for k in n:
			var xg := _mast_x(_mid[k], lee)
			var x: float = xg[0]
			if x < cp[k] + b:
				_mid[k] += xg[1] * (cp[k] + _smax(x - cp[k], b) - x)


static func _smax(x: float, b: float) -> float:
	if x >= b:
		return x
	if x <= -b:
		return 0.0
	return (x + b) * (x + b) / (4.0 * b)


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
	var s := _srow[i]
	var a0 := _a[i * cols]
	var e := _drow[i] * s * _c[i] * 4.0 * uc * (1.0 - uc)
	var i2 := 0.33 * flutter_amp * shiver
	var q := phi - 7.0 * uc
	var m := Vector3(wv.x + 0.1 * i2 * sin(q), wv.y, wv.z + i2 * cos(q))
	var r := Vector3(a0 + (_a[k] - a0) * s, _l[k], 0.0) - m * e
	if kind == Kind.SYM:
		var h := _h[k]
		var g := maxf(0.0, shiver - uc) * (1.0 - (2.0 * h - 1.0) * (2.0 * h - 1.0))
		r.x += (a0 + (_amid[i] - a0) * s - r.x) * 0.5 * g
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
