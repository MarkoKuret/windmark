class_name RaceHudEvents
extends RefCounted
## The events part of RaceHudValues (hud.md §9.1, §10, §12.2, §13): the race and rules events of a tick turned into
## the banners, feed lines and splits, the finish card and the results rows of the values `rv`, from
## RaceHudValues.tick. Banners carry the priority of hud.md §9.1: the viewed boat's own over the race's over the
## individual recall.


static func events(rv: RaceHudValues, sim: SimSource, b: int) -> void:
	for e in sim.race_events():
		var kind := int(e["kind"])
		var eb := int(e["boat"])
		match kind:
			RaceText.Ev.SIGNAL:
				var sk := int(e["signal"])
				var text := RaceText.signal_banner(sk, int(e["flag"]))
				var recall := sk == RaceText.SignalKind.X_UP or sk == RaceText.SignalKind.X_DOWN
				rv._banner(text, RaceHudValues.Tint.WHITE, RaceHudValues.BANNER_SIGNAL, false,
					RaceHudValues.PRIO_RECALL if recall else RaceHudValues.PRIO_RACE, true)
				rv._feed(text)
				rv.hud_event.emit("signal", {"kind": sk, "flag": int(e["flag"])})
			RaceText.Ev.BOAT_OCS:
				if eb == rv.own_boat:
					rv.start_ocs = true
				if eb == b:
					var fl := int(e["flag"])
					var txt: String = "OVER: " + RaceText.OVER_CONSEQUENCE[clampi(fl, 0, 4)]
					if fl == RaceText.Flag.P:
						txt = RaceText.ocs_instruction(false)
					rv._banner(txt, RaceHudValues.Tint.RED, RaceHudValues.BANNER_SIGNAL, false, RaceHudValues.PRIO_OWN)
					rv.hud_event.emit("ocs", {"flag": fl})
			RaceText.Ev.BOAT_RETURNED:
				if eb == b:
					rv._banner("Returned: now start", RaceHudValues.Tint.GREEN, RaceHudValues.BANNER_SERVED, false,
						RaceHudValues.PRIO_OWN)
			RaceText.Ev.STARTED:
				if eb == b:
					rv._banner("Started", RaceHudValues.Tint.GREEN, RaceHudValues.BANNER_SERVED, false,
						RaceHudValues.PRIO_OWN)
				if eb == rv.own_boat:
					rv.start_t = float(e.get("t", rv.race_time))
			RaceText.Ev.ROUNDED:
				rounded(rv, sim, b, eb, int(e["step"]))
			RaceText.Ev.FINISH_BLOCKED:
				if eb == b:
					rv._banner("Take your penalty before finishing" if int(e["block"]) == 0
						else "Return and start before you can finish", RaceHudValues.Tint.RED,
						RaceHudValues.BANNER_PENALTY, false, RaceHudValues.PRIO_OWN)
			RaceText.Ev.FINISHED:
				finished(rv, sim, b, eb, e)
			RaceText.Ev.GHOSTED:
				# hud.md §9.4: out at the start limit
				if int(e["ghost"]) == RaceText.Ghost.DNS:
					if eb == b:
						rv._banner("DID NOT START: no start within %s" % HudFormat.clock(rv.start_limit),
							RaceHudValues.Tint.RED, RaceHudValues.BANNER_DSQ, true, RaceHudValues.PRIO_OWN)
						rv.hud_event.emit("dns", {})
					else:
						rv._feed("%s did not start" % rv.name_of(eb), [eb])
			RaceText.Ev.RETIRED:
				rv._feed("%s retired" % rv.name_of(eb), [eb])
				if eb == rv.own_boat:
					rv._card("ret", "RET", "RETIRED", "", "", "Retired")
			RaceText.Ev.JOINED:
				rv._feed("%s joined" % rv.name_of(eb), [eb])
			RaceText.Ev.LEFT:
				rv._feed("%s left" % rv.name_of(eb), [eb])
			RaceText.Ev.WINDOW_WARNING:
				if not rv.finished:
					rv._banner("Finishing window closes in %d s" % int(e["value"]), RaceHudValues.Tint.YELLOW,
						RaceHudValues.BANNER_SPLIT)
			RaceText.Ev.RACE_CLOSING:
				rv._feed("First boat home: finishing window %s" % HudFormat.clock(float(e["value"])))
			RaceText.Ev.RACE_CLOSED:
				results(rv, sim, true)
				rv.hud_event.emit("results", {})
			RaceText.Ev.ABANDONED:
				rv._banner("Race abandoned", RaceHudValues.Tint.RED, RaceHudValues.BANNER_DSQ, true,
					RaceHudValues.PRIO_OWN)
	for e in sim.rules_events():
		var kind := int(e["kind"])
		var eb := int(e["boat"])
		var eo := int(e["other"])
		var rule := int(e["rule"])
		match kind:
			RaceText.Rev.RULE_WARNING:
				if eb == b or eo == b:
					rv.hud_event.emit("rule_warning", {"giver": eb, "holder": eo, "rule": rule})
			RaceText.Rev.PENALTY:
				if eb == rv.own_boat:
					rv.penalties.append({"rule": rule, "other": eo, "state": "pending"})
				if eb == b:
					rv._last_penalty_tick = rv._tick
				var other_txt := " (%s)" % rv.name_of(eo) if eo >= 0 else ""
				if eb == b:
					# hud.md §12.2: short, the panel carries the rule text and the other boat
					rv._banner("PENALTY · RULE %s" % RaceText.code(rule), RaceHudValues.Tint.RED,
						RaceHudValues.BANNER_SIGNAL, false, RaceHudValues.PRIO_OWN)
				else:
					rv._feed("%s penalised, rule %s%s" % [rv.name_of(eb), RaceText.code(rule), other_txt], [eb, eo])
				rv.hud_event.emit("penalty", {"boat": eb, "rule": rule, "other": eo})
			RaceText.Rev.PENALTY_SERVED:
				if eb == rv.own_boat:
					rv._penalty_state("done")
				if eb == b:
					rv._banner("Penalty done", RaceHudValues.Tint.GREEN, RaceHudValues.BANNER_SERVED, false,
						RaceHudValues.PRIO_OWN)
					rv.hud_event.emit("penalty_served", {"boat": eb})
			RaceText.Rev.PENALTY_CANCELLED:
				if eb == rv.own_boat:
					rv._penalty_state("cancelled")
				if eb == b:
					rv._banner("Penalties offset: one each cancelled", RaceHudValues.Tint.GREEN,
						RaceHudValues.BANNER_SERVED, false, RaceHudValues.PRIO_OWN)
			RaceText.Rev.PENALTY_LATE:
				# rules.md §9.4: no banner of its own, the disqualification that follows says why
				if eb == rv.own_boat:
					rv._penalty_state("late")
				if eb == b:
					rv._last_penalty_tick = rv._tick
			RaceText.Rev.PROTESTABLE:
				if eo == b:
					rv.protest_culprit = eb
					rv.protest_rule = rule
					rv.protest_ticks = int(ceil(maxf(float(e["deadline"]), 1.0) / RaceHudValues.DT))
					rv.hud_event.emit("protest_prompt", {"culprit": eb, "rule": rule})
			RaceText.Rev.PROTESTED:
				if eo == b or eb == b:
					rv.protest_ticks = 0
			RaceText.Rev.DISQUALIFIED:
				var why := "too many penalties"
				if rule == RaceText.Rule.SI_BOUNDARY:
					why = "outside the race area"
				elif rule == RaceText.Rule.LATE:
					why = "penalty not taken within 2 minutes"
				if eb == rv.own_boat:
					rv.dsq_reason = why
				if eb == b:
					rv._banner("DISQUALIFIED: %s" % why, RaceHudValues.Tint.RED, RaceHudValues.BANNER_DSQ, true,
						RaceHudValues.PRIO_OWN)
				else:
					rv._feed("%s disqualified, %s" % [rv.name_of(eb), why], [eb])
	start_limit(rv, sim, b)
	if not rv._summary_done and rv.state >= RaceText.RaceState.RACING and rv.race_time >= RaceHudValues.START_SUMMARY_S:
		rv._summary_done = true
		var n_started := 0
		var n_ocs := 0
		for i in sim.boat_count():
			var r := sim.race_boat(i)
			if bool(r.get("started", false)):
				n_started += 1
			elif bool(r.get("ocs", false)) or bool(r.get("ocs_i", false)):
				n_ocs += 1
		rv._feed("%d %s started%s" % [n_started, "boat" if n_started == 1 else "boats",
			", %d OCS" % n_ocs if n_ocs > 0 else ""])


