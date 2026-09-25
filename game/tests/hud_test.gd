extends SceneTree
## Minimal HUD tests (hud.md §1, §2, §3.1, §5, §14 for these elements) and the sail test scene run headless:
## the HUD shows the sim's live values, read back from the node text.
##   godot --headless --path game -s res://tests/hud_test.gd

var t := TestLog.new()


## A scripted boat state behind the SimSource interface.
class StubSim:
	extends SimSource
	var info := ClassInfo.new()
	var s := BoatState.new()
	var c := BoatControls.new()
	var o := BoatOutputs.new()
	var sv := SailsView.new()
	var trim_table := true

	func _init() -> void:
		info.id = "stub"
		for n in ["main", "jib", "kite"]:
			var si := SailInfo.new()
			si.name = n
			si.type = "main" if n == "main" else "jib"
			si.sheet_min = 0.1
			si.sheet_max = 1.2
			info.sails.append(si)
			var st := SailState.new()
			st.phase = Phase.UP if n != "kite" else Phase.DOWN
			sv.sails.append(st)
			sv.out.append(SailOutput.new())
		info.main_sail = 0
		info.front_sails = PackedInt32Array([1, 2])
		sv.front = 1

	func class_info(_b: int) -> ClassInfo:
		return info

	func state(_b: int) -> BoatState:
		return s

	func controls(_b: int) -> BoatControls:
		return c

	func outputs(_b: int) -> BoatOutputs:
		return o

	func sails(_b: int) -> SailsView:
		return sv

	## a parabola: 1 at eps = 0, 0.98 at +-4 deg
	func trim_speed_at(_b: int, _tws: float, _awa: float, eps: float) -> float:
		if not trim_table:
			return NAN
		var k := 0.02 / pow(deg_to_rad(4.0), 2)
		return 1.0 - k * eps * eps


func _init() -> void:
	test_formats()
	test_values()
	test_trim_gauge()
	test_hud_text()
	await test_scene()
	t.finish(self, "hud_test")


func test_formats() -> void:
	t.begin("formats")
	var K := HudFormat.KNOT
	t.ok(HudFormat.speed_kn(7.4 * K) == "7.4", "7.4 kn")
	t.ok(HudFormat.speed_kn(7.45 * K + 1e-6) == "7.5", "half away from zero")
	t.ok(HudFormat.speed_kn(0.04 * K) == "0.0", "below 0.05 shows 0.0")
	t.ok(HudFormat.speed_kn(-0.04 * K) == "0.0", "small sternway shows 0.0")
	t.ok(HudFormat.compass_deg(deg_to_rad(5.0)) == "005", "3 digits")
	t.ok(HudFormat.compass_deg(deg_to_rad(359.6)) == "000", "359.6 rounds to 000")
	t.ok(HudFormat.compass_deg(deg_to_rad(-90.0)) == "270", "wrapped")
	t.ok(HudFormat.side_angle(deg_to_rad(42.4), "S", "P") == "42° S", "42° S")
	t.ok(HudFormat.side_angle(deg_to_rad(-38.5), "S", "P") == "39° P", "39° P")
	t.ok(HudFormat.percent(97.5) == "98", "percent")


func _ticks(v: HudValues, sim: SimSource, n: int) -> void:
	for i in n:
		v.tick(sim, 0)


