extends SceneTree
## Race HUD tests (hud.md §15 and the race parts of §3.2, §4, §6 to §14) run headless:
##   - scripted race states (RaceStubSim): countdown, flags and signal banners, the start line panel with the
##     time to burn test of §15, bias, OVER and OCS, the next mark, VMG / VMC signs, layline distance and
##     overstanding, the shift meter, the sail hint, rank hysteresis, gaps and splits, every rules awareness line,
##     radar colours for the port-starboard, windward-leeward and mark-room pair records, penalties, protest and
##     hail prompts, the feed, the results and the assist presets;
##   - the layline test of §15 on the core (a boat on the computed starboard layline fetches the mark);
##   - a real race on the core, example_bay/example_wl, two boats steered by RacePilot from the spawn to the
##     results, the HUD checked against the core's race and rules records every tick;
##   - the sail test scene in race mode: the HUD shows the race and hides the stand-in label.
##   godot --headless --path game -s res://tests/race_hud_test.gd

const KNOT := HudFormat.KNOT

var t := TestLog.new()


func _init() -> void:
	test_countdown_flags()
	test_start_panel()
	test_next_mark()
	test_laylines_shift_hint()
	test_position()
	test_rules_messages()
	test_radar_colours()
	test_penalties_prompts()
	test_results_feed()
	test_assists_text()
	test_fake_sim()
	if CoreSimSource.available():
		test_layline_core()
		test_core_race()
		await test_scene_race()
	else:
		t.ok(false, "the GDExtension is not loaded: core tests skipped")
	t.finish(self, "race_hud_test")


func _hud(sim: SimSource, b := 0) -> Hud:
	var h := Hud.new()
	get_root().add_child(h)
	h.tick(sim, b)
	h.frame(0.3)
	return h


func _refresh(h: Hud, sim: SimSource, b := 0, ticks := 1) -> void:
	for i in ticks:
		sim.step()
		h.tick(sim, b)
	h.frame(0.3)
	h.refresh_text()


func _rev(kind: int, fields: Dictionary) -> Dictionary:
	var e := {"kind": kind, "tick": 0, "boat": -1, "signal": 0, "flag": 0, "step": -1, "buoy": -1, "t": 0.0,
		"t_us": 0, "place": 0, "block": 0, "ghost": 0, "value": 0.0}
	e.merge(fields, true)
	return e


func _uev(kind: int, fields: Dictionary) -> Dictionary:
	var e := {"kind": kind, "tick": 0, "boat": -1, "other": -1, "rule": 0, "count": 1, "contact": false,
		"mark": -1, "deadline": 0.0}
	e.merge(fields, true)
	return e


# ---- §9.1 --------------------------------------------------------------------------------------------------------

func test_countdown_flags() -> void:
	t.begin("countdown, flags and signal banners (hud.md §9.1)")
	var sim := RaceStubSim.new()
	sim.put(0, 0, -200, 0.0, 2.0)
	sim.put(1, 30, -200, 0.0, 2.0)
	sim.race_d["state"] = RaceText.RaceState.FREE_SAILING
	sim.race_d["race_time"] = -320.0
	var h := _hud(sim)
	h.refresh_text()
	t.ok(h.race_panel.visible and h.text_of("clock") == "Warning in 0:20", "free sailing: " + h.text_of("clock"))
	sim.race_d["state"] = RaceText.RaceState.SEQUENCE
	sim.race_d["race_time"] = -270.0
	sim.race_ev = [_rev(RaceText.Ev.SIGNAL, {"signal": RaceText.SignalKind.WARNING})]
	_refresh(h, sim)
	t.ok(h.text_of("clock") == "Start in 4:30", "sequence: " + h.text_of("clock"))
	t.ok(_same(h.race.flags, ["class"]), "class flag from the warning signal: %s" % str(h.race.flags))
	t.ok(h.text_of("banner") == "Warning signal: class flag up", "warning banner: " + h.text_of("banner"))
	sim.race_d["race_time"] = -239.0
	sim.race_ev = [_rev(RaceText.Ev.SIGNAL, {"signal": RaceText.SignalKind.PREP_UP, "flag": RaceText.Flag.I})]
	_refresh(h, sim)
	t.ok(_same(h.race.flags, ["class", "I"]), "prep flag I from the preparatory signal: %s" % str(h.race.flags))
	t.ok(h.text_of("banner") == "Preparatory signal, I flag: over in the last minute means round an end",
		"prep banner: " + h.text_of("banner"))
	t.ok(h.feed_text().size() == 2 and h.feed_text()[1].begins_with("Preparatory"), "signals in the feed")
	sim.race_ev = []
	_refresh(h, sim, 0, 58)
	t.ok(h.text_of("banner") != "", "banner still up in its 60th tick")
	_refresh(h, sim, 0, 1)
	t.ok(h.text_of("banner") == "" and not h.labels["banner"].visible, "banner gone after 3 s")
	sim.race_d["race_time"] = -59.0
	_refresh(h, sim)
	t.ok(_same(h.race.flags, ["class"]), "prep flag down at one minute")
	sim.race_d["race_time"] = -7.44
	_refresh(h, sim)
	t.ok(h.text_of("clock") == "Start in 0:07.4", "tenths in the last 10 s: " + h.text_of("clock"))
	sim.race_d["state"] = RaceText.RaceState.RACING
	sim.race_d["race_time"] = 65.2
	sim.race_d["x_flag"] = true
	_refresh(h, sim)
	t.ok(h.text_of("clock") == "Race  1:05" and _same(h.race.flags, ["X"]),
		"race clock and X flag: %s %s" % [h.text_of("clock"), str(h.race.flags)])
	sim.race_d["state"] = RaceText.RaceState.SEQUENCE
	sim.race_d["race_time"] = -330.0
	sim.race_d["x_flag"] = false
	sim.race_d["general_recalls"] = 1
	_refresh(h, sim)
	t.ok(h.race.flags.has("1st substitute") and h.text_of("clock").begins_with("Warning in"),
		"general recall: first substitute until the new warning (%s, %s)" % [str(h.race.flags), h.text_of("clock")])
	h.free()


# ---- §9.2 --------------------------------------------------------------------------------------------------------

