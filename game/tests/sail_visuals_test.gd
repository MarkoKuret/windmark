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
	_set_params()
	_boats()
	_clearance()
	_reach_clew()
	_sheet_clear()
	_tack_on_sprit()
	_clew_on_sheet()
	_loft_sections()
	_parity()
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
		K.HEADSAIL: {"fill_gain": 0.75, "fill_curve": 1.2, "flutter_amp": 0.07, "twist_top": 0.175},
		K.ASYM: {"fill_gain": 1.0, "fill_curve": 1.0, "flutter_amp": 1.0, "twist_top": 0.45, "camber": 0.27,
			"tack_line_max": 0.04},
		K.SYM: {"fill_gain": 1.5, "fill_curve": 1.5, "flutter_amp": 1.0, "twist_top": 0.0, "camber": 0.26},
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
	var cam := 0.135 * tanh(sqrt(0.4113 / 4.0) / 0.15)
	t.near(cam, 0.1313, 5e-4, "jib camber over chord m at beta -25 (formula)")
	t.ok(best_j == 4 and absf(best / 3.0 - cam * 0.4 * 0.6 * 1.6 / 0.3849002) < 1e-3,
		"grid belly largest at x = 0.4 next to the draft 0.42, toward port (%.4f Sa)" % (best / 3.0))
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
	var lbk: PackedVector3Array = jb.local_shape()
	t.ok(lbk[10].z > 0.0 and lbk[5 * 11 + 6].z - 0.6 * lbk[5 * 11 + 10].z < 0.0,
		"backed: clew pressed out, belly on the other side of the luff-clew line")

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
		# §6.3 at mid height (p_i = 1 - 0.55 (0.2 / 0.7)^2, q_i = 0.8): camber d = k_c F p_i, the chord shortened
		# to s = 1 / (1 + 8/3 d^2), the mid-chord vertex at sin(PI 0.5^q_i) of the camber
		var pm := 1.0 - 0.55 * pow(0.2 / 0.7, 2.0)
		var dd: float = 0.27 * c[1] * pm
		var sr := 1.0 / (1.0 + 8.0 / 3.0 * dd * dd)
		var disp := la[5 * 11 + 5].distance_to(Vector3(1.5 * sr, 4.5, 0.0))
		t.near(disp / (sr * 3.0 * sin(PI * pow(0.5, 0.8))) / (0.27 * pm), c[1], 0.01 * c[1], "aws %.3f m/s: F" % c[0])
		t.near(la[5 * 11 + 10].x, 3.0 * sr, 1e-4, "aws %.3f m/s: mid-height leech at %.3f of the flat chord" % [c[0], sr])

	_camber_tests(impl)

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

## Largest distance of row i from its luff-leech line over the chord (camber over chord) of a local shape.
static func row_camber(la: PackedVector3Array, i: int, cols: int) -> float:
	var p0 := la[i * cols]
	var p1 := la[i * cols + cols - 1]
	var ch := p1 - p0
	var c := ch.length()
	var worst := 0.0
	for j in cols:
		var v := la[i * cols + j] - p0
		worst = maxf(worst, (v - ch * (v.dot(ch) / (c * c))).length())
	return worst / c


## §12 test 17: camber over chord of the flying sails and the code zero.
func _camber_tests(impl: String) -> void:
	t.begin("%s: 17 camber" % impl)
	var d2r := PI / 180.0
	for kind in [K.ASYM, K.SYM]:
		var sh: Variant = mk(impl, kind, M.SPRIT if kind == K.ASYM else M.POLE)
		for c in [[90.0, 45.0], [150.0, 85.0]]:
			sh.update(UP, 1.0, -c[1] * d2r, 0.0, 0.0, c[0] * d2r, 6.0 * KNOT)
			var la: PackedVector3Array = sh.local_shape()
			var mid := row_camber(la, 5, 11)
			var foot := row_camber(la, 0, 11)
			var head := row_camber(la, 10, 11)
			var msg := "%s awa %.0f deg: camber %.3f at mid height, %.3f foot, %.3f head" % [
				"asym" if kind == K.ASYM else "sym", c[0], mid, foot, head]
			# the asymmetric shallower at the foot; the symmetric as deep at the foot as at mid height (§6.4)
			var foot_ok := foot < mid if kind == K.ASYM else foot >= 0.9 * mid
			t.ok(mid >= 0.20 and mid <= 0.30 and foot_ok and head < mid, msg)
			if impl == "ref":
				print("  " + msg)
	var cz: Variant = mk(impl, K.HEADSAIL, M.LUFF, {"fill_gain": 0.7, "fill_curve": 1.3, "flutter_amp": 0.08,
		"twist_top": 0.14, "camber": 0.12})
	var line := ""
	var ok := true
	for b in [25.0, 40.0, 60.0, 90.0]:
		cz.update(UP, 1.0, -b * d2r, 0.0, 0.0, 100.0 * d2r, 5.0)
		var foot := row_camber(cz.local_shape(), 0, 11)
		ok = ok and foot <= 0.12 and (b > 60.0 or foot >= 0.07)
		line += "%.0f deg %.3f; " % [b, foot]
	t.ok(ok, "code zero camber at beta %s(0.07 to 0.12, never above)" % line)
	if impl == "ref":
		print("  code zero camber at beta " + line)
	var jb: Variant = mk(impl, K.HEADSAIL, M.LUFF)
	jb.update(UP, 1.0, -60.0 * d2r, 0.0, 0.0, 100.0 * d2r, 5.0)
	var jc := row_camber(jb.local_shape(), 0, 11)
	t.ok(jc >= 0.08 and jc <= 0.135, "a jib eased to 60 deg: foot camber %.3f, at most k_j 0.135 (§6.2)" % jc)


func _native_vs_ref() -> void:
	t.begin("native = reference")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0.0
	var cases := 0
	var kinds := [[K.MAIN, M.BOOM, false], [K.HEADSAIL, M.LUFF, false], [K.HEADSAIL, M.LUFF, true],
		[K.ASYM, M.SPRIT, false], [K.SYM, M.POLE, false], [K.HEADSAIL, M.SPRIT, false, {"camber": 0.12}]]
	for g in [rect(), tri()]:
		for c in kinds:
			var ex := {"furling": c[2], "mast_step": Vector3(1.2, 0, 0.5), "boom_pivot": Vector3(0.2, 0, 1.0)}
			if c.size() > 3:
				ex.merge(c[3])
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
	# §7.4 on the generated wm7: the kite eased and pushed off the main and the jib, native against reference
	if not FileAccess.file_exists("res://generated/boats/wm7.glb"):
		return
	var data := BoatClassData.load_class("wm7")
	var bvs := [BoatView.create(data.info, 0.5), BoatView.create(data.info, 0.5, true)]
	var ki := int(data.sail_index["kite"])
	var ji := int(data.sail_index["jib"])
	var w2 := 0.0
	var we := 0.0
	var eased := 0
	var n2 := 0
	for twa_deg in [60, 100, 140, 180]:
		for side in [1.0, -1.0]:
			var tws := 12.0 * KNOT
			var aw := _apparent(data, ki, tws, deg_to_rad(float(twa_deg)), side)
			var sv := _sails_view(data, aw.x, aw.y, tws, ki, ji, [0.85, 1.2])
			var kp := []
			for bv in bvs:
				bv.apply_sails(sv, sv, 1.0, 1.0 / 60.0)
				for sp in bv.sail_parts:
					if sp.index == ki:
						kp.append(sp.shape)
			w2 = maxf(w2, max_move(kp[0].positions(), kp[1].positions()))
			we = maxf(we, absf(kp[0].get_ease() - kp[1].get_ease()))
			eased += 1 if kp[0].get_ease() > 0.01 else 0
			n2 += 1
	# single precision against double: where a vertex is pushed round the end of an obstacle's section the push
	# direction turns fast, so a few millimetres (still well inside the generator parity's 10 mm)
	t.ok(w2 < 5e-3 and we < 1e-3 and eased > 0, "wm7 kite off the main and jib, %d cases (%d eased): native within %.7f m (ease %.7f rad) of the reference" % [
		n2, eased, w2, we])
	for bv in bvs:
		bv.free()


