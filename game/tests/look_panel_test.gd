extends SceneTree
## The developer look panel (hud.md §18, LookPanel and DevLook), headless, in the sail scene (free sailing on the
## core when the GDExtension is loaded, FakeSim otherwise): every row's change reaches its object (environment,
## root viewport, camera rig, sky, sea, shadows, perf overlay), stepping a row and back restores the original, the
## startup flags set the same state through the same functions, the restart with a wind makes the world again with
## that wind, and the panel blocks the boat's keys only while it has the focus (the simulation keeps running).
##   godot --headless --path game -s res://tests/look_panel_test.gd

const DT := 1.0 / 60.0

var t := TestLog.new()
var sc: Node
var panel: LookPanel


func _init() -> void:
	await _run()
	t.finish(self, "look_panel_test")


func _run() -> void:
	var core := CoreSimSource.available()
	sc = (load("res://scenes/sail_test.tscn") as PackedScene).instantiate()
	sc.auto_process = false
	sc.sim_kind = sc.SimKind.CORE if core else sc.SimKind.FAKE
	sc.with_pause_menu = false
	sc.apply_settings = false
	root.add_child(sc)
	await process_frame
	sc.scripted_input = RawInput.new()
	root.size = Vector2i(1920, 1080)
	panel = sc.look_panel
	t.begin("look panel in the sail scene (%s)" % ("core, free sailing" if core else "FakeSim"))
	t.ok(panel != null and panel.layer > 1 and panel.layer < 60, "panel between the HUD and the pause menu (layer %d)"
		% panel.layer)
	t.ok(not panel.is_open and not panel.blocks_input(), "closed at start, keys with the boat")
	_frames(5)
	await test_keys()
	await test_rows()
	test_flags()
	if core:
		await test_restart()
	await test_focus()
	_restore_statics()
	sc.queue_free()
	await process_frame


func _frames(n: int) -> void:
	for i in n:
		sc.step_frame(DT)


func _key(code: Key, shift := false) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	k.shift_pressed = shift
	root.push_input(k)
	var up := k.duplicate() as InputEventKey
	up.pressed = false
	root.push_input(up)


## Steps a row forward and back, checking each state with `check` (called with the step count, 1 then 0).
func _round_trip(id: String, check: Callable) -> void:
	var before: Variant = panel.value(id)
	panel.step(id, 1)
	_frames(1)
	check.call(1)
	panel.step(id, -1)
	_frames(1)
	check.call(0)
	var after: Variant = panel.value(id)
	t.ok(str(after) == str(before), "%s: forward and back restores %s" % [id, before])