func test_start_panel() -> void:
	t.begin("start line panel: time to burn, bias, OVER, OCS (hud.md §9.2, §15)")
	var sim := RaceStubSim.new()
	sim.race_d["race_time"] = -30.0
	# the bow 100 m behind the middle of the line at 5 m/s heading straight at it, 30 s before the gun
	sim.put(0, 0.0, -103.5, 0.0, 5.0)
	sim.line_status(0)
	sim.put(1, 50, -300, 0.0, 2.0)
	sim.line_status(1)
	var h := _hud(sim)
	h.refresh_text()
	var r := h.race
	t.near(r.line_dist, -100.0, 1e-3, "distance to line: s(bow)")
	t.near(r.t_line, 20.0, 1e-3, "t_line 20 s")
	t.near(r.burn, 10.0, 1e-3, "time to burn +10 s")
	t.ok(h.text_of("line") == "Line  -100 m" and h.text_of("tline") == "To line  0:20" and h.text_of("burn") == "Burn  +10 s",
		"%s | %s | %s" % [h.text_of("line"), h.text_of("tline"), h.text_of("burn")])
	# heading away from the line: the COG ray misses it
	sim.put(0, 0.0, -103.5, PI, 5.0)
	sim.line_status(0)
	_refresh(h, sim)
	t.ok(is_nan(h.race.t_line) and h.text_of("tline") == "To line  --" and h.text_of("burn") == "Burn  --",
		"COG ray misses the line: --")
	# too slow
	sim.put(0, 0.0, -103.5, 0.0, 0.2)
	sim.line_status(0)
	_refresh(h, sim)
	t.ok(is_nan(h.race.t_line), "SOG below 0.5 kn: --")
	# beyond an end: the distance to the nearer end
	sim.put(0, -130.0, -43.5, 0.0, 3.0)
	sim.line_status(0)
	_refresh(h, sim)
	t.ok(h.race.line_end and h.text_of("line") == "Line  50 m (end)", "beyond the pin end: " + h.text_of("line"))
	# bias: a 10 degree veer (wind from 010) favours the committee boat end B, by 200 sin 10 m
	sim.wind = Vector2(5.0, deg_to_rad(10.0))
	var h2 := _hud(sim)
	h2.refresh_text()
	t.near(rad_to_deg(h2.race.bias), 10.0, 1e-3, "bias 10 degrees")
	t.near(h2.race.bias_m, 200.0 * sin(deg_to_rad(10.0)), 1e-3, "bias upwind distance |du|")
	t.ok(h2.text_of("bias") == "Bias  BOAT +10° · 35 m", "bias text: " + h2.text_of("bias"))
	h2.free()
	sim.wind = Vector2(5.0, deg_to_rad(-7.0))
	var h3 := _hud(sim)
	h3.refresh_text()
	t.ok(h3.text_of("bias") == "Bias  PIN +7° · 24 m", "backed wind favours the pin: " + h3.text_of("bias"))
	h3.free()
	sim.wind = Vector2(5.0, 0.0)
	# OVER in the last minute under the I flag
	sim.race_d["race_time"] = -40.0
	sim.put(0, 0.0, 2.0, 0.0, 3.0)
	sim.line_status(0, true)
	_refresh(h, sim)
	t.ok(h.race.over and h.text_of("over") == "OVER  I flag: round an end", "over in the last minute: " + h.text_of("over"))
	sim.race_d["race_time"] = -70.0
	_refresh(h, sim)
	t.ok(not h.race.over and not h.labels["over"].visible, "no OVER before the last minute")
	# OCS after the gun, until returned; the panel stays until started
	sim.race_d["state"] = RaceText.RaceState.RACING
	sim.race_d["race_time"] = 5.0
	sim.boats_d[0]["ocs_i"] = true
	sim.race_ev = [_rev(RaceText.Ev.BOAT_OCS, {"boat": 0, "flag": RaceText.Flag.I})]
	_refresh(h, sim)
	t.ok(h.race.ocs and h.text_of("over") == "OVER  OCS: return around an end", "OCS-I: " + h.text_of("over"))
	t.ok(h.text_of("burn") == "", "no time to burn after the gun")
	sim.race_ev = []
	sim.boats_d[0]["ocs_i"] = false
	sim.boats_d[0]["started"] = true
	sim.boats_d[0]["next"] = 1
	_refresh(h, sim)
	t.ok(not h.race.start_panel and not h.labels["line"].visible and not h.race.over, "panel gone once started")
	h.free()


# ---- §7, §4 ------------------------------------------------------------------------------------------------------

func test_next_mark() -> void:
	t.begin("next mark, leg, ETA, VMG and VMC (hud.md §7, §4, §15)")
	var sim := RaceStubSim.new()
	sim.race_d["state"] = RaceText.RaceState.RACING
	sim.race_d["race_time"] = 100.0
	for b in 2:
		sim.boats_d[b]["started"] = true
		sim.boats_d[b]["next"] = 1
	# beating on starboard (heading 318, twa +42) at (200, 400)
	var psi := Frames.wrap_2pi(-deg_to_rad(42.0))
	sim.put(0, 200.0, 400.0, psi, 3.0)
	sim.put(1, 0, 0, 0.0, 3.0)
	var h := _hud(sim)
	_refresh(h, sim, 0, 200)
	var r := h.race
	var bow := Vector2(200, 400) + 3.5 * Vector2(sin(psi), cos(psi))
	var w := Vector2(0, 1000)
	t.ok(r.next_name == "Windward" and h.text_of("next") == "Windward", "label from the course file: " + h.text_of("next"))
	t.ok(h.text_of("lap") == "Lap 1/2 · Leg 1/4", "lap and leg: " + h.text_of("lap"))
	t.ok(_same(r.next_sides, [RaceText.Side.PORT]) and h.arrow_view.sides == r.next_sides, "leave to port arrow")
	t.near(r.next_dist, bow.distance_to(w) - 1.0, 1e-2, "distance: bow to the buoy centre minus its radius")
	var brg := Frames.compass(w.x - 200.0, w.y - 400.0)
	t.near(r.next_bearing, brg, 1e-4, "bearing")
	t.ok(h.text_of("bearing") == "Bearing  %s  (%s)" % [HudFormat.compass_deg(brg),
		HudFormat.relative_bearing(Frames.wrap_pi(brg - psi))], "bearing text: " + h.text_of("bearing"))
	t.ok(r.leg_type == "beat", "beat")
	t.near(r.vmg, 3.0 * cos(deg_to_rad(42.0)), 1e-3, "VMG on a beat: v cos(twa)")
	t.near(r.eta, (1000.0 - bow.y) / r.vmg, 0.5, "ETA: axis distance / VMG")
	t.ok(h.text_of("leg").begins_with("Beat  ·  ETA "), h.text_of("leg"))
	t.ok(h.text_of("vmg").begins_with("VMG  %s kn" % HudFormat.speed_kn(r.vmg)), h.text_of("vmg"))
	t.near(r.target_speed, 3.0, 1e-3, "target speed on a beat: V_up")
	t.near(r.vmg_pct, 100.0, 0.5, "VMG %% at the optimum")
	# no display smoothing (hud.md §1): a speed change shows in VMG, VMG % and VMC on the next tick
	sim.put(0, 200.0, 400.0, psi, 2.0)
	_refresh(h, sim, 0, 1)
	t.near(r.vmg, 2.0 * cos(deg_to_rad(42.0)), 1e-3, "VMG unsmoothed")
	t.near(r.vmg_pct, 100.0 * 2.0 / 3.0, 0.5, "VMG %% unsmoothed")
	t.near(r.vmc, 2.0 * Vector2(sin(psi), cos(psi)).dot((w - Vector2(200, 400)).normalized()), 1e-3, "VMC unsmoothed")
	# a run to the gate: VMG positive when sailing towards it
	for b in 2:
		sim.boats_d[b]["next"] = 2
	var psi_run := Frames.wrap_2pi(PI - deg_to_rad(30.0))
	sim.put(0, 60.0, 700.0, psi_run, 3.5)
	_refresh(h, sim, 0, 200)
	t.ok(r.leg_type == "run", "run to the gate")
	t.ok(r.vmg > 0.0, "VMG on a run is positive towards the leeward mark (%.2f)" % r.vmg)
	t.ok(r.next_name == "Gate Gate left / Gate right" and r.next_sides.size() == 2, "gate: both buoys' arrows: " + r.next_name)
	t.near(r.next_dist, (Vector2(60, 700) + 3.5 * Vector2(sin(psi_run), cos(psi_run))).distance_to(Vector2(20, 100)) - 1.0,
		1e-2, "gate: the nearer buoy")
	# sailing away from the mark: VMC negative (a reach)
	for b in 2:
		sim.boats_d[b]["next"] = 1
	sim.put(0, 900.0, 900.0, deg_to_rad(120.0), 3.0)
	_refresh(h, sim, 0, 200)
	t.ok(r.leg_type == "reach" and r.vmc < 0.0, "VMC negative when sailing away from the mark (%s, %.2f)" % [r.leg_type, r.vmc])
	t.ok(is_nan(r.eta) and h.text_of("leg") == "Reach  ·  ETA --:--", "ETA --:-- below 0.3 kn of VMC: " + h.text_of("leg"))
	t.ok(h.text_of("vmg").begins_with("VMC  "), "VMC replaces VMG on a reach")
	# the finish: distance to the nearest point of the line
	for b in 2:
		sim.boats_d[b]["next"] = 4
	sim.put(0, 150.0, 60.0, PI, 3.0)
	_refresh(h, sim)
	t.ok(r.next_name == "Finish" and absf(r.next_dist - Vector2(100, 0).distance_to(Vector2(150, 56.5))) < 1e-2,
		"finish: nearest point of the segment (%.2f)" % r.next_dist)
	h.free()