## §12 test 26: the kite set parameters (§4.1). The defaults given as keys draw exactly what no keys draw; every key
## changes the drawn kite; native against reference with every key away from its default over random drivers.
const SET_ASYM := {"depth_peak_h": 0.35, "depth_foot": 0.9, "depth_head": 0.5, "draft_low": 0.45, "draft_head": 0.58,
	"draft_from_h": 0.5, "belly_aft": 0.6, "belly_up": 0.4, "twist_exp": 2.0, "twist_awa_lo": 1.13,
	"twist_awa_hi": 2.2, "twist_run": 0.5, "foot_sag": 0.1, "foot_sag_h": 0.3, "girth_foot": 0.95, "girth_mid": 1.04,
	"girth_head": 0.97, "luff_curl": 0.15, "leech_curl": -0.1, "head_drop": 0.02, "clew_lift": 0.03,
	"clew_out": -0.02, "clew_h": 0.35, "forward": 0.05, "tack_rise": 0.03, "stay_clear": 0.3, "stay_width": 0.5,
	"stay_head": 0.25, "stay_luff": 0.45, "stay_leech": 0.25}


## the rectangle of §12 with its luff leaning aft (2 m over its 9 m), as a kite's does
static func rect_lean() -> PackedVector3Array:
	var g := PackedVector3Array()
	for i in 11:
		for j in 11:
			g.append(Vector3(-2.0 * i / 10.0 - 3.0 * j / 10.0, 0.0, 9.0 * i / 10.0))
	return g


## the synthetic kite of test 26 (the leaning rectangle): on a sprit with a sheet lead (asymmetric), or on a pole
## with a forestay (symmetric)
func _set_kite(impl: String, kind: int, kset: Dictionary) -> Variant:
	var ex := {"mast_step": Vector3(1.2, 0, 0.5)}
	if kind == K.ASYM:
		ex["sheet_lead"] = Vector3(-6.0, -1.0, 0.5)
	else:
		ex.merge({"clearance": 0.3, "forestay_tack": Vector3(-1.0, 0, 0.5), "hounds": Vector3(-1.2, 0, 8.0)})
	ex.merge(kset, true)
	return mk(impl, kind, M.SPRIT if kind == K.ASYM else M.POLE, ex, rect_lean())


## the kite of test 26 placed at the apparent wind angle awa (rad, > 0), the sail 0.45 awa to leeward and the pole
## 0.3 rad to windward (the core's signs)
static func _set_place(sh: Variant, awa: float) -> PackedVector3Array:
	sh.advance(0.0, 6.0, awa, false)
	sh.set_twist_side(-1.0)
	sh.update(UP, 1.0, -0.45 * awa, -0.3, 0.0, awa, 6.0)
	return sh.mid()


func _set_params() -> void:
	t.begin("26 kite set parameters")
	for impl in (["ref", "native"] if native else ["ref"]):
		for kind in [K.ASYM, K.SYM]:
			var type := "spinnaker_asym" if kind == K.ASYM else "spinnaker_sym"
			var worst := 0.0
			for awa_deg in [80.0, 120.0, 165.0]:
				var a := _set_place(_set_kite(impl, kind, {}), deg_to_rad(awa_deg))
				var b := _set_place(_set_kite(impl, kind, KiteSet.defaults(type)), deg_to_rad(awa_deg))
				worst = maxf(worst, max_move(a, b))
			t.ok(worst == 0.0, "%s %s: the defaults given as keys draw the same kite as no keys (%.9f m)" % [impl, type, worst])
			var dead := []
			# a base where every key acts: some foot sag, the draft moving up the sail, some twist and clew lift
			var base := {"foot_sag": 0.2, "draft_head": 0.6, "twist_top": 0.1, "clew_lift": 0.05}
			for row in KiteSet.PARAMS:
				var key: String = row[0]
				if (row[7] == "asym" and kind != K.ASYM) or (row[7] == "pole" and kind != K.SYM) or row[7] == "loft":
					continue
				var d: Dictionary = KiteSet.defaults(type)
				d.merge(base, true)
				var v: float = d[key]
				var span: float = row[5] - row[4]
				var nv := v + 0.15 * span if v + 0.15 * span <= row[5] else v - 0.15 * span
				var moved := 0.0
				for awa_deg in [80.0, 120.0, 165.0]:
					var a := _set_place(_set_kite(impl, kind, base), deg_to_rad(awa_deg))
					var bk := base.duplicate()
					bk[key] = nv
					var b := _set_place(_set_kite(impl, kind, bk), deg_to_rad(awa_deg))
					moved = maxf(moved, max_move(a, b))
				if moved < 1e-3:
					dead.append(key)
			t.ok(dead.is_empty(), "%s %s: every set parameter moves the kite (none: %s)" % [impl, type, ", ".join(dead)])
	if not native:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 26
	var worst := 0.0
	var cases := 0
	for kind in [K.ASYM, K.SYM]:
		var a: Variant = _set_kite("ref", kind, SET_ASYM)
		var b: Variant = _set_kite("native", kind, SET_ASYM)
		for r in 60:
			var dt := rng.randf_range(0.0, 0.05)
			var aws := rng.randf_range(0.5, 9.0)
			var awa := rng.randf_range(-PI, PI)
			a.advance(dt, aws, awa, false)
			b.advance(dt, aws, awa, false)
			var ph: int = [1, 2, 3, 4, 5][r % 5]
			var args := [ph, rng.randf(), -0.6 * awa, rng.randf_range(-0.6, 0.6), rng.randf(), awa, aws]
			a.update(args[0], args[1], args[2], args[3], args[4], args[5], args[6])
			b.update(args[0], args[1], args[2], args[3], args[4], args[5], args[6])
			worst = maxf(worst, max_move(a.positions(), b.positions()))
			cases += 1
	t.ok(worst < 1e-3, "%d random frames, every key away from its default: native within %.7f m of the reference" % [
		cases, worst])
	_loft_params()


## §6.5 a synthetic lofted kite on the leaning rectangle of test 26: two "measured" shapes (AWA 64 and 124 deg),
## each row a circular-ish belly of its own camber with the chord drawn in to keep the cloth, the run's twisted
static func synth_loft() -> Dictionary:
	var g := rect_lean()
	var tk := g[0]
	var lh := (g[110] - tk).normalized()
	var nh := Vector3(0, 1, 0)
	var ah := lh.cross(nh).normalized()
	var awa := PackedFloat32Array([deg_to_rad(64.0), deg_to_rad(124.0)])
	var pts := PackedVector3Array()
	for m in 2:
		var cam := 0.22 if m == 0 else 0.3
		for i in 11:
			var h := i / 10.0
			var tw := (0.05 if m == 0 else 0.4) * h
			for j in 11:
				var uc := j / 10.0
				var d := g[i * 11 + j] - tk
				var d0 := g[i * 11] - tk
				var a := d.dot(ah)
				var a0 := d0.dot(ah)
				var sh := 1.0 / (1.0 + 8.0 / 3.0 * cam * cam)
				var ar := a0 + (a - a0) * sh
				var nn := cam * sh * 3.0 * sin(PI * uc) * (1.0 - 0.6 * h)
				# the twist: the row turned about the luff toward the belly's side
				var ra := ar - a0
				pts.append(Vector3(a0 + ra * cos(tw) - nn * sin(tw), d.dot(lh), ra * sin(tw) + nn * cos(tw)))
	return {"model": "loft", "loft_awa": awa, "loft_shapes": pts}


func _loft_kite(impl: String, extra: Dictionary = {}) -> Variant:
	var ex := synth_loft()
	ex.merge(extra, true)
	return _set_kite(impl, K.ASYM, ex)


