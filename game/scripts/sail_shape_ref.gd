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
## clearance, mast_head (§7.4; set_obstacles(sails) before each update of a flying sail); a lofted kite (§6.5):
## model "loft", loft_awa (the measured AWAs, rad, rising), loft_shapes (per AWA every vertex's local position in
## grid order, concatenated), loft_depth, loft_trim.

enum Kind { MAIN, HEADSAIL, ASYM, SYM }
## BOOM: the main about the boom axis; LUFF: jib, genoa, code zero about the luff; SPRIT: asymmetric on a fixed
## sprit; POLE: a flying sail on a pole (sail_visuals.md §7)
enum Mode { BOOM, LUFF, SPRIT, POLE }

const KNOT := 1852.0 / 3600.0
const C_HOOK := 0.0369260386
## §6.2 the jib's and genoa's camber k_j, its fill scale b_j and the largest of x (1 - x) (2 - x)
const JIB_CAMBER := 0.135
const JIB_FILL := 0.15
const JIB_PROFILE_MAX := 0.3849002
## §7.3 the tack pin reaches this share of the luff from the tack
const TACK_PIN := 0.25
## §7.4 the last segment of an obstacle section runs on past its leech by this many clearances
const RUN_ON := 6.0
const TAU_SMOOTH := 0.25
const DT_MAX := 0.1
## §4, §7.4 clearance constants: push slope, ease threshold (in clearances), ease cap (rad)
const PUSH_SLOPE := 0.3
const PUSH_EASE := 2.0
const EASE_MAX := 0.35
## §7.7 the clew set: corner reach (grid steps), fade height (of Sl), bounds of the draw-in and draw-down, the
## difference step and the Newton steps of the solve
const CLEW_REACH := 2
const CLEW_H := 0.3
const CLEW_KD := Vector2(-0.1, 0.25)
const CLEW_KL := Vector2(-0.1, 0.3)
const CLEW_STEP := 0.01
const CLEW_ITER := 2
const CLEW_FADE := Vector2(1.3089969, 1.8325957)  # faded out as |beta| goes round the bow
const CLEW_AWA := Vector2(0.7853982, 1.1344640)  # and in with the AWA over the kite's lowest angles
## §4.1 the luff and leech curl reach this share of the chord in from the edge; `forward` holds the corners over this
## share of Sl; `tack_rise` fades out over this share of Sl from the tack
const CURL_BAND := 0.25
const HOLD := 0.35
const TACK_REACH := 0.5
## §6.5 the lofted belly crosses to the other side as sin(beta + awa) passes +-LOFT_SIDE; the whole kite's turn off
## the main, the jib and the mast: at most LOFT_EASE_MAX (rad; LOFT_STAY_MAX for a kite on a pole, which also keeps
## off the forestay, a last resort), in at most LOFT_EASE_STEPS steps
const LOFT_SIDE := 0.1
const LOFT_EASE_MAX := 0.5
const LOFT_STAY_MAX := 1.8
## §6.5 the drawn whole-kite turn moves at most this fast (rad/s) from the last update's
const LOFT_EASE_RATE := 0.6
## §6.5 ... and its belly crosses to the other side at most this fast (per second; 2: a full crossing in 1 s)
const LOFT_SIDE_RATE := 2.0
## §6.5 a flogging kite: its side held to leeward forward of the beam (faded out from |AWA| LOFT_FLOG_UP0 over
## LOFT_FLOG_UP1, rad), its luff collapsing over this share of the chord
const LOFT_FLOG_UP0 := 70.0 * PI / 180.0
const LOFT_FLOG_UP1 := 40.0 * PI / 180.0
const LOFT_FLOG_LUFF := 0.35
## §6.5 a lofted kite on a pole keeps this share of the foretriangle base ahead of the forestay (the hard rule)
const LOFT_STAY_CLEAR := 0.04
const LOFT_EASE_STEPS := 12
## §6.5 after its first step, the turn's solve looks only at vertices this many clearances near the worst; it keeps
## LOFT_MARGIN margins (horizontal, §7.4), so the true distance up by the head, where the sails lean, keeps one
const LOFT_NEAR := 2.0
const LOFT_MARGIN := 1.2
## §6.5 |beta| over which the trim and the turn off the obstacles fade in from the centreline, and from where and over
## how much they fade out round the bow (rad)
const LOFT_FADE := Vector3(0.1, 1.7453293, 1.0471976)

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
## §7.4 the forestay (tack fitting, hounds) of a flying sail on a pole, its wall half width and margin
var has_stay := false
var stay0 := Vector3.ZERO
var stay1 := Vector3.ZERO
var stay_w := 0.0
var stay_c := 0.0
var loft_stay_c := 0.0
var loft_stay := false
var stay_on := true
var _turn_set := false
var _turn_step := 0.0
var _turn_prev := 0.0
var _side_prev := 1.0
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
var _u0row := PackedFloat32Array()  # §6.2 u of each row's luff and leech vertex
var _ulrow := PackedFloat32Array()
var _jcam := 0.0                     # §6.2 the jib's signed camber m, per update
## per row, per update: camber over chord and chord shortening (§6.3)
var _drow := PackedFloat32Array()
var _srow := PackedFloat32Array()
var _prow := PackedFloat32Array()   # §6.3, §6.4 the camber's height profile p_i
var _prof := PackedFloat32Array()   # §6.3, §6.4 the chordwise camber profile per vertex
var _trow := PackedFloat32Array()   # §7 the twist of each row toward leeward, rad
var _crow := PackedFloat32Array()   # §7.7 the clew set's share of each row
var _d0row := PackedFloat32Array()  # §7.7 the camber of each row before the clew set, per update
var _kd := 0.0                       # §7.7 the draw-in and draw-down of the last update
var _kl := 0.0