func test_laylines_shift_hint() -> void:
	t.begin("layline distance, overstood, shift meter, sail hint (hud.md §6, §3.2, §4)")
	var sim := RaceStubSim.new()
	sim.race_d["state"] = RaceText.RaceState.RACING
	sim.race_d["race_time"] = 100.0
	for b in 2:
		sim.boats_d[b]["started"] = true
		sim.boats_d[b]["next"] = 1
	var th := deg_to_rad(42.0)
	# on starboard (heading -42) at (300, 200): the port-tack layline through W runs back from W along 42 + 180
	var psi := Frames.wrap_2pi(-th)
	sim.put(0, 300.0, 200.0, psi, 3.0)
	sim.put(1, 0, 0, 0.0, 3.0)
	sim.polar_by_front[2] = 2.9
	var h := _hud(sim)
	h.assist = Hud.Assist.FULL
	_refresh(h, sim, 0, 5)
	var r := h.race
	# hand computation: c + s dir(-th) = W - l dir(th)
	var c := Vector2(300, 200)
	var d1 := Vector2(sin(-th), cos(-th))
	var d2 := Vector2(sin(th), cos(th))
	var wv := Vector2(0, 1000)
	var hit: Vector2 = Geometry2D.segment_intersects_segment(c, c + d1 * 1e5, wv, wv - d2 * 1e5)
	t.near(r.layline_dist, c.distance_to(hit), 0.5, "distance along the COG to the port layline")
	t.near(r.layline_time, c.distance_to(hit) / 3.0, 0.2, "time to the layline")
	t.ok(h.text_of("layline") == "Layline %s · %s" % [HudFormat.distance(r.layline_dist), HudFormat.clock(r.layline_time)],
		h.text_of("layline"))
	t.ok(r.laylines.size() == 2 and r.laylines[0]["a"] == wv, "two layline rays through the mark for the radar")
	# past the port layline on starboard: overstood by the perpendicular distance
	var beyond := wv - d2 * 800.0 + Vector2(-d2.y, d2.x) * 30.0
	sim.put(0, beyond.x, beyond.y, psi, 3.0)
	_refresh(h, sim, 0, 5)
	t.near(r.overstood, 30.0, 0.5, "OVERSTOOD 30 m")
	t.ok(h.text_of("layline") == "OVERSTOOD 30 m", h.text_of("layline"))
	# shift meter: a 5 degree veer held on starboard upwind lifts (heading VMG turns towards the mark)
	sim.put(0, 300.0, 200.0, psi, 3.0)
	_refresh(h, sim, 0, 5)
	sim.wind = Vector2(5.0, deg_to_rad(5.0))
	sim.put(0, 300.0, 200.0, psi, 3.0)
	_refresh(h, sim, 0, 200)
	t.ok(r.shift_kind == "header" or r.shift_kind == "lift", "shift shown after a 5 degree shift (%s %.1f)" % [r.shift_kind,
		rad_to_deg(r.shift)])
	# veer on starboard: psi_opt = TWD - th turns right (towards the mark to the left? mark bearing from c is ~343)
	var psi_opt := Frames.wrap_2pi(deg_to_rad(5.0) - th)
	var expect := "header" if r.shift * signf(Frames.wrap_pi(psi_opt - Frames.compass(-300.0, 800.0))) > 0.0 else "lift"
	t.ok(r.shift_kind == expect, "lift or header by the rule of hud.md §3.2 (%s)" % expect)
	t.ok(h.text_of("shift").begins_with(expect.to_upper()), h.text_of("shift"))
	h.assist = Hud.Assist.MINIMAL
	h.refresh_text()
	t.ok(h.text_of("shift") == "" and h.text_of("layline") == "", "Minimal: no shift meter, no layline distance")
	# sail hint on Full: the code zero 13 % faster than the jib for 5 s
	h.assist = Hud.Assist.FULL
	sim.wind = Vector2(5.0, 0.0)
	sim.polar_by_front[2] = 3.4
	sim.put(0, 900.0, 900.0, deg_to_rad(250.0), 3.0)
	_refresh(h, sim, 0, 99)
	t.ok(r.sail_hint == "", "no hint before 5 s")
	_refresh(h, sim, 0, 2)
	t.ok(r.sail_hint == "Code Zero +13 %" and h.text_of("hint") == r.sail_hint, "sail hint: " + r.sail_hint)
	h.assist = Hud.Assist.STANDARD
	h.refresh_text()
	t.ok(h.text_of("hint") == "", "sail hint on Full only")
	h.free()


# ---- §10 ---------------------------------------------------------------------------------------------------------

