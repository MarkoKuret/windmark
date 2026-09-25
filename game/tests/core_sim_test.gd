extends SceneTree
## Headless test of the core binding (game/native, WM-016.01): CoreSim through CoreSimSource.
##   godot --headless --path game -s res://tests/core_sim_test.gd
## - free sailing as the core's C API example does it (core/examples/race_example.c free_sail): one wm7 in open
##   water, 12 kn steady wind, no puffs, placed at the origin on heading 1.2 rad, 60 s of auto trim with the helm
##   centred; prints the example's line so run_core_sim_test.sh can compare the two
## - every SimSource call, the render pose between ticks, the input frame wire form, sail requests
## - a race world on example_bay: the sea renderer calls (components, exposure, wind state with puffs, current),
##   the sea clock, the drawn sea mirror against the core's height, race events, determinism

const KNOT := 0.514444470

var t := TestLog.new()


func _init() -> void:
	t.begin("extension")
	if not t.ok(CoreSimSource.available(), "CoreSim is registered (build game/native first)"):
		t.finish(self, "core sim test")
		return
	var probe: Object = ClassDB.instantiate(&"CoreSim")
	t.ok(probe.api_version() == 1, "C API version 1")
	t.ok(CoreSimSource.default_settings().has("race_seed"), "default settings")
	_free_sailing()
	_race_world()
	t.finish(self, "core sim test")


