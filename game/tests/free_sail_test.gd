extends SceneTree
## Wrong-mode and wrong-time events (hud.md events and feed, audio.md §5) run headless on the core:
##   1. free sailing (no race, one boat) for a few minutes of sim time: no hud_event, no race or voice sound, no
##      banner, toast, flag, feed line, penalty panel, ranking or results, no name tags; the same after the
##      reset key, after a new world (the look panel's restart with a wind) and while paused;
##   2. a race from its start: nothing of the race fires before the first tick has a valid state, the warning
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
	await test_race_start()
	t.finish(self, "free_sail_test")


func _scene(race: bool, fleet: int) -> Node:
	var sc: Node = (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	sc.set("auto_process", false)
	sc.set("sim_kind", 1)  # CORE
	sc.set("race_mode", race)
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


## Everything of the race that must stay quiet without one.
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
	for p in [hud.race_panel, hud.penalty_panel, hud.flags_view, hud.results_panel, hud.ranking_panel, hud.next_panel,
			hud.bug_block, hud.feed_block]:
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
	# the reset key: re-placed at the start point
	n = a.played.size()
	sc.call("reset_boat")
	for i in 60:
		sc.call("step_frame", DT)
	_quiet(sc, "after reset", n)
	# a new world (the look panel's restart with a wind)
	n = a.played.size()
	sc.call("restart_with_wind", 16.0)
	t.ok(not (sc.get("sim") as CoreSimSource).has_race(), "still no race after a new world")
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