func test_position() -> void:
	t.begin("rank with hysteresis, gaps and splits (hud.md §10)")
	var sim := RaceStubSim.new(3)
	sim.race_d["state"] = RaceText.RaceState.RACING
	sim.race_d["race_time"] = 300.0
	for b in 3:
		sim.boats_d[b]["started"] = true
		sim.boats_d[b]["next"] = 2
		sim.boats_d[b]["last_rounded"] = 1
		sim.put(b, 100.0 * b, 500.0, PI, 3.0)
	sim.boats_d[0]["D"] = 1500.0
	sim.boats_d[1]["D"] = 1400.0
	sim.boats_d[2]["D"] = 1600.0
	sim.order = PackedInt32Array([1, 0, 2])
	sim.splits = {"0:1": 250.0, "1:1": 232.0, "2:1": 260.0}
	var h := _hud(sim)
	h.race.names = {1: "Nora"}
	_refresh(h, sim)
	t.ok(h.text_of("rank") == "2 / 3", "rank: " + h.text_of("rank"))
	t.ok(h.text_of("gap") == "Leader  +100 m  +0:18 @ Windward", "gap to the leader at the common split: " + h.text_of("gap"))
	t.ok(h.text_of("ahead") == "Ahead  Nora  +100 m" and h.text_of("behind") == "Behind  Boat 3  -100 m",
		"%s | %s" % [h.text_of("ahead"), h.text_of("behind")])
	# the order flips: shown only after it has held for 2 s
	sim.order = PackedInt32Array([0, 1, 2])
	_refresh(h, sim, 0, 39)
	t.ok(h.race.rank == 2, "new order not shown before 2 s")
	_refresh(h, sim, 0, 2)
	t.ok(h.race.rank == 1 and h.text_of("gap") == "Leading", "new order shown after 2 s: %d %s" % [h.race.rank, h.text_of("gap")])
	# a flicker shorter than 2 s is never shown
	sim.order = PackedInt32Array([1, 0, 2])
	_refresh(h, sim, 0, 10)
	sim.order = PackedInt32Array([0, 1, 2])
	_refresh(h, sim, 0, 35)
	t.ok(h.race.rank == 1, "a short flicker does not change the rank")
	# the leader rounds the next mark: the gap becomes an estimate
	sim.order = PackedInt32Array([1, 0, 2])
	sim.boats_d[1]["last_rounded"] = 2
	sim.boats_d[1]["next"] = 3
	_refresh(h, sim, 0, 45)
	t.ok(h.race.gap_estimate and h.text_of("gap").contains("~+"), "between splits the estimate, marked ~: " + h.text_of("gap"))
	# a finish changes the order at once
	sim.boats_d[2]["finished"] = true
	sim.boats_d[2]["place"] = 1
	sim.order = PackedInt32Array([2, 1, 0])
	_refresh(h, sim)
	t.ok(h.race.rank == 3, "a finish changes the rank at once (%d)" % h.race.rank)
	# split banner on rounding
	sim.splits["0:2"] = 400.0
	sim.splits["1:2"] = 380.0
	sim.race_ev = [_rev(RaceText.Ev.ROUNDED, {"boat": 0, "step": 2})]
	_refresh(h, sim)
	sim.race_ev = []
	t.ok(h.text_of("banner") == "Gate · 2nd · +0:20", "split at rounding: " + h.text_of("banner"))
	h.show_ranking = true
	_refresh(h, sim)
	var rows := h.ranking_text()
	t.ok(h.ranking_panel.visible and rows.size() == 3 and rows[0].begins_with("1  Boat 3"), "ranking list: %s" % str(rows))
	h.free()


# ---- §11 ---------------------------------------------------------------------------------------------------------

func test_rules_messages() -> void:
	t.begin("rules awareness lines (hud.md §11)")
	var sim := RaceStubSim.new(3)
	sim.race_d["state"] = RaceText.RaceState.RACING
	sim.race_d["race_time"] = 100.0
	for b in 3:
		sim.boats_d[b]["started"] = true
		sim.boats_d[b]["next"] = 1
		sim.put(b, 20.0 * b, 300.0, 0.7, 3.0)
	var h := _hud(sim)
	h.race.names = {1: "Nora", 2: "Ivo"}
	var R := RaceText.Rule
	var cases := [
		[{"kc_giver": 0, "kc_holder": 1, "kc_rule": R.R10, "kc_state": 2},
			"KEEP CLEAR: Port tack keeps clear of starboard (Nora)", RaceHudValues.Tint.RED],
		[{"kc_giver": 0, "kc_holder": 1, "kc_rule": R.R11, "kc_state": 1},
			"Keep clear: Windward boat keeps clear (Nora)", RaceHudValues.Tint.ORANGE],
		[{"room_giver": 0, "room_entitled": 1, "room_rule": R.R18_2, "room_state": 1}, "Give mark-room to Nora",
			RaceHudValues.Tint.ORANGE],
		[{"room_giver": 0, "room_entitled": 1, "room_rule": R.R19, "room_state": 2},
			"Give room at the obstruction (Nora)", RaceHudValues.Tint.RED],
		[{"room_giver": 1, "room_entitled": 0, "room_rule": R.R18_2}, "You have mark-room", RaceHudValues.Tint.CYAN],
		[{"rule17_holder": 0}, "Don't sail above your proper course (rule 17)", RaceHudValues.Tint.YELLOW],
		[{"kc_giver": 1, "kc_holder": 0, "kc_rule": R.R10, "kc_state": 1}, "Starboard!", RaceHudValues.Tint.GREEN],
		[{"kc_giver": 1, "kc_holder": 0, "kc_rule": R.R11, "kc_state": 1}, "Leeward!", RaceHudValues.Tint.GREEN],
		[{"kc_giver": 1, "kc_holder": 0, "kc_rule": R.R12, "kc_state": 2}, "Clear ahead: right of way",
			RaceHudValues.Tint.GREEN],
	]
	for cs in cases:
		sim.pairs_a = [sim.pair(0, 1, cs[0])]
		_refresh(h, sim)
		t.ok(h.text_of("rules") == cs[1] and h.labels["rules"].get_theme_color("font_color") == Hud.TINT_COLOURS[cs[2]],
			"%s (got %s)" % [cs[1], h.text_of("rules")])
	sim.pairs_a = [sim.pair(0, 1, {"kc_giver": 1, "kc_holder": 0, "kc_rule": R.R10, "kc_state": 0})]
	_refresh(h, sim)
	t.ok(h.text_of("rules") == "", "right of way with the other boat Clear: no line")
	# priority: a breach with one boat beats a warning with another
	sim.pairs_a = [sim.pair(0, 1, {"kc_giver": 0, "kc_holder": 1, "kc_rule": R.R11, "kc_state": 1}),
		sim.pair(0, 2, {"kc_giver": 0, "kc_holder": 2, "kc_rule": R.R10, "kc_state": 2})]
	_refresh(h, sim)
	t.ok(h.text_of("rules").begins_with("KEEP CLEAR") and h.text_of("rules").ends_with("(Ivo)") and h.race.message.other == 2,
		"highest priority first: " + h.text_of("rules"))
	# Minimal: Breach lines only
	h.assist = Hud.Assist.MINIMAL
	_refresh(h, sim)
	t.ok(h.text_of("rules").begins_with("KEEP CLEAR"), "Minimal shows a breach")
	sim.pairs_a = [sim.pair(0, 1, {"kc_giver": 0, "kc_holder": 1, "kc_rule": R.R11, "kc_state": 1})]
	_refresh(h, sim)
	t.ok(h.text_of("rules") == "", "Minimal hides a warning")
	# pairs not involving the viewed boat are ignored
	h.assist = Hud.Assist.STANDARD
	sim.pairs_a = [sim.pair(1, 2, {"kc_giver": 1, "kc_holder": 2, "kc_rule": R.R10, "kc_state": 2})]
	_refresh(h, sim)
	t.ok(h.text_of("rules") == "", "other boats' pairs ignored")
	# rule warning events go out for audio
	var got := []
	h.hud_event.connect(func(k: String, d: Dictionary) -> void: got.append([k, d]))
	sim.rules_ev = [_uev(RaceText.Rev.RULE_WARNING, {"boat": 1, "other": 0, "rule": R.R10})]
	_refresh(h, sim)
	sim.rules_ev = []
	t.ok(got.size() == 1 and got[0][0] == "rule_warning" and got[0][1]["holder"] == 0, "rule_warning event: %s" % str(got))
	h.free()


