extends SceneTree
## controls.md §8 tests (headless, scripted input, fixed frame rates), plus the input map and the input frame.
##   godot --headless --path game -s res://tests/controls_test.gd

const FPS := [30.0, 60.0, 144.0]
const P := SimSource.Phase

var t := TestLog.new()


func _init() -> void:
	test_stick_curve()
	test_hold_to_steer()
	test_sheet_keys()
	test_latching()
	test_sail_mapping()
	test_focus()
	test_last_moved()
	test_set_and_hold()
	test_auto_trim_off()
	test_free_camera_keys()
	test_input_map()
	test_input_frame()
	test_capture_state()
	test_click_or_drag()
	test_trackpad()
	await test_capture_scene_fake()
	if CoreSimSource.available():
		await test_capture_scene_race()
	else:
		t.ok(false, "the GDExtension is not loaded: the race capture test skipped")
	t.finish(self, "controls_test")


## frames of `fps` until `seconds` have passed (the first frame that reaches it)
static func frames_for(seconds: float, fps: float) -> int:
	return int(ceil(seconds * fps - 1e-6))


func run(pc: PlayerControls, r: RawInput, n: int, dt: float) -> void:
	for i in n:
		pc.update(r, dt)
		r.pressed = []


func test_stick_curve() -> void:
	t.begin("1 stick curve")
	var xs := [0.05, 0.3, 0.5, 0.95]
	var want := [0.0, 0.099, 0.299, 1.000]
	for i in 4:
		t.near(PlayerControls.stick_curve(xs[i]), want[i], 0.001, "x = %.2f" % xs[i])
		var pc := PlayerControls.new()
		var r := RawInput.new()
		r.helm_stick = xs[i]
		pc.update(r, 1.0 / 60.0)
		t.near(pc.h_cmd, want[i], 0.001, "through update x = %.2f" % xs[i])
		r.helm_stick = -xs[i]
		pc.update(r, 1.0 / 60.0)
		t.near(pc.h_cmd, -want[i], 0.001, "negative x = %.2f" % xs[i])


func test_hold_to_steer() -> void:
	t.begin("2 hold-to-steer ramp")
	for fps in FPS:
		var dt: float = 1.0 / fps
		var pc := PlayerControls.new()
		pc.helm_mode = PlayerControls.HelmMode.HOLD_TO_STEER
		var r := RawInput.new().press(&"helm_right")
		var n04 := frames_for(0.4, fps)
		run(pc, r, n04, dt)
		t.ok(absf(pc.h_cmd - 0.625) <= 0.625 * 0.005, "%d fps: 0.4 s gives %.4f, want 0.625" % [fps, pc.h_cmd])
		run(pc, r, frames_for(0.8, fps) - n04, dt)
		t.near(pc.h_cmd, 1.0, 1e-6, "%d fps: 0.8 s" % fps)
		run(pc, r, int(fps), dt)
		t.near(pc.h_cmd, 1.0, 1e-6, "%d fps: later" % fps)
		r.held.erase(&"helm_right")
		pc.update(r, dt)
		t.near(pc.h_cmd, 0.0, 1e-9, "%d fps: release gives 0 in the next frame" % fps)
		# left, and the later key wins
		r = RawInput.new().press(&"helm_left")
		run(pc, r, frames_for(0.4, fps), dt)
		t.ok(absf(pc.h_cmd + 0.625) <= 0.625 * 0.005, "%d fps: left 0.4 s gives %.4f" % [fps, pc.h_cmd])
		r.press(&"helm_right")
		pc.update(r, dt)
		t.ok(pc.h_cmd > 0.0, "%d fps: the later key wins" % fps)


func test_sheet_keys() -> void:
	t.begin("3 sheet keys")
	var dt := 1.0 / 60.0
	var pc := PlayerControls.new()
	pc.auto_trim = false
	pc.sheet_cmd = 0.5
	var r := RawInput.new().press(&"sheet_out")
	run(pc, r, 3, dt)  # 0.05 s
	t.near(pc.sheet_cmd - 0.5, 0.003, 1e-6, "a 0.05 s tap")
	r.held.erase(&"sheet_out")
	pc.update(r, dt)
	pc.sheet_cmd = 0.0
	r = RawInput.new().press(&"sheet_out")
	run(pc, r, 180, dt)
	t.near(pc.sheet_cmd, 1.0, 1e-9, "holding 3 s from 0 reaches 1")
	# about 2.7 s for the full sweep
	pc = PlayerControls.new()
	pc.auto_trim = false
	r = RawInput.new().press(&"sheet_out")
	var n := 0
	while pc.sheet_cmd < 1.0 and n < 1000:
		pc.update(r, dt)
		r.pressed = []
		n += 1
	t.near(n * dt, 2.7, 0.02, "full sweep time")
	# continuity of the rate curve: r(e) from the integral on both sides of the knees
	for e in [0.1, 1.0]:
		var h := 1e-5
		var lo := (PlayerControls.sheet_key_integral(e) - PlayerControls.sheet_key_integral(e - h)) / h
		var hi := (PlayerControls.sheet_key_integral(e + h) - PlayerControls.sheet_key_integral(e)) / h
		t.near(lo, hi, 1e-3, "rate continuous at e = %.1f" % e)
	# frame-rate independence of a hold
	var u := []
	for fps in [30.0, 60.0, 144.0]:
		pc = PlayerControls.new()
		pc.auto_trim = false
		r = RawInput.new().press(&"sheet_in")
		pc.sheet_cmd = 1.0
		run(pc, r, int(fps * 1.5), 1.0 / fps)
		u.append(pc.sheet_cmd)
	t.near(u[0], u[2], 1e-6, "1.5 s hold equal at 30 and 144 fps")
	# ignored while auto-trim is on, with the option off (controls.md §5.3; on by default, test_auto_trim_off)
	pc = PlayerControls.new()
	pc.sheet_turns_auto_trim_off = false
	pc.sheet_cmd = 0.3
	run(pc, RawInput.new().press(&"sheet_out"), 30, dt)
	t.near(pc.sheet_cmd, 0.3, 1e-9, "ignored with auto-trim on")


func _sim() -> FakeSim:
	var sim := FakeSim.new()
	sim.add_boat("wm7", 0, 0, deg_to_rad(300), 3.0)
	return sim


