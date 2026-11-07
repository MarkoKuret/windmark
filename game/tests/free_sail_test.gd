extends SceneTree
## Wrong-mode and wrong-time events (hud.md events and feed, audio.md §5) run headless on the core:
##   1. free sailing (no race, one boat, the venue's course laid, courses.md §6.4) for a few minutes of sim time: no
##      hud_event, no race or voice sound, no banner, toast, flag, feed line, penalty panel, ranking or results, no
##      name tags; the same after the reset key, after a new world (the look panel's restart with a wind) and while
##      paused; free sailing on empty water (no course) the same with no course items at all;
##   2. free sail round the laid course (courses.md §6.4, hud.md §7.2): the start line first, each mark and the gate
##      in order by the race's tests (a mark passed on the wrong side is not rounded), the finish, then the start
##      line again; the HUD's next mark and the CourseView follow, and nothing of the race fires;
##   3. a race from its start: nothing of the race fires before the first tick has a valid state, the warning
##      signal fires once, and nothing of the race fires while the game is paused.
##   godot --headless --path game -s res://tests/free_sail_test.gd

const DT := 1.0 / 30.0

var t := TestLog.new()
var events: Array = []


func _init() -> void:
	await process_frame
	if not CoreSimSource.available():
		t.ok(false, "the GDExtension is not loaded")
		t.finish(self, "free_sail_test")
		return
	await test_free_sail()
	await test_empty_water()
	await test_free_course()
	await test_race_start()
	t.finish(self, "free_sail_test")