func test_values() -> void:
	t.begin("values")
	var sim := StubSim.new()
	var s := sim.s
	s.v = 3.0
	s.v_filt = 3.0
	s.sog_filt_x = 3.0 * sin(deg_to_rad(45.0))
	s.sog_filt_y = 3.0 * cos(deg_to_rad(45.0))
	s.psi = deg_to_rad(45.0)
	s.phi = deg_to_rad(-11.0)
	s.h = 0.2
	sim.c.h_cmd = 0.5
	s.tws = 6.0
	s.twa = deg_to_rad(-42.0)
	s.twd_from = deg_to_rad(3.0)
	s.aws = 8.5
	s.awa = deg_to_rad(-28.0)
	sim.o.polar_speed = 3.2
	sim.o.cog = deg_to_rad(45.0)
	var v := HudValues.new()
	_ticks(v, sim, 1)
	t.near(v.bsp, 3.0, 1e-9, "BSP is v_filt")
	t.near(v.sog, 3.0, 1e-6, "SOG from the filtered ground velocity")
	t.near(rad_to_deg(v.hdg), 45.0, 1e-4, "HDG")
	t.near(v.h, 0.2, 1e-9, "rudder h")
	t.near(v.h_cmd, 0.5, 1e-9, "rudder mark h_cmd")
	# time constants: a TWS step reaches 1 - 1/e after tau = 2 s (40 ticks)
	s.tws = 10.0
	_ticks(v, sim, 40)
	t.near(v.tws, 6.0 + 4.0 * (1.0 - exp(-1.0)), 0.01, "TWS tau 2 s")
	s.aws = 12.5
	var a0 := v.aws
	_ticks(v, sim, 20)
	t.near(v.aws, a0 + (12.5 - a0) * (1.0 - exp(-1.0)), 0.01, "AWS tau 1 s")
	# angles through unit vectors: a heading step across north does not swing the long way
	s.psi = deg_to_rad(355.0)
	v = HudValues.new()
	_ticks(v, sim, 1)
	s.psi = deg_to_rad(5.0)
	_ticks(v, sim, 1)
	var d := rad_to_deg(Frames.angle_diff(v.hdg, deg_to_rad(355.0)))
	t.ok(d > 0.0 and d < 10.0, "HDG filtered across north (%.2f)" % d)
	_ticks(v, sim, 200)
	t.near(rad_to_deg(Frames.angle_diff(v.hdg, deg_to_rad(5.0))), 0.0, 0.01, "HDG settles")
	t.near(v.polar_pct, 100.0 * 3.0 / 3.2, 0.01, "polar %")


func test_trim_gauge() -> void:
	t.begin("trim gauge")
	var sim := StubSim.new()
	var v := HudValues.new()
	sim.c.auto_trim = true
	sim.sv.out[1].trim_error = deg_to_rad(10.0)
	_ticks(v, sim, 1)
	t.ok(v.gauges.size() == 2 and v.gauges[0].name == "main" and v.gauges[1].name == "jib", "main and the front sail")
	var g: HudValues.Gauge = v.gauges[1]
	t.ok(g.auto and g.needle == 0.0 and g.colour == HudValues.Colour.NONE, "auto: neutral needle, no colour")
	var tol := v.trim_tolerance(sim, 0, sim.s.tws, 0.0)
	t.near(rad_to_deg(tol.x), 4.0, 0.11, "tolerance from the trim_speed table (+)")
	t.near(rad_to_deg(tol.y), 4.0, 0.11, "tolerance from the trim_speed table (-)")
	sim.c.auto_trim = false
	var cases := [[1.0, HudValues.Colour.GREEN, "Flowing"], [3.0, HudValues.Colour.YELLOW, "Flowing"],
		[6.0, HudValues.Colour.RED, "Luffing: sheet in"], [-6.0, HudValues.Colour.RED, "Stalled: ease"]]
	for cs in cases:
		v = HudValues.new()
		sim.sv.out[1].trim_error = deg_to_rad(cs[0])
		_ticks(v, sim, 1)
		g = v.gauges[1]
		t.ok(g.colour == cs[1] and g.telltale == cs[2], "eps %.0f deg: colour %d, %s" % [cs[0], g.colour, g.telltale])
		t.near(g.e, clampf(cs[0] / 4.0, -2.0, 2.0), 0.03, "normalised error at %.0f deg" % cs[0])
	sim.sv.out[1].trim_error = 0.0
	sim.sv.out[1].luff_shiver = 0.8
	_ticks(v, sim, 1)
	t.ok(v.gauges[1].telltale == "Luffing: sheet in", "luff shiver > 0.5: luffing")
	sim.sv.out[1].luff_shiver = 0.0
	sim.sv.out[1].backed = true
	_ticks(v, sim, 1)
	t.ok(v.gauges[1].telltale == "Aback", "backed: aback")
	sim.sv.out[1].backed = false
	# needle smoothing tau 0.3 s
	v = HudValues.new()
	sim.sv.out[1].trim_error = 0.0
	_ticks(v, sim, 1)
	sim.sv.out[1].trim_error = deg_to_rad(4.0)
	_ticks(v, sim, 6)
	t.near(v.gauges[1].needle, 1.0 - exp(-1.0), 0.02, "needle tau 0.3 s")
	# without a table: +-2 deg
	sim.trim_table = false
	var v2 := HudValues.new()
	t.near(rad_to_deg(v2.trim_tolerance(sim, 0, 5.0, 0.5).x), 2.0, 1e-6, "no table: 2 deg")
	sim.trim_table = true
	# greyed while a sail is being hoisted
	sim.sv.sails[1].phase = SimSource.Phase.PREPARE_DROP
	_ticks(v, sim, 1)
	t.ok(v.gauges[1].greyed, "greyed during a change")
	sim.sv.sails[1].phase = SimSource.Phase.UP
	# a real class table (wm7 through FakeSim)
	var fs := FakeSim.new()
	fs.add_boat("wm7", 0, 0, deg_to_rad(320))
	var tl := v.trim_tolerance(fs, 0, fs.state(0).tws, absf(fs.state(0).awa))
	t.ok(tl.x > 0.0 and tl.x <= deg_to_rad(30.0) and tl.y > 0.0, "wm7 tolerance found (%.1f, %.1f deg)"
		% [rad_to_deg(tl.x), rad_to_deg(tl.y)])