func test_latching() -> void:
	t.begin("4 latching")
	var sim := _sim()
	var pc := PlayerControls.new()
	pc.bind(sim, 0)
	var runner := SimRunner.new(sim, pc)
	runner.keep_frames = 16
	var dt := 1.0 / 60.0
	var info := sim.class_info(0)
	var kite: int = info.sails.find_custom(func(s): return s.name == "kite")
	var jib: int = info.sails.find_custom(func(s): return s.name == "jib")
	t.ok(sim.sails(0).front == jib and not sim.sails(0).busy(), "starts idle with the jib up")
	var r := RawInput.new()
	# both presses land inside one tick (frames 1 and 2 of a 3-frame tick)
	var presses := {1: &"sail_2", 2: &"sail_1"}
	for i in 12:
		r = RawInput.new()
		if presses.has(i):
			r.press(presses[i])
		pc.update(r, dt)
		runner.advance(dt)
	var reqs: Array = runner.frames.map(func(f): return f.sail_req)
	var first := reqs.find(InputFrame.hoist_req(kite))
	t.ok(first >= 0, "the first press is sent: %s" % [reqs])
	t.ok(first >= 0 and first + 1 < reqs.size() and reqs[first + 1] == InputFrame.hoist_req(jib),
		"the second one in the frame after (hoist(F) cancels): %s" % [reqs])
	t.ok(reqs.count(InputFrame.SAIL_NONE) == reqs.size() - 2, "nothing else is sent")


func _view(front: int, steps: Array, pos := 0, progress := 0.3) -> SimSource.SailsView:
	var v := SimSource.SailsView.new()
	v.front = front
	for s in steps:
		v.queue.append(SimSource.SailStep.new(s[0], s[1], s.size() > 2 and s[2]))
	v.queue_len = v.queue.size()
	v.queue_pos = pos
	for i in 3:
		var st := SimSource.SailState.new()
		st.progress = progress
		v.sails.append(st)
		v.out.append(SimSource.SailOutput.new())
	return v


func test_sail_mapping() -> void:
	t.begin("5 sail mapping")
	var info := _sim().class_info(0)  # main 0, jib 1 (slot 0), kite 2 (slot 1)
	var J := 1
	var K := 2
	var sj := 0
	var sk := 1
	var hj := InputFrame.hoist_req(J)
	var hk := InputFrame.hoist_req(K)
	var drop := InputFrame.SAIL_DROP_FRONT
	var none := InputFrame.SAIL_NONE
	var idle := _view(J, [])
	t.ok(SailRequests.map(sk, idle, info) == hk, "idle, slot X != F: hoist(X)")
	t.ok(SailRequests.map(sj, idle, info) == drop, "idle, slot F: drop_front()")
	var peel := [[K, P.PREPARE_HOIST], [K, P.HOISTING], [K, P.UP], [J, P.PREPARE_DROP], [J, P.DROPPING], [J, P.DOWN]]
	for pos in [0, 1]:
		var v := _view(J, peel, pos)
		t.ok(SailRequests.map(sj, v, info) == hj, "peel (step %d), slot F: hoist(F)" % pos)
		t.ok(SailRequests.map(sk, v, info) == hj, "peel (step %d), slot S: hoist(F)" % pos)
	for pos in [0, 1]:
		var v := _view(J, [[J, P.PREPARE_DROP], [J, P.DROPPING], [J, P.DOWN]], pos)
		t.ok(SailRequests.map(sj, v, info) == hj, "lone drop of S (step %d), slot S: hoist(S)" % pos)
		t.ok(SailRequests.map(sk, v, info) == none, "lone drop, another slot: nothing")
		t.ok(SailRequests.map(SailRequests.DROP, v, info) == none, "lone drop, drop_front: nothing")
	t.ok(SailRequests.map(SailRequests.DROP, idle, info) == drop, "drop_front, idle, F >= 0")
	t.ok(SailRequests.map(SailRequests.DROP, _view(-1, []), info) == none, "drop_front, idle, nothing up")
	t.ok(SailRequests.map(sj, _view(-1, []), info) == hj, "idle, nothing up, slot X: hoist(X)")
	# the first hoist (nothing up) is cancelled by its own slot or drop_front (sails.md §4.2)
	var first := _view(-1, [[K, P.PREPARE_HOIST], [K, P.HOISTING], [K, P.UP]], 1)
	t.ok(SailRequests.map(sk, first, info) == drop, "first hoist, slot S: drop_front() cancels")
	t.ok(SailRequests.map(SailRequests.DROP, first, info) == drop, "first hoist, drop_front: cancels")
	t.ok(SailRequests.map(sj, first, info) == none, "first hoist, another slot: nothing")
	# busy, matching no row
	var late := _view(K, peel, 3)  # the old jib coming down after the kite is up
	t.ok(SailRequests.map(sj, late, info) == none, "peel after the up step, old slot: nothing")
	t.ok(SailRequests.map(sk, late, info) == none, "peel after the up step, slot F: nothing")
	t.ok(SailRequests.map(SailRequests.DROP, late, info) == none, "busy, drop_front: nothing")
	var rev := _view(J, [[K, P.HOISTING, true], [K, P.DOWN]], 0)
	t.ok(SailRequests.map(sk, rev, info) == none, "a cancelled hoist coming down: nothing")
	# every mapped request is accepted by the sim in that state
	var sim := _sim()
	var b := sim.boats[0]
	t.ok(sim.apply_input(0, _frame(SailRequests.map(sk, sim.sails(0), info))) == SimSource.Request.ACCEPTED,
		"sim accepts hoist(kite)")
	for i in 20:
		sim.step()
	t.ok(b.busy() and b.queue[b.queue_pos].sail == K, "the kite is going up")
	t.ok(sim.apply_input(0, _frame(SailRequests.map(sk, sim.sails(0), info))) == SimSource.Request.ACCEPTED,
		"sim accepts the cancel from slot S")
	# the HUD flash on a press that matches no row
	var pc := PlayerControls.new()
	pc.bind(sim, 0)
	pc.update(RawInput.new().press(&"sail_1"), 0.016)
	var f := pc.stamp(sim.tick())
	t.ok(f.sail_req == none and pc.busy_flash, "busy press: nothing sent, HUD flashes")
	t.ok(pc.sail_pressed, "a sail key tells the HUD (the sail strip shows, hud.md §5.3)")
	pc.sail_pressed = false
	pc.update(RawInput.new().press(&"sail_next"), 0.016)
	t.ok(pc.sail_pressed and pc.sail_highlight >= 0, "a pad sail step too (highlight %d)" % pc.sail_highlight)
	pc.sail_pressed = false
	pc.update(RawInput.new().press(&"let_fly"), 0.016)
	t.ok(not pc.sail_pressed, "other keys do not")


