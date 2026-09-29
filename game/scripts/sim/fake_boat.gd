class_name FakeBoat
extends RefCounted
## Placeholder boat for FakeSim: a GDScript sketch of boat.md §5 and sails.md §4-§5 driven by the class's
## generated tables, heave, pitch and wave roll on the sea it is given (§5.6, no wobble), no collisions or wind
## shadow. Good enough to drive cameras, controls
## and the HUD until the core binding (WM-016.01) replaces it. Not deterministic across platforms and not the
## reference: the core is.

const P := SimSource.Phase
const FILT_A := 0.0243902430
const V_MAX := 40.0
const DT := SimSource.DT

var d: BoatClassData
var s := SimSource.BoatState.new()
var ctl := SimSource.BoatControls.new()
var out := SimSource.BoatOutputs.new()

var front := -1
var queue: Array[SimSource.SailStep] = []
var queue_pos := 0
var queue_progress := 0.0
var sail_st: Array[SimSource.SailState] = []
var sail_out: Array[SimSource.SailOutput] = []

var prev_pose := SimSource.RenderPose.new()
var cur_pose := SimSource.RenderPose.new()
## sea.md §5.1 hull sample points (body x forward, y port) and their fit sums
var hull_points := PackedVector2Array()
var _hp_mx := 0.0
var _hp_my := 0.0
var _hp_sxx := 0.0
var _hp_syy := 0.0
## §5.6 mean sea height under the hull at the last tick (m)
var wave_hm := 0.0


func _init(data: BoatClassData) -> void:
	d = data
	_hull_points()
	for i in d.info.sails.size():
		sail_st.append(SimSource.SailState.new())
		sail_out.append(SimSource.SailOutput.new())


## boat.md §6.6 (simplified): place, main and `front_sail` up, trimmed.
func reset(pos_x: float, pos_y: float, psi: float, v: float, front_sail: int, auto_trim: bool,
		wind_speed: float, wind_from: float) -> void:
	s = SimSource.BoatState.new()
	s.pos_x = pos_x
	s.pos_y = pos_y
	s.psi = Frames.wrap_2pi(psi)
	s.v = v
	ctl = SimSource.BoatControls.new()
	ctl.auto_trim = auto_trim
	front = front_sail
	queue.clear()
	queue_pos = 0
	queue_progress = 0.0
	for i in sail_st.size():
		sail_st[i] = SimSource.SailState.new()
		sail_st[i].phase = P.UP if (i == d.info.main_sail or i == front_sail) else P.DOWN
	_wind_triangle(wind_speed, wind_from)
	_trim(true)
	s.v_filt = v
	s.sog_filt_x = v * sin(s.psi)
	s.sog_filt_y = v * cos(s.psi)
	_store_pose()
	prev_pose = cur_pose
	cur_pose = SimSource.RenderPose.new()
	_store_pose()


func busy() -> bool:
	return queue_pos < queue.size()


## ---- sails.md §4.2 requests ----

func hoist(x: int) -> int:
	if x < 0 or x >= sail_st.size() or x == d.info.main_sail:
		return SimSource.Request.REJECTED
	if not busy():
		if x == front:
			return SimSource.Request.REJECTED
		var steps: Array[SimSource.SailStep] = [
			SimSource.SailStep.new(x, P.PREPARE_HOIST), SimSource.SailStep.new(x, P.HOISTING),
			SimSource.SailStep.new(x, P.UP)]
		if front >= 0:
			steps.append_array([SimSource.SailStep.new(front, P.PREPARE_DROP),
				SimSource.SailStep.new(front, P.DROPPING), SimSource.SailStep.new(front, P.DOWN)])
		_set_queue(steps)
		return SimSource.Request.ACCEPTED
	var run: SimSource.SailStep = queue[queue_pos]
	var p := sail_st[run.sail].progress
	if x == front and run.sail != front and (run.phase == P.PREPARE_HOIST or run.phase == P.HOISTING):
		_cancel_hoist(run, p)
		return SimSource.Request.ACCEPTED
	if x == run.sail and _lone(run.sail, [P.PREPARE_DROP, P.DROPPING, P.DOWN]) \
			and (run.phase == P.PREPARE_DROP or run.phase == P.DROPPING):
		if run.phase == P.PREPARE_DROP:
			_set_queue([SimSource.SailStep.new(x, P.UP)])
		else:
			_set_queue([SimSource.SailStep.new(x, P.DROPPING, true), SimSource.SailStep.new(x, P.UP)])
			queue_progress = 1.0 - p
		return SimSource.Request.ACCEPTED
	return SimSource.Request.REJECTED


