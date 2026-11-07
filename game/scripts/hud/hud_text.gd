class_name HudText
extends RefCounted
## The race texts of a Hud (hud.md §3.2, §7, §9 to §13) and the selected boat's card (§16.7), written into its
## `texts` at the 4 Hz refresh from the values of the last tick. Static functions on the Hud `hud`, called from
## Hud.refresh_text and Hud.frame.


## The race numbers at 4 Hz (hud.md §1 formats, §14 assists).
static func race(hud: Hud) -> void:
	var r := hud.race
	if not r.active:
		return
	var red: Color = HudStyle.PORT
	var white: Color = HudStyle.PAPER
	# clock (§9.1)
	var clock := ""
	var clock_v := ""
	if r.state <= RaceText.RaceState.FREE_SAILING or (r.state == RaceText.RaceState.SEQUENCE
			and r.race_time < -r.warning_time):
		clock_v = HudFormat.countdown(-r.race_time - r.warning_time)
		clock = "Warning in %s" % clock_v
	elif r.state == RaceText.RaceState.SEQUENCE:
		clock_v = HudFormat.countdown(-r.race_time)
		clock = "Start in %s" % clock_v
	elif r.finished:
		clock_v = HudFormat.finish_time(r.t_finish)
		clock = "Finished  %s" % clock_v
	elif r.state == RaceText.RaceState.ABANDONED:
		clock = "Abandoned"
	else:
		clock_v = HudFormat.clock(r.race_time)
		clock = "Race  %s" % clock_v
	hud._put("clock", clock, white, clock_v)
	# the finish card (§13.1)
	hud._put("finish", r.card.get("line", "") if hud.finish_card_shown() else "", HudStyle.PAPER)
	# start line panel (§9.2)
	if r.start_panel:
		var dv := HudStyle.split_unit(HudFormat.signed_distance(r.line_dist) if not r.line_end
			else HudFormat.distance(r.line_dist))
		var d := "Line  %s" % HudFormat.signed_distance(r.line_dist) if not r.line_end \
			else "Line  %s (end)" % HudFormat.distance(r.line_dist)
		hud._put("line", d, white, dv[0], dv[1] + (" END" if r.line_end else ""))
		var full := hud.shows("burn_bias")
		var tl := "--" if is_nan(r.t_line) else HudFormat.clock(r.t_line)
		hud._put("tline", ("To line  %s" % tl) if full else "", white, tl)
		var burn := ""
		var burn_v := "--"
		if full and r.race_time < 0.0:
			# a signed m:ss gap, never bare seconds: an S after a number is starboard (hud.md §1, §9.2)
			if not is_nan(r.burn):
				burn_v = HudFormat.gap(r.burn)
			burn = "Burn  %s" % burn_v
		hud._put("burn", burn, white if is_nan(r.burn) or r.burn >= 0.0 else HudStyle.OWE, burn_v)
		var bias := ""
		if full and r.bias_end != "":
			bias = "Bias  %s +%d° · %s" % [r.bias_end, int(HudFormat.round_half_away(rad_to_deg(r.bias))),
				HudFormat.distance(r.bias_m)]
		hud._put("bias", bias, white, r.bias_end)
		if bias != "":
			hud.texts["bias"]["sub"] = ("+%d° · %s" % [int(HudFormat.round_half_away(rad_to_deg(r.bias))),
				HudFormat.distance(r.bias_m)]).to_upper()
	else:
		for k in ["line", "tline", "burn", "bias"]:
			hud._put(k, "")
	hud._put("over", "OVER  %s" % r.over_text if r.over else "", red)
	# next mark (§7) and performance (§4, §6, §3.2)
	if r.next_step > 0:
		hud._put("next", r.next_name, HudStyle.MARK)
		hud._put("lap", "Lap %d/%d · Leg %d/%d" % [r.lap, r.laps, r.leg, r.legs])
		var md := HudStyle.split_unit(HudFormat.distance(r.next_dist))
		hud._put("mark_dist", HudFormat.distance(r.next_dist), white, md[0], md[1])
		hud._put("bearing", "Bearing  %s  (%s)" % [HudFormat.compass_deg(r.next_bearing),
			HudFormat.relative_bearing(r.next_rel)])
		var eta := "--:--" if is_nan(r.eta) else HudFormat.clock(r.eta)
		hud._put("leg", "%s  ·  ETA %s" % [r.leg_type.capitalize(), eta])
		if r.leg_type == "reach":
			hud._put("vmg", "VMC  %s kn" % HudFormat.speed_kn(r.vmc), white, HudFormat.speed_kn(r.vmc), "KN")
			hud._put("vmg_kn", "", white, HudFormat.speed_kn(r.vmc), "KN")
		else:
			hud._put("vmg", "VMG  %s kn" % HudFormat.speed_kn(r.vmg), white, HudFormat.speed_kn(r.vmg), "KN")
			hud._put("vmg_kn", "", white, HudFormat.speed_kn(r.vmg), "KN")
		var lay := ""
		if hud.shows("layline_distance"):
			if not is_nan(r.overstood):
				lay = "OVERSTOOD %s" % HudFormat.distance(r.overstood)
			elif not is_nan(r.layline_dist):
				lay = "Layline %s · %s" % [HudFormat.distance(r.layline_dist), HudFormat.clock(r.layline_time)]
		hud._put("layline", lay, red if lay.begins_with("OVER") else white)
		var sh := ""
		if hud.shows("shift") and r.leg_type != "reach":
			sh = "Shift  --"
			if r.shift_kind != "":
				sh = "%s %d°" % [r.shift_kind.to_upper(), int(HudFormat.round_half_away(rad_to_deg(absf(r.shift))))]
		var sh_col := white
		if r.shift_kind == "lift":
			sh_col = HudStyle.STBD
		elif r.shift_kind == "header":
			sh_col = red
		hud._put("shift", sh, sh_col)
		hud._put("hint", r.sail_hint if hud.shows("sail_hint") else "", HudStyle.HAVE)
	else:
		for k in ["next", "lap", "mark_dist", "bearing", "leg", "layline", "hint", "vmg", "shift"]:
			hud._put(k, "")
	# position (§10)
	hud._put("rank", "%d / %d" % [r.rank, r.fleet] if r.rank > 0 else "")
	# the leader by name and the boat ahead with their time gaps (hud.md §10); no ahead line when she leads
	var gap := ""
	if r.leader >= 0 and r.leader != r.boat and r.started:
		gap = gap_line("Leader", r.name_of(r.leader), "+" + HudFormat.distance(r.gap_dist), r.gap_time,
			r.gap_estimate, r.gap_at)
	elif r.leader == r.boat and r.started and r.fleet > 1:
		gap = "Leading"
	hud._put("gap", gap)
	hud._put("ahead", gap_line("Ahead", r.name_of(r.ahead), HudFormat.signed_distance(r.ahead_dist), r.ahead_time,
		r.ahead_estimate, r.ahead_at) if r.ahead >= 0 and r.ahead != r.leader and r.started else "")
	hud._put("behind", "Behind  %s  %s" % [r.name_of(r.behind), HudFormat.signed_distance(r.behind_dist)]
		if r.behind >= 0 and r.started else "")
	# penalties (§12.1)
	if r.pending > 0:
		var other := " (%s)" % r.name_of(r.penalty_other) if r.penalty_other >= 0 else ""
		var head := "Penalty" if r.pending == 1 else "Penalty 1 of %d" % r.pending
		hud._put("pen_head", "%s: %s%s" % [head, RaceText.rule_text(r.penalty_rule), other], red)
	else:
		hud._put("pen_head", "Penalty done" if r.penalty_visible else "")
	hud._put("pen_turn", r.turn_text)
	var dl := ""
	if r.deadline >= 0.0 and r.pending > 0:
		dl = "Deadline  %s" % HudFormat.clock(r.deadline)
	hud._put("pen_deadline", dl, red if r.deadline < 30.0 else white, HudFormat.clock(maxf(r.deadline, 0.0)))
	hud._put("pen_dsq", "One more penalty = disqualification" if r.dsq_warning and r.pending > 0 else "", red)