func _frame(req: int) -> InputFrame:
	var f := InputFrame.new()
	f.sail_req = req
	f.flags = InputFrame.FLAG_AUTO_TRIM
	return f


func test_focus() -> void:
	t.begin("6 focus")
	var pc := PlayerControls.new()
	var dt := 1.0 / 60.0
	var r := RawInput.new().press(&"let_fly")
	pc.update(r, dt)
	t.ok(pc.stamp(0).let_fly(), "let-fly held sets the flag")
	pc.set_text_focus(true)
	r.pressed = []
	r.helm_stick = 0.5
	pc.update(r, dt)
	t.ok(not pc.stamp(1).let_fly(), "opening chat clears let_fly in the next stamped frame")
	t.near(pc.h_cmd, 0.299, 0.001, "sticks keep working under chat focus")
	pc.set_text_focus(false)
	r.helm_stick = 0.0
	pc.update(r, dt)
	t.ok(pc.stamp(2).let_fly(), "closing chat: the held key counts again")
	pc.set_window_focus(false)
	pc.update(r, dt)
	t.ok(not pc.stamp(3).let_fly(), "window focus lost clears held states")
	pc.set_window_focus(true)
	# toggle option: one press sets, the next clears
	pc = PlayerControls.new()
	pc.let_fly_toggle = true
	pc.update(RawInput.new().press(&"let_fly"), dt)
	pc.update(RawInput.new(), dt)
	t.ok(pc.let_fly, "toggle: set by one press")
	pc.update(RawInput.new().press(&"let_fly"), dt)
	t.ok(not pc.let_fly, "toggle: cleared by the next")
	# pause menu online: last helm kept, held let-fly released
	pc = PlayerControls.new()
	run(pc, RawInput.new().press(&"helm_right").hold(&"let_fly"), 30, dt)
	var h := pc.h_cmd
	pc.menu_open = true
	pc.update(RawInput.new().hold(&"helm_right").hold(&"let_fly"), dt)
	t.ok(pc.h_cmd == h and not pc.let_fly, "menu: helm kept, let-fly released")


func test_last_moved() -> void:
	t.begin("7 last-moved source")
	var dt := 1.0 / 60.0
	var pc := PlayerControls.new()
	var r := RawInput.new().press(&"helm_right")
	run(pc, r, 20, dt)
	t.ok(pc.h_cmd > 0.1 and pc.helm_source == PlayerControls.Source.KEYS, "keys steer")
	r.helm_stick = -0.5
	pc.update(r, dt)
	t.near(pc.h_cmd, -0.299, 0.001, "a stick outside its dead zone overrides held keys")
	r.helm_stick = 0.05
	run(pc, r, 20, dt)  # 0.33 s inside the dead zone
	t.near(pc.h_cmd, 0.0, 1e-9, "stick in the dead zone under 0.5 s: centred stick, centred helm")
	t.ok(pc.helm_source == PlayerControls.Source.STICK, "still the stick")
	run(pc, r, 11, dt)  # 0.52 s
	t.ok(pc.helm_source == PlayerControls.Source.KEYS and pc.h_cmd > 0.0, "after 0.5 s the held keys take over")
	r.helm_stick = 0.3
	pc.update(r, dt)
	t.near(pc.h_cmd, 0.099, 0.001, "moving the stick takes it back")


func test_set_and_hold() -> void:
	t.begin("8 set and hold")
	var rate := PlayerControls.KEY_RATE
	for fps in FPS:
		var dt: float = 1.0 / fps
		var pc := PlayerControls.new()
		t.ok(pc.helm_mode == PlayerControls.HelmMode.SET_AND_HOLD, "default mode")
		# a held key moves the helm linearly at 0.85 per second, no ramp
		var r := RawInput.new().press(&"helm_right")
		run(pc, r, frames_for(1.0 / 6.0, fps), dt)
		t.ok(absf(pc.h_cmd - 0.141667) <= 0.141667 * 0.005, "%d fps: 1/6 s gives %.4f" % [fps, pc.h_cmd])
		pc = PlayerControls.new()
		r = RawInput.new().press(&"helm_right")
		run(pc, r, frames_for(0.5, fps), dt)
		t.ok(absf(pc.h_cmd - 0.425) <= 0.425 * 0.005, "%d fps: 0.5 s gives %.4f" % [fps, pc.h_cmd])
		r.held.erase(&"helm_right")
		run(pc, r, int(fps), dt)
		t.ok(absf(pc.h_cmd - 0.425) <= 0.425 * 0.005, "%d fps: stays after release" % fps)
		# centring eases back at the same rate: 0.425 takes 0.5 s, and the helm is not snapped
		pc.update(RawInput.new().press(&"helm_centre"), dt)
		t.ok(pc.h_cmd >= 0.425 - rate * dt - 1e-4, "%d fps: helm_centre does not snap the helm (%.4f)" % [fps, pc.h_cmd])
		run(pc, RawInput.new(), frames_for(1.0 / 3.0, fps) - 1, dt)
		t.ok(absf(pc.h_cmd - 0.141667) <= 0.002, "%d fps: 1/3 s after centring %.4f" % [fps, pc.h_cmd])
		run(pc, RawInput.new(), frames_for(1.0 / 6.0, fps), dt)
		t.near(pc.h_cmd, 0.0, 1e-4, "%d fps: centred 0.5 s after helm_centre" % fps)
		# held long: full helm from the centre in about 1.18 s
		run(pc, RawInput.new().press(&"helm_left"), frames_for(1.0, fps), dt)
		t.ok(absf(pc.h_cmd + 0.85) <= 0.85 * 0.005, "%d fps: 1 s gives %.4f" % [fps, pc.h_cmd])
		run(pc, RawInput.new().hold(&"helm_left"), frames_for(0.2, fps), dt)
		t.near(pc.h_cmd, -1.0, 1e-9, "%d fps: full helm by 1.2 s" % fps)
		# a helm key during the easing takes over at once
		pc.update(RawInput.new().press(&"helm_centre"), dt)
		run(pc, RawInput.new(), frames_for(0.2, fps), dt)
		var mid := pc.h_cmd
		pc.update(RawInput.new().press(&"helm_left"), dt)
		t.ok(pc.h_cmd < mid, "%d fps: a key stops the centring" % fps)
		run(pc, RawInput.new(), frames_for(0.5, fps), dt)
		t.ok(pc.h_cmd < mid, "%d fps: and the helm stays where the key left it" % fps)
		# helm_fine: a third of the rate
		pc = PlayerControls.new()
		run(pc, RawInput.new().press(&"helm_right").hold(&"helm_fine"), frames_for(0.5, fps), dt)
		t.ok(absf(pc.h_cmd - 0.141667) <= 0.141667 * 0.005, "%d fps: fine 0.5 s gives %.4f" % [fps, pc.h_cmd])