## §6.5, §12 test 26: the lofted model's keys (`loft_depth`, `loft_trim`) move the kite; native against reference
## over random drivers in every phase, with the main as an obstacle.
func _loft_params() -> void:
	t.begin("26 kite set parameters: the lofted model")
	for impl in (["ref", "native"] if native else ["ref"]):
		var k0: Variant = _loft_kite(impl)
		t.ok(k0.is_loft(), "%s: the synthetic kite is lofted" % impl)
		for key in ["loft_depth", "loft_trim"]:
			var moved := 0.0
			for awa_deg in [70.0, 100.0, 140.0]:
				var a := _set_place(_loft_kite(impl), deg_to_rad(awa_deg))
				var b := _set_place(_loft_kite(impl, {key: 0.8 if key == "loft_depth" else 0.1}), deg_to_rad(awa_deg))
				moved = maxf(moved, max_move(a, b))
			t.ok(moved > 1e-2, "%s: %s moves the kite (%.3f m)" % [impl, key, moved])
		# the tack and the head stay on their fittings
		var kk: Variant = _loft_kite(impl)
		kk.update(UP, 1.0, -0.8, 0.0, 0.0, deg_to_rad(100.0), 6.0)
		var m: PackedVector3Array = kk.mid()
		var g := rect_lean()
		t.ok(m[0].distance_to(g[0]) < 1e-4 and m[110].distance_to(g[110]) < 1e-3,
			"%s: the tack and the head stay where they are hoisted" % impl)
	if not native:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 65
	var worst := 0.0
	var cases := 0
	var a: Variant = _loft_kite("ref", {"loft_depth": 1.1, "loft_trim": 0.05, "clearance": 0.3,
		"mast_head": Vector3(1.2, 0, 9.5)})
	var b: Variant = _loft_kite("native", {"loft_depth": 1.1, "loft_trim": 0.05, "clearance": 0.3,
		"mast_head": Vector3(1.2, 0, 9.5)})
	for r in 80:
		var dt := rng.randf_range(0.0, 0.05)
		var aws := rng.randf_range(0.5, 9.0)
		var awa := rng.randf_range(-PI, PI)
		a.advance(dt, aws, awa, false)
		b.advance(dt, aws, awa, false)
		var ph: int = [1, 2, 3, 4, 5][r % 5]
		var args := [ph, rng.randf(), -0.6 * awa, rng.randf_range(-0.6, 0.6), rng.randf(), awa, aws]
		a.update(args[0], args[1], args[2], args[3], args[4], args[5], args[6])
		b.update(args[0], args[1], args[2], args[3], args[4], args[5], args[6])
		worst = maxf(worst, max_move(a.positions(), b.positions()))
		cases += 1
	t.ok(worst < 1e-3, "lofted: %d random frames in every phase, native within %.7f m of the reference" % [
		cases, worst])


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
			# flying sails are left out: at beta = 0 they lie in the mast's plane and wrap round it (§7.4)
			if not BoatView.is_flying(sp.type):
				sp.shape.update(UP, 1.0, 0.0, 0.0, 0.0, 0.0, 5.0)
				var worst := 1.0
				var nr: PackedVector3Array = sp.shape.normals()
				for k in n:
					worst = minf(worst, nr[k].dot(port))
				# the head row is turned by twist_top toward leeward (10 deg on the jib, §4)
				t.ok(worst > 0.98, "%s: rest pose port normals dot(N, +y) > 0.98 (%.4f)" % [sp.id, worst])
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
		if sp.shape.is_loft():
			# §6.5 a lofted kite's sections are convex: every inner vertex lies on the downwind side of the vertical
			# plane through its row's chord (the luff curl and the clew hook stay on the belly's side); in its
			# working range, the sheet at most sheet_max (64 deg; test 9 takes it round the bow)
			beta = -Frames.sgn(awa) * minf(deg_to_rad(absf(deg) - 25.0), deg_to_rad(64.0))
			sp.shape.update(UP, 1.0, beta, gamma, 0.0, awa, 5.0)
			m = sp.shape.mid()
			for i in range(1, sp.rows - 1):
				var c0 := m[i * sp.cols]
				var ch := m[i * sp.cols + sp.cols - 1] - c0
				var nc := ch.cross(up).normalized()
				var sc := signf(downwind.dot(nc))
				for j in range(1, sp.cols - 1):
					if (m[i * sp.cols + j] - c0).dot(nc) * sc <= 0.0:
						bad += 1
			t.ok(bad == 0, "%s awa %+.0f deg, beta %+.0f deg: lofted belly to leeward of each row's chord (%d vertices not)" % [
				sp.id, deg, rad_to_deg(beta), bad])
			continue
		for i in range(1, sp.rows - 1):
			for j in range(1, sp.cols - 1):
				# the plane through the row's own luff point (the luff is cut with a curve)
				if (m[i * sp.cols + j] - m[i * sp.cols]).dot(pn) * s <= 0.0:
					bad += 1
		t.ok(bad == 0, "%s awa %+.0f deg, beta %+.0f deg: belly to leeward of the luff (%d vertices not)" % [sp.id, deg,
			rad_to_deg(beta), bad])


# ---- §12 test 18: clearance of the flying sails -------------------------------------------------------------

const CELL := 0.6


static func _cell(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))