# ---- §8 ----------------------------------------------------------------------------------------------------------

func test_radar_colours() -> void:
	t.begin("radar colours from the pair records (hud.md §8, §15; rules.md §13 scenarios)")
	var sim := RaceStubSim.new(4)
	sim.race_d["state"] = RaceText.RaceState.RACING
	sim.race_d["race_time"] = 100.0
	for b in 4:
		sim.boats_d[b]["started"] = true
		sim.boats_d[b]["next"] = 1
	sim.put(0, 0, 300, 0.7, 3.0)
	sim.put(1, 60, 330, -0.7, 3.0)
	sim.put(2, -40, 290, 0.7, 3.0)
	sim.put(3, 30, 250, 0.7, 3.0)
	var h := _hud(sim)
	var R := RaceText.Rule
	var T := RaceHudValues.Tint
	var P := RaceHudValues.Pulse
	var scen := [
		# port-starboard: me on port (giver) / me on starboard (holder)
		["port-starboard, I am on port", {"kc_giver": 0, "kc_holder": 1, "kc_rule": R.R10, "kc_state": 1}, T.RED, P.WARNING],
		["port-starboard, I am on starboard", {"kc_giver": 1, "kc_holder": 0, "kc_rule": R.R10, "kc_state": 0}, T.GREEN, P.NONE],
		["windward-leeward, I am windward", {"kc_giver": 0, "kc_holder": 1, "kc_rule": R.R11, "kc_state": 2}, T.RED, P.BREACH],
		["windward-leeward, I am leeward", {"kc_giver": 1, "kc_holder": 0, "kc_rule": R.R11, "kc_state": 1}, T.GREEN, P.WARNING],
		["mark-room, I owe it", {"kc_giver": 1, "kc_holder": 0, "kc_rule": R.R11, "room_giver": 0, "room_entitled": 1,
			"room_rule": R.R18_2, "room_state": 1}, T.ORANGE, P.WARNING],
		["mark-room, she owes it", {"kc_giver": 0, "kc_holder": 1, "kc_rule": R.R11, "room_giver": 1, "room_entitled": 0,
			"room_rule": R.R18_2, "room_state": 0}, T.CYAN, P.NONE],
		["no relation", {}, T.WHITE, P.NONE],
	]
	for sc in scen:
		sim.pairs_a = [sim.pair(0, 1, sc[1])]
		_refresh(h, sim)
		var ct := h.race.contact(1)
		t.ok(ct != null and ct.tint == sc[2] and ct.pulse == sc[3], "%s: tint %d pulse %d" % [sc[0], ct.tint, ct.pulse])
	# the radar draws them in those colours; ghosts grey; Minimal all white
	sim.pairs_a = [sim.pair(0, 1, {"kc_giver": 0, "kc_holder": 1, "kc_rule": R.R10, "kc_state": 0}),
		sim.pair(0, 3, {"kc_giver": 3, "kc_holder": 0, "kc_rule": R.R12})]
	sim.boats_d[2]["ghost"] = true
	_refresh(h, sim)
	h.radar.size = Vector2(230, 230)
	h.radar.drawn = h.radar.contact_colours()
	t.ok(h.radar.drawn.get(1) == RadarView.TINTS[T.RED] and h.radar.drawn.get(3) == RadarView.TINTS[T.GREEN],
		"drawn red and green: %s" % str(h.radar.drawn))
	t.ok(h.radar.drawn.get(2) == RadarView.TINTS[T.GREY], "ghost grey translucent")
	# pulsing: the Warning colour moves at 2 Hz
	sim.pairs_a = [sim.pair(0, 1, {"kc_giver": 0, "kc_holder": 1, "kc_rule": R.R10, "kc_state": 1})]
	_refresh(h, sim)
	var ct1 := h.race.contact(1)
	h.radar._t = 0.125
	var c_a := h.radar.contact_colour(ct1)
	h.radar._t = 0.375
	var c_b := h.radar.contact_colour(ct1)
	h.radar._t = 0.625
	t.ok(c_a != c_b and h.radar.contact_colour(ct1).is_equal_approx(c_a), "Warning pulses at 2 Hz")
	h.assist = Hud.Assist.MINIMAL
	h.frame(0.01)
	t.ok(h.radar.contact_colour(ct1) == RadarView.TINTS[T.WHITE], "Minimal: all white")
	h.assist = Hud.Assist.STANDARD
	# range and orientation
	var r0 := h.radar.range_m()
	h.radar.zoom(1)
	t.near(h.radar.range_m(), r0 * 1.5, 1e-3, "range steps of x1.5")
	h.radar.zoom(-1)
	var up := h.radar.north_up
	var raw := RawInput.new()
	raw.pressed.append(&"radar_orientation")
	h.ui_input(raw)
	t.ok(h.radar.north_up != up, "radar orientation key")
	h.radar.toggle_orientation()
	h.free()


# ---- §12, prompts ------------------------------------------------------------------------------------------------