func test_keys() -> void:
	t.begin("F9, keyboard and mouse")
	_key(KEY_F9)
	t.ok(panel.is_open and panel.focused and panel.blocks_input(), "F9 opens it with the focus")
	await process_frame
	await process_frame  # layout
	var perf: PerfMonitor = sc.perf
	t.ok(not perf.overlay, "F9 leaves the frame-time overlay alone")
	panel.select(0)
	_key(KEY_DOWN)
	t.ok(panel.selected == 1, "Down picks the next row")
	_key(KEY_UP)
	_key(KEY_UP)
	t.ok(panel.selected == panel.rows.size() - 1, "Up wraps to the last row")
	panel.select(panel.row_index("caps"))
	var caps0: bool = sc.sea.whitecaps
	_key(KEY_RIGHT)
	t.ok(sc.sea.whitecaps != caps0, "Right changes the row (whitecaps %s)" % sc.sea.whitecaps)
	_key(KEY_ENTER)
	t.ok(sc.sea.whitecaps == caps0, "Enter toggles it back")
	# a click on a row
	var box := panel.get_node("Panel").find_child("Row_breathing", true, false) as Control
	var rect := box.get_global_rect()
	t.ok(rect.size.x > 50.0 and rect.size.y > 5.0, "rows laid out (%s)" % rect)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = rect.get_center()
	mb.global_position = mb.position
	root.push_input(mb)
	var mu := mb.duplicate() as InputEventMouseButton
	mu.pressed = false
	root.push_input(mu)
	t.ok(panel.selected == panel.row_index("breathing") and not sc.rig.chase.breathing, "a click picks and steps a row")
	panel.step("breathing", 1)
	var p0 := panel.get_node("Panel") as Control
	var vis := root.get_visible_rect().size
	t.ok(p0.get_global_rect().position.x > vis.x * 0.5, "a side column on the right (x %.0f of %.0f)"
		% [p0.get_global_rect().position.x, vis.x])
	t.ok(p0.get_global_rect().end.y <= vis.y + 1.0, "fits the screen height (%.0f of %.0f)"
		% [p0.get_global_rect().end.y, vis.y])
	root.size = Vector2i(1280, 800)
	await process_frame
	await process_frame
	vis = root.get_visible_rect().size
	t.ok(p0.get_global_rect().end.y <= vis.y + 1.0 and p0.get_global_rect().position.x > vis.x * 0.5,
		"fits 1280 x 800 on the right (%s)" % p0.get_global_rect())
	root.size = Vector2i(1920, 1080)
	await process_frame
	var txt := ""
	for l in p0.find_children("*", "Label", true, false):
		txt += (l as Label).text + "\n"
	t.ok(not txt.contains("—"), "no em dashes on the panel")
	await process_frame
	await process_frame
	await get_tree_timer(0.3)
	t.ok((panel.get_node("Panel").find_child("Readout", true, false) as Label).text.contains("fps")
		and panel.frame_ms > 0.0, "readout: %s" % (panel.get_node("Panel").find_child("Readout", true, false) as Label).text)
	_key(KEY_F9)
	t.ok(not panel.is_open and not panel.focused, "F9 on the focused panel closes it")
	_key(KEY_F9, true)
	t.ok(perf.overlay and not panel.is_open, "Shift+F9 is the frame-time overlay")
	_key(KEY_F9, true)
	t.ok(not perf.overlay, "Shift+F9 again hides it")


func get_tree_timer(s: float) -> Signal:
	return create_timer(s).timeout