func drop_front() -> int:
	if not busy():
		if front < 0:
			return SimSource.Request.REJECTED
		_set_queue([SimSource.SailStep.new(front, P.PREPARE_DROP), SimSource.SailStep.new(front, P.DROPPING),
			SimSource.SailStep.new(front, P.DOWN)])
		return SimSource.Request.ACCEPTED
	var run: SimSource.SailStep = queue[queue_pos]
	if front < 0 and _lone(run.sail, [P.PREPARE_HOIST, P.HOISTING, P.UP]) \
			and (run.phase == P.PREPARE_HOIST or run.phase == P.HOISTING):
		_cancel_hoist(run, sail_st[run.sail].progress)
		return SimSource.Request.ACCEPTED
	return SimSource.Request.REJECTED


func _cancel_hoist(run: SimSource.SailStep, p: float) -> void:
	if run.phase == P.PREPARE_HOIST:
		_set_queue([SimSource.SailStep.new(run.sail, P.DOWN)])
	else:
		_set_queue([SimSource.SailStep.new(run.sail, P.HOISTING, true), SimSource.SailStep.new(run.sail, P.DOWN)])
		queue_progress = 1.0 - p


func _lone(sail: int, phases: Array) -> bool:
	if queue.size() != 3:
		return false
	for i in 3:
		if queue[i].sail != sail or queue[i].phase != phases[i] or queue[i].reversed:
			return false
	return true


func _set_queue(steps: Array) -> void:
	queue.clear()
	for st in steps:
		queue.append(st)
	queue_pos = 0
	queue_progress = 0.0


## ---- one tick ----