func test_penalties_prompts() -> void:
	t.begin("penalty panel, messages, protest and hail prompts (hud.md §12, §11)")
	var sim := RaceStubSim.new()
	sim.race_d["state"] = RaceText.RaceState.RACING
	sim.race_d["race_time"] = 100.0
	for b in 2:
		sim.boats_d[b]["started"] = true
		sim.boats_d[b]["next"] = 1
	sim.put(0, 0, 500, 0.7, 3.0)
	sim.put(1, 100, 500, 0.7, 3.0)
	var h := _hud(sim)
	h.race.names = {1: "Nora"}
	t.ok(not h.penalty_panel.visible, "no panel without a penalty")
	var R := RaceText.Rule
	sim.rules_ev = [_uev(RaceText.Rev.PENALTY, {"boat": 0, "other": 1, "rule": R.R10})]
	sim.rules_d[0] = {"pending": [{"rule": R.R10, "other": 1, "count": 1}], "turn_progress": 0.0, "turn_tacks": 0,
		"turn_gybes": 0, "deadline_s": 32.4, "received": 1, "turning_for_penalty": false}
	_refresh(h, sim)
	sim.rules_ev = []
	t.ok(h.text_of("banner") == "PENALTY: Port tack keeps clear of starboard (Nora)", "penalty banner: " + h.text_of("banner"))
	t.ok(h.penalty_panel.visible and h.text_of("pen_head") == "Penalty: Port tack keeps clear of starboard (Nora)",
		h.text_of("pen_head"))
	t.ok(h.text_of("pen_deadline") == "Deadline  0:32", "deadline: " + h.text_of("pen_deadline"))
	t.ok(h.text_of("pen_turn") == "Sail clear and turn: one tack and one gybe", h.text_of("pen_turn"))
	# turning: the ring fills, tack tick lit
	sim.rules_d[0]["turning_for_penalty"] = true
	sim.rules_d[0]["turn_progress"] = deg_to_rad(-210.0)
	sim.rules_d[0]["turn_tacks"] = 1
	_refresh(h, sim)
	t.ok(h.text_of("pen_turn") == "Turn: 210°" and h.ring_view.turn_deg > 209.9 and h.ring_view.tack_done
		and not h.ring_view.gybe_done, "turn progress: " + h.text_of("pen_turn"))
	# in the zone of the next mark: not counted
	sim.put(0, 0, 985, 0.7, 3.0)
	_refresh(h, sim)
	t.ok(h.text_of("pen_turn") == "Not counted: inside the zone", h.text_of("pen_turn"))
	# the turn resets
	sim.put(0, 0, 500, 0.7, 3.0)
	sim.rules_d[0]["turning_for_penalty"] = false
	sim.rules_d[0]["turn_progress"] = 0.0
	_refresh(h, sim)
	t.ok(h.text_of("pen_turn").begins_with("Turn reset"), "turn reset: " + h.text_of("pen_turn"))
	# deadline red below 10 s, dsq warning at dsq_pending - 1 pending
	sim.rules_d[0]["deadline_s"] = 8.0
	sim.rules_d[0]["pending"] = [{"rule": R.R10, "other": 1, "count": 1}, {"rule": R.R31, "other": -1, "count": 1}]
	_refresh(h, sim)
	t.ok(h.labels["pen_deadline"].get_theme_color("font_color") == Hud.TINT_COLOURS[RaceHudValues.Tint.RED],
		"deadline red below 10 s")
	t.ok(h.text_of("pen_head") == "Penalty 1 of 2: Port tack keeps clear of starboard (Nora)", h.text_of("pen_head"))
	t.ok(h.text_of("pen_dsq") == "One more penalty = disqualification", "disqualification warning")
	# finish blocked, late, served
	sim.race_ev = [_rev(RaceText.Ev.FINISH_BLOCKED, {"boat": 0, "block": 0})]
	_refresh(h, sim)
	sim.race_ev = []
	t.ok(h.text_of("banner") == "Take your penalty before finishing", h.text_of("banner"))
	sim.rules_ev = [_uev(RaceText.Rev.PENALTY_LATE, {"boat": 0})]
	_refresh(h, sim)
	t.ok(h.text_of("banner") == "Penalty not taken in time: +1 turn", h.text_of("banner"))
	sim.rules_ev = [_uev(RaceText.Rev.PENALTY_SERVED, {"boat": 0, "rule": R.R10})]
	sim.rules_d[0]["pending"] = []
	sim.rules_d[0]["deadline_s"] = -1.0
	_refresh(h, sim)
	sim.rules_ev = []
	t.ok(h.text_of("banner") == "Penalty done", "penalty done banner")
	_refresh(h, sim, 0, 101)
	t.ok(not h.penalty_panel.visible, "panel hidden 5 s after the last penalty")
	# other boats' penalties go to the feed
	sim.rules_ev = [_uev(RaceText.Rev.PENALTY, {"boat": 1, "other": 0, "rule": R.R11})]
	_refresh(h, sim)
	sim.rules_ev = []
	t.ok(h.feed_text().has("Nora penalised, rule 11 (You)"), "fleet feed: %s" % str(h.feed_text()))
	# disqualified: a full-width banner
	sim.rules_ev = [_uev(RaceText.Rev.DISQUALIFIED, {"boat": 0})]
	_refresh(h, sim)
	sim.rules_ev = []
	t.ok(h.race.banner.full and h.text_of("banner") == "DISQUALIFIED: too many penalties", h.text_of("banner"))
	# protest prompt with its 8 s countdown, wired into PlayerControls
	var pc := PlayerControls.new()
	h.frame(0.01, pc)
	t.ok(not pc.protest_prompt.call(), "no protest prompt")
	sim.rules_ev = [_uev(RaceText.Rev.PROTESTABLE, {"boat": 1, "other": 0, "rule": R.R11, "deadline": 8.0})]
	_refresh(h, sim)
	sim.rules_ev = []
	h.frame(0.01, pc)
	t.ok(pc.protest_prompt.call() and h.text_of("prompt") == "Protest Nora (rule 11)? [P]  8", "protest prompt: " + h.text_of("prompt"))
	_refresh(h, sim, 0, 158)
	t.ok(pc.protest_prompt.call(), "prompt still shown just before 8 s")
	_refresh(h, sim, 0, 2)
	t.ok(not pc.protest_prompt.call() and h.text_of("prompt") == "", "prompt gone after 8 s")
	# hail (rules.md §7.9, optional): the button and the reply prompt
	sim.hail = {"available": true, "hailed_by": -1}
	_refresh(h, sim)
	t.ok(pc.hail_available.call() and h.text_of("prompt") == "Hail: room to tack [H]", "hail button: " + h.text_of("prompt"))
	sim.hail = {"available": false, "hailed_by": 1}
	_refresh(h, sim)
	t.ok(pc.hailed.call() and h.text_of("prompt") == "Nora hails for room to tack: tack, or reply [H] you tack",
		h.text_of("prompt"))
	h.free()


# ---- §13 ---------------------------------------------------------------------------------------------------------

func test_results_feed() -> void:
	t.begin("finish, feed and results (hud.md §10, §13)")
	var sim := RaceStubSim.new(3)
	sim.race_d["state"] = RaceText.RaceState.RACING
	sim.race_d["race_time"] = 1500.0
	for b in 3:
		sim.boats_d[b]["started"] = true
		sim.boats_d[b]["next"] = 4
		sim.put(b, 10.0 * b, 20.0, PI, 3.0)
	var h := _hud(sim)
	h.race.names = {1: "Nora", 2: "Ivo"}
	h.race.ai_levels = {1: "Expert", 2: "Pro"}
	sim.boats_d[1]["finished"] = true
	sim.boats_d[1]["place"] = 1
	sim.boats_d[1]["t_finish_us"] = 1400000000
	sim.race_ev = [_rev(RaceText.Ev.FINISHED, {"boat": 1, "place": 1, "t_us": 1400000000})]
	_refresh(h, sim)
	t.ok(h.feed_text().has("Nora finishes 1st"), "finish in the feed")
	sim.boats_d[0]["finished"] = true
	sim.boats_d[0]["place"] = 2
	sim.boats_d[0]["t_finish_us"] = 1412350000
	sim.order = PackedInt32Array([1, 0, 2])
	sim.race_ev = [_rev(RaceText.Ev.FINISHED, {"boat": 0, "place": 2, "t_us": 1412350000})]
	_refresh(h, sim)
	sim.race_ev = []
	t.ok(h.text_of("banner") == "Finished 2nd · 0:23:32.35 · +0:12", "finish banner: " + h.text_of("banner"))
	t.ok(h.text_of("clock") == "Finished  0:23:32.35", h.text_of("clock"))
	t.ok(h.race.results_visible and not h.race.results_final and h.race.result_rows.size() == 3, "provisional results")
	# the close: the core's results, the projected AI finish marked
	sim.results_a = [
		{"boat": 1, "place": 1, "code": 0, "code_name": "", "points": 1.0, "t_finish_us": 1400000000, "projected": false},
		{"boat": 0, "place": 2, "code": 0, "code_name": "", "points": 2.0, "t_finish_us": 1412350000, "projected": false},
		{"boat": 2, "place": 3, "code": 0, "code_name": "", "points": 3.0, "t_finish_us": 1500000000, "projected": true},
	]
	sim.race_d["state"] = RaceText.RaceState.CLOSED
	sim.race_ev = [_rev(RaceText.Ev.RACE_CLOSED, {})]
	_refresh(h, sim)
	sim.race_ev = []
	var rows := h.results_text_rows()
	t.ok(h.race.results_final and h.results_panel.visible and h.results_title.text == "Results", "final results shown")
	t.ok(rows.size() == 3 and rows[0] == ["1", "Nora", "", "Expert", "0:23:20.00", "", "", "1"], "row 1: %s" % str(rows[0]))
	t.ok(rows[1][4] == "0:23:32.35" and rows[1][5] == "+0:12" and rows[1][1] == "You", "row 2: %s" % str(rows[1]))
	t.ok(rows[2][4] == "0:25:00.00 proj." and rows[2][3] == "Pro", "projected AI finish marked: %s" % str(rows[2]))
	h.free()