func test_rows() -> void:
	t.begin("each row reaches its object and comes back")
	var env: Environment = sc.sky.environment()
	var win := root
	var rig: CameraRig = sc.rig
	var sea: Sea = sc.sea
	panel.open()
	# anti-aliasing: the root viewport
	panel.rows[panel.row_index("aa")]["set"].call("off")
	t.ok(win.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "AA off on the root viewport")
	panel.rows[panel.row_index("aa")]["set"].call("fxaa")
	t.ok(win.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA, "FXAA on the root viewport")
	panel.rows[panel.row_index("aa")]["set"].call("smaa")
	t.ok(win.screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA, "SMAA on the root viewport")
	_round_trip("aa", func(n: int) -> void:
		t.ok(win.screen_space_aa == (Viewport.SCREEN_SPACE_AA_DISABLED if n == 1 else Viewport.SCREEN_SPACE_AA_SMAA),
			"aa step %d: %d" % [n, win.screen_space_aa]))
	# grade and vignette: the environment and the rig's vignette
	var lut0 := env.adjustment_color_correction
	_round_trip("look", func(n: int) -> void:
		var on := n == 0
		t.ok(env.adjustment_enabled == on and (env.adjustment_color_correction == lut0) == on
			and (rig.look.strength > 0.0) == on, "look step %d: grade %s, vignette %.2f" % [n, env.adjustment_enabled,
			rig.look.strength]))
	# SSAO: the environment
	panel.rows[panel.row_index("ssao")]["set"].call(1)
	t.ok(env.ssao_enabled, "SSAO on: the environment draws it")
	panel.rows[panel.row_index("ssao")]["set"].call(0)
	t.ok(not env.ssao_enabled, "SSAO off")
	panel.rows[panel.row_index("ssao")]["set"].call(-1)
	t.ok(env.ssao_enabled == (sea.quality == SeaQuality.Tier.H), "SSAO by the tier (%s)" % env.ssao_enabled)
	_round_trip("ssao", func(n: int) -> void:
		t.ok(env.ssao_enabled == (n == 0 and sea.quality == SeaQuality.Tier.H), "ssao step %d" % n))
	# depth of field: the long lens camera's attributes
	rig.select_mode(CameraRig.Mode.LONG_LENS, sc.target)
	_frames(2)
	t.ok(rig.camera.attributes != null, "long lens: depth of field on its camera")
	_round_trip("dof", func(n: int) -> void:
		t.ok((rig.camera.attributes != null) == (n == 0), "dof step %d: attributes %s" % [n, rig.camera.attributes]))
	rig.select_mode(CameraRig.Mode.CHASE, sc.target)
	_frames(1)
	# time of day: the sky rig's hour, its sun and its grade
	var h0: float = sc.sky.hour
	var el0: float = sc.sky.sun_elevation_deg
	_round_trip("time", func(n: int) -> void:
		var want := h0 + 0.5 * n if n == 1 else h0
		t.ok(absf(sc.sky.hour - snappedf(want, 0.5 if n == 1 else 0.0001)) < 1e-3
			and (n == 0) == is_equal_approx(sc.sky.sun_elevation_deg, el0)
			and env.adjustment_color_correction == LookFx.lut(LookFx.scaled(sc.sky.grade, LookFx.grade_strength)),
			"time step %d: %s, sun %.1f deg" % [n, Daylight.hour_text(sc.sky.hour), sc.sky.sun_elevation_deg]))
	t.ok(panel.value_text("time").contains("sun") and panel.value_text("time").contains(":"),
		"time row shows the clock and the sun (%s)" % panel.value_text("time"))
	for i in 60:
		panel.step("time", 1)
	t.ok(sc.sky.sun_elevation_deg >= Daylight.MIN_SUN - 0.01, "time stops with the sun at 6 deg or more (%.1f)"
		% sc.sky.sun_elevation_deg)
	DevLook.set_time(sc, h0)
	# conditions: the sky rig's clouds, haze and grade
	var c0: String = sc.sky.conditions
	var cc0: float = sc.sky.cloud_cover
	_round_trip("conditions", func(n: int) -> void:
		var want: String = DevLook.CONDITIONS[(DevLook.CONDITIONS.find(c0) + n) % 4]
		t.ok(sc.sky.conditions == want and (n == 0) == is_equal_approx(sc.sky.cloud_cover, cc0)
			and is_equal_approx(env.fog_density, sc.sky.haze_max * sc.sky.haze_scale),
			"conditions step %d: %s, clouds %.2f" % [n, sc.sky.conditions, sc.sky.cloud_cover]))
	# grade and vignette strength: the environment's LUT and the rig's vignette
	var lutg := env.adjustment_color_correction
	_round_trip("grade", func(n: int) -> void:
		t.ok(is_equal_approx(LookFx.grade_strength, 1.0 + 0.1 * n) and (env.adjustment_color_correction == lutg) == (n == 0)
			and env.adjustment_color_correction == LookFx.lut(LookFx.scaled(sc.sky.grade, LookFx.grade_strength)),
			"grade step %d: x%.1f" % [n, LookFx.grade_strength]))
	panel.rows[panel.row_index("grade")]["set"].call(0.0)
	t.ok(not env.adjustment_enabled and panel.value_text("grade") == "Off", "grade strength 0: off")
	panel.rows[panel.row_index("grade")]["set"].call(1.0)
	var v0 := rig.look.strength
	_round_trip("vignette", func(n: int) -> void:
		t.near(rig.look.strength, v0 * (1.0 + 0.1 * n), 1e-6, "vignette step %d: %.3f" % [n, rig.look.strength]))
	panel.rows[panel.row_index("vignette")]["set"].call(0.0)
	t.ok(rig.look.strength == 0.0, "vignette strength 0: off")
	panel.rows[panel.row_index("vignette")]["set"].call(1.0)
	# every row says where to look, except the plain actions and the wind value
	var missing := []
	for r in panel.rows:
		if r["look"] == "" and not r["id"] in ["haze_reset", "wind"]:
			missing.append(r["id"])
	t.ok(missing.is_empty(), "every row has a where-to-look hint (%s)" % ", ".join(missing))
	panel.select(panel.row_index("ssao"))
	panel.set_focused(true)
	t.ok((panel.get_node("Panel").find_child("Hint", true, false) as Label).text.contains("foot of the mast"),
		"the selected row's hint is shown")
	# quality: the sea's shader and grid, reflections, the sun's shadows
	var q0 := sea.quality
	panel.rows[panel.row_index("quality")]["set"].call(SeaQuality.Tier.H)
	_frames(1)
	t.ok(sea.quality == SeaQuality.Tier.H and sea.material.shader.resource_path.ends_with("water_h.gdshader")
		and env.ssr_enabled and is_equal_approx(sc.sky.sun().directional_shadow_max_distance, 150.0)
		and env.ssao_enabled, "tier H live: water_h, reflections, 150 m shadows, SSAO")
	panel.rows[panel.row_index("quality")]["set"].call(SeaQuality.Tier.L)
	_frames(1)
	t.ok(sea.material.shader.resource_path.ends_with("water_l.gdshader") and not env.ssr_enabled
		and not env.glow_enabled, "tier L live: water_l, no reflections, no glow")
	panel.rows[panel.row_index("quality")]["set"].call(q0)
	_frames(1)
	_round_trip("quality", func(n: int) -> void:
		t.ok(sea.quality == (q0 + n) % 3 and sea.get_tier()["shader"] == sea.material.shader.resource_path,
			"quality step %d: %s" % [n, sea.get_tier()["name"]]))
	# haze: the environment's fog
	var hm: float = sc.sky.haze_max
	_round_trip("haze", func(n: int) -> void:
		t.near(env.fog_density, hm * (1.0 + 0.1 * n), 1e-5, "haze step %d: fog %.3f" % [n, env.fog_density]))
	for i in 20:
		panel.step("haze", 1)
	t.near(sc.sky.haze_scale, DevLook.HAZE_MAX, 1e-6, "haze stops at x1.5")
	sc.sky.conditions = "hazy"
	t.near(env.fog_density, sc.sky.haze_max * 1.5, 1e-5, "the factor stays with new conditions")
	sc.sky.conditions = c0
	panel.activate("haze_reset")
	t.near(env.fog_density, hm, 1e-6, "reset: the light's haze")
	# whitecaps: the sea's foam uniforms (off by default, water_render.md §4.4: start the round trip from on)
	t.ok(not sea.whitecaps, "whitecaps off by default")
	sea.whitecaps = true
	_frames(1)
	var cam: Vector3 = rig.camera.global_position
	sea.update_frame(cam, rig.camera)
	var rest0: float = sea.material.get_shader_parameter("caps_rest")
	var k0 := _caps_weight(sea)
	_round_trip("caps", func(n: int) -> void:
		sea.update_frame(cam, rig.camera)
		if n == 1:
			t.ok(_caps_weight(sea) == 0.0 and float(sea.material.get_shader_parameter("caps_rest")) == 0.0,
				"caps off: no foam weight uploaded")
		else:
			t.ok(is_equal_approx(_caps_weight(sea), k0) and is_equal_approx(sea.material.get_shader_parameter("caps_rest"),
				rest0), "caps on: the weights back (%.4f)" % k0))
	sea.whitecaps = false
	# drawn wind: the sea's base speed
	sea.update_frame(cam, rig.camera)
	var w0: float = sea.material.get_shader_parameter("base_speed")
	_round_trip("drawn_wind", func(n: int) -> void:
		sea.update_frame(cam, rig.camera)
		t.near(sea.material.get_shader_parameter("base_speed"), 8.0 * HudFormat.KNOT if n == 1 else w0, 1e-4,
			"drawn wind step %d" % n))
	panel.rows[panel.row_index("drawn_wind")]["set"].call(25.0)
	sea.update_frame(cam, rig.camera)
	t.near(sea.material.get_shader_parameter("base_speed"), 25.0 * HudFormat.KNOT, 1e-4, "drawn wind 25 kn")
	panel.rows[panel.row_index("drawn_wind")]["set"].call(0.0)
	# breathing: the chase camera
	_round_trip("breathing", func(n: int) -> void:
		t.ok(rig.chase.breathing == (n == 0), "breathing step %d" % n))
	panel.step("breathing", 1)
	_frames(30)
	t.ok(rig.chase.bank == 0.0 and rig.chase.surge == Vector3.ZERO and rig.chase.lean == Vector3.ZERO,
		"plain follow: no bank, trail or lean")
	panel.step("breathing", -1)
	_frames(30)
	t.ok(rig.chase.lean != Vector3.ZERO or absf(sc.target.pose.phi) < 1e-3, "breathing again: the lean back")
	# drawn shadows: BoatShadows
	_round_trip("drawn_shadows", func(n: int) -> void:
		var on := n == 0
		t.ok(sc.shadows.enabled == on and sc.no_drawn_shadows == not on, "drawn shadows step %d" % n))
	panel.step("drawn_shadows", 1)
	await process_frame
	await process_frame  # BoatShadows draws in its own _process
	var any_visible := false
	for c in sc.shadows.get_children():
		if c is MeshInstance3D and c.visible:
			any_visible = true
	t.ok(not any_visible, "drawn shadows off: none drawn")
	panel.step("drawn_shadows", -1)
	# boat sun shadows (sail_visuals.md §11.4): off hides the shadow proxies (never drawn in the colour pass) and
	# turns the sails off; on puts every surface's setting and visibility back
	var casts := _casts()
	_round_trip("boat_shadows", func(n: int) -> void:
		if n == 1:
			var off := true
			for v in sc.boat_views:
				for g in v.find_children("*", "GeometryInstance3D", true, false):
					var gi := g as GeometryInstance3D
					if String(gi.name).begins_with("shadow"):
						off = off and not gi.visible \
								and gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
					else:
						off = off and gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			t.ok(off, "sun shadows off: proxies hidden (still shadows only), every other boat surface off")
		else:
			t.ok(_casts() == casts, "sun shadows: every surface's own setting and visibility back")
		t.ok(_proxies_drawn() == 0, "no shadow proxy drawn in the colour pass (step %d)" % n))
	# render scale: the root viewport
	var s0 := win.scaling_3d_scale
	_round_trip("render_scale", func(n: int) -> void:
		t.near(win.scaling_3d_scale, 0.5 if n == 1 else s0, 1e-6, "render scale step %d: %.2f" % [n,
			win.scaling_3d_scale]))
	# the frame-time overlay
	_round_trip("perf", func(n: int) -> void:
		t.ok(sc.perf.overlay == (n == 1), "frame-time overlay step %d" % n))