## "Leader  Nora  +120 m  ~+0:25", "Ahead  Kestrel  +45 m  +0:08 @ Windward" (hud.md §10): the time gap marked ~
## when estimated, with the split's label when not
static func gap_line(label: String, name: String, dist: String, t: float, estimate: bool, at: String) -> String:
	var s := "%s  %s  %s" % [label, name, dist]
	if not is_nan(t):
		s += "  %s%s%s" % ["~" if estimate else "", HudFormat.gap(t), " @ %s" % at if at != "" and not estimate else ""]
	return s


## the selected boat's card from the race and rules records of the last tick (hud.md §16.7: who she is, her place,
## how she stands against the viewed boat; no cells of her distance, bearing, speed or heading)
static func card(hud: Hud) -> void:
	hud.card = {}
	hud._bump()
	var b := hud.selected_boat()
	if b < 0 or hud.sim == null or hud.viewed < 0 or b == hud.viewed or b >= hud.sim.boat_count():
		return
	if hud.sim.state(hud.viewed) == null or hud.sim.state(b) == null:
		return
	var r := hud.race
	var c := {"boat": b}
	# header
	var head: Array[String] = []
	var sail := str(r.sail_numbers.get(b, ""))
	if sail != "":
		head.append(sail.to_upper())
	var ai := r.ai_badge(b)
	var skipper := str(r.skippers.get(b, ""))
	if ai != "":
		head.append(("%s · AI %s" % [skipper, ai] if skipper != "" else "AI " + ai).to_upper())
	else:
		head.append(skipper.to_upper() if skipper != "" else "PLAYER")
	c["head"] = " · ".join(head)
	c["name"] = r.name_of(b).to_upper()
	var col := HudStyle.PAPER
	var ct := r.contact(b)
	if ct != null:
		col = HudStyle.TINTS[RaceHudValues.Tint.GREY] if ct.ghost else (HudStyle.TINTS[ct.tint] if hud.radar.colours
			else HudStyle.PAPER)
	c["col"] = col
	if r.active:
		card_race(hud, c, b)
	hud.card = c