func test_auto_trim_off() -> void:
	t.begin("auto-trim off starts from the present trim")
	var sim := _sim()
	for i in 40:
		sim.step()
	var pc := PlayerControls.new()
	pc.bind(sim, 0)
	pc.update(RawInput.new().press(&"auto_trim"), 0.016)
	t.ok(not pc.auto_trim, "switched off")
	var eps_before := sim.sails(0).out[1].trim_error
	var f := pc.stamp(sim.tick())
	sim.apply_input(0, f)
	for i in 20:
		sim.step()
	t.ok(absf(sim.sails(0).out[1].trim_error - eps_before) < deg_to_rad(1.0),
		"no jump in the jib trim (%.2f deg)" % rad_to_deg(sim.sails(0).out[1].trim_error))
	pc.auto_trim_allowed = false
	pc.update(RawInput.new().press(&"auto_trim"), 0.016)
	t.ok(not pc.auto_trim and pc.messages.size() == 1, "refused with a message when the lobby forbids it")
	t.ok(not pc.messages[0].contains("—"), "message has no em dash")
	# the option (controls.md §5.3, default on): a sheet key while AUTO shows hands the trim over, with a note
	var pd := PlayerControls.new()
	pd.bind(sim, 0)
	pd.auto_trim = true
	t.ok(pd.sheet_turns_auto_trim_off, "sheet turns auto trim off by default")
	pd.update(RawInput.new().hold(&"sheet_out"), 0.016)
	t.ok(not pd.auto_trim, "a sheet key while auto trim is on switches it off")
	t.ok(pd.messages.size() == 1 and pd.messages[0].begins_with("Auto trim off: ")
		and pd.messages[0].ends_with(" turns it back on") and not pd.messages[0].contains("—"),
		"with a note naming the key: %s" % (pd.messages[0] if not pd.messages.is_empty() else ""))
	pd.messages.clear()
	pd.update(RawInput.new().hold(&"sheet_out"), 0.016)
	t.ok(pd.messages.is_empty(), "no second note while it stays off")
	var pe := PlayerControls.new()
	pe.bind(sim, 0)
	pe.auto_trim = true
	pe.sheet_turns_auto_trim_off = false
	pe.update(RawInput.new().hold(&"sheet_out"), 0.016)
	t.ok(pe.auto_trim and pe.messages.is_empty(), "option off: the key is ignored, AUTO stays")


func test_free_camera_keys() -> void:
	t.begin("free camera takes the boat keys")
	var dt := 1.0 / 60.0
	var pc := PlayerControls.new()
	run(pc, RawInput.new().press(&"helm_right"), 30, dt)
	var h := pc.h_cmd
	pc.free_camera = true
	var r := RawInput.new().hold(&"helm_right").hold(&"sheet_in")
	run(pc, r, 30, dt)
	t.near(pc.h_cmd, h, 1e-9, "the boat keeps its last helm")
	var c := CameraInput.from_raw(r, true)
	t.ok(c.move.x == 1.0 and c.move.z == 1.0, "helm keys strafe, sheet_in flies forward")
	pc = PlayerControls.new()
	pc.helm_mode = PlayerControls.HelmMode.HOLD_TO_STEER
	run(pc, RawInput.new().press(&"helm_right"), 10, dt)
	pc.free_camera = true
	pc.update(RawInput.new().hold(&"helm_right"), dt)
	t.near(pc.h_cmd, 0.0, 1e-9, "a hold-to-steer key counts as released")
	# presets: F1 recalls 1, Shift+F1 recalls 5, Ctrl+F1 stores 1
	var k := RawInput.new().press(&"camera_preset_1")
	t.ok(CameraInput.from_raw(k, false).preset_recall == 0, "F1 recalls slot 1")
	k = RawInput.new().press(&"camera_preset_1").press(&"camera_preset_5").hold(&"helm_fine")
	t.ok(CameraInput.from_raw(k, false).preset_recall == 4, "Shift+F1 recalls slot 5")
	k = RawInput.new().press(&"camera_preset_1").hold(&"camera_preset_store")
	var ck := CameraInput.from_raw(k, false)
	t.ok(ck.preset_store == 0 and ck.preset_recall == -1, "Ctrl+F1 stores slot 1")
	k = RawInput.new().hold(&"camera_zoom_in").hold(&"helm_fine")
	k.gamepad = true
	t.ok(CameraInput.from_raw(k, false).zoom_held == -1.0, "gamepad RB + LB zooms out")