func _caps_weight(sea: Sea) -> float:
	var s := 0.0
	for v in sea.material.get_shader_parameter("caps_k") as PackedVector4Array:
		s += absf(v.w)
	return s


func _casts() -> Dictionary:
	var d := {}
	for v in sc.boat_views:
		for g in v.find_children("*", "GeometryInstance3D", true, false):
			d[g.get_instance_id()] = [(g as GeometryInstance3D).cast_shadow, (g as GeometryInstance3D).visible]
	return d


## The shadow proxies the colour pass would draw: shown and not shadows-only.
func _proxies_drawn() -> int:
	var n := 0
	for v in sc.boat_views:
		for g in v.find_children("shadow*", "GeometryInstance3D", true, false):
			var gi := g as GeometryInstance3D
			if gi.is_visible_in_tree() and gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				n += 1
	return n


func test_flags() -> void:
	t.begin("startup flags set what the rows set")
	var env: Environment = sc.sky.environment()
	var checks := [
		["--aa=fxaa", func() -> bool: return root.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA and panel.value("aa") == "fxaa"],
		["--aa=smaa", func() -> bool: return panel.value("aa") == "smaa"],
		["--look=off", func() -> bool: return not env.adjustment_enabled and panel.value("look") == false],
		["--look=on", func() -> bool: return env.adjustment_enabled and panel.value("look") == true],
		["--ssao=on", func() -> bool: return env.ssao_enabled and panel.value("ssao") == 1],
		["--ssao=tier", func() -> bool: return panel.value("ssao") == -1],
		["--dof=off", func() -> bool: return not LookFx.dof_allowed() and panel.value("dof") == false],
		["--dof=on", func() -> bool: return panel.value("dof") == true],
		["--sky=late", func() -> bool: return sc.sky.preset_name() == "late" and panel.value("conditions") == "fair" and absf(sc.sky.sun_elevation_deg - 17.0) < 0.05],
		["--sky=fair", func() -> bool: return sc.sky.preset_name() == "fair"],
		["--time=10:30", func() -> bool: return is_equal_approx(panel.value("time"), 10.5)],
		["--conditions=overcast", func() -> bool: return sc.sky.conditions == "overcast" and panel.value("conditions") == "overcast"],
		["--conditions=fair", func() -> bool: return panel.value("conditions") == "fair"],
		["--time=14:30", func() -> bool: return is_equal_approx(sc.sky.hour, 14.5)],
		["--grade=0.5", func() -> bool: return is_equal_approx(panel.value("grade"), 0.5) and env.adjustment_enabled],
		["--grade=1", func() -> bool: return is_equal_approx(LookFx.grade_strength, 1.0)],
		["--vignette=0", func() -> bool: return sc.rig.look.strength == 0.0 and panel.value("vignette") == 0.0],
		["--vignette=1", func() -> bool: return sc.rig.look.strength > 0.0],
		["--light-advance=0", func() -> bool: return sc.sky.light_advance == 0.0],
		["--haze=0.5", func() -> bool: return is_equal_approx(env.fog_density, sc.sky.haze_max * 0.5)],
		["--haze=1", func() -> bool: return is_equal_approx(panel.value("haze"), 1.0)],
		["--quality=H", func() -> bool: return sc.sea.quality == SeaQuality.Tier.H and panel.value("quality") == 2],
		["--quality=M", func() -> bool: return panel.value("quality") == 1],
		["--caps=off", func() -> bool: return not sc.sea.whitecaps and panel.value("caps") == false],
		["--caps=on", func() -> bool: return panel.value("caps") == true],
		["--drawn-wind=18", func() -> bool: return is_equal_approx(panel.value("drawn_wind"), 18.0)],
		["--drawn-wind=0", func() -> bool: return panel.value("drawn_wind") == 0.0],
		["--breathing=off", func() -> bool: return not sc.rig.chase.breathing and panel.value("breathing") == false],
		["--breathing=on", func() -> bool: return panel.value("breathing") == true],
		["--no-drawn-shadows", func() -> bool: return not sc.shadows.enabled and panel.value("drawn_shadows") == false],
		["--no-boat-shadows", func() -> bool: return panel.value("boat_shadows") == false],
		["--render-scale=75", func() -> bool: return is_equal_approx(root.scaling_3d_scale, 0.75) and is_equal_approx(panel.value("render_scale"), 0.75)],
	]
	for c in checks:
		t.ok(DevLook.apply_flag(sc, c[0]) and (c[1] as Callable).call(), "%s" % c[0])
	t.ok(not DevLook.apply_flag(sc, "--race"), "other flags left to the scene")
	DevLook.set_drawn_shadows(sc, true)
	DevLook.set_boat_shadows(sc, true)
	DevLook.set_render_scale(sc, 0.0)