## The triangles of a grid-order mid-surface, three points each (collapsed ones left out).
static func grid_tris(m: PackedVector3Array, rows: int, cols: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in rows - 1:
		for j in cols - 1:
			var a := m[i * cols + j]
			var b := m[i * cols + j + 1]
			var c := m[(i + 1) * cols + j]
			var d := m[(i + 1) * cols + j + 1]
			if (b - a).cross(c - a).length_squared() > 1e-10:
				out.append_array([a, b, c])
			if (b - c).cross(d - c).length_squared() > 1e-10:
				out.append_array([c, b, d])
	return out


## The edges of the same triangulation, two points each.
static func grid_edges(m: PackedVector3Array, rows: int, cols: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in rows:
		for j in cols:
			var k := i * cols + j
			if j + 1 < cols:
				out.append_array([m[k], m[k + 1]])
			if i + 1 < rows:
				out.append_array([m[k], m[k + cols]])
			if i + 1 < rows and j + 1 < cols:
				out.append_array([m[k + 1], m[k + cols]])
	return out


## cell -> triangle indices, each triangle in every cell its box touches
static func tri_hash(tris: PackedVector3Array) -> Dictionary:
	var h := {}
	for ti in tris.size() / 3:
		var a := tris[3 * ti]
		var b := tris[3 * ti + 1]
		var c := tris[3 * ti + 2]
		var c0 := _cell(a.min(b).min(c))
		var c1 := _cell(a.max(b).max(c))
		for x in range(c0.x, c1.x + 1):
			for y in range(c0.y, c1.y + 1):
				for z in range(c0.z, c1.z + 1):
					var key := Vector3i(x, y, z)
					if not h.has(key):
						h[key] = []
					h[key].append(ti)
	return h


## Closest point of triangle abc to p.
static func closest_on_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var den := 1.0 / (va + vb + vc)
	return a + ab * (vb * den) + ac * (vc * den)


## Distance of p from the hashed triangles, INF beyond one cell.
static func dist_to(p: Vector3, tris: PackedVector3Array, h: Dictionary) -> float:
	var best := INF
	var c := _cell(p)
	var seen := {}
	for x in range(c.x - 1, c.x + 2):
		for y in range(c.y - 1, c.y + 2):
			for z in range(c.z - 1, c.z + 2):
				for ti in h.get(Vector3i(x, y, z), []):
					if seen.has(ti):
						continue
					seen[ti] = true
					var q := closest_on_tri(p, tris[3 * ti], tris[3 * ti + 1], tris[3 * ti + 2])
					best = minf(best, p.distance_to(q))
	return best


## Number of edges crossing the hashed triangles.
static func crossings(edges: PackedVector3Array, tris: PackedVector3Array, h: Dictionary) -> int:
	var n := 0
	for e in edges.size() / 2:
		var p := edges[2 * e]
		var q := edges[2 * e + 1]
		var c0 := _cell(p.min(q))
		var c1 := _cell(p.max(q))
		var hit := false
		for x in range(c0.x, c1.x + 1):
			for y in range(c0.y, c1.y + 1):
				for z in range(c0.z, c1.z + 1):
					for ti in h.get(Vector3i(x, y, z), []):
						if not hit and Geometry3D.segment_intersects_triangle(p, q, tris[3 * ti], tris[3 * ti + 1],
								tris[3 * ti + 2]) != null:
							hit = true
		if hit:
			n += 1
	return n


## §12 test 18: every flying sail of wm7 and wm12 over TWA, TWS, both tacks, trims, the jib up and down, placed by
## BoatView as in the game: no crossing with the main, the jib or the mast, and at least 0.9 of the margin clear.
func _clearance() -> void:
	for id in ["wm7", "wm12"]:
		if not FileAccess.file_exists("res://generated/boats/%s.glb" % id):
			continue
		var data := BoatClassData.load_class(id)
		var bv := BoatView.create(data.info, 0.5)
		var c: float = 0.042 * data.info.loa
		var main_i: int = data.info.main_sail
		var jib_i := int(data.sail_index.get("jib", -1))
		var parts := {}
		for sp in bv.sail_parts:
			parts[sp.index] = sp
		var ms: Vector3 = bv._mast_step
		var mh: Vector3 = bv._mast_head
		for fi in data.info.front_sails:
			var fp: BoatView.SailPart = parts[fi]
			if not (fp.type.begins_with("spinnaker") or fp.type == "code_zero"):
				continue
			t.begin("18 clearance: %s %s" % [id, fp.id])
			var t0 := Time.get_ticks_msec()
			var cfg: Dictionary = data.configs[fi]
			var r := {"worst": INF, "at": "", "bad": 0, "cross": 0, "n": 0, "first": "", "ease": 0.0}
			for twa_deg in range(60, 181, 20):
				for kn in [6.0, 12.0, 22.0]:
					for side in [1.0, -1.0]:
						var tws: float = kn * KNOT
						var twa := deg_to_rad(float(twa_deg))
						var ap := _apparent(data, fi, tws, twa, side)
						var awa := ap.x
						for tr in [[1.0, 1.0], [0.85, 1.0], [1.2, 1.0], [0.85, 1.2]]:
							for jib_up in ([false, true] if jib_i >= 0 else [false]):
								var sv := _sails_view(data, awa, ap.y, tws, fi, jib_i if jib_up else -1, tr)
								# a steady state: the eased twist side (§7.1) settled on this tack
								for k in (20 if tr == [1.0, 1.0] and not jib_up else 1):
									bv.apply_sails(sv, sv, 1.0, 0.1 if k < 19 else 1.0 / 60.0)
								r["ease"] = maxf(r["ease"], fp.shape.get_ease())
								var what := "twa %d tws %.0f %s trim %.2f/%.2f jib %s" % [twa_deg, kn,
									"stbd" if side > 0 else "port", tr[0], tr[1], "up" if jib_up else "down"]
								var obs: Array = [parts[main_i]]
								if jib_up:
									obs.append(parts[jib_i])
								_clear_check(fp, obs, ms, mh, c, r, what)
			_clear_sweep(data, bv, fp, jib_i)
			t.ok(r["cross"] == 0, "%s %s: %d configs, %d crossings with the main, jib or mast%s" % [id, fp.id, r["n"],
				r["cross"], "" if r["first"] == "" else " (first: %s)" % r["first"]])
			t.ok(r["bad"] == 0 and r["worst"] >= 0.9 * c, "%s %s: smallest clearance %.3f m (margin %.2f m) at %s; %d vertices inside 0.9 of the faded margin" % [
				id, fp.id, r["worst"], c, r["at"], r["bad"]])
			print("  %s %s: %d configs, smallest clearance %.3f m (margin %.2f m) at %s; %d crossings, %d vertices inside 0.9 margin; largest ease %.1f deg; %d ms" % [
				id, fp.id, r["n"], r["worst"], c, r["at"], r["cross"], r["bad"], rad_to_deg(r["ease"]), Time.get_ticks_msec() - t0])
		bv.free()


## §12 test 20: on a reach (AWA 70 to 90 deg) at the core's optimum the asymmetric's clew stays where a real
## reaching kite's does: at most REACH_FWD * LOA forward of the mast (abreast of it or aft) and at most REACH_OUT * LOA
## outboard of the widest beam.
const REACH_OUT := 0.3
## §6.5 a lofted kite is cleared of the main by turning it out whole (the hinge model bends its leech off the main
## instead), so on the closest reaches (the core sheeting it inside the main) its clew flies a little further out
const REACH_OUT_LOFT := 0.32
const REACH_FWD := 0.05


func _reach_clew() -> void:
	for id in ["wm7", "wm12"]:
		if not FileAccess.file_exists("res://generated/boats/%s.glb" % id):
			continue
		var data := BoatClassData.load_class(id)
		var bv := BoatView.create(data.info, 0.5)
		var jib_i := int(data.sail_index.get("jib", -1))
		var parts := {}
		for sp in bv.sail_parts:
			parts[sp.index] = sp
		var mast_x: float = bv._mast_step.z
		var half: float = 0.5 * data.info.beam_max
		for fi in data.info.front_sails:
			var fp: BoatView.SailPart = parts[fi]
			if fp.type != "spinnaker_asym":
				continue
			t.begin("20 reach clew: %s %s" % [id, fp.id])
			var fwd := -INF
			var out := -INF
			var ease := 0.0
			var n := 0
			var at := ""
			for kn in [6.0, 12.0, 22.0]:
				for twa_deg in range(50, 131, 2):
					for side in [1.0, -1.0]:
						var tws: float = kn * KNOT
						var ap := _apparent(data, fi, tws, deg_to_rad(float(twa_deg)), side)
						if absf(ap.x) < deg_to_rad(70.0) or absf(ap.x) > deg_to_rad(90.0):
							continue
						for jib_up in ([false, true] if jib_i >= 0 else [false]):
							var sv := _sails_view(data, ap.x, ap.y, tws, fi, jib_i if jib_up else -1, [1.0, 1.0])
							bv.apply_sails(sv, sv, 1.0, 1.0 / 60.0)
							var cl: Vector3 = fp.shape.mid()[fp.cols - 1]
							n += 1
							ease = maxf(ease, fp.shape.get_ease())
							if cl.z - mast_x > fwd:
								fwd = cl.z - mast_x
								at = "awa %.0f tws %.0f" % [rad_to_deg(absf(ap.x)), kn]
							out = maxf(out, absf(cl.x) - half)
			var rout := REACH_OUT_LOFT if fp.shape.is_loft() else REACH_OUT
			var msg := "%s %s: %d reaching cases, clew at most %.2f m forward of the mast (<= %.2f, aft < 0, at %s), at most %.2f m outboard of the widest beam (<= %.2f), largest ease %.1f deg" % [
				id, fp.id, n, fwd, REACH_FWD * data.info.loa, at, out, rout * data.info.loa, rad_to_deg(ease)]
			t.ok(n > 0 and fwd <= REACH_FWD * data.info.loa and out <= rout * data.info.loa, msg)
			print("  " + msg)
		bv.free()


## §12 test 23: an asymmetric spinnaker's working sheet runs straight from its placed clew to the lead block and keeps
## half the margin off the main and the boom over configs and trims up to a let-fly main; the main's stop (§7.6) never
## eases the main past the core's angle; the stop is continuous.
func _sheet_clear() -> void:
	for id in ["wm7", "wm12"]:
		if not FileAccess.file_exists("res://generated/boats/%s.glb" % id):
			continue
		var data := BoatClassData.load_class(id)
		var main_i: int = data.info.main_sail
		for reference in ([false, true] if native else [true]):
			var bv := BoatView.create(data.info, 0.5, reference)
			var c: float = 0.042 * data.info.loa
			var parts := {}
			for sp in bv.sail_parts:
				parts[sp.index] = sp
			var mp: BoatView.SailPart = parts[main_i]
			for fi in data.info.front_sails:
				var fp: BoatView.SailPart = parts[fi]
				if fp.type != "spinnaker_asym":
					continue
				var impl := "reference" if reference else "native"
				t.begin("23 kite sheet: %s %s (%s)" % [id, fp.id, impl])
				var t0 := Time.get_ticks_msec()
				var worst_m := INF
				var worst_b := INF
				var at_m := ""
				var at_b := ""
				var over := 0
				var cross := 0
				var stop := 0.0
				var n := 0
				for twa_deg in range(60, 171, 10):
					for kn in ([6.0, 12.0, 22.0] if not reference else [12.0]):
						for side in [1.0, -1.0]:
							var tws: float = kn * KNOT
							var ap := _apparent(data, fi, tws, deg_to_rad(float(twa_deg)), side)
							for kt in [0.85, 1.0, 1.2]:
								for mt in [1.0, 1.15, 10.0]:
									var sv := _sails_view(data, ap.x, ap.y, tws, fi, -1, [kt, mt])
									for k in 3:
										bv.apply_sails(sv, sv, 1.0, 0.1)
									n += 1
									var core: float = sv.sails[main_i].beta
									if absf(mp.beta) > absf(core) + 1e-5:
										over += 1
									stop = maxf(stop, absf(core) - absf(mp.beta))
									var what := "twa %d tws %.0f %s kite %.2f main %s" % [twa_deg, kn,
										"stbd" if side > 0 else "port", kt, "let fly" if mt > 5.0 else "%.2f" % mt]
									var cl: Vector3 = fp.clew()
									var ld: Vector3 = fp.shape.working_lead(fp.beta)
									var mm: PackedVector3Array = mp.shape.mid()
									var mtris := grid_tris(mm, mp.rows, mp.cols)
									var mh := tri_hash(mtris)
									cross += crossings(PackedVector3Array([cl, ld]), mtris, mh)
									var dm := INF
									for q in 61:
										dm = minf(dm, dist_to(cl.lerp(ld, q / 60.0), mtris, mh))
									var be: Vector3 = bv._boom_pivot + (mp.stop_aft * mp.stop_span).rotated(bv._boom_axis, mp.beta)
									var pts := Geometry3D.get_closest_points_between_segments(cl, ld, bv._boom_pivot, be)
									var db: float = pts[0].distance_to(pts[1])
									if dm < worst_m:
										worst_m = dm
										at_m = what
									if db < worst_b:
										worst_b = db
										at_b = what
				t.ok(cross == 0 and worst_m >= 0.5 * c, "%s %s: %d cases, the straight sheet %d crossings, at least %.3f m off the main (>= %.3f) at %s" % [
					id, fp.id, n, cross, worst_m, 0.5 * c, at_m])
				t.ok(worst_b >= 0.5 * c, "%s %s: at least %.3f m off the boom (>= %.3f) at %s" % [id, fp.id, worst_b, 0.5 * c, at_b])
				t.ok(over == 0, "%s %s: the drawn main never past the core's angle (%d over); largest stop %.1f deg" % [
					id, fp.id, over, rad_to_deg(stop)])
				print("  %s %s (%s): %d cases, sheet off the main %.3f m, off the boom %.3f m, largest stop %.1f deg, %d ms" % [
					id, fp.id, impl, n, worst_m, worst_b, rad_to_deg(stop), Time.get_ticks_msec() - t0])
				if not reference:
					_stop_sweep(data, bv, fp, mp)
			bv.free()


## §12 test 24: an asymmetric spinnaker's tack stays on the sprit fitting (§7.5): over configs and trims, a hoist, a
## drop and a gybe round the bow, native and reference.
const TACK_TOL := 0.001


func _tack_on_sprit() -> void:
	for id in ["wm7", "wm12"]:
		if not FileAccess.file_exists("res://generated/boats/%s.glb" % id):
			continue
		var data := BoatClassData.load_class(id)
		var rig: Dictionary = data.info.physics.get("rig", {})
		if not rig.get("bowsprit_end") is Array:
			continue
		var end := Frames.body_to_model(BoatView._vec(rig["bowsprit_end"]))
		for reference in ([false, true] if native else [true]):
			var bv := BoatView.create(data.info, 0.5, reference)
			var parts := {}
			for sp in bv.sail_parts:
				parts[sp.index] = sp
			for fi in data.info.front_sails:
				var fp: BoatView.SailPart = parts[fi]
				if fp.type != "spinnaker_asym":
					continue
				var impl := "reference" if reference else "native"
				t.begin("24 tack on the sprit: %s %s (%s)" % [id, fp.id, impl])
				var worst := 0.0
				var at := ""
				var n := 0
				var tws := 12.0 * KNOT
				for twa_deg in range(60, 171, 20 if reference else 10):
					for side in [1.0, -1.0]:
						var ap := _apparent(data, fi, tws, deg_to_rad(float(twa_deg)), side)
						for kt in [0.6, 1.0, 1.3]:
							for mt in [1.0, 10.0]:
								var sv := _sails_view(data, ap.x, ap.y, tws, fi, -1, [kt, mt])
								bv.apply_sails(sv, sv, 1.0, 0.1)
								var d: float = fp.shape.mid()[0].distance_to(end)
								n += 1
								if d > worst:
									worst = d
									at = "twa %d %s kite %.2f" % [twa_deg, "stbd" if side > 0 else "port", kt]
				# hoist and drop at a reach, then a gybe round the bow (the kite's angle through +-180 deg)
				var ap2 := _apparent(data, fi, tws, deg_to_rad(110.0), 1.0)
				for ph in [SimSource.Phase.HOISTING, SimSource.Phase.DROPPING]:
					for f in 21:
						var sv := _sails_view(data, ap2.x, ap2.y, tws, fi, -1, [1.0, 1.0])
						sv.sails[fi].phase = ph
						sv.sails[fi].progress = f / 20.0
						bv.apply_sails(sv, sv, 1.0, 0.1)
						var d: float = fp.shape.mid()[0].distance_to(end)
						n += 1
						if d > worst:
							worst = d
							at = "%s %.2f" % ["hoist" if ph == SimSource.Phase.HOISTING else "drop", f / 20.0]
				for f in 41:
					var sv := _sails_view(data, ap2.x, ap2.y, tws, fi, -1, [1.0, 1.0])
					sv.sails[fi].beta = Frames.wrap_pi(deg_to_rad(-150.0) - deg_to_rad(60.0) * f / 40.0)
					bv.apply_sails(sv, sv, 1.0, 0.1)
					var d: float = fp.shape.mid()[0].distance_to(end)
					n += 1
					if d > worst:
						worst = d
						at = "gybe step %d" % f
				var msg := "%s %s (%s): %d cases, the tack at most %.4f m from the sprit end (<= %.3f) at %s" % [
					id, fp.id, impl, n, worst, TACK_TOL, at]
				t.ok(n > 0 and worst <= TACK_TOL, msg)
				print("  " + msg)
			bv.free()


## §12 test 25: an asymmetric spinnaker's sheet leaves the clew along the corner's bisector (§7.7), and the foot and
## the lower leech stay fair (no kink, no bulge), native and reference.
const CLEW_ANGLE_MAX := 12.0     # deg, sheet off the clew corner's bisector
const FAIR_STEP_MAX := 3.0       # deg, change of the signed turn from one edge vertex to the next
const FAIR_DEAD := 0.5           # deg, turns smaller than this have no sign
## §6.5 a lofted kite: its clew is shaped once, by the generator, for the nominal trim of each measured AWA (the
## hook and lift of §6.5), not every frame, so over the whole sweep of trims the sheet strays further off the
## bisector; its foot carries the clew hook, a little sharper than the hinge model's draw-in
const CLEW_ANGLE_MAX_LOFT := 50.0
const FAIR_STEP_MAX_LOFT := 4.0


func _clew_on_sheet() -> void:
	for id in ["wm7", "wm12"]:
		if not FileAccess.file_exists("res://generated/boats/%s.glb" % id):
			continue
		var data := BoatClassData.load_class(id)
		for reference in ([false, true] if native else [true]):
			var bv := BoatView.create(data.info, 0.5, reference)
			var parts := {}
			for sp in bv.sail_parts:
				parts[sp.index] = sp
			for fi in data.info.front_sails:
				var fp: BoatView.SailPart = parts[fi]
				if fp.type != "spinnaker_asym":
					continue
				var impl := "reference" if reference else "native"
				t.begin("25 clew on its sheet: %s %s (%s)" % [id, fp.id, impl])
				var worst := 0.0
				var at := ""
				var step := 0.0
				var at_step := ""
				var bulges := 0
				var at_bulge := ""
				var n := 0
				var tws := 12.0 * KNOT
				for awa_deg in range(60, 161, 10):
					for side in [1.0, -1.0]:
						for kt in [0.6, 0.85, 1.0, 1.2, 1.3]:
							for mt in [1.0, 10.0]:
								var sv := _sails_view(data, side * deg_to_rad(float(awa_deg)), tws, tws, fi, -1, [kt, mt])
								bv.apply_sails(sv, sv, 1.0, 0.1)
								var r := clew_check(fp, sv.sails[fi].beta)
								# fairness of the flying shape itself: placed again without the obstacles (the push of
								# §7.4 is test 18's)
								fp.shape.set_obstacles([])
								fp.shape.update(SimSource.Phase.UP, 1.0, fp.beta, fp.gamma, 0.0, sv.awa, sv.aws)
								var r2 := clew_check(fp, sv.sails[fi].beta)
								r[1] = r2[1]
								r[2] = r2[2]
								var what := "awa %d %s kite %.2f main %s" % [awa_deg, "stbd" if side > 0 else "port", kt,
										"let fly" if mt > 1.0 else "opt"]
								n += 1
								if r[0] > worst:
									worst = r[0]
									at = what
								if r[1] > step:
									step = r[1]
									at_step = what
								if r[2] > 1:
									bulges += 1
									if at_bulge == "":
										at_bulge = what
				var amax := CLEW_ANGLE_MAX_LOFT if fp.shape.is_loft() else CLEW_ANGLE_MAX
				var smax := FAIR_STEP_MAX_LOFT if fp.shape.is_loft() else FAIR_STEP_MAX
				var msg := "%s %s (%s): %d cases, the sheet at most %.1f deg off the clew's bisector (<= %.0f) at %s" % [
					id, fp.id, impl, n, worst, amax, at]
				t.ok(n > 0 and worst <= amax, msg)
				print("  " + msg)
				msg = "%s %s (%s): foot and lower leech turn step at most %.2f deg (<= %.0f) at %s, %d bulged%s" % [
					id, fp.id, impl, step, smax, at_step, bulges, (" (first " + at_bulge + ")") if bulges > 0 else ""]
				t.ok(step <= smax and bulges == 0, msg)
				print("  " + msg)
			bv.free()


## §12 test 25 on one placed flying sail: [the sheet's angle off the clew corner's bisector (deg), the largest change
## of the signed turn between neighbouring vertices of the foot and the lower leech (deg), the most sign changes of
## that turn on either edge]
static func clew_check(fp: BoatView.SailPart, beta: float) -> Array:
	var m: PackedVector3Array = fp.shape.mid()
	var cols := fp.cols
	var c := m[cols - 1]
	var f := (m[cols - 3] - c).normalized()
	var e := (m[2 * cols + cols - 1] - c).normalized()
	var b := (f + e).normalized()
	var lead: Vector3 = fp.shape.working_lead(beta)
	var s := (c - lead).normalized()
	var ang := rad_to_deg(acos(clampf(b.dot(s), -1.0, 1.0)))
	var nrm := f.cross(e).normalized()
	var foot := PackedVector3Array()
	for j in range(cols - 1, -1, -1):
		foot.append(m[j])
	var leech := PackedVector3Array()
	for i in int(0.45 * (fp.rows - 1)) + 1:
		leech.append(m[i * cols + cols - 1])
	var st := 0.0
	var flips := 0
	for edge in [foot, leech]:
		var turns := edge_turns(edge, nrm)
		var sg := 0.0
		var fl := 0
		for k in turns.size():
			if k > 0:
				st = maxf(st, absf(turns[k] - turns[k - 1]))
			if absf(turns[k]) >= FAIR_DEAD:
				var g := signf(turns[k])
				if sg != 0.0 and g != sg:
					fl += 1
				sg = g
		flips = maxi(flips, fl)
	return [ang, st, flips]


## the turn (deg) at each inner vertex of a polyline, signed about `nrm`
static func edge_turns(p: PackedVector3Array, nrm: Vector3) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in range(1, p.size() - 1):
		var t0 := (p[k] - p[k - 1]).normalized()
		var t1 := (p[k + 1] - p[k]).normalized()
		out.append(rad_to_deg(asin(clampf(t0.cross(t1).dot(nrm), -1.0, 1.0))))
	return out


## §7.6: with the main let fly, the kite sheeted from 60 % to 130 % of its optimum over 2 s at TWA 100 deg, 12 kn,
## moves no vertex of the main more than 0.05 Sa between frames.
func _stop_sweep(data: BoatClassData, bv: BoatView, fp: BoatView.SailPart, mp: BoatView.SailPart) -> void:
	var tws := 12.0 * KNOT
	var ap := _apparent(data, fp.index, tws, deg_to_rad(100.0), 1.0)
	var prev := PackedVector3Array()
	var worst := 0.0
	for f in 121:
		var k := 0.6 + 0.7 * f / 120.0
		var sv := _sails_view(data, ap.x, ap.y, tws, fp.index, -1, [k, 10.0])
		for w in (3 if f == 0 else 1):  # the stop reads the clew as last placed: settle the start
			bv.apply_sails(sv, sv, 1.0, 1.0 / 60.0)
		var m: PackedVector3Array = mp.shape.mid()
		if not prev.is_empty():
			worst = maxf(worst, max_move(prev, m))
		prev = m.duplicate()
	var sa: float = mp.shape.frame()["sa"]
	var msg := "main let fly, %s sheeted from 60 to 130 %%: the main moves at most %.3f m per frame (<= %.3f)" % [
		fp.id, worst, 0.05 * sa]
	t.ok(worst <= 0.05 * sa, msg)
	print("  " + msg)


## §7.4 the ease and the push are continuous: at TWA 100 deg, 12 kn, the flying sail sheeted from 60 % to 130 % of
## its optimum over 2 s with the main eased 20 % and the jib up moves no vertex more than 0.05 Sa between frames.
func _clear_sweep(data: BoatClassData, bv: BoatView, fp: BoatView.SailPart, jib_i: int) -> void:
	var tws := 12.0 * KNOT
	var ap := _apparent(data, fp.index, tws, deg_to_rad(100.0), 1.0)
	var prev := PackedVector3Array()
	var worst := 0.0
	for f in 121:
		var k := 0.6 + 0.7 * f / 120.0
		var sv := _sails_view(data, ap.x, ap.y, tws, fp.index, jib_i, [k, 1.2])
		# a steady start: the jib's eased twist side (§7.1) settled on this tack and the main's stop (§7.6) on this
		# clew, so only the kite's trim changes during the sweep
		for w in (20 if f == 0 else 1):
			bv.apply_sails(sv, sv, 1.0, 0.1 if f == 0 else 1.0 / 60.0)
		var m: PackedVector3Array = fp.shape.mid()
		if not prev.is_empty():
			worst = maxf(worst, max_move(prev, m))
		prev = m.duplicate()
	var sa: float = fp.shape.frame()["sa"]
	var msg := "%s sheeted from 60 to 130 %% with the main eased: largest move per frame %.3f m (<= %.3f)" % [
		fp.id, worst, 0.05 * sa]
	t.ok(worst <= 0.05 * sa, msg)
	print("  " + msg)


## The apparent wind (awa, aws) over a sail config's polar speed at the true wind (tws m/s, twa rad) on a tack
## (side +1: wind from starboard).
static func _apparent(data: BoatClassData, fi: int, tws: float, twa: float, side: float) -> Vector2:
	var v: float = data.configs[fi]["polar"].at(tws, twa)
	var aw := Vector2(tws * cos(twa) + v, tws * sin(twa))
	return Vector2(side * aw.angle(), aw.length())


## The sail states of one clearance case: the main and the flying sail up at trim factors of their optimum (and
## the jib at its own, when `jib_i` >= 0), the other sails down.
func _sails_view(data: BoatClassData, awa: float, aws: float, tws: float, fi: int, jib_i: int, tr: Array) -> SimSource.SailsView:
	var sv := SimSource.SailsView.new()
	sv.awa = awa
	sv.aws = aws
	sv.tws = tws
	var cfg: Dictionary = data.configs[fi]
	for i in data.info.sails.size():
		var st := SimSource.SailState.new()
		var si: SimSource.SailInfo = data.info.sails[i]
		var opt: PerfTable = null
		var f := 1.0
		if i == data.info.main_sail:
			opt = cfg["optimal"].get(i)
			f = tr[1]
		elif i == fi:
			opt = cfg["optimal"].get(i)
			f = tr[0]
			var pa: PerfTable = data.sail_data[i]["pole_angle"]
			st.pole = -Frames.sgn(awa) * (pa.at(tws, absf(awa)) if pa != null else 0.0)
		elif i == jib_i:
			opt = data.configs[jib_i]["optimal"].get(i)
		if i == data.info.main_sail or i == fi or i == jib_i:
			st.phase = UP
			var m: float = opt.at(tws, absf(awa)) if opt != null else si.sheet_min
			st.beta = -Frames.sgn(awa) * clampf(m * f, si.sheet_min, si.sheet_max)
		sv.sails.append(st)
		sv.out.append(SimSource.SailOutput.new())
	return sv


## One case: distances of the flying sail's vertices from the obstacles and the mast, and edge crossings both ways.
func _clear_check(fp: BoatView.SailPart, obs: Array, ms: Vector3, mh: Vector3, c: float, r: Dictionary, what: String) -> void:
	r["n"] += 1
	var km: PackedVector3Array = fp.shape.mid()
	var hd := km[(fp.rows - 1) * fp.cols]
	var ktris := grid_tris(km, fp.rows, fp.cols)
	var kh := tri_hash(ktris)
	var kedges := grid_edges(km, fp.rows, fp.cols)
	var cross := 0
	var od := []
	for o in obs:
		var sp: BoatView.SailPart = o
		var om: PackedVector3Array = sp.shape.mid()
		var otris := grid_tris(om, sp.rows, sp.cols)
		var oh := tri_hash(otris)
		od.append([otris, oh])
		cross += crossings(kedges, otris, oh) + crossings(grid_edges(om, sp.rows, sp.cols), ktris, kh)
	for e in kedges.size() / 2:
		var pts := Geometry3D.get_closest_points_between_segments(kedges[2 * e], kedges[2 * e + 1], ms, mh)
		if pts[0].distance_to(pts[1]) < 0.04:
			cross += 1
	if cross > 0:
		r["cross"] += cross
		if r["first"] == "":
			r["first"] = what
	for p in km:
		var cp := c * smoothstep(0.0, 1.0, p.distance_to(hd) / (5.0 * c))
		var d := p.distance_to(Geometry3D.get_closest_point_to_segment(p, ms, mh))
		for o in od:
			d = minf(d, dist_to(p, o[0], o[1]))
		if d < 0.9 * cp - 1e-4:
			r["bad"] += 1
		if cp >= c - 1e-6 and d < r["worst"]:
			r["worst"] = d
			r["at"] = what


## §12 test 27: the lofted wm7 kite as drawn (BoatView, native and reference, alone, full) against the measured
## sections it is lofted from: camber, draft and twist by height at the measured AWAs and half way between them
## (the AWA blend of §6.5: the measured numbers blended by the same smoothstep).
const LOFT_CAMBER_TOL := 0.025
const LOFT_DRAFT_TOL := 0.05
const LOFT_TWIST_TOL := 2.5  # deg


func _loft_sections() -> void:
	t.begin("27 lofted kite against its measured sections: wm7")
	if not FileAccess.file_exists("res://generated/boats/wm7.glb"):
		return
	var cls: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BoatClassData.repo_path(
			"data/classes/wm7.boat.json")))
	var shape_name := String(KiteSet.class_entry(cls, "kite").get("set", {}).get("shape", ""))
	var tab: Variant = JSON.parse_string(FileAccess.get_file_as_string(BoatClassData.repo_path(
			"data/sails/%s.kite_shape.json" % shape_name)))
	if tab is Dictionary and String(tab.get("kind", "")) == "surface":
		_loft_surface(tab, shape_name)
		return
	t.ok(tab is Dictionary and tab.get("shapes") is Array and tab["shapes"].size() >= 2,
		"wm7 kite: kite shape file %s read" % shape_name)
	if not tab is Dictionary:
		return
	var shapes: Array = tab["shapes"]
	var a0 := float(shapes[0]["awa_deg"])
	var a1 := float(shapes[shapes.size() - 1]["awa_deg"])
	var data := BoatClassData.load_class("wm7")
	for reference in ([false, true] if native else [true]):
		var bv := BoatView.create(data.info, 0.5, reference)
		var sp: BoatView.SailPart = null
		for q in bv.sail_parts:
			if q.type == "spinnaker_asym":
				sp = q
		t.ok(sp != null and sp.shape.is_loft(), "wm7 kite drawn with the lofted model (%s)" % (
			"reference" if reference else "native"))
		if sp == null or not sp.shape.is_loft():
			bv.free()
			continue
		var worst := [0.0, 0.0, 0.0]
		for awa_deg in [a0, 0.5 * (a0 + a1), a1]:
			for side in [1.0, -1.0]:
				var awa: float = side * deg_to_rad(awa_deg)
				var beta: float = -side * deg_to_rad(clampf(awa_deg - 48.0, 15.0, 64.0))
				sp.shape.set_obstacles([])
				sp.shape.update(UP, 1.0, beta, 0.0, 0.0, awa, 8.0)
				var w := clampf((awa_deg - a0) / (a1 - a0), 0.0, 1.0)
				w = w * w * (3.0 - 2.0 * w)
				var lines := []
				for k in (shapes[0]["sections"] as Array).size():
					var s0: Dictionary = shapes[0]["sections"][k]
					var s1: Dictionary = shapes[shapes.size() - 1]["sections"][k]
					var h := float(s0["h"])
					var want := [lerpf(s0["camber"], s1["camber"], w), lerpf(s0["draft"], s1["draft"], w),
						lerpf(float(s0.get("twist_deg", 0.0)), float(s1.get("twist_deg", 0.0)), w)]
					var got := loft_row_measure(sp, h, awa)
					for q in 3:
						worst[q] = maxf(worst[q], absf(got[q] - want[q]))
					lines.append("h %.2f camber %.1f/%.1f %% draft %.2f/%.2f twist %.1f/%.1f deg" % [h,
						100.0 * want[0], 100.0 * got[0], want[1], got[1], want[2], got[2]])
				if side > 0.0 and not reference:
					print("  wm7 kite at AWA %.0f (measured/drawn): %s" % [awa_deg, "; ".join(lines)])
		var msg := "wm7 kite (%s): camber within %.3f (<= %.3f), draft within %.3f (<= %.2f), twist within %.1f deg (<= %.1f) of the measured sections" % [
			"reference" if reference else "native", worst[0], LOFT_CAMBER_TOL, worst[1], LOFT_DRAFT_TOL, worst[2],
			LOFT_TWIST_TOL]
		t.ok(worst[0] <= LOFT_CAMBER_TOL and worst[1] <= LOFT_DRAFT_TOL and worst[2] <= LOFT_TWIST_TOL, msg)
		print("  " + msg)
		bv.free()