func _hud() -> Hud:
	var h := Hud.new()
	root.add_child(h)
	return h


func test_hud_text() -> void:
	t.begin("HUD text and assist presets")
	var sim := StubSim.new()
	var s := sim.s
	s.v_filt = 3.8
	s.psi = deg_to_rad(92.0)
	s.phi = deg_to_rad(12.0)
	s.tws = 6.2
	s.twa = deg_to_rad(-44.0)
	s.twd_from = deg_to_rad(48.0)
	s.aws = 8.9
	s.awa = deg_to_rad(-29.0)
	s.h = -0.3
	sim.c.h_cmd = -0.3
	var h := _hud()
	h.tick(sim, 0)
	h.frame(0.016)
	t.ok(h.text_of("bsp") == "BSP  7.4 kn", h.text_of("bsp"))
	t.ok(h.text_of("hdg") == "HDG  092", h.text_of("hdg"))
	t.ok(h.text_of("heel") == "Heel  12° S", h.text_of("heel"))
	t.ok(h.text_of("tws") == "TWS  12.1 kn", h.text_of("tws"))
	t.ok(h.text_of("twa") == "TWA  44° P", h.text_of("twa"))
	t.ok(h.text_of("twd") == "TWD  048", h.text_of("twd"))
	t.ok(h.text_of("aws") == "AWS  17.3 kn", h.text_of("aws"))
	t.ok(h.text_of("awa") == "AWA  29° P", h.text_of("awa"))
	t.ok(h.text_of("sail") == "Sail  Jib", h.text_of("sail"))
	t.ok(h.text_of("rudder") == "Helm  30 P", h.text_of("rudder"))
	t.ok(h.text_of("sheet") == "Sheet  AUTO", h.text_of("sheet"))
	t.ok(not h.sheet_bar.visible, "manual sheet bar hidden with auto-trim")
	t.ok(h.rudder_bar.value == -0.3 and h.rudder_bar.mark == -0.3, "rudder bar h and h_cmd mark")
	# 4 Hz refresh: a change shows up only at the next refresh
	s.v_filt = 5.0
	h.tick(sim, 0)
	h.frame(0.1)
	t.ok(h.text_of("bsp") == "BSP  7.4 kn", "text holds between refreshes")
	h.frame(0.16)
	t.ok(h.text_of("bsp") == "BSP  9.7 kn", "text refreshed after 0.25 s: " + h.text_of("bsp"))
	# manual sheet, let fly
	sim.c.auto_trim = false
	sim.c.sheet_cmd = 0.42
	sim.c.let_fly = true
	sim.sv.out[1].trim_error = deg_to_rad(6.0)
	h.tick(sim, 0)
	h.refresh_text()
	h.frame(0.016)
	t.ok(h.text_of("sheet") == "Sheet  42 %   LET FLY", h.text_of("sheet"))
	t.ok(h.sheet_bar.visible and absf(h.sheet_bar.value - 0.42) < 1e-9, "sheet bar shows u")
	var gv := h.gauge_views[1]
	t.ok(gv.show_needle and gv.colour == Hud.COLOURS[HudValues.Colour.RED], "standard: needle and colour")
	t.ok(gv.telltale == "Luffing: sheet in", "tell-tale")
	h.assist = Hud.Assist.MINIMAL
	h.frame(0.016)
	t.ok(not gv.show_needle and gv.colour == Hud.COLOURS[HudValues.Colour.NONE] and gv.telltale != "",
		"minimal: tell-tales only")
	h.assist = Hud.Assist.FULL
	h.frame(0.016)
	t.ok(gv.show_needle, "full: needle")
	# sail change and the busy flash
	sim.sv.queue = [SimSource.SailStep.new(2, SimSource.Phase.HOISTING), SimSource.SailStep.new(2, SimSource.Phase.UP)]
	sim.sv.queue_len = 2
	sim.sv.queue_pos = 0
	sim.sv.sails[2].progress = 0.4
	h.tick(sim, 0)
	h.refresh_text()
	t.ok(h.text_of("sail") == "Sail  Jib, hoisting Kite 40 %", h.text_of("sail"))
	var pc := PlayerControls.new()
	pc.busy_flash = true
	pc.messages.append(PlayerControls.MSG_AUTO_TRIM_REFUSED)
	h.frame(0.1, pc)
	t.ok(h.text_of("message") == PlayerControls.MSG_AUTO_TRIM_REFUSED and not pc.busy_flash, "controls feedback shown")
	# no em dash anywhere in the player text
	var dash := false
	for k in h.labels:
		dash = dash or h.text_of(k).contains("—")
	t.ok(not dash, "no em dash in HUD text")
	h.toggle_hidden()
	t.ok(not h.visible, "hud_hide")
	h.queue_free()


