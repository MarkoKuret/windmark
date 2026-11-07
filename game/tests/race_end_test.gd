extends SceneTree
## Race end tests (hud.md §13.1 to §13.3, menus.md §5, menus.md §2 Retire, cameras.md §9.1, race.md §6.2) run
## headless:
##   - scripted race states (RaceStubSim): the finish card's texts and timing, RET, DNF and DSQ, when the race is
##     over and the results are due, the live finishing rows filling in, the final rows with their codes and the
##     projected finish, the race summary (start, roundings with places, places gained, penalty with its rule text,
##     top speed, distance sailed);
##   - the results screen over a stand-in host: opening when due, title, heading, table rows and the player's row,
##     keyboard navigation and scrolling, Race again (the setup with a new seed), Change setup (the main menu opens
##     on the race card with the setup), Main menu, the fit at 1280 x 800 and 1080 x 1920 for 80, 100 and 130 %;
##   - the finish view of the camera rig: the ease from the chase camera, the drift, camera_next back to chase;
##   - on the core: the finished-boat autopilot sails the player's boat clear after her finish; the sail scene in a
##     quick race from the spawn to the results screen (finish view, HUD hidden, pause menu over it, Race again),
##     and Retire from the pause menu.
##   godot --headless --path game -s res://tests/race_end_test.gd

const TEST_PATH := "user://race_end_test_settings.cfg"
const KNOT := HudFormat.KNOT

var t := TestLog.new()


func _init() -> void:
	Settings.path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	Settings.reset_current()
	Settings.current().welcomed = true
	test_card_and_over()
	test_summary()
	test_live_and_final()
	await test_screen()
	test_finish_view()
	if CoreSimSource.available():
		test_autopilot_core()
		await test_scene_flow()
		await test_scene_retire()
	else:
		t.ok(false, "the GDExtension is not loaded: core tests skipped")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	t.finish(self, "race_end_test")


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


## a stub race of n boats on the last leg, every boat started
func _racing(n: int) -> RaceStubSim:
	var sim := RaceStubSim.new(n)
	sim.race_d["state"] = RaceText.RaceState.RACING
	sim.race_d["race_time"] = 1300.0
	for b in n:
		sim.boats_d[b]["started"] = true
		sim.boats_d[b]["next"] = 4
		sim.put(b, 10.0 * b, 40.0, PI, 3.0)
	return sim


func _tick(r: RaceHudValues, sim: SimSource, n := 1) -> void:
	for i in n:
		sim.step()
		r.tick(sim, 0)
		if sim is RaceStubSim:
			(sim as RaceStubSim).race_ev = []
			(sim as RaceStubSim).rules_ev = []


func _finish(sim: RaceStubSim, b: int, place: int, t_us: int) -> void:
	sim.boats_d[b]["finished"] = true
	sim.boats_d[b]["place"] = place
	sim.boats_d[b]["t_finish_us"] = t_us
	sim.race_ev.append(_rev(RaceText.Ev.FINISHED, {"boat": b, "place": place, "t_us": t_us}))


# ---- hud.md §13.1, §13.2 -----------------------------------------------------------------------------------------

