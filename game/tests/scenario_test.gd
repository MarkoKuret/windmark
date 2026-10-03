extends SceneTree
## Headless test of the rules scenarios (WM-016.33, race.md §14, data_format.md §9):
##   - the scenario files of game/data/scenarios load; bad files are refused with the JSON path
##   - port/starboard: every boat started, set up at clip time 0 on her heading, speed and front sail, then the
##     port-tack boat is the one to keep clear under rule 10 and receives the rule 10 penalty, in every run (two
##     worlds), with the same checksum every tick
##   - windward/leeward: the windward boat keeps clear under rule 11 and receives the penalty
##   - the sail scene started with GameSetup mode scenario: the scenario's boats, the player watching, paused at the
##     clip's end, and reset_boat running it again
##   godot --headless --path game -s res://tests/scenario_test.gd

const RULE_10 := 1
const RULE_11 := 2
const REV_PENALTY := 2

var t := TestLog.new()


func _init() -> void:
	if not t.ok(CoreSimSource.available(), "GDExtension loaded (game/native/build.sh)"):
		t.finish(self, "scenario test")
		return
	test_files()
	test_port_starboard()
	test_windward_leeward()
	await test_scene()
	t.finish(self, "scenario test")


func test_files() -> void:
	t.begin("scenario files")
	for f in DirAccess.get_files_at(BoatClassData.repo_path("game/data/scenarios")):
		if not f.ends_with(".scenario.json"):
			continue
		var why := []
		var s := Scenario.load_file(f.trim_suffix(".scenario.json"), why)
		t.ok(s != null, "%s loads%s" % [f, "" if why.is_empty() else ": " + str(why[0])])
	var s := Scenario.load_file("port_starboard")
	t.ok(s.class_id == "wm7" and s.course == "example_bay/example_wl" and s.venue == "example_bay", "class, course")
	t.ok(s.boats.size() == 2 and s.boats[0].tack == 1 and s.boats[1].tack == -1, "starboard and port boats")
	t.ok(s.lead == 20.0 and s.after == 5.0 and s.shift_preset == 0 and not s.puffs, "lead, after, steady, no puffs")
	t.ok(s.boats[0].helm == "hold" and s.boats[0].speed < 0.0 and s.boats[0].front_sail == "", "defaults")
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Scenario.file_of("port_starboard")))
	var cases := [
		["schema", "windmark.scenario/2", "$.schema"],
		["wind", {"speed": 6.0}, "$.wind.from"],
		["boats", [], "$.boats"],
		["course", "example_bay/nowhere", "$.course"],
	]
	for c in cases:
		var d := good.duplicate(true)
		d[c[0]] = c[1]
		var why := []
		t.ok(Scenario.parse(d, why) == null and str(why[0]).begins_with(c[2]), "refused at %s: %s" % [c[2], why])
	var d2 := good.duplicate(true)
	d2["boats"][1]["helm"] = "player"
	var why2 := []
	t.ok(Scenario.parse(d2, why2) == null and str(why2[0]).begins_with("$.boats[1].helm"), "player on boat 1 refused")
	var d3 := good.duplicate(true)
	d3["boats"][0]["tack"] = "upwind"
	var why3 := []
	t.ok(Scenario.parse(d3, why3) == null and str(why3[0]).begins_with("$.boats[0].tack"), "bad tack refused")


## Runs a scenario to the end of its clip: per tick checksums, the pairs' keep-clear rules seen and the penalties.
func _run(run: ScenarioRun, cs: CoreSimSource) -> Dictionary:
	var out := {"sums": PackedInt64Array(), "kc": {}, "penalties": [], "first_kc_tick": -1}
	while not run.finished(cs):
		cs.step()
		out["sums"].append(cs.checksum())
		for p in cs.pairs():
			if p["kc_rule"] != 0:
				var k := "%d>%d:%d" % [p["kc_giver"], p["kc_holder"], p["kc_rule"]]
				out["kc"][k] = true
		for e in cs.rules_events():
			if e["kind"] == REV_PENALTY:
				out["penalties"].append({"boat": e["boat"], "rule": e["rule"], "t": run.clip_time(cs)})
	return out