func test_restart() -> void:
	t.begin("restart with a wind (core)")
	var cs0: CoreSimSource = sc.sim
	var hs0: float = sc.sea.model.hs_eff
	panel.rows[panel.row_index("wind")]["set"].call(20.0)
	t.ok(panel.value_text("restart") == "20 kn", "the action names the wind (%s)" % panel.value_text("restart"))
	panel.activate("restart")
	_frames(3)
	var cs: CoreSimSource = sc.sim
	var w: Dictionary = cs.wind_state(cs.render_time_ms(0.0))
	t.ok(cs != cs0 and sc.wind_speed_kn == 20.0, "a new world with 20 kn")
	t.near(float(w["base_speed"]) / HudFormat.KNOT, 20.0, 0.05, "the core's base wind is 20 kn")
	t.ok(sc.sea.model.hs_eff > hs0, "the sea follows it (Hs %.2f m, was %.2f m)" % [sc.sea.model.hs_eff, hs0])
	t.ok(not sc.race_mode and sc.sim.boat_count() == 1, "still free sailing")
	t.ok(sc.sea.quality == SeaQuality.Tier.M and sc.sky.conditions == "fair", "the look kept")
	panel.rows[panel.row_index("wind")]["set"].call(12.0)
	panel.activate("restart")
	_frames(2)
	t.near(float(sc.sim.wind_state(sc.sim.render_time_ms(0.0))["base_speed"]) / HudFormat.KNOT, 12.0, 0.05,
		"and back to 12 kn")


