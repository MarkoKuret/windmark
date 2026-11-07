class_name RaceHudValues
extends RefCounted
## The race values behind the HUD for the viewed boat (hud.md §3.2, §4, §6 distance to layline, §7 to §13),
## computed every tick from the race and rules readers of SimSource (race.md, rules.md §11): the start
## countdown, flags and signal banners, the start line panel (distance, time to line, time to burn, bias, OVER,
## OCS), the next mark, VMG and VMC, the layline distance, the shift meter, the sail hint, the rank with its
## hysteresis, gaps and splits, rules awareness messages, the penalty panel, protest and hail prompts, the radar
## colours, the event feed, banners and the results, and the race end of the player's own boat (§13.1 to §13.3: the
## finish card, when her race is over, the summary of her race). Timers count ticks, so the values are a function of the
## sim's states and events. Without a race (FakeSim, free sailing) `active` is false and nothing else is set.
## Player-facing text has no em dashes.

## hud_event(kind, data) for audio and anything else that follows the race: "signal" {kind, flag},
## "penalty" {boat, rule, other}, "penalty_served", "rule_warning" {giver, holder, rule}, "finished" {place},
## "protest_prompt" {culprit, rule}, "ocs" {flag}, "results"
signal hud_event(kind: String, data: Dictionary)

const DT := SimSource.DT
const RANK_HOLD_TICKS := 40  # hud.md §10: 2 s
const BANNER_SIGNAL := 60  # 3 s
const BANNER_SPLIT := 80  # 4 s
const BANNER_PENALTY := 80
const BANNER_SERVED := 40
const BANNER_DSQ := 200
const FEED_TICKS := 160  # 8 s
const FEED_LINES := 6
const PENALTY_RECENT := 100  # hud.md §12.1: 5 s
const HINT_TICKS := 100  # hud.md §4 sail hint: 5 s
const RESET_TICKS := 60  # hud.md §12.1: the reset text, 3 s
const START_SUMMARY_S := 30.0
const MIN_KN := 0.3 * HudFormat.KNOT
## hud.md §13.1 the finish card: 5 s, fading in over 0.3 s and out over the last 0.8 s
const CARD_TICKS := 100
const CARD_IN_S := 0.3
const CARD_OUT_S := 0.8

enum Tint { WHITE, RED, ORANGE, CYAN, YELLOW, GREEN, GREY }
## radar pulse (hud.md §8): none, Warning 2 Hz, Breach 4 Hz with an outline
enum Pulse { NONE, WARNING, BREACH }


## one boat on the radar (hud.md §8)
class Contact:
	var boat := -1
	var tint := Tint.WHITE
	var pulse := Pulse.NONE
	var ghost := false


## the rules awareness line (hud.md §11)
class Message:
	var text := ""
	var tint := Tint.WHITE
	var other := -1
	var breach := false
	var priority := 99


## a timed line (banner or feed)
class Line:
	var text := ""
	var tint := Tint.WHITE
	var ticks := 0
	var full := false
	## a feed line about the viewed boat or the whole race (signals, starts): the Glance feed shows only these
	var own := true

	func _init(t := "", c := Tint.WHITE, n := 0, f := false) -> void:
		text = t
		tint = c
		ticks = n
		full = f


var active := false
var boat := -1
## boat index -> display name / skipper / AI level ("" for humans); defaults "You" and "Boat n"
var names := {}
var skippers := {}
var ai_levels := {}
## the player's own boat (named "You" unless `names` says otherwise); -1 = none
var own_boat := 0
## rules.md §9.5 limits (lobby settings)
var dsq_pending := 3
var dsq_total := 6

# ---- race and start (§9) ----
var state := 0
var race_time := 0.0
var sequence := 0
var prep_flag := 1
var warning_time := 300.0
## flags shown now: "class", "P", "I", "Z", "U", "black", "X", "1st substitute"
var flags: Array[String] = []
var start_panel := false
var line_dist := 0.0  # m, signed (negative behind), or the distance to the nearer end
var line_end := false
var t_line := NAN
var burn := NAN  # s, positive = early
var bias := 0.0  # rad, favoured end's advantage angle |beta|
var bias_end := ""  # "PIN" / "BOAT" / ""
var bias_m := 0.0
var over := false
var over_text := ""
var ocs := false
var ocs_text := ""
var started := false
var finished := false
var t_finish := 0.0

# ---- next mark (§7), performance (§4), laylines (§6), shift (§3.2), hint (§4) ----
var next_step := -1
var next_kind := -1
var next_name := ""
var next_sides: Array[int] = []  # RaceText.Side per buoy
var next_dist := INF
var next_bearing := 0.0
var next_rel := 0.0
var lap := 0
var laps := 1
var leg := 0
var legs := 0
var leg_type := ""  # "beat", "run", "reach", ""
var eta := NAN  # s
var vmg := 0.0
var vmc := 0.0
var target_speed := 0.0
var target_twa := NAN
var layline_dist := NAN
var layline_time := NAN
var overstood := NAN
var shift := 0.0  # rad, the shift of the current tack
var shift_kind := ""  # "lift", "header", "" (below 2 degrees or hidden)
var sail_hint := ""
## hud.md §6 laylines of the next step for the radar, refreshed at 2 Hz: [{a (mark), b (far end), tack}]
var laylines: Array = []

# ---- position (§10) ----
var rank := 0
var fleet := 0
var shown_order := PackedInt32Array()
var leader := -1
var gap_dist := 0.0
var gap_time := NAN
var gap_estimate := false
var gap_at := ""  # the split's mark label
var ahead := -1
var ahead_dist := 0.0
var behind := -1
var behind_dist := 0.0

# ---- rules (§11, §12) ----
var message: Message = null
var protest_culprit := -1
var protest_rule := 0
var protest_ticks := 0
var hail_available := false
var hailed_by := -1
var penalty_visible := false
var pending := 0
var penalty_rule := 0
var penalty_other := -1
var turn_deg := 0.0
## the direction of the turn being sailed: +1 clockwise seen from above (to starboard), -1 anticlockwise, 0 none
var turn_sign := 0
var turn_target := 360.0
var turn_tack := false
var turn_gybe := false
var turn_text := ""
var deadline := -1.0
var dsq_warning := false
var dsq := false

# ---- radar, feed, banners, results (§8, §13) ----
var contacts: Array[Contact] = []
var banner: Line = null
var feed: Array[Line] = []
var results_visible := false
var results_final := false
## [{place, boat, name, skipper, ai, time (s or NAN), gap (s or NAN), code, points, projected, status}]
var result_rows: Array = []
## boat index -> sail number ("7") and boat name ("Kestrel", the player's too); the results screen's Sail and Boat
var sail_numbers := {}
var boat_names := {}

