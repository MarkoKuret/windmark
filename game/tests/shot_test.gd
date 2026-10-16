extends SceneTree
## Shot script tests (cameras.md §10 test 16, §9.2): the files load and bad ones are refused, the cues run in time
## order, and the sail scene runs a shot: camera cues select their mode, slow, pause, resume, hud, tags and input act
## as their keys do, the shot time runs through the pause, `end` and --quit-at end the run, and a race shot with
## `start` begins at that time from the gun. Headless.
##   godot --headless --path game -s res://tests/shot_test.gd

const FPS := 60.0

var t := TestLog.new()


func _init() -> void:
	test_parse()
	test_order()
	await test_scene()
	await test_race_start()
	t.finish(self, "shot")


func _shot(cues: Array, extra := {}) -> Dictionary:
	var d := {"schema": ShotScript.SCHEMA, "cues": cues}
	d.merge(extra, true)
	return d


func test_parse() -> void:
	t.begin("files and refusals")
	for id in ["rule10_penalty", "quiz1_freeze", "puffs_aerial", "letfly", "ai_start", "mark_rounding"]:
		var why := []
		var s := ShotScript.load_file(id, why)
		t.ok(s != null and not s.cues.is_empty() and s.cues[-1]["action"] == "end",
			"%s loads and ends with end %s" % [id, why])
	var s2 := ShotScript.load_file("res://data/shots/letfly.shot.json")
	t.ok(s2 != null and s2.portrait and not s2.hud and not s2.world_tags and is_nan(s2.start), "a path loads, its flags read")
	var bad := {
		"wrong schema": {"schema": "windmark.shot/2", "cues": []},
		"unknown action": _shot([{"t": 1, "zoom": 2}]),
		"no time": _shot([{"end": true}]),
		"two actions": _shot([{"t": 1, "hud": false, "tags": false}]),
		"unknown camera": _shot([{"t": 1, "camera": "drone"}]),
		"slow 0.3": _shot([{"t": 1, "slow": 0.3}]),
		"preset 9": _shot([{"t": 1, "camera": "chase", "preset": 9}]),
		"unknown input": _shot([{"t": 1, "input": "jump", "for": 1}]),
		"input without for": _shot([{"t": 1, "input": "let_fly"}]),
		"start not a number": _shot([], {"start": "gun"}),
	}
	for k in bad:
		var why := []
		t.ok(ShotScript.parse(bad[k], why) == null and not why.is_empty(), "%s refused: %s" % [k, why])
	t.ok(ShotScript.load_file("no_such_shot") == null, "a missing file is refused")
	var p := ShotScript.camera_params({"params": {"el_deg": 90.0, "R": 40}})
	t.near(p["el"], PI * 0.5, 1e-6, "el_deg read in radians as el")
	t.ok(p["R"] == 40 and not p.has("el_deg"), "other params as written")


func test_order() -> void:
	t.begin("cue order")
	var s := ShotScript.parse(_shot([
		{"t": 5, "end": true}, {"t": 1, "hud": false}, {"t": 1, "tags": false}, {"t": -2, "slow": 0.5},
	]))
	var acts := s.cues.map(func(c: Dictionary) -> String: return c["action"])
	t.ok(acts == ["slow", "hud", "tags", "end"], "by time, the file's order for equal times: %s" % [acts])
	t.ok(s.due(-3.0).is_empty(), "nothing due before the first")
	t.ok(s.due(1.0).size() == 3 and s.due(1.0).is_empty(), "each cue runs once")
	t.ok(s.due(10.0).size() == 1 and s.done(), "then the end")