func test_card_and_over() -> void:
	t.begin("finish card and race over (hud.md §13.1, §13.2)")
	var sim := _racing(3)
	var r := RaceHudValues.new()
	r.names = {1: "Nora", 2: "Ivo"}
	r.tick(sim, 0)
	_finish(sim, 1, 1, 1400000000)
	_tick(r, sim)
	t.ok(r.card.is_empty() and not r.race_over, "another boat's finish: no card")
	_finish(sim, 0, 2, 1412350000)
	sim.order = PackedInt32Array([1, 0, 2])
	_tick(r, sim)
	t.ok(r.card.get("big", "") == "2ND" and r.card.get("gap", "") == "+0:12" and r.card.get("time", "") == "0:23:32.35"
		and r.card.get("caption", "") == "FINISHED", "card: 2ND +0:12 0:23:32.35 (%s)" % str(r.card))
	t.ok(r.card.get("line", "") == "Finished 2nd · 0:23:32.35 · +0:12" and not bool(r.card.get("win", true)),
		"card line, not a win")
	t.ok(r.banner == null or not r.banner.text.begins_with("Finished"), "no finish banner as well")
	t.ok(r.race_over and r.end_reason == "finished" and not r.results_due(), "race over at the finish, results not yet due")
	t.ok(r.card_alpha() > 0.0 and r.card_alpha() < 0.5, "fading in (%.2f)" % r.card_alpha())
	_tick(r, sim, 6)
	t.near(r.card_alpha(), 1.0, 1e-6, "fully shown after 0.3 s")
	_tick(r, sim, RaceHudValues.CARD_TICKS - 20)
	t.ok(r.card_alpha() < 1.0 and r.card_alpha() > 0.0, "fading out in the last 0.8 s (%.2f)" % r.card_alpha())
	_tick(r, sim, 13)
	t.ok(r.card.is_empty() and r.card_alpha() == 0.0, "gone after 5 s")
	t.ok(r.results_due() and r.over_ticks >= RaceHudValues.CARD_TICKS, "results due 5 s after the finish")
	# a win is yellow, a finish without a place shows its code
	var w := _racing(2)
	var rw := RaceHudValues.new()
	rw.tick(w, 0)
	_finish(w, 0, 1, 1300000000)
	_tick(rw, w)
	t.ok(rw.card.get("big", "") == "1ST" and bool(rw.card.get("win", false)) and rw.card.get("gap", "x") == "",
		"winner: 1ST, no gap, the win flag")
	var o := _racing(2)
	var ro := RaceHudValues.new()
	ro.tick(o, 0)
	o.boats_d[0]["code"] = 4
	_finish(o, 0, 0, 1300000000)
	_tick(ro, o)
	t.ok(ro.card.get("big", "") == "OCS", "a finish without a place shows its code (%s)" % ro.card.get("big", ""))
	# retirement, disqualification, the race closing with her still racing, abandonment
	var rt := _racing(2)
	var rr := RaceHudValues.new()
	rr.tick(rt, 0)
	rt.boats_d[0]["retired"] = true
	rt.boats_d[0]["ghost"] = true
	rt.race_ev = [_rev(RaceText.Ev.RETIRED, {"boat": 0})]
	_tick(rr, rt)
	t.ok(rr.card.get("big", "") == "RET" and rr.card.get("caption", "") == "RETIRED" and rr.race_over
		and rr.end_reason == "retired", "retired: RET card, race over")
	var ds := _racing(2)
	var rd := RaceHudValues.new()
	rd.tick(ds, 0)
	ds.boats_d[0]["dsq"] = true
	ds.boats_d[0]["ghost"] = true
	ds.rules_ev = [_uev(RaceText.Rev.DISQUALIFIED, {"boat": 0, "rule": RaceText.Rule.LATE})]
	_tick(rd, ds)
	t.ok(rd.card.is_empty() and rd.banner != null and rd.banner.text.begins_with("DISQUALIFIED") and rd.race_over
		and rd.end_reason == "dsq", "disqualified: the banner, no card, race over")
	var dn := _racing(2)
	var rn := RaceHudValues.new()
	rn.tick(dn, 0)
	dn.race_d["state"] = RaceText.RaceState.CLOSED
	dn.boats_d[0]["code"] = 7
	dn.race_ev = [_rev(RaceText.Ev.RACE_CLOSED, {})]
	_tick(rn, dn)
	t.ok(rn.card.get("big", "") == "DNF" and rn.end_reason == "dnf" and rn.results_visible, "closed while racing: DNF")
	var ab := _racing(2)
	var ra := RaceHudValues.new()
	ra.tick(ab, 0)
	ab.race_d["state"] = RaceText.RaceState.ABANDONED
	ab.race_ev = [_rev(RaceText.Ev.ABANDONED, {})]
	_tick(ra, ab)
	t.ok(ra.race_over and ra.end_reason == "abandoned" and ra.card.is_empty(), "abandoned: race over, the banner only")
	# the HUD draws the card in the lane and keeps its own results table off while it shows
	var h := Hud.new()
	get_root().add_child(h)
	h.screen_size = Vector2(1280, 800)
	var hs := _racing(3)
	h.tick(hs, 0)
	_finish(hs, 0, 1, 1300000000)
	hs.step()
	h.tick(hs, 0)
	h.frame(0.05)
	h.refresh_text()
	h.frame(0.0)
	var texts := []
	for q in h.start_block.primitives():
		if q["k"] == "text":
			texts.append(q["text"])
	t.ok(h.finish_card_shown() and h.start_block.visible and texts.has("1ST") and texts.has("FINISHED"),
		"the card in the lane: %s" % str(texts))
	t.ok(not h.results_panel.visible, "no HUD results table over the card")
	h.free()


# ---- hud.md §13.3 ------------------------------------------------------------------------------------------------