## One tick. `sea`: (x, y) -> sea height at this tick's time; an invalid Callable is flat water.
func step(wind_speed: float, wind_from: float, sea := Callable()) -> void:
	prev_pose = cur_pose
	cur_pose = SimSource.RenderPose.new()
	var dy: Dictionary = d.dyn
	_wind_triangle(wind_speed, wind_from)
	var tack := Frames.sgn(s.twa)
	# 5.2 helm
	var hr := float(dy["helm_rate"]) * DT
	s.h += clampf(ctl.h_cmd - s.h, -hr, hr)
	# 5.3 sail changes
	_advance()
	# 5.4 trim
	_trim(false)
	var drv := front if front >= 0 else d.info.main_sail
	var eps := sail_out[drv].trim_error
	# 5.5 lookups
	var cfg: Dictionary = d.configs.get(front, d.configs[-1])
	var twa_abs := absf(s.twa)
	var awa_abs := absf(s.awa)
	out.polar_speed = cfg["polar"].at(s.tws, twa_abs)
	var ts: PerfTable = cfg["trim_speed"]
	var th: PerfTable = cfg["trim_heel"]
	out.trim_speed = ts.at(s.tws, awa_abs, eps) if ts else 1.0
	out.trim_heel = th.at(s.tws, awa_abs, eps) if th else 1.0
	var accel: float = cfg["accel"].at(s.tws, twa_abs)
	var heel_mag: float = cfg["heel"].at(s.tws, twa_abs)
	out.man_coef = _man_coef()
	# 5.6 waves: heave and pitch (no wobble)
	var wave_roll := _waves(sea)
	# 5.7 heel: a damped spring toward the target
	var heel_max := float(dy["heel_max"])
	var heel_sail := clampf(-tack * heel_mag * out.trim_heel, -heel_max, heel_max)
	out.heel_target = clampf(heel_sail + float(dy.get("wave_roll_gain", 0.3)) * wave_roll, -heel_max, heel_max)
	var w := float(dy["heel_freq"])
	var k1 := w * w * DT
	var k2 := 1.0 - 2.0 * float(dy["heel_damping"]) * w * DT
	s.phi_rate = k2 * s.phi_rate + k1 * (out.heel_target - s.phi)
	s.phi += s.phi_rate * DT
	var heel_limit := float(dy["heel_limit"])
	if absf(s.phi) > heel_limit:
		s.phi = Frames.sgn(s.phi) * heel_limit
		s.phi_rate = 0.0
	# 5.8 speed
	var hsf: PerfTable = d.tables["heel_speed_factor"]
	out.heel_coef = hsf.at(absf(s.phi)) if hsf else 1.0
	out.surf_coef = 1.0
	var trim_drive := out.trim_speed if out.polar_speed > 0.0 else 1.0
	out.target_speed = out.polar_speed * trim_drive * out.man_coef * out.heel_coef * ctl.performance_scale
	var err := out.target_speed - s.v
	var a := 0.0
	if err > 0.0:
		a = accel
		if err < DT * a:
			a = err / DT
	else:
		var err_d := (maxf(out.target_speed, 0.0) if s.v > 0.0 else out.target_speed) - s.v
		var wind := float(dy.get("decel_windage", 0.0)) * s.aws * s.aws * maxf(cos(s.awa), 0.0)
		a = float(dy["decel_linear"]) * err_d - float(dy["decel_const"]) - wind
		if absf(err_d) < DT * absf(a):
			a = err_d / DT
	s.v += DT * a
	var drag_t: PerfTable = d.tables["rudder_drag_luff" if s.h * tack > 0.0 else "rudder_drag_bear"]
	var drag := drag_t.at(absf(s.v), absf(s.h)) if drag_t else 0.0
	s.v -= Frames.sgn(s.v) * minf(DT * drag, absf(s.v))
	s.v = clampf(s.v, -V_MAX, V_MAX)
	# 5.9 turning
	var turn_full := float(dy["turn_radius_full"])
	var turn_off := float(dy["turn_radius_offset"])
	var turn_arc := 0.0
	var n := absf(s.h)
	if n >= 1e-5:
		var r := maxf((turn_full + turn_off) / n - turn_off, 0.5)
		turn_arc = (s.v / r) * Frames.sgn(s.h)
	var fall := 0.0
	if cfg["fall_off"]:
		fall = cfg["fall_off"].at(s.v, twa_abs)
	# yaw inertia (boat.md §5.9): the hull's yaw rate follows its steady value over yaw_time
	var yaw_a := DT / (float(dy.get("yaw_time", 0.0)) + DT)
	s.yaw_rate += yaw_a * ((turn_arc - tack * fall) - s.yaw_rate)
	out.turn_rate = s.yaw_rate
	var dpsi := out.turn_rate * DT
	var mid := s.psi + 0.5 * dpsi
	s.pos_x += s.v * sin(mid) * DT
	s.pos_y += s.v * cos(mid) * DT
	s.psi = Frames.wrap_2pi(s.psi + dpsi)
	# 5.10 outputs
	var gx := s.v * sin(s.psi)
	var gy := s.v * cos(s.psi)
	out.sog = sqrt(gx * gx + gy * gy)
	out.vmg = s.v * cos(s.twa)
	s.v_filt += FILT_A * (s.v - s.v_filt)
	s.sog_filt_x += FILT_A * (gx - s.sog_filt_x)
	s.sog_filt_y += FILT_A * (gy - s.sog_filt_y)
	if sqrt(s.sog_filt_x * s.sog_filt_x + s.sog_filt_y * s.sog_filt_y) >= 1e-4:
		out.cog = Frames.compass(s.sog_filt_x, s.sog_filt_y)
	out.wind_speed_clean = wind_speed
	_store_pose()