# ---- race end of the player's own boat (§13.1 to §13.3) ----
## the finish card: {} none, else {kind ("finish", "ret", "dnf"), big, caption, gap, time, line, win}
var card := {}
## ticks since the card came up
var card_ticks := 0
## hud.md §13.2: the player's race is over, why ("finished", "retired", "dsq", "ghost", "dnf", "abandoned") and the
## ticks since
var race_over := false
var end_reason := ""
var over_ticks := 0
## §13.3 records: start time after the gun (NAN before), OCS at the start; roundings [{step, label, place, gap}];
## penalties [{rule, other, state ("pending", "done", "late", "cancelled")}]; the disqualification's reason; the
## top boat speed (m/s) and the ground track sailed (m) while racing
var start_t := NAN
var start_ocs := false
var roundings: Array = []
var penalties: Array = []
var dsq_reason := ""
var top_speed := 0.0
var distance_sailed := 0.0

var _sim: SimSource
var _course := {}
var _labels := {}
var _loa := 7.0
var _started_filters := false
var _twd2 := Vector2.ZERO  # clean wind dir (from) as a unit vector, tau 2 s
var _twd5 := Vector2.ZERO
var _twd10 := Vector2.ZERO
var _twd180 := Vector2.ZERO
var _tws10 := 0.0
var _leg_prev := ""
var _order_cand := PackedInt32Array()
var _order_since := 0
var _finished_count := 0
var _last_penalty_tick := -1000000
var _hint_best := -2
var _hint_ticks := 0
var _summary_done := false
var _track_last := Vector2.INF
var _tick := 0
var _events_tick := -1


func _k(tau: float) -> float:
	return 1.0 - exp(-DT / tau)


func name_of(b: int) -> String:
	if names.has(b):
		return names[b]
	return "You" if b == own_boat else "Boat %d" % (b + 1)


## the verb for a boat's name: "Nora finishes", "You finish"
func _verb(b: int, third: String, second: String) -> String:
	return second if b == own_boat and not names.has(b) else third


## the AI badge of a boat: `ai_levels` when set, else the sim's AI level ("" for humans)
func ai_badge(b: int) -> String:
	if ai_levels.has(b):
		return ai_levels[b]
	return _sim.ai_level(b) if _sim != null else ""


func mark_label(m: int) -> String:
	var id: String = _course["marks"][m]["id"]
	return _labels.get(id, id)


func _mark_pos(m: int) -> Vector2:
	var md: Dictionary = _course["marks"][m]
	return Vector2(md["x"], md["y"])


## the step's points: [buoy] for a mark, both buoys of a gate, both ends of a line
func step_points(k: int) -> Array[Vector2]:
	var st: Dictionary = _course["steps"][k]
	var ms: PackedInt32Array = st["marks"]
	var out: Array[Vector2] = [_mark_pos(ms[0])]
	if int(st["kind"]) != RaceText.Step.MARK:
		out.append(_mark_pos(ms[1]))
	return out


func course() -> Dictionary:
	return _course


## Forget everything (a new sim or race).
func reset() -> void:
	var keep := [names, skippers, ai_levels, own_boat, dsq_pending, dsq_total, sail_numbers, boat_names]
	var fresh := RaceHudValues.new()
	for p in get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			set(p["name"], fresh.get(p["name"]))
	names = keep[0]
	skippers = keep[1]
	ai_levels = keep[2]
	own_boat = keep[3]
	dsq_pending = keep[4]
	dsq_total = keep[5]
	sail_numbers = keep[6]
	boat_names = keep[7]


## Once per tick after the step, for the viewed boat `b`.
func tick(sim: SimSource, b: int) -> void:
	if sim != _sim:
		reset()
		_sim = sim
	if not sim.has_race():
		active = false
		return
	if not active or _course.is_empty():
		_course = sim.course()
		_labels = sim.course_labels()
		if _course.is_empty():
			return
	if b != boat:
		_started_filters = false
		boat = b
	active = true
	_tick += 1
	_loa = sim.class_info(b).loa
	var race := sim.race()
	var rb := sim.race_boat(b)
	var s := sim.state(b)
	state = int(race.get("state", 0))
	race_time = float(race.get("race_time", 0.0))
	sequence = int(race.get("sequence", 0))
	prep_flag = int(race.get("prep_flag", 1))
	warning_time = 180.0 if sequence == RaceText.Sequence.S3210 else 300.0
	started = bool(rb.get("started", false))
	finished = bool(rb.get("finished", false))
	t_finish = float(rb.get("t_finish_us", 0)) * 1e-6
	dsq = bool(rb.get("dsq", false))
	_wind(sim, s)
	_flags(race)
	_start(sim, rb, s)
	_next_mark(sim, rb, s)
	_position(sim, b)
	_rules(sim, b)
	_penalties(sim, b)
	_radar(sim, b)
	# events and timers once per simulation tick (a scene may tick the HUD again without a step, e.g. on reset)
	if sim.tick() != _events_tick:
		_events_tick = sim.tick()
		_events(sim, b)
		_race_end(sim)
		_timers()


# ---- wind filters (clean wind at the boat, hud.md §3.2, §6, ai.md §3.3) ----

func _wind(sim: SimSource, s: SimSource.BoatState) -> void:
	var w := sim.wind_clean(s.pos_x, s.pos_y)
	var u := Vector2(sin(w.y), cos(w.y))
	if w == Vector2.ZERO:
		u = Vector2(sin(s.twd_from), cos(s.twd_from))
	if not _started_filters:
		_twd2 = u
		_twd5 = u
		_twd10 = u
		_twd180 = u
		_tws10 = s.tws
		_started_filters = true
	_twd2 += (u - _twd2) * _k(2.0)
	_twd5 += (u - _twd5) * _k(5.0)
	_twd10 += (u - _twd10) * _k(10.0)
	_twd180 += (u - _twd180) * _k(180.0)
	_tws10 += (s.tws - _tws10) * _k(10.0)


func twd10() -> float:
	return Frames.compass(_twd10.x, _twd10.y)


func _twd(v: Vector2) -> float:
	return Frames.compass(v.x, v.y)


# ---- flags (§9.1) ----

func _flags(race: Dictionary) -> void:
	flags.clear()
	var seq := state == RaceText.RaceState.SEQUENCE
	var t := race_time
	if seq and t >= -warning_time and t < 0.0:
		flags.append("class")
	if seq and t >= -(warning_time - 60.0) and t < -60.0:
		flags.append(["P", "I", "Z", "U", "black"][clampi(prep_flag, 0, 4)])
	if bool(race.get("x_flag", false)):
		flags.append("X")
	if seq and int(race.get("general_recalls", 0)) > 0 and t < -warning_time:
		flags.append("1st substitute")


# ---- start line panel (§9.2) ----