func test_summary() -> void:
	t.begin("race summary (hud.md §13.3)")
	var sim := RaceStubSim.new(3)
	sim.race_d["state"] = RaceText.RaceState.RACING
	sim.race_d["race_time"] = 2.0
	sim.put(0, 0.0, -20.0, 0.0, 3.0)
	sim.put(1, 20.0, -20.0, 0.0, 3.0)
	sim.put(2, 40.0, -20.0, 0.0, 3.0)
	var r := RaceHudValues.new()
	r.names = {1: "Nora", 2: "Ivo"}
	r.tick(sim, 0)
	for b in 3:
		sim.boats_d[b]["started"] = true
		sim.boats_d[b]["next"] = 1
	sim.race_ev = [_rev(RaceText.Ev.STARTED, {"boat": 0, "t": 4.2})]
	_tick(r, sim)
	# 100 ticks north at 3 m/s, one tick at 4 m/s
	var y := -20.0
	for i in 100:
		y += 3.0 * SimSource.DT
		sim.put(0, 0.0, y, 0.0, 4.0 if i == 50 else 3.0)
		_tick(r, sim)
	# the windward mark: two boats first, she is 3rd 18 s behind
	sim.splits = {"1:1": 600.0, "2:1": 610.0, "0:1": 618.0}
	sim.race_ev = [_rev(RaceText.Ev.ROUNDED, {"boat": 0, "step": 1})]
	_tick(r, sim)
	sim.rules_ev = [_uev(RaceText.Rev.PENALTY, {"boat": 0, "other": 1, "rule": RaceText.Rule.R10})]
	_tick(r, sim)
	sim.rules_ev = [_uev(RaceText.Rev.PENALTY_SERVED, {"boat": 0})]
	_tick(r, sim)
	sim.splits.merge({"1:2": 900.0, "0:2": 905.0, "2:2": 930.0})
	sim.race_ev = [_rev(RaceText.Ev.ROUNDED, {"boat": 0, "step": 2})]
	_tick(r, sim)
	sim.order = PackedInt32Array([1, 0, 2])
	_finish(sim, 1, 1, 1400000000)
	_tick(r, sim)
	_finish(sim, 0, 2, 1412350000)
	_tick(r, sim)
	var dist := r.distance_sailed
	for i in 50:
		y += 3.0 * SimSource.DT
		sim.put(0, 0.0, y, 0.0, 6.0)
		_tick(r, sim)
	var lines := r.summary_lines()
	var by := {}
	for ln in lines:
		by[ln[0]] = by.get(ln[0], []) + [ln[1]]
	print("  summary: %s" % str(lines))
	t.ok(by.get("Start", []) == ["+0:04 after the gun"], "start: %s" % str(by.get("Start")))
	t.ok(by.get("Windward 1", []) == ["3rd  ·  +0:18"], "windward: 3rd +0:18 (%s)" % str(by.get("Windward 1")))
	t.ok(by.get("Gate 1", []) == ["2nd  ·  +0:05"], "gate: 2nd +0:05 (%s)" % str(by.get("Gate 1")))
	t.ok(by.get("Places", []) == ["+1 since the first mark"], "places: %s" % str(by.get("Places")))
	t.ok(by.get("Penalty", []) == ["Rule 10: Port tack keeps clear of starboard (Nora), done"],
		"penalty with its rule text: %s" % str(by.get("Penalty")))
	t.ok(by.get("Top speed", []) == ["%s kn" % HudFormat.speed_kn(4.0)], "top speed while racing: %s" % str(by.get("Top speed")))
	t.near(dist, 100.0 * 3.0 * SimSource.DT, 0.05, "distance sailed to the finish")
	t.near(r.distance_sailed, dist, 1e-6, "nothing added after the finish")
	t.ok(by.get("Distance sailed", []) == [HudFormat.distance(dist)], "distance shown: %s" % str(by.get("Distance sailed")))
	# a clean race says so
	var c := _racing(2)
	var rc := RaceHudValues.new()
	rc.tick(c, 0)
	c.race_ev = [_rev(RaceText.Ev.STARTED, {"boat": 0, "t": 1.0})]
	_tick(rc, c)
	var cl := rc.summary_lines()
	t.ok(cl.has(["Penalties", "No penalties"]), "no penalties: %s" % str(cl))


# ---- menus.md §5 rows ---------------------------------------------------------------------------------------------

func test_live_and_final() -> void:
	t.begin("finishing rows fill in, then the final results (hud.md §13, menus.md §5)")
	var sim := _racing(5)
	var r := RaceHudValues.new()
	r.names = {1: "Nora", 2: "Ivo", 3: "Maja", 4: "Tine"}
	r.ai_levels = {1: "Expert", 2: "Expert", 3: "Pro", 4: "Easy"}
	r.tick(sim, 0)
	sim.order = PackedInt32Array([1, 0, 2, 3, 4])
	_finish(sim, 1, 1, 1400000000)
	_tick(r, sim)
	_finish(sim, 0, 2, 1410000000)
	sim.boats_d[4]["retired"] = true
	sim.boats_d[4]["ghost"] = true
	_tick(r, sim)
	var home := func() -> int: return r.result_rows.filter(func(x: Dictionary) -> bool: return not is_nan(x["time"])).size()
	t.ok(r.results_visible and not r.results_final and home.call() == 2, "live: two home")
	t.ok(r.result_rows[4]["status"] == "RET" and r.result_rows[2]["status"] == "Racing", "live status of the others")
	_finish(sim, 2, 3, 1430000000)
	sim.order = PackedInt32Array([1, 0, 2, 3, 4])
	_tick(r, sim)
	t.ok(home.call() == 3 and not r.results_final, "a third boat finishes: the rows fill in")
	sim.results_a = [
		{"boat": 1, "place": 1, "code": 0, "code_name": "", "points": 1.0, "t_finish_us": 1400000000, "projected": false},
		{"boat": 0, "place": 2, "code": 0, "code_name": "", "points": 2.0, "t_finish_us": 1410000000, "projected": false},
		{"boat": 2, "place": 3, "code": 0, "code_name": "", "points": 3.0, "t_finish_us": 1430000000, "projected": false},
		{"boat": 3, "place": 4, "code": 0, "code_name": "", "points": 4.0, "t_finish_us": 1500000000, "projected": true},
		{"boat": 4, "place": 0, "code": 8, "code_name": "RET", "points": 6.0, "t_finish_us": 0, "projected": false},
	]
	sim.race_d["state"] = RaceText.RaceState.CLOSED
	sim.race_ev = [_rev(RaceText.Ev.RACE_CLOSED, {})]
	_tick(r, sim)
	var order := r.result_rows.map(func(x: Dictionary) -> int: return x["boat"])
	t.ok(r.results_final and order == [1, 0, 2, 3, 4], "final order from the core: %s" % str(order))
	t.ok(r.result_rows[3]["projected"] and r.result_rows[4]["code"] == "RET" and r.result_rows[4]["place"] == 0,
		"projected AI finish and the RET code")
	t.near(float(r.result_rows[1]["gap"]), 10.0, 1e-6, "gap to the winner")
	t.ok(r.own_place() == 2, "own place 2")