## hud.md §9.4: the viewed boat not started gets a banner 2:00 and 1:00 before the start limit; released OCS at the
## limit, one more. The ghost at the limit is the GHOSTED event's.
static func start_limit(rv: RaceHudValues, sim: SimSource, b: int) -> void:
	var t := rv.race_time
	var prev := rv._prev_race_time
	rv._prev_race_time = t
	if is_nan(prev) or rv.state < RaceText.RaceState.RACING or rv.state >= RaceText.RaceState.CLOSED:
		return
	var rb := sim.race_boat(b)
	if bool(rb.get("started", false)) or bool(rb.get("ghost", false)) or bool(rb.get("finished", false)):
		return
	var is_ocs := bool(rb.get("ocs", false)) or bool(rb.get("ocs_i", false))
	if bool(rb.get("ocs_scored", false)):
		if not rv._release_shown and t < rv.start_limit + 1.0:
			rv._release_shown = true
			rv._banner("Not returned: you score OCS", RaceHudValues.Tint.RED, RaceHudValues.BANNER_PENALTY, false,
				RaceHudValues.PRIO_OWN)
		return
	for w in RaceHudValues.START_LIMIT_WARN:
		var at: float = rv.start_limit - w
		if prev < at and t >= at:
			var txt := ("Return within %s or you score OCS" if is_ocs else "Start within %s or you are out (DNS)") \
				% HudFormat.clock(w)
			rv._banner(txt, RaceHudValues.Tint.YELLOW, RaceHudValues.BANNER_SPLIT, false, RaceHudValues.PRIO_OWN)
			rv.hud_event.emit("start_limit", {"left": w, "ocs": is_ocs})