## §12 test 27 from a surface file (§6.5 "The surface source"): the drawn wm7 kite (alone, full, at the file's first
## AWA, both tacks) against the measured surface's own rows at the same stripes: camber and draft.
func _loft_surface(tab: Dictionary, shape_name: String) -> void:
	var first: Dictionary = tab["shapes"][0]
	var srf: Dictionary = tab["surfaces"][first["surface"]]
	t.ok(String(srf.get("form", "")) == "grid", "wm7 kite: surface file %s, its first shape a measured grid" % shape_name)
	if String(srf.get("form", "")) != "grid":
		return
	var pts: Array = srf["points"]
	var awa_deg := float(first["awa_deg"])
	var data := BoatClassData.load_class("wm7")
	for reference in ([false, true] if native else [true]):
		var bv := BoatView.create(data.info, 0.5, reference)
		var sp: BoatView.SailPart = null
		for q in bv.sail_parts:
			if q.type == "spinnaker_asym":
				sp = q
		t.ok(sp != null and sp.shape.is_loft(), "wm7 kite drawn with the lofted model (%s)" % (
			"reference" if reference else "native"))
		if sp == null or not sp.shape.is_loft():
			bv.free()
			continue
		var worst := [0.0, 0.0]
		for side in [1.0, -1.0]:
			var awa: float = side * deg_to_rad(awa_deg)
			var beta: float = -side * deg_to_rad(clampf(awa_deg - 48.0, 15.0, 64.0))
			sp.shape.set_obstacles([])
			sp.shape.update(UP, 1.0, beta, 0.0, 0.0, awa, 8.0)
			var lines := []
			for k in range(1, 6):
				var h := k / 6.0
				var want := surface_row_measure(pts, h)
				var got := loft_row_measure(sp, h, awa)
				for q in 2:
					worst[q] = maxf(worst[q], absf(got[q] - want[q]))
				lines.append("h %.2f camber %.1f/%.1f %% draft %.2f/%.2f" % [h, 100.0 * want[0], 100.0 * got[0],
					want[1], got[1]])
			if side > 0.0 and not reference:
				print("  wm7 kite at AWA %.0f (measured surface/drawn): %s" % [awa_deg, "; ".join(lines)])
		var msg := "wm7 kite (%s): camber within %.3f (<= %.3f), draft within %.3f (<= %.2f) of the measured surface" % [
			"reference" if reference else "native", worst[0], LOFT_CAMBER_TOL, worst[1], LOFT_DRAFT_TOL]
		t.ok(worst[0] <= LOFT_CAMBER_TOL and worst[1] <= LOFT_DRAFT_TOL, msg)
		print("  " + msg)
		bv.free()


