class_name RaceHudMarks
extends RefCounted
## The next mark part of RaceHudValues (hud.md §7, §4, §6, §3.2): the next step and its distance, the leg type, VMG,
## VMC and the targets, the ETA, the laylines, the shift meter and the sail hint, written into the values `rv` every
## tick from RaceHudValues.tick.


static func next_mark(rv: RaceHudValues, sim: SimSource, rb: Dictionary, s: SimSource.BoatState) -> void:
	var steps: Array = rv._course["steps"]
	rv.laps = int(rv._course.get("laps", 1))
	rv.legs = steps.size() - 1
	var k := int(rb.get("next", 0))
	rv.next_step = k if k > 0 and k < steps.size() and not rv.finished and not bool(rb.get("ghost", false)) else -1
	rv.next_sides.clear()
	rv.leg_type = ""
	rv.eta = NAN
	rv.layline_dist = NAN
	rv.layline_time = NAN
	rv.overstood = NAN
	rv.shift_kind = ""
	rv.target_twa = NAN
	rv.sail_hint = ""
	if rv.next_step < 0:
		rv.laylines.clear()
		rv.next_kind = -1
		rv.next_name = ""
		rv.next_dist = INF
		return
	var st: Dictionary = steps[k]
	rv.next_kind = int(st["kind"])
	rv.lap = int(st["lap"])
	rv.leg = k
	var ms: PackedInt32Array = st["marks"]
	var sides: PackedInt32Array = st["sides"]
	match rv.next_kind:
		RaceText.Step.MARK:
			rv.next_name = rv.mark_label(ms[0])
			rv.next_sides.append(sides[0])
		RaceText.Step.GATE:
			rv.next_name = "Gate %s / %s" % [rv.mark_label(ms[0]), rv.mark_label(ms[1])]
			rv.next_sides.append(sides[0])
			rv.next_sides.append(sides[1])
		_:
			rv.next_name = "Finish"
	var c := Vector2(s.pos_x, s.pos_y)
	var fwd := Vector2(sin(s.psi), cos(s.psi))
	var bow := c + fwd * 0.5 * rv._loa
	var pts := rv.step_points(k)
	var r := pts[0]
	if rv.next_kind == RaceText.Step.FINISH:
		r = Geometry2D.get_closest_point_to_segment(bow, pts[0], pts[1])
		rv.next_dist = bow.distance_to(r)
	else:
		rv.next_dist = INF
		for i in pts.size():
			var dd := bow.distance_to(pts[i]) - float(rv._course["marks"][ms[i]]["radius"])
			if dd < rv.next_dist:
				rv.next_dist = dd
				r = pts[i]
		rv.next_dist = maxf(rv.next_dist, 0.0)
	rv.next_bearing = Frames.compass(r.x - c.x, r.y - c.y)
	rv.next_rel = Frames.wrap_pi(rv.next_bearing - s.psi)
	# leg type (ai.md §4.1) on the clean wind smoothed 2 s, 3 degrees of hysteresis
	var vm := sim.polar_vmg(rv.boat, s.tws)
	var tw2 := rv._twd(rv._twd2)
	var th_r := absf(Frames.wrap_pi(tw2 - Frames.compass(r.x - c.x, r.y - c.y)))
	var th_up := float(vm.get("up_twa", deg_to_rad(42.0)))
	var th_dn := float(vm.get("down_twa", deg_to_rad(150.0)))
	var h := deg_to_rad(3.0)
	var up_edge := th_up + (h if rv._leg_prev == "beat" else -h if rv._leg_prev == "reach" else 0.0)
	var dn_edge := th_dn - (h if rv._leg_prev == "run" else -h if rv._leg_prev == "reach" else 0.0)
	if th_r < up_edge:
		rv.leg_type = "beat"
	elif th_r > dn_edge:
		rv.leg_type = "run"
	else:
		rv.leg_type = "reach"
	rv._leg_prev = rv.leg_type
	# VMG, VMC, targets (§4)
	var o := sim.outputs(rv.boat)
	var g := Vector2(s.sog_filt_x, s.sog_filt_y)
	var to_r := (r - c).normalized() if c.distance_to(r) > 0.01 else fwd
	rv.vmg = o.vmg if rv.leg_type != "run" else -o.vmg
	rv.vmc = g.dot(to_r)
	var v_up := float(vm.get("up_speed", NAN))
	var v_dn := float(vm.get("down_speed", NAN))
	var tgt := o.polar_speed
	if rv.leg_type == "beat" and not is_nan(v_up):
		tgt = v_up
		rv.target_twa = th_up
	elif rv.leg_type == "run" and not is_nan(v_dn):
		tgt = v_dn
		rv.target_twa = th_dn
	else:
		var best := best_polar(rv, sim, s)
		if not is_nan(best.y):
			tgt = best.y
	rv.target_speed = tgt
	# ETA: axis distance of the leg / VMG (beat, run), distance / VMC (reach)
	if rv.leg_type == "reach":
		rv.eta = rv.next_dist / rv.vmc if rv.vmc >= RaceHudValues.MIN_KN else NAN
	elif rv.vmg >= RaceHudValues.MIN_KN:
		rv.eta = axis_distance(rv, k, bow, float(sim.race().get("twd_mean", tw2))) / rv.vmg
	# laylines and the shift meter (beat and run only)
	if rv.leg_type == "reach":
		rv.laylines.clear()
	elif rv._tick % 10 == 1 or rv.laylines.is_empty():
		layline_lines(rv, sim, c, r, pts)
	if rv.leg_type != "reach":
		layline(rv, sim, s, c, r, g)
		shift_meter(rv, c, r, s, th_up if rv.leg_type == "beat" else th_dn)
	sail_hint(rv, sim, s)