func test_port_starboard() -> void:
	t.begin("port/starboard: rule 10 every run")
	var s := Scenario.load_file("port_starboard")
	var runs := []
	for k in 2:
		var run := ScenarioRun.new(s)
		var cs := run.make_core()
		if not t.ok(cs != null, "starts: " + run.error):
			return
		if k == 0:
			_check_setup(run, cs)
		runs.append(_run(run, cs))
	for k in runs.size():
		var r: Dictionary = runs[k]
		t.ok(r["kc"].has("1>0:%d" % RULE_10), "run %d: the port boat keeps clear of the starboard boat under rule 10 (%s)"
			% [k + 1, r["kc"].keys()])
		var pen: Array = r["penalties"]
		t.ok(pen.size() == 1 and pen[0]["boat"] == 1 and pen[0]["rule"] == RULE_10,
			"run %d: one penalty, the port boat's, rule 10: %s" % [k + 1, pen])
		if pen.size() > 0:
			print("port/starboard run %d: penalty boat %d rule %d at clip time %.2f s" % [k + 1, pen[0]["boat"],
				pen[0]["rule"], pen[0]["t"]])
	t.ok(runs[0]["sums"] == runs[1]["sums"] and runs[0]["sums"].size() == 500,
		"two runs: the same checksum every tick (%d ticks)" % runs[0]["sums"].size())


func _check_setup(run: ScenarioRun, cs: CoreSimSource) -> void:
	t.ok(run.clip_time(cs) == 0.0, "clip time 0 at the set-up")
	var race: Dictionary = cs.race()
	t.ok(race["state"] == 3 and race["rules_live"], "racing, rules live")
	for i in 2:
		t.ok(cs.race_boat(i)["started"] and not cs.race_boat(i)["ocs"], "boat %d started" % i)
		var st := cs.state(i)
		t.near(Frames.wrap_pi(st.psi - run.psi[i]), 0.0, 1e-5, "boat %d on her set-up heading" % i)
		t.near(st.v, run.speed[i], 1e-4, "boat %d at her set-up speed" % i)
		t.ok(run.speed[i] > 2.0, "boat %d speed is the polar speed: %.2f m/s" % [i, run.speed[i]])
		t.near(st.pos_x, run.setup_pos[i].x, 1e-2, "boat %d at her set-up x" % i)
		t.near(st.pos_y, run.setup_pos[i].y, 1e-2, "boat %d at her set-up y" % i)
		t.ok(cs.sails(i).front == cs.class_info(i).sails.map(func(x: SimSource.SailInfo) -> String: return x.name).find("jib"),
			"boat %d has the class start sail up" % i)
		t.ok(int(cs.boat_rules(i)["tack"]) == (1 if i == 0 else -1), "boat %d on her tack for the rules" % i)
	# both would reach the incident point 300 m up the beat in `lead` seconds
	var meet := run.setup_pos[0] + Vector2(sin(run.psi[0]), cos(run.psi[0])) * run.speed[0] * 20.0
	var meet1 := run.setup_pos[1] + Vector2(sin(run.psi[1]), cos(run.psi[1])) * run.speed[1] * 20.0
	t.ok(meet.distance_to(meet1) < 0.01, "both set up to meet at the same point")


func test_windward_leeward() -> void:
	t.begin("windward/leeward: rule 11")
	var s := Scenario.load_file("windward_leeward")
	var run := ScenarioRun.new(s)
	var cs := run.make_core()
	if not t.ok(cs != null, "starts: " + run.error):
		return
	var r := _run(run, cs)
	t.ok(r["kc"].has("0>1:%d" % RULE_11), "boat 0 (windward) keeps clear under rule 11 (%s)" % [r["kc"].keys()])
	var pen: Array = r["penalties"]
	t.ok(pen.size() == 1 and pen[0]["boat"] == 0 and pen[0]["rule"] == RULE_11, "one penalty, boat 0, rule 11: %s" % [pen])


func test_scene() -> void:
	t.begin("sail scene: GameSetup mode scenario")
	var gs := GameSetup.new()
	gs.mode = "scenario"
	gs.scenario = "port_starboard"
	var sc := (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	sc.auto_process = false
	sc.setup = gs
	root.add_child(sc)
	sc.scripted_input = RawInput.new()
	await process_frame
	var sim: CoreSimSource = sc.sim
	t.ok(sc.scenario_run != null and sc.on_core and sc.race_mode and sim.boat_count() == 2, "the scenario's two boats")
	t.ok(not sc.racing and sc.can_spectate() and sc.viewed == 0, "the player watches boat 0")
	t.ok(sc.scenario_run.clip_time(sim) == 0.0, "the scene starts at clip time 0")
	var tick0 := sim.tick()
	for k in 600:
		sc.step_frame(SimSource.DT)
	t.ok(sc.runner.paused and sim.tick() - tick0 == 500, "paused at the clip's end: %d ticks" % (sim.tick() - tick0))
	t.ok(int(sim.boat_rules(1)["received"]) == 1, "the port boat was penalised in the scene")
	sc.reset_boat()
	var sim2: CoreSimSource = sc.sim
	t.ok(sim2 != sim and not sc.runner.paused and sc.scenario_run.clip_time(sim2) == 0.0, "reset runs it again")
	sc.queue_free()
	await process_frame
