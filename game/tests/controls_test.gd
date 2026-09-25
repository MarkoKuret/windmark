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
	test_input_map()
	test_input_frame()
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
	# ignored while auto-trim is on
	pc = PlayerControls.new()
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
	for fps in FPS:
		var dt: float = 1.0 / fps
		var pc := PlayerControls.new()
		t.ok(pc.helm_mode == PlayerControls.HelmMode.SET_AND_HOLD, "default mode")
		var r := RawInput.new().press(&"helm_right")
		run(pc, r, frames_for(0.5, fps), dt)
		t.ok(absf(pc.h_cmd - 0.30) <= 0.30 * 0.005, "%d fps: 0.5 s gives %.4f" % [fps, pc.h_cmd])
		r.held.erase(&"helm_right")
		run(pc, r, int(fps), dt)
		t.ok(absf(pc.h_cmd - 0.30) <= 0.30 * 0.005, "%d fps: stays after release" % fps)
		pc.update(RawInput.new().press(&"helm_centre"), dt)
		t.near(pc.h_cmd, 0.0, 1e-9, "%d fps: helm_centre gives 0 in the next frame" % fps)
		# helm_fine: a third of the rate
		run(pc, RawInput.new().press(&"helm_right").hold(&"helm_fine"), frames_for(0.5, fps), dt)
		t.ok(absf(pc.h_cmd - 0.10) <= 0.10 * 0.005, "%d fps: fine 0.5 s gives %.4f" % [fps, pc.h_cmd])


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
		"map", "radar_zoom_in", "radar_zoom_out", "radar_orientation", "wind_shadow_view", "hud_hide",
		"boat_names", "spectate_next", "spectate_prev", "spectate_leader", "chat", "pause_menu", "screenshot",
		"helm_stick_left", "helm_stick_right", "sheet_in_trigger", "sheet_out_trigger", "camera_orbit_left",
		"camera_orbit_drag", "camera_look_up"]
	for a in spec:
		t.ok(InputMap.has_action(a), "InputMap has %s" % a)
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
