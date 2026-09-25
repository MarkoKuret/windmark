extends SceneTree
## Headless tests of the sail visuals (docs/specs/sail_visuals.md §12), run by run_sail_visuals_test.sh:
##   godot --headless --path game -s res://tests/sail_visuals_test.gd
## Every numbered test of §12 runs on the GDScript reference (SailShapeRef) and on the native SailShape (the
## GDExtension, game/native) when it is loaded; the two are compared on random drivers in every phase; the native
## vertex buffer is checked byte for byte against Godot's own encoding of the same arrays; the generated wm7 and
## wm12 sails are set up by BoatView (grid-order meshes, native shapes, in-place buffer writes); the update rate
## by distance and the frustum; and the cost per sail update is printed.

const KNOT := 1852.0 / 3600.0
const K := SailShapeRef.Kind
const M := SailShapeRef.Mode
const UP := 3
const HOISTING := 2
const DROPPING := 5
const PREPARE_HOIST := 1
## the body frame for the synthetic grids
const BODY := {"fwd": Vector3(1, 0, 0), "port": Vector3(0, 1, 0), "up": Vector3(0, 0, 1)}

var t := TestLog.new()
var native := false


func _init() -> void:
	_main()


func _main() -> void:
	await process_frame
	native = ClassDB.class_exists("SailShape")
	print("native SailShape: ", "loaded" if native else "not built (reference only)")
	for impl in (["ref", "native"] if native else ["ref"]):
		_spec_tests(impl)
	if native:
		_native_vs_ref()
		_vertex_bytes()
	_boats()
	await _rate_by_distance()
	_perf()
	t.finish(self, "sail visuals test")


# ---- helpers ------------------------------------------------------------------------------------------------

## §12 rectangle: luff on x = 0 from z = 0 to 9 m, leech at x = -3 m, 11 x 11, in y = 0 (body frame)
static func rect() -> PackedVector3Array:
	var g := PackedVector3Array()
	for i in 11:
		for j in 11:
			g.append(Vector3(-3.0 * j / 10.0, 0.0, 9.0 * i / 10.0))
	return g


## a pointed-head triangle (collapsed head row), same frame
static func tri() -> PackedVector3Array:
	var g := PackedVector3Array()
	for i in 11:
		for j in 11:
			var f := float(i) / 10.0
			g.append(Vector3(-3.0 * (1.0 - f) * j / 10.0, 0.0, 9.0 * f))
	return g


func mk(impl: String, kind: int, mode: int, extra: Dictionary = {}, grid: PackedVector3Array = rect()) -> Variant:
	var sh: Variant = ClassDB.instantiate("SailShape") if impl == "native" else SailShapeRef.new()
	var p := BODY.duplicate()
	p["kind"] = kind
	p["mode"] = mode
	var defaults := {
		K.MAIN: {"fill_gain": 0.6, "fill_curve": 4.0, "flutter_amp": 0.15, "twist_top": 0.07},
		K.HEADSAIL: {"fill_gain": 0.75, "fill_curve": 1.2, "flutter_amp": 0.07, "twist_top": 0.105},
		K.ASYM: {"fill_gain": 1.0, "fill_curve": 1.0, "flutter_amp": 1.0, "twist_top": 0.0, "depth": 0.30,
			"tack_line_max": 0.04},
		K.SYM: {"fill_gain": 1.5, "fill_curve": 1.5, "flutter_amp": 1.0, "twist_top": 0.0, "depth": 0.35},
	}
	p.merge(defaults[kind])
	p["flutter_rate"] = 2.904
	p["flutter_rate_max"] = 9.04
	p.merge(extra, true)
	var r: int = int(sqrt(grid.size()))
	t.ok(sh.configure(grid, r, r, p), "%s configure" % impl)
	return sh