# ---- the results screen -------------------------------------------------------------------------------------------

class Host extends Node:
	var hud: Hud
	var rig: CameraRig
	var runner: SimRunner
	var venue := "practice_waters"
	var course := "practice_waters/example_wl"
	var class_id := "wm7"

	func session_setup() -> GameSetup:
		var g := GameSetup.new()
		g.mode = "race"
		g.course = course
		g.venue = venue
		g.class_id = class_id
		g.livery = "kestrel"
		g.fleet_size = 5
		g.ai_level = "pro"
		g.wind_kn = 17.0
		g.wind_from_deg = 45.0
		g.seed = 4242
		return g


func _key(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	root.push_input(e)
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	root.push_input(r)


func _screen_host(sim: RaceStubSim) -> Host:
	var host := Host.new()
	host.hud = Hud.new()
	host.add_child(host.hud)
	host.rig = CameraRig.new()
	host.add_child(host.rig)
	host.runner = SimRunner.new(sim, null, 0)
	host.hud.results_table = false
	var r := host.hud.race
	r.names = {1: "Nora", 2: "Ivo", 3: "Maja", 4: "Tine"}
	r.ai_levels = {1: "Expert", 2: "Expert", 3: "Pro", 4: "Easy"}
	r.boat_names = {0: "Kestrel", 1: "Nora", 2: "Ivo", 3: "Maja", 4: "Tine"}
	r.sail_numbers = {0: "7", 1: "12", 2: "3", 3: "21", 4: "9"}
	return host


func test_screen() -> void:
	t.begin("results screen: rows, title, navigation, actions, fit (menus.md §5)")
	root.size = Vector2i(1280, 800)
	var sim := _racing(5)
	var host := _screen_host(sim)
	root.add_child(host)
	var rs := ResultsScreen.new()
	rs.act = false
	host.add_child(rs)
	await process_frame
	host.hud.tick(sim, 0)
	sim.order = PackedInt32Array([1, 0, 2, 3, 4])
	_finish(sim, 1, 1, 1400000000)
	_tick(host.hud.race, sim)
	_finish(sim, 0, 2, 1412350000)
	_tick(host.hud.race, sim)
	await process_frame
	t.ok(not rs.is_open, "not before the card has run")
	_tick(host.hud.race, sim, RaceHudValues.CARD_TICKS)
	await process_frame
	await process_frame
	t.ok(rs.is_open and not host.hud.visible, "opens when due; the HUD hides")
	t.ok(root.gui_get_focus_owner() == rs.buttons["again"], "focus on Race again")
	t.ok(rs.heading_label.text == "FINISHING" and rs.line_label.text.begins_with("2 of 5 home"),
		"finishing heading: %s / %s" % [rs.heading_label.text, rs.line_label.text])
	t.ok(rs.title.text == "2ND" and rs.title.tagline_text == "FINISHED  0:23:32.35  +0:12",
		"title: %s / %s" % [rs.title.text, rs.title.tagline_text])
	# a boat ghosted at the start limit is a DNS, not a disqualification (menus.md §5)
	var why_was: String = host.hud.race.end_reason
	host.hud.race.end_reason = "ghost"
	var code_was := ""
	for row in host.hud.race.result_rows:
		if int(row["boat"]) == host.hud.race.own_boat:
			code_was = str(row.get("code", ""))
			row["code"] = "DNS"
	t.ok(rs.title_words() == ["DNS", "DID NOT START"], "a DNS ghost's title: %s" % str(rs.title_words()))
	host.hud.race.end_reason = why_was
	for row in host.hud.race.result_rows:
		if int(row["boat"]) == host.hud.race.own_boat:
			row["code"] = code_was
	t.ok(rs.own_row == 1 and rs.shown_rows[1][2] == "Kestrel" and rs.shown_rows[1][3] == "You"
		and rs.shown_rows[1][1] == "7", "the player's row: %s" % str(rs.shown_rows[1]))
	var own_box := (rs.table.get_child(rs.own_row + 1) as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	t.ok(own_box.bg_color == MenuTheme.ACCENT and own_box.border_width_left == MenuTheme.FOCUS_EDGE,
		"the player's row in the accent with the navy edge")
	t.ok(rs.shown_rows[0][3] == "AI · Expert" and rs.shown_rows[2][6] == "Racing", "AI badge, live status: %s" % str(rs.shown_rows[2]))
	# hud.md §10: the HUD's ranking list names every boat as the results do (sail, boat, skipper)
	var by_boat := {}
	for rw in host.hud.race.ranking_rows():
		by_boat[int(rw["boat"])] = [rw["sail"], rw["name"], rw["skipper"]]
	var same := by_boat.size() == host.hud.race.result_rows.size()
	for i in host.hud.race.result_rows.size():
		var b := int(host.hud.race.result_rows[i]["boat"])
		same = same and by_boat.has(b) and by_boat[b] == rs.shown_rows[i].slice(1, 4)
	t.ok(same, "ranking list and results name the boats alike: %s | %s" % [str(by_boat), str(rs.shown_rows)])
	# the close: final rows, codes and the projected finish
	sim.results_a = [
		{"boat": 1, "place": 1, "code": 0, "code_name": "", "points": 1.0, "t_finish_us": 1400000000, "projected": false},
		{"boat": 0, "place": 2, "code": 0, "code_name": "", "points": 2.0, "t_finish_us": 1412350000, "projected": false},
		{"boat": 2, "place": 3, "code": 0, "code_name": "", "points": 3.0, "t_finish_us": 1500000000, "projected": true},
		{"boat": 3, "place": 0, "code": 4, "code_name": "OCS", "points": 6.0, "t_finish_us": 0, "projected": false},
		{"boat": 4, "place": 0, "code": 9, "code_name": "DSQ", "points": 6.0, "t_finish_us": 0, "projected": false},
	]
	sim.race_d["state"] = RaceText.RaceState.CLOSED
	sim.race_ev = [_rev(RaceText.Ev.RACE_CLOSED, {})]
	_tick(host.hud.race, sim)
	await process_frame
	t.ok(rs.heading_label.text == "RESULTS" and rs.line_label.text == "Practice Waters · %s · 5 boats"
		% MenuData.name_of(MenuData.courses("practice_waters", "wm7"), "practice_waters/example_wl"),
		"final heading: %s / %s" % [rs.heading_label.text, rs.line_label.text])
	var codes := rs.shown_rows.map(func(x: Array) -> String: return x[6])
	t.ok(codes == ["", "", "", "OCS", "DSQ"] and rs.shown_rows[2][4] == "0:25:00.00 proj." and rs.shown_rows[3][7] == "6",
		"codes %s, projected %s" % [str(codes), rs.shown_rows[2][4]])
	t.ok(rs.shown_rows[0][0] == "1" and rs.shown_rows[0][7] == "1" and rs.shown_rows[1][5] == "+0:12", "places, points, gap")
	# keyboard: right, right, left between the actions; down scrolls the body
	_key("ui_right")
	await process_frame
	t.ok(root.gui_get_focus_owner() == rs.buttons["setup"], "right: Change setup")
	_key("ui_right")
	await process_frame
	t.ok(root.gui_get_focus_owner() == rs.buttons["menu"], "right: Main menu")
	_key("ui_left")
	_key("ui_left")
	await process_frame
	t.ok(root.gui_get_focus_owner() == rs.buttons["again"], "left x2: Race again")
	# a summary long enough to scroll at 130 %
	var hr := host.hud.race
	hr.start_t = 3.0
	for k in 6:
		hr.roundings.append({"step": k + 1, "label": "Windward", "place": 3, "gap": 12.0})
	hr.top_speed = 4.0
	hr.distance_sailed = 3000.0
	Settings.current().ui_scale = 1.3
	Settings.current().apply_display(root)
	await process_frame
	await process_frame
	var sc: ScrollContainer = rs._scroll
	var before := sc.scroll_vertical
	_key("ui_down")
	await process_frame
	t.ok(sc.scroll_vertical > before and root.gui_get_focus_owner() == rs.buttons["again"],
		"down scrolls the body, the focus stays (%d -> %d)" % [before, sc.scroll_vertical])
	_key("ui_up")
	await process_frame
	t.ok(sc.scroll_vertical < before + 1, "up scrolls back")
	# fit: 1280 x 800 and the portrait window at 80 %, 100 % and 130 %
	for scr in [Vector2i(1280, 800), Vector2i(1080, 1920)]:
		root.size = scr
		for k in [0.8, 1.0, 1.3]:
			Settings.current().ui_scale = k
			Settings.current().apply_display(root)
			await process_frame
			await process_frame
			await process_frame
			var vis := root.get_visible_rect().grow(1)
			var need: Array = [rs._panel, rs.title, rs.buttons["again"], rs.buttons["setup"], rs.buttons["menu"],
				rs.heading_label]
			var inside := true
			for c in need:
				inside = inside and vis.encloses((c as Control).get_global_rect())
			var apart := not rs.title.get_global_rect().intersects(rs._panel.get_global_rect())
			var row_w := (rs.table.get_child(1) as Control).get_global_rect()
			var fits := rs._scroll.get_global_rect().grow(1).encloses(Rect2(row_w.position, Vector2(row_w.size.x, 1)))
			if not (inside and apart and fits):
				print("  %s at %d %%: vis %s panel %s title %s row %s" % [scr, roundi(k * 100), vis,
					rs._panel.get_global_rect(), rs.title.get_global_rect(), row_w])
			t.ok(inside and apart and fits, "fits %s at %d %% (%s layout)" % [scr, roundi(k * 100),
				"wide" if rs.wide else "stacked"])
	Settings.current().ui_scale = 1.0
	Settings.current().apply_display(root)
	root.size = Vector2i(1280, 800)
	# the actions
	var acts: Array[String] = []
	rs.action_requested.connect(func(a: String) -> void: acts.append(a))
	GameSetup.next = null
	rs.press("again")
	var g := GameSetup.next
	t.ok(g != null and g.mode == "race" and g.course == "practice_waters/example_wl" and g.fleet_size == 5
		and g.ai_level == "pro" and g.livery == "kestrel" and absf(g.wind_kn - 17.0) < 1e-9
		and absf(g.wind_from_deg - 45.0) < 1e-9, "Race again: the same setup")
	t.ok(g != null and g.seed == 0, "Race again: a new seed (0, from the clock)")
	rs.press("setup")
	var last := Settings.current().last_setup
	t.ok(MainMenu.open_on == "quick" and last.get("fleet_size") == 5 and last.get("ai_level") == "pro"
		and last.get("mode") == "race", "Change setup: remembered, the race card next")
	var saved := Settings.new()
	saved.load_file(TEST_PATH)
	t.ok(saved.last_setup.get("wind_kn") == 17.0, "Change setup: saved in the settings file")
	rs.press("menu")
	t.ok(acts == ["again", "setup", "menu"] and MainMenu.open_on == "", "Main menu: %s" % str(acts))
	host.queue_free()
	await process_frame
	# the main menu opens on the race card with the remembered setup
	MainMenu.open_on = "quick"
	var m := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	m.change_scenes = false
	m.live_backdrop = false
	root.add_child(m)
	await process_frame
	await process_frame
	await process_frame
	var q := m.quick
	t.ok(m.page == "quick" and q.is_visible_in_tree() and MainMenu.open_on == "", "the main menu opens on the race card")
	t.ok(int(q.rows["fleet_size"].value) == 5 and str(q.rows["ai_level"].value) == "pro"
		and absf(float(q.rows["wind_kn"].value) - 17.0) < 1e-9 and str(q.rows["livery"].value) == "kestrel",
		"with the setup: fleet %s, %s, %s kn, %s" % [q.rows["fleet_size"].value, q.rows["ai_level"].value,
		q.rows["wind_kn"].value, q.rows["livery"].value])
	t.ok(root.gui_get_focus_owner() == q.rows["class_id"], "focus on its first row")
	m.queue_free()
	await process_frame


# ---- cameras.md §9.1 ---------------------------------------------------------------------------------------------

func test_finish_view() -> void:
	t.begin("finish view (cameras.md §9.1)")
	var rig := CameraRig.new()
	get_root().add_child(rig)
	var tg := CamTypes.Target.new()
	tg.loa = 7.2
	tg.beam_max = 2.5
	var c := CameraInput.new()
	for i in 60:
		rig.frame(tg, c, 1.0 / 60.0)
	var chase_eye := rig.camera.transform.origin
	rig.ease_to(CameraRig.Mode.FINISH, tg)
	rig.frame(tg, c, 1.0 / 600.0)
	t.ok(rig.mode == CameraRig.Mode.FINISH and rig.camera.transform.origin.distance_to(chase_eye) < 0.05,
		"the ease starts on the chase eye (%.3f m)" % rig.camera.transform.origin.distance_to(chase_eye))
	for i in 74:
		rig.frame(tg, c, 1.0 / 60.0)
	var mid := rig.camera.transform.origin
	var d_mid := Vector2(mid.x, mid.z).length()
	for i in 80:
		rig.frame(tg, c, 1.0 / 60.0)
	var e := rig.camera.transform.origin
	var d := Vector2(e.x, e.z).length()
	t.ok(d >= 44.9 and d <= 70.1 and e.y >= 4.9 and e.y <= 11.1, "the drift after 2.5 s: %.1f m out, %.1f m up" % [d, e.y])
	t.ok(d_mid > Vector2(chase_eye.x, chase_eye.z).length() + 1.0 and d_mid < d - 1.0,
		"halfway neither (%.1f m between %.1f and %.1f)" % [d_mid, Vector2(chase_eye.x, chase_eye.z).length(), d])
	var a0 := rig.finish.alpha
	for i in 120:
		rig.frame(tg, c, 1.0 / 60.0)
	t.near(Frames.wrap_pi(rig.finish.alpha - a0), deg_to_rad(3.0), 1e-3, "circles at 1.5° a second")
	c.next = true
	rig.frame(tg, c, 1.0 / 60.0)
	t.ok(rig.mode == CameraRig.Mode.CHASE, "camera_next leaves it for chase")
	t.ok(int(rig.to_dict()["mode"]) == CameraRig.Mode.CHASE, "the profile keeps chase")
	t.ok(not CameraRig.is_clip(CameraRig.Mode.FINISH), "not a clip camera")
	rig.queue_free()


# ---- the core ----------------------------------------------------------------------------------------------------

func test_autopilot_core() -> void:
	t.begin("the finished-boat autopilot sails the player's boat clear (race.md §6.2)")
	var sim := CoreSimSource.new()
	sim.settings = {"race_seed": 20260925, "wind_speed": 11.0 * KNOT, "wind_from": 0.2, "shift_preset": 1,
		"free_sailing_s": 10.0}
	if not sim.create("practice_waters"):
		t.ok(false, "world: " + sim.last_error())
		return
	sim.add_entry("wm7", {"human": true})
	sim.add_entry("wm7", {"human": true})
	sim.create_race("practice_waters/example_wl")
	var pilot := RacePilot.new(sim)
	var n := 0
	while n < 60000 and not bool(sim.race_boat(0)["finished"]):
		pilot.steer()
		sim.step()
		n += 1
	t.ok(bool(sim.race_boat(0)["finished"]), "the pilot sailed her to the finish (%d ticks)" % n)
	t.ok(sim.ai_add_autopilot(0), "autopilot added on her finish, as the sail scene does")
	var s0 := sim.state(0)
	var p0 := Vector2(s0.pos_x, s0.pos_y)
	var far := 0.0
	var v_end := 0.0
	for i in 1800:
		pilot.steer()  # the pilot keeps steering; the autopilot has the helm now
		sim.step()
		var s := sim.state(0)
		far = maxf(far, Vector2(s.pos_x, s.pos_y).distance_to(p0))
		v_end = s.v
	print("  autopilot: %.1f m from the finish point, %.2f m/s after 90 s" % [far, v_end])
	t.ok(far > 2.0 * sim.class_info(0).loa, "she sails clear of the line (%.1f m)" % far)
	t.ok(v_end < 1.5, "and stops there, luffed (%.2f m/s)" % v_end)


func _scene(fleet: int) -> Node:
	GameSetup.next = null
	var sc: Node = (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	sc.set("auto_process", false)
	sc.set("sim_kind", 1)  # CORE
	sc.set("race_mode", true)
	sc.set("fleet_size", fleet)
	sc.set("ai_level", "expert")
	sc.set("core_settings", {"free_sailing_s": 5.0})
	return sc


func test_scene_flow() -> void:
	t.begin("a quick race in the sail scene from the spawn to the results screen")
	var sc := _scene(3)
	get_root().add_child(sc)
	sc.set("scripted_input", RawInput.new())
	await process_frame
	var hud: Hud = sc.get("hud")
	var rig: CameraRig = sc.get("rig")
	var rs: ResultsScreen = sc.get("results")
	t.ok(rs != null and not hud.results_table, "the results screen is there, the HUD's table off")
	if rs == null:
		sc.queue_free()
		return
	rs.act = false
	# controls.md §2: in a race Backspace asks first; a second press within 3 s restarts it, a later one asks again
	var sim0: Object = sc.get("sim")
	_press(sc, &"reset_boat")
	t.ok(sc.get("sim") == sim0 and hud.text_of("message").begins_with("Restart the race? Press "),
		"Backspace once: a note, no restart: %s" % hud.text_of("message"))
	var seed0 := int(sc.get("world_seed"))
	_press(sc, &"reset_boat")
	t.ok(sc.get("sim") != sim0, "Backspace again within 3 s: the race restarts")
	# menus.md §2, controls.md §2 (WM-212): the restart is the same race, on the same seed
	t.ok(int(sc.get("world_seed")) == seed0 and int((sc.get("sim") as CoreSimSource).settings.get("race_seed", -1)) == seed0,
		"Backspace: the same seed (%d)" % seed0)
	var sim1: Object = sc.get("sim")
	_press(sc, &"reset_boat")
	for i in 200:  # 3.3 s
		sc.call("step_frame", 1.0 / 60.0)
	_press(sc, &"reset_boat")
	t.ok(sc.get("sim") == sim1, "a press after 3 s asks again")
	(sc.get("sim") as CoreSimSource).ai_take_over(0)  # an AI skipper sails the player's boat round the course
	var frames := 0
	while frames < 20000 and not hud.race.race_over:
		sc.call("step_frame", 0.25)
		frames += 1
	t.ok(hud.race.race_over and hud.race.end_reason == "finished", "her race is over: %s after %d frames"
		% [hud.race.end_reason, frames])
	t.ok(rig.mode == CameraRig.Mode.FINISH, "the camera eases into the finish view")
	t.ok(hud.race.card.get("kind", "") == "finish", "the finish card")
	for i in 30:
		sc.call("step_frame", 0.25)
		await process_frame
	await process_frame
	t.ok(rig._blend_from < 0, "the ease is done after 2.5 s (camera frames are at most 0.1 s)")
	t.ok(rs.is_open and not hud.visible, "the results screen after the card; the HUD hidden")
	t.ok(hud.race.results_final and rs.shown_rows.size() == 3 and rs.own_row >= 0, "final results, three rows")
	print("  results: %s" % str(rs.shown_rows))
	print("  summary: %s" % str(hud.race.summary_lines()))
	t.ok(rs.title.text == RaceText.ordinal(hud.race.own_place()).to_upper(), "title: the place %s" % rs.title.text)
	var labels := hud.race.summary_lines().map(func(x: Array) -> String: return x[0])
	t.ok(labels.has("Start") and labels.has("Top speed") and labels.has("Distance sailed") and labels.has("Places"),
		"summary items: %s" % str(labels))
	t.ok(rs.shown_rows[rs.own_row][1] != "" and rs.shown_rows[rs.own_row][2] != "You", "sail number and boat name")
	# the pause menu over the results: Retire hidden, Resume back to them
	var pm := sc.get_node_or_null("PauseMenu") as PauseMenu
	t.ok(pm != null, "the pause menu")
	if pm != null:
		pm.act = false
		sc.set("scripted_input", RawInput.new().press(&"pause_menu"))
		sc.call("step_frame", 1.0 / 60.0)
		sc.set("scripted_input", RawInput.new())
		await process_frame
		await process_frame
		t.ok(pm.is_open and not pm.buttons["retire"].visible, "pause menu over the results, no Retire")
		pm.buttons["resume"].pressed.emit()
		await process_frame
		await process_frame
		var fo := get_root().gui_get_focus_owner()
		t.ok(not pm.is_open and fo != null and rs.buttons.values().has(fo), "Resume: the focus back on the results")
	var old_seed := int(sc.get("world_seed"))
	GameSetup.next = null
	rs.press("again")
	var g := GameSetup.next
	t.ok(g != null and g.mode == "race" and g.fleet_size == 3 and g.course == str(sc.get("course"))
		and g.ai_level == "expert" and g.seed == 0 and old_seed != 0, "Race again: the setup, a new seed")
	sc.queue_free()
	await process_frame
	# Race again starts the scene from it: a new seed from the clock
	var sc2: Node = (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	sc2.set("auto_process", false)
	sc2.set("sim_kind", 1)
	get_root().add_child(sc2)
	await process_frame
	t.ok(bool(sc2.get("race_mode")) and int(sc2.get("fleet_size")) == 3 and int(sc2.get("world_seed")) != old_seed
		and int(sc2.get("world_seed")) != 0, "the new race: same fleet, seed %d (was %d)" % [sc2.get("world_seed"), old_seed])
	# menus.md §2 (WM-212): the pause menu's Restart in that race is the same race again, although GameSetup still
	# carries seed 0 (Race again's new day); the reloaded scene takes the running seed
	var pm2 := sc2.get_node_or_null("PauseMenu") as PauseMenu
	var seed2 := int(sc2.get("world_seed"))
	t.ok(pm2 != null and GameSetup.next.seed == 0 and pm2.restart_seed() == seed2, "Restart's seed: %d" % seed2)
	GameSetup.restart_seed = pm2.restart_seed() if pm2 != null else 0  # what Restart sets before the reload
	sc2.queue_free()
	await process_frame
	var sc3: Node = (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	sc3.set("auto_process", false)
	sc3.set("sim_kind", 1)
	get_root().add_child(sc3)
	await process_frame
	t.ok(int(sc3.get("world_seed")) == seed2 and GameSetup.restart_seed == 0 and bool(sc3.get("race_mode"))
		and int((sc3.get("sim") as CoreSimSource).settings.get("race_seed", -1)) == seed2,
		"Restart: the same race again, seed %d" % sc3.get("world_seed"))
	GameSetup.next = null
	sc3.queue_free()
	await process_frame


## one frame of the scene with `action` pressed
func _press(sc: Node, action: StringName) -> void:
	sc.set("scripted_input", RawInput.new().press(action))
	sc.call("step_frame", 1.0 / 60.0)
	sc.set("scripted_input", RawInput.new())


func test_scene_retire() -> void:
	t.begin("Retire from the pause menu (menus.md §2, race.md §6.4)")
	var sc := _scene(2)
	get_root().add_child(sc)
	sc.set("scripted_input", RawInput.new())
	await process_frame
	var hud: Hud = sc.get("hud")
	var pm := sc.get_node_or_null("PauseMenu") as PauseMenu
	pm.act = false
	pm.open()
	t.ok(not pm.buttons["retire"].visible, "no Retire before the warning signal")
	pm.close()
	var n := 0
	while n < 4000 and int((sc.get("sim") as CoreSimSource).race().get("state", 0)) < RaceText.RaceState.SEQUENCE:
		sc.call("step_frame", 0.25)
		n += 1
	pm.open()
	t.ok(pm.buttons["retire"].visible, "Retire in the sequence")
	pm.buttons["retire"].pressed.emit()
	t.ok(pm.is_open and pm.buttons["retire"].text == PauseMenu.RETIRE_ASK.to_upper(), "the first press asks again")
	pm.buttons["retire"].pressed.emit()
	t.ok(not pm.is_open, "the second press retires and closes the menu")
	for i in 3:
		sc.call("step_frame", 0.25)
	var rb := (sc.get("sim") as CoreSimSource).race_boat(0)
	t.ok(bool(rb["retired"]) and hud.race.race_over and hud.race.end_reason == "retired", "retired, her race is over")
	t.ok((sc.get("rig") as CameraRig).mode == CameraRig.Mode.FINISH, "the finish view")
	pm.open()
	t.ok(not pm.buttons["retire"].visible, "no Retire after it")
	pm.close()
	sc.queue_free()
	await process_frame