# ---- §14, text ---------------------------------------------------------------------------------------------------

func test_assists_text() -> void:
	t.begin("assist presets (hud.md §14) and the player text")
	var h := Hud.new()
	var table := {
		"laylines": [true, true, false], "layline_distance": [true, true, false], "zone": [true, true, false],
		"radar_colours": [true, true, false], "shift": [true, true, false], "burn_bias": [true, true, false],
		"shadow_view": [true, false, false], "sail_hint": [true, false, false],
	}
	var ok := true
	for k in table:
		for a in 3:
			h.assist = a
			ok = ok and h.shows(k) == table[k][a]
	t.ok(ok, "each element per preset as the table")
	h.free()
	# the start line panel on Minimal: distance only
	var sim := RaceStubSim.new()
	sim.race_d["race_time"] = -30.0
	sim.put(0, 0.0, -103.5, 0.0, 5.0)
	sim.line_status(0)
	sim.line_status(1)
	var h2 := _hud(sim)
	h2.assist = Hud.Assist.MINIMAL
	h2.refresh_text()
	t.ok(h2.text_of("line") != "" and h2.text_of("tline") == "" and h2.text_of("burn") == "" and h2.text_of("bias") == "",
		"Minimal start: distance to line only")
	# no em dash in any text the race HUD wrote, nor in the tables behind it
	var dash := false
	for k in h2.labels:
		dash = dash or h2.text_of(k).contains("—")
	for v in RaceText.RULE_TEXT.values() + RaceText.PREP_MEANING + RaceText.OVER_CONSEQUENCE:
		dash = dash or str(v).contains("—")
	for k in 7:
		dash = dash or RaceText.signal_banner(k, 1).contains("—")
	t.ok(not dash, "no em dash")
	t.ok(RaceText.rule_text(RaceText.Rule.R16_2) == "Don't bear away onto a ducking port boat"
		and RaceText.rule_text("30.1") == "Over early (I flag)" and RaceText.RULE_CODES.size() == 22, "rule texts of §12.3")
	h2.free()


func test_fake_sim() -> void:
	t.begin("no race: FakeSim and free sailing")
	var fs := FakeSim.new()
	var b := fs.add_boat("wm7", 0.0, 0.0, 0.5, 2.5)
	var h := _hud(fs, b)
	t.ok(not h.race.active and not h.race_panel.visible and not h.radar.visible and not h.next_panel.visible,
		"race panels hidden without a race")
	h.free()


# ---- §15 layline test on the core --------------------------------------------------------------------------------

func test_layline_core() -> void:
	t.begin("layline test on the core (hud.md §15): the starboard layline fetches the mark")
	var sim := CoreSimSource.new()
	sim.settings = {"race_seed": 7, "wind_speed": 10.0 * KNOT, "wind_from": 0.0, "shift_preset": 0, "puffs": false,
		"oscillation": false, "sea": false, "shadows": false}
	if not t.ok(sim.create(""), "open water world: " + sim.last_error()):
		return
	var b := sim.add_boat("wm7", 0.0, 0.0, 0.0)
	var loa := sim.class_info(b).loa
	# the felt wind of a boat sailing in this steady wind, then the layline angle from the polar at it
	for i in 200:
		sim.step()
	var felt := sim.state(b)
	var vm: Dictionary = sim.polar_vmg(b, felt.tws)
	var th: float = vm["up_twa"]
	var psi := Frames.wrap_2pi(felt.twd_from - th)
	var mark := Vector2(0.0, 0.0)
	var start := mark - 400.0 * Vector2(sin(psi), cos(psi))
	sim.place_boat(b, start.x, start.y, psi)
	var best := INF
	var integ := 0.0
	var err_max := 0.0
	for i in 8000:
		var s := sim.state(b)
		var e := Frames.wrap_pi(psi - s.psi)
		integ = clampf(integ + e * SimSource.DT, -0.2, 0.2)
		if i > 100:
			err_max = maxf(err_max, absf(e))
		sim.core.set_helm(b, clampf(3.0 * e + 1.5 * integ, -0.5, 0.5))
		sim.step()
		s = sim.state(b)
		best = minf(best, Vector2(s.pos_x, s.pos_y).distance_to(mark))
		if (Vector2(s.pos_x, s.pos_y) - mark).dot(Vector2(sin(psi), cos(psi))) > 30.0:
			break
	print("  layline: heading error after settling at most %.2f deg" % rad_to_deg(err_max))
	var s := sim.state(b)
	print("  layline: theta_up %.1f deg, felt twa %.1f deg, closest approach %.2f m (L %.2f m)"
		% [rad_to_deg(th), rad_to_deg(s.twa), best, loa])
	t.ok(best <= 0.5 * loa, "reaches the mark within 0.5 L (%.2f m)" % best)


# ---- a real race on the core -------------------------------------------------------------------------------------

func _core_race(seed_: int) -> CoreSimSource:
	var sim := CoreSimSource.new()
	sim.settings = {"race_seed": seed_, "wind_speed": 11.0 * KNOT, "wind_from": 0.2, "shift_preset": 1,
		"free_sailing_s": 10.0}
	if not sim.create("example_bay"):
		t.ok(false, "world: " + sim.last_error())
		return null
	sim.add_entry("wm7", {"human": true})
	sim.add_entry("wm7", {"human": true})
	if not sim.create_race("example_bay/example_wl"):
		t.ok(false, "race: " + sim.last_error())
		return null
	return sim