func _free_sailing() -> void:
	t.begin("free sailing")
	var sim := CoreSimSource.new()
	sim.settings = {"wind_speed": 12.0 * KNOT, "shift_preset": 0, "puffs": false}
	t.ok(sim.create(), "open-water world: " + sim.last_error())
	var b := sim.add_boat("wm7", 0.0, 0.0, 1.2)
	t.ok(b == 0 and sim.boat_count() == 1, "one boat")
	var s0 := sim.state(b)
	t.near(s0.psi, 1.2, 1e-6, "placed heading")
	t.ok(s0.v > 0.5, "placed moving (60 %% of polar): %.2f" % s0.v)

	var f := InputFrame.new()
	f.sheet_cmd = 0.5
	f.flags = InputFrame.FLAG_AUTO_TRIM
	for k in 1200:
		f.tick = sim.tick()
		sim.apply_input(b, f)
		sim.step()
	t.ok(sim.tick() == 1200, "1200 ticks")
	var s := sim.state(b)
	var d := Vector2(s.pos_x, s.pos_y).length()
	print("free sailing: 60 s on heading %.2f rad, %.1f m sailed, speed %.2f m/s, twa %.2f rad, has race %d"
		% [s.psi, d, s.v, s.twa, 1 if sim.core.has_race() else 0])
	t.ok(d > 100.0 and s.v > 2.0, "the boat sails: %.1f m, %.2f m/s" % [d, s.v])
	t.ok(not sim.core.has_race(), "no race")
	t.near(sim.sea_time_ms(sim.tick()), 60000.0, 0.0, "sea clock at tick 1200")
	t.ok(sim.core.time_ms() == 60000, "core time 60000 ms")

	# class info: core numbers plus the class file
	var info := sim.class_info(b)
	t.ok(info.id == "wm7" and info.name != "" and info.name != "wm7", "class id and name")
	t.near(info.lwl, 6.75, 1e-5, "lwl")
	t.ok(info.bwl > 1.5 and info.bwl < 2.2, "bwl %.4f" % info.bwl)
	t.near(info.transom_width, 2.10, 1e-6, "transom width")
	t.near(info.loa, 7.2, 1e-5, "loa")
	t.near(info.beam_max, 2.5, 1e-6, "beam_max")
	t.near(info.rudder_max, 0.61, 1e-6, "rudder_max")
	t.ok(info.sails.size() >= 2 and info.sails[info.main_sail].type == "main", "sails, main first")
	t.ok(info.front_sails.size() == info.sails.size() - 1, "front sail slots")
	var fake_info := BoatClassData.load_class("wm7").info
	t.ok(fake_info.sails.size() == info.sails.size(), "same sails as FakeSim's class data")
	for i in info.sails.size():
		t.ok(info.sails[i].name == fake_info.sails[i].name and info.sails[i].type == fake_info.sails[i].type,
			"sail %d %s" % [i, info.sails[i].name])
		t.near(info.sails[i].sheet_max, fake_info.sails[i].sheet_max, 1e-6, "sheet_max %d" % i)
	t.near(fake_info.lwl, info.lwl, 1e-5, "FakeSim lwl")
	t.near(fake_info.bwl, info.bwl, 1e-5, "FakeSim bwl")
	t.near(fake_info.transom_width, info.transom_width, 1e-6, "FakeSim transom width")
	t.ok(sim.class_info(b) == info, "class info cached")

	var c := sim.controls(b)
	t.ok(c.auto_trim and not c.let_fly and c.h_cmd == 0.0, "controls: auto trim, helm centred")
	var o := sim.outputs(b)
	t.ok(o.polar_speed > 2.0 and o.target_speed > 0.0, "outputs: polar %.2f" % o.polar_speed)
	t.near(o.wind_speed_clean, 12.0 * KNOT, 1e-3, "outputs: clean wind")
	var w := sim.wind_clean(s.pos_x, s.pos_y)
	t.near(w.x, 12.0 * KNOT, 1e-4, "wind_clean speed")
	t.ok(is_finite(sim.sea_height(s.pos_x, s.pos_y)), "sea height")
	var ts := sim.trim_speed_at(b, s.tws, absf(s.awa), 0.1)
	t.ok(is_nan(ts) or (ts > 0.0 and ts <= 1.0), "trim_speed_at %.3f" % ts)
	var env := sim.boat_env(b)
	t.ok(env["shadow_source"] == -1, "clear air")

	# the render pose lies between the last two states
	sim.step()
	var s1 := sim.state(b)
	var p0 := sim.render_pose(b, 0.0)
	var p1 := sim.render_pose(b, 1.0)
	var ph := sim.render_pose(b, 0.5)
	t.ok(p0.pos_x == s.pos_x and p0.pos_y == s.pos_y, "pose at alpha 0 = previous tick")
	t.ok(p1.pos_x == s1.pos_x and p1.pos_y == s1.pos_y and p1.psi == s1.psi, "pose at alpha 1 = last tick")
	t.near(ph.pos_x, 0.5 * (s.pos_x + s1.pos_x), 1e-3, "pose at alpha 0.5")
	t.near(sim.render_time_ms(0.5), sim.sea_time_ms(sim.tick() - 1 + 0.5), 1e-9, "render time = sea clock")

	# the input frame: GDScript and C wire forms agree
	var fr := InputFrame.new()
	fr.h_cmd = -0.37
	fr.sheet_cmd = 0.81
	fr.sail_req = 3
	fr.flags = InputFrame.FLAG_LET_FLY | InputFrame.FLAG_PROTEST
	t.ok(fr.encode() == sim.core.encode_input(fr.h_cmd, fr.sheet_cmd, fr.sail_req, fr.flags), "wire form")

	# sail requests are answered at once and take effect in the next step
	var kite := -1
	for i in info.sails.size():
		if info.sails[i].type.begins_with("spinnaker"):
			kite = i
	var hf := InputFrame.new()
	hf.sheet_cmd = 0.5
	hf.flags = InputFrame.FLAG_AUTO_TRIM
	hf.sail_req = InputFrame.hoist_req(kite)
	t.ok(sim.apply_input(b, hf) == SimSource.Request.ACCEPTED, "kite hoist accepted")
	hf.sail_req = InputFrame.hoist_req(info.main_sail)
	t.ok(sim.apply_input(b, hf) == SimSource.Request.REJECTED, "main hoist rejected")
	hf.sail_req = InputFrame.SAIL_NONE
	hf.h_cmd = 0.3
	sim.apply_input(b, hf)
	t.ok(sim.controls(b).h_cmd == 0.0, "queued helm applies at the next step")
	sim.step()
	t.near(sim.controls(b).h_cmd, 0.3, 1e-4, "helm after the step (wire-quantised)")
	var sv := sim.sails(b)
	t.ok(sv.busy() and sv.queue_len > 0, "sail change running: %d steps" % sv.queue_len)
	t.ok(sv.sails.size() == info.sails.size() and sv.out.size() == info.sails.size(), "per-sail records")
	t.ok(sv.sails[info.main_sail].phase == SimSource.Phase.UP, "main up")
	var ws := sim.wake_state(b, sim.render_pose(b, 1.0), true)
	t.ok(ws["lwl"] == info.lwl and ws["transom_width"] == info.transom_width and ws["own"], "wake state")