## race.md §8.1 and §8.2: the leg axis distance from the bow to the step's reference point
static func axis_distance(rv: RaceHudValues, k: int, bow: Vector2, twd_mean: float) -> float:
	var steps: Array = rv._course["steps"]
	var rk: Vector2 = steps[k]["ref"]
	var rp: Vector2 = steps[k - 1]["ref"]
	var w := Vector2(sin(twd_mean), cos(twd_mean))
	var leg_v := rk - rp
	var e := leg_v.normalized()
	if leg_v.length() > 0.01 and absf(e.dot(w)) >= cos(PI / 4.0):
		e = w * signf(leg_v.dot(w))
	if int(steps[k]["kind"]) == RaceText.Step.FINISH:
		var p := rv.step_points(k)
		var q := Geometry2D.get_closest_point_to_segment(bow, p[0], p[1])
		return maxf(0.0, (q - bow).dot(e))
	return maxf(0.0, (rk - bow).dot(e))


## hud.md §6 distance along the COG to the other tack's layline, or how far past it
static func layline(rv: RaceHudValues, sim: SimSource, s: SimSource.BoatState, c: Vector2, r: Vector2,
		g: Vector2) -> void:
	var sog := g.length()
	if sog < RaceHudValues.MIN_KN:
		return
	var vm := sim.polar_vmg(rv.boat, rv._tws10)
	if vm.is_empty():
		return
	var beat := rv.leg_type == "beat"
	var th := float(vm["up_twa"] if beat else vm["down_twa"])
	var v := float(vm["up_speed"] if beat else vm["down_speed"])
	var tw := rv.twd10()
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
		rv.overstood = absf(side)
		return
	var hit: Variant = Geometry2D.segment_intersects_segment(c, c + dir * 1.0e5, r, r + ldir * 1.0e5)
	if hit != null:
		rv.layline_dist = c.distance_to(hit)
		rv.layline_time = rv.layline_dist / sog


## hud.md §6 the layline rays of both tacks through each point of the step
static func layline_lines(rv: RaceHudValues, sim: SimSource, c: Vector2, r: Vector2, pts: Array[Vector2]) -> void:
	rv.laylines.clear()
	var vm := sim.polar_vmg(rv.boat, rv._tws10)
	if vm.is_empty():
		return
	var beat := rv.leg_type == "beat"
	var th := float(vm["up_twa"] if beat else vm["down_twa"])
	var v := float(vm["up_speed"] if beat else vm["down_speed"])
	var tw := rv.twd10()
	var length := 1.2 * maxf(c.distance_to(r), 500.0)
	for p in pts:
		var cur := sim.current_at(p.x, p.y, 50.0 * sim.tick())
		for tack in [1.0, -1.0]:
			var psi := Frames.wrap_2pi(tw - tack * th)
			var go := v * Vector2(sin(psi), cos(psi)) + cur
			rv.laylines.append({"a": p, "b": p - go.normalized() * length, "tack": int(tack)})


## hud.md §3.2: header when the shift turns the current tack's VMG heading away from the mark
static func shift_meter(rv: RaceHudValues, c: Vector2, r: Vector2, s: SimSource.BoatState, th: float) -> void:
	var t5 := rv._twd(rv._twd5)
	rv.shift = Frames.wrap_pi(t5 - rv._twd(rv._twd180))
	if absf(rv.shift) < deg_to_rad(2.0):
		rv.shift_kind = ""
		return
	var tack := 1.0 if s.twa > 0.0 else -1.0
	var psi_opt := Frames.wrap_2pi(t5 - tack * th)
	var header := rv.shift * signf(Frames.wrap_pi(psi_opt - Frames.compass(r.x - c.x, r.y - c.y))) > 0.0
	rv.shift_kind = "header" if header else "lift"


## the best config at the present TWS and TWA: Vector2(front sail index or -1, polar speed); NAN speed unknown
static func best_polar(rv: RaceHudValues, sim: SimSource, s: SimSource.BoatState) -> Vector2:
	var info := sim.class_info(rv.boat)
	var best := Vector2(-2, NAN)
	var cands: Array[int] = [-1]
	cands.append_array(info.front_sails)
	for f in cands:
		var p := sim.polar(rv.boat, s.tws, absf(s.twa), f)
		if not is_nan(p) and (is_nan(best.y) or p > best.y):
			best = Vector2(f, p)
	return best


static func sail_hint(rv: RaceHudValues, sim: SimSource, s: SimSource.BoatState) -> void:
	var best := best_polar(rv, sim, s)
	var front := sim.sails(rv.boat).front
	var cur := sim.polar(rv.boat, s.tws, absf(s.twa), front)
	if is_nan(best.y) or is_nan(cur) or cur <= 0.05 or int(best.x) == front or best.y < 1.03 * cur:
		rv._hint_best = -2
		rv._hint_ticks = 0
		return
	if int(best.x) != rv._hint_best:
		rv._hint_best = int(best.x)
		rv._hint_ticks = 0
	rv._hint_ticks += 1
	if rv._hint_ticks >= RaceHudValues.HINT_TICKS:
		var info := sim.class_info(rv.boat)
		var nm := "Main only" if rv._hint_best < 0 else info.sails[rv._hint_best].name.capitalize()
		rv.sail_hint = "%s +%s %%" % [nm, HudFormat.percent(100.0 * (best.y / cur - 1.0))]