func test_focus() -> void:
	t.begin("the boat's keys only while the panel has no focus")
	var r: RawInput = sc.scripted_input
	var pc: PlayerControls = sc.controls
	panel.close()
	await process_frame
	pc.h_cmd = 0.0
	r.held = {}
	r.hold(&"helm_right")
	_frames(20)
	t.ok(pc.h_cmd > 0.05, "closed: the helm key steers (h_cmd %.2f)" % pc.h_cmd)
	r.held = {}
	_frames(2)
	pc.h_cmd = 0.0
	panel.open()
	var tick0: int = sc.sim.tick()
	r.hold(&"helm_right")
	_frames(30)
	t.ok(pc.h_cmd == 0.0, "focused: the helm key does not steer (h_cmd %.2f)" % pc.h_cmd)
	t.ok(sc.sim.tick() > tick0, "the simulation keeps running (%d ticks)" % (sc.sim.tick() - tick0))
	# Esc gives the keys back; the same frame's Esc does not pause the scene
	r.pressed = [&"pause_menu"]
	r.held[&"pause_menu"] = true
	_key(KEY_ESCAPE)
	t.ok(panel.is_open and not panel.focused and panel.blocks_input(), "Esc: open, focus given back, this frame still blocked")
	sc.step_frame(DT)
	t.ok(not sc.runner.paused, "the Esc did not pause the scene")
	r.pressed = []
	r.held.erase(&"pause_menu")
	await process_frame
	t.ok(not panel.blocks_input(), "next frame: keys with the boat")
	_frames(20)
	t.ok(pc.h_cmd > 0.05, "open without focus: the helm key steers (h_cmd %.2f)" % pc.h_cmd)
	_key(KEY_F9)
	t.ok(panel.focused, "F9 on the open panel takes the focus again")
	r.held = {}
	panel.close()


func _restore_statics() -> void:
	Settings.aa_override = ""
	Settings.quality_override = -1
	Settings.render_scale_override = 0.0
	LookFx.enabled = true
	LookFx.ssao_override = -1
	LookFx.dof_enabled = true
	LookFx.grade_strength = 1.0
	LookFx.vignette_scale = 1.0