func _start(sim: SimSource, rb: Dictionary, s: SimSource.BoatState) -> void:
	var st := sim.race_start_status(boat)
	var in_seq := state == RaceText.RaceState.SEQUENCE and race_time >= -warning_time
	var after_gun := state >= RaceText.RaceState.RACING
	start_panel = not st.is_empty() and not started and not finished and (in_seq or after_gun) \
		and not bool(rb.get("ghost", false))
	over = false
	over_text = ""
	ocs = bool(rb.get("ocs", false)) or bool(rb.get("ocs_i", false))
	ocs_text = RaceText.ocs_instruction(bool(rb.get("ocs_i", false))) if ocs and not started else ""
	t_line = NAN
	burn = NAN
	bias_end = ""
	if st.is_empty():
		return
	var a: Vector2 = st["a"]
	var b: Vector2 = st["b"]
	var d := b - a
	var len_ := d.length()
	if len_ < 0.01:
		return
	var n := Vector2(-d.y, d.x) / len_  # towards the course side
	var sb := float(st["s_bow"])
	var ub := float(st["u_bow"])
	var bow := a + d * ub + n * sb
	if ub >= 0.0 and ub <= 1.0:
		line_dist = sb
		line_end = false
	else:
		line_dist = minf(bow.distance_to(a), bow.distance_to(b))
		line_end = true
	# time to line along the COG at the SOG
	var g := Vector2(s.sog_filt_x, s.sog_filt_y)
	var sog := g.length()
	if sog >= 0.5 * HudFormat.KNOT:
		var hit: Variant = Geometry2D.segment_intersects_segment(bow, bow + g / sog * 1.0e5, a, b)
		if hit != null:
			t_line = bow.distance_to(hit) / sog
	if race_time < 0.0 and not is_nan(t_line):
		burn = -race_time - t_line
	# bias from the clean wind smoothed 10 s (ai.md §5.2)
	var tw := twd10()
	var beta := Frames.wrap_pi(Frames.compass(n.x, n.y) - tw)
	var du := d.dot(Vector2(sin(tw), cos(tw)))
	bias = absf(beta)
	bias_m = absf(du)
	var fav_mark: int = _course["steps"][0]["marks"][1 if du > 0.0 else 0]
	var ends: PackedInt32Array = _course["steps"][0]["marks"]
	# the oriented ends may be swapped against the step's mark order: take the mark nearer the favoured end
	var fav_pt := b if du > 0.0 else a
	fav_mark = ends[0] if _mark_pos(ends[0]).distance_to(fav_pt) <= _mark_pos(ends[1]).distance_to(fav_pt) else ends[1]
	var mt := int(_course["marks"][fav_mark]["type"])
	bias_end = "BOAT" if mt == 1 else "PIN"
	# OVER (last minute, the active flag rule) and OCS after the gun
	var last_minute := state == RaceText.RaceState.SEQUENCE and race_time >= -60.0 and race_time < 0.0
	if last_minute and bool(st.get("over", false)):
		over = true
		over_text = RaceText.OVER_CONSEQUENCE[clampi(prep_flag, 0, 4)]
	elif after_gun and ocs and not started:
		over = true
		over_text = ocs_text


# ---- next mark (§7), performance (§4), laylines (§6), shift meter (§3.2), sail hint (§4) ----

func _next_mark(sim: SimSource, rb: Dictionary, s: SimSource.BoatState) -> void:
	var steps: Array = _course["steps"]
	laps = int(_course.get("laps", 1))
	legs = steps.size() - 1
	var k := int(rb.get("next", 0))
	next_step = k if k > 0 and k < steps.size() and not finished and not bool(rb.get("ghost", false)) else -1
	next_sides.clear()
	leg_type = ""
	eta = NAN
	layline_dist = NAN
	layline_time = NAN
	overstood = NAN
	shift_kind = ""
	target_twa = NAN
	sail_hint = ""
	if next_step < 0:
		laylines.clear()
		next_kind = -1
		next_name = ""
		next_dist = INF
		return
	var st: Dictionary = steps[k]
	next_kind = int(st["kind"])
	lap = int(st["lap"])
	leg = k
	var ms: PackedInt32Array = st["marks"]
	var sides: PackedInt32Array = st["sides"]
	match next_kind:
		RaceText.Step.MARK:
			next_name = mark_label(ms[0])
			next_sides.append(sides[0])
		RaceText.Step.GATE:
			next_name = CourseMapView.gate_label(mark_label(ms[0]), mark_label(ms[1]))
			next_sides.append(sides[0])
			next_sides.append(sides[1])
		_:
			next_name = "Finish"
	var c := Vector2(s.pos_x, s.pos_y)
	var fwd := Vector2(sin(s.psi), cos(s.psi))
	var bow := c + fwd * 0.5 * _loa
	var pts := step_points(k)
	var r := pts[0]
	if next_kind == RaceText.Step.FINISH:
		r = Geometry2D.get_closest_point_to_segment(bow, pts[0], pts[1])
		next_dist = bow.distance_to(r)
	else:
		next_dist = INF
		for i in pts.size():
			var dd := bow.distance_to(pts[i]) - float(_course["marks"][ms[i]]["radius"])
			if dd < next_dist:
				next_dist = dd
				r = pts[i]
		next_dist = maxf(next_dist, 0.0)
	next_bearing = Frames.compass(r.x - c.x, r.y - c.y)
	next_rel = Frames.wrap_pi(next_bearing - s.psi)
	# leg type (ai.md §4.1) on the clean wind smoothed 2 s, 3 degrees of hysteresis
	var vm := sim.polar_vmg(boat, s.tws)
	var tw2 := _twd(_twd2)
	var th_r := absf(Frames.wrap_pi(tw2 - Frames.compass(r.x - c.x, r.y - c.y)))
	var th_up := float(vm.get("up_twa", deg_to_rad(42.0)))
	var th_dn := float(vm.get("down_twa", deg_to_rad(150.0)))
	var h := deg_to_rad(3.0)
	var up_edge := th_up + (h if _leg_prev == "beat" else -h if _leg_prev == "reach" else 0.0)
	var dn_edge := th_dn - (h if _leg_prev == "run" else -h if _leg_prev == "reach" else 0.0)
	if th_r < up_edge:
		leg_type = "beat"
	elif th_r > dn_edge:
		leg_type = "run"
	else:
		leg_type = "reach"
	_leg_prev = leg_type
	# VMG, VMC, targets (§4)
	var o := sim.outputs(boat)
	var g := Vector2(s.sog_filt_x, s.sog_filt_y)
	var to_r := (r - c).normalized() if c.distance_to(r) > 0.01 else fwd
	vmg = o.vmg if leg_type != "run" else -o.vmg
	vmc = g.dot(to_r)
	var v_up := float(vm.get("up_speed", NAN))
	var v_dn := float(vm.get("down_speed", NAN))
	var tgt := o.polar_speed
	if leg_type == "beat" and not is_nan(v_up):
		tgt = v_up
		target_twa = th_up
	elif leg_type == "run" and not is_nan(v_dn):
		tgt = v_dn
		target_twa = th_dn
	else:
		var best := _best_polar(sim, s)
		if not is_nan(best.y):
			tgt = best.y
	target_speed = tgt
	# ETA: axis distance of the leg / VMG (beat, run), distance / VMC (reach)
	if leg_type == "reach":
		eta = next_dist / vmc if vmc >= MIN_KN else NAN
	elif vmg >= MIN_KN:
		eta = _axis_distance(k, bow, float(sim.race().get("twd_mean", tw2))) / vmg
	# laylines and the shift meter (beat and run only)
	if leg_type == "reach":
		laylines.clear()
	elif _tick % 10 == 1 or laylines.is_empty():
		_layline_lines(sim, c, r, pts)
	if leg_type != "reach":
		_layline(sim, s, c, r, g)
		_shift_meter(c, r, s, th_up if leg_type == "beat" else th_dn)
	_sail_hint(sim, s)