## §12 test 27: camber and draft of a measured surface grid's row at the stripe h (rows from the foot of [a, l, n]
## points; the rows either side blended).
static func surface_row_measure(pts: Array, h: float) -> Array:
	var x := h * (pts.size() - 1)
	var i0 := mini(int(floor(x)), pts.size() - 2)
	var f := x - i0
	var row := PackedVector3Array()
	for j in (pts[i0] as Array).size():
		var a: Array = pts[i0][j]
		var b: Array = pts[i0 + 1][j]
		row.append(Vector3(lerpf(a[0], b[0], f), lerpf(a[1], b[1], f), lerpf(a[2], b[2], f)))
	return chord_measure(row)


## camber (largest distance from the chord over the chord, a parabola through the deepest point and its
## neighbours) and draft (its place along the chord from the first point) of a polyline row.
static func chord_measure(row: PackedVector3Array) -> Array:
	var c := row.size()
	var p0 := row[0]
	var ch := row[c - 1] - p0
	var cl := ch.length()
	var cu := ch / cl
	var xs := PackedFloat32Array()
	var ds := PackedFloat32Array()
	for j in c:
		var v := row[j] - p0
		var xx := v.dot(cu)
		xs.append(xx)
		ds.append((v - cu * xx).length())
	var k := 0
	for j in c:
		if ds[j] > ds[k]:
			k = j
	var dmax := ds[k]
	var xmax := xs[k]
	if k > 0 and k < c - 1:
		var den := (xs[k - 1] - xs[k]) * (xs[k - 1] - xs[k + 1]) * (xs[k] - xs[k + 1])
		if absf(den) > 1e-9:
			var aa := (xs[k + 1] * (ds[k] - ds[k - 1]) + xs[k] * (ds[k - 1] - ds[k + 1]) + xs[k - 1] * (ds[k + 1] - ds[k])) / den
			var bb := (xs[k + 1] * xs[k + 1] * (ds[k - 1] - ds[k]) + xs[k] * xs[k] * (ds[k + 1] - ds[k - 1]) + xs[k - 1] * xs[k - 1] * (ds[k] - ds[k + 1])) / den
			if aa < 0.0:
				var xv := -bb / (2.0 * aa)
				if xv > xs[k - 1] and xv < xs[k + 1]:
					xmax = xv
					dmax = ds[k] + aa * (xv - xs[k]) * (xv - xs[k]) + (2.0 * aa * xs[k] + bb) * (xv - xs[k])
	return [dmax / cl, xmax / cl]