## sea.md §5.1: the listed points, or 8 from lwl and bwl.
func _hull_points() -> void:
	var dy: Dictionary = d.dyn
	hull_points.clear()
	var listed = dy.get("hull_points")
	if listed is Array and not listed.is_empty():
		for q in listed:
			hull_points.append(Vector2(float(q[0]), float(q[1])))
	else:
		var l := float(dy.get("lwl", d.info.loa * 0.9))
		var w := float(dy.get("bwl", d.info.beam_max * 0.75))
		for q in [[0.45, 0.0], [-0.45, 0.0], [0.25, 0.35], [0.25, -0.35], [0.0, 0.35], [0.0, -0.35],
				[-0.25, 0.35], [-0.25, -0.35]]:
			hull_points.append(Vector2(q[0] * l, q[1] * w))
	_hp_mx = 0.0
	_hp_my = 0.0
	for q in hull_points:
		_hp_mx += q.x
		_hp_my += q.y
	_hp_mx /= hull_points.size()
	_hp_my /= hull_points.size()
	_hp_sxx = 0.0
	_hp_syy = 0.0
	for q in hull_points:
		_hp_sxx += (q.x - _hp_mx) * (q.x - _hp_mx)
		_hp_syy += (q.y - _hp_my) * (q.y - _hp_my)


## boat.md §5.6 heave and pitch springs, sea.md §5.2 sampling; returns the wave roll for the heel target.
func _waves(sea: Callable) -> float:
	var dy: Dictionary = d.dyn
	var hm := 0.0
	var wave_pitch := 0.0
	var wave_roll := 0.0
	if sea.is_valid():
		var fx := sin(s.psi)
		var fy := cos(s.psi)
		var lx := -fy
		var ly := fx
		var h := PackedFloat64Array()
		for q in hull_points:
			var hk: float = sea.call(s.pos_x + q.x * fx + q.y * lx, s.pos_y + q.x * fy + q.y * ly)
			h.append(hk)
			hm += hk
		hm /= hull_points.size()
		var gx := 0.0
		var gy := 0.0
		for k in hull_points.size():
			gx += (h[k] - hm) * (hull_points[k].x - _hp_mx)
			gy += (h[k] - hm) * (hull_points[k].y - _hp_my)
		wave_pitch = atan(gx / _hp_sxx) if _hp_sxx > 1e-6 else 0.0
		wave_roll = atan(gy / _hp_syy) if _hp_syy > 1e-6 else 0.0
	wave_hm = hm
	var heave_a := DT / (float(dy.get("heave_time", 0.25)) + DT)
	s.z += heave_a * ((hm + float(dy.get("waterline_offset", 0.0))) - s.z)
	var w := float(dy.get("pitch_freq", 3.0))
	var k1 := w * w * DT
	var k2 := 1.0 - 2.0 * float(dy.get("pitch_damping", 0.7)) * w * DT
	var theta_target := float(dy.get("wave_pitch_gain", 1.0)) * wave_pitch
	s.theta_rate = k2 * s.theta_rate + k1 * (theta_target - s.theta)
	s.theta += s.theta_rate * DT
	return wave_roll


func _store_pose() -> void:
	var p := cur_pose
	p.pos_x = s.pos_x
	p.pos_y = s.pos_y
	p.z = s.z
	p.psi = s.psi
	p.theta = s.theta
	p.phi = s.phi
	p.h = s.h
	p.twa = s.twa
	p.twd_from = s.twd_from