## race.md §8.1 and §8.2: the leg axis distance from the bow to the step's reference point
func _axis_distance(k: int, bow: Vector2, twd_mean: float) -> float:
	var steps: Array = _course["steps"]
	var rk: Vector2 = steps[k]["ref"]
	var rp: Vector2 = steps[k - 1]["ref"]
	var w := Vector2(sin(twd_mean), cos(twd_mean))
	var leg_v := rk - rp
	var e := leg_v.normalized()
	if leg_v.length() > 0.01 and absf(e.dot(w)) >= cos(PI / 4.0):
		e = w * signf(leg_v.dot(w))
	if int(steps[k]["kind"]) == RaceText.Step.FINISH:
		var p := step_points(k)
		var q := Geometry2D.get_closest_point_to_segment(bow, p[0], p[1])
		return maxf(0.0, (q - bow).dot(e))
	return maxf(0.0, (rk - bow).dot(e))


## hud.md §6 distance along the COG to the other tack's layline, or how far past it
func _layline(sim: SimSource, s: SimSource.BoatState, c: Vector2, r: Vector2, g: Vector2) -> void:
	var sog := g.length()
	if sog < MIN_KN:
		return
	var vm := sim.polar_vmg(boat, _tws10)
	if vm.is_empty():
		return
	var beat := leg_type == "beat"
	var th := float(vm["up_twa"] if beat else vm["down_twa"])
	var v := float(vm["up_speed"] if beat else vm["down_speed"])
	var tw := twd10()
	var tack := 1.0 if s.twa > 0.0 else -1.0
	var other := -tack
	var psi_o := Frames.wrap_2pi(tw - other * th)
	var cur := sim.current_at(r.x, r.y, 50.0 * sim.tick())
	var go := v * Vector2(sin(psi_o), cos(psi_o)) + cur
	var ldir := -go.normalized()  # from the mark backwards along the layline
	var dir := g / sog
	var side := ldir.cross(c - r)
	var closing := ldir.cross(dir)
	if (c - r).dot(ldir) < 0.0:
		return  # beyond the mark
	if side * closing > 0.0:
		overstood = absf(side)
		return
	var hit: Variant = Geometry2D.segment_intersects_segment(c, c + dir * 1.0e5, r, r + ldir * 1.0e5)
	if hit != null:
		layline_dist = c.distance_to(hit)
		layline_time = layline_dist / sog


## hud.md §6 the layline rays of both tacks through each point of the step
func _layline_lines(sim: SimSource, c: Vector2, r: Vector2, pts: Array[Vector2]) -> void:
	laylines.clear()
	var vm := sim.polar_vmg(boat, _tws10)
	if vm.is_empty():
		return
	var beat := leg_type == "beat"
	var th := float(vm["up_twa"] if beat else vm["down_twa"])
	var v := float(vm["up_speed"] if beat else vm["down_speed"])
	var tw := twd10()
	var length := 1.2 * maxf(c.distance_to(r), 500.0)
	for p in pts:
		var cur := sim.current_at(p.x, p.y, 50.0 * sim.tick())
		for tack in [1.0, -1.0]:
			var psi := Frames.wrap_2pi(tw - tack * th)
			var go := v * Vector2(sin(psi), cos(psi)) + cur
			laylines.append({"a": p, "b": p - go.normalized() * length, "tack": int(tack)})


## hud.md §3.2: header when the shift turns the current tack's VMG heading away from the mark
func _shift_meter(c: Vector2, r: Vector2, s: SimSource.BoatState, th: float) -> void:
	var t5 := _twd(_twd5)
	shift = Frames.wrap_pi(t5 - _twd(_twd180))
	if absf(shift) < deg_to_rad(2.0):
		shift_kind = ""
		return
	var tack := 1.0 if s.twa > 0.0 else -1.0
	var psi_opt := Frames.wrap_2pi(t5 - tack * th)
	var header := shift * signf(Frames.wrap_pi(psi_opt - Frames.compass(r.x - c.x, r.y - c.y))) > 0.0
	shift_kind = "header" if header else "lift"


## the best config at the present TWS and TWA: Vector2(front sail index or -1, polar speed); NAN speed unknown
func _best_polar(sim: SimSource, s: SimSource.BoatState) -> Vector2:
	var info := sim.class_info(boat)
	var best := Vector2(-2, NAN)
	var cands: Array[int] = [-1]
	cands.append_array(info.front_sails)
	for f in cands:
		var p := sim.polar(boat, s.tws, absf(s.twa), f)
		if not is_nan(p) and (is_nan(best.y) or p > best.y):
			best = Vector2(f, p)
	return best


func _sail_hint(sim: SimSource, s: SimSource.BoatState) -> void:
	var best := _best_polar(sim, s)
	var front := sim.sails(boat).front
	var cur := sim.polar(boat, s.tws, absf(s.twa), front)
	if is_nan(best.y) or is_nan(cur) or cur <= 0.05 or int(best.x) == front or best.y < 1.03 * cur:
		_hint_best = -2
		_hint_ticks = 0
		return
	if int(best.x) != _hint_best:
		_hint_best = int(best.x)
		_hint_ticks = 0
	_hint_ticks += 1
	if _hint_ticks >= HINT_TICKS:
		var info := sim.class_info(boat)
		var nm := "Main only" if _hint_best < 0 else info.sails[_hint_best].name.capitalize()
		sail_hint = "%s +%s %%" % [nm, HudFormat.percent(100.0 * (best.y / cur - 1.0))]


# ---- position (§10) ----