func _race_world() -> void:
	t.begin("race world on example_bay")
	var a := _make_race()
	var b := _make_race()
	if not t.ok(a != null and b != null, "two race worlds"):
		return
	t.ok(a.core.has_race() and a.boat_count() == 2, "race with two boats")
	var course: Dictionary = a.core.course()
	t.ok(course["marks"].size() > 0 and course["steps"].size() > 0, "course marks and steps")
	var signals := 0
	for k in 3000:
		for i in a.boat_count():
			var f := InputFrame.new()
			f.flags = InputFrame.FLAG_AUTO_TRIM
			f.h_cmd = 0.2 if (k / 400) % 2 == 0 else -0.2
			a.apply_input(i, f)
			b.apply_input(i, f)
		a.step()
		b.step()
		for e in a.core.race_events():
			if e["kind"] == 0:
				signals += 1
	t.ok(a.checksum() == b.checksum() and a.checksum() != 0, "same checksum twice: %x" % a.checksum())
	t.ok(signals >= 1, "race signals: %d" % signals)
	var race: Dictionary = a.core.race()
	t.ok(race["state"] >= 1, "race state %d" % race["state"])

	# the sea renderer's calls
	var comps := a.sea_components()
	t.ok(comps.size() > 0 and comps[0].size() == 5, "sea components: %d" % comps.size())
	var ex := a.sea_exposure()
	t.ok(not ex.is_empty() and ex["e"] is PackedFloat32Array and ex["e"].size() == ex["nx"] * ex["ny"],
		"exposure grid %sx%s" % [ex.get("nx"), ex.get("ny")])
	var tm := a.sea_time_ms(a.tick())
	var wst := a.wind_state(tm)
	for key in ["base_speed", "base_from", "global_from", "puff_tile", "cap_up", "cap_down", "puffs", "patches"]:
		t.ok(wst.has(key), "wind state has " + key)
	t.ok(wst["puffs"] and wst["patches"].size() > 0, "live puff patches: %d" % wst["patches"].size())
	t.ok(wst["patches"].size() == 0 or wst["patches"][0].size() == 5, "patch = [px, py, R, s, e]")
	t.near(wst["global_from"], a.core.wind_global_from(), 1e-6, "global direction now")
	var cur := a.current_at(100.0, 100.0, tm)
	t.ok(is_finite(cur.x) and is_finite(cur.y), "current %s" % cur)
	var env := CoreEnvSource.new()
	env.sim = a
	t.ok(env.sea_components().size() == comps.size() and env.wind_state(tm)["patches"].size() ==
		wst["patches"].size(), "CoreEnvSource forwards")
	env.free()

	# the drawn sea (SeaModel on the core's components and exposure) matches the core's height
	var model := SeaModel.new()
	model.set_components(comps)
	model.set_exposure(ex)
	var worst := 0.0
	for p in [Vector2(0, 0), Vector2(250, -130), Vector2(-420, 610), Vector2(900, 40)]:
		var hc := a.sea_height(p.x, p.y)
		var hm := model.height(p.x, p.y, tm)
		worst = maxf(worst, absf(hc - hm))
		t.near(a.sea_height_at(p.x, p.y, tm * 0.001), hc, 1e-6, "sea_height_at the tick time")
	t.ok(worst < 1e-3, "drawn sea within 1 mm of the core: %.7f m" % worst)
	var st := a.state(0)
	t.ok(is_finite(st.z) and is_finite(st.theta), "hull heave and pitch")


func _make_race() -> CoreSimSource:
	var sim := CoreSimSource.new()
	sim.settings = {"race_seed": 20260925, "wind_speed": 11.0 * KNOT, "wind_from": 0.2, "shift_preset": 1,
		"free_sailing_s": 10.0}
	if not sim.create("example_bay"):
		t.ok(false, "race world: " + sim.last_error())
		return null
	sim.add_entry("wm7", {"human": true})
	sim.add_entry("wm12")
	if not sim.create_race("example_bay/example_wl"):
		t.ok(false, "create race: " + sim.last_error())
		return null
	return sim