static func max_move(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var m := 0.0
	for k in a.size():
		m = maxf(m, a[k].distance_to(b[k]))
	return m


static func finite(v: PackedVector3Array) -> bool:
	for p in v:
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			return false
	return true


## sails.md §7 luff shiver (shiver_angle 0.3 rad here)
static func shiver(beta: float, awa: float, ang := 0.3) -> float:
	var d := Frames.wrap_pi(beta + awa)
	if absf(d) >= PI / 2:
		return 0.0
	var q := clampf(absf(sin(d)) / (sin(ang) + 1e-4), 0.0, 1.0)
	return 1.0 - q * q


# ---- §12 tests --------------------------------------------------------------------------------------------

func _spec_tests(impl: String) -> void:
	var d2r := PI / 180.0
	t.begin("%s: 1-3 main fill, backwind, mirror" % impl)
	var sh: Variant = mk(impl, K.MAIN, M.BOOM, {"twist_top": 0.0})
	var cases := [[25.0, 0.3739, 0.1373], [10.0, 0.3059, 0.0919], [40.0, 0.4078, 0.1633]]
	for c in cases:
		var b := SailShapeRef.fill(sin(c[0] * d2r), 0.6, 4.0)
		t.near(b, c[1], 5e-4, "b at d = %d deg" % c[0])
		sh.update(UP, 1.0, -5.0 * d2r if c[0] == 25.0 else (c[0] - 30.0) * d2r, 0.0, 0.0, 30.0 * d2r, 5.0)
		var loc: PackedVector3Array = sh.local_shape()
		t.near(loc[5 * 11 + 5].z / 3.0, c[2], 1e-3, "camber n'/Sa at (0.5, 0.5), d = %d deg" % c[0])
	sh.update(UP, 1.0, -5.0 * d2r, 0.0, 0.0, 30.0 * d2r, 5.0)
	var l1: PackedVector3Array = sh.local_shape()
	var edges := 0.0
	for i in 11:
		edges = maxf(edges, maxf(absf(l1[i * 11].z), absf(l1[i * 11 + 10].z)))
	t.ok(edges < 1e-6 and l1[5 * 11 + 5].z > 0.0, "n' = 0 on luff and leech, belly to port (leeward)")
	sh.update(UP, 1.0, -40.0 * d2r, 0.0, 0.0, 30.0 * d2r, 5.0)
	var l2: PackedVector3Array = sh.local_shape()
	var neg := true
	for i in range(1, 11):
		for j in range(1, 10):
			neg = neg and l2[i * 11 + j].z < 0.0
	t.ok(neg, "over-sheeted (d = -10 deg): every inner n' to windward")
	sh.update(UP, 1.0, 5.0 * d2r, 0.0, 0.0, -30.0 * d2r, 5.0)
	var l3: PackedVector3Array = sh.local_shape()
	var mirr := 0.0
	for k in l1.size():
		mirr = maxf(mirr, absf(l3[k].z + l1[k].z))
	t.ok(mirr < 1e-6, "awa -30, beta +5: the mirror of test 1 (%.7f)" % mirr)

	t.begin("%s: 4-5 headsail, backed" % impl)
	var jb: Variant = mk(impl, K.HEADSAIL, M.LUFF, {"twist_top": 0.0})
	t.near(SailShapeRef.fill(sin(-25.0 * d2r), 0.75, 1.2), -0.3207, 5e-4, "jib b at beta -25")
	jb.update(UP, 1.0, -25.0 * d2r, 0.0, 0.0, 30.0 * d2r, 5.0)
	var lj: PackedVector3Array = jb.local_shape()
	t.near(lj[10].z / 3.0, -0.198, 1e-3, "clew n'/Sa (inboard)")
	var best := -INF
	var best_j := -1
	for j in 11:
		var u := j / 10.0
		var belly := lj[5 * 11 + j].z - u * lj[5 * 11 + 10].z
		if belly > best:
			best = belly
			best_j = j
	var d_cam := -0.4113 * 3.0
	var fine := 0.5 * absf(d_cam) * (0.63 - pow(0.63, 4)) / 3.0
	t.near(fine, 0.0972, 5e-4, "belly against the luff-clew line at u = 0.63 (formula)")
	t.ok(best_j == 6 and absf(best / 3.0 - 0.5 * 0.4113 * (0.6 - pow(0.6, 4))) < 1e-3,
		"grid belly largest at u = 0.6 next to 0.63, toward port (%.4f Sa)" % (best / 3.0))
	jb.update(UP, 1.0, 0.0, 0.0, 0.0, 30.0 * d2r, 5.0)
	var flat := 0.0
	for p in jb.local_shape():
		flat = maxf(flat, absf(p.z))
	t.ok(flat < 1e-7, "beta = 0: every n' = 0")
	jb.set_backed_factor(1.0)
	var tt := 0.0
	var t0 := -1.0
	for f in 60:
		var before: float = jb.get_backed_factor()
		jb.advance(1.0 / 60.0, 0.0, 30.0 * d2r, true)
		tt += 1.0 / 60.0
		if before > 0.0 and jb.get_backed_factor() <= 0.0:
			t0 = tt
	t.ok(absf(t0 - 0.173) <= 1.0 / 60.0, "s_b passes 0 at %.3f s (0.173)" % t0)
	t.near(jb.get_backed_factor(), -0.963, 1e-3, "s_b after 1 s")
	jb.update(UP, 1.0, -25.0 * d2r, 0.0, 0.0, 30.0 * d2r, 5.0)
	t.ok(jb.local_shape()[10].z > 0.0 and jb.local_shape()[5 * 11 + 6].z > 0.0, "backed: belly and clew on the other side")

	t.begin("%s: 6 flutter" % impl)
	var mf: Variant = mk(impl, K.MAIN, M.BOOM, {"twist_top": 0.0})
	var lo := INF
	var hi := -INF
	for s in 64:
		mf.set_phase(TAU * s / 64.0)
		mf.update(UP, 1.0, -30.0 * d2r, 0.0, 1.0, 30.0 * d2r, 5.0)
		var z: float = mf.local_shape()[10 * 11 + 10].z
		lo = minf(lo, z)
		hi = maxf(hi, z)
	t.near(hi, 0.45, 2e-3, "head-leech flutter +0.15 Sa")
	t.near(lo, -0.45, 2e-3, "head-leech flutter -0.15 Sa")
	mf.set_phase(0.0)
	mf.advance(0.1, 6.0, 30.0 * d2r, false)
	t.near(mf.get_phase() / 0.1, 9.04, 1e-3, "wm7 phase speed at aws 6 m/s (period %.2f s)" % (TAU / 9.04))
	var big: Variant = mk(impl, K.MAIN, M.BOOM, {"flutter_rate": 0.6, "flutter_rate_max": 10.0})
	big.set_phase(0.0)
	big.advance(0.1, 6.0, 30.0 * d2r, false)
	t.near(big.get_phase() / 0.1, 3.6, 1e-3, "12 m boat phase speed (period %.2f s)" % (TAU / 3.6))
	var crest := []
	for ph in [PI / 2 + 0.8, PI / 2 + 1.3]:
		mf.set_phase(ph)
		mf.update(UP, 1.0, -30.0 * d2r, 0.0, 1.0, 30.0 * d2r, 5.0)
		var lb: PackedVector3Array = mf.local_shape()
		var bj := 0
		for j in 11:
			if lb[10 * 11 + j].z > lb[10 * 11 + bj].z:
				bj = j
		crest.append(bj)
	t.ok(crest[1] > crest[0], "crests move toward the leech (col %d then %d)" % crest)

	t.begin("%s: 7 asym inflation" % impl)
	var ak: Variant = mk(impl, K.ASYM, M.SPRIT)
	for c in [[1.0, 0.5], [1.543, 0.5], [2.0, 0.648], [3.087, 1.0], [8.0, 1.0]]:
		ak.update(UP, 1.0, -60.0 * d2r, 0.0, 0.0, 100.0 * d2r, c[0])
		var la: PackedVector3Array = ak.local_shape()
		var disp := la[5 * 11 + 5].distance_to(Vector3(-1.5 * -1.0, 4.5, 0.0))
		t.near(disp / (0.30 * 3.0), c[1], 0.01 * c[1], "aws %.3f m/s: F" % c[0])

	t.begin("%s: 9 asym gybe continuity" % impl)
	var ag: Variant = mk(impl, K.ASYM, M.SPRIT)
	var prev := PackedVector3Array()
	var worst := 0.0
	for f in 121:
		var s := f / 120.0
		var beta := Frames.wrap_pi(-170.0 * d2r - 20.0 * d2r * s)
		var awa := Frames.wrap_pi(170.0 * d2r + 20.0 * d2r * s)
		ag.advance(1.0 / 60.0, 4.0, awa, false)
		ag.update(UP, 1.0, beta, 0.0, 0.0, awa, 4.0)
		var m: PackedVector3Array = ag.mid()
		if not prev.is_empty():
			worst = maxf(worst, max_move(prev, m))
		prev = m.duplicate()
	t.ok(worst <= 0.05 * 3.0, "beta through +-180 deg: largest move per frame %.3f m (<= %.3f)" % [worst, 0.15])

	t.begin("%s: 10 halyard hoist" % impl)
	var hj: Variant = mk(impl, K.HEADSAIL, M.LUFF)
	hj.update(HOISTING, 0.5, -20.0 * d2r, 0.0, 0.0, 30.0 * d2r, 5.0)
	var top := -INF
	var flake_ok := true
	var kap: float = hj.frame()["kappa"]
	var lh: PackedVector3Array = hj.local_shape()
	for k in lh.size():
		top = maxf(top, lh[k].y)
		if (k / 11) / 10.0 < 0.5 - 1e-6:
			flake_ok = flake_ok and absf(lh[k].y - (lh[k].x * kap + 0.03)) < 1e-5 and absf(lh[k].z) <= 0.02 * 9.0 + 1e-6
	t.near(top, 4.5, 1e-3, "p = 0.5: the highest vertex at 0.5 Sl")
	t.ok(flake_ok, "flaked vertices on the flake line, within 0.02 Sl")
	hj.update(HOISTING, 1.0, -20.0 * d2r, 0.0, 0.3, 30.0 * d2r, 5.0)
	var m1: PackedVector3Array = hj.mid().duplicate()
	hj.update(UP, 1.0, -20.0 * d2r, 0.0, 0.3, 30.0 * d2r, 5.0)
	t.ok(max_move(m1, hj.mid()) < 1e-5, "p = 1 is the up shape")
	hj.update(PREPARE_HOIST, 0.0, -20.0 * d2r, 0.0, 0.0, 30.0 * d2r, 5.0)
	var above := -INF
	for p in hj.local_shape():
		above = maxf(above, p.y)
	t.ok(above <= 0.03 + 3.0 * kap + 1e-6, "p = 0: nothing above the deck line (%.4f m)" % above)
	var dj: Variant = mk(impl, K.HEADSAIL, M.LUFF)
	dj.update(DROPPING, 0.5, -20.0 * d2r, 0.0, 0.0, 30.0 * d2r, 5.0)
	var dtop := -INF
	for p in dj.local_shape():
		dtop = maxf(dtop, p.y)
	t.near(dtop, 4.5, 1e-3, "drop half way: the head at 0.5 Sl")

	t.begin("%s: 11 furler" % impl)
	var fj: Variant = mk(impl, K.HEADSAIL, M.LUFF, {"furling": true, "furl_radius": 0.04})
	fj.update(HOISTING, 0.3, -20.0 * d2r, 0.0, 0.0, 30.0 * d2r, 5.0)
	var lf: PackedVector3Array = fj.local_shape()
	var amin := INF
	var ua := INF
	var ub := -INF
	for k in lf.size():
		amin = minf(amin, lf[k].x)
		var a0 := 3.0 * (k % 11) / 10.0
		if a0 >= 0.7 * 3.0 - 1e-5:
			ua = minf(ua, lf[k].x)
			ub = maxf(ub, lf[k].x)
	t.ok(amin >= -1e-6, "p = 0.3: no vertex forward of the luff (%.5f)" % amin)
	t.ok(ub - ua <= 0.3 * 3.0 + 1e-4 and ub - ua >= 0.2 * 3.0, "unrolled part spans %.3f m of chord (0.3 Sa = 0.9)" % (ub - ua))
	fj.update(PREPARE_HOIST, 0.0, -20.0 * d2r, 0.0, 0.0, 30.0 * d2r, 5.0)
	var far := 0.0
	for p in fj.local_shape():
		far = maxf(far, Vector2(p.x, p.z).length())
	t.ok(far <= 2.0 * 0.04 + 1e-6, "p = 0: every vertex within 2 furl radii of the luff (%.4f m)" % far)

	t.begin("%s: 12-13 spinnaker hoist and drop" % impl)
	var sk: Variant = mk(impl, K.ASYM, M.SPRIT)
	var dr := [-90.0 * d2r, 0.0, 0.2, 120.0 * d2r, 5.0]
	sk.set_phase(1.0)
	sk.update(UP, 1.0, dr[0], dr[1], dr[2], dr[3], dr[4])
	var fly: PackedVector3Array = sk.local_shape().duplicate()
	var fly_mid: PackedVector3Array = sk.mid().duplicate()
	sk.update(HOISTING, 0.45, dr[0], dr[1], dr[2], dr[3], dr[4])
	var ht := -INF
	for p in sk.local_shape():
		ht = maxf(ht, p.y)
	t.near(ht, 4.5, 1e-4, "c = 0.45: the highest vertex at l_min + 0.5 Sl")
	sk.update(HOISTING, 0.9, dr[0], dr[1], dr[2], dr[3], dr[4])
	var b9: PackedVector3Array = sk.local_shape()
	var ht9 := -INF
	var thin := true
	var as_ := 1.0 * 0.1 * 3.0
	for k in b9.size():
		ht9 = maxf(ht9, b9[k].y)
		thin = thin and absf(b9[k].x) + absf(b9[k].z) <= 0.05 * (absf(fly[k].x) + absf(fly[k].z) + 2.0 * as_) + 1e-6
	t.near(ht9, 9.0, 1e-4, "c = 0.9: the bundle reaches the head")
	t.ok(thin, "c = 0.9: the bundle hugs the luff")
	sk.update(HOISTING, 1.0, dr[0], dr[1], dr[2], dr[3], dr[4])
	t.ok(max_move(sk.mid(), fly_mid) < 1e-5, "c = 1: the flying shape")
	sk.update(DROPPING, 1.0, dr[0], dr[1], dr[2], dr[3], dr[4])
	var gathered := 0.0
	for p in sk.local_shape():
		gathered = maxf(gathered, p.length())
	t.ok(gathered <= 0.05 * 9.0 + 1e-5, "drop c = 1: every vertex within 0.05 Sl of the tack (%.3f m)" % gathered)
	var last := INF
	var mono := true
	for s in 51:
		sk.update(DROPPING, s / 50.0, dr[0], dr[1], dr[2], dr[3], dr[4])
		var hh := -INF
		for p in sk.local_shape():
			hh = maxf(hh, p.y)
		mono = mono and hh <= last + 1e-5
		last = hh
	t.ok(mono, "drop: the highest vertex falls monotonically")
	var sy: Variant = mk(impl, K.SYM, M.POLE, {"mast_step": Vector3(1.5, 0, 0), "mast_axis": Vector3(0, 0, 1)})
	sy.update(UP, 1.0, -80.0 * d2r, 30.0 * d2r, 0.8, 150.0 * d2r, 4.0)
	t.ok(finite(sy.mid()), "symmetric spinnaker on a pole, luffing: finite")

	t.begin("%s: 14 normals and layers" % impl)
	for kd in [K.MAIN, K.HEADSAIL]:
		var r0: Variant = mk(impl, kd, M.BOOM if kd == K.MAIN else M.LUFF, {"twist_top": 0.0})
		r0.update(UP, 1.0, 0.0, 0.0, 0.0, 0.0, 5.0)
		var worst_n := 0.0
		var nr: PackedVector3Array = r0.normals()
		for k in 121:
			worst_n = maxf(worst_n, nr[k].distance_to(Vector3(0, 1, 0)))
		t.ok(worst_n < 1e-6, "rest pose: port normals (0, 1, 0) (%s, %.7f)" % ["main" if kd == K.MAIN else "jib", worst_n])
	var shapes := [
		[K.MAIN, M.BOOM, UP, 1.0, false], [K.HEADSAIL, M.LUFF, HOISTING, 0.4, false],
		[K.HEADSAIL, M.LUFF, PREPARE_HOIST, 0.0, true], [K.HEADSAIL, M.LUFF, HOISTING, 0.0, false],
		[K.ASYM, M.SPRIT, DROPPING, 1.0, false], [K.ASYM, M.SPRIT, HOISTING, 0.3, false],
		[K.SYM, M.POLE, DROPPING, 0.7, false]]
	var sep_ok := true
	var nan_ok := true
	for g in [rect(), tri()]:
		for c in shapes:
			var z: Variant = mk(impl, c[0], c[1], {"furling": c[4]}, g)
			z.update(c[2], c[3], -30.0 * d2r, 0.1, 0.7, 60.0 * d2r, 4.0)
			var ps: PackedVector3Array = z.positions()
			var ns: PackedVector3Array = z.normals()
			nan_ok = nan_ok and finite(ps) and finite(ns)
			for k in 121:
				sep_ok = sep_ok and (ps[k] - ps[121 + k]).distance_to(0.002 * ns[k]) < 1e-5 \
					and absf(ns[k].length() - 1.0) < 1e-4 and ns[121 + k].is_equal_approx(-ns[k])
	t.ok(sep_ok, "layers 2 mm apart along unit normals, starboard normal = -port")
	t.ok(nan_ok, "no NaN: collapsed head, gathered drop, fully furled, bundle")

	t.begin("%s: 15 continuity (tack, gybe)" % impl)
	for run in ["tack", "gybe"]:
		var mn: Variant = mk(impl, K.MAIN, M.BOOM, {"boom_pivot": Vector3(0.3, 0, 0)})
		var jn: Variant = mk(impl, K.HEADSAIL, M.LUFF)
		var bm := -5.0 * d2r if run == "tack" else -70.0 * d2r
		var bj := -20.0 * d2r
		var pm := PackedVector3Array()
		var pj := PackedVector3Array()
		var wm := 0.0
		var wj := 0.0
		for f in 241:
			var s := f / 240.0
			var awa := lerpf(30.0, -30.0, s) * d2r if run == "tack" \
				else Frames.wrap_pi(lerpf(150.0, 210.0, s) * d2r)
			var dt := 1.0 / 60.0
			# sails.md §5.5 motion toward the target at the wm7 rates (main in 0.55 / out 0.75, jib 0.65 / 0.95)
			var tm := (-5.0 if run == "tack" else -70.0) * d2r * Frames.sgn(awa)
			var tj := -20.0 * d2r * Frames.sgn(awa)
			bm = _sheet_step(bm, tm, awa, 0.55, 0.75, dt)
			bj = _sheet_step(bj, tj, awa, 0.65, 0.95, dt)
			var backed := Frames.sgn(bj) == Frames.sgn(awa) and absf(bj) > 0.02
			mn.advance(dt, 4.0, awa, false)
			jn.advance(dt, 4.0, awa, backed)
			mn.update(UP, 1.0, bm, 0.0, shiver(bm, awa), awa, 4.0)
			jn.update(UP, 1.0, bj, 0.0, shiver(bj, awa), awa, 4.0)
			if not pm.is_empty():
				wm = maxf(wm, max_move(pm, mn.mid()))
				wj = maxf(wj, max_move(pj, jn.mid()))
			pm = mn.mid().duplicate()
			pj = jn.mid().duplicate()
		t.ok(wm <= 0.15 and wj <= 0.15, "%s: largest move per frame main %.3f m, jib %.3f m (<= 0.05 Sa = 0.15)" % [run, wm, wj])


## sails.md §5.5: step = (|D| + 5 deg) dt rate, rate_in away from the wind line, rate_out toward it
static func _sheet_step(beta: float, target: float, awa: float, rate_in: float, rate_out: float, dt: float) -> float:
	var d := target - beta
	var rate := rate_in if (-awa - beta) * d <= 0.0 else rate_out
	var step := (absf(d) + 0.0872664626) * dt * rate
	return target if absf(d) <= step else beta + signf(d) * step


# ---- native against the reference ------------------------------------------------------------------------

func _native_vs_ref() -> void:
	t.begin("native = reference")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0.0
	var cases := 0
	var kinds := [[K.MAIN, M.BOOM, false], [K.HEADSAIL, M.LUFF, false], [K.HEADSAIL, M.LUFF, true],
		[K.ASYM, M.SPRIT, false], [K.SYM, M.POLE, false]]
	for g in [rect(), tri()]:
		for c in kinds:
			var ex := {"furling": c[2], "mast_step": Vector3(1.2, 0, 0.5), "boom_pivot": Vector3(0.2, 0, 1.0)}
			var a: Variant = mk("ref", c[0], c[1], ex, g)
			var b: Variant = mk("native", c[0], c[1], ex, g)
			for r in 40:
				var dt := rng.randf_range(0.0, 0.05)
				var aws := rng.randf_range(0.5, 9.0)
				var awa := rng.randf_range(-PI, PI)
				var backed := rng.randf() < 0.3
				a.advance(dt, aws, awa, backed)
				b.advance(dt, aws, awa, backed)
				var ph: int = [1, 2, 3, 4, 5][r % 5]
				var args := [ph, rng.randf(), rng.randf_range(-PI, PI), rng.randf_range(-0.6, 0.6), rng.randf(), awa, aws]
				a.update(args[0], args[1], args[2], args[3], args[4], args[5], args[6])
				b.update(args[0], args[1], args[2], args[3], args[4], args[5], args[6])
				worst = maxf(worst, max_move(a.positions(), b.positions()))
				worst = maxf(worst, max_move(a.normals(), b.normals()) * 0.01)
				cases += 1
	t.ok(worst < 1e-3, "%d random frames in every phase: native within %.7f m of the reference" % [cases, worst])


## The native buffer against Godot's own encoding of the same positions and normals.
func _vertex_bytes() -> void:
	t.begin("vertex buffer")
	var sh: Variant = mk("native", K.HEADSAIL, M.LUFF, {}, tri())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = sh.positions()
	arrays[Mesh.ARRAY_NORMAL] = sh.normals()
	var uv := PackedVector2Array()
	uv.resize(242)
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	t.ok(sh.attach_mesh(mesh.get_rid()), "attach to an uncompressed grid-order mesh")
	sh.update(UP, 1.0, -0.4, 0.0, 0.5, 0.6, 5.0)
	var mine: PackedByteArray = sh.vertex_bytes()
	arrays[Mesh.ARRAY_VERTEX] = sh.positions()
	arrays[Mesh.ARRAY_NORMAL] = sh.normals()
	var ref := ArrayMesh.new()
	ref.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var theirs: PackedByteArray = RenderingServer.mesh_get_surface(ref.get_rid(), 0)["vertex_data"]
	t.ok(mine.size() == theirs.size(), "same buffer size (%d bytes)" % mine.size())
	var pos_same := mine.slice(0, 12 * 242) == theirs.slice(0, 12 * 242)
	t.ok(pos_same, "positions byte for byte")
	var fmt := ref.surface_get_format(0)
	var noff := RenderingServer.mesh_surface_get_format_offset(fmt, 242, Mesh.ARRAY_NORMAL)
	var nst := RenderingServer.mesh_surface_get_format_normal_tangent_stride(fmt, 242)
	var dn := 0
	for k in 242:
		for c in 2:
			dn = maxi(dn, absi(mine.decode_u16(noff + nst * k + 2 * c) - theirs.decode_u16(noff + nst * k + 2 * c)))
	t.ok(dn <= 1, "normals as Godot encodes them (largest difference %d units)" % dn)
	var rs: Variant = mk("ref", K.HEADSAIL, M.LUFF, {}, tri())
	t.ok(rs.attach_mesh(mesh.get_rid()), "the reference attaches too")
	sh.set_phase(0.0)
	rs.set_phase(0.0)
	sh.update(UP, 1.0, -0.4, 0.0, 0.0, 0.6, 5.0)
	rs.update(UP, 1.0, -0.4, 0.0, 0.0, 0.6, 5.0)
	var rb: PackedByteArray = rs.vertex_bytes()
	var nb: PackedByteArray = sh.vertex_bytes()
	var dp := 0.0
	for k in 3 * 242:
		dp = maxf(dp, absf(rb.decode_float(4 * k) - nb.decode_float(4 * k)))
	t.ok(dp < 1e-4, "the reference writes the same layout (%.7f)" % dp)


# ---- the generated boats -------------------------------------------------------------------------------

func _boats() -> void:
	for id in ["wm7", "wm12"]:
		t.begin("%s sails in BoatView" % id)
		if not FileAccess.file_exists("res://generated/boats/%s.glb" % id):
			t.ok(false, "%s generated (run tests/run_boat_import_test.sh)" % id)
			continue
		var data := BoatClassData.load_class(id)
		var bv := BoatView.create(data.info, 0.5)
		var shaped := 0
		for sp in bv.sail_parts:
			var ok: bool = sp.shape != null and sp.arrays.is_empty() and sp.mesh != null \
				and sp.mesh.get_surface_count() == 1
			t.ok(ok, "%s: grid-order mesh, shape %s, written in place" % [sp.id,
				"native" if sp.shape is Object and (sp.shape as Object).get_class() == "SailShape" else "reference"])
			if not ok:
				continue
			shaped += 1
			if native:
				t.ok((sp.shape as Object).get_class() == "SailShape", "%s uses the native SailShape" % sp.id)
			var n: int = sp.rows * sp.cols
			t.ok(sp.mesh.surface_get_array_len(0) == 2 * n, "%s: 2 x %d x %d vertices" % [sp.id, sp.rows, sp.cols])
			t.ok(sp.node.transform == Transform3D.IDENTITY, "%s: node transform is the identity" % sp.id)
			var sm := sp.mesh.surface_get_material(0) as ShaderMaterial
			t.ok(sm != null and sm.shader == BoatView.SAIL_SHADER and sm.get_shader_parameter("albedo_color") is Color,
				"%s: on the sail shader with the slot's colour" % sp.id)
			var port := Frames.body_to_model(Vector3(0, 1, 0))
			if sp.type != "spinnaker_asym" and sp.type != "spinnaker_sym":
				sp.shape.update(UP, 1.0, 0.0, 0.0, 0.0, 0.0, 5.0)
				var worst := 1.0
				var nr: PackedVector3Array = sp.shape.normals()
				for k in n:
					worst = minf(worst, nr[k].dot(port))
				t.ok(worst > 0.99, "%s: rest pose port normals dot(N, +y) > 0.99 (%.4f)" % [sp.id, worst])
			# the uv sets follow the grid (uv1 = (j / (cols - 1), 1 - i / (rows - 1)))
			var uv2: PackedVector2Array = sp.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
			var uv_ok := true
			for i in sp.rows:
				for j in sp.cols:
					var e := Vector2(float(j) / (sp.cols - 1), 1.0 - float(i) / (sp.rows - 1))
					uv_ok = uv_ok and uv2[i * sp.cols + j].distance_to(e) < 2e-3
			t.ok(uv_ok, "%s: uv1 in grid order" % sp.id)
			_cloth(id, sp, sm, data.info.loa)
			if sp.type == "spinnaker_asym":
				_asym_leeward(sp)
			if sp.type == "jib" or sp.type == "genoa" or sp.type == "code_zero":
				var kap: float = sp.shape.frame()["kappa"]
				var sa: float = sp.shape.frame()["sa"]
				sp.shape.update(PREPARE_HOIST, 0.0, 0.0, 0.0, 0.0, 0.5, 5.0)
				var above := -INF
				for p in sp.shape.local_shape():
					above = maxf(above, p.y)
				t.ok(above <= 0.03 + sa * kap + 1e-4, "%s: flaked on deck at p = 0 (%.3f m)" % [sp.id, above])
		t.ok(shaped == bv.sail_parts.size() and shaped >= 3, "%s: all %d sails shaped" % [id, shaped])
		var names := []
		for u in BoatView.SAIL_SHADER.get_shader_uniform_list():
			names.append(u["name"])
		t.ok(names.has("backlight") and names.has("albedo_tex") and BoatView.SAIL_SHADER.code.contains("void light()"),
			"sail shader parses, with the back-light in its light function")
		t.ok(names.has("cloth_chord") and names.has("cloth_style") and names.has("shadow_push")
			and BoatView.SAIL_SHADER.code.contains("IN_SHADOW_PASS"),
			"sail shader: cloth uniforms, and the shadow pass pushes the sail off itself (water_render.md §4.6)")
		var mats := {}
		for sp in bv.sail_parts:
			if sp.mesh:
				mats[sp.mesh.surface_get_material(0)] = true
		t.ok(mats.size() == bv.sail_parts.size(), "%s: one cloth material per sail (%d)" % [id, mats.size()])
		bv.free()


## §11.1 the cloth of a generated sail: style and kind by sail type and boat size, the flat plan and its
## corners, row chords, battens on the main, tell-tales on the jib, a material of its own.
func _cloth(id: String, sp: BoatView.SailPart, sm: ShaderMaterial, loa: float) -> void:
	if sm == null:
		return
	var kite := sp.type.begins_with("spinnaker")
	var style_want := 2 if kite else (1 if sp.type == "code_zero" or loa >= 10.0 else 0)
	var kind_want := 0 if sp.type == "main" else (2 if kite else 1)
	t.ok(int(sm.get_shader_parameter("cloth_style")) == style_want and int(sm.get_shader_parameter("cloth_kind")) == kind_want,
		"%s: cloth %s, kind %d" % [sp.id, ["woven, cross-cut", "laminate, tri-radial", "nylon, tri-radial"][style_want], kind_want])
	var shear: Vector2 = sm.get_shader_parameter("cloth_shear")
	var clew: Vector2 = sm.get_shader_parameter("cloth_clew")
	var head: Vector2 = sm.get_shader_parameter("cloth_head")
	var chord: PackedFloat32Array = sm.get_shader_parameter("cloth_chord")
	t.ok(absf(shear.length() - 1.0) < 1e-4 and shear.y > 0.4 and clew.x > 1.0 and head.y > 3.0 and absf(head.x) < 1e-6,
		"%s: flat plan (shear %.2f, clew %s, head %s)" % [sp.id, shear.x, clew, head])
	# the plan's height is the generator's uv0 height (the mean row spacing summed): close to the tack-head line
	var d_rest := sp.tack.distance_to(sp.head)
	t.ok(head.y >= 0.85 * d_rest and head.y < 1.1 * d_rest, "%s: plan luff %.2f m, tack to head %.2f m" % [sp.id, head.y, d_rest])
	t.ok(chord.size() == 48 and chord[0] > 1.0 and int(sm.get_shader_parameter("cloth_rows")) == mini(sp.rows, 48),
		"%s: %d row chords, foot %.2f m" % [sp.id, sp.rows, chord[0]])
	t.ok((int(sm.get_shader_parameter("cloth_battens")) > 0) == (sp.type == "main"), "%s: batten pockets on the main only" % sp.id)
	t.ok((int(sm.get_shader_parameter("cloth_telltales")) > 0) == (sp.type == "jib" or sp.type == "genoa"),
		"%s: tell-tales on the jib only" % sp.id)
	t.ok(sm != BoatView._sail_mats.get(sm, null) and sm.shader == BoatView.SAIL_SHADER, "%s: a cloth material of its own" % sp.id)


## §12 test 8 on the generated kite: every inner vertex to leeward of the vertical plane through its luff.
func _asym_leeward(sp: BoatView.SailPart) -> void:
	var up := Vector3(0, 1, 0)
	for deg in [60.0, -60.0, 120.0, -120.0, 170.0, -170.0]:
		var awa := deg_to_rad(deg)
		var beta := -Frames.sgn(awa) * deg_to_rad(absf(deg) - 25.0)
		var gamma := -Frames.sgn(awa) * 0.3
		sp.shape.update(UP, 1.0, beta, gamma, 0.0, awa, 5.0)
		var m: PackedVector3Array = sp.shape.mid()
		var tk := m[0]
		var hd := m[(sp.rows - 1) * sp.cols]
		var pn := (hd - tk).cross(up).normalized()
		var fwd := Frames.body_to_model(Vector3(1, 0, 0))
		var port := Frames.body_to_model(Vector3(0, 1, 0))
		var downwind := -(fwd * cos(awa) - port * sin(awa))
		var s := signf(downwind.dot(pn))
		var bad := 0
		for i in range(1, sp.rows - 1):
			for j in range(1, sp.cols - 1):
				# the plane through the row's own luff point (the luff is cut with a curve)
				if (m[i * sp.cols + j] - m[i * sp.cols]).dot(pn) * s <= 0.0:
					bad += 1
		t.ok(bad == 0, "%s awa %+.0f deg, beta %+.0f deg: belly to leeward of the luff (%d vertices not)" % [sp.id, deg,
			rad_to_deg(beta), bad])


## §11 update rate by distance and the frustum.
func _rate_by_distance() -> void:
	t.begin("update rate by distance")
	if not FileAccess.file_exists("res://generated/boats/wm7.glb"):
		return
	var data := BoatClassData.load_class("wm7")
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.far = 5000.0
	cam.current = true
	await process_frame
	var sv := SimSource.SailsView.new()
	sv.awa = 0.6
	sv.aws = 5.0
	for i in data.info.sails.size():
		var st := SimSource.SailState.new()
		st.phase = UP if i < 2 else 0
		st.beta = -0.3
		sv.sails.append(st)
		sv.out.append(SimSource.SailOutput.new())
	for c in [[100.0, 60], [500.0, 15], [1500.0, 4], [-300.0, 0]]:
		var bv := BoatView.create(data.info, 0.5)
		root.add_child(bv)
		# the camera looks north (-Z); the boat ahead at the distance, or behind it
		bv.global_position = Vector3(0, 0, -float(c[0]))
		var phi0: float = bv.sail_parts[0].shape.get_phase()
		for f in 60:
			bv.apply_sails(sv, sv, 1.0, 1.0 / 60.0)
		var n: int = bv.sail_parts[0].updates
		t.ok(absi(n - int(c[1])) <= 1, "main at %.0f m: %d updates in 1 s (%d)" % [c[0], n, c[1]])
		t.ok(absf(bv.sail_parts[0].shape.get_phase() - phi0) > 0.1, "flutter phase runs on at %.0f m" % c[0])
		bv.free()
	cam.free()


## Cost per sail update (shape, placement, layers, buffer write), native and reference.
func _perf() -> void:
	t.begin("cost")
	if not FileAccess.file_exists("res://generated/boats/wm7.glb"):
		return
	var data := BoatClassData.load_class("wm7")
	var impls := [false, true] if native else [true]
	for reference in impls:
		var bv := BoatView.create(data.info, 0.5, reference)
		var line := ""
		var total := 0.0
		for sp in bv.sail_parts:
			var reps := 2000 if not reference else 50
			var t0 := Time.get_ticks_usec()
			for r in reps:
				sp.shape.advance(1.0 / 60.0, 5.0, 0.6, false)
				sp.shape.update(UP, 1.0, -0.4, 0.1, 0.3, 0.6, 5.0)
				sp.shape.write_mesh()
			var us := float(Time.get_ticks_usec() - t0) / reps
			total += us
			line += "%s %dx%d %.1f us; " % [sp.id, sp.rows, sp.cols, us]
		print("  %s: %s all sails %.1f us per boat, 40 boats %.2f ms per frame" % [
			"reference (GDScript)" if reference else "native", line, total, total * 40.0 / 1000.0])
		if not reference:
			t.ok(total < 200.0, "native: the three sails of a wm7 cost %.1f us per frame (< 200)" % total)
		bv.free()