func test_core_race() -> void:
	t.begin("a race on the core: example_bay/example_wl, two boats from the spawn to the results")
	var sim := _core_race(20260925)
	if sim == null:
		return
	var h := Hud.new()
	get_root().add_child(h)
	h.race.names = {1: "Nora"}
	var pilot := RacePilot.new(sim)
	var seen_signals := {}
	var banners := {}
	var clock_kinds := {}
	var flags_ok := true
	var line_ok := true
	var burn_ok := true
	var next_ok := true
	var rank_ok := true
	var radar_ok := true
	var pairs_seen := 0
	var penalty_seen := false
	var pen_ok := true
	var feeds := {}
	var closed := false
	var events := []
	h.hud_event.connect(func(k: String, d: Dictionary) -> void: events.append(k))
	var n := 0
	while n < 60000 and not closed:
		pilot.steer()
		sim.step()
		h.tick(sim, 0)
		n += 1
		var race := sim.race()
		var rt: float = race["race_time"]
		var st: int = race["state"]
		for e in sim.race_events():
			if int(e["kind"]) == RaceText.Ev.SIGNAL:
				seen_signals[int(e["signal"])] = true
			if int(e["kind"]) == RaceText.Ev.RACE_CLOSED:
				closed = true
		if h.race.banner != null:
			banners[h.race.banner.text] = true
		for l in h.race.feed:
			feeds[l.text] = true
		var r := h.race
		# flags against the race state
		if st == RaceText.RaceState.SEQUENCE:
			var want_class := rt >= -r.warning_time and rt < 0.0
			var want_prep := rt >= -(r.warning_time - 60.0) and rt < -60.0
			flags_ok = flags_ok and r.flags.has("class") == want_class and (r.flags.size() > 1) == (want_prep or bool(race["x_flag"]))
		# the start panel against the core's line status
		var rb := sim.race_boat(0)
		var ss := sim.race_start_status(0)
		if r.start_panel and not r.line_end:
			line_ok = line_ok and absf(r.line_dist - float(ss["s_bow"])) < 1e-3
		if r.start_panel and rt < 0.0 and not is_nan(r.burn):
			burn_ok = burn_ok and absf(r.burn - (-rt - r.t_line)) < 1e-3
		if r.over and rt < 0.0:
			line_ok = line_ok and bool(ss["over"])
		# next step, rank and radar colours against the records
		if bool(rb["started"]) and not bool(rb["finished"]):
			next_ok = next_ok and r.next_step == int(rb["next"])
		rank_ok = rank_ok and r.fleet == 2
		for p in sim.pairs():
			pairs_seen += 1
			var ct := r.contact(1)
			var want := RaceHudValues.Tint.WHITE
			if int(p["room_rule"]) != 0 and int(p["room_giver"]) == 0:
				want = RaceHudValues.Tint.ORANGE
			elif int(p["room_rule"]) != 0 and int(p["room_entitled"]) == 0:
				want = RaceHudValues.Tint.CYAN
			elif int(p["kc_rule"]) != 0 and int(p["kc_giver"]) == 0:
				want = RaceHudValues.Tint.RED
			elif int(p["kc_rule"]) != 0 and int(p["kc_holder"]) == 0:
				want = RaceHudValues.Tint.GREEN
			radar_ok = radar_ok and ct != null and (ct.ghost or ct.tint == want)
		var br := sim.boat_rules(0)
		if br.get("pending", []).size() > 0:
			penalty_seen = true
			pen_ok = pen_ok and r.penalty_visible and r.pending == br["pending"].size()
		if n % 5 == 0:
			h.frame(0.25)
			h.refresh_text()
			var ck := h.text_of("clock")
			clock_kinds[ck.get_slice(" ", 0)] = true
	h.frame(0.25)
	h.refresh_text()
	var rb0 := sim.race_boat(0)
	print("  core race: %d ticks, signals %s, finished %s, pairs seen %d, penalty %s, clock kinds %s"
		% [n, str(seen_signals.keys()), str(rb0["finished"]), pairs_seen, str(penalty_seen), str(clock_kinds.keys())])
	print("  banners: %s" % str(banners.keys()))
	print("  feed: %s" % str(h.feed_text()))
	t.ok(seen_signals.has(0) and seen_signals.has(1) and seen_signals.has(2) and seen_signals.has(3), "all four signals")
	t.ok(banners.has("Warning signal: class flag up") and banners.has("One minute") and feeds.has("Start"),
		"signal banners and the start in the feed")
	t.ok(clock_kinds.has("Warning") and clock_kinds.has("Start") and clock_kinds.has("Race"), "clock: warning, start, race")
	t.ok(flags_ok, "flags row follows the race state")
	t.ok(line_ok, "start line distance and OVER are the core's")
	t.ok(burn_ok, "time to burn = time to the gun - time to the line")
	t.ok(next_ok, "next step is the core's")
	t.ok(rank_ok, "fleet of two")
	t.ok(radar_ok, "radar colours follow the core's pair records (%d pair ticks)" % pairs_seen)
	t.ok(pen_ok, "penalty panel follows the core's pending penalties")
	t.ok(bool(rb0["finished"]), "the boat finished")
	var fb := banners.keys().filter(func(k: String) -> bool: return k.begins_with("Finished "))
	t.ok(fb.size() == 1, "finish banner: %s" % str(fb))
	t.ok(closed and h.race.results_final and h.results_panel.visible and h.race.result_rows.size() == 2,
		"results panel after the close (%d rows)" % h.race.result_rows.size())
	t.ok(events.has("signal") and events.has("finished") and events.has("results"), "hud events for audio")
	for row in h.results_text_rows():
		print("  result: %s" % " | ".join(row))
	h.free()


# ---- the sail test scene in race mode ------------------------------------------------------------------------------

func test_scene_race() -> void:
	t.begin("sail test scene in race mode with AI boats: the race HUD, no stand-in")
	var sc: Node = (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	sc.set("auto_process", false)
	sc.set("sim_kind", 1)  # CORE
	sc.set("race_mode", true)
	sc.set("fleet_size", 4)
	sc.set("ai_level", "expert")
	sc.set("with_pause_menu", false)
	sc.set("apply_settings", false)
	sc.set("core_settings", {"free_sailing_s": 5.0})
	get_root().add_child(sc)
	sc.set("scripted_input", RawInput.new())
	await process_frame
	var hud: Hud = sc.get("hud")
	for i in 400:
		sc.call("step_frame", 1.0 / 30.0)
	hud.refresh_text()
	var raw: RawInput = sc.get("scripted_input")
	raw.held[&"rankings"] = true
	sc.call("step_frame", 1.0 / 30.0)
	var rows := hud.ranking_text()
	print("  scene ranking: %s" % str(rows))
	t.ok(hud.race.active and hud.race_panel.visible, "race HUD shown")
	t.ok(hud.get_parent().get_node_or_null("RaceStatus") == null, "no stand-in label")
	t.ok(hud.text_of("clock").begins_with("Warning in") or hud.text_of("clock").begins_with("Start in"),
		"countdown: " + hud.text_of("clock"))
	t.ok(hud.ranking_panel.visible and rows.size() == 4, "ranking list held open through ui_input")
	var badges := rows.filter(func(r: String) -> bool: return r.contains("[Expert]"))
	t.ok(badges.size() == 3, "AI badges from the sim (%d)" % badges.size())
	t.ok(hud.race.contacts.size() == 3, "three boats on the radar")
	raw.held.erase(&"rankings")
	sc.queue_free()
	await process_frame

func _same(a: Variant, b: Array) -> bool:
	var x := Array(a)
	if x.size() != b.size():
		return false
	for i in b.size():
		if x[i] != b[i]:
			return false
	return true