func render_pose(alpha: float) -> SimSource.RenderPose:
	var a := prev_pose
	var b := cur_pose
	var r := SimSource.RenderPose.new()
	r.pos_x = lerpf(a.pos_x, b.pos_x, alpha)
	r.pos_y = lerpf(a.pos_y, b.pos_y, alpha)
	r.z = lerpf(a.z, b.z, alpha)
	r.psi = Frames.wrap_2pi(a.psi + Frames.angle_diff(b.psi, a.psi) * alpha)
	r.theta = lerpf(a.theta, b.theta, alpha)
	r.phi = lerpf(a.phi, b.phi, alpha)
	r.h = lerpf(a.h, b.h, alpha)
	r.twa = Frames.wrap_pi(a.twa + Frames.angle_diff(b.twa, a.twa) * alpha)
	r.twd_from = Frames.wrap_2pi(a.twd_from + Frames.angle_diff(b.twd_from, a.twd_from) * alpha)
	return r


## boat.md §5.1 with no current
func _wind_triangle(wind_speed: float, wind_from: float) -> void:
	var tx := -wind_speed * sin(wind_from)
	var ty := -wind_speed * cos(wind_from)
	s.tws = sqrt(tx * tx + ty * ty)
	if s.tws >= 1e-4:
		s.twd_from = Frames.compass(-tx, -ty)
	var ax := tx - s.v * sin(s.psi)
	var ay := ty - s.v * cos(s.psi)
	s.aws = sqrt(ax * ax + ay * ay)
	if s.aws >= 1e-4:
		s.awd_from = Frames.compass(-ax, -ay)
	s.twa = Frames.wrap_pi(s.twd_from - s.psi)
	s.awa = Frames.wrap_pi(s.awd_from - s.psi)


func _duration(sail: int, phase: int) -> float:
	var h: Dictionary = d.sail_data[sail]["handling"]
	var key := ""
	match phase:
		P.PREPARE_HOIST: key = "prepare_hoist_time"
		P.HOISTING: key = "hoist_time"
		P.PREPARE_DROP: key = "prepare_drop_time"
		P.DROPPING: key = "drop_time"
	return h[key].at(s.tws, absf(s.twa))


## sails.md §4.3
func _advance() -> void:
	var dt_left := DT
	while queue_pos < queue.size():
		var st: SimSource.SailStep = queue[queue_pos]
		var ss := sail_st[st.sail]
		ss.phase = st.phase
		if st.phase == P.UP:
			front = st.sail
			ss.progress = 0.0
		elif st.phase == P.DOWN:
			if front == st.sail:
				front = -1
			ss.progress = 0.0
		else:
			var dur := _duration(st.sail, st.phase)
			queue_progress = queue_progress + dt_left / dur if dur > 1e-5 else 1.0
			var q := clampf(queue_progress, 0.0, 1.0)
			ss.progress = 1.0 - q if st.reversed else q
			if queue_progress < 1.0:
				break
			if dur > 1e-5:
				dt_left = (queue_progress - 1.0) * dur
		queue_pos += 1
		queue_progress = 0.0
	if queue_pos >= queue.size():
		queue.clear()
		queue_pos = 0
		queue_progress = 0.0


## sails.md §4.5
func _man_coef() -> float:
	if not busy():
		return 1.0
	var st: SimSource.SailStep = queue[queue_pos]
	var sl: float = d.sail_data[st.sail]["slow"].get(st.phase, 1.0)
	return sl + (1.0 - sl) * absf(sin(0.5 * s.twa))


func _hoist_factor(i: int) -> float:
	if d.info.sails[i].type == "spinnaker_sym":
		return 1.0
	match sail_st[i].phase:
		P.HOISTING:
			return clampf(2.0 * sail_st[i].progress * sail_st[i].progress, 0.1, 1.0)
		P.UP, P.PREPARE_DROP:
			return 1.0
	return 0.1


