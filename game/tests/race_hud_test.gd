extends SceneTree
## Race HUD tests (hud.md §15 and the race parts of §3.2, §4, §6 to §14) run headless:
##   - scripted race states (RaceStubSim): countdown, flags and signal banners, the start line panel with the
##     time to burn test of §15, bias, OVER and OCS, the next mark, VMG / VMC signs, layline distance and
##     overstanding, the shift meter, the sail hint, rank hysteresis, gaps and splits, every rules awareness line,
##     radar colours for the port-starboard, windward-leeward and mark-room pair records, penalties, protest and
##     hail prompts, the feed, the results and the assist presets;
##   - the layline test of §15 on the core (a boat on the computed starboard layline fetches the mark);
##   - a real race on the core, practice_waters/example_wl, two boats steered by RacePilot from the spawn to the
##     results, the HUD checked against the core's race and rules records every tick;
##   - the sail test scene in race mode: the HUD shows the race and hides the stand-in label;
##   - the presentation of hud.md §16: what each instrument density shows in each phase, the density key and its
##     setting, name tags within 50 m and on selected boats, the penalty turn only in the chase and aerial cameras,
##     and every text fitting at 1280 x 800 for UI scales 80 % to 130 %; the portrait layout of §16.5 at
##     1080 x 1920 (texts on screen and apart, no block over another, Glance by default, the compact radar);
##   - picking a boat (§16.4.1: a click on her selects, on water or on her again clears, another replaces, the
##     bracket and the radar corners, boat_select nearest first), her card (§16.7) against the scripted state, the
##     card fitting at 1280 x 800 and 1080 x 1920, and the tack point drawn without a line from the boat.
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
	test_density()
	test_density_key_and_settings()
	await test_name_tags_and_penalty_turn()
	await test_boat_pick()
	await test_boat_card()
	await test_tack_point_no_line()
	test_text_fits()
	test_card_fits()
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
	t.ok(h.text_of("banner") == "" and not h.shown("banner"), "banner gone after 3 s")
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
	t.ok(not h.race.over and not h.shown("over"), "no OVER before the last minute")
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
	t.ok(not h.race.start_panel and not h.shown("line") and not h.race.over, "panel gone once started")
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
	t.ok(HudPaint.turn_in_label("beat") == "TACK IN" and HudPaint.turn_in_label("run") == "GYBE IN",
		"the layline turn is a tack on a beat and a gybe on a run (hud.md §16.4)")
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
		t.ok(h.text_of("rules") == cs[1] and h.colour_of("rules") == HudStyle.TINTS[cs[2]],
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
	t.ok(h.radar.drawn.get(1) == HudStyle.TINTS[T.RED] and h.radar.drawn.get(3) == HudStyle.TINTS[T.GREEN],
		"drawn red and green: %s" % str(h.radar.drawn))
	t.ok(h.radar.drawn.get(2) == HudStyle.TINTS[T.GREY], "ghost grey translucent")
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
	t.ok(h.radar.contact_colour(ct1) == HudStyle.TINTS[T.WHITE], "Minimal: all white")
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
	# the zone is the core's (rules.md §9.3): near the mark the HUD does not guess, the core's flag says not counted
	sim.put(0, 0, 985, 0.7, 3.0)
	sim.race_d["race_type"] = RaceText.RACE_MATCH
	_refresh(h, sim)
	t.ok(h.text_of("pen_turn") == "Turn: 210°", "no zone guess near the mark: " + h.text_of("pen_turn"))
	sim.rules_d[0]["turn_in_zone"] = true
	_refresh(h, sim)
	t.ok(h.text_of("pen_turn") == "Not counted: inside the zone", h.text_of("pen_turn"))
	sim.rules_d[0]["turn_in_zone"] = false
	sim.race_d["race_type"] = 0
	sim.put(0, 0, 500, 0.7, 3.0)
	# the progress dropping to 0 is not a reset by itself: only the core's turn_reset is
	sim.rules_d[0]["turning_for_penalty"] = false
	sim.rules_d[0]["turn_progress"] = 0.0
	_refresh(h, sim)
	t.ok(h.text_of("pen_turn") == "Sail clear and turn: one tack and one gybe", "no reset inferred: "
		+ h.text_of("pen_turn"))
	# each reset reason from the core, shown for 3 s
	var texts := {RaceText.TurnReset.PAUSED: "Turn reset: paused", RaceText.TurnReset.REVERSED: "Turn reset: turned back",
		RaceText.TurnReset.ZONE: "Turn reset: inside the zone", RaceText.TurnReset.ROUNDED: "Turn reset: mark rounded"}
	for why in texts:
		sim.rules_d[0]["turn_reset"] = why
		sim.rules_d[0]["turn_reset_tick"] = sim.tick()
		_refresh(h, sim)
		t.ok(h.text_of("pen_turn") == texts[why], "turn reset: " + h.text_of("pen_turn"))
	# over a new turn's progress while it shows, then gone after 3 s
	sim.rules_d[0]["turning_for_penalty"] = true
	sim.rules_d[0]["turn_progress"] = deg_to_rad(15.0)
	_refresh(h, sim, 0, RaceHudValues.RESET_TICKS - 2)
	t.ok(h.text_of("pen_turn") == "Turn reset: mark rounded", "reset text over the new turn: " + h.text_of("pen_turn"))
	_refresh(h, sim, 0, 3)
	t.ok(h.text_of("pen_turn") == "Turn: 15°", "reset text gone after 3 s: " + h.text_of("pen_turn"))
	sim.rules_d[0]["turning_for_penalty"] = false
	sim.rules_d[0]["turn_progress"] = 0.0
	sim.rules_d[0]["turn_reset"] = RaceText.TurnReset.NONE
	# deadline red below 30 s, dsq warning at dsq_pending - 1 pending
	sim.rules_d[0]["deadline_s"] = 25.0
	sim.rules_d[0]["pending"] = [{"rule": R.R10, "other": 1, "count": 1}, {"rule": R.R31, "other": -1, "count": 1}]
	_refresh(h, sim)
	t.ok(h.colour_of("pen_deadline") == HudStyle.TINTS[RaceHudValues.Tint.RED],
		"deadline red below 30 s")
	t.ok(h.text_of("pen_head") == "Penalty 1 of 2: Port tack keeps clear of starboard (Nora)", h.text_of("pen_head"))
	t.ok(h.text_of("pen_dsq") == "One more penalty = disqualification", "disqualification warning")
	# finish blocked, late, served
	sim.race_ev = [_rev(RaceText.Ev.FINISH_BLOCKED, {"boat": 0, "block": 0})]
	_refresh(h, sim)
	sim.race_ev = []
	t.ok(h.text_of("banner") == "Take your penalty before finishing", h.text_of("banner"))
	sim.rules_ev = [_uev(RaceText.Rev.PENALTY_LATE, {"boat": 0})]
	_refresh(h, sim)
	t.ok(h.text_of("banner") == "Take your penalty before finishing", "no banner of its own: " + h.text_of("banner"))
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
	_refresh(h, sim)  # the panel follows the events one tick later
	t.ok(not h.penalty_panel.visible and not h.text_of("banner").begins_with("PENALTY"),
		"another boat's penalty shows no panel or banner")
	sim.rules_ev = [_uev(RaceText.Rev.PENALTY_LATE, {"boat": 1})]
	_refresh(h, sim)
	sim.rules_ev = []
	t.ok(not h.penalty_panel.visible, "another boat's late penalty shows no panel")
	# disqualified: a full-width banner
	sim.rules_ev = [_uev(RaceText.Rev.DISQUALIFIED, {"boat": 0})]
	_refresh(h, sim)
	sim.rules_ev = []
	t.ok(h.race.banner.full and h.text_of("banner") == "DISQUALIFIED: too many penalties", h.text_of("banner"))
	sim.rules_ev = [_uev(RaceText.Rev.DISQUALIFIED, {"boat": 0, "rule": R.LATE})]
	_refresh(h, sim)
	sim.rules_ev = []
	t.ok(h.text_of("banner") == "DISQUALIFIED: penalty not taken within 2 minutes", h.text_of("banner"))
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
	t.ok(h.text_of("finish") == "Finished 2nd · 0:23:32.35 · +0:12" and h.finish_card_shown(),
		"finish card (§13.1): " + h.text_of("finish"))
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
	t.ok(not h.results_panel.visible, "no results table over the finish card")
	_refresh(h, sim, 0, RaceHudValues.CARD_TICKS)
	var rows := h.results_text_rows()
	t.ok(h.race.results_final and h.results_panel.visible and h.results_title == "Results", "final results shown")
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
	for k in h2.texts:
		dash = dash or h2.text_of(k).contains("—")
	for v in RaceText.RULE_TEXT.values() + RaceText.PREP_MEANING + RaceText.OVER_CONSEQUENCE:
		dash = dash or str(v).contains("—")
	for k in 7:
		dash = dash or RaceText.signal_banner(k, 1).contains("—")
	t.ok(not dash, "no em dash")
	t.ok(RaceText.rule_text(RaceText.Rule.R16_2) == "Don't bear away onto a ducking port boat"
		and RaceText.rule_text("30.1") == "Over early (I flag)" and RaceText.RULE_CODES.size() == 22, "rule texts of §12.3")
	h2.free()


# ---- §16 presentation -----------------------------------------------------------------------------------------

## a racing stub: boat 0 beating on starboard at (200, 400), boat 1 at (0, 0); `near_mark` puts boat 0 inside 6 L
func _beat_sim(near_mark := false) -> RaceStubSim:
	var sim := RaceStubSim.new(3)
	sim.race_d["state"] = RaceText.RaceState.RACING
	sim.race_d["race_time"] = 100.0
	for b in 3:
		sim.boats_d[b]["started"] = true
		sim.boats_d[b]["next"] = 1
	var psi := Frames.wrap_2pi(-deg_to_rad(42.0))
	sim.put(0, 10.0 if near_mark else 200.0, 975.0 if near_mark else 400.0, psi, 3.0)
	sim.put(1, 0, 0, 0.0, 3.0)
	sim.put(2, 60, 60, 0.0, 3.0)
	return sim


func _pre_sim() -> RaceStubSim:
	var sim := RaceStubSim.new(3)
	sim.race_d["state"] = RaceText.RaceState.SEQUENCE
	sim.race_d["race_time"] = -150.0
	for b in 3:
		sim.put(b, -40.0 + 40.0 * b, -100.0, 0.0, 3.0)
		sim.line_status(b)
	return sim


func _items_at(h: Hud, d: int) -> Array[String]:
	h.density_auto = false
	h.density = d as Hud.Density
	return h.items()


static func _has_all(a: Array[String], want: Array) -> bool:
	for w in want:
		if not a.has(w):
			return false
	return true


static func _has_none(a: Array[String], want: Array) -> bool:
	for w in want:
		if a.has(w):
			return false
	return true


static func _page_texts(b: HudCanvas) -> Array[String]:
	var out: Array[String] = []
	for q in b.primitives():
		if q["k"] == "text":
			out.append(q["text"])
	return out


func test_density() -> void:
	t.begin("instrument density per phase (hud.md §16.1)")
	var G := Hud.Density.GLANCE
	var RC := Hud.Density.RACE
	var D := Hud.Density.DATA
	var data_only := ["vmg_kn", "awa", "sog", "cog", "aws", "heel_bar"]
	# pre-start
	var sim := _pre_sim()
	var h := _hud(sim)
	_refresh(h, sim, 0, 5)
	t.ok(h.phase() == "pre", "phase pre: " + h.phase())
	var g := _items_at(h, G)
	t.ok(_has_all(g, ["bsp", "twa_dial", "start_min", "radar", "helm"]) and _has_none(g, ["cue", "hdg", "bug",
		"wind_page", "start_full", "feed"]), "pre-start Glance: %s" % str(g))
	var rc := _items_at(h, RC)
	t.ok(_has_all(rc, ["cue", "hdg", "target", "start_full", "wind_page", "bug", "feed"]) and _has_none(rc, data_only),
		"pre-start Race: %s" % str(rc))
	var d := _items_at(h, D)
	t.ok(_has_all(d, data_only + ["bug_lap"]), "pre-start Data: %s" % str(d))
	h.frame(0.3)
	t.ok(not h.cue_is_vmg(), "pre-start cue is polar %")
	h.free()
	# beat
	sim = _beat_sim()
	h = _hud(sim)
	h.assist = Hud.Assist.FULL
	_refresh(h, sim, 0, 200)
	t.ok(h.phase() == "beat", "phase beat: " + h.phase())
	g = _items_at(h, G)
	t.ok(_has_all(g, ["bsp", "twa_dial", "cue", "bug", "feed_own"]) and _has_none(g, ["hdg", "target", "wind_page",
		"shift", "bug_lap", "feed"] + data_only), "beat Glance: %s" % str(g))
	h.frame(0.3)
	var page := _page_texts(h.inst_page)
	t.ok(page.has("BOAT SPEED") and page.has("VMG TARGET") and not page.has("HEADING") and h.cue_is_vmg(),
		"Glance page: speed, TWA dial, VMG %%: %s" % str(page))
	t.ok(h.radar.compact and not h.wind_page.visible and h.bug_block.visible, "Glance: small radar, no wind page")
	rc = _items_at(h, RC)
	t.ok(_has_all(rc, ["cue", "hdg", "target", "wind_page", "shift", "bug_lap", "feed"]) and _has_none(rc,
		data_only + ["bug_gaps", "hint", "polar"]), "beat Race: %s" % str(rc))
	h.frame(0.3)
	page = _page_texts(h.inst_page)
	t.ok(page.has("HEADING") and page.has("TARGET") and not page.has("SOG") and h.wind_page.visible,
		"Race page: heading and target, wind page: %s" % str(page))
	d = _items_at(h, D)
	t.ok(_has_all(d, data_only + ["bug_gaps", "hint", "polar"]), "beat Data: %s" % str(d))
	h.frame(0.3)
	page = _page_texts(h.inst_page)
	t.ok(page.has("SOG") and page.has("COG") and page.has("AWS") and page.has("POLAR %") and page.has("HEEL")
		and page.has("VMG") and page.has("AWA"), "Data page: %s" % str(page))
	# the assist still decides: no sail hint below Full, no shift on Minimal
	h.assist = Hud.Assist.STANDARD
	t.ok(not _items_at(h, D).has("hint"), "sail hint needs the Full assist")
	h.assist = Hud.Assist.MINIMAL
	t.ok(not _items_at(h, D).has("shift"), "Minimal: no shift meter at any density")
	h.assist = Hud.Assist.STANDARD
	# contextual items are never hidden by the density
	var R := RaceText.Rule
	sim.pairs_a = [sim.pair(0, 1, {"kc_giver": 0, "kc_holder": 1, "kc_rule": R.R10, "kc_state": 2})]
	sim.rules_d[0] = {"pending": [{"rule": R.R10, "other": 1, "count": 1}], "turn_progress": 0.0, "turn_tacks": 0,
		"turn_gybes": 0, "deadline_s": 30.0, "received": 1, "turning_for_penalty": false}
	_refresh(h, sim)
	_items_at(h, G)
	h.frame(0.3)
	t.ok(h.phase() == "penalty" and h.penalty_panel.visible and h.shown("rules") and h.alerts_block.visible,
		"Glance keeps the penalty panel and the rules line")
	t.ok(not h.has_item("cue") and h.has_item("bsp"), "penalty at Glance: speed and TWA dial only")
	t.ok(_items_at(h, RC).has("cue"), "penalty at Race: as the leg")
	h.free()
	# rounding
	sim = _beat_sim(true)
	h = _hud(sim)
	_refresh(h, sim, 0, 20)
	t.ok(h.phase() == "rounding", "within 6 L of the mark: rounding (%s, %.0f m)" % [h.phase(), h.race.next_dist])
	t.ok(not _items_at(h, G).has("cue") and _items_at(h, RC).has("cue"), "rounding: Glance drops the cue")
	h.free()
	# reach: polar % is the cue, VMC in Data
	sim = _beat_sim()
	sim.put(0, 200.0, 400.0, Frames.wrap_2pi(-deg_to_rad(90.0)), 3.0)
	sim.put(0, -300.0, 900.0, deg_to_rad(90.0), 3.0)
	h = _hud(sim)
	_refresh(h, sim, 0, 200)
	if h.race.leg_type == "reach":
		d = _items_at(h, D)
		t.ok(not h.cue_is_vmg() and not d.has("polar") and d.has("vmg_kn"), "reach: polar %% is the cue: %s" % str(d))
		h.frame(0.3)
		t.ok(_page_texts(h.inst_page).has("VMC"), "reach Data: VMC")
	else:
		t.ok(false, "reach set-up: leg %s" % h.race.leg_type)
	h.free()


func test_density_key_and_settings() -> void:
	t.begin("density key, View tap and hold, defaults and the setting (hud.md §16.1, controls.md §3)")
	t.ok(Hud.default_density(Vector2(1920, 1080)) == Hud.Density.RACE, "default Race at 1920 x 1080")
	t.ok(Hud.default_density(Vector2(1280, 800)) == Hud.Density.GLANCE, "default Glance at 1280 x 800")
	t.ok(Hud.default_density(Vector2(2560, 1440)) == Hud.Density.RACE, "default Race at 2560 x 1440")
	var sim := _beat_sim()
	var h := Hud.new()
	h.screen_size = Vector2(1920, 1080)
	h.tick(sim, 0)
	h.frame(0.3)
	t.ok(h.density_auto and h.density == Hud.Density.RACE, "auto: Race on 16:9")
	h.screen_size = Vector2(1280, 800)
	h.frame(0.016)
	t.ok(h.density == Hud.Density.GLANCE, "auto: Glance on the Deck screen")
	var seen := []
	for i in 4:
		h.ui_input(RawInput.new().press(&"hud_density"), 0.016)
		h.frame(0.016)
		seen.append(h.density)
	t.ok(seen == [Hud.Density.RACE, Hud.Density.DATA, Hud.Density.GLANCE, Hud.Density.RACE] and not h.density_auto,
		"G cycles Glance, Race, Data, Glance: %s" % str(seen))
	t.ok(h.toast_block.visible and "RACE" in _page_texts(h.toast_block), "the INSTRUMENTS chip names the level")
	for i in 100:
		h.frame(0.016)
	t.ok(not h.toast_block.visible, "the chip goes after 1.5 s")
	# gamepad View: a tap cycles, a hold is the ranking list
	var before := h.density
	for i in 5:
		h.ui_input(RawInput.new().hold(&"rankings_pad"), 1.0 / 60.0)
	h.ui_input(RawInput.new(), 1.0 / 60.0)
	t.ok(h.density == (int(before) + 1) % 3 and not h.show_ranking, "View tap cycles the density")
	before = h.density
	var ranking := false
	for i in 40:
		h.ui_input(RawInput.new().hold(&"rankings_pad"), 1.0 / 60.0)
		ranking = ranking or h.show_ranking
	h.ui_input(RawInput.new(), 1.0 / 60.0)
	t.ok(h.density == before and ranking and not h.show_ranking, "View hold shows the ranking, no density change")
	# the choice is stored per device in the settings file
	var path := "user://hud_density_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var st := Settings.new()
	st.hud_density = -1
	st.save_file(path)
	var saved_path := Settings.path
	Settings.path = path
	st.apply_hud(h)
	t.ok(h.density_auto, "setting Auto: the device default")
	h.set_density(Hud.Density.DATA)
	var back := Settings.new()
	back.load_file(path)
	t.ok(back.hud_density == Hud.Density.DATA, "the density key saved Data: %d" % back.hud_density)
	var h2 := Hud.new()
	h2.screen_size = Vector2(1280, 800)
	back.apply_hud(h2)
	h2.tick(sim, 0)
	h2.frame(0.3)
	t.ok(not h2.density_auto and h2.density == Hud.Density.DATA, "a new HUD starts at the stored level")
	Settings.path = saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	h.free()
	h2.free()


func test_name_tags_and_penalty_turn() -> void:
	t.begin("name tags within 50 m or selected, the penalty turn by camera (hud.md §16.4, §12.1)")
	var sim := RaceStubSim.new(3)
	sim.race_d["state"] = RaceText.RaceState.RACING
	sim.race_d["race_time"] = 100.0
	for b in 3:
		sim.boats_d[b]["started"] = true
		sim.boats_d[b]["next"] = 1
	sim.put(0, 0.0, 400.0, 0.0, 3.0)
	sim.put(1, 0.0, 445.0, 0.0, 3.0)  # 45 m ahead
	sim.put(2, 20.0, 455.0 - 0.0, 0.0, 3.0)
	sim.put(2, 0.0, 400.0 + sqrt(55.0 * 55.0 - 20.0 * 20.0), 0.0, 3.0)
	sim.states[2].pos_x = 20.0  # 55 m away, ahead
	await process_frame
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.disable_3d = false
	get_root().add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.fov = 60.0
	var eye := Frames.enu_to_scene(0.0, 370.0, 12.0)
	cam.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(Frames.enu_to_scene(0.0, 440.0, 2.0), Vector3.UP)
	var h := Hud.new()
	h.screen_size = Vector2(1280, 720)
	h.camera = cam
	h.camera_kind = "chase"
	h.race.names = {1: "Nora", 2: "Ivo"}
	h.tick(sim, 0)
	h.frame(0.3)
	var d2 := Vector2(sim.states[2].pos_x, sim.states[2].pos_y - 400.0).length()
	t.near(d2, 55.0, 0.01, "boat 2 at 55 m")
	var names := h.name_tags().map(func(g: Dictionary) -> String: return g["name"])
	t.ok(names == ["NORA"], "tag on the boat at 45 m only: %s" % str(names))
	h.select_next()
	t.ok(h.selected.keys() == [1], "select key: nearest first")
	h.select_next()
	names = h.name_tags().map(func(g: Dictionary) -> String: return g["name"])
	t.ok(h.selected.keys() == [2] and names.has("IVO"), "select key: the next one gets a tag at 55 m: %s" % str(names))
	h.select_next()
	t.ok(h.selected.is_empty(), "select key: then none")
	var mast: Variant = h.project(Vector3(20.0, sim.states[2].pos_y, 0.6 * h.mast_height(2)))
	t.ok(mast != null and h.pick_at(mast) == 2 and h.selected.has(2), "click on a boat selects it")
	t.ok(h.pick_at(mast) == 2 and not h.selected.has(2), "a second click clears it")
	t.ok(h.pick_at(Vector2(2.0, 2.0)) == -1, "a click on empty water picks nothing")
	h.show_names = false
	t.ok(h.name_tags().is_empty(), "boat_names off: no tags")
	h.show_names = true
	# penalty turn: chase and aerial only
	var R := RaceText.Rule
	sim.rules_d[0] = {"pending": [{"rule": R.R10, "other": 1, "count": 1}], "turn_progress": deg_to_rad(120.0),
		"turn_tacks": 1, "turn_gybes": 0, "deadline_s": 30.0, "received": 1, "turning_for_penalty": true}
	_refresh(h, sim)
	var ring := func() -> bool:
		for q in h.world.primitives():
			if q["k"] == "polyline" and (q["col"] as Color).is_equal_approx(HudStyle.PORT):
				return true
		return false
	for kind in ["chase", "aerial", "onboard", "free"]:
		h.camera_kind = kind
		var want: bool = kind in ["chase", "aerial"]
		t.ok(h.penalty_turn_shown() == want and ring.call() == want, "penalty turn in the %s camera: %s" % [kind,
			"drawn" if want else "not drawn"])
	h.free()
	vp.free()


## a camera in a 1280 x 720 viewport at `eye` looking at `at` (ENU), for the world tags
func _cam(eye: Vector3, at: Vector3, fov := 60.0) -> Camera3D:
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.disable_3d = false
	get_root().add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.fov = fov
	var e := Frames.enu_to_scene(eye.x, eye.y, eye.z)
	cam.global_transform = Transform3D(Basis.IDENTITY, e).looking_at(Frames.enu_to_scene(at.x, at.y, at.z), Vector3.UP)
	return cam


## boat 0 at (0, 400) heading north; 1 at 45 m, 2 at 55 m, 3 far ahead at 320 m (a few px on screen)
func _pick_sim() -> RaceStubSim:
	var sim := RaceStubSim.new(4)
	sim.race_d["state"] = RaceText.RaceState.RACING
	sim.race_d["race_time"] = 100.0
	for b in 4:
		sim.boats_d[b]["started"] = true
		sim.boats_d[b]["next"] = 1
	sim.put(0, 0.0, 400.0, 0.0, 3.0)
	sim.put(1, -12.0, 400.0 + sqrt(45.0 * 45.0 - 144.0), 0.0, 3.0)
	sim.put(2, 20.0, 400.0 + sqrt(55.0 * 55.0 - 400.0), 0.0, 3.0)
	sim.put(3, 30.0, 400.0 + sqrt(320.0 * 320.0 - 900.0), deg_to_rad(40.0), 3.4)
	return sim


func test_boat_pick() -> void:
	t.begin("picking a boat: click, water, again, another, bracket, radar, boat_select (hud.md §16.4.1)")
	var sim := _pick_sim()
	await process_frame
	var cam := _cam(Vector3(0.0, 370.0, 12.0), Vector3(0.0, 440.0, 2.0))
	var h := Hud.new()
	get_root().add_child(h)
	h.screen_size = Vector2(1280, 720)
	h.camera = cam
	h.race.names = {1: "Nora", 2: "Ivo", 3: "Maja"}
	h.tick(sim, 0)
	h.frame(0.3)
	var tri := h.boat_triangle(3)
	var far := tri[2].distance_to((tri[0] + tri[1]) * 0.5)
	t.ok(not tri.is_empty() and far < 40.0, "the far boat is small on screen (%.0f px hull to masthead)" % far)
	var near_far := (tri[0] + tri[1] + tri[2]) / 3.0 + Vector2(22.0, 0.0)
	var raw := RawInput.new().click(near_far)
	h.ui_input(raw)
	h.frame(0.1)
	t.ok(h.selected_boat() == 3, "a click 22 px beside the far boat selects her (generous hit area)")
	var names := h.name_tags().map(func(g: Dictionary) -> String: return g["name"])
	t.ok(names.has("MAJA"), "her name tag shows at 320 m: %s" % str(names))
	var br := h.selected_bracket()
	var box := Rect2(tri[0], Vector2.ZERO).expand(tri[1]).expand(tri[2])
	t.ok(br.has("r") and (br["r"] as Rect2).encloses(box), "the bracket stands round her hull and rig")
	var corners := 0
	for q in h.world.primitives():
		if q["k"] == "polyline" and (q["pts"] as PackedVector2Array).size() == 3 and (br["r"] as Rect2).grow(1.0).has_point(q["pts"][1]):
			corners += 1
	t.ok(corners == 4, "four hairline corners drawn (%d)" % corners)
	var ri := h.radar.range_index
	h.radar.range_index = 4  # 506 m (not saved)
	h.frame(0.1)
	h.radar.primitives()
	t.ok(h.radar.selected == 3 and h.radar.selected_at.is_finite(), "the radar marks her (%d, %s)" % [h.radar.selected,
		h.radar.selected_at])
	h.radar.range_index = ri
	# water clears, again clears, another replaces
	h.ui_input(RawInput.new().click(Vector2(640.0, 700.0)))
	t.ok(h.selected_boat() == -1, "a click on open water clears the selection")
	var mast: Variant = h.project(Vector3(sim.states[2].pos_x, sim.states[2].pos_y, 0.6 * h.mast_height(2)))
	h.ui_input(RawInput.new().click(mast))
	t.ok(h.selected_boat() == 2, "a click on her mast selects boat 2")
	var hull: Variant = h.project(Vector3(sim.states[1].pos_x, sim.states[1].pos_y, 0.5))
	h.ui_input(RawInput.new().click(hull))
	t.ok(h.selected_boat() == 1 and h.selected.size() == 1, "a click on another boat's hull replaces her (one at a time)")
	h.ui_input(RawInput.new().click(hull))
	t.ok(h.selected_boat() == -1, "a click on the selected boat again clears")
	h.pick_enabled = false
	h.ui_input(RawInput.new().click(hull))
	t.ok(h.selected_boat() == -1, "no pick while the pause menu has the pointer")
	h.pick_enabled = true
	# boat_select: nearest first, then the next, then none
	var got := []
	for i in 4:
		h.ui_input(RawInput.new().press(&"boat_select"))
		got.append(h.selected_boat())
	t.ok(got == [1, 2, 3, -1], "boat_select: nearest first, then the next, then none: %s" % str(got))
	t.ok(h.clear_selection() == false, "clear with nothing selected reports none")
	h.select(2)
	t.ok(h.clear_selection() and h.selected_boat() == -1, "clear_selection (Esc) clears")
	# the viewed boat cannot be selected; the selection goes when she becomes the viewed one
	h.select(1)
	h.tick(sim, 1)
	h.frame(0.1)
	t.ok(h.selected_boat() == -1, "spectating the selected boat clears the selection")
	h.queue_free()
	cam.get_parent().queue_free()
	await process_frame


func test_boat_card() -> void:
	t.begin("the selected boat's card against the scripted state (hud.md §16.7)")
	var sim := _pick_sim()
	var R := RaceText.Rule
	sim.order = PackedInt32Array([3, 0, 1, 2])
	for i in 4:
		sim.boats_d[sim.order[i]]["D"] = 1200.0 + 25.0 * i
	sim.pairs_a = [sim.pair(0, 3, {"kc_giver": 0, "kc_holder": 3, "kc_rule": R.R10, "kc_state": 1}),
		sim.pair(0, 1, {"room_giver": 1, "room_entitled": 0, "room_rule": R.R18_2, "room_state": 2})]
	sim.rules_d[3] = {"pending": [{"rule": R.R12, "other": 2, "count": 1}], "turn_progress": deg_to_rad(90.0),
		"turn_tacks": 1, "turn_gybes": 0, "deadline_s": 30.0, "received": 1, "turning_for_penalty": true}
	var h := Hud.new()
	h.screen_size = Vector2(1280, 720)
	h.assist = Hud.Assist.FULL
	h.race.names = {1: "Nora", 2: "Ivo", 3: "Maja"}
	h.race.sail_numbers = {3: "slo 7"}
	h.race.ai_levels = {1: "Pro", 3: "Expert"}
	for i in 3:
		sim.step()
		h.tick(sim, 0)
	h.select(3)
	h.frame(0.3)
	h.refresh_text()
	var c := h.card
	var me := sim.states[0]
	var her := sim.states[3]
	var d := Vector2(her.pos_x - me.pos_x, her.pos_y - me.pos_y)
	t.ok(c["head"] == "SLO 7 · AI EXPERT" and c["name"] == "MAJA", "header: %s / %s" % [c["head"], c["name"]])
	t.ok(c["place"] == "1" and c["fleet"] == 4, "place 1 / 4 from the shown order")
	t.near(c["d_m"], d.length(), 1e-6, "distance from the boat states")
	t.ok(c["dist"] == HudStyle.split_unit(HudFormat.distance(d.length())), "distance text %s" % str(c["dist"]))
	var brg := Frames.compass(d.x, d.y)
	t.near(c["brg_rad"], brg, 1e-9, "bearing to her")
	t.ok(c["brg"][0] == HudFormat.compass_deg(brg) and c["brg"][1] == "· " + HudFormat.relative_bearing(Frames.wrap_pi(brg - me.psi)).to_upper(),
		"bearing text %s" % str(c["brg"]))
	t.ok(c["speed"][0] == HudFormat.speed_kn(her.v) and c["hdg"][0] == HudFormat.compass_deg(her.psi),
		"speed %s kn, heading %s" % [c["speed"][0], c["hdg"][0]])
	t.ok(c["hdg"][1] == ("S" if her.twa > 0.0 else "P"), "her tack letter %s (TWA %.0f)" % [c["hdg"][1], rad_to_deg(her.twa)])
	t.ok(c["course"] == "Next Windward · 25 m ahead of you", "course line: %s" % c["course"])
	t.ok(c["rules"] == "YOU KEEP CLEAR" and c["rule_text"] == "Port tack keeps clear of starboard (10)"
		and (c["rules_col"] as Color).is_equal_approx(HudStyle.PORT), "rules: %s, %s" % [c["rules"], c["rule_text"]])
	t.ok(c["penalty"] == "1 PENALTY OWED · TURNING", "penalty: %s" % c["penalty"])
	t.ok((c["col"] as Color).is_equal_approx(HudStyle.PORT), "her tag colour is the radar's (red: I keep clear)")
	h.layout_now()
	t.ok(h.card_block.visible and h.card_block.position.y + h.card_block.size.y <= h.inst_page.position.y,
		"the card sits left, over the instrument page")
	var texts := _page_texts(h.card_block)
	t.ok(texts.has("MAJA") and texts.has("YOU KEEP CLEAR") and texts.has("1 PENALTY OWED · TURNING"),
		"the card draws its rows")
	# boat 1: she gives me room, breached; a player with no sail number
	h.select(1)
	h.refresh_text()
	c = h.card
	t.ok(c["head"] == "AI PRO" and c["rules"] == "SHE GIVES YOU ROOM · BREACH" and c["rule_text"] == "Give mark-room (18.2)"
		and not c.has("penalty"), "boat 1: %s, %s, %s" % [c["head"], c["rules"], c["rule_text"]])
	t.ok(c["course"] == "Next Windward · 25 m behind you", "boat 1 course: %s" % c["course"])
	h.select(2)
	h.refresh_text()
	t.ok(h.card["head"] == "PLAYER" and not h.card.has("rules"), "boat 2: a player, no relation")
	# Minimal assist: no rules row (as the radar colours)
	h.assist = Hud.Assist.MINIMAL
	h.select(3)
	h.frame(0.1)
	h.refresh_text()
	t.ok(not h.card.has("rules") and h.card.has("penalty"), "Minimal assist: no relation row, the penalty stays")
	h.free()


func test_tack_point_no_line() -> void:
	t.begin("the tack point: ring and TACK IN label, no line from the boat (hud.md §16.4)")
	var sim := RaceStubSim.new()
	sim.race_d["state"] = RaceText.RaceState.RACING
	sim.race_d["race_time"] = 100.0
	for b in 2:
		sim.boats_d[b]["started"] = true
		sim.boats_d[b]["next"] = 1
	var th := deg_to_rad(42.0)
	sim.put(0, 300.0, 200.0, Frames.wrap_2pi(-th), 3.0)
	sim.put(1, 0, 0, 0.0, 3.0)
	await process_frame
	var h := Hud.new()
	get_root().add_child(h)
	h.screen_size = Vector2(1280, 720)
	h.assist = Hud.Assist.FULL
	for i in 5:
		sim.step()
		h.tick(sim, 0)
	var tp0: Variant = null
	h.frame(0.3)
	h.refresh_text()
	var dir := Vector2(sin(-th), cos(-th))
	var o := Vector2(300, 200)
	var tgt := o + dir * h.race.layline_dist
	var eye := o - dir * 60.0
	var cam := _cam(Vector3(eye.x, eye.y, 70.0), Vector3(tgt.x * 0.5 + o.x * 0.5, tgt.y * 0.5 + o.y * 0.5, 0.0), 70.0)
	h.camera = cam
	h.frame(0.1)
	tp0 = h.world_tack_point()
	t.ok(tp0 != null, "a tack point (%.0f m along the COG)" % h.race.layline_dist)
	var bs: Variant = h.project(h.own_world(0.0))
	var ts: Variant = h.project(Vector3(tp0.x, tp0.y, 0.0)) if tp0 != null else null
	t.ok(bs != null and ts != null and h._on_screen(ts), "boat and tack point on screen")
	var ring := false
	var label := false
	var line_from_boat := 0
	for q in h.world.primitives():
		if q["k"] == "arc" and ts != null and (q["p"] as Vector2).distance_to(ts) < 1.0:
			ring = true
		if q["k"] == "text" and q["text"] == "TACK IN":
			label = true
		if q["k"] == "line" and bs != null and ts != null:
			var a: Vector2 = q["a"]
			var b: Vector2 = q["b"]
			# any segment on the boat-to-tack-point path
			var on_path := Geometry2D.get_closest_point_to_segment(a, bs, ts).distance_to(a) < 2.0 \
				and Geometry2D.get_closest_point_to_segment(b, bs, ts).distance_to(b) < 2.0
			if on_path:
				line_from_boat += 1
	t.ok(ring and label, "the ring and TACK IN label are drawn")
	t.ok(line_from_boat == 0, "no line from the boat to the tack point (%d segments)" % line_from_boat)
	h.queue_free()
	cam.get_parent().queue_free()
	await process_frame


func test_card_fits() -> void:
	t.begin("the boat card fits: 1280 x 800 and 1080 x 1920, UI scale 80 % to 130 %, every density")
	var R := RaceText.Rule
	var bad := []
	var checked := 0
	for scr in [Vector2(1280, 800), Vector2(1080, 1920), Vector2(1280, 720)]:
		for sname in ["beat", "penalty"]:
			for scale in [0.8, 1.0, 1.3]:
				for lvl in 3:
					var sim := _beat_sim()
					sim.order = PackedInt32Array([1, 0, 2])
					sim.pairs_a = [sim.pair(0, 1, {"kc_giver": 0, "kc_holder": 1, "kc_rule": R.R16_1, "kc_state": 2})]
					sim.rules_d[1] = {"pending": [{"rule": R.R10, "other": 0, "count": 2}, {"rule": R.R31, "other": -1}],
						"turn_progress": 0.0, "turn_tacks": 0, "turn_gybes": 0, "deadline_s": 30.0, "received": 2,
						"turning_for_penalty": true}
					if sname == "penalty":
						sim.rules_d[0] = {"pending": [{"rule": R.R10, "other": 1, "count": 2}], "turn_progress": deg_to_rad(200.0),
							"turn_tacks": 1, "turn_gybes": 0, "deadline_s": 8.0, "received": 5, "turning_for_penalty": true}
					var h := Hud.new()
					h.screen_size = scr / scale
					h.assist = Hud.Assist.FULL
					h.race.names = {1: "Windflower", 2: "Ivo"}
					h.race.sail_numbers = {1: "SLO 1234"}
					h.race.ai_levels = {1: "Intermediate"}
					h.set_density(lvl)
					for i in 30:
						sim.step()
						h.tick(sim, 0)
					h.select(1)
					h.frame(0.3)
					h.refresh_text()
					h.frame(2.0)
					var what := "%s %s %.0f%% %s" % [scr, sname, scale * 100, Hud.DENSITY_NAMES[lvl]]
					if not h.card_block.visible:
						bad.append("%s: no card" % what)
					var rects := _text_rects(h)
					var screen := Rect2(Vector2.ZERO, h.screen_size)
					for a in rects:
						if a["b"] != "BoatCard":
							continue
						checked += 1
						if not screen.encloses(a["r"]):
							bad.append("%s: '%s' off screen" % [what, a["t"]])
						for c in rects:
							if c == a or (c["b"] == "BoatCard" and c["t"] == a["t"]):
								continue
							if (a["r"] as Rect2).grow(-1.0).intersects((c["r"] as Rect2).grow(-1.0)):
								bad.append("%s: '%s' overlaps '%s' (%s)" % [what, a["t"], c["t"], c["b"]])
					for p in HudLayoutCheck.problems(h, h.screen_size):
						if p.contains("BoatCard"):
							bad.append("%s: %s" % [what, p])
					h.free()
	t.ok(bad.is_empty() and checked > 0, "%d card texts checked, %d problems: %s" % [checked, bad.size(), str(bad.slice(0, 8))])


## screen rects of every text the HUD paints now (blocks laid out inside the Hud, which is not in the tree)
static func _text_rects(h: Hud) -> Array:
	var out := []
	for b in h.blocks():
		if b == h.world:
			continue
		var o := b.position
		var n: Node = b.get_parent()
		while n != null and n != h:
			if n is Control:
				o += (n as Control).position
			n = n.get_parent()
		for q in b.primitives():
			if q["k"] != "text" or q["text"] == "":
				continue
			var sz: int = q["size"]
			var f := HudStyle.font(q["weight"], q["tracking"], sz)
			var w := f.get_string_size(q["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
			var p: Vector2 = q["p"]
			var x := p.x - (w if q["align"] == HORIZONTAL_ALIGNMENT_RIGHT else (w * 0.5 if q["align"] == 1 else 0.0))
			# the digits and caps: cap height above the baseline, a little below it
			out.append({"r": Rect2(o + Vector2(x, p.y - f.get_ascent(sz) * 0.72), Vector2(w, f.get_ascent(sz) * 0.8)),
				"b": b.name, "t": q["text"]})
	return out


func test_text_fits() -> void:
	t.begin("every text fits at 1280 x 800 and in portrait at 1080 x 1920, UI scale 80 % to 130 %")
	var R := RaceText.Rule
	var scenarios := {}
	var pre := _pre_sim()
	pre.race_d["race_time"] = -150.0
	pre.race_d["prep_flag"] = 1
	scenarios["pre-start"] = pre
	var inc := _beat_sim()
	inc.pairs_a = [inc.pair(0, 1, {"kc_giver": 0, "kc_holder": 1, "kc_rule": R.R10, "kc_state": 2})]
	inc.rules_d[0] = {"pending": [{"rule": R.R10, "other": 1, "count": 2}], "turn_progress": deg_to_rad(200.0),
		"turn_tacks": 1, "turn_gybes": 0, "deadline_s": 8.0, "received": 5, "turning_for_penalty": true}
	scenarios["penalty"] = inc
	scenarios["beat"] = _beat_sim()
	var bad := []
	var blocks_bad := []
	var checked := 0
	for scr in [Vector2(1280, 800), Vector2(1080, 1920)]:
		var tag := "" if scr.x > scr.y else "portrait "
		for sname in scenarios:
			for scale in [0.8, 1.0, 1.3]:
				for lvl in 3:
					var sim: RaceStubSim = scenarios[sname]
					var h := Hud.new()
					h.screen_size = scr / scale
					h.assist = Hud.Assist.FULL
					h.race.names = {1: "Nora", 2: "Ivo"}
					h.set_density(lvl)
					for i in 30:
						sim.step()
						h.tick(sim, 0)
					h.frame(0.3)
					h.refresh_text()
					h.frame(2.0)
					var rects := _text_rects(h)
					var screen := Rect2(Vector2.ZERO, h.screen_size)
					var what := "%s%s %.0f%% %s" % [tag, sname, scale * 100, Hud.DENSITY_NAMES[lvl]]
					for i in rects.size():
						var a: Dictionary = rects[i]
						checked += 1
						if not screen.encloses(a["r"]):
							bad.append("%s: '%s' off screen" % [what, a["t"]])
						for j in range(i + 1, rects.size()):
							var c: Dictionary = rects[j]
							if (a["r"] as Rect2).grow(-1.0).intersects((c["r"] as Rect2).grow(-1.0)):
								bad.append("%s: '%s' (%s) overlaps '%s' (%s)" % [what, a["t"], a["b"], c["t"], c["b"]])
					if tag != "":
						for p in HudLayoutCheck.problems(h, h.screen_size):
							blocks_bad.append("%s: %s" % [what, p])
						if not h.radar.compact:
							blocks_bad.append("%s: radar not compact" % what)
					h.free()
	t.ok(bad.is_empty(), "%d texts checked, %d problems: %s" % [checked, bad.size(), str(bad.slice(0, 8))])
	t.ok(blocks_bad.is_empty(), "portrait: no block over another, all on screen, compact radar (%d problems: %s)" % [
		blocks_bad.size(), str(blocks_bad.slice(0, 6))])
	# portrait defaults and scale (hud.md §16.5)
	t.ok(Hud.default_density(Vector2(1080, 1920)) == Hud.Density.GLANCE, "portrait: default Glance at 1080 x 1920")
	t.near(HudStyle.ui_k(Vector2(1080, 1920)), 1.0, 1e-9, "portrait: k = 1 at 1080 x 1920")
	t.near(HudStyle.ui_k(Vector2(720, 1280)), 720.0 / 1080.0, 1e-9, "portrait: k = width / 1080")
	t.ok(not HudStyle.portrait(Vector2(1920, 1080)) and HudStyle.portrait(Vector2(1080, 1920)), "portrait test")
	var ph := Hud.new()
	ph.screen_size = Vector2(1080, 1920)
	var pen := _beat_sim()
	pen.rules_d[0] = inc.rules_d[0]
	pen.pairs_a = inc.pairs_a
	for i in 30:
		pen.step()
		ph.tick(pen, 0)
	ph.frame(0.3)
	ph.refresh_text()
	ph.frame(0.0)
	var lane_y := ph.race_panel.position.y
	t.ok(ph.density == Hud.Density.GLANCE and ph.penalty_panel.visible and ph.alerts_block.visible
		and lane_y < 1920.0 * 0.25 and ph.inst_page.position.y > 1920.0 * 0.75,
		"portrait: penalty panel and rule text at the top (lane at y %.0f), instruments at the bottom (y %.0f)" % [
		lane_y, ph.inst_page.position.y])
	t.ok(ph.penalty_panel.k > 1.0 and ph.alerts_block.k > 1.0 and ph.inst_page.k == 1.0,
		"portrait: the alert lane drawn larger (%.2f) than the rest (%.2f)" % [ph.alerts_block.k, ph.inst_page.k])
	ph.free()


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
	if not sim.create("practice_waters"):
		t.ok(false, "world: " + sim.last_error())
		return null
	sim.add_entry("wm7", {"human": true})
	sim.add_entry("wm7", {"human": true})
	if not sim.create_race("practice_waters/example_wl"):
		t.ok(false, "race: " + sim.last_error())
		return null
	return sim


func test_core_race() -> void:
	t.begin("a race on the core: practice_waters/example_wl, two boats from the spawn to the results")
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
	t.ok(h.race.card.get("kind", "") == "finish" and h.race.race_over and h.race.end_reason == "finished",
		"finish card and race over: %s" % str(h.race.card))
	for i in RaceHudValues.CARD_TICKS:
		sim.step()
		h.tick(sim, 0)
	h.frame(0.25)
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