func test_input_map() -> void:
	t.begin("input map")
	var table := DefaultBindings.table()
	for action in table:
		var key: String = "input/" + action
		if not t.ok(ProjectSettings.has_setting(key), "project.godot has %s" % action):
			continue
		var d: Dictionary = ProjectSettings.get_setting(key)
		var want := DefaultBindings.events(table[action])
		var have: Array = d["events"]
		var same := have.size() == want.size()
		for i in mini(have.size(), want.size()):
			same = same and have[i].as_text() == want[i].as_text() and have[i].device == want[i].device
		t.ok(same, "%s matches the defaults (run scripts/controls/write_input_map.gd)" % action)
	var spec := ["helm_left", "helm_right", "helm_centre", "helm_fine", "sheet_in", "sheet_out", "let_fly",
		"auto_trim", "sail_1", "sail_9", "sail_prev", "sail_next", "sail_set", "drop_front", "hail", "protest",
		"camera_next", "camera_chase", "camera_onboard", "camera_aerial", "camera_free", "camera_zoom_in",
		"camera_zoom_out", "camera_recentre", "camera_preset_1", "camera_preset_8", "camera_boost", "rankings",
		"map", "radar_zoom_in", "radar_zoom_out", "radar_orientation", "hud_hide",
		"boat_names", "world_tags", "capture_pause", "capture_slow", "camera_clip", "hud_density", "boat_select", "boat_pick", "rankings_pad", "spectate_next", "spectate_prev", "spectate_leader", "chat", "pause_menu", "screenshot",
		"helm_stick_left", "helm_stick_right", "sheet_in_trigger", "sheet_out_trigger", "camera_orbit_left",
		"camera_orbit_drag", "camera_look_up"]
	for a in spec:
		t.ok(InputMap.has_action(a), "InputMap has %s" % a)
	# WM-214, WM-215, WM-208: no wind shadow view key (not built); D-pad up opens the course map; hail and protest
	# keep their keys, lose the pad button and leave the Bindings list until online play exists
	t.ok(not InputMap.has_action(&"wind_shadow_view") and not table.has("wind_shadow_view"), "V is not bound")
	var dpad_up := Bindings.decode(["button", JOY_BUTTON_DPAD_UP])
	t.ok(InputMap.action_has_event(&"map", dpad_up), "the map has D-pad up")
	t.ok(not InputMap.action_has_event(&"hail", dpad_up) and not InputMap.action_has_event(&"protest", dpad_up),
		"hail and protest have no pad button")
	t.ok(InputMap.action_has_event(&"hail", Bindings.decode(["key", KEY_H, ""]))
		and InputMap.action_has_event(&"protest", Bindings.decode(["key", KEY_P, ""])), "H and P kept")
	t.ok(not Bindings.online_play and not Bindings.actions().has("hail") and not Bindings.actions().has("protest")
		and Bindings.actions().has("map"), "offline: hail and protest not listed")
	Bindings.online_play = true
	t.ok(Bindings.actions().has("hail") and Bindings.actions().has("protest"), "online: listed")
	Bindings.online_play = false
	t.ok(not Bindings.actions().has("hail"), "the list follows the switch back")
	t.ok(Bindings.all_conflicts().is_empty(), "the defaults have no conflicts")
	# controls.md §3 Prompts: the binding on the device used last, the other device's when that has none
	t.ok(Bindings.prompt(&"map", "", false) == "M" and Bindings.prompt(&"map", "", true) == "D-pad up",
		"map: M on the keys, D-pad up on the pad")
	t.ok(Bindings.prompt(&"auto_trim", "", true) == "D-pad down" and Bindings.prompt(&"hail", "", true) == "H",
		"auto trim on the pad: D-pad down; hail has no pad button: H")
	t.ok(Bindings.prompt(&"sail_set", "", false) == "X" and Bindings.prompt(&"no_such", "x") == "x",
		"no key for sail set: the pad's X; no action: the fallback")
	Bindings.pad_last = true
	t.ok(PlayerControls.key_text(&"auto_trim", "") == "D-pad down", "a note follows the pad")
	Bindings.pad_last = false
	t.ok(PlayerControls.key_text(&"auto_trim", "") == "T", "and the keyboard")
	Bindings.set_slot("auto_trim", 0, ["key", KEY_Y, ""])
	t.ok(PlayerControls.key_text(&"auto_trim", "") == "Y", "and a rebinding")
	DefaultBindings.apply_to_input_map()
	# a scripted key press through the live InputMap reaches the reader
	var reader := InputReader.new()
	root.add_child(reader)
	Input.action_press(&"let_fly")
	var r := reader.read()
	t.ok(r.is_held(&"let_fly"), "reader sees a held action")
	Input.action_release(&"let_fly")
	reader.queue_free()


func test_input_frame() -> void:
	t.begin("input frame")
	var f := InputFrame.new()
	f.h_cmd = -0.5
	f.sheet_cmd = 0.25
	f.sail_req = 3
	f.flags = InputFrame.FLAG_LET_FLY | InputFrame.FLAG_PROTEST
	var b := f.encode()
	t.ok(b.size() == 6, "6 bytes")
	var g := InputFrame.decode(b)
	t.near(g.h_cmd, -0.5, 1.0 / 32767.0, "h_cmd round trip")
	t.near(g.sheet_cmd, 0.25, 1.0 / 65535.0, "sheet_cmd round trip")
	t.ok(g.sail_req == 3 and g.flags == f.flags, "sail_req and flags round trip")
	var pc := PlayerControls.new()
	pc.h_cmd = 1.7
	pc.sheet_cmd = -0.2
	var s := pc.stamp(9)
	t.ok(s.h_cmd == 1.0 and s.sheet_cmd == 0.0 and s.tick == 9, "commands clamped before stamping")
	# one frame per 50 ms tick at any frame rate
	for fps in FPS:
		var sim := _sim()
		var pcs := PlayerControls.new()
		pcs.bind(sim, 0)
		var runner := SimRunner.new(sim, pcs)
		for i in int(fps * 2.0):
			pcs.update(RawInput.new(), 1.0 / fps)
			runner.advance(1.0 / fps)
		t.ok(absi(sim.tick() - 40) <= 1, "%d fps: 2 s gives 40 ticks (%d)" % [fps, sim.tick()])


func test_capture_state() -> void:
	t.begin("9 capture state")
	var cm := CaptureMode.new()
	t.ok(not cm.frozen and cm.rate() == 1.0 and cm.world_tags, "starts running at x1 with the world tags shown")
	cm.handle(RawInput.new().press(&"capture_pause"))
	t.ok(cm.frozen and cm.sim_dt(0.1) == 0.0, "clean pause: no simulation time")
	cm.handle(RawInput.new().press(&"capture_pause"))
	t.ok(not cm.frozen and cm.sim_dt(0.1) == 0.1, "again: running")
	var rates := []
	for i in 3:
		cm.handle(RawInput.new().press(&"capture_slow"))
		rates.append(cm.rate())
	t.ok(rates == [0.5, 0.25, 1.0], "slow motion cycles 0.5, 0.25, 1: %s" % [rates])
	cm.handle(RawInput.new().press(&"capture_slow"))
	t.near(cm.sim_dt(0.1), 0.05, 1e-9, "x0.5 halves the simulation time")
	t.ok(cm.handle(RawInput.new().press(&"world_tags")) and not cm.world_tags, "world_tags toggles off")
	cm.handle(RawInput.new().press(&"capture_pause"))
	cm.reset()
	t.ok(not cm.frozen and cm.rate() == 1.0 and not cm.world_tags, "reset: running at x1, world tags choice kept")
	var on := CaptureMode.new()
	on.allowed = false
	on.handle(RawInput.new().press(&"capture_pause").press(&"capture_slow"))
	t.ok(not on.frozen and on.rate() == 1.0 and on.sim_dt(0.1) == 0.1, "online: the capture actions change nothing")
	t.ok(on.handle(RawInput.new().press(&"world_tags")) and not on.world_tags, "online: world_tags still toggles")
	t.ok(on.note == "", "online: no rate note")
	test_capture_note()