func _scene(race: bool, fleet: int, course := "practice_waters/example_wl") -> Node:
	var sc: Node = (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	sc.set("auto_process", false)
	sc.set("sim_kind", 1)  # CORE
	sc.set("race_mode", race)
	sc.set("course", course)
	sc.set("fleet_size", fleet)
	sc.set("ai_level", "expert")
	sc.set("with_pause_menu", false)
	sc.set("with_results", false)
	sc.set("apply_settings", false)
	sc.set("core_settings", {"free_sailing_s": 5.0})
	get_root().add_child(sc)
	sc.set("scripted_input", RawInput.new())
	events.clear()
	(sc.get("hud") as Hud).hud_event.connect(func(kind: String, d: Dictionary) -> void:
		events.append({"kind": kind, "data": d}))
	return sc


func _played(a: GameAudio, prefix: String, since := 0) -> Array:
	var out := []
	for i in range(since, a.played.size()):
		if String(a.played[i]["id"]).begins_with(prefix):
			out.append(a.played[i])
	return out


## Everything of the race that must stay quiet without one (on a laid course the mark tag may show, hud.md §7.2).
func _quiet(sc: Node, what: String, since := 0) -> void:
	var hud: Hud = sc.get("hud")
	var a: GameAudio = sc.get("audio")
	var r := hud.race
	t.ok(not r.active, "%s: race values inactive" % what)
	t.ok(events.is_empty(), "%s: no hud_event (%s)" % [what, str(events.slice(0, 3))])
	var race_sounds := _played(a, "race.", since) + _played(a, "voice.", since)
	t.ok(race_sounds.is_empty(), "%s: no race sound (%s)" % [what, str(race_sounds.slice(0, 3))])
	t.ok(hud.text_of("banner") == "" and hud.text_of("rules") == "" and hud.text_of("prompt") == "",
		"%s: no banner, rules line or prompt" % what)
	t.ok(r.feed.is_empty() and hud.feed_text().is_empty(), "%s: no feed line" % what)
	var shown := []
	var panels := [hud.race_panel, hud.penalty_panel, hud.flags_view, hud.results_panel, hud.ranking_panel,
		hud.bug_block, hud.feed_block]
	if not r.free:
		panels.append(hud.next_panel)
	for p in panels:
		if p.is_visible_in_tree():
			shown.append(p.name)
	t.ok(shown.is_empty(), "%s: race panels hidden (%s)" % [what, str(shown)])
	t.ok(not hud.countdown_shown() and not hud.finish_card_shown(), "%s: no countdown, no finish card" % what)
	t.ok(hud.name_tags().is_empty() and hud.tag_boats().is_empty(), "%s: no name tags" % what)
	t.ok(hud.ranking_text().is_empty(), "%s: no ranking rows" % what)
	t.ok(not r.race_over and not r.results_visible and not r.penalty_visible, "%s: no race end, no penalty" % what)
	t.ok(r.turn_deg == 0.0 and r.penalties.is_empty(), "%s: no penalty turn" % what)


func test_free_sail() -> void:
	t.begin("free sailing on the core: nothing of the race fires")
	var sc := _scene(false, 1)
	await process_frame
	var a: GameAudio = sc.get("audio")
	var sim: CoreSimSource = sc.get("sim")
	t.ok(not sim.has_race(), "no race in the core")
	t.ok(sim.boat_count() == 1, "one boat (%d)" % sim.boat_count())
	t.ok(sim.has_course() and sim.free_course() != null and sc.get("course_view") != null,
		"the venue's course is laid, with its CourseView")
	# three minutes of sim time with the boat sailing itself on its start heading
	for i in int(180.0 / DT):
		sc.call("step_frame", DT)
	_quiet(sc, "after 180 s")
	t.ok(a.played.size() > 0, "boat sounds play (%d one-shots)" % a.played.size())
	var hist := {}
	for p in a.played:
		hist[p["id"]] = int(hist.get(p["id"], 0)) + 1
	print("  one-shots in 180 s of free sailing: %s" % str(hist))
	# two minutes steering about with the auto trim following (a player at the helm): the sheet sounds fire
	var n := a.played.size()
	for i in int(120.0 / DT):
		var phase := int(i * DT) % 16
		var raw := RawInput.new()
		if phase < 3:
			raw.hold(&"helm_left")
		elif phase >= 8 and phase < 11:
			raw.hold(&"helm_right")
		sc.set("scripted_input", raw)
		sc.call("step_frame", DT)
	sc.set("scripted_input", RawInput.new())
	hist = {}
	for i in range(n, a.played.size()):
		hist[a.played[i]["id"]] = int(hist.get(a.played[i]["id"], 0)) + 1
	print("  one-shots in 120 s at the helm: %s" % str(hist))
	_quiet(sc, "at the helm", n)
	# the reset key: re-placed at the spawn, the progress back at the start line
	n = a.played.size()
	sc.call("reset_boat")
	var sp: Vector3 = sc.get("free_spawn")
	var s0 := (sc.get("sim") as CoreSimSource).state(0)
	t.ok(sp != Vector3.INF and Vector2(s0.pos_x, s0.pos_y).distance_to(Vector2(sp.x, sp.y)) < 1.0,
		"reset: the boat at her spawn")
	t.ok(sim.free_course().next == 0, "reset: the start line is next")
	for i in 60:
		sc.call("step_frame", DT)
	_quiet(sc, "after reset", n)
	# a new world (the look panel's restart with a wind)
	n = a.played.size()
	sc.call("restart_with_wind", 16.0)
	t.ok(not (sc.get("sim") as CoreSimSource).has_race(), "still no race after a new world")
	t.ok((sc.get("sim") as CoreSimSource).has_course() and sc.get("course_view") != null,
		"the course laid again in the new world")
	for i in 60:
		sc.call("step_frame", DT)
	_quiet(sc, "after a new world", n)
	# paused: the sim stands, no sound of the boat or the race
	n = a.played.size()
	(sc.get("runner") as SimRunner).paused = true
	for i in 90:
		sc.call("step_frame", DT)
	var while_paused := []
	for i in range(n, a.played.size()):
		if not String(a.played[i]["id"]).begins_with("amb."):
			while_paused.append(a.played[i])
	t.ok(while_paused.is_empty(), "paused: no one-shot but the ambience (%s)" % str(while_paused.slice(0, 3)))
	_quiet(sc, "paused", n)
	(sc.get("runner") as SimRunner).paused = false
	sc.queue_free()
	await process_frame


func test_empty_water() -> void:
	t.begin("free sailing on empty water (no course): no course items")
	var sc := _scene(false, 1, "")
	await process_frame
	var sim: CoreSimSource = sc.get("sim")
	var hud: Hud = sc.get("hud")
	t.ok(not sim.has_course() and sim.free_course() == null and sc.get("course_view") == null,
		"no course, no CourseView")
	for i in int(30.0 / DT):
		sc.call("step_frame", DT)
	_quiet(sc, "empty water")
	t.ok(not hud.race.free and not hud.race.on_course() and hud.text_of("next") == "" and not hud.radar.visible,
		"no mark tag, no radar")
	sc.queue_free()
	await process_frame


## One tick with boat 0 put at `p` (at rest), the free progress following.
func _at(sim: CoreSimSource, p: Vector2) -> void:
	sim.scenario_place(0, p.x, p.y, sim.state(0).psi, 0.0)
	sim.step()


## Circles the next step's first buoy on its rounding side (σ: port anticlockwise) from the boat's bearing, 10° a
## tick at `r` m, up to `max_deg`; `wrong` circles the other way. Returns the degrees it took (INF: not passed).
func _round(sim: CoreSimSource, r := 25.0, max_deg := 540.0, wrong := false) -> float:
	var fc := sim.free_course()
	var k := fc.next
	var st: Dictionary = fc.course["steps"][k]
	var mi: int = (st["marks"] as PackedInt32Array)[0]
	var m := Vector2(fc.course["marks"][mi]["x"], fc.course["marks"][mi]["y"])
	var port := (st["sides"] as PackedInt32Array)[0] == FreeCourse.SIDE_PORT
	var dir := -1.0 if port != wrong else 1.0  # compass bearings: anticlockwise is decreasing
	var s := sim.state(0)
	var b := Frames.compass(s.pos_x - m.x, s.pos_y - m.y)
	var deg := 0.0
	while deg <= max_deg:
		_at(sim, m + r * Vector2(sin(b), cos(b)))
		if fc.next != k:
			return deg
		b += dir * deg_to_rad(10.0)
		deg += 10.0
	return INF


## Crosses line step `k` (start or finish) at its middle, from the side of `from` to the other side.
func _cross_line(sim: CoreSimSource, k: int, from: Vector2) -> void:
	var fc := sim.free_course()
	var ms: PackedInt32Array = fc.course["steps"][k]["marks"]
	var a := Vector2(fc.course["marks"][ms[0]]["x"], fc.course["marks"][ms[0]]["y"])
	var b := Vector2(fc.course["marks"][ms[1]]["x"], fc.course["marks"][ms[1]]["y"])
	var mid := (a + b) * 0.5
	var nrm := (b - a).normalized().orthogonal()
	if nrm.dot(from - mid) < 0.0:
		nrm = -nrm
	_at(sim, mid + nrm * 20.0)
	_at(sim, mid - nrm * 20.0)


func test_free_course() -> void:
	t.begin("free sail round the laid course: the start line, the marks and the gate in order, the finish, again")
	var sc := _scene(false, 1)
	await process_frame
	var sim: CoreSimSource = sc.get("sim")
	var hud: Hud = sc.get("hud")
	var a: GameAudio = sc.get("audio")
	var cv: CourseView = sc.get("course_view")
	var fc := sim.free_course()
	var steps: Array = fc.course["steps"]
	t.ok(steps.size() == 7, "example course: start, W, Offset, gate, W, Offset, finish (%d steps)" % steps.size())
	# spawned on the pre-start side: the start line is next, named Start, white on the water
	for i in 20:
		sc.call("step_frame", DT)
	t.ok(fc.next == 0 and hud.race.free and hud.race.next_step == 0 and hud.text_of("next") == "Start",
		"the start line first (%s, next %d)" % [hud.text_of("next"), fc.next])
	t.ok(hud.text_of("lap") == "" and hud.race.next_dist < 200.0, "Start: no lap line, the distance to the line (%s)"
		% hud.text_of("mark_dist"))
	t.ok(cv.start_line_state == "white" and cv.lines.any(func(l: Dictionary) -> bool: return l["kind"] == "start"),
		"the start line drawn white while it is next")
	t.ok(hud.radar.visible and hud.phase() != "free" and not hud.has_item("bug") and not hud.has_item("feed_own"),
		"the radar and the leg rows, no race bug or feed (phase %s)" % hud.phase())
	# sailing along the line without crossing it does nothing
	var ms0: PackedInt32Array = steps[0]["marks"]
	var la := Vector2(fc.course["marks"][ms0[0]]["x"], fc.course["marks"][ms0[0]]["y"])
	var lb := Vector2(fc.course["marks"][ms0[1]]["x"], fc.course["marks"][ms0[1]]["y"])
	var up_side: Vector2 = steps[1]["ref"]
	# round an end (the extension, outside the band) to the course side, back through the line, then through it
	# from the pre-start side: only the last starts her
	var beyond := la + (la - lb).normalized() * 60.0
	var pre := (lb - la).normalized().orthogonal()
	if pre.dot(up_side - la) > 0.0:
		pre = -pre
	_at(sim, beyond + pre * 20.0)
	_at(sim, beyond - pre * 20.0)
	t.ok(fc.next == 0, "crossing the line's extension: still the start line")
	_cross_line(sim, 0, up_side)
	t.ok(fc.next == 0, "crossing the start line backwards: still the start line")
	_cross_line(sim, 0, (la + lb) * 0.5 + pre * 50.0)
	t.ok(fc.next == 1, "crossed from the pre-start side: the windward mark is next (%d)" % fc.next)
	for i in 10:
		sc.call("step_frame", DT)
	t.ok(hud.text_of("next") == "Windward" and hud.text_of("lap").begins_with("Lap 1/2"),
		"HUD: Windward, %s" % hud.text_of("lap"))
	t.ok(cv.start_line_state == "hidden", "the start line no longer drawn")
	# the wrong way round the windward mark does not round it; the right way does
	t.ok(is_inf(_round(sim, 25.0, 200.0, true)) and fc.next == 1, "Windward the wrong way: not rounded")
	var deg := _round(sim, 25.0, 900.0)
	t.ok(fc.next == 2 and not is_inf(deg), "Windward to port: rounded after %s°, Offset next" % str(deg))
	deg = _round(sim)
	t.ok(fc.next == 3, "Offset rounded after %s°, the gate next" % str(deg))
	for i in 10:
		sc.call("step_frame", DT)
	t.ok(hud.text_of("next").begins_with("Gate") and cv.lines.any(func(l: Dictionary) -> bool:
		return l["kind"] == "gate"), "HUD: %s, the gate line drawn" % hud.text_of("next"))
	deg = _round(sim)
	t.ok(fc.next == 4, "the gate passed and rounded after %s°, lap 2's Windward next" % str(deg))
	_round(sim, 25.0, 900.0)
	_round(sim)
	t.ok(fc.next == 6, "lap 2 rounded, the finish next (%d)" % fc.next)
	for i in 10:
		sc.call("step_frame", DT)
	t.ok(hud.text_of("next") == "Finish" and cv.lines.any(func(l: Dictionary) -> bool: return l["kind"] == "finish"),
		"HUD: Finish, the finish line drawn")
	_cross_line(sim, 6, steps[5]["ref"])
	t.ok(fc.next == 0 and fc.passed == 7, "finished: the start line next again (%d, %d passed)" % [fc.next, fc.passed])
	for i in 10:
		sc.call("step_frame", DT)
	t.ok(hud.text_of("next") == "Start" and cv.start_line_state == "white", "HUD: Start again, the line white")
	_quiet(sc, "round the course")
	t.ok(_played(a, "race.").is_empty(), "no race sound round the course")
	sc.queue_free()
	await process_frame


func test_race_start() -> void:
	t.begin("a race from its start: nothing fires early, nothing while paused")
	var sc := _scene(true, 3)
	await process_frame
	var a: GameAudio = sc.get("audio")
	var hud: Hud = sc.get("hud")
	var sim: CoreSimSource = sc.get("sim")
	t.ok(sim.has_race(), "a race in the core")
	# the first frames: the state is valid from the first tick, nothing of the race fires before the warning
	for i in 30:
		sc.call("step_frame", DT)
	t.ok(events.is_empty(), "first second: no hud_event (%s)" % str(events.slice(0, 3)))
	t.ok(_played(a, "race.").is_empty(), "first second: no race sound")
	t.ok(hud.race.active and hud.race.feed.is_empty(), "first second: race HUD on, feed empty")
	t.ok(hud.text_of("banner") == "", "first second: no banner (%s)" % hud.text_of("banner"))
	# paused through the warning signal's time: the sim stands, so nothing fires
	(sc.get("runner") as SimRunner).paused = true
	for i in int(6.0 / DT):
		sc.call("step_frame", DT)
	t.ok(events.is_empty() and _played(a, "race.").is_empty(), "paused: no signal, no race sound")
	(sc.get("runner") as SimRunner).paused = false
	for i in int(6.0 / DT):
		sc.call("step_frame", DT)
	var signals := events.filter(func(e: Dictionary) -> bool: return e["kind"] == "signal")
	t.ok(signals.size() == 1, "the warning signal once after the pause (%d)" % signals.size())
	var horns := _played(a, "race.horn")
	t.ok(horns.filter(func(p: Dictionary) -> bool: return p["space"] == "2d").size() == 1,
		"one horn (%d)" % horns.size())
	var n := 0
	t.ok(hud.text_of("banner") != "", "the signal's banner shows")
	# a general recall's second horn (0.8 s after the first) waits while the game is paused
	n = a.played.size()
	(sc.get("runner") as SimRunner).paused = true
	a.race_signal(RaceText.SignalKind.GENERAL_RECALL)
	for i in 60:
		sc.call("step_frame", DT)
	t.ok(_played(a, "race.horn", n).filter(func(p: Dictionary) -> bool: return p["space"] == "2d").size() == 1,
		"paused after a general recall: one horn so far")
	(sc.get("runner") as SimRunner).paused = false
	for i in 60:
		sc.call("step_frame", DT)
	t.ok(_played(a, "race.horn", n).filter(func(p: Dictionary) -> bool: return p["space"] == "2d").size() == 2,
		"the second horn after the pause")
	sc.queue_free()
	await process_frame