## §12 test 27: camber (over the chord), draft (share of the chord from the luff) and twist (deg, the chord's
## horizontal angle from the foot's, to leeward) of the placed kite at height h (a share of the luff and the leech,
## between the rows either side).
static func loft_row_measure(sp: BoatView.SailPart, h: float, awa: float) -> Array:
	var x := h * (sp.rows - 1)
	var i0 := mini(int(floor(x)), sp.rows - 2)
	var f := x - i0
	var m0 := row_measure(sp, i0, awa)
	var m1 := row_measure(sp, i0 + 1, awa)
	return [lerpf(m0[0], m1[0], f), lerpf(m0[1], m1[1], f), lerpf(m0[2], m1[2], f)]


static func row_measure(sp: BoatView.SailPart, i: int, awa: float) -> Array:
	var m: PackedVector3Array = sp.shape.mid()
	var c := sp.cols
	var p0 := m[i * c]
	var ch := m[i * c + c - 1] - p0
	var cl := ch.length()
	var cu := ch / cl
	var xs := PackedFloat32Array()
	var ds := PackedFloat32Array()
	for j in c:
		var v := m[i * c + j] - p0
		var xx := v.dot(cu)
		xs.append(xx)
		ds.append((v - cu * xx).length())
	var k := 0
	for j in c:
		if ds[j] > ds[k]:
			k = j
	var dmax := ds[k]
	var xmax := xs[k]
	if k > 0 and k < c - 1:  # a parabola through the deepest vertex and its neighbours
		var den := (xs[k - 1] - xs[k]) * (xs[k - 1] - xs[k + 1]) * (xs[k] - xs[k + 1])
		if absf(den) > 1e-9:
			var aa := (xs[k + 1] * (ds[k] - ds[k - 1]) + xs[k] * (ds[k - 1] - ds[k + 1]) + xs[k - 1] * (ds[k + 1] - ds[k])) / den
			var bb := (xs[k + 1] * xs[k + 1] * (ds[k - 1] - ds[k]) + xs[k] * xs[k] * (ds[k + 1] - ds[k - 1]) + xs[k - 1] * xs[k - 1] * (ds[k] - ds[k + 1])) / den
			if aa < 0.0:
				var xv := -bb / (2.0 * aa)
				if xv > xs[k - 1] and xv < xs[k + 1]:
					xmax = xv
					dmax = ds[k] + aa * (xv - xs[k]) * (xv - xs[k]) + (2.0 * aa * xs[k] + bb) * (xv - xs[k])
	var up := Frames.body_to_model(Vector3(0, 0, 1))
	var aft := -Frames.body_to_model(Vector3(1, 0, 0))
	var lee := Frames.body_to_model(Vector3(0, 1, 0)) * signf(awa)
	var f0 := m[c - 1] - m[0]
	var a_f := atan2(f0.dot(lee), f0.dot(aft))
	var a_i := atan2(ch.dot(lee), ch.dot(aft))
	return [dmax / cl, xmax / cl, rad_to_deg(Frames.wrap_pi(a_i - a_f))]