## hud.md §16.6: the rate note says the new rate, lasts 1.5 s of frame time, fades over its last 0.4 s, and the
## clean pause and a restart show none.
func test_capture_note() -> void:
	t.begin("9 capture rate note")
	var cm := CaptureMode.new()
	cm.handle(RawInput.new().press(&"capture_pause"))
	t.ok(cm.note == "" and cm.note_alpha() == 0.0, "the clean pause shows no note")
	var notes := []
	for i in 3:
		cm.handle(RawInput.new().press(&"capture_slow"))
		notes.append(cm.note)
		cm.frame(0.1)
	t.ok(notes == ["Slow motion x0.5", "Slow motion x0.25", "Normal speed"], "a note per rate: %s" % [notes])
	cm.handle(RawInput.new().press(&"capture_slow"))
	t.ok(cm.note == "Slow motion x0.5" and cm.note_alpha() == 1.0, "a new press restarts the note, opaque")
	for i in 66:  # 1.1 s at 60 fps
		cm.frame(1.0 / 60.0)
	t.near(cm.note_alpha(), 1.0, 1e-6, "still opaque at 1.1 s")
	for i in 12:  # 1.3 s
		cm.frame(1.0 / 60.0)
	t.near(cm.note_alpha(), 0.5, 1e-3, "fading: half at 1.3 s")
	for i in 13:  # 1.517 s
		cm.frame(1.0 / 60.0)
	t.ok(cm.note == "" and cm.note_alpha() == 0.0, "gone after 1.5 s (in a clean pause too)")
	cm.handle(RawInput.new().press(&"capture_slow"))
	cm.reset()
	t.ok(cm.note == "" and cm.note_alpha() == 0.0, "a restart clears the note")


## controls.md §3 click or drag, §8 test 10: the pick button released within 8 px is a click at its point; moved
## further it drags the camera by the motion past the 8 px and picks nothing
func test_click_or_drag() -> void:
	t.begin("10 click or drag (InputReader)")
	var rd := InputReader.new()
	rd.pointer_press(Vector2(100, 100))
	rd.pointer_move(Vector2(103, 100), Vector2(3, 0))
	rd.pointer_release(Vector2(103, 100))
	var r := rd.read()
	t.ok(r.was_pressed(&"boat_pick") and r.pointer == Vector2(103, 100), "3 px of motion: a click at its point")
	t.ok(r.mouse_drag == Vector2.ZERO and not r.pointer_drag and not CameraInput.from_raw(r, false).dragging,
		"the click orbits nothing")
	t.ok(not rd.read().was_pressed(&"boat_pick"), "one pick per click")
	rd.pointer_press(Vector2(200, 200))
	for i in 4:
		rd.pointer_move(Vector2(200 + 5 * (i + 1), 200), Vector2(5, 0))
	r = rd.read()
	var cin := CameraInput.from_raw(r, false)
	t.ok(r.pointer_drag and cin.dragging, "dragged 20 px: a camera drag")
	t.near(r.mouse_drag.x, 12.0, 1e-4, "the camera gets the motion past the 8 px")
	rd.pointer_move(Vector2(230, 200), Vector2(10, 0))
	rd.pointer_release(Vector2(230, 200))
	r = rd.read()
	t.ok(not r.was_pressed(&"boat_pick") and r.mouse_drag.x == 10.0, "the drag picks nothing on release")
	t.ok(not rd.read().pointer_drag, "and ends with the release")
	rd.pointer_move(Vector2(300, 300), Vector2(9, 9))
	t.ok(rd.read().mouse_drag == Vector2.ZERO, "motion without a press is no drag")
	rd.free()