func _scene(shot: ShotScript) -> Node:
	var sc := (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	sc.auto_process = false
	sc.with_pause_menu = false
	sc.apply_settings = false
	sc.shot = shot
	sc.shot_quits = false
	return sc


func test_scene() -> void:
	var core := CoreSimSource.available()
	t.begin("a shot on the sail scene (%s)" % ("core" if core else "FakeSim"))
	var shot := ShotScript.parse(_shot([
		{"t": 0, "camera": "long_lens"},
		{"t": 1, "slow": 0.5},
		{"t": 2, "pause": true},
		{"t": 2, "slow": 1},
		{"t": 3, "resume": true},
		{"t": 3.5, "hud": false},
		{"t": 3.5, "tags": false},
		{"t": 4, "input": "let_fly", "for": 1},
		{"t": 4.5, "camera": "helicopter", "params": {"scale": 2}},
		{"t": 6, "end": true},
	]))
	var sc := _scene(shot)
	if not core:
		sc.sim_kind = sc.SimKind.FAKE
	root.add_child(sc)
	sc.scripted_input = RawInput.new()
	await process_frame
	var dt := 1.0 / FPS
	var frames := 0
	var seen := {}
	var tick_at_pause := -1
	while not sc.shot_ended and frames < 2000:
		sc.step_frame(dt)
		frames += 1
		var now: float = sc.shot_time()
		if frames == 1:
			seen["long_lens"] = sc.rig.mode == CameraRig.Mode.LONG_LENS
		if now > 1.5 and now < 1.9:
			seen["slow"] = sc.capture.rate() == 0.5 and sc.capture.note == ""
		if now > 2.2 and now < 2.8:
			if tick_at_pause < 0:
				tick_at_pause = sc.sim.tick()
			seen["paused"] = sc.capture.frozen and sc.sim.tick() == tick_at_pause
		if now > 3.2 and now < 3.4:
			seen["resumed"] = not sc.capture.frozen and sc.sim.tick() > tick_at_pause and sc.hud.visible
		if now > 3.7 and now < 3.9:
			seen["hud off"] = not sc.hud.visible and not sc.hud.world_tags and not sc.capture.world_tags
		if now > 4.2 and now < 4.4:
			seen["let fly held"] = sc.controls.let_fly
		if now > 4.7 and now < 4.9:
			seen["helicopter"] = sc.rig.mode == CameraRig.Mode.HELICOPTER and sc.rig.helicopter.scale == 2.0
		if now > 5.2 and now < 5.4:
			seen["let fly released"] = not sc.controls.let_fly
	for k in ["long_lens", "slow", "paused", "resumed", "hud off", "let fly held", "helicopter", "let fly released"]:
		t.ok(seen.get(k, false), k)
	# 1 s at x1, 1 s at x0.5 (2 s of frames), 1 s paused, back to x1 for 3 s
	var want := int((1.0 + 2.0 + 1.0 + 3.0) * FPS)
	t.ok(sc.shot_ended and absi(frames - want) <= 1, "end after %d frames (%d wanted)" % [frames, want])
	t.near(sc.shot_time(), 6.0, 1.5 * dt, "the shot time at the end")
	sc.queue_free()
	await process_frame


func test_race_start() -> void:
	if not CoreSimSource.available():
		t.begin("race shot skipped: no GDExtension")
		return
	t.begin("a race shot from 10 s before the gun")
	var shot := ShotScript.parse(_shot([{"t": -10, "camera": "start_line"}], {"start": -10}))
	var sc := _scene(shot)
	sc.sim_kind = sc.SimKind.CORE
	sc.race_mode = true
	sc.fleet_size = 3
	sc.watch = true
	sc.racing = false
	sc.quit_at = -9.0
	root.add_child(sc)
	sc.scripted_input = RawInput.new()
	await process_frame
	t.near(sc.shot_time(), -10.0, 1e-6, "the first frame 10 s before the gun")
	sc.step_frame(1.0 / FPS)
	t.ok(sc.rig.mode == CameraRig.Mode.START_LINE, "the start line camera")
	var frames := 1
	while not sc.shot_ended and frames < 500:
		sc.step_frame(1.0 / FPS)
		frames += 1
	t.ok(sc.shot_ended and absi(frames - int(FPS)) <= 1, "--quit-at ends it after 1 s: %d frames" % frames)
	sc.queue_free()
	await process_frame