## §12 test 19: the generator's preview poses (tools/boatgen/boatgen/sail_set.py, written to
## generated/boats/<id>.sets.json) draw the sails as BoatView does, native and reference, within PARITY_TOL.
const PARITY_TOL := 0.01
const PARITY_CLASSES := ["wm7", "wm12", "wm9", "wm21", "test_sym", "test_set_asym", "test_set_sym"]


func _parity() -> void:
	for id in PARITY_CLASSES:
		var sets_path := ProjectSettings.globalize_path("res://generated/boats/%s.sets.json" % id)
		if not FileAccess.file_exists("res://generated/boats/%s.glb" % id):
			continue
		t.begin("19 generator parity: %s" % id)
		var sets: Variant = BoatClassData._read_json(sets_path)
		t.ok(sets is Dictionary and sets.get("sets") is Array,
			"%s: %s.sets.json written by the generator (run_boat_import_test.sh)" % [id, id])
		if not sets is Dictionary:
			continue
		var info := _parity_info(id)
		for reference in ([false, true] if native else [true]):
			var bv := BoatView.create(info, 0.5, reference)
			var parts := {}
			for sp in bv.sail_parts:
				parts[sp.id] = sp
			var worst := 0.0
			var at := ""
			var n := 0
			for st in sets["sets"]:
				var sv := SimSource.SailsView.new()
				sv.awa = float(st["awa"])
				sv.aws = float(st["aws"])
				var want := {}
				for s in st["sails"]:
					want[String(s["id"])] = s
				for i in info.sails.size():
					var ss := SimSource.SailState.new()
					var w: Variant = want.get(info.sails[i].name)
					if w != null:
						ss.phase = UP
						ss.beta = float(w["beta"])
						ss.pole = float(w["gamma"])
					sv.sails.append(ss)
					sv.out.append(SimSource.SailOutput.new())
				for k in 3:  # the main's stop (§7.6) reads the flying sail's clew as last placed
					bv.apply_sails(sv, sv, 1.0, 0.1)
				for sid in want:
					var sp: BoatView.SailPart = parts.get(sid)
					t.ok(sp != null and sp.shape != null, "%s %s: sail %s drawn" % [id, st["name"], sid])
					if sp == null or sp.shape == null:
						continue
					var m: PackedVector3Array = sp.shape.mid()
					var e: Array = want[sid]["mid"]
					t.ok(m.size() == e.size(), "%s %s %s: grid sizes %d and %d" % [id, st["name"], sid, m.size(), e.size()])
					for k in mini(m.size(), e.size()):
						var q := m[k]
						var d := Vector3(q.z, q.x, q.y).distance_to(Vector3(e[k][0], e[k][1], e[k][2]))
						if d > worst:
							worst = d
							at = "%s %s vertex %d" % [st["name"], sid, k]
					n += 1
			var impl := "reference" if reference else "native"
			var msg := "%s (%s): %d sails in %d poses, largest distance from the generator's %.4f m at %s (<= %.3f)" % [
				id, impl, n, sets["sets"].size(), worst, at, PARITY_TOL]
			t.ok(n > 0 and worst <= PARITY_TOL, msg)
			print("  " + msg)
			bv.free()


## The class numbers BoatView needs, from the class and performance files, or for a generator test class from its
## sidecar (sails in class order).
func _parity_info(id: String) -> SimSource.ClassInfo:
	if FileAccess.file_exists(BoatClassData.repo_path("data/perf/%s.perf.json" % id)):
		return BoatClassData.load_class(id).info
	var side: Dictionary = BoatClassData._read_json(ProjectSettings.globalize_path("res://generated/boats/%s.physics.json" % id))
	var cls: Dictionary = BoatClassData._read_json(BoatClassData.repo_path("tools/boatgen/tests/fixtures/%s.boat.json" % id))
	var info := SimSource.ClassInfo.new()
	info.id = id
	info.loa = float(cls["hull"]["loa"])
	info.beam_max = float(cls["hull"]["beam_max"])
	info.physics = side
	for s in cls["sails"]:
		var si := SimSource.SailInfo.new()
		si.name = s["id"]
		si.type = s["type"]
		info.sails.append(si)
	return info


## §11 update rate by size on screen, distance and the frustum.
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
	# every frame large on screen, 30 Hz smaller within 200 m, 15 Hz to 800 m, 4 Hz beyond, none behind the camera
	for c in [[12.0, 60], [100.0, 30], [500.0, 15], [1500.0, 4], [-300.0, 0]]:
		var bv := BoatView.create(data.info, 0.5)
		root.add_child(bv)
		# the camera looks north (-Z); the boat ahead at the distance, or behind it
		bv.global_position = Vector3(0, 0, -float(c[0]))
		var phi0: float = bv.sail_parts[0].shape.get_phase()
		for f in 60:
			bv.apply_sails(sv, sv, 1.0, 1.0 / 60.0)
		var n: int = bv.sail_parts[0].updates
		t.ok(absi(n - int(c[1])) <= 1, "main at %.0f m: %d updates in 1 s (%d)" % [c[0], n, c[1]])
		if c[1] == 0:
			# back in view: placed at once, the flutter phase advanced by the time it was out of view
			bv.global_position = Vector3(0, 0, -300.0)
			bv.apply_sails(sv, sv, 1.0, 1.0 / 60.0)
			t.ok(bv.sail_parts[0].updates == 1, "placed at once back in view")
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
			if BoatView.is_flying(sp.type):  # §7.4 with the main and the jib as obstacles
				sp.shape.set_obstacles(bv._obstacles(sp))
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
			var kp: BoatView.SailPart = bv.sail_parts[bv.sail_parts.size() - 1]
			print("  native kite ease in the cost pose: %.1f deg" % rad_to_deg(kp.shape.get_ease()))
		bv.free()