## controls.md §3 Trackpad, §4, §8 test 11: a pan gesture zooms by fractional notches (vertical) or drags
## (horizontal), one axis per gesture; a pinch zooms by its factor; the wheel keeps one notch per click
func test_trackpad() -> void:
	t.begin("11 trackpad gestures (InputReader)")
	var rd := InputReader.new()
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(0, 1.2)  # two fingers up with natural scrolling: a wheel down
	rd._input(pan)
	var r := rd.read()
	t.near(r.pan.y, 1.2, 1e-6, "the pan gesture reaches the frame")
	var cin := CameraInput.from_raw(r, false)
	t.near(cin.zoom_notches, -2.0, 1e-6, "a pan of 1.2 down is -2 notches (zoom out)")
	t.ok(not cin.dragging and cin.mouse == Vector2.ZERO, "and no drag")
	var chase := ChaseCamera.new()
	var o := CamTypes.Options.new()
	var r0 := chase.R
	chase.handle_input(cin, o, 1.0 / 60.0)
	t.near(chase.R, r0 * ChaseCamera.NOTCH * ChaseCamera.NOTCH, 1e-6, "the chase camera zooms out by x1.12^2")
	pan.delta = Vector2(0, -1.2)
	rd._input(pan)
	chase.handle_input(CameraInput.from_raw(rd.read(), false), o, 1.0 / 60.0)
	t.near(chase.R, r0, 1e-6, "a pan up zooms in by the same")
	t.ok(rd.read().pan == Vector2.ZERO, "read drains the pan")
	# pinch
	var mag := InputEventMagnifyGesture.new()
	mag.factor = 1.25
	rd._input(mag)
	r = rd.read()
	t.near(r.magnify, 1.25, 1e-9, "the magnify gesture reaches the frame")
	chase.handle_input(CameraInput.from_raw(r, false), o, 1.0 / 60.0)
	t.near(chase.R, r0 / 1.25, 1e-6, "fingers apart: zoom in by the factor")
	mag.factor = 0.8
	rd._input(mag)
	chase.handle_input(CameraInput.from_raw(rd.read(), false), o, 1.0 / 60.0)
	t.near(chase.R, r0, 1e-6, "fingers together: zoom out by the factor")
	t.near(rd.read().magnify, 1.0, 1e-9, "read drains the pinch")
	# a horizontal pan is a drag
	rd.pan_gesture(Vector2(3, 0), 10.0)
	cin = CameraInput.from_raw(rd.read(), false)
	t.ok(cin.dragging, "a horizontal pan drags")
	t.near(cin.mouse.x, 100.0, 1e-6, "3 of delta is 100 px of drag")
	t.near(cin.zoom_notches, 0.0, 1e-9, "and zooms nothing")
	var az0 := chase.az
	chase.handle_input(cin, o, 1.0 / 60.0)
	t.near(chase.az - az0, 100.0 * ChaseCamera.MOUSE_RATE, 1e-9, "the chase camera orbits as a mouse drag")
	# one axis per gesture, kept through its glide
	rd.pan_gesture(Vector2(1, 10), 20.0)
	rd.pan_gesture(Vector2(10, 1), 20.1)
	r = rd.read()
	t.ok(r.pan == Vector2(0, 11), "a gesture that starts vertical keeps its axis: %s" % r.pan)
	rd.pan_gesture(Vector2(10, 1), 20.5)
	r = rd.read()
	t.ok(r.pan == Vector2(10, 0), "after 0.3 s of quiet a horizontal gesture starts: %s" % r.pan)
	# the wheel is unchanged: one notch per click, whatever its factor
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.factor = 0.3
	rd._input(wheel)
	wheel.pressed = false
	rd._input(wheel)
	t.near(rd.read().wheel, -1.0, 1e-9, "a wheel click of factor 0.3 is still one notch")
	# chat focus drops the gestures of the frame as it drops the wheel
	rd.pan_gesture(Vector2(0, 2), 30.0)
	rd.magnify_gesture(1.5)
	var quiet := rd.read().without_buttons()
	t.ok(quiet.pan == Vector2.ZERO and quiet.magnify == 1.0 and quiet.wheel == 0.0, "chat focus: no gestures")
	rd.free()


## one frame of the scene with `actions` pressed (and `held` held)
func _frame_with(sc: Node, actions: Array = [], held: Array = [], dt := 1.0 / 60.0) -> void:
	var r := RawInput.new()
	for a in held:
		r.hold(a)
	for a in actions:
		r.press(a)
	sc.scripted_input = r
	sc.step_frame(dt)
	sc.scripted_input = RawInput.new()


## ticks stepped over `seconds` of frames at 60 fps
func _ticks_over(sc: Node, seconds: float) -> int:
	var t0: int = sc.sim.tick()
	for i in int(round(seconds * 60.0)):
		_frame_with(sc)
	return sc.sim.tick() - t0