## sails.md §5 for every sail
func _trim(place: bool) -> void:
	var awa_abs := absf(s.awa)
	var sg := Frames.sgn(s.awa)
	var n := sail_st.size()
	var main := d.info.main_sail
	var m_opt := PackedFloat64Array()
	m_opt.resize(n)
	var m_s := PackedFloat64Array()
	m_s.resize(n)
	for i in n:
		var si: SimSource.SailInfo = d.info.sails[i]
		var cfg: Dictionary = d.configs.get(front if i == main else i, d.configs[-1])
		var t: PerfTable = cfg["optimal"].get(i)
		m_opt[i] = clampf(t.at(s.tws, awa_abs) if t else si.sheet_min, si.sheet_min, si.sheet_max)
	for i in n:
		var si: SimSource.SailInfo = d.info.sails[i]
		if ctl.auto_trim:
			m_s[i] = m_opt[i]
		elif i != main or front < 0:
			m_s[i] = si.sheet_min + ctl.sheet_cmd * (si.sheet_max - si.sheet_min)
	if not ctl.auto_trim and front >= 0:
		m_s[main] = clampf((m_s[front] - m_opt[front]) + m_opt[main], 0.0, d.info.sails[main].sheet_max)
	for i in n:
		var si: SimSource.SailInfo = d.info.sails[i]
		var sd: Dictionary = d.sail_data[i]
		var o := sail_out[i]
		var st := sail_st[i]
		if ctl.let_fly:
			m_s[i] = awa_abs
		var lim := si.sheet_max
		if sd["sheet_max_by_heel"]:
			lim = minf(lim, sd["sheet_max_by_heel"].at(absf(s.phi)))
		var m := m_s[i] if ctl.let_fly else clampf(m_s[i], si.sheet_min, lim)
		o.k_h = _hoist_factor(i)
		o.m_opt = m_opt[i]
		o.beta_opt = -sg * m_opt[i]
		var beta_t := -sg * m * o.k_h
		if si.type == "spinnaker_asym" and st.beta * beta_t < -1e-5 and not place:
			beta_t = (1.0 if st.beta >= 0.0 else -1.0) * 4.71238898
		elif awa_abs < absf(beta_t):
			beta_t = Frames.sgn(beta_t) * awa_abs
		o.beta_t = beta_t
		o.motion = SimSource.Motion.IDLE
		var dd := beta_t - st.beta
		if place or absf(dd) <= 1e-5 or si.type == "spinnaker_sym":
			st.beta = Frames.wrap_pi(beta_t)
		else:
			var rate: float = sd["rate_out"]
			o.motion = SimSource.Motion.EASING
			if (-s.awa - st.beta) * dd <= 0.0:
				rate = sd["rate_in"]
				o.motion = SimSource.Motion.SHEETING
			var stp := ((absf(dd) + 0.0872664626) * DT) * rate
			if absf(dd) < 0.0174532924:
				o.motion = SimSource.Motion.IDLE
			st.beta = Frames.wrap_pi(st.beta + Frames.sgn(dd) * minf(stp, absf(dd)))
		if sd["pole_angle"]:
			var pole_t: float = -sg * sd["pole_angle"].at(s.tws, awa_abs)
			st.pole = pole_t * o.k_h if place else st.pole + ((pole_t * o.k_h) - st.pole) * (DT * sd["pole_rate"])
		else:
			st.pole = st.beta
		o.trim_error = -sg * Frames.wrap_pi(st.beta - o.beta_opt)
		var dl := st.beta + s.awa
		if not sd["shiver_free"] and absf(dl) >= PI * 0.5:
			o.luff_shiver = 0.0
		else:
			var sa: float = sd["shiver_angle"].at(s.tws) if sd["shiver_angle"] else 0.1
			var q := clampf(absf(sin(dl)) / (sin(sa) + 1e-4), 0.0, 1.0)
			o.luff_shiver = 1.0 - q * q
		o.backed = Frames.sgn(st.beta) == Frames.sgn(s.awa) and absf(st.beta) > 0.02