func test_scene() -> void:
	t.begin("sail test scene, live values")
	var packed := load("res://scenes/sail_test.tscn") as PackedScene
	t.ok(packed != null, "scene loads")
	var sc := packed.instantiate()
	sc.auto_process = false
	root.add_child(sc)
	await process_frame  # _ready runs once the tree is up
	t.ok(sc.boat_view.model != null, "generated boat loaded (run tests/run_boat_import_test.sh first)")
	var r := RawInput.new()
	sc.scripted_input = r
	var dt := 1.0 / 60.0
	var sim: FakeSim = sc.sim
	var v0 := sim.state(0).v
	# sail 20 s, bear away (helm to port on starboard tack) for a second at 5 s, auto-trim off at 10 s and ease, camera cycle at 15 s
	for i in 1200:
		r.pressed = []
		if i == 300:
			r.press(&"helm_left")
		if i == 360:
			r.held.erase(&"helm_left")
			r.press(&"helm_centre")
		if i == 361:
			r.held.erase(&"helm_centre")
		if i == 600:
			r.press(&"auto_trim")
		if i == 601:
			r.held.erase(&"auto_trim")
			r.press(&"sheet_out")
		if i == 640:
			r.held.erase(&"sheet_out")
		if i == 900:
			r.press(&"camera_next")
		if i == 901:
			r.held.erase(&"camera_next")
		sc.step_frame(dt)
	var s := sim.state(0)
	t.ok(sim.tick() >= 399 and sim.tick() <= 401, "20 s at 60 fps is 400 ticks (%d)" % sim.tick())
	t.ok(s.v > 1.0 and s.v != v0, "the boat sails (%.2f m/s)" % s.v)
	t.ok(not sim.controls(0).auto_trim, "auto-trim switched off through the frame")
	t.ok(sim.controls(0).sheet_cmd > 0.0, "sheet eased (%.3f)" % sim.controls(0).sheet_cmd)
	t.ok(sc.rig.mode == CameraRig.Mode.ONBOARD, "camera_next went to onboard")
	var hud: Hud = sc.hud
	hud.refresh_text()
	var hv := hud.values
	t.ok(hud.text_of("bsp") == "BSP  %s kn" % HudFormat.speed_kn(s.v_filt), "BSP shows v_filt: " + hud.text_of("bsp"))
	t.ok(absf(Frames.angle_diff(hv.hdg, s.psi)) < deg_to_rad(3.0), "HDG tracks psi")
	t.ok(hud.text_of("hdg") == "HDG  %s" % HudFormat.compass_deg(hv.hdg), hud.text_of("hdg"))
	t.ok(absf(hv.tws - s.tws) < 0.2, "TWS tracks tws")
	t.ok(hud.text_of("twa") == "TWA  %s" % HudFormat.side_angle(hv.twa, "S", "P"), hud.text_of("twa"))
	t.ok(hud.text_of("sheet") == "Sheet  %s %%" % HudFormat.percent(100.0 * sim.controls(0).sheet_cmd),
		hud.text_of("sheet"))
	t.ok(hud.rudder_bar.value == hv.h, "rudder bar live")
	var shown := ""
	for k in ["bsp", "hdg", "heel", "tws", "twa", "twd", "aws", "awa", "sail", "rudder", "sheet"]:
		shown += hud.text_of(k) + " | "
	print("  HUD: " + shown)
	sc.queue_free()