func _position(sim: SimSource, b: int) -> void:
	var order := sim.race_order()
	fleet = order.size()
	var nfin := 0
	for i in order:
		if bool(sim.race_boat(i).get("finished", false)):
			nfin += 1
	if order != _order_cand:
		_order_cand = order
		_order_since = 0
	else:
		_order_since += 1
	if shown_order.size() != order.size() or nfin != _finished_count or _order_since >= RANK_HOLD_TICKS:
		shown_order = order
	_finished_count = nfin
	var idx := shown_order.find(b)
	rank = idx + 1 if idx >= 0 else 0
	if finished:
		rank = int(sim.race_boat(b).get("place", rank))
	leader = shown_order[0] if shown_order.size() > 0 else -1
	ahead = shown_order[idx - 1] if idx > 0 else -1
	behind = shown_order[idx + 1] if idx >= 0 and idx + 1 < shown_order.size() else -1
	var d_me := float(sim.race_boat(b).get("D", 0.0))
	# D is the course distance only for boats that have started (before, the distance to the start line)
	if not _racing_on_course(sim, b) and not finished:
		ahead = -1
		behind = -1
	if ahead >= 0 and not _racing_on_course(sim, ahead):
		ahead = -1
	if behind >= 0 and not _racing_on_course(sim, behind):
		behind = -1
	ahead_dist = d_me - float(sim.race_boat(ahead).get("D", 0.0)) if ahead >= 0 else 0.0
	behind_dist = d_me - float(sim.race_boat(behind).get("D", 0.0)) if behind >= 0 else 0.0
	gap_time = NAN
	gap_estimate = false
	gap_at = ""
	gap_dist = 0.0
	if leader < 0 or leader == b or not started or (not finished and not _racing_on_course(sim, b)):
		return
	var rl := sim.race_boat(leader)
	gap_dist = maxf(0.0, d_me - float(rl.get("D", 0.0)))
	var mine := int(sim.race_boat(b).get("last_rounded", -1))
	var theirs := int(rl.get("last_rounded", -1))
	var common := mini(mine, theirs)
	if finished and bool(rl.get("finished", false)):
		gap_time = t_finish - float(rl.get("t_finish_us", 0)) * 1e-6
		gap_at = "Finish"
		return
	if common >= 1 and mine == theirs:
		var t_me := sim.race_split(b, common)
		var t_l := sim.race_split(leader, common)
		if not is_nan(t_me) and not is_nan(t_l):
			gap_time = t_me - t_l
			gap_at = _step_label(common)
			return
	var vref := _v_ref(sim, b)
	if vref > 0.05:
		gap_time = gap_dist / vref
		gap_estimate = true


func _racing_on_course(sim: SimSource, i: int) -> bool:
	var r := sim.race_boat(i)
	return bool(r.get("started", false)) and not bool(r.get("ghost", false))


func _step_label(k: int) -> String:
	var st: Dictionary = _course["steps"][k]
	match int(st["kind"]):
		RaceText.Step.MARK:
			return mark_label(st["marks"][0])
		RaceText.Step.GATE:
			return "gate"
		RaceText.Step.START:
			return "start"
	return "finish"


## race.md §7.2 V_ref of the boat's present leg: 0.9 x performance_scale x polar VMG (beat, run) or polar speed
## (reach)
func _v_ref(sim: SimSource, b: int) -> float:
	var s := sim.state(b)
	var vm := sim.polar_vmg(b, s.tws)
	if vm.is_empty():
		return 0.9 * maxf(s.v, 0.0)
	var k := 0.9 * sim.controls(b).performance_scale
	match leg_type:
		"beat":
			return k * float(vm["up_speed"]) * cos(float(vm["up_twa"]))
		"run":
			return -k * float(vm["down_speed"]) * cos(float(vm["down_twa"]))
	return k * sim.outputs(b).polar_speed


## the ranking list rows (hud.md §10): [{rank, boat, name, ai, gap, status}]
func ranking_rows() -> Array:
	var rows := []
	if _sim == null or not active:
		return rows
	var d_lead := float(_sim.race_boat(leader).get("D", 0.0)) if leader >= 0 else 0.0
	var t_win := NAN
	for i in shown_order.size():
		var bi := shown_order[i]
		var rb := _sim.race_boat(bi)
		var br := _sim.boat_rules(bi)
		var status := ""
		var gap_txt := ""
		if bool(rb.get("finished", false)):
			var tf := float(rb.get("t_finish_us", 0)) * 1e-6
			if is_nan(t_win):
				t_win = tf
			status = HudFormat.finish_time(tf)
			gap_txt = HudFormat.gap(tf - t_win) if i > 0 else ""
		else:
			var code := int(rb.get("code", 0))
			if bool(rb.get("dsq", false)):
				status = "DSQ"
			elif bool(rb.get("retired", false)):
				status = "RET"
			elif bool(rb.get("ocs", false)) or bool(rb.get("ocs_i", false)) or bool(rb.get("ocs_scored", false)):
				status = "OCS"
			elif code > 0:
				status = RaceText.score(code)
			var np: int = br.get("pending", []).size()
			if np > 0:
				status = ("%s  " % status if status != "" else "") + ("%d pen" % np)
			if i > 0 and bool(rb.get("started", false)):
				gap_txt = HudFormat.signed_distance(float(rb.get("D", 0.0)) - d_lead)
		rows.append({"rank": i + 1, "boat": bi, "name": name_of(bi), "ai": ai_badge(bi),
			"gap": gap_txt, "status": status})
	return rows


# ---- rules awareness (§11) and prompts ----

func _rules(sim: SimSource, b: int) -> void:
	message = null
	for p in sim.pairs():
		var i := int(p["i"])
		var j := int(p["j"])
		if i != b and j != b:
			continue
		var other := j if i == b else i
		var m := _pair_message(p, b, other)
		if m != null and (message == null or m.priority < message.priority):
			message = m
	var hs := sim.hail_state(b)
	hail_available = bool(hs.get("available", false))
	hailed_by = int(hs.get("hailed_by", -1))


func _pair_message(p: Dictionary, me: int, other: int) -> Message:
	var nm := name_of(other)
	var kc_rule := int(p["kc_rule"])
	var kc_state := int(p["kc_state"])
	var room_rule := int(p["room_rule"])
	var room_state := int(p["room_state"])
	var m := Message.new()
	m.other = other
	if int(p["kc_giver"]) == me and kc_rule != 0 and kc_state == RaceText.Kc.BREACH:
		m.text = "KEEP CLEAR: %s (%s)" % [RaceText.rule_text(kc_rule), nm]
		m.tint = Tint.RED
		m.breach = true
		m.priority = 0
	elif int(p["room_giver"]) == me and room_rule != 0 and room_state != RaceText.Kc.CLEAR:
		var obstr := room_rule == RaceText.Rule.R19
		m.text = "Give room at the obstruction (%s)" % nm if obstr else "Give mark-room to %s" % nm
		m.breach = room_state == RaceText.Kc.BREACH
		m.tint = Tint.RED if m.breach else Tint.ORANGE
		m.priority = 1 if m.breach else 3
	elif int(p["kc_giver"]) == me and kc_rule != 0 and kc_state == RaceText.Kc.WARNING:
		m.text = "Keep clear: %s (%s)" % [RaceText.rule_text(kc_rule), nm]
		m.tint = Tint.ORANGE
		m.priority = 2
	elif int(p["room_entitled"]) == me and room_rule != 0:
		m.text = "You have room at the obstruction" if room_rule == RaceText.Rule.R19 else "You have mark-room"
		m.tint = Tint.CYAN
		m.priority = 4
	elif int(p["rule17_holder"]) == me:
		m.text = "Don't sail above your proper course (rule 17)"
		m.tint = Tint.YELLOW
		m.priority = 5
	elif int(p["kc_holder"]) == me and kc_rule != 0 and kc_state != RaceText.Kc.CLEAR:
		m.text = RaceText.right_of_way_call(kc_rule)
		m.tint = Tint.GREEN
		m.priority = 6
	else:
		return null
	return m


