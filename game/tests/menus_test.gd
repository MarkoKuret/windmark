extends SceneTree
## Menus tests (menus.md): the lists come from the data on disk, a quick race and a free sail write GameSetup and
## ask for the sail scene, keyboard navigation reaches and changes the rows, the settings file round-trips, the
## apply calls reach their targets, and the pause menu follows the sail scene's pause. Headless.
##   godot --headless --path game -s res://tests/menus_test.gd

const TEST_PATH := "user://menus_test_settings.cfg"

var t := TestLog.new()


func _init() -> void:
	Settings.path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	Settings.reset_current()
	test_data()
	test_settings_round_trip()
	test_apply()
	await test_main_menu()
	await test_pause_menu()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	t.finish(self, "menus")


func _disk_ids(dir: String, suffix: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(suffix):
			out.append(f.trim_suffix(suffix))
	out.sort()
	return out


func test_data() -> void:
	t.begin("lists from the data on disk")
	var cls := MenuData.ids(MenuData.classes())
	var disk := _disk_ids(BoatClassData.repo_path("data/classes"), ".boat.json")
	var sorted := cls.duplicate()
	sorted.sort()
	t.ok(sorted == disk and disk.size() >= 2, "classes %s = files %s" % [cls, disk])
	t.ok(MenuData.names(MenuData.classes()).has("Windmark 7 Sportsboat"), "class names from the class files")
	var ven := MenuData.ids(MenuData.venues())
	t.ok(ven.has("example_bay") and ven.size() == _disk_ids(BoatClassData.repo_path("data/venues"),
		".venue.json").size(), "venues %s" % [ven])
	var c7 := MenuData.ids(MenuData.courses("example_bay", "wm7"))
	t.ok(c7.has("example_bay/example_wl"), "example_bay courses for wm7: %s" % [c7])
	t.ok(MenuData.courses("example_bay", "no_such_class").is_empty(), "no course lists an unknown class")
	t.ok(MenuData.courses("no_such_venue", "wm7").is_empty(), "no courses for an unknown venue")


func _odd_settings() -> Settings:
	var s := Settings.new()
	s.helm_mode = PlayerControls.HelmMode.HOLD_TO_STEER
	s.stick_dead_zone = 0.2
	s.stick_curve = 2.2
	s.sheet_rate = 1.5
	s.let_fly_toggle = true
	s.helm_fine_toggle = true
	s.rankings_toggle = true
	s.camera_boost_toggle = true
	s.sheet_turns_auto_trim_off = true
	s.vibration = 0.3
	s.camera_speed = 1.75
	s.invert_orbit_x = true
	s.invert_orbit_y = true
	s.invert_look_x = true
	s.invert_look_y = true
	s.heel_follow = 0.4
	s.smooth_switch = true
	s.reduced_motion = true
	s.assist = Hud.Assist.MINIMAL
	s.hud_density = Hud.Density.DATA
	s.ui_scale = 1.15
	s.palette = "tritanopia"
	s.captions = true
	s.quality = SeaQuality.Tier.H
	s.render_scale = 0.75
	s.fullscreen = true
	s.vsync = false
	s.fps_limit = 90
	s.capture_preset = "portrait"
	s.master_volume = 0.5
	s.effects_volume = 0.25
	s.signals_volume = 0.75
	s.voice_volume = 0.1
	s.ambience_volume = 0.0
	s.interface_volume = 0.6
	s.last_setup = {"class_id": "wm12", "fleet_size": 7}
	return s


func test_settings_round_trip() -> void:
	t.begin("settings save and load")
	var fresh := Settings.new()
	var s := _odd_settings()
	var differs := 0
	for sec in Settings.FIELDS:
		for f in Settings.FIELDS[sec]:
			if s.get(f) != fresh.get(f):
				differs += 1
			else:
				t.ok(false, "test value of %s is its default" % f)
	t.ok(s.save_file(TEST_PATH) == OK, "saved")
	var back := Settings.new()
	t.ok(back.load_file(TEST_PATH) == OK, "loaded")
	t.ok(back.to_dict() == s.to_dict(), "every field back (%d fields)" % differs)
	var cf := ConfigFile.new()
	cf.load(TEST_PATH)
	t.ok(cf.get_value("settings", "version", 0) == Settings.VERSION, "file carries its version")
	# a damaged file: wrong types keep the defaults, out-of-range values are clamped
	cf.set_value("controls", "stick_dead_zone", "wide")
	cf.set_value("controls", "stick_curve", 9.0)
	cf.set_value("hud", "assist", 7)
	cf.set_value("graphics", "vsync", 3)
	cf.set_value("graphics", "render_scale", 7)
	t.ok(not cf.has_section_key("graphics", "capture_preset") and back.capture_preset == "off",
		"the capture preset is session only: not saved, Off after a load (menus.md §3)")
	cf.set_value("graphics", "capture_preset", "portrait")
	cf.save(TEST_PATH)
	var d := Settings.new()
	d.load_file(TEST_PATH)
	t.near(d.stick_dead_zone, 0.10, 1e-9, "wrong type keeps the default")
	t.near(d.stick_curve, 3.0, 1e-9, "curve clamped to 3.0")
	t.ok(d.assist == Hud.Assist.MINIMAL, "assist clamped to Minimal")
	t.ok(d.vsync == true, "vsync of the wrong type keeps the default")
	t.near(d.render_scale, 1.0, 1e-9, "render scale clamped to 100 %")
	t.ok(d.capture_preset == "off", "a capture preset in an older file is ignored: the game starts with it Off")
	t.ok(Settings.new().capture_preset == "off", "capture preset defaults to Off")
	t.near(Settings.new().render_scale, 0.0, 0.0, "render scale defaults to Auto")
	t.ok(Settings.new().load_file("user://no_such_settings.cfg") != OK, "missing file: defaults")
	s.reset("audio")
	t.near(s.master_volume, fresh.master_volume, 1e-9, "reset a section: audio back to defaults")
	t.ok(s.fps_limit == 90, "reset a section keeps the others")
	s.reset("graphics")
	t.ok(s.capture_preset == "off", "reset graphics turns the capture preset off")
	var u := _odd_settings()
	u.reset("audio")
	t.ok(u.capture_preset == "portrait", "reset of another section keeps the capture preset")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func test_apply() -> void:
	t.begin("apply reaches its targets")
	var s := _odd_settings()
	var pc := PlayerControls.new()
	s.apply_controls(pc)
	t.ok(pc.helm_mode == PlayerControls.HelmMode.HOLD_TO_STEER, "controls: helm key mode")
	t.near(pc.stick_dead_zone, 0.2, 1e-9, "controls: stick dead zone")
	t.near(pc.stick_gamma, 2.2, 1e-9, "controls: stick curve")
	t.near(pc.sheet_rate_scale, 1.5, 1e-9, "controls: sheet rate")
	t.ok(pc.let_fly_toggle and pc.helm_fine_toggle and pc.sheet_turns_auto_trim_off, "controls: toggles")
	var rig := CameraRig.new()
	s.apply_cameras(rig)
	var o := rig.options
	t.near(o.speed, 1.75, 1e-9, "cameras: speed")
	t.ok(o.invert_orbit_x and o.invert_orbit_y and o.invert_look_x and o.invert_look_y, "cameras: invert")
	t.ok(o.smooth_switch and o.reduced_motion, "cameras: smooth switch, reduced motion")
	t.near(rig.onboard.heel_follow, 0.4, 1e-9, "cameras: onboard heel follow")
	rig.call("free")
	var hud := Hud.new()
	s.apply_hud(hud)
	t.ok(hud.assist == Hud.Assist.MINIMAL, "HUD: assist preset")
	hud.free()
	var sea := (load("res://scenes/sea/sea.tscn") as PackedScene).instantiate() as Sea
	s.apply_sea(sea)
	t.ok(sea.quality == SeaQuality.Tier.H, "sea: quality tier")
	sea.free()
	var fps := Engine.max_fps
	var scale := root.content_scale_factor
	s.apply_display(root)
	t.ok(Engine.max_fps == 90, "display: frame rate limit")
	t.near(root.content_scale_factor, 1.15, 1e-6, "display: UI scale")
	Engine.max_fps = fps
	root.content_scale_factor = scale
	test_render_scale(s)
	s.apply_audio()
	var m := AudioServer.get_bus_index("Master")
	t.near(AudioServer.get_bus_volume_db(m), linear_to_db(0.5), 1e-3, "audio: master volume")
	Settings.new().apply_audio()


## menus.md §3 render scale: the setting on the root viewport's 3D scale and upscaler, the 2D untouched, Auto's
## rule, the command-line override.
func test_render_scale(s: Settings) -> void:
	var sc0 := root.scaling_3d_scale
	var mode0 := root.scaling_3d_mode
	var cs0 := root.content_scale_factor
	s.apply_display(root)
	t.near(root.scaling_3d_scale, 0.75, 1e-6, "render scale: 75 % on the viewport's 3D scale")
	var rd := RenderingServer.get_current_rendering_method() in ["forward_plus", "mobile"]
	t.ok(root.scaling_3d_mode == (Viewport.SCALING_3D_MODE_FSR if rd else Viewport.SCALING_3D_MODE_BILINEAR),
		"render scale: FSR 1.0 upscales on %s (mode %d)" % [RenderingServer.get_current_rendering_method(),
		root.scaling_3d_mode])
	t.near(root.content_scale_factor, 1.15, 1e-6, "render scale leaves the 2D (UI scale) alone")
	var a := Settings.new()
	a.render_scale = 0.0
	a.apply_render_scale(root)
	var want := Settings.auto_render_scale(root.size, DisplayServer.screen_get_scale())
	t.near(root.scaling_3d_scale, want, 1e-6, "Auto on a %s window: %.2f" % [root.size, want])
	a.render_scale = 1.0
	a.apply_render_scale(root)
	t.ok(root.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR and absf(root.scaling_3d_scale - 1.0) < 1e-6,
		"100 %: no upscaler")
	# water_render.md §7: SMAA at every scale and upscaler, off only under a temporal upscaler
	t.ok(root.screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA, "100 %%: SMAA (screen-space AA %d)" % root.screen_space_aa)
	t.ok(int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa")) == Viewport.SCREEN_SPACE_AA_SMAA,
		"project default: SMAA from start-up")
	for m in [Viewport.SCALING_3D_MODE_BILINEAR, Viewport.SCALING_3D_MODE_FSR, Viewport.SCALING_3D_MODE_METALFX_SPATIAL]:
		t.ok(Settings.screen_space_aa(m) == Viewport.SCREEN_SPACE_AA_SMAA, "SMAA with %s" % Settings.upscaler_name(m))
	for m in [Viewport.SCALING_3D_MODE_FSR2, Viewport.SCALING_3D_MODE_METALFX_TEMPORAL]:
		t.ok(Settings.screen_space_aa(m) == Viewport.SCREEN_SPACE_AA_DISABLED, "no SMAA under %s" % Settings.upscaler_name(m))
	Settings.aa_override = "fxaa"
	t.ok(Settings.screen_space_aa(Viewport.SCALING_3D_MODE_FSR) == Viewport.SCREEN_SPACE_AA_FXAA, "--aa=fxaa for this run")
	Settings.aa_override = ""
	for c in [[Vector2i(2560, 1600), 2.0, 0.67], [Vector2i(2560, 1600), 1.0, 0.67], [Vector2i(2880, 1800), 2.0, 0.67],
			[Vector2i(3840, 2160), 1.0, 0.5301], [Vector2i(6880, 2880), 1.0, 0.3430],
			[Vector2i(1920, 1200), 1.0, 1.0], [Vector2i(1920, 1080), 1.0, 1.0], [Vector2i(1280, 800), 1.0, 1.0],
			[Vector2i(1280, 800), 2.0, 1.0], [Vector2i(1440, 900), 2.0, 0.67], [Vector2i(2560, 1080), 1.0, 0.67]]:
		t.near(Settings.auto_render_scale(c[0], c[1]), c[2], 1e-3, "Auto at %s, screen scale %.1f" % [c[0], c[1]])
	# the portrait capture preset (menus.md §3): Auto picks 100 %, the window is 1080 x 1920 or the largest 9:16
	a.render_scale = 0.0
	a.capture_preset = "portrait"
	t.near(a.effective_render_scale(root), 1.0, 1e-9, "capture preset: Auto picks 100 %")
	a.render_scale = 0.75
	t.near(a.effective_render_scale(root), 0.75, 1e-9, "capture preset: a chosen render scale stays")
	a.capture_preset = "off"
	a.render_scale = 1.0
	for c in [[Vector2i(2560, 1950), Vector2i(1080, 1920)], [Vector2i(3840, 2100), Vector2i(1080, 1920)],
			[Vector2i(1920, 1050), Vector2i(590, 1050)], [Vector2i(1440, 875), Vector2i(492, 875)],
			[Vector2i(500, 1920), Vector2i(500, 888)]]:
		t.ok(Settings.capture_window_size(c[0]) == c[1], "portrait window on a %s usable area: %s (%s)" % [c[0],
			c[1], Settings.capture_window_size(c[0])])
	# on, off: the window gets its previous size back, centred in the usable area
	var usable := Rect2i(Vector2i(0, 25), Vector2i(2560, 1950))
	var w := Settings.new()
	t.ok(w.capture_window_rect(Vector2i(1600, 900), usable) == Rect2i(), "Off: no change")
	w.capture_preset = "portrait"
	t.ok(w.capture_window_rect(Vector2i(1600, 900), usable) == Rect2i(Vector2i(740, 40), Vector2i(1080, 1920)),
		"Portrait: 1080 x 1920 centred")
	t.ok(w.capture_window_rect(Vector2i(1080, 1920), usable) == Rect2i(), "Portrait again: no change")
	w.capture_preset = "off"
	t.ok(w.capture_window_rect(Vector2i(1080, 1920), usable) == Rect2i(Vector2i(480, 550), Vector2i(1600, 900)),
		"Off: the previous 1600 x 900 back, centred")
	t.ok(w.capture_window_rect(Vector2i(1600, 900), usable) == Rect2i(), "Off again: nothing remembered")
	Settings.render_scale_override = 0.5
	a.apply_render_scale(root)
	t.near(root.scaling_3d_scale, 0.5, 1e-6, "command-line override replaces the setting")
	Settings.upscaler_override = "bilinear"
	a.apply_render_scale(root)
	t.ok(root.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR, "command-line upscaler override")
	Settings.render_scale_override = 0.0
	Settings.upscaler_override = ""
	root.scaling_3d_scale = sc0
	root.scaling_3d_mode = mode0
	root.content_scale_factor = cs0


func _key(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	root.push_input(e)
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	root.push_input(r)


func test_main_menu() -> void:
	t.begin("main menu: quick race and free sail")
	Settings.reset_current()
	var m := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	m.change_scenes = false
	var asked: Array[String] = []
	m.scene_requested.connect(func(p: String) -> void: asked.append(p))
	root.add_child(m)
	await process_frame
	await process_frame
	t.ok(root.gui_get_focus_owner() == m.buttons["quick"], "focus starts on Quick race")
	var q := m.quick
	t.ok(q.rows["class_id"].choices == MenuData.ids(MenuData.classes()), "quick race: classes from disk")
	t.ok(q.rows["venue"].choices == MenuData.ids(MenuData.venues()), "quick race: venues from disk")
	t.ok(q.rows["course"].choices.has("example_bay/example_wl"), "quick race: the venue's courses")
	t.ok(q.rows["livery"].choices == MenuData.ids(MenuData.liveries(str(q.rows["class_id"].value)))
		and q.rows["livery"].choices.size() >= 12, "quick race: the class's boats (sail numbers) from disk")
	# keyboard: Enter opens the page, the focus lands on the first row, down and right change the fleet size
	_key("ui_accept")
	await process_frame
	await process_frame
	t.ok(m.page == "quick" and m.quick.is_visible_in_tree(), "Enter opens Quick race")
	t.ok(root.gui_get_focus_owner() == q.rows["class_id"], "focus on the first row")
	for i in 4:
		_key("ui_down")
		await process_frame
	t.ok(root.gui_get_focus_owner() == q.rows["fleet_size"], "down x4 reaches the fleet row")
	var fleet := int(q.rows["fleet_size"].value)
	_key("ui_right")
	_key("ui_right")
	await process_frame
	t.ok(int(q.rows["fleet_size"].value) == fleet + 2, "right x2: fleet %d -> %d" % [fleet, q.rows["fleet_size"].value])
	q.rows["class_id"].set_value("wm12", true)
	t.ok(q.rows["livery"].choices == MenuData.ids(MenuData.liveries("wm12")), "the sail number list follows the class")
	q.rows["livery"].set_value("nightjar", true)
	q.rows["ai_level"].set_value("pro", true)
	q.rows["wind_kn"].set_value(15.0, true)
	q.rows["wind_from_deg"].set_value(90.0, true)
	q.start_button.pressed.emit()
	var g := GameSetup.current()
	t.ok(g.mode == "race" and g.class_id == "wm12" and g.venue == "example_bay", "GameSetup: race, wm12, venue")
	t.ok(g.course == "example_bay/example_wl" and g.fleet_size == fleet + 2 and g.ai_level == "pro",
		"GameSetup: course, fleet, AI level")
	t.ok(g.livery == "nightjar", "GameSetup: the chosen boat")
	t.near(g.wind_kn, 15.0, 1e-9, "GameSetup: wind speed")
	t.near(g.wind_from_deg, 90.0, 1e-9, "GameSetup: wind direction")
	t.ok(asked == [MainMenu.SAIL_SCENE], "sail scene requested: %s" % [asked])
	var saved := Settings.new()
	saved.load_file(TEST_PATH)
	t.ok(saved.last_setup.get("fleet_size", 0) == fleet + 2, "last setup remembered in the settings file")
	# Esc goes back to the menu, then Free sail
	_key("ui_cancel")
	await process_frame
	t.ok(m.page == "" and root.gui_get_focus_owner() == m.buttons["quick"], "Esc back to the menu")
	m.buttons["free"].pressed.emit()
	await process_frame
	m.free_sail.rows["wind_kn"].set_value(8.0, true)
	m.free_sail.start_button.pressed.emit()
	t.ok(g.mode == "free" and g.class_id == "wm12" and absf(g.wind_kn - 8.0) < 1e-9,
		"free sail: mode free, the remembered class, its wind")
	t.ok(asked.size() == 2 and asked[1] == MainMenu.SAIL_SCENE, "sail scene requested again")
	# settings page: a change is saved on close
	m.close_page()
	m.open_page("settings")
	await process_frame
	m.settings_panel.show_section("graphics")
	m.settings_panel.rows["fps_limit"].set_value(60, true)
	t.ok(Engine.max_fps == 60, "frame rate limit applied at once")
	m.settings_panel.close()
	saved.load_file(TEST_PATH)
	t.ok(saved.fps_limit == 60 and m.page == "", "settings saved on close")
	Engine.max_fps = 0
	# render scale from the settings screen: applied to the viewport at once, saved on close
	m.open_page("settings")
	await process_frame
	m.settings_panel.show_section("graphics")
	var rs_row: MenuRow = m.settings_panel.rows.get("render_scale")
	t.ok(rs_row != null and rs_row.choices == Settings.RENDER_SCALES, "graphics: render scale row with its choices")
	if rs_row != null:
		t.ok(String(rs_row.names[0]).begins_with("Auto ("), "the Auto choice shows its pick: %s" % rs_row.names[0])
		rs_row.set_value(0.67, true)
		t.near(root.scaling_3d_scale, 0.67, 1e-6, "render scale 67 % applied to the viewport at once")
		m.settings_panel.close()
		saved.load_file(TEST_PATH)
		t.near(saved.render_scale, 0.67, 1e-9, "render scale saved on close")
		m.settings.render_scale = 0.0
		m.settings.apply_display(root)
	# every section builds its rows, the bindings are shown
	for sec in SettingsPanel.SECTIONS:
		m.settings_panel.show_section(sec)
		t.ok(m.settings_panel.rows.size() > 0, "section %s has rows" % sec)
	m.settings_panel.show_section("controls")
	t.ok(SettingsPanel.binding_text("let_fly").contains("Space") and SettingsPanel.binding_text("let_fly").contains("A"),
		"bindings shown: let fly = %s" % SettingsPanel.binding_text("let_fly"))
	# Steam Deck and the portrait capture window: every page inside 1280 x 800 and 1080 x 1920 at 80 %, 100 %
	# and 130 %
	for scr in [Vector2i(1280, 800), Vector2i(1080, 1920)]:
		root.size = scr
		for sc in [0.8, 1.0, 1.3]:
			m.settings.ui_scale = sc
			m.settings.apply_display(root)
			for p in ["quick", "free", "settings"]:
				m.open_page(p)
				await process_frame
				await process_frame
				var vis := root.get_visible_rect().grow(1)
				var need: Array = [m.buttons["quit"], m._panel]
				need.append(m.settings_panel.get_child(-1) if p == "settings"
					else (m.quick if p == "quick" else m.free_sail).start_button)
				var inside := true
				for c in need:
					inside = inside and vis.encloses((c as Control).get_global_rect())
				if not inside:
					print("  vis %s: %s" % [vis, need.map(func(c: Control) -> Rect2: return c.get_global_rect())])
				t.ok(inside, "%s page within %s at %d %%" % [p, scr, roundi(sc * 100)])
				m.close_page()
	m.settings.ui_scale = 1.0
	root.content_scale_factor = 1.0
	m.queue_free()
	await process_frame
	Settings.reset_current()


func test_pause_menu() -> void:
	t.begin("pause menu over the sail scene")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	Settings.reset_current()
	var st := Settings.current()
	st.helm_mode = PlayerControls.HelmMode.HOLD_TO_STEER
	st.quality = SeaQuality.Tier.L
	st.heel_follow = 0.5
	var packed := load("res://scenes/sail_test.tscn") as PackedScene
	var sc := packed.instantiate()
	sc.auto_process = false
	sc.sim_kind = sc.SimKind.FAKE
	root.add_child(sc)
	await process_frame
	# the one line the sail scene adds
	sc.add_child(preload("res://scenes/menu/pause_menu.tscn").instantiate())
	var pm := sc.get_node("PauseMenu") as PauseMenu
	pm.act = false
	await process_frame
	t.ok(sc.controls.helm_mode == PlayerControls.HelmMode.HOLD_TO_STEER, "settings applied to the controls")
	t.ok(sc.sea.quality == SeaQuality.Tier.L, "settings applied to the sea tier")
	t.near(sc.rig.onboard.heel_follow, 0.5, 1e-9, "settings applied to the onboard camera")
	t.ok(not pm.is_open, "closed at start")
	# the scene's own pause key opens it
	sc.scripted_input = RawInput.new().press(&"pause_menu")
	sc.step_frame(1.0 / 60.0)
	sc.scripted_input = RawInput.new()
	await process_frame
	t.ok(sc.runner.paused and pm.is_open, "pause key: simulation paused, menu open")
	t.ok(sc.controls.menu_open, "boat controls held while open")
	var paused_label := sc.get_node_or_null("HudLayer/Paused") as CanvasItem
	t.ok(paused_label == null or not paused_label.visible, "the scene's own Paused line hidden")
	var tick: int = sc.sim.tick()
	for i in 10:
		sc.step_frame(1.0 / 60.0)
	t.ok(sc.sim.tick() == tick, "no ticks while paused")
	pm.buttons["resume"].pressed.emit()
	t.ok(not sc.runner.paused and not pm.is_open and not sc.controls.menu_open, "Resume: running again")
	# settings from the pause menu reach the scene when they close
	sc.scripted_input = RawInput.new().press(&"pause_menu")
	sc.step_frame(1.0 / 60.0)
	sc.scripted_input = RawInput.new()
	await process_frame
	pm.buttons["settings"].pressed.emit()
	pm.settings_panel.show_section("controls")
	pm.settings_panel.rows["stick_dead_zone"].set_value(0.25, true)
	pm.settings_panel.show_section("hud")
	pm.settings_panel.rows["assist"].set_value(Hud.Assist.FULL, true)
	pm.settings_panel.close()
	t.near(sc.controls.stick_dead_zone, 0.25, 1e-9, "dead zone applied to the running scene")
	t.ok(sc.hud.assist == Hud.Assist.FULL, "assist preset applied to the running scene")
	t.ok(pm.is_open and pm.buttons["settings"].is_visible_in_tree(), "back on the pause menu")
	# pause key again closes it
	sc.scripted_input = RawInput.new().press(&"pause_menu")
	sc.step_frame(1.0 / 60.0)
	sc.scripted_input = RawInput.new()
	await process_frame
	t.ok(not pm.is_open and not sc.runner.paused, "pause key again resumes")
	var acts: Array[String] = []
	pm.action_requested.connect(func(a: String) -> void: acts.append(a))
	pm.open()
	pm.buttons["restart"].pressed.emit()
	pm.open()
	pm.buttons["quit"].pressed.emit()
	t.ok(acts == ["restart", "quit"] and not pm.is_open, "restart and quit to menu requested: %s" % [acts])
	sc.queue_free()
	await process_frame