## the card's race rows: place, course and gap, the rules relation, penalties
static func card_race(hud: Hud, c: Dictionary, b: int) -> void:
	var r := hud.race
	var rb := hud.sim.race_boat(b)
	var fin := bool(rb.get("finished", false))
	if r.started:
		var idx := r.shown_order.find(b)
		var place := int(rb.get("place", idx + 1)) if fin else idx + 1
		if place > 0:
			c["place"] = str(place)
			c["fleet"] = r.fleet
	var course := ""
	if fin:
		course = "Finished"
	elif bool(rb.get("dsq", false)):
		course = "DSQ"
	elif bool(rb.get("retired", false)):
		course = "RET"
	else:
		var k := int(rb.get("next", 0))
		var lab := "start" if k <= 0 or not bool(rb.get("started", false)) else r._step_label(k)
		course = "Next " + (lab.capitalize() if lab in ["start", "gate", "finish"] else lab)
		if bool(rb.get("ocs", false)) or bool(rb.get("ocs_i", false)):
			course = "OCS · " + course
		if r._racing_on_course(hud.sim, b) and r._racing_on_course(hud.sim, hud.viewed) \
				and not bool(hud.sim.race_boat(hud.viewed).get("finished", false)):
			var g := float(rb.get("D", 0.0)) - float(hud.sim.race_boat(hud.viewed).get("D", 0.0))
			c["gap_m"] = g
			if absf(g) < 0.5:
				course += " · level with you"
			else:
				course += " · %s %s" % [HudFormat.distance(absf(g)), "behind you" if g > 0.0 else "ahead of you"]
	c["course"] = course
	# the rules relation with the viewed boat (the radar colour's meaning, §8)
	if hud.shows("radar_colours"):
		for p in hud.sim.pairs():
			var i := int(p["i"])
			var j := int(p["j"])
			if not ((i == hud.viewed and j == b) or (i == b and j == hud.viewed)):
				continue
			var text := ""
			var rule := 0
			var st := 0
			var tint := RaceHudValues.Tint.WHITE
			if int(p["room_rule"]) != 0 and int(p["room_giver"]) == hud.viewed:
				text = "YOU GIVE ROOM"
				rule = int(p["room_rule"])
				st = int(p["room_state"])
				tint = RaceHudValues.Tint.ORANGE
			elif int(p["room_rule"]) != 0 and int(p["room_entitled"]) == hud.viewed:
				text = "SHE GIVES YOU ROOM"
				rule = int(p["room_rule"])
				st = int(p["room_state"])
				tint = RaceHudValues.Tint.CYAN
			elif int(p["kc_rule"]) != 0 and int(p["kc_giver"]) == hud.viewed:
				text = "YOU KEEP CLEAR"
				rule = int(p["kc_rule"])
				st = int(p["kc_state"])
				tint = RaceHudValues.Tint.RED
			elif int(p["kc_rule"]) != 0 and int(p["kc_holder"]) == hud.viewed:
				text = "SHE KEEPS CLEAR"
				rule = int(p["kc_rule"])
				st = int(p["kc_state"])
				tint = RaceHudValues.Tint.GREEN
			if text != "":
				# one line: the relation, the rule's number, BREACH (the rules line of §11 carries the text)
				c["rules"] = "%s · RULE %s%s" % [text, RaceText.code(rule),
					" · BREACH" if st == RaceText.Kc.BREACH else ""]
				c["rules_col"] = HudStyle.TINTS[tint]
				c["rule"] = rule
			break
	# penalties owed
	var br := hud.sim.boat_rules(b)
	var n: int = br.get("pending", []).size()
	if n > 0:
		c["penalty"] = "%d %s OWED" % [n, "PENALTY" if n == 1 else "PENALTIES"]
		if bool(br.get("turning_for_penalty", false)):
			c["penalty"] += " · TURNING"