## whether the protest prompt shows now (PlayerControls.protest_prompt)
func protest_prompt() -> bool:
	return protest_ticks > 0


# ---- penalties (§12.1) ----

func _penalties(sim: SimSource, b: int) -> void:
	var br := sim.boat_rules(b)
	var pend: Array = br.get("pending", [])
	pending = pend.size()
	var turning := bool(br.get("turning_for_penalty", false))
	penalty_visible = pending > 0 or turning or _tick - _last_penalty_tick < PENALTY_RECENT
	if pending > 0:
		penalty_rule = int(pend[0]["rule"])
		penalty_other = int(pend[0]["other"])
		turn_target = 360.0 * maxi(int(pend[0].get("count", 1)), 1)
	var cnt := int(turn_target / 360.0)
	turn_deg = absf(rad_to_deg(float(br.get("turn_progress", 0.0))))
	turn_sign = int(signf(float(br.get("turn_progress", 0.0))))
	turn_tack = int(br.get("turn_tacks", 0)) >= cnt
	turn_gybe = int(br.get("turn_gybes", 0)) >= cnt
	deadline = float(br.get("deadline_s", -1.0))
	var received := int(br.get("received", 0))
	dsq_warning = pending == dsq_pending - 1 or received == dsq_total - 1
	# both from the core's turn tracker (rules.md §9.3, §11.2): the match-race zone and the last reset
	var why := int(br.get("turn_reset", RaceText.TurnReset.NONE))
	var reset_age := sim.tick() - int(br.get("turn_reset_tick", 0))
	if bool(br.get("turn_in_zone", false)):
		turn_text = "Not counted: inside the zone"
	elif why != RaceText.TurnReset.NONE and why < RaceText.TURN_RESET_TEXT.size() and reset_age >= 0 \
			and reset_age <= RESET_TICKS and (pending > 0 or turning):
		turn_text = RaceText.TURN_RESET_TEXT[why]
	elif turn_deg >= 1.0:
		turn_text = ""  # hud.md §12.1: the ring says how far
	elif pending > 0:
		turn_text = "Sail clear, then one full turn"
	else:
		turn_text = ""


# ---- radar colours (§8) ----

func _radar(sim: SimSource, b: int) -> void:
	var by := {}
	for i in sim.boat_count():
		if i == b:
			continue
		var ct := Contact.new()
		ct.boat = i
		ct.ghost = bool(sim.race_boat(i).get("ghost", false))
		ct.tint = Tint.GREY if ct.ghost else Tint.WHITE
		by[i] = ct
	for p in sim.pairs():
		var i := int(p["i"])
		var j := int(p["j"])
		if i != b and j != b:
			continue
		var other := j if i == b else i
		if not by.has(other) or by[other].ghost:
			continue
		var ct: Contact = by[other]
		var st := RaceText.Kc.CLEAR
		if int(p["room_rule"]) != 0 and int(p["room_giver"]) == b:
			ct.tint = Tint.ORANGE
			st = int(p["room_state"])
		elif int(p["room_rule"]) != 0 and int(p["room_entitled"]) == b:
			ct.tint = Tint.CYAN
			st = int(p["room_state"])
		elif int(p["kc_rule"]) != 0 and int(p["kc_giver"]) == b:
			ct.tint = Tint.RED
			st = int(p["kc_state"])
		elif int(p["kc_rule"]) != 0 and int(p["kc_holder"]) == b:
			ct.tint = Tint.GREEN
			st = int(p["kc_state"])
		ct.pulse = [Pulse.NONE, Pulse.WARNING, Pulse.BREACH][clampi(st, 0, 2)]
	contacts.clear()
	for i in by:
		contacts.append(by[i])


func contact(b: int) -> Contact:
	for c in contacts:
		if c.boat == b:
			return c
	return null


# ---- events: banners, feed, splits, results (§9.1, §10, §12.2, §13) ----

func _banner(text: String, tint: int, ticks: int, full := false) -> void:
	banner = Line.new(text, tint, ticks, full)


## `about`: the boats the line is about (none: the whole race)
func _feed(text: String, about: Array = []) -> void:
	var l := Line.new(text, Tint.WHITE, FEED_TICKS)
	l.own = about.is_empty() or about.has(boat)
	feed.append(l)
	while feed.size() > FEED_LINES:
		feed.remove_at(0)