## §4.1 the kite set parameters read per update (the rest shape the per-row and per-vertex tables at set-up)
var belly_aft := 0.5
var belly_up := 0.5
var twist_exp := 1.5
var twist_lo := 0.0
var twist_hi := 0.0
var twist_run := 0.0
var foot_sag := 0.0
var foot_sag_h := 0.35
var head_drop := 0.0
var clew_lift := 0.0
var clew_out := 0.0
var forward := 0.0
var tack_rise := 0.0
var stay_head := 0.3
var stay_luff := 0.5
var stay_leech := 0.3
var _grow := PackedFloat32Array()   # per row: the girth scale
var _hold := PackedFloat32Array()   # per vertex: the corners' hold of `forward`
var _rise := PackedFloat32Array()   # per vertex: the share of `tack_rise`

## drivers kept between frames
var phi := 0.0
var s_b := 1.0
var tl := 0.0
var _tl_set := false
## §7.4: the obstacles (SailShapeRef), their sections this update, and the ease of the last update
var _obs: Array = []
var _secs: Array = []
var _ease := 0.0
## §7.6 the working lead block on starboard (model axes), with the flag
var has_lead := false
var sheet_lead := Vector3.ZERO
## §6.5 a lofted kite: its measured AWAs and shapes (grid order, one block per AWA), depth scale and trim
var loft := false
var _loft_awa := PackedFloat32Array()
var _loft := PackedVector3Array()
var loft_depth := 1.0
var loft_trim := 0.0
var _turn := 0.0      # §6.5 the turn about the luff of the last update, before the ease
var _fa := 0.0        # §7.6 the flying shape's share this update (the main's stop weight)
var _clew0 := Vector3.ZERO  # §7.6 the clew as placed, before the clearance push
var _tack_d := PackedFloat32Array()  # §7.3 rest distance of each vertex from the tack (the tack pin)
var _tack_at := Vector3.ZERO  # §7.4 the placed tack, where the margin fades out as at the head
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
	has_lead = p.has("sheet_lead")
	sheet_lead = p.get("sheet_lead", Vector3.ZERO)
	has_mast_head = p.has("mast_head")
	mast_head = p.get("mast_head", mast_step + mast_axis)
	# §4.1 the kite set parameters: the keys given over the defaults of the kind (none on a main or headsail)
	var kite := kind == Kind.ASYM or kind == Kind.SYM
	var ks := KiteSet.defaults("spinnaker_asym" if kind == Kind.ASYM else "spinnaker_sym")
	if kite:
		for key in ks:
			if p.has(key):
				ks[key] = float(p[key])
	belly_aft = ks["belly_aft"]
	belly_up = ks["belly_up"]
	twist_exp = ks["twist_exp"] if kite else 1.5
	twist_lo = ks["twist_awa_lo"]
	twist_hi = ks["twist_awa_hi"]
	twist_run = ks["twist_run"]
	foot_sag = ks["foot_sag"] if kite else 0.0
	foot_sag_h = ks["foot_sag_h"]
	head_drop = ks["head_drop"]
	clew_lift = ks["clew_lift"]
	clew_out = ks["clew_out"]
	forward = ks["forward"]
	tack_rise = ks["tack_rise"]
	stay_head = ks["stay_head"]
	stay_luff = ks["stay_luff"]
	stay_leech = ks["stay_leech"]
	loft_depth = ks["loft_depth"] if kite else 1.0
	loft_trim = ks["loft_trim"] if kite else 0.0
	# §6.5 the lofted shapes, when the set block picks the loft and the sidecar has them
	loft = false
	_turn = 0.0
	if kite and String(p.get("model", "hinge")) == "loft" and p.get("loft_awa") != null:
		_loft_awa = PackedFloat32Array(p["loft_awa"])
		_loft = PackedVector3Array(p.get("loft_shapes", PackedVector3Array()))
		loft = _loft_awa.size() >= 1 and _loft.size() == _loft_awa.size() * r * c
	has_stay = mode == Mode.POLE and clearance > 0.0 and p.has("forestay_tack") and p.has("hounds")
	if has_stay:
		stay0 = p["forestay_tack"]
		stay1 = p["hounds"]
		var dm := stay0 - mast_step
		var jb := (dm - mast_axis * dm.dot(mast_axis)).length()  # the foretriangle base
		stay_w = float(ks["stay_width"]) * jb
		stay_c = maxf(float(ks["stay_clear"]) * jb, clearance)
	# §6.5 a lofted kite, on a pole or a sprit, keeps ahead of the forestay (the hard rule)
	loft_stay = loft and clearance > 0.0 and p.has("forestay_tack") and p.has("hounds")
	if loft_stay:
		stay0 = p["forestay_tack"]
		stay1 = p["hounds"]
		var dm2 := stay0 - mast_step
		loft_stay_c = LOFT_STAY_CLEAR * (dm2 - mast_axis * dm2.dot(mast_axis)).length()
	_obs = []
	_ease = 0.0
	_turn_set = false
	_turn_prev = 0.0
	_side_prev = 1.0
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
	_u0row.resize(rows)
	_ulrow.resize(rows)
	_drow.resize(rows)
	_drow.fill(0.0)
	_srow.resize(rows)
	_srow.fill(1.0)
	_prow.resize(rows)
	_crow.resize(rows)
	_d0row.resize(rows)
	_d0row.fill(0.0)
	_trow.resize(rows)
	_trow.fill(0.0)
	_prof.resize(n)
	_grow.resize(rows)
	_grow.fill(1.0)
	# §6.3, §6.4, §4.1: the camber's height profile, the draft's exponent, the girth and the edge curls
	var pk: float = ks["depth_peak_h"]
	var cf: float = 1.0 - float(ks["depth_foot"])
	var chd: float = 1.0 - float(ks["depth_head"])
	var ql: float = log(0.5) / log(float(ks["draft_low"]))
	var dq: float = log(0.5) / log(float(ks["draft_head"])) - ql
	var df: float = ks["draft_from_h"]
	var gm: float = ks["girth_mid"]
	var lcu: float = ks["luff_curl"]
	var rcu: float = ks["leech_curl"]
	for i in rows:
		for j in cols:
			var k := i * cols + j
			_u[k] = (_a[k] - a_min) / sa
			_h[k] = (_l[k] - l_min) / sl
			_uc[k] = float(j) / (cols - 1)
		_c[i] = rest_mid[i * cols + cols - 1].distance_to(rest_mid[i * cols])
		_amid[i] = 0.5 * (_a[i * cols] + _a[i * cols + cols - 1])
		_hrow[i] = _h[i * cols]
		var cr := clampf(1.0 - _hrow[i] / float(ks["clew_h"] if kite else CLEW_H), 0.0, 1.0)
		_crow[i] = cr * cr * cr
		_u0row[i] = _u[i * cols]
		_ulrow[i] = _u[i * cols + cols - 1]
		# §6.3 (asymmetric: deepest at 0.3 of the height, the draft forward) and §6.4 (symmetric: full depth from
		# the foot to mid height, the draft in the middle), by the set parameters of §4.1
		var hr := _hrow[i]
		if kite:
			var lo := (pk - hr) / pk
			var hi := (hr - pk) / (1.0 - pk)
			_prow[i] = 1.0 - cf * lo * lo if hr < pk else 1.0 - chd * hi * hi
			var t := clampf((hr - df) / (1.0 - df), 0.0, 1.0)
			var q := ql + dq * t * t * (3.0 - 2.0 * t)
			var b := 1.0 - 2.0 * hr if hr < 0.5 else 2.0 * hr - 1.0
			_grow[i] = gm + (float(ks["girth_foot"] if hr < 0.5 else ks["girth_head"]) - gm) * b * b
			var fh := 4.0 * hr * (1.0 - hr)  # the edge curls, none at the corners
			for j in cols:
				var uc := _uc[i * cols + j]
				var pr := 0.0
				if kind == Kind.ASYM:
					pr = sin(PI * pow(uc, q))
				else:
					var x := uc if q == 1.0 else pow(uc, q)
					pr = 4.0 * x * (1.0 - x)
				if lcu != 0.0:
					var bl := clampf(1.0 - uc / CURL_BAND, 0.0, 1.0)
					pr += lcu * bl * bl * fh
				if rcu != 0.0:
					var br := clampf(1.0 - (1.0 - uc) / CURL_BAND, 0.0, 1.0)
					pr += rcu * br * br * fh
				_prof[i * cols + j] = pr
	furl_radius = float(p.get("furl_radius", 0.02 + 0.006 * sa))
	_tack_d.resize(n)
	for k in n:
		_tack_d[k] = rest_mid[k].distance_to(rest_mid[0])
	# §4.1 the corners' hold of `forward` and the share of `tack_rise`, from the rest distances to the corners
	_hold.resize(n)
	_hold.fill(0.0)
	_rise.resize(n)
	_rise.fill(0.0)
	if kite:
		var rr := HOLD * sl
		var hc := rest_mid[(rows - 1) * cols]
		var cc := rest_mid[cols - 1]
		for k in n:
			_hold[k] = Frames.smoothstep01(_tack_d[k] / rr) * Frames.smoothstep01(rest_mid[k].distance_to(hc) / rr) \
					* Frames.smoothstep01(rest_mid[k].distance_to(cc) / rr)
			var w := 1.0 - minf(_tack_d[k] / (TACK_REACH * sl), 1.0)
			_rise[k] = w * w
	_fa = 0.0
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