func test_capture_scene_fake() -> void:
	t.begin("9 capture in the sail scene (FakeSim): clean pause, slow motion, online")
	var sc: Node = (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	sc.auto_process = false
	sc.sim_kind = sc.SimKind.FAKE
	sc.with_pause_menu = false
	sc.apply_settings = false
	root.add_child(sc)
	await process_frame
	sc.add_child(preload("res://scenes/menu/pause_menu.tscn").instantiate())
	var pm := sc.get_node("PauseMenu") as PauseMenu
	pm.act = false
	await process_frame
	t.ok(_ticks_over(sc, 1.0) >= 19, "running")
	# controls.md §7: without the capture preset (or a shot script) the capture keys do nothing
	_frame_with(sc, [&"capture_pause", &"capture_slow"])
	t.ok(_ticks_over(sc, 1.0) >= 19 and sc.capture.rate() == 1.0 and not sc.capture.frozen,
		"without the capture preset the capture keys do nothing")
	sc.capture_keys = true
	_frame_with(sc, [&"capture_pause"])
	await process_frame
	var tick0: int = sc.sim.tick()
	var az0: float = sc.rig.chase.az
	for i in 60:
		_frame_with(sc, [], [&"camera_orbit_right"])
	await process_frame
	var label := sc.get_node("HudLayer/Paused") as CanvasItem
	t.ok(sc.sim.tick() == tick0, "clean pause: no ticks")
	t.ok(not pm.is_open and not label.visible and not sc.runner.paused, "no menu, no Paused label")
	t.ok(absf(Frames.wrap_pi(sc.rig.chase.az - az0)) > deg_to_rad(100.0), "the camera still orbits")
	t.ok(sc.audio.paused, "the audio ducks")
	_frame_with(sc, [&"capture_pause"])
	t.ok(sc.sim.tick() == tick0 + 1 or sc.sim.tick() == tick0, "continues from the same tick")
	t.ok(_ticks_over(sc, 1.0) >= 19, "running again")
	var note := sc.get_node("HudLayer/RateNote") as Label
	t.ok(not note.visible, "no rate note in the clean pause or running")
	_frame_with(sc, [&"capture_slow"])
	t.ok(note.visible and note.text == "Slow motion x0.5" and note.size.x > 0.0 and note.modulate.a == 1.0,
		"capture_slow shows the rate note: %s" % note.text)
	var n05 := _ticks_over(sc, 2.0)
	t.ok(not note.visible, "the rate note is gone after the 2 s of frames")
	t.ok(absi(n05 - 20) <= 1, "x0.5: 2 s of frames step %d ticks (20)" % n05)
	_frame_with(sc, [&"capture_slow"])
	var n025 := _ticks_over(sc, 2.0)
	t.ok(absi(n025 - 10) <= 1, "x0.25: 2 s of frames step %d ticks (10)" % n025)
	_frame_with(sc, [&"capture_slow"])
	var n1 := _ticks_over(sc, 2.0)
	t.ok(absi(n1 - 40) <= 1, "x1 again: %d ticks (40)" % n1)
	t.ok(not note.visible, "the rate note expired")
	# with the HUD hidden the note still shows, then goes away
	_frame_with(sc, [&"hud_hide"])
	_frame_with(sc, [&"capture_slow"])
	t.ok(not sc.hud.visible and note.visible and note.text == "Slow motion x0.5", "the rate note shows with the HUD hidden")
	var gone_at := -1
	for i in 120:
		_frame_with(sc)
		if not note.visible and gone_at < 0:
			gone_at = i + 1
	t.ok(gone_at >= 88 and gone_at <= 92, "gone after 1.5 s of frames (%d frames at 60 fps)" % gone_at)
	_frame_with(sc, [&"hud_hide"])
	_frame_with(sc, [&"capture_slow"])
	sc.reset_boat()
	t.ok(sc.capture.rate() == 1.0, "a restart sets the rate back to x1")
	_frame_with(sc)
	t.ok(not note.visible, "a restart clears the rate note")
	# the pause menu over a clean pause, then back to the clean pause
	_frame_with(sc, [&"capture_pause"])
	_frame_with(sc, [&"pause_menu"])
	await process_frame
	t.ok(pm.is_open, "pause_menu opens the menu over a clean pause")
	_frame_with(sc, [&"pause_menu"])
	await process_frame
	tick0 = sc.sim.tick()
	_ticks_over(sc, 0.5)
	t.ok(not pm.is_open and sc.sim.tick() == tick0, "closing the menu returns to the clean pause")
	sc.queue_free()
	await process_frame
	# online: the capture actions and the clip cameras do nothing
	var on: Node = (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	on.auto_process = false
	on.sim_kind = on.SimKind.FAKE
	on.with_pause_menu = false
	on.apply_settings = false
	on.online = true
	root.add_child(on)
	await process_frame
	_frame_with(on, [&"capture_pause", &"capture_slow"])
	t.ok(_ticks_over(on, 1.0) >= 19, "online: capture_pause and capture_slow change nothing")
	_frame_with(on, [&"camera_clip"])
	t.ok(on.rig.mode == CameraRig.Mode.CHASE, "online: camera_clip changes nothing")
	_frame_with(on, [&"world_tags"])
	t.ok(not on.hud.world.visible, "online: world_tags hides the world tags")
	on.queue_free()
	await process_frame


func test_capture_scene_race() -> void:
	t.begin("9 capture in a race on the core: world tags, on-water guides, clip cameras")
	var sc: Node = (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	sc.set("auto_process", false)
	sc.set("sim_kind", 1)  # CORE
	sc.set("race_mode", true)
	sc.set("fleet_size", 3)
	sc.set("with_pause_menu", false)
	sc.set("apply_settings", false)
	sc.set("core_settings", {"free_sailing_s": 5.0})
	root.add_child(sc)
	sc.set("scripted_input", RawInput.new())
	await process_frame
	for i in 300:
		_frame_with(sc, [], [], 1.0 / 30.0)
	var cv: CourseView = sc.course_view
	var hud: Hud = sc.hud
	var n_lines := cv.lines.size()
	t.ok(n_lines > 0 and hud.world.visible, "guides on the water (%d lines) and world tags shown" % n_lines)
	_frame_with(sc, [&"world_tags"])
	t.ok(not hud.world.visible and not cv.show_guides and cv.lines.is_empty() and cv.circles.is_empty(),
		"world_tags: world tags and the water overlays hidden")
	t.ok(hud.visible, "the rest of the HUD stays")
	_frame_with(sc, [&"world_tags"])
	t.ok(hud.world.visible and cv.lines.size() == n_lines, "world_tags again: shown")
	# hud.md §16.4.1: a click on a boat in the scene selects her; Esc clears before it pauses
	var runner: SimRunner = sc.runner
	var other := -1
	var tri := PackedVector2Array()
	for b in sc.sim.boat_count():
		if b != sc.viewed and not hud.boat_triangle(b).is_empty():
			other = b
			tri = hud.boat_triangle(b)
			break
	var at := Vector2(-1, -1)
	if not tri.is_empty():
		at = Vector2.ZERO
		for q in tri:
			at += q / tri.size()
	var ck := RawInput.new().click(at)
	sc.scripted_input = ck
	sc.step_frame(1.0 / 30.0)
	sc.scripted_input = RawInput.new()
	t.ok(not tri.is_empty() and hud.selected_boat() == other, "a click on boat %d in the scene selects her (%s, %d)" % [
		other, str(tri), hud.selected_boat()])
	hud.select(other)
	_frame_with(sc, [&"pause_menu"])
	t.ok(hud.selected_boat() == -1 and not runner.paused, "Esc with a boat selected clears it and does not pause")
	_frame_with(sc, [&"pause_menu"])
	t.ok(runner.paused, "the next Esc pauses")
	hud.select(other)
	sc.scripted_input = RawInput.new().click(at)
	sc.step_frame(1.0 / 30.0)
	sc.scripted_input = RawInput.new()
	t.ok(hud.selected_boat() == other, "no picks while paused")
	_frame_with(sc, [&"pause_menu"])
	t.ok(not runner.paused and hud.selected_boat() == other, "Esc in the pause resumes and keeps the selection")
	hud.select(-1)
	_frame_with(sc, [&"camera_clip"])
	var rig: CameraRig = sc.rig
	t.ok(rig.mode == CameraRig.Mode.START_LINE and rig.course != null and rig.course.has_line,
		"camera_clip: the start line shot from the race")
	var want := StartLineCamera.place(rig.course.committee, rig.course.pin, rig.course.pre_start)[0]
	t.ok(Vector2(rig.view.xform.origin.x - want.x, rig.view.xform.origin.z - want.z).length() < 0.01
		and rig.view.xform.origin.y >= StartLineCamera.HEIGHT - 1e-6,
		"start line eye 20 m outside the committee end, 12 m behind the line, 8 m up or more")
	_frame_with(sc, [&"camera_clip"])
	t.ok(rig.mode == CameraRig.Mode.MARK and rig.course.has_mark, "camera_clip: the mark shot")
	var me := MarkCamera.eye_for(rig.course.mark, rig.course.approach, rig.course.side)
	t.ok(Vector2(rig.view.xform.origin.x - me.x, rig.view.xform.origin.z - me.z).length() < 0.01,
		"mark eye 40 m from the first mark")
	t.near(Vector2(me.x - rig.course.mark.x, me.z - rig.course.mark.z).length(), 40.0, 1e-3, "40 m from the mark")
	_frame_with(sc, [&"camera_clip"])
	_frame_with(sc, [&"camera_clip"])
	t.ok(rig.mode == CameraRig.Mode.HELICOPTER, "then long lens and helicopter")
	sc.queue_free()
	await process_frame