func _events(sim: SimSource, b: int) -> void:
	for e in sim.race_events():
		var kind := int(e["kind"])
		var eb := int(e["boat"])
		match kind:
			RaceText.Ev.SIGNAL:
				var sk := int(e["signal"])
				var text := RaceText.signal_banner(sk, int(e["flag"]))
				_banner(text, Tint.WHITE, BANNER_SIGNAL)
				_feed(text)
				hud_event.emit("signal", {"kind": sk, "flag": int(e["flag"])})
			RaceText.Ev.BOAT_OCS:
				if eb == own_boat:
					start_ocs = true
				if eb == b:
					var fl := int(e["flag"])
					var txt: String = "OVER: " + RaceText.OVER_CONSEQUENCE[clampi(fl, 0, 4)]
					if fl == RaceText.Flag.P:
						txt = RaceText.ocs_instruction(false)
					_banner(txt, Tint.RED, BANNER_SIGNAL)
					hud_event.emit("ocs", {"flag": fl})
			RaceText.Ev.BOAT_RETURNED:
				if eb == b:
					_banner("Returned: now start", Tint.GREEN, BANNER_SERVED)
			RaceText.Ev.STARTED:
				if eb == b:
					_banner("Started", Tint.GREEN, BANNER_SERVED)
				if eb == own_boat:
					start_t = float(e.get("t", race_time))
			RaceText.Ev.ROUNDED:
				_rounded(sim, b, eb, int(e["step"]))
			RaceText.Ev.FINISH_BLOCKED:
				if eb == b:
					_banner("Take your penalty before finishing" if int(e["block"]) == 0
						else "Return and start before you can finish", Tint.RED, BANNER_PENALTY)
			RaceText.Ev.FINISHED:
				_finished(sim, b, eb, e)
			RaceText.Ev.RETIRED:
				_feed("%s retired" % name_of(eb), [eb])
				if eb == own_boat:
					_card("ret", "RET", "RETIRED", "", "", "Retired")
			RaceText.Ev.JOINED:
				_feed("%s joined" % name_of(eb), [eb])
			RaceText.Ev.LEFT:
				_feed("%s left" % name_of(eb), [eb])
			RaceText.Ev.WINDOW_WARNING:
				if not finished:
					_banner("Finishing window closes in %d s" % int(e["value"]), Tint.YELLOW, BANNER_SPLIT)
			RaceText.Ev.RACE_CLOSING:
				_feed("First boat home: finishing window %s" % HudFormat.clock(float(e["value"])))
			RaceText.Ev.RACE_CLOSED:
				_results(sim, true)
				hud_event.emit("results", {})
			RaceText.Ev.ABANDONED:
				_banner("Race abandoned", Tint.RED, BANNER_DSQ, true)
	for e in sim.rules_events():
		var kind := int(e["kind"])
		var eb := int(e["boat"])
		var eo := int(e["other"])
		var rule := int(e["rule"])
		match kind:
			RaceText.Rev.RULE_WARNING:
				if eb == b or eo == b:
					hud_event.emit("rule_warning", {"giver": eb, "holder": eo, "rule": rule})
			RaceText.Rev.PENALTY:
				if eb == own_boat:
					penalties.append({"rule": rule, "other": eo, "state": "pending"})
				if eb == b:
					_last_penalty_tick = _tick
				var other_txt := " (%s)" % name_of(eo) if eo >= 0 else ""
				if eb == b:
					# hud.md §12.2: short, the panel carries the rule text and the other boat
					_banner("PENALTY · RULE %s" % RaceText.code(rule), Tint.RED, BANNER_SIGNAL)
				else:
					_feed("%s penalised, rule %s%s" % [name_of(eb), RaceText.code(rule), other_txt], [eb, eo])
				hud_event.emit("penalty", {"boat": eb, "rule": rule, "other": eo})
			RaceText.Rev.PENALTY_SERVED:
				if eb == own_boat:
					_penalty_state("done")
				if eb == b:
					_banner("Penalty done", Tint.GREEN, BANNER_SERVED)
					hud_event.emit("penalty_served", {"boat": eb})
			RaceText.Rev.PENALTY_CANCELLED:
				if eb == own_boat:
					_penalty_state("cancelled")
				if eb == b:
					_banner("Penalties offset: one each cancelled", Tint.GREEN, BANNER_SERVED)
			RaceText.Rev.PENALTY_LATE:
				# rules.md §9.4: no banner of its own, the disqualification that follows says why
				if eb == own_boat:
					_penalty_state("late")
				if eb == b:
					_last_penalty_tick = _tick
			RaceText.Rev.PROTESTABLE:
				if eo == b:
					protest_culprit = eb
					protest_rule = rule
					protest_ticks = int(ceil(maxf(float(e["deadline"]), 1.0) / DT))
					hud_event.emit("protest_prompt", {"culprit": eb, "rule": rule})
			RaceText.Rev.PROTESTED:
				if eo == b or eb == b:
					protest_ticks = 0
			RaceText.Rev.DISQUALIFIED:
				var why := "too many penalties"
				if rule == RaceText.Rule.SI_BOUNDARY:
					why = "outside the race area"
				elif rule == RaceText.Rule.LATE:
					why = "penalty not taken within 2 minutes"
				if eb == own_boat:
					dsq_reason = why
				if eb == b:
					_banner("DISQUALIFIED: %s" % why, Tint.RED, BANNER_DSQ, true)
				else:
					_feed("%s disqualified, %s" % [name_of(eb), why], [eb])
	if not _summary_done and state >= RaceText.RaceState.RACING and race_time >= START_SUMMARY_S:
		_summary_done = true
		var n_started := 0
		var n_ocs := 0
		for i in sim.boat_count():
			var r := sim.race_boat(i)
			if bool(r.get("started", false)):
				n_started += 1
			elif bool(r.get("ocs", false)) or bool(r.get("ocs_i", false)):
				n_ocs += 1
		_feed("%d %s started%s" % [n_started, "boat" if n_started == 1 else "boats",
			", %d OCS" % n_ocs if n_ocs > 0 else ""])


func _rounded(sim: SimSource, b: int, eb: int, k: int) -> void:
	if k <= 0 or k >= _course["steps"].size():
		return
	var mine := sim.race_split(eb, k)
	var first := mine
	var place := 1
	for i in sim.boat_count():
		if i == eb:
			continue
		var t := sim.race_split(i, k)
		if not is_nan(t) and not is_nan(mine) and t <= mine:
			place += 1
			first = minf(first, t)
	var what := _step_label(k)
	if eb == own_boat:
		# §13.3: "Windward 2" on a course of more than one lap
		var lbl := what.capitalize()
		if int(_course.get("laps", 1)) > 1:
			lbl += " %d" % int(_course["steps"][k].get("lap", 1))
		roundings.append({"step": k, "label": lbl, "place": place,
			"gap": mine - first if place > 1 and not is_nan(mine) else NAN})
	if eb == b:
		var txt := "%s · %s" % [what.capitalize() if what == "gate" else what, RaceText.ordinal(place)]
		if place > 1 and not is_nan(mine):
			txt += " · %s" % HudFormat.gap(mine - first)
		_banner(txt, Tint.WHITE, BANNER_SPLIT)
	if place <= 3:
		_feed("%s %s %s %s" % [name_of(eb), _verb(eb, "rounds", "round"), what, RaceText.ordinal(place)], [eb])


func _finished(sim: SimSource, b: int, eb: int, e: Dictionary) -> void:
	var place := int(e["place"])
	var t := float(e["t_us"]) * 1e-6
	var t_win := t
	for i in sim.boat_count():
		var r := sim.race_boat(i)
		if bool(r.get("finished", false)):
			t_win = minf(t_win, float(r.get("t_finish_us", 0)) * 1e-6)
	var place_txt := RaceText.ordinal(place) if place > 0 else "No place"
	_feed("%s %s %s" % [name_of(eb), _verb(eb, "finishes", "finish"), place_txt], [eb])
	if eb == own_boat:
		# hud.md §13.1: the card, not a banner
		var txt := "Finished %s · %s" % [place_txt, HudFormat.finish_time(t)]
		var gap_txt := ""
		if t > t_win:
			gap_txt = HudFormat.gap(t - t_win)
			txt += " · %s" % gap_txt
		var code := RaceText.score(int(sim.race_boat(eb).get("code", 0)))
		_card("finish", place_txt.to_upper() if place > 0 else (code if code != "" else "OCS"), "FINISHED", gap_txt,
			HudFormat.finish_time(t), txt, place == 1)
	if eb == b:
		hud_event.emit("finished", {"place": place})
		_results(sim, false)


## hud.md §13 results: final from the core's results after the close, provisional from the ranking before
func _results(sim: SimSource, final: bool) -> void:
	results_visible = true
	results_final = final
	result_rows.clear()
	var rows: Array = sim.results() if final else []
	var t_win := NAN
	if not rows.is_empty():
		for r in rows:
			var tf := float(r["t_finish_us"]) * 1e-6 if int(r["place"]) > 0 else NAN
			if not is_nan(tf) and (is_nan(t_win) or tf < t_win):
				t_win = tf
		for r in rows:
			var bi := int(r["boat"])
			var tf := float(r["t_finish_us"]) * 1e-6 if int(r["place"]) > 0 else NAN
			result_rows.append({"place": int(r["place"]), "boat": bi, "name": name_of(bi),
				"skipper": skippers.get(bi, ""), "ai": ai_badge(bi), "time": tf,
				"gap": tf - t_win if not is_nan(tf) else NAN, "code": str(r.get("code_name", RaceText.score(int(r["code"])))),
				"points": float(r["points"]), "projected": bool(r["projected"]), "status": ""})
		return
	results_final = false
	for bi in sim.race_order():
		var rb := sim.race_boat(bi)
		var fin := bool(rb.get("finished", false))
		var tf := float(rb.get("t_finish_us", 0)) * 1e-6 if fin else NAN
		if fin and (is_nan(t_win) or tf < t_win):
			t_win = tf
		result_rows.append({"place": int(rb.get("place", 0)) if fin else 0, "boat": bi, "name": name_of(bi),
			"skipper": skippers.get(bi, ""), "ai": ai_badge(bi), "time": tf, "gap": NAN,
			"code": RaceText.score(int(rb.get("code", 0))) if not fin else "", "points": NAN,
			"projected": false, "status": "" if fin else _live_status(rb)})
	for r in result_rows:
		if not is_nan(r["time"]):
			r["gap"] = r["time"] - t_win