static func rounded(rv: RaceHudValues, sim: SimSource, b: int, eb: int, k: int) -> void:
	if k <= 0 or k >= rv._course["steps"].size():
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
	var what := rv._step_label(k)
	if eb == rv.own_boat:
		# §13.3: "Windward 2" on a course of more than one lap
		var lbl := what.capitalize()
		if int(rv._course.get("laps", 1)) > 1:
			lbl += " %d" % int(rv._course["steps"][k].get("lap", 1))
		rv.roundings.append({"step": k, "label": lbl, "place": place,
			"gap": mine - first if place > 1 and not is_nan(mine) else NAN})
	if eb == b:
		var txt := "%s · %s" % [what.capitalize() if what == "gate" else what, RaceText.ordinal(place)]
		if place > 1 and not is_nan(mine):
			txt += " · %s" % HudFormat.gap(mine - first)
		rv._banner(txt, RaceHudValues.Tint.WHITE, RaceHudValues.BANNER_SPLIT)
	if place <= 3:
		rv._feed("%s %s %s %s" % [rv.name_of(eb), rv._verb(eb, "rounds", "round"), what, RaceText.ordinal(place)], [eb])


static func finished(rv: RaceHudValues, sim: SimSource, b: int, eb: int, e: Dictionary) -> void:
	var place := int(e["place"])
	var t := float(e["t_us"]) * 1e-6
	var t_win := t
	for i in sim.boat_count():
		var r := sim.race_boat(i)
		if bool(r.get("finished", false)):
			t_win = minf(t_win, float(r.get("t_finish_us", 0)) * 1e-6)
	var place_txt := RaceText.ordinal(place) if place > 0 else "No place"
	rv._feed("%s %s %s" % [rv.name_of(eb), rv._verb(eb, "finishes", "finish"), place_txt], [eb])
	if eb == rv.own_boat:
		# hud.md §13.1: the card, not a banner
		var txt := "Finished %s · %s" % [place_txt, HudFormat.finish_time(t)]
		var gap_txt := ""
		if t > t_win:
			gap_txt = HudFormat.gap(t - t_win)
			txt += " · %s" % gap_txt
		var code := RaceText.score(int(sim.race_boat(eb).get("code", 0)))
		rv._card("finish", place_txt.to_upper() if place > 0 else (code if code != "" else "OCS"), "FINISHED", gap_txt,
			HudFormat.finish_time(t), txt, place == 1)
	if eb == b:
		rv.hud_event.emit("finished", {"place": place})
		results(rv, sim, false)


## hud.md §13 results: final from the core's results after the close, provisional from the ranking before
static func results(rv: RaceHudValues, sim: SimSource, final: bool) -> void:
	rv.results_visible = true
	rv.results_final = final
	rv.result_rows.clear()
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
			rv.result_rows.append({"place": int(r["place"]), "boat": bi, "name": rv.name_of(bi),
				"skipper": rv.skippers.get(bi, ""), "ai": rv.ai_badge(bi), "time": tf,
				"gap": tf - t_win if not is_nan(tf) else NAN,
				"code": str(r.get("code_name", RaceText.score(int(r["code"])))),
				"points": float(r["points"]), "projected": bool(r["projected"]), "status": ""})
		return
	rv.results_final = false
	for bi in sim.race_order():
		var rb := sim.race_boat(bi)
		var fin := bool(rb.get("finished", false))
		var tf := float(rb.get("t_finish_us", 0)) * 1e-6 if fin else NAN
		if fin and (is_nan(t_win) or tf < t_win):
			t_win = tf
		rv.result_rows.append({"place": int(rb.get("place", 0)) if fin else 0, "boat": bi, "name": rv.name_of(bi),
			"skipper": rv.skippers.get(bi, ""), "ai": rv.ai_badge(bi), "time": tf, "gap": NAN,
			"code": RaceText.score(int(rb.get("code", 0))) if not fin else "", "points": NAN,
			"projected": false, "status": "" if fin else live_status(rb)})
	for r in rv.result_rows:
		if not is_nan(r["time"]):
			r["gap"] = r["time"] - t_win


## a boat that has not finished in the live finishing rows (menus.md §5): Racing, RET, DSQ, OCS, or her score code
static func live_status(rb: Dictionary) -> String:
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