## sail_visuals.md §5.2, §5.3 and the twist side of §7.1; every frame, paused with the game.
func advance(dt: float, aws: float, awa: float, backed: bool) -> void:
	dt = clampf(dt, 0.0, DT_MAX)
	var w := minf(flutter_rate * aws, flutter_rate_max)
	phi = fposmod(phi + w * dt, TAU)
	var k := 1.0 - exp(-dt / TAU_SMOOTH)
	s_b += ((-1.0 if backed else 1.0) - s_b) * k
	if not _tl_set:
		tl = -Frames.sgn(awa)
		_tl_set = true
	else:
		tl += (-Frames.sgn(awa) - tl) * k


func get_phase() -> float:
	return phi


func set_phase(v: float) -> void:
	phi = v


func get_backed_factor() -> float:
	return s_b


func set_backed_factor(v: float) -> void:
	s_b = v


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


## the placed mid-surface at the given grid indices (the drawn shadow's outline, BoatShadows.sail_indices)
func mid_points(idx: PackedInt32Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(idx.size())
	for k in idx.size():
		out[k] = _mid[idx[k]] if idx[k] >= 0 and idx[k] < _mid.size() else Vector3.ZERO
	return out


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
		tl = -Frames.sgn(awa)
		_tl_set = true
	var shiver := clampf(luff_shiver, 0.0, 1.0)
	if loft:
		_update_loft(phase, progress, beta, gamma, shiver, awa, aws)
		return
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
			ge = Frames.sgn(gamma) * minf(absf(gamma), lim)
			s_t = Frames.about(head, up, ge)
		Mode.POLE:
			ge = gamma
			s_t = Frames.about(mast_step, mast_axis, ge)
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
		var b := fill(sin(Frames.wrap_pi(beta + awa)), fill_gain, fill_curve)
		d_cam = Frames.sgn(b) * 4.0 * sa * b * b
	elif kind == Kind.HEADSAIL:
		var b := fill(sin(beta), fill_gain, fill_curve) * s_b
		d_cam = Frames.sgn(b) * 4.0 * sa * b * b
		if cam_cap > 0.0:
			var dm := cam_cap * sa / 0.2362
			d_cam = dm * tanh(d_cam / dm)
		_jcam = Frames.sgn(b) * JIB_CAMBER * tanh(absf(b) / JIB_FILL) if b != 0.0 else 0.0
	else:
		if kind == Kind.SYM:
			f_fly = absf(fill(sin(beta), fill_gain, fill_curve))
		else:
			f_fly = fill_gain * clampf(aws / KNOT, 3.0, 6.0) / 6.0
		var uw := fwd * cos(awa) - port * sin(awa)
		wv = Vector3(uw.dot(ap) * belly_aft / fill_curve, uw.dot(lp) * belly_up, uw.dot(np))
		wv = wv.normalized() if wv.length_squared() > 1e-12 else Vector3(0, 0, 1)
		var fc := camber * minf(f_fly, 1.15)
		for i in rows:
			_d0row[i] = fc * _prow[i]
		_clew_rows(0.0, 0.0)
	# §7.1 to §7.3 the row twist (an asymmetric spinnaker's opens with the AWA)
	var tw := twist_top
	if kind == Kind.ASYM:
		var ta := clampf((absf(awa) - twist_lo) / (twist_hi - twist_lo), 0.0, 1.0)
		var tr := clampf((PI - absf(awa)) / twist_run, 0.0, 1.0)
		tw *= ta * ta * (3.0 - 2.0 * ta) * tr * tr * (3.0 - 2.0 * tr)
	# (signed; the asymmetric spinnaker's on the side away from the wind at once: it is zero where awa changes sign)
	for i in rows:
		_trow[i] = -Frames.sgn(awa) * tw * (1.0 - pow(1.0 - _hrow[i], twist_exp)) if kind == Kind.ASYM \
				else tl * tw * pow(_hrow[i], twist_exp)
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
	_local(phase, up_shape, p, d_cam, amp, shiver, wv)
	# §7.4 the ease of a flying sail off the other sails (the head lies on the luff axis)
	var hd := s_t * (head - lh * (head_drop * sl))  # §4.1 the head as dropped
	_tack_at = s_t * tack
	var clearing := clearance > 0.0 and (not _obs.is_empty() or has_mast_head)
	_ease = 0.0
	if clearing and not _obs.is_empty():
		_sections(s_t, piv, ax, base)
		_ease = _ease_for(beta, s_t, piv, ax, base, hd)
	else:
		_secs = []  # no obstacles: none left over from the last update
	var es := Frames.sgn(beta) * _ease
	# §7.7 the clew set by its sheet (with the sail as eased): the low rows again with the solved draw-in, draw-down
	_kd = 0.0
	_kl = 0.0
	var g_c := (1.0 - Frames.smoothstep01((absf(Frames.wrap_pi(beta)) - CLEW_FADE.x) / (CLEW_FADE.y - CLEW_FADE.x))) \
			* Frames.smoothstep01((absf(awa) - CLEW_AWA.x) / (CLEW_AWA.y - CLEW_AWA.x))
	if kind == Kind.ASYM and has_lead and g_c > 0.0:
		var kk := _clew_set(beta, base + es, piv, ax, s_t, wv)
		_kd = g_c * kk.x
		_kl = g_c * kk.y
		if _kd != 0.0 or _kl != 0.0:
			_clew_rows(_kd, _kl)
			# only the rows the clew set reaches change (the tack corner does not: its offset is the same)
			var r_to := 0
			while r_to < rows and _crow[r_to] > 0.0:
				r_to += 1
			_local(phase, up_shape, p, d_cam, amp, shiver, wv, r_to)
	# §7 placement, row by row with the twist toward leeward
	for i in rows:
		var th := base + _trow[i] + es
		var xr := Frames.about(piv, ax, th) * s_t
		for j in cols:
			var k := i * cols + j
			var lc := _loc[k]
			_mid[k] = xr * (tack + ah * lc.x + lh * lc.y + nh * lc.z)
	# §7.6 the share of the flying shape: 1 up, growing over the last tenth of the hoist, going with the drop
	_fa = 0.0
	if kind == Kind.ASYM or kind == Kind.SYM:
		if up_shape:
			_fa = 1.0
		elif phase == 2:
			var kh := clampf((p - 0.9) / 0.1, 0.0, 1.0)
			_fa = kh * kh
		elif phase == 5:
			_fa = 1.0 - pow(p, 0.3)
	_clew0 = _mid[cols - 1]
	if _fa > 0.0 and (forward != 0.0 or tack_rise != 0.0):
		_shift()
	if has_stay and _fa > 0.0:
		_stay()
	if clearing:
		_push(awa, hd)
	_layers(np)


## §6.5 a lofted kite: the measured shapes blended by the AWA, scaled by the fill, the belly on the side the wind
## blows it to, then placed whole: turned about its luff by the core's sheet angle (and the trim), and further out
## only as far as the main, the jib and the mast need. No local bending.
func _update_loft(phase: int, progress: float, beta: float, gamma: float, shiver: float, awa: float,
		aws: float) -> void:
	var s_t := Transform3D.IDENTITY
	var ge := 0.0
	if mode == Mode.SPRIT:
		var lim := asin(minf(1.0, tack_line_max * sl / r_h))
		ge = Frames.sgn(gamma) * minf(absf(gamma), lim)
		s_t = Frames.about(head, up, ge)
	elif mode == Mode.POLE:
		ge = gamma
		s_t = Frames.about(mast_step, mast_axis, ge)
	var piv := s_t * tack
	var ax := (s_t.basis * lh).normalized()
	# the measured shapes by the AWA (smoothstep between neighbours, held beyond the ends)
	var m := _loft_awa.size()
	var x := absf(Frames.wrap_pi(awa))
	var i0 := 0
	var i1 := 0
	var t := 0.0
	if x >= _loft_awa[m - 1]:
		i0 = m - 1
		i1 = m - 1
	elif x > _loft_awa[0]:
		while i0 + 2 < m and x >= _loft_awa[i0 + 1]:
			i0 += 1
		i1 = i0 + 1
		t = Frames.smoothstep01((x - _loft_awa[i0]) / (_loft_awa[i1] - _loft_awa[i0]))
	var dep := minf(fill_gain * clampf(aws / KNOT, 3.0, 6.0) / 6.0, 1.0) * loft_depth
	var sd := clampf(sin(Frames.wrap_pi(beta + awa)) / LOFT_SIDE, -1.0, 1.0)
	# a flogging kite (the shiver: on the wind line, or flown beyond its usable angle) keeps its belly to leeward
	# forward of the beam, its fill breathing and its luff collapsing and refilling, the flutter three times as hard
	var w_up := 1.0 - Frames.smoothstep01((absf(Frames.wrap_pi(awa)) - LOFT_FLOG_UP0) / LOFT_FLOG_UP1)
	var kf := shiver * w_up  # forward of the beam: abaft it a luffing kite (a gybe) only shivers
	var side := sd * (3.0 - sd * sd) / 2.0
	var side_f := side + (Frames.sgn(awa) - side) * minf(1.0, 2.0 * kf)
	# the belly crosses over at most at LOFT_SIDE_RATE per second (a gybe turns it inside out over a visible time)
	if _turn_set and _turn_step > 0.0:
		var lim_s := LOFT_SIDE_RATE * _turn_step
		side_f = _side_prev + clampf(side_f - _side_prev, -lim_s, lim_s)
	_side_prev = side_f
	var breath := 1.0 - kf * (0.3 + 0.2 * sin(phi) + 0.15 * sin(2.3 * phi + 1.0))
	var luff_c := kf * (0.5 + 0.5 * sin(1.7 * phi + 0.5))
	var i2 := 0.33 * flutter_amp * shiver * (1.0 + 2.0 * kf)
	var fly := PackedVector3Array()
	fly.resize(n)
	for k in n:
		var a := _loft[i0 * n + k]
		var lf := a + (_loft[i1 * n + k] - a) * t
		var fl := Vector3(_a[k], _l[k], 0.0)
		fl += (lf - fl) * (dep * breath)
		fl.z *= side_f
		if luff_c > 0.0 and _uc[k] < LOFT_FLOG_LUFF:
			var r := 1.0 - _uc[k] / LOFT_FLOG_LUFF
			fl.z *= 1.0 - luff_c * r * r
		if i2 > 0.0:  # luffing: the belly breathes, strongest where it is deep, travelling aft
			var q := phi - 7.0 * _uc[k]
			fl += Vector3(0.1 * i2 * sin(q) * absf(fl.z), 0.0, i2 * cos(q) * fl.z)
		fly[k] = fl
	# the turn about the luff: the core's sheet angle (as the hinge model's, §7.3), plus the trim
	# the trim and the turn off the obstacles fade out where sgn(beta) flips: on the centreline and round the bow
	var wb := absf(Frames.wrap_pi(beta))
	var es := Frames.sgn(beta) * Frames.smoothstep01(wb / LOFT_FADE.x) * (1.0 - Frames.smoothstep01((wb - LOFT_FADE.y) / LOFT_FADE.z))
	var th := beta - ge + es * loft_trim
	_turn = th
	# §8.1 which shape: the hoist and drop of §8.4, §8.5 toward the flying shape, the tack on its fitting
	var up_shape := phase == 3 or phase == 4
	var p := 1.0
	if not up_shape:
		if phase == 2 or phase == 5:
			p = clampf(progress, 0.0, 1.0)
		else:
			p = 0.0
	for k in n:
		if up_shape:
			_loc[k] = fly[k]
		elif phase == 5:
			_loc[k] = _drop(k, p, fly[k], true)
		else:
			_loc[k] = _hoist(k, p, fly[k])
	if not up_shape:
		var dt0 := _loc[0] - Vector3(_a[0], _l[0], 0.0)
		if dt0.length_squared() > 0.0:
			for k in n:
				var w := 1.0 - clampf(_tack_d[k] / (TACK_PIN * sl), 0.0, 1.0)
				if w > 0.0:
					_loc[k] -= dt0 * (w * w)
	for i in rows:
		_trow[i] = 0.0
	var hd := s_t * head
	_tack_at = piv
	_ease = 0.0
	if clearance > 0.0 and (not _obs.is_empty() or has_mast_head or loft_stay):
		if not _obs.is_empty():
			_sections(s_t, piv, ax, th)
		else:
			_secs = []
		stay_on = wb <= LOFT_FADE.y  # not while an asymmetric goes round the bow in a gybe
		_ease = _loft_ease(es, awa, s_t, piv, ax, th, hd)
	# the drawn turn moves at most LOFT_EASE_RATE from the last update's over the time since (a placement's first
	# update, or a step of 0, takes it at once)
	var turned := es * _ease  # the turn as drawn, out to the side of sgn(beta)
	if _turn_set and _turn_step > 0.0:
		var lim := LOFT_EASE_RATE * _turn_step
		turned = _turn_prev + clampf(turned - _turn_prev, -lim, lim)
	_turn_prev = turned
	_turn_set = true
	var xr := Frames.about(piv, ax, th + turned) * s_t
	for k in n:
		var lc := _loc[k]
		_mid[k] = xr * (tack + ah * lc.x + lh * lc.y + nh * lc.z)
	_fa = 0.0
	if up_shape:
		_fa = 1.0
	elif phase == 2:
		var kh := clampf((p - 0.9) / 0.1, 0.0, 1.0)
		_fa = kh * kh
	elif phase == 5:
		_fa = 1.0 - pow(p, 0.3)
	_clew0 = _mid[cols - 1]
	_layers(xr.basis * nh)


## §6.5 the clearance over its margin of each placed point `idx` (the obstacles' sections and the mast; INF when
## none is near).
func _loft_clear(pts: PackedVector3Array, hd: Vector3, lee: Vector3, idx: PackedInt32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(idx.size())
	for q in idx.size():
		var pt := pts[idx[q]]
		var cp := LOFT_MARGIN * _margin_at(pt, hd)
		var x := INF
		if has_mast_head:
			x = float(_mast_x(pt, lee)[0]) - cp
		for o in _secs:
			x = minf(x, float(_clear_x(o, pt, cp)[0]) - cp)
		if loft_stay and stay_on:
			x = minf(x, _stay_x(pt) - loft_stay_c)
		out[q] = x
	return out


## §6.5 how far a point lies ahead of the forestay, a wall LOFT_NEAR clearances either side of the stay between its
## tack fitting and the hounds (INF beside or above it).
func _stay_x(pt: Vector3) -> float:
	var z0 := stay0.dot(up)
	var z1 := stay1.dot(up)
	var pz := pt.dot(up)
	if pz < z0 or pz > z1:
		return INF
	var q := stay0 + (stay1 - stay0) * ((pz - z0) / (z1 - z0))
	if absf((pt - q).dot(port)) > LOFT_NEAR * clearance:
		return INF
	return (pt - q).dot(fwd)


## §6.5 the kite turned as a whole about its luff, away from the centreline, just far enough that no vertex is
## inside the margin of the main, the jib or the mast, or behind the forestay (at most LOFT_EASE_MAX, LOFT_STAY_MAX
## with the forestay); with the forestay not cleared that way, turned in instead when that clears it or comes nearer
## (a negative ease).
func _loft_ease(beta: float, awa: float, s_t: Transform3D, piv: Vector3, ax: Vector3, th: float,
		hd: Vector3) -> float:
	var q := PackedVector3Array()
	q.resize(n)
	for k in n:
		var lc := _loc[k]
		q[k] = s_t * (tack + ah * lc.x + lh * lc.y + nh * lc.z)
	return float(_loft_turn(1.0, beta, awa, q, piv, ax, th, hd)[0])


## §6.5 the turn's solve one way (dir +1 out, -1 in): [the turn (rad, >= 0), the worst clearance over its margin
## there (>= 0 when clear)]. After the first step only the vertices then within LOFT_NEAR clearances of the worst are
## looked at again, but with the forestay every vertex (the whole kite may come round it).
func _loft_turn(dir: float, es_f: float, awa: float, q: PackedVector3Array, piv: Vector3, ax: Vector3, th: float,
		hd: Vector3) -> Array:
	# the turn as it is drawn: es_f, the out side times the fade where sgn(beta) flips (_update_loft)
	var es := es_f * dir
	if absf(es_f) < 0.05:
		return [0.0, 0.0]
	var lee := port * Frames.sgn(awa)
	var cap := LOFT_STAY_MAX if loft_stay else LOFT_EASE_MAX
	var delta := 0.0
	var idx := PackedInt32Array()
	idx.resize(n)
	for k in n:
		idx[k] = k
	var pts := PackedVector3Array()
	pts.resize(n)
	var left := INF
	for it in LOFT_EASE_STEPS + 1:
		var xr := Frames.about(piv, ax, th + es * delta)
		for k in idx:
			pts[k] = xr * q[k]
		var x := _loft_clear(pts, hd, lee, idx)
		var worst := INF
		var at := -1
		for m in x.size():
			if x[m] < worst:
				worst = x[m]
				at = idx[m]
		left = worst
		if not (worst < 0.0) or it == LOFT_EASE_STEPS or delta >= cap:
			break
		if it == 0 and not loft_stay:
			var keep := PackedInt32Array()
			for m in x.size():
				if x[m] < worst + LOFT_NEAR * clearance:
					keep.append(idx[m])
			idx = keep
		var d := pts[at] - piv
		var rr := (d - ax * d.dot(ax)).length()
		delta = minf(delta + (-worst) / (maxf(rr, 0.5) * absf(es)), cap)
	return [delta, left]


## §6.5 the time since the last drawn update, for the turn's rate (0: no limit).
func set_turn_step(dt: float) -> void:
	_turn_step = dt


## §6.5 the turn of the last update (rad, about the luff, before the ease).
func get_turn() -> float:
	return _turn



## §4.1 the cloth projected forward (the corners held) and the tack raised, times the flying shape's share.
func _shift() -> void:
	var f := forward * sl * _fa
	var t := tack_rise * sl * _fa
	for k in n:
		_mid[k] += fwd * (f * _hold[k]) + up * (t * _rise[k])
	_tack_at += up * t


## §7.4 a flying sail on a pole flies forward of the forestay: per row the shift forward that brings its cloth
## within the stay's half width at least c_s ahead of the stay, the largest of its own and the rows' above (so it
## grows down to the foot), faded out over the top `stay_head` of the height, taken in full at the middle of the
## chord, none at the luff and 1 - `stay_leech` of it at the leech; times the flying shape's share.
func _stay() -> void:
	var z0 := stay0.dot(up)
	var z1 := stay1.dot(up)
	var sw := PackedFloat32Array()
	sw.resize(cols)
	for j in cols:
		var uc := _uc[j]
		var tt := clampf((uc - stay_luff) / (1.0 - stay_luff), 0.0, 1.0)
		sw[j] = Frames.smoothstep01(uc / stay_luff) * (1.0 - stay_leech * tt * tt * (3.0 - 2.0 * tt))
	var d_row := PackedFloat32Array()
	d_row.resize(rows)
	for i in rows:
		d_row[i] = 0.0
	for i in rows - 1:
		for j in cols:
			var pt := _mid[i * cols + j]
			var pz := pt.dot(up)
			if pz < z0 or pz > z1 or sw[j] < 0.25:
				continue
			var q := stay0 + (stay1 - stay0) * ((pz - z0) / (z1 - z0))
			var dy := absf((pt - q).dot(port))
			var kk := 1.0 - Frames.smoothstep01((dy - stay_w) / stay_c)
			var d := (stay_c - (pt - q).dot(fwd)) * kk
			if d > 0.0:
				d_row[i] = maxf(d_row[i], d / maxf(sw[j], 0.5))
	for i in range(rows - 2, -1, -1):  # never less than a row above needs
		d_row[i] = maxf(d_row[i], d_row[i + 1])
	for i in rows:
		var s := d_row[i] * Frames.smoothstep01((1.0 - _hrow[i]) / stay_head) * _fa
		if s <= 0.0:
			continue
		for j in cols:
			_mid[i * cols + j] += fwd * (s * sw[j])


## §6, §8 the local shape of every vertex, with the tack pin of §7.5
func _local(phase: int, up_shape: bool, p: float, d_cam: float, amp: float, shiver: float,
		wv: Vector3, rows_to: int = -1) -> void:
	var nk := n if rows_to < 0 else mini(rows_to, rows) * cols
	for k in nk:
		var loc: Vector3
		@warning_ignore("integer_division")
		var i := k / cols
		if kind == Kind.MAIN:
			loc = _main(k, d_cam, amp, shiver)
		elif kind == Kind.HEADSAIL:
			if up_shape:
				loc = Vector3(_a[k], _l[k], _head_n(i, _u[k], _a[k], d_cam, amp, shiver, 0.0))
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
	# §7.3 the tack stays on its fitting: the hoist and drop shapes' offset of the tack corner is taken out of the
	# cloth round it
	if kind == Kind.ASYM or kind == Kind.SYM:
		var dt0 := _loc[0] - Vector3(_a[0], _l[0], 0.0)
		if dt0.length_squared() > 0.0:
			for k in nk:
				var w := 1.0 - clampf(_tack_d[k] / (TACK_PIN * sl), 0.0, 1.0)
				if w > 0.0:
					_loc[k] -= dt0 * (w * w)


## §7.7 the rows' chord over flat chord and camber with the draw-in kd (the low rows drawn in, the cloth's length
## kept as camber)
func _clew_rows(kd: float, kl: float) -> void:
	for i in rows:
		var s := 1.0 / (1.0 + 8.0 / 3.0 * _d0row[i] * _d0row[i])
		if kd != 0.0 and _crow[i] > 0.0:
			s = minf(s * (1.0 - kd * _crow[i]), 1.0)
			_drow[i] = sqrt(maxf(1.0 / s - 1.0, 0.0) * 3.0 / 8.0)
		else:
			_drow[i] = _d0row[i]
		_srow[i] = s
	_kl = kl


## §7.7 the flying shape (up, no flutter) of vertex k with the draw-in kd and draw-down kl
func _fly_at(k: int, wv: Vector3, kd: float, kl: float) -> Vector3:
	@warning_ignore("integer_division")
	var i := k / cols
	var s := 1.0 / (1.0 + 8.0 / 3.0 * _d0row[i] * _d0row[i])
	var d := _d0row[i]
	if kd != 0.0 and _crow[i] > 0.0:
		s = minf(s * (1.0 - kd * _crow[i]), 1.0)
		d = sqrt(maxf(1.0 / s - 1.0, 0.0) * 3.0 / 8.0)
	var a0 := _a[i * cols]
	var gi := _grow[i]
	var e := d * s * gi * _c[i] * _prof[k]
	var uc := _uc[k]
	var r := Vector3(a0 + (_a[k] - a0) * s * gi + clew_out * _c[0] * _crow[i] * uc * uc,
			_l[k] - (kl - clew_lift) * _c[0] * _crow[i] * uc * uc - head_drop * sl * _h[k], 0.0)
	if foot_sag != 0.0:
		var fs := clampf(1.0 - _hrow[i] / foot_sag_h, 0.0, 1.0)
		r.y -= foot_sag * e * fs * fs
	return r - wv * e


## §7.7 the corner's bisector and the sheet's direction with (kd, kl): [b, s]
func _clew_corner(kd: float, kl: float, beta: float, base: float, piv: Vector3, ax: Vector3, s_t: Transform3D,
		wv: Vector3) -> Array:
	var x0 := Frames.about(piv, ax, base + _trow[0]) * s_t
	var x2 := Frames.about(piv, ax, base + _trow[CLEW_REACH]) * s_t
	var lc := _fly_at(cols - 1, wv, kd, kl)
	var cl := x0 * (tack + ah * lc.x + lh * lc.y + nh * lc.z)
	lc = _fly_at(cols - 1 - CLEW_REACH, wv, kd, kl)
	var ft := x0 * (tack + ah * lc.x + lh * lc.y + nh * lc.z)
	lc = _fly_at(CLEW_REACH * cols + cols - 1, wv, kd, kl)
	var et := x2 * (tack + ah * lc.x + lh * lc.y + nh * lc.z)
	var b := ((ft - cl).normalized() + (et - cl).normalized()).normalized()
	return [b, (cl - working_lead(beta)).normalized()]


## §7.7 the draw-in and draw-down that lay the clew's bisector on the sheet: two Newton steps from (0, 0) with
## difference derivatives, each clamped to its bounds
func _clew_set(beta: float, base: float, piv: Vector3, ax: Vector3, s_t: Transform3D, wv: Vector3) -> Vector2:
	var bs := _clew_corner(0.0, 0.0, beta, base, piv, ax, s_t, wv)
	var s0: Vector3 = bs[1]
	var u1 := s0.cross(up)
	if u1.length_squared() < 1e-12:
		u1 = s0.cross(fwd)
	u1 = u1.normalized()
	var u2 := u1.cross(s0)
	var kd := 0.0
	var kl := 0.0
	for it in CLEW_ITER:
		var r0 := _clew_res(kd, kl, beta, base, piv, ax, s_t, wv, u1, u2)
		var j0 := (_clew_res(kd + CLEW_STEP, kl, beta, base, piv, ax, s_t, wv, u1, u2) - r0) / CLEW_STEP
		var j1 := (_clew_res(kd, kl + CLEW_STEP, beta, base, piv, ax, s_t, wv, u1, u2) - r0) / CLEW_STEP
		var det := j0.x * j1.y - j1.x * j0.y
		if absf(det) < 1e-9:
			break
		kd = clampf(kd - (j1.y * r0.x - j1.x * r0.y) / det, CLEW_KD.x, CLEW_KD.y)
		kl = clampf(kl - (-j0.y * r0.x + j0.x * r0.y) / det, CLEW_KL.x, CLEW_KL.y)
	return Vector2(kd, kl)


func _clew_res(kd: float, kl: float, beta: float, base: float, piv: Vector3, ax: Vector3, s_t: Transform3D,
		wv: Vector3, u1: Vector3, u2: Vector3) -> Vector2:
	var bs := _clew_corner(kd, kl, beta, base, piv, ax, s_t, wv)
	var d: Vector3 = bs[0] - bs[1]
	return Vector2(d.dot(u1), d.dot(u2))


## §7.6 the working lead block: the starboard lead mirrored to the side of beta (starboard for beta > 0)
func working_lead(beta: float) -> Vector3:
	var y := sheet_lead.dot(port)
	return sheet_lead + port * (-Frames.sgn(beta) * absf(y) - y)


## §7.6 the flying shape's share of the last update (0 down or bagged, 1 up)
func sheet_weight() -> float:
	return _fa


## §7.6 the clew the sheet leaves from: as placed, before the clearance push of §7.4
func sheet_clew() -> Vector3:
	return _clew0


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
	var xr := Frames.about(piv, ax, base + _trow[0]) * s_t
	var cl := xr * (tack + ah * lc.x + lh * lc.y + nh * lc.z)
	var sk := Frames.sgn((cl - mast_step).dot(port))
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
	reach += RUN_ON * clearance  # the bounds cover the leech's run-on
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
	var bh := 1.0
	var q0 := _sec_pt(sh, r, 0, t)
	for j in cn - 1:
		var q1 := _sec_pt(sh, r, j + 1, t)
		var d := q1 - q0
		var l2 := d.length_squared()
		# the last segment runs on past the leech by RUN_ON clearances (§7.4)
		var hi := 1.0 + RUN_ON * clearance / sqrt(l2) if j == cn - 2 and l2 > 1e-12 else 1.0
		var sp := clampf((ph - q0).dot(d) / l2, 0.0, hi) if l2 > 1e-12 else 0.0
		var q := q0 + d * sp
		var d2 := (ph - q).length_squared()
		if d2 < best:
			best = d2
			bj = j
			bs = sp
			bq = q
			bd = d
			bh = hi
		q0 = q1
	if (bj == 0 and bs <= 0.0) or (bj == cn - 2 and bs >= bh) or bd.length_squared() < 1e-12:
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
	var y := clampf(p.distance_to(_tack_at) / (5.0 * clearance), 0.0, 1.0)
	return clearance * x * x * (3.0 - 2.0 * x) * y * y * (3.0 - 2.0 * y)


## §7.4 the ease: the extra turn about the luff that brings the leech samples clear of the obstacles.
func _ease_for(beta: float, s_t: Transform3D, piv: Vector3, ax: Vector3, base: float, hd: Vector3) -> float:
	var delta := 0.0
	var es := Frames.sgn(beta)
	for it in 4:
		var worst := INF
		var rr := 1.0
		var i := 0
		while true:  # rows 0, 3, 6, ... and the one below the head
			var lc := _loc[i * cols + cols - 1]
			var th := base + _trow[i] + es * delta
			var pt := (Frames.about(piv, ax, th) * s_t) * (tack + ah * lc.x + lh * lc.y + nh * lc.z)
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
	var lee := port * Frames.sgn(awa)
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


## §6.2 a headsail's offset off its rest plane; `us` is the furled fraction of §8.3 (0 when up or on a halyard)
func _head_n(i: int, u: float, a: float, d_cam: float, amp: float, shiver: float, us: float) -> float:
	var fl := amp * shiver * u * sin(phi - a)
	if cam_cap > 0.0:
		return 0.5 * d_cam * (pow(u, 4) - C_HOOK * u) + fl
	var u0 := _u0row[i] if us <= 0.0 else 0.0
	var ul := _ulrow[i] - us
	var x := clampf((u - u0) / maxf(ul - u0, 1e-3), 0.0, 1.0)
	var c := _c[i] * clampf((ul - u0) / maxf(_ulrow[i] - _u0row[i], 1e-3), 0.0, 1.0)
	var hh := 2.0 * _hrow[i] - 1.0
	var g := x * (1.0 - x) * (2.0 - x) / JIB_PROFILE_MAX
	return 0.5 * d_cam * (pow(ul, 4) - C_HOOK * ul) * x - _jcam * (1.0 - 0.15 * hh * hh) * c * g + fl


## §8.2
func _halyard(k: int, p: float, d_cam: float, amp: float, shiver: float) -> Vector3:
	var hc := 1.0 - p
	if _h[k] >= hc:
		@warning_ignore("integer_division")
		return Vector3(_a[k], _l[k] - hc * sl, _head_n(k / cols, _u[k], _a[k], d_cam, amp, shiver, 0.0))
	return Vector3(_a[k], _a[k] * kappa + 0.03, 0.02 * sl * sin(12.0 * _h[k]))


## §8.3
func _furl(k: int, p: float, d_cam: float, amp: float, shiver: float) -> Vector3:
	var ac := (1.0 - p) * sa
	var r := furl_radius * (0.4 + 0.6 * (1.0 - p))
	if _a[k] - a_min < ac:
		var t := 6.0 * PI * _uc[k]
		return Vector3(a_min + r * (1.0 - cos(t)), _l[k], r * sin(t))
	var a2 := _a[k] - ac
	@warning_ignore("integer_division")
	return Vector3(a2, _l[k], _head_n(k / cols, (a2 - a_min) / sa, a2, d_cam, amp, shiver, 1.0 - p))


## §6.3, §6.4 the flying shape
func _fly(k: int, i: int, wv: Vector3, shiver: float) -> Vector3:
	var uc := _uc[k]
	var s := _srow[i]
	var a0 := _a[i * cols]
	var gi := _grow[i]
	var e := _drow[i] * s * gi * _c[i] * _prof[k]
	var i2 := 0.33 * flutter_amp * shiver
	var q := phi - 7.0 * uc
	var m := Vector3(wv.x + 0.1 * i2 * sin(q), wv.y, wv.z + i2 * cos(q))
	# §7.7 the draw-down; §4.1 the clew raised and let out, the head dropped, the girth
	var r := Vector3(a0 + (_a[k] - a0) * s * gi + clew_out * _c[0] * _crow[i] * uc * uc,
			_l[k] - (_kl - clew_lift) * _c[0] * _crow[i] * uc * uc - head_drop * sl * _h[k], 0.0) - m * e
	if foot_sag != 0.0:
		# §6.4, §4.1 the lower panels' belly sags, so the foot curves round and down
		var fs := clampf(1.0 - _hrow[i] / foot_sag_h, 0.0, 1.0)
		r.y -= foot_sag * e * fs * fs
	if kind == Kind.SYM:
		var h := _h[k]
		var g := maxf(0.0, shiver - uc) * (1.0 - (2.0 * h - 1.0) * (2.0 * h - 1.0))
		r.x += (a0 + (_amid[i] - a0) * s * gi - r.x) * 0.5 * g
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


## §8.5; slide (a lofted kite, §6.5): the cloth still up slides down the luff keeping its flying shape instead of
## relaxing to the flat sail (which, near the centreline, would cross the forestay)
func _drop(k: int, c: float, fly: Vector3, slide: bool = false) -> Vector3:
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
		if slide:
			tg = Vector3(fly.x + w, fly.y - (thr - l_min), fly.z + w)
		else:
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


## §6.5 whether the sail is drawn as a lofted kite.
func is_loft() -> bool:
	return loft