## a boat that has not finished in the live finishing rows (menus.md §5): Racing, RET, DSQ, OCS, or her score code
static func _live_status(rb: Dictionary) -> String:
	if bool(rb.get("dsq", false)):
		return "DSQ"
	if bool(rb.get("retired", false)):
		return "RET"
	if bool(rb.get("ocs", false)) or bool(rb.get("ocs_i", false)) or bool(rb.get("ocs_scored", false)):
		return "OCS"
	var code := RaceText.score(int(rb.get("code", 0)))
	if code != "":
		return code
	return "Racing"


# ---- race end (§13.1 to §13.3) ----

func _card(kind: String, big: String, caption: String, gap_txt: String, time_txt: String, line: String,
		win := false) -> void:
	card = {"kind": kind, "big": big, "caption": caption, "gap": gap_txt, "time": time_txt, "line": line, "win": win}
	card_ticks = 0


func _penalty_state(st: String) -> void:
	for p in penalties:
		if p["state"] == "pending":
			p["state"] = st
			return


## Once per tick after the events: the track records of the own boat, whether her race is over (§13.2), the DNF
## card at a close with her still racing, the live finishing rows.
func _race_end(sim: SimSource) -> void:
	var ob := own_boat
	if ob < 0 or ob >= sim.boat_count():
		return
	var rb := sim.race_boat(ob)
	var fin := bool(rb.get("finished", false))
	var ghost := bool(rb.get("ghost", false))
	var racing := bool(rb.get("started", false)) and not fin and not ghost
	# §13.3: the track from the start signal to her finish or race end, the top speed while racing
	if not race_over and not fin and not ghost and state >= RaceText.RaceState.RACING:
		var st := sim.state(ob)
		var p := Vector2(st.pos_x, st.pos_y)
		if racing:
			top_speed = maxf(top_speed, st.v)
		if _track_last != Vector2.INF:
			distance_sailed += p.distance_to(_track_last)
		_track_last = p
	elif fin and _track_last != Vector2.INF and not race_over:
		var st := sim.state(ob)
		distance_sailed += Vector2(st.pos_x, st.pos_y).distance_to(_track_last)
		_track_last = Vector2.INF
	if not race_over:
		var why := ""
		if fin:
			why = "finished"
		elif bool(rb.get("dsq", false)):
			why = "dsq"
		elif bool(rb.get("retired", false)):
			why = "retired"
		elif ghost:
			why = "ghost"
		elif state == RaceText.RaceState.CLOSED:
			why = "dnf"
		elif state == RaceText.RaceState.ABANDONED:
			why = "abandoned"
		if why != "":
			race_over = true
			end_reason = why
			if why == "dnf":
				_card("dnf", "DNF", "RACE CLOSED", "", "", "Did not finish")
			if not results_visible:
				_results(sim, state == RaceText.RaceState.CLOSED)
	if race_over:
		over_ticks += 1  # the card counts the tick it came up on too
	if results_visible and not results_final:
		_results(sim, false)


## hud.md §13.2: the results screen's time has come (the card's 5 s after the race is over)
func results_due() -> bool:
	return race_over and over_ticks >= CARD_TICKS


## the card's opacity, `frac` ticks into the present tick (0..1): fading in, then out (§13.1); 0 when there is none
func card_alpha(frac := 0.0) -> float:
	if card.is_empty():
		return 0.0
	var t := (card_ticks + frac) * DT
	var total := CARD_TICKS * DT
	if t >= total:
		return 0.0
	return clampf(minf(t / CARD_IN_S, (total - t) / CARD_OUT_S), 0.0, 1.0)


## the own boat's place in the result rows (final after the close, live before), 0 without one
func own_place() -> int:
	for r in result_rows:
		if int(r["boat"]) == own_boat:
			return int(r["place"])
	return 0


## hud.md §13.3 the summary lines: [[label, value]], the items that have data
func summary_lines() -> Array:
	var out := []
	if not is_nan(start_t):
		var s := "%s after the gun" % HudFormat.gap(start_t)
		out.append(["Start", ("OCS, returned and started %s" % HudFormat.gap(start_t)) if start_ocs else s])
	elif start_ocs:
		out.append(["Start", "OCS"])
	for r in roundings:
		var v := RaceText.ordinal(int(r["place"]))
		if not is_nan(r["gap"]):
			v += "  ·  %s" % HudFormat.gap(r["gap"])
		out.append([r["label"], v])
	var place := own_place()
	if not roundings.is_empty() and place > 0:
		var d := int(roundings[0]["place"]) - place
		var txt := "Held %s since the first mark" % RaceText.ordinal(place)
		if d != 0:
			txt = "%s%d since the first mark" % ["+" if d > 0 else "", d]
		out.append(["Places", txt])
	if penalties.is_empty() and dsq_reason == "" and not is_nan(start_t):
		out.append(["Penalties", "No penalties"])
	for p in penalties:
		var other := " (%s)" % name_of(int(p["other"])) if int(p["other"]) >= 0 else ""
		var how: String = {"pending": "not taken", "done": "done", "late": "late", "cancelled": "cancelled"}[p["state"]]
		out.append(["Penalty", "Rule %s: %s%s, %s" % [RaceText.code(int(p["rule"])), RaceText.rule_text(int(p["rule"])),
			other, how]])
	if dsq_reason != "":
		out.append(["Disqualified", dsq_reason.substr(0, 1).to_upper() + dsq_reason.substr(1)])
	if top_speed > 0.0:
		out.append(["Top speed", "%s kn" % HudFormat.speed_kn(top_speed)])
	if distance_sailed > 0.0:
		out.append(["Distance sailed", HudFormat.distance(distance_sailed)])
	return out


func _timers() -> void:
	if not card.is_empty():
		card_ticks += 1
		if card_ticks >= CARD_TICKS:
			card = {}
	if banner != null:
		banner.ticks -= 1
		if banner.ticks <= 0:
			banner = null
	for i in range(feed.size() - 1, -1, -1):
		feed[i].ticks -= 1
		if feed[i].ticks <= 0:
			feed.remove_at(i)
	if protest_ticks > 0:
		protest_ticks -= 1
