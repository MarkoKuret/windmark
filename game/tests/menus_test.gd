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
	test_look()
	test_settings_round_trip()
	test_device_defaults()
	test_apply()
	test_every_key_applied()
	await test_rebinding()
	await test_live_backdrop()
	await test_main_menu()
	await test_race_card()
	test_briefing()
	await test_weather_card()
	await test_touches()
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
	t.ok(ven.has("practice_waters") and ven.size() == _disk_ids(BoatClassData.repo_path("data/venues"),
		".venue.json").size(), "venues %s" % [ven])
	var c7 := MenuData.ids(MenuData.courses("practice_waters", "wm7"))
	t.ok(c7.has("practice_waters/example_wl"), "practice_waters courses for wm7: %s" % [c7])
	t.ok(MenuData.courses("practice_waters", "no_such_class").is_empty(), "no course lists an unknown class")
	t.ok(MenuData.courses("no_such_venue", "wm7").is_empty(), "no courses for an unknown venue")


## menus.md §4: one accent (the HUD's yellow) as a fill with navy text, red only for destructive actions, the
## HUD's type.
static func _lum(c: Color) -> float:
	var l := func(x: float) -> float: return x / 12.92 if x <= 0.03928 else pow((x + 0.055) / 1.055, 2.4)
	return 0.2126 * l.call(c.r) + 0.7152 * l.call(c.g) + 0.0722 * l.call(c.b)


static func contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func test_look() -> void:
	t.begin("look: one accent, red for destructive actions, Barlow")
	t.ok(MenuTheme.ACCENT == HudStyle.MARK, "menu accent is the HUD's mark yellow")
	var cloth := MenuTheme.CLOTH_SOLID
	t.ok(contrast(MenuTheme.NAVY, MenuTheme.ACCENT) >= 4.5, "navy text on the yellow fill: %.1f:1"
		% contrast(MenuTheme.NAVY, MenuTheme.ACCENT))
	t.ok(contrast(MenuTheme.NAVY, cloth) >= 4.5 and contrast(MenuTheme.MUTED, cloth) >= 4.5,
		"navy and muted text on the cloth: %.1f:1, %.1f:1" % [contrast(MenuTheme.NAVY, cloth),
		contrast(MenuTheme.MUTED, cloth)])
	t.ok(contrast(MenuTheme.SIGNAL, cloth) >= 4.5, "red text on the cloth (and cloth text on red): %.1f:1"
		% contrast(MenuTheme.SIGNAL, cloth))
	var th := MenuTheme.theme()
	var focus := th.get_stylebox("focus", "Button") as StyleBoxFlat
	t.ok(focus.bg_color == MenuTheme.ACCENT and th.get_color("font_focus_color", "Button") == MenuTheme.NAVY,
		"focused button: yellow fill, navy text")
	var quit := MenuTheme.button("Quit", MenuTheme.ITEM_SIZE, true)
	t.ok(quit.get_theme_color("font_color") == MenuTheme.SIGNAL and quit.text == "QUIT", "Quit: red caps")
	var f := quit.get_theme_font("font") as FontVariation
	t.ok(f != null and f.base_font.resource_path.ends_with("BarlowSemiCondensed-Bold.ttf"), "buttons in Barlow Bold")
	quit.free()
	var r := MenuRow.range_row("Wind speed", "wind_kn", 4, 25, 1, 12.0, func(v: float) -> String: return "%d kn" % v)
	var vf := r._value.get_theme_font("font") as FontVariation
	t.ok(r._name.text == "WIND SPEED" and vf != null and vf.opentype_features.size() > 0,
		"rows: caps names, tabular values")
	r.free()


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
	s.welcomed = true
	s.bindings = {"let_fly": [["key", KEY_Q, ""], [], ["button", JOY_BUTTON_Y]]}
	return s


## menus.md §3 device defaults: the adapter class from injected names, and what a first start picks for it.
func test_device_defaults() -> void:
	t.begin("settings: device defaults at the first start")
	var I := Settings.Gpu.INTEGRATED
	var D := Settings.Gpu.DISCRETE
	var IG := RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU
	var DG := RenderingDevice.DEVICE_TYPE_DISCRETE_GPU
	var cases := [
		# adapter, vendor, device type, Steam Deck, class
		["Intel(R) UHD Graphics 620", "Intel", IG, false, I],
		["Intel(R) Iris(R) Xe Graphics", "Intel", IG, false, I],
		["Intel(R) HD Graphics 520", "Intel", -1, false, I],
		["Mesa Intel(R) UHD Graphics 620 (KBL GT2)", "Intel", IG, false, I],
		["Intel(R) Arc(TM) Graphics", "Intel", IG, false, I],
		["Intel(R) Arc(TM) A770 Graphics", "Intel", DG, false, D],
		["Intel(R) Arc(TM) B580 Graphics", "Intel", -1, false, D],
		["AMD Radeon(TM) Graphics", "AMD", IG, false, I],
		["AMD Radeon(TM) Vega 8 Graphics", "AMD", -1, false, I],
		["AMD Radeon(TM) RX Vega 10 Graphics", "AMD", IG, false, I],
		["AMD Radeon 780M", "AMD", -1, false, I],
		["AMD Radeon Graphics (RADV RENOIR)", "AMD", IG, false, I],
		["AMD Radeon RX 6600", "AMD", DG, false, D],
		["AMD Radeon RX 7600M XT", "AMD", DG, false, D],
		["AMD Radeon Pro 5500M", "AMD", DG, false, D],
		["NVIDIA GeForce RTX 3060", "NVIDIA", DG, false, D],
		["NVIDIA GeForce MX450", "NVIDIA", DG, false, D],
		["Apple M1", "Apple", IG, false, Settings.Gpu.APPLE],
		["Apple M5", "Apple", -1, false, Settings.Gpu.APPLE],
		["AMD Custom GPU 0405 (RADV VANGOGH)", "AMD", IG, false, Settings.Gpu.STEAM_DECK],
		["AMD Custom GPU 0932", "AMD", IG, false, Settings.Gpu.STEAM_DECK],
		["AMD Radeon Graphics", "AMD", IG, true, Settings.Gpu.STEAM_DECK],
		["llvmpipe (LLVM 15.0.7, 256 bits)", "Mesa", RenderingDevice.DEVICE_TYPE_CPU, false, I],
		["Qualcomm(R) Adreno(TM) X1-85 GPU", "Qualcomm", IG, false, I],
		["Some New GPU", "Unknown", IG, false, I],
		["Some New GPU", "Unknown", DG, false, D],
		["", "", -1, false, Settings.Gpu.UNKNOWN],
	]
	var wrong := []
	for c in cases:
		var got := Settings.gpu_class(c[0], c[1], c[2], c[3])
		if got != c[4]:
			wrong.append("%s -> %s (want %s)" % [c[0], Settings.Gpu.keys()[got], Settings.Gpu.keys()[c[4]]])
	t.ok(wrong.is_empty(), "adapter classes from %d names %s" % [cases.size(), wrong])
	var g := Settings.device_graphics(I)
	t.ok(g["quality"] == SeaQuality.Tier.L and is_equal_approx(g["render_scale"], 0.67), "integrated: tier L at 67 %")
	g = Settings.device_graphics(Settings.Gpu.STEAM_DECK)
	t.ok(g["quality"] == SeaQuality.Tier.L and g["render_scale"] == 0.0, "Steam Deck: tier L, Auto (native)")
	for k in [D, Settings.Gpu.APPLE, Settings.Gpu.UNKNOWN]:
		g = Settings.device_graphics(k)
		t.ok(g["quality"] == SeaQuality.Tier.M and g["render_scale"] == 0.0,
			"%s: today's defaults (M, Auto)" % Settings.Gpu.keys()[k])
	# the first start: no file, so the detected device decides; a file keeps the player's values
	var first := "user://menus_test_first_start.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(first))
	Settings.path = first
	Settings.gpu_override = I
	Settings.reset_current()
	var s := Settings.current()
	t.ok(s.quality == SeaQuality.Tier.L and is_equal_approx(s.render_scale, 0.67),
		"first start on an integrated GPU: tier L at 67 %")
	s.quality = SeaQuality.Tier.H
	s.render_scale = 1.0
	s.save_file()
	Settings.reset_current()
	s = Settings.current()
	t.ok(s.quality == SeaQuality.Tier.H and s.render_scale == 1.0, "a saved file keeps the player's choice")
	s.reset("graphics")
	t.ok(s.quality == SeaQuality.Tier.L and is_equal_approx(s.render_scale, 0.67), "Reset Graphics: the device defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(first))
	Settings.gpu_override = Settings.Gpu.APPLE
	Settings.reset_current()
	s = Settings.current()
	t.ok(s.quality == SeaQuality.Tier.M and s.render_scale == 0.0, "first start on Apple silicon: M, Auto")
	Settings.gpu_override = Settings.Gpu.STEAM_DECK
	Settings.reset_current()
	s = Settings.current()
	t.ok(s.quality == SeaQuality.Tier.L and s.render_scale == 0.0, "first start on a Steam Deck: L, Auto")
	Settings.gpu_override = -1
	Settings.path = TEST_PATH
	Settings.reset_current()


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


class StubSim extends SimSource:
	var ev := []

	func contact_events() -> Array:
		return ev


## menus.md §3 "Where each setting goes": every key of the settings file reaches its target, except the ones
## NOT_APPLIED lists (captions: the audio has no caption lines yet).
func test_every_key_applied() -> void:
	t.begin("every setting is applied")
	var s := _odd_settings()
	var fresh := Settings.new()
	var pc := PlayerControls.new()
	s.apply_controls(pc)
	var rig := CameraRig.new()
	s.apply_cameras(rig)
	var hud := Hud.new()
	s.apply_hud(hud)
	var sea := (load("res://scenes/sea/sea.tscn") as PackedScene).instantiate() as Sea
	s.apply_sea(sea)
	var fps := Engine.max_fps
	var cs := root.content_scale_factor
	var sc3 := root.scaling_3d_scale
	s.apply_display(root)
	s.apply_audio()
	s.apply_bindings()
	var bus := func(n: String) -> float: return db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(n)))
	var got := {
		"controls.helm_mode": pc.helm_mode == s.helm_mode,
		"controls.stick_dead_zone": is_equal_approx(pc.stick_dead_zone, s.stick_dead_zone),
		"controls.stick_curve": is_equal_approx(pc.stick_gamma, s.stick_curve),
		"controls.sheet_rate": is_equal_approx(pc.sheet_rate_scale, s.sheet_rate),
		"controls.let_fly_toggle": pc.let_fly_toggle,
		"controls.helm_fine_toggle": pc.helm_fine_toggle,
		"controls.rankings_toggle": hud.rankings_toggle,
		"controls.camera_boost_toggle": rig.options.boost_toggle,
		"controls.sheet_turns_auto_trim_off": pc.sheet_turns_auto_trim_off,
		"controls.vibration": is_equal_approx(pc.rumble.strength, s.vibration),
		"cameras.camera_speed": is_equal_approx(rig.options.speed, s.camera_speed),
		"cameras.invert_orbit_x": rig.options.invert_orbit_x,
		"cameras.invert_orbit_y": rig.options.invert_orbit_y,
		"cameras.invert_look_x": rig.options.invert_look_x,
		"cameras.invert_look_y": rig.options.invert_look_y,
		"cameras.heel_follow": is_equal_approx(rig.onboard.heel_follow, s.heel_follow),
		"cameras.smooth_switch": rig.options.smooth_switch,
		"cameras.reduced_motion": rig.options.reduced_motion,
		"hud.assist": hud.assist == s.assist,
		"hud.hud_density": hud.density == s.hud_density and not hud.density_auto,
		"hud.ui_scale": is_equal_approx(root.content_scale_factor, s.ui_scale),
		"hud.palette": HudStyle.palette == "tritanopia" and HudStyle.STBD == HudStyle.PALETTES["tritanopia"][0]
			and HudStyle.TINTS[RaceHudValues.Tint.RED] == HudStyle.PALETTES["tritanopia"][1],
		"graphics.quality": sea.quality == s.quality,
		"graphics.render_scale": is_equal_approx(root.scaling_3d_scale, s.render_scale),
		"graphics.fullscreen": DisplayServer.get_name() == "headless",  # the window mode: not in headless runs
		"graphics.vsync": DisplayServer.get_name() == "headless",
		"graphics.fps_limit": Engine.max_fps == s.fps_limit,
		"menu.last_setup": true,  # the setup pages and Continue (test_main_menu, test_touches)
		"menu.welcomed": true,  # the first-launch screen (test_touches)
		"bindings.bindings": Bindings.slots("let_fly") == s.bindings["let_fly"],
	}
	for f in Settings.BUSES:
		got["audio." + f] = absf(bus.call(Settings.BUSES[f][0]) - float(s.get(f))) < 1e-3 or (float(s.get(f)) <= 0.0
			and AudioServer.is_bus_mute(AudioServer.get_bus_index(Settings.BUSES[f][0])))
	for sec in Settings.FIELDS:
		for f in Settings.FIELDS[sec]:
			var k: String = sec + "." + f
			if k in Settings.NOT_APPLIED:
				t.ok(not got.has(k), "%s stored only (listed in NOT_APPLIED)" % k)
			else:
				t.ok(got.get(k, false), "%s applied" % k)
	t.ok(Settings.NOT_APPLIED == ["hud.captions"], "only captions stay stored: %s" % [Settings.NOT_APPLIED])
	# back to the defaults
	fresh.apply_hud(hud)
	t.ok(HudStyle.palette == "standard" and HudStyle.PORT == Color("#FF4438"), "standard palette back")
	fresh.apply_bindings()
	Engine.max_fps = fps
	root.content_scale_factor = cs
	root.scaling_3d_scale = sc3
	fresh.apply_audio()
	hud.free()
	rig.call("free")
	sea.free()
	# the options' behaviour: rankings toggle, camera boost toggle, vibration
	var h := Hud.new()
	h.ui_input(RawInput.new().hold(&"rankings"))
	t.ok(h.show_ranking, "rankings hold: open while held")
	h.ui_input(RawInput.new())
	t.ok(not h.show_ranking, "rankings hold: closed on release")
	h.rankings_toggle = true
	h.ui_input(RawInput.new().press(&"rankings"))
	h.ui_input(RawInput.new())
	t.ok(h.show_ranking, "rankings toggle: a press opens it")
	var dens := h.density
	h.ui_input(RawInput.new().press(&"rankings_pad"), 0.05)
	h.ui_input(RawInput.new(), 0.05)
	t.ok(not h.show_ranking and h.density == dens, "rankings toggle: a View press closes it and leaves the density")
	h.free()
	var fc := FreeCamera.new()
	var o := CamTypes.Options.new()
	var ci := CameraInput.new()
	ci.boost = true
	fc.handle_input(ci, o, 0.016)
	t.ok(fc._boost, "boost hold: on while held")
	o.boost_toggle = true
	ci = CameraInput.new()
	fc.handle_input(ci, o, 0.016)
	t.ok(fc._boost, "boost toggle: stays on when released")
	ci.boost_pressed = true
	fc.handle_input(ci, o, 0.016)
	t.ok(not fc._boost, "boost toggle: the next press turns it off")
	var rb := Rumble.new()
	rb.devices = [99]  # no such pad: nothing is driven in the test
	rb.strength = 0.5
	var stub := StubSim.new()
	stub.ev = [{"boat": 0, "begin": true, "closing_speed": 1.0}, {"boat": 1, "begin": true, "closing_speed": 4.0}]
	rb.tick(stub, 0)
	rb.frame(0.05, false)
	t.near(rb.strong, 0.25, 1e-6, "vibration: own contact min(1, 1.0 / 2) x 50 %")
	rb.frame(0.2, false)
	t.near(rb.strong, 0.0, 1e-6, "vibration: the contact rumble lasts 0.2 s")
	rb.frame(0.016, true)
	t.near(rb.weak, 0.05, 1e-6, "vibration: let fly buzz 0.1 x 50 %")
	rb.strength = 0.0
	rb.frame(0.016, true)
	t.ok(rb.weak == 0.0 and rb.strong == 0.0, "vibration Off: nothing")
	rb.strength = 1.0
	rb.frame(0.016, true, false)
	t.ok(rb.weak == 0.0, "no vibration while not sailing (paused, watching)")


## menus.md §3 Rebinding: bind a slot, the conflict shown on both rows, default pairs not conflicts, clear, reset,
## saved and loaded with the settings.
func test_rebinding() -> void:
	t.begin("rebinding")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	Settings.reset_current()
	var st := Settings.current()
	st.apply_bindings()
	t.ok(Bindings.all_conflicts().is_empty(), "the defaults have no conflicts (context pairs: %s)" %
		["Shift for fine helm and camera boost" if Bindings.default_pair("helm_fine", "camera_boost") else "none"])
	var p := SettingsPanel.new()
	p.build(st)
	root.add_child(p)
	await process_frame
	p.show_section("controls", false)
	var row: BindingRow = p.binding_rows.get("let_fly")
	t.ok(row != null and p.binding_rows.size() == Bindings.actions().size(), "a row per action (%d)"
		% p.binding_rows.size())
	t.ok(row._slots.size() == 3 and p.binding_rows["camera_zoom_in"]._slots.size() == 4,
		"Key 1, Key 2, Pad (zoom: three keys, its defaults have three)")
	# keyboard: focus the row, pick Key 2, Enter listens, T binds
	row.grab_focus()
	await process_frame
	_key("ui_right")
	await process_frame
	t.ok(row.slot == 1, "right picks Key 2")
	_key("ui_accept")
	await process_frame
	t.ok(row.listening and row._slots[1].text == "Press a key", "Enter listens: %s" % row._slots[1].text)
	var k := InputEventKey.new()
	k.physical_keycode = KEY_T
	k.pressed = true
	root.push_input(k)
	await process_frame
	t.ok(not row.listening and Bindings.slots("let_fly")[1] == ["key", KEY_T, ""], "T bound to let fly's Key 2")
	t.ok(InputMap.action_has_event("let_fly", Bindings.decode(["key", KEY_T, ""])), "in the input map at once")
	t.ok(row.conflicts.has(1) and p.binding_rows["auto_trim"].conflicts.has(0),
		"conflict with auto trim shown on both rows")
	t.ok(row.help.contains("Auto trim"), "the help names the other action: %s" % row.help)
	t.ok(st.bindings.has("let_fly") and not st.bindings.has("auto_trim"), "only the changed action stored")
	# a gamepad button goes to the Pad slot whichever slot is picked; Esc cancels
	row.slot = 0
	row.listen()
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_Y
	jb.pressed = true
	root.push_input(jb)
	await process_frame
	t.ok(Bindings.slots("let_fly")[2] == ["button", JOY_BUTTON_Y] and row.conflicts.has(2),
		"Y to the Pad slot (conflicts with camera next)")
	row.listen()
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc)
	await process_frame
	t.ok(not row.listening and p.is_visible_in_tree(), "Esc cancels listening (the settings stay open)")
	# a modifier alone binds itself on release; with a key, the combination
	row.slot = 0
	row.listen()
	var sh := InputEventKey.new()
	sh.physical_keycode = KEY_SHIFT
	sh.pressed = true
	root.push_input(sh)
	var f2 := InputEventKey.new()
	f2.physical_keycode = KEY_F2
	f2.shift_pressed = true
	f2.pressed = true
	root.push_input(f2)
	await process_frame
	t.ok(Bindings.slots("let_fly")[0] == ["key", KEY_F2, "shift"], "Shift + F2: %s" % [Bindings.slots("let_fly")[0]])
	# clear a slot
	row.slot = 2
	row.clear_slot()
	t.ok(Bindings.slots("let_fly")[2].is_empty(), "Delete or X clears the slot")
	# saved on close, applied at start
	p.close()
	var back := Settings.new()
	back.load_file(TEST_PATH)
	t.ok(back.bindings.get("let_fly", []) == Bindings.slots("let_fly"), "saved in the settings file: %s"
		% [back.bindings.get("let_fly")])
	Bindings.apply({})
	back.apply_bindings()
	t.ok(Bindings.slots("let_fly")[1] == ["key", KEY_T, ""], "loaded and applied at start")
	# reset
	p.reset_bindings()
	t.ok(Bindings.slots("let_fly") == Bindings.default_slots("let_fly") and st.bindings.is_empty()
		and Bindings.all_conflicts().is_empty(), "Reset bindings: the defaults, nothing stored, no conflicts")
	t.ok(SettingsPanel.binding_text("let_fly").contains("Space"), "bindings shown: %s" %
		SettingsPanel.binding_text("let_fly"))
	p.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	Settings.reset_current()


func _key(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	root.push_input(e)
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	root.push_input(r)


## menus.md §4 live backdrop: the sail scene with AI boats only, no chrome, no input, no sound, a drifting
## camera; the painted backdrop when it does not load.
func test_live_backdrop() -> void:
	t.begin("main menu: live backdrop")
	Settings.reset_current()
	Settings.current().welcomed = true
	Settings.current().quality = SeaQuality.Tier.L
	var m := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	m.change_scenes = false
	root.add_child(m)
	await process_frame
	t.ok(m.stage != null and m.stage.scene != null, "the sail scene runs behind the menu")
	if m.stage != null and m.stage.scene != null:
		var sc: Variant = m.stage.scene
		t.ok(not m.backdrop.draw_scene and m.backdrop.haze, "painted scene off, the haze on")
		var n := m.stage.boat_count()
		print("  backdrop: %d boats on %s" % [n, "the core" if sc.on_core else "FakeSim"])
		t.ok(n == (MenuStage.FLEET_L if sc.on_core else 1), "%d boats on tier L (%s)" % [n,
			"core" if sc.on_core else "FakeSim"])
		t.ok(not m.stage.sun_shadows() and Engine.max_fps == MenuStage.FPS_L,
			"tier L: no sun shadows, %d fps cap (max_fps %d)" % [MenuStage.FPS_L, Engine.max_fps])
		Settings.current().fps_limit = 144
		m._setting_changed("fps_limit")
		t.ok(Engine.max_fps == MenuStage.FPS_L, "a display change keeps the 30 fps cap on L")
		Settings.current().fps_limit = 0
		t.ok(not sc.racing and sc.watch, "no player: every boat sails itself")
		t.ok(not sc.hud.visible, "no HUD")
		t.ok(sc.get_node_or_null("PauseMenu") == null, "no pause menu")
		t.ok(sc.scripted_input != null and sc.scripted_input.pressed.is_empty(), "no player input reaches it")
		t.ok(not sc.audio.audible, "silent")
		if sc.course_view != null:
			t.ok(not sc.course_view.show_guides and not sc.course_view.show_laylines, "no course guides on the water")
		t.ok(sc.sea.quality == SeaQuality.Tier.L, "the player's quality tier")
		var cam := m.stage.camera()
		t.ok(cam != null and cam.current, "seen through the scene's camera")
		var p0 := cam.global_position
		for i in 30:
			await process_frame
		var p1 := cam.global_position
		var d := Vector2(p1.x, p1.z).distance_to(Vector2(m.stage._focus.x, m.stage._focus.z))
		t.ok(p0.distance_to(p1) > 0.01 and d > MenuStage.DIST.x * 0.8 and d < MenuStage.DIST.y * 1.2
			and p1.y >= 3.0, "the camera drifts round the boat at %.0f m, %.1f m up" % [d, p1.y])
		Settings.current().quality = SeaQuality.Tier.H
		m._setting_changed("quality")
		t.ok(sc.sea.quality == SeaQuality.Tier.H, "a quality change reaches the backdrop at once")
		t.ok(m.stage.sun_shadows() and Engine.max_fps == 0, "tier H: sun shadows back, no frame cap")
		Settings.current().quality = SeaQuality.Tier.L
		m._setting_changed("quality")
	m.queue_free()
	await process_frame
	t.ok(Engine.max_fps == Settings.current().fps_limit, "leaving the menu puts the player's frame limit back")
	t.ok(MenuStage.fleet_for(SeaQuality.Tier.M) == MenuStage.FLEET and MenuStage.fleet_for(SeaQuality.Tier.H)
		== MenuStage.FLEET and MenuStage.FLEET_L == 2, "4 boats on M and H, 2 on L")
	t.ok(MenuStage.frame_cap(SeaQuality.Tier.L, 0) == 30 and MenuStage.frame_cap(SeaQuality.Tier.L, 144) == 30
		and MenuStage.frame_cap(SeaQuality.Tier.L, 24) == 24 and MenuStage.frame_cap(SeaQuality.Tier.M, 0) == 0
		and MenuStage.frame_cap(SeaQuality.Tier.H, 90) == 90, "frame cap: 30 on L (or the lower limit), the player's on M and H")
	var f := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	f.change_scenes = false
	f.stage_scene = "res://scenes/no_such_scene.tscn"
	root.add_child(f)
	await process_frame
	t.ok(f.stage == null and f.backdrop.draw_scene, "fallback: the painted backdrop when the scene does not load")
	f.queue_free()
	await process_frame
	Settings.reset_current()


func test_main_menu() -> void:
	t.begin("main menu: quick race and free sail")
	Settings.reset_current()
	Settings.current().welcomed = true
	var m := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	m.change_scenes = false
	m.live_backdrop = false
	var asked: Array[String] = []
	m.scene_requested.connect(func(p: String) -> void: asked.append(p))
	root.add_child(m)
	await process_frame
	await process_frame
	t.ok(root.gui_get_focus_owner() == m.buttons["quick"], "focus starts on Quick race")
	var q := m.quick
	t.ok(q.rows["class_id"].choices == MenuData.ids(MenuData.classes()), "quick race: classes from disk")
	t.ok(q.rows["venue"].choices == MenuData.ids(MenuData.venues()), "quick race: venues from disk")
	t.ok(q.rows["course"].choices.has("practice_waters/example_wl"), "quick race: the venue's courses")
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
	t.ok(g.mode == "race" and g.class_id == "wm12" and g.venue == "practice_waters", "GameSetup: race, wm12, venue")
	t.ok(g.course == "practice_waters/example_wl" and g.fleet_size == fleet + 2 and g.ai_level == "pro",
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
			# the logo inside the window, clear of the menu (menus.md §1.2)
			await process_frame
			var mark := m.find_child("Wordmark", true, false) as Wordmark
			var mr := mark.get_global_rect()
			var menu_r := (m.find_child("Menu", true, false) as Control).get_global_rect()
			print("  logo %s at %d %%: %s, WINDMARK %d px" % [scr, roundi(sc * 100), mr.size, mark.title_px])
			t.ok(root.get_visible_rect().grow(1).encloses(mr) and not mr.intersects(menu_r),
				"logo within %s at %d %%, clear of the menu: %s, WINDMARK %d px" % [scr, roundi(sc * 100), mr,
				mark.title_px])
	m.settings.ui_scale = 1.0
	root.content_scale_factor = 1.0
	m.queue_free()
	await process_frame
	Settings.reset_current()


## menus.md §1.1: the course map from the course file, the fleet summary, Start always reachable, the layout.
func test_race_card() -> void:
	t.begin("quick race: the race card")
	Settings.reset_current()
	Settings.current().welcomed = true
	var c := MenuData.course_file("practice_waters/example_wl")
	t.ok(c.get("id", "") == "example_wl", "course file read")
	var p := CourseMap.resolve(c, 0.0)
	t.ok(p["rc"].distance_to(Vector2(125, -300)) < 0.01 and p["pin"].distance_to(Vector2(-125, -300)) < 0.01,
		"start ends square to a north wind: rc %s, pin %s" % [p["rc"], p["pin"]])
	t.ok(p["w"].distance_to(Vector2(0, 400)) < 0.01, "windward mark 700 m upwind of the line: %s" % p["w"])
	var e := CourseMap.resolve(c, PI * 0.5)
	t.ok(e["w"].distance_to(Vector2(700, -300)) < 0.01, "wind from the east: windward mark to the east %s" % e["w"])
	t.ok(CourseMap.laps_legs(c) == Vector2i(2, 6), "2 laps, 6 legs")
	t.ok(CourseMap.rounding_ids(c).has("w") and CourseMap.rounding_ids(c).has("g1")
		and not CourseMap.rounding_ids(c).has("rc"), "rounding marks: the sequence's marks and gates")
	var m := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	m.change_scenes = false
	m.live_backdrop = false
	root.add_child(m)
	root.size = Vector2i(1280, 800)
	await process_frame
	m.open_page("quick")
	await process_frame
	await process_frame
	var q := m.quick
	t.ok(q.course_map != null and q.course_map.points.has("w"), "the course map shows the chosen course")
	q.rows["weather"].set_value("custom", true)
	q.rows["wind_from_deg"].set_value(90.0, true)
	q.rows["wind_kn"].set_value(18.0, true)
	t.ok(absf(q.course_map.wind_from_deg - 90.0) < 1e-6 and absf(q.course_map.wind_kn - 18.0) < 1e-6
		and q.course_map.points["w"].x > 600.0, "the map follows the wind rows")
	q.rows["fleet_size"].set_value(12.0, true)
	q.rows["ai_level"].set_value("pro", true)
	t.ok(q.fleet_text.text.contains("12 boats: you and 11 AI") and q.fleet_text.text.contains("Pro AI")
		and q.fleet_text.text.contains(MenuData.name_of(MenuData.classes(), str(q.rows["class_id"].value))),
		"fleet summary: %s" % q.fleet_text.text.replace("\n", " / "))
	t.ok(q.course_text.text.contains("2 laps, 6 legs"), "course caption: %s" % q.course_text.text.replace("\n", " / "))
	# keyboard: down from the last row is Start, up from Start the last row (Gusts in Custom, Weather otherwise)
	t.ok(q.last_row() == q.rows["gusts"], "Custom: the last row is Gusts")
	q.rows["gusts"].grab_focus()
	await process_frame
	_key("ui_down")
	await process_frame
	t.ok(root.gui_get_focus_owner() == q.start_button, "down from the last row: Start")
	_key("ui_up")
	await process_frame
	t.ok(root.gui_get_focus_owner() == q.rows["gusts"], "up from Start: the last row")
	q.rows["weather"].set_value("local", true)
	t.ok(q.last_row() == q.rows["weather"] and not q.rows["wind_kn"].visible, "Local: the Custom rows hidden")
	q.rows["weather"].grab_focus()
	await process_frame
	_key("ui_down")
	await process_frame
	t.ok(root.gui_get_focus_owner() == q.start_button, "Local: down from Weather is Start")
	_key("ui_up")
	await process_frame
	t.ok(root.gui_get_focus_owner() == q.rows["weather"], "Local: up from Start is Weather")
	# the layout: preview beside the rows when there is room, under them when not; Start always on screen
	for c2 in [[Vector2i(1280, 800), 0.8], [Vector2i(1280, 800), 1.0], [Vector2i(1280, 800), 1.3],
			[Vector2i(1080, 1920), 0.8], [Vector2i(1080, 1920), 1.0], [Vector2i(1080, 1920), 1.3]]:
		root.size = c2[0]
		m.settings.ui_scale = c2[1]
		m.settings.apply_display(root)
		await process_frame
		await process_frame
		var vis := root.get_visible_rect().grow(1)
		var wide: bool = q.size.x >= SetupPanel.TWO_COLUMNS_MIN
		print("  race card %s at %d %%: page %d px, %s" % [c2[0], roundi(c2[1] * 100), q.size.x,
			"two columns" if wide else "one column"])
		t.ok(q.body.vertical != wide, "%s at %d %%: %s (page %d px)" % [c2[0], roundi(c2[1] * 100),
			"preview beside the rows" if wide else "preview under the rows", q.size.x])
		t.ok(vis.encloses(q.start_button.get_global_rect()), "Start on screen")
		if c2[0] == Vector2i(1280, 800) and c2[1] <= 1.0:
			t.ok(wide, "the logo leaves the race card two columns at %d %%" % roundi(c2[1] * 100))
		if wide:
			t.ok(vis.encloses(q.course_map.get_global_rect()), "the course map on screen")
		if wide:
			t.ok(vis.encloses(q.briefing.get_global_rect()), "the briefing on screen")
		# the last row and Start reachable by the keyboard at this size
		q.last_row().grab_focus()
		await process_frame
		_key("ui_down")
		await process_frame
		t.ok(root.gui_get_focus_owner() == q.start_button, "down to Start")
	m.settings.ui_scale = 1.0
	m.settings.apply_display(root)
	root.size = Vector2i(1280, 800)
	m.queue_free()
	await process_frame
	Settings.reset_current()


const TIDAL := "res://tests/fixtures/tidal_test.venue.json"


## A venue file's weather info (VenueWeather.info), {} when it does not read.
func _vi(path: String) -> Dictionary:
	var v: Variant = BoatClassData._read_json(ProjectSettings.globalize_path(path) if path.begins_with("res://")
		else path)
	return VenueWeather.info(v) if v is Dictionary else {}


## A venue doc with these conditions (SI), for the threshold checks.
func _cond(c: Dictionary, extra := {}) -> Dictionary:
	var d := {"id": "t", "name": "Test", "fetch": 10000.0, "conditions": c}
	d.merge(extra, true)
	return VenueWeather.info(d)


## menus.md §1.3: the briefing's lines, number formats and thresholds; the spec's examples; Random shows nothing
## but the Unknown line; the Tip in Local only; the Today line of menus.md §5.
func test_briefing() -> void:
	t.begin("venue briefing: lines, thresholds, modes")
	var KN := VenueWeather.KNOT
	var tm := {"t_gun": 330.0, "t_race": 900.0}
	# Practice Waters, Local
	var pw := MenuData.venue_info("practice_waters")
	t.ok(pw.get("has_conditions", false) and VenueWeather.modes(pw) == ["local", "random", "custom"],
		"Practice Waters: conditions, three weather modes")
	var txt := VenueWeather.text(pw, "local", {}, tm)
	print("  Practice Waters (Local):\n    " + txt.replace("\n", "\n    ").replace("\t", "  "))
	t.ok(txt == "PRACTICE WATERS · Practice\nWind\t10-14 kn from the N\nShifts\tStable: small, slow (3°)\n"
		+ "Gusts\tLight: to +15 %, frequent\nCurrent\tLight, 0.3 kn, sets E\nSea\tChop\nTip\t" + str(pw["tip"]),
		"Practice Waters briefing (Local)")
	t.ok(str(pw["tip"]).length() <= 80 and not str(pw["tip"]).contains("—"), "the tip: at most 80 characters, no em dash")
	# Random: only the Unknown line, nothing about the conditions
	var rnd := VenueWeather.lines(pw, "random", {}, tm)
	t.ok(rnd.size() == 1 and rnd[0][0] == "Weather" and rnd[0][1] == "Unknown: read it on the water",
		"Random: only `Weather  Unknown: read it on the water`")
	t.ok(not VenueWeather.text(pw, "random", {}, tm).contains(" kn"), "Random: no numbers at all")
	# Custom: the picks, the venue's current and sea, no Tip
	var cus := VenueWeather.text(pw, "custom", {"kn": 18.0, "from_deg": 90.0, "shift": "unstable", "gusts": "gusty"}, tm)
	t.ok(cus == "PRACTICE WATERS · Practice\nWind\t18 kn from the E\nShifts\tUnstable: very large, fast (25°)\n"
		+ "Gusts\tVery strong: to +45 %, frequent\nCurrent\tLight, 0.3 kn, sets E\nSea\tModerate", "Custom briefing: %s"
		% cus.replace("\n", " / "))
	t.ok(not cus.contains("Tip"), "Custom: no Tip")
	var none := VenueWeather.text(pw, "custom", {"kn": 4.0, "from_deg": 0.0, "shift": "steady", "gusts": "none"}, tm)
	t.ok(none.contains("Shifts\tSteady\n") and none.contains("Gusts\tNone") and none.contains("Sea\tFlat"),
		"Custom steady, no gusts, 4 kn: %s" % none.replace("\n", " / "))
	var cd := VenueWeather.custom_defaults(pw)
	t.ok(cd == {"kn": 12.0, "from_deg": 0.0, "shift": "stable", "gusts": "light"}, "Custom defaults: %s" % [cd])
	# the tide and trend fixture
	var td := _vi(TIDAL)
	var ttm := tm.duplicate()
	ttm["tide_factor"] = 0.6  # a race drawn at the flood's peak
	var tt := VenueWeather.text(td, "local", {}, ttm)
	print("  Tidal fixture (Local):\n    " + tt.replace("\n", "\n    ").replace("\t", "  "))
	t.ok(tt == "TIDAL TEST · Strong tide\nWind\t10-16 kn from the SW\nShifts\tStable: small, slow (4°), backs 7°\n"
		+ "Gusts\tLight: to +15 %, frequent\nCurrent\tStrong, 1.5 kn, flooding (sets E)\n"
		+ "Sea\tFlat to chop, swell 0.4 m from the SW\nTip\tThe stream runs hardest mid-channel; cheat it along the shore.",
		"tide and trend fixture briefing")
	var short := VenueWeather.lines(td, "local", {}, VenueWeather.timing(MenuData.course_file("practice_waters/example_wl")))
	t.ok(short[1][1] == "Stable: small, slow (4°), backs 5°", "the trend over the course's own timing: %s" % short[1][1])
	# the spec's examples (venues.md §2) from their sketched conditions
	var solent := _cond({"wind": {"speed": [10 * KN, 16 * KN], "from": deg_to_rad(225)},
		"shift": {"amplitude": deg_to_rad(4.0), "hold_max": 120}, "puffs": {"preset": "light"},
		"tide": {"scale": 0.6, "period": 44712}},
		{"fetch": 8000.0, "current_field": {"ref_speed": 1.29, "ref_to": deg_to_rad(75.0)}})
	var stm := tm.duplicate()
	stm["tide_factor"] = 0.6
	var sl := VenueWeather.lines(solent, "local", {}, stm)
	t.ok(sl.map(func(l: Array) -> String: return l[1]) == ["10-16 kn from the SW", "Stable: small, slow (4°)",
		"Light: to +15 %, frequent", "Strong, 1.5 kn, flooding (sets E)", "Flat to chop"], "Solent example: %s" % [sl])
	# the spec's other Solent races (venues.md §2): a moderate ebb and slack
	for c in [[-0.45, "Moderate, 1.1 kn, ebbing (sets W)"], [0.05, "Slack, turning"], [-0.1, "Slack, turning"],
			[0.15, "Light, 0.4 kn, flooding (sets E)"]]:
		stm["tide_factor"] = c[0]
		var cl: String = VenueWeather.lines(solent, "local", {}, stm)[3][1]
		t.ok(cl == c[1], "Solent tide factor %+.2f: %s" % [c[0], cl])
	# without the race's tide (no seed known) the line names no state
	t.ok(VenueWeather.lines(solent, "local", {}, tm)[3][1] == "Strong, 1.5 kn", "tide state unknown: strength only")
	var fre := _cond({"wind": {"speed": [16 * KN, 24 * KN], "from": deg_to_rad(230)},
		"shift": {"amplitude": deg_to_rad(5.0), "hold_max": 90, "trend_rate": deg_to_rad(-0.5) / 60.0,
		"trend_max": deg_to_rad(15.0)}, "puffs": {"preset": "standard"},
		"sea": {"swells": [{"hs": 0.8, "tp": 12.0, "from": deg_to_rad(240)}]}}, {"fetch": 30000.0})
	var fl := VenueWeather.lines(fre, "local", {}, tm)
	t.ok(fl.map(func(l: Array) -> String: return l[1]) == ["16-24 kn from the SW",
		"Stable: small, regular (5°), backs 8°", "Moderate: to +25 %, frequent", "None",
		"Moderate to rough, swell 0.8 m from the SW"], "Fremantle example: %s" % [fl])
	var tri := _cond({"wind": {"speed": [16 * KN, 24 * KN], "from": deg_to_rad(65)},
		"shift": {"amplitude": deg_to_rad(22.0), "hold_max": 45}, "puffs": {"preset": "gusty"},
		"current": {"speed": 0.3 * KN, "to": deg_to_rad(225)}}, {"fetch": 3000.0})
	var tl := VenueWeather.lines(tri, "local", {}, tm)
	t.ok(tl.map(func(l: Array) -> String: return l[1]) == ["16-24 kn from the NE", "Unstable: very large, fast (22°)",
		"Very strong: to +45 %, frequent", "Light, 0.3 kn, sets SW", "Flat to chop"], "Trieste example: %s" % [tl])
	# shift thresholds: word and size by A, pace by H
	for c in [[1.4, 120, "Steady"], [1.5, 120, "Stable: small, slow (2°)"], [5.4, 100, "Stable: small, slow (5°)"],
			[5.5, 99, "Oscillating: medium, regular (6°)"], [11.4, 55, "Oscillating: medium, regular (11°)"],
			[11.5, 54, "Shifty: large, fast (12°)"], [19.9, 60, "Shifty: large, regular (20°)"],
			[20.0, 45, "Unstable: very large, fast (20°)"]]:
		var s := VenueWeather.shifts_text(deg_to_rad(c[0]), c[1], 0.0)
		t.ok(s == c[2], "shifts A %.1f°, H %d s: %s" % [c[0], c[1], s])
	t.ok(VenueWeather.shifts_text(deg_to_rad(3.0), 120, 2.4) == "Stable: small, slow (3°)", "a trend under 3° not shown")
	t.ok(VenueWeather.shifts_text(deg_to_rad(3.0), 120, 3.0) == "Stable: small, slow (3°), veers 3°", "veers 3°")
	t.ok(VenueWeather.shifts_text(0.0, 0, -6.0) == "Steady, backs 6°", "steady with a back")
	# gust thresholds by g = min(cap_up, strength_max), spread by cover
	for c in [[0.17, "Light"], [0.18, "Moderate"], [0.279, "Moderate"], [0.28, "Strong"], [0.399, "Strong"],
			[0.40, "Very strong"]]:
		var p := VenueWeather.puff_preset("standard")
		p["puff_cap_up"] = c[0]
		p["puff_strength_max"] = 0.9
		t.ok(VenueWeather.gusts_text(p).begins_with(c[1] + ":"), "gusts g %.3f: %s" % [c[0], VenueWeather.gusts_text(p)])
	var sp := VenueWeather.puff_preset("standard")
	sp["puff_count"] = 2
	t.ok(VenueWeather.gusts_text(sp).ends_with("scattered"), "few puffs: scattered")
	sp["puff_count"] = 8
	t.ok(VenueWeather.gusts_text(sp).ends_with("everywhere"), "many puffs: everywhere")
	t.ok(VenueWeather.gusts_text(VenueWeather.puff_preset("none")) == "None", "puffs off: None")
	# current thresholds and the tide's turn
	for c in [[0.19, "None"], [0.2, "Light, 0.2 kn, sets N"], [0.59, "Light, 0.6 kn, sets N"],
			[0.6, "Moderate, 0.6 kn, sets N"], [1.2, "Strong, 1.2 kn, sets N"], [2.0, "Very strong, 2.0 kn, sets N"]]:
		var x := {"current": c[0] * KN, "uniform": c[0] * KN, "uniform_to": 0.0, "tide": {}}
		t.ok(VenueWeather.current_text(x) == c[1], "current %.2f kn: %s" % [c[0], VenueWeather.current_text(x)])
	# the tide near slack: the stream under 0.3 kn; with a uniform current the uniform line
	for c in [[0.29, 0.0, "Slack, turning"], [0.31, 0.0, "Light, 0.3 kn, ebbing (sets S)"],
			[0.29, 0.3, "Light, 0.6 kn, sets N"]]:
		var x := {"current": (c[0] + c[1]) * KN, "uniform": c[1] * KN, "uniform_to": 0.0, "tide": {"scale": 1.0},
			"tide_factor": -0.5, "tide_stream": c[0] * KN, "ref_to": 0.0}
		t.ok(VenueWeather.current_text(x) == c[2], "tide %.2f kn, uniform %.1f kn: %s" % [c[0], c[1],
			VenueWeather.current_text(x)])
	# sea words
	for c in [[0.24, "Flat"], [0.25, "Chop"], [0.5, "Moderate"], [1.0, "Rough"]]:
		t.ok(VenueWeather._sea_word(c[0]) == c[1].to_lower(), "sea %.2f m: %s" % [c[0], c[1]])
	# the Today line after a Random race (menus.md §5)
	var today := VenueWeather.today({"wind_speed": 18 * KN, "wind_from": deg_to_rad(225), "shift_amplitude":
		deg_to_rad(15.0), "puffs": true, "puff": {"cap_up": 0.45, "puff_strength_max": 0.7}})
	t.ok(today == "Today: 18 kn from the SW · Shifty · Very strong gusts", "Today line: %s" % today)
	t.ok(VenueWeather.today({"wind_speed": 8 * KN, "wind_from": 0.0, "shift_amplitude": 0.0, "puffs": false})
		== "Today: 8 kn from the N · Steady · No gusts", "Today line without gusts")
	# no em dashes in any fixed text
	var dash := false
	for k in Strings.EN:
		dash = dash or str(Strings.EN[k]).contains("—")
	t.ok(not dash, "no em dashes in the string table")


## menus.md §1, §1.1, §1.3: the Weather row and its modes on the race card, the Custom rows, the briefing following
## the rows for every venue on disk, a venue without conditions (Custom only), GameSetup and the results' Today line.
func test_weather_card() -> void:
	t.begin("quick race: weather row and briefing")
	Settings.reset_current()
	Settings.current().welcomed = true
	var m := _menu()
	root.size = Vector2i(1280, 800)
	await process_frame
	m.open_page("quick")
	await process_frame
	await process_frame
	var q := m.quick
	q.rows["venue"].set_value("practice_waters", true)
	t.ok(q.rows["weather"].choices == ["local", "random", "custom"] and q.rows["weather"].value == "local",
		"Weather row: Local, Random, Custom; Local by default")
	t.ok(q.rows["weather"].names == ["Local", "Random", "Custom"], "mode names: %s" % [q.rows["weather"].names])
	for k in SetupPanel.CUSTOM_ROWS:
		t.ok(not q.rows[k].visible, "Local: %s hidden" % k)
	t.ok(q.briefing_header.visible and q.briefing_header.text == "PRACTICE WATERS · Practice",
		"Local: the header %s" % q.briefing_header.text)
	t.ok(q.briefing_grid.get_child_count() == 12, "Local: six lines with the Tip (%d cells)" % q.briefing_grid.get_child_count())
	t.ok(q.briefing_text().contains("Tip\t"), "Local: the Tip")
	t.ok(q.course_map.wind_shown and absf(q.course_map.wind_kn - 12.0) < 0.01 and q.course_map.wind_from_deg == 0.0,
		"Local: the map's wind is the typical direction and the middle of the range")
	# Random: nothing but the Unknown line, no wind on the map
	q.rows["weather"].set_value("random", true)
	t.ok(not q.briefing_header.visible and q.briefing_grid.get_child_count() == 2
		and (q.briefing_grid.get_child(1) as Label).text == "Unknown: read it on the water",
		"Random: only the Unknown line")
	t.ok(not q.course_map.wind_shown, "Random: no wind arrow or numbers on the map")
	for k in SetupPanel.CUSTOM_ROWS:
		t.ok(not q.rows[k].visible, "Random: %s hidden" % k)
	# Custom: four rows on the venue's defaults, the briefing follows them, no Tip
	q.rows["weather"].set_value("custom", true)
	for k in SetupPanel.CUSTOM_ROWS:
		t.ok(q.rows[k].visible, "Custom: %s shown" % k)
	t.ok(q.rows["wind_kn"].value == 12.0 and q.rows["shift"].value == "stable" and q.rows["gusts"].value == "light",
		"Custom rows on the venue's defaults")
	t.ok(q.rows["gusts"].names == ["None", "Light", "Moderate", "Very strong"], "Gusts names: %s" % [q.rows["gusts"].names])
	q.rows["wind_kn"].set_value(18.0, true)
	q.rows["wind_from_deg"].set_value(225.0, true)
	q.rows["shift"].set_value("shifty", true)
	q.rows["gusts"].set_value("standard", true)
	var bt := q.briefing_text()
	t.ok(bt.contains("Wind\t18 kn from the SW") and bt.contains("Shifts\tShifty: large, regular (15°)")
		and bt.contains("Gusts\tModerate: to +25 %, frequent") and not bt.contains("Tip"),
		"Custom: the briefing follows the rows, no Tip: %s" % bt.replace("\n", " / "))
	t.ok(q.briefing_header.text == "PRACTICE WATERS · Practice", "Custom: the header keeps the tag")
	t.ok(q.course_map.wind_shown and absf(q.course_map.wind_kn - 18.0) < 1e-6, "Custom: the map's wind is the pick")
	q.start_button.pressed.emit()
	var g := GameSetup.current()
	t.ok(g.weather == "custom" and g.wind_kn == 18.0 and g.wind_from_deg == 225.0 and g.shift == "shifty"
		and g.gusts == "standard", "GameSetup: the weather and the Custom picks")
	m.open_page("quick")
	await process_frame
	q.rows["weather"].set_value("random", true)
	q.start_button.pressed.emit()
	t.ok(GameSetup.current().weather == "random", "GameSetup: Random")
	t.ok(m.settings.last_setup.get("weather", "") == "random", "the weather mode is remembered")
	m.open_page("quick")
	await process_frame
	# a tidal venue: the card's race seed fixes the tide the Current line names, and Start passes that seed on
	if MenuData.ids(MenuData.venues()).has("solent"):
		q.rows["venue"].set_value("solent", true)
		q.rows["weather"].set_value("local", true)
		var seed := q.race_seed
		var r := CoreSimSource.resolve_settings({"race_seed": seed, "weather": 0}, "solent", str(q.rows["course"].value))
		var tau := VenueWeather.tide_at_gun(r, float(VenueWeather.timing(q._course_doc())["t_gun"]))
		var cur: String = q.briefing_lines()[3][1]
		var want := "Slack, turning" if absf(tau) * 1.2873 / VenueWeather.KNOT < 0.3 else ("flooding (sets E)" if tau > 0.0
			else "ebbing (sets W)")
		print("  Solent card, seed %d: tide factor %+.3f, Current  %s" % [seed, tau, cur])
		t.ok(seed != 0 and cur.ends_with(want), "Solent seed %d: tide factor %+.3f, Current %s" % [seed, tau, cur])
		q.start_button.pressed.emit()
		t.ok(GameSetup.current().seed == seed, "Start passes the seed the briefing was made for")
		t.ok(q.race_seed != seed, "the card draws a new seed for its next start")
		m.open_page("quick")
		await process_frame
		var seen := {}
		for s in range(1, 41):  # flood, ebb and slack all come up over seeds
			q.race_seed = s
			q._tide_cache.clear()
			var line: String = q.briefing_lines()[3][1]
			seen["flood" if line.contains("flooding") else ("ebb" if line.contains("ebbing") else "slack")] = true
		print("  Solent over 40 seeds: %s" % [seen.keys()])
		t.ok(seen.size() == 3, "Solent over 40 seeds: %s" % [seen.keys()])
		q.rows["venue"].set_value("practice_waters", true)
	# every venue on disk has a briefing (Local on its conditions, Custom without), and it follows the venue
	for vid in MenuData.ids(MenuData.venues()):
		q.rows["venue"].set_value(vid, true)
		var vi := MenuData.venue_info(vid)
		var want := "local" if vi.get("has_conditions", false) else "custom"
		q.rows["weather"].set_value(want, true)
		var ls := q.briefing_lines()
		t.ok(ls.size() >= 5 and q.briefing_header.text.begins_with(str(vi["name"]).to_upper()),
			"%s: a %s briefing of %d lines" % [vid, want, ls.size()])
	# a venue without conditions (data_format.md §6.9): Custom only, on 12 kn, 0°, Shifty, Moderate, no Tip
	var old := {"id": "old_bay", "name": "Old Bay", "fetch": 10000.0}
	MenuData._venue_info[BoatClassData.repo_path("data/venues/old_bay.venue.json")] = VenueWeather.info(old)
	var ids: Array = q.rows["venue"].choices.duplicate()
	ids.append("old_bay")
	q.rows["venue"].set_choices(ids, q.rows["venue"].names + ["Old Bay"])
	q.rows["venue"].set_value("old_bay", true)
	t.ok(q.rows["weather"].choices == ["custom"] and q.rows["weather"].value == "custom", "no conditions: Custom only")
	t.ok(q.rows["wind_kn"].value == 12.0 and q.rows["wind_from_deg"].value == 0.0 and q.rows["shift"].value == "shifty"
		and q.rows["gusts"].value == "standard", "no conditions: 12 kn, 0°, Shifty, Moderate")
	var ob := q.briefing_text()
	t.ok(ob == "OLD BAY\nWind\t12 kn from the N\nShifts\tShifty: large, regular (15°)\n"
		+ "Gusts\tModerate: to +25 %, frequent\nCurrent\tNone\nSea\tChop", "no conditions: %s" % ob.replace("\n", " / "))
	MenuData._venue_info.erase(BoatClassData.repo_path("data/venues/old_bay.venue.json"))
	q.rows["venue"].set_value("practice_waters", true)
	t.ok(q.rows["weather"].choices.size() == 3, "back on Practice Waters: three modes")
	# a remembered setup on a venue that is gone falls back to the default venue
	t.ok(SetupPanel._pick(["a_venue", "practice_waters", "z_venue"], "example_bay") == "practice_waters",
		"a remembered venue no longer on disk falls back to the default")
	# Steam Deck: the card at 1280 x 800 in every mode, the briefing and Start on screen
	for mode in ["local", "random", "custom"]:
		q.rows["weather"].set_value(mode, true)
		for sc in [0.8, 1.0, 1.3]:
			m.settings.ui_scale = sc
			m.settings.apply_display(root)
			await process_frame
			await process_frame
			var vis := root.get_visible_rect().grow(1)
			var wide: bool = q.size.x >= SetupPanel.TWO_COLUMNS_MIN
			t.ok(vis.encloses(q.start_button.get_global_rect()), "%s at %d %%: Start on screen" % [mode, roundi(sc * 100)])
			if wide:
				t.ok(vis.encloses(q.briefing.get_global_rect()), "%s at %d %%: the briefing on screen" % [mode,
					roundi(sc * 100)])
	m.settings.ui_scale = 1.0
	m.settings.apply_display(root)
	# the results screen's Today line: after a Random race only
	var rs: Node = (load("res://scenes/menu/results_screen.gd") as GDScript).new()
	var hs := GDScript.new()
	hs.source_code = "extends Node\nvar weather_settings := {}\n"
	hs.reload()
	var host: Node = hs.new()
	rs.host = host
	host.weather_settings = {"weather_mode": "random", "wind_speed": 18 * VenueWeather.KNOT,
		"wind_from": deg_to_rad(225), "shift_amplitude": deg_to_rad(15.0), "puffs": true,
		"puff": {"cap_up": 0.45, "puff_strength_max": 0.7}}
	t.ok(rs.today_text() == "Today: 18 kn from the SW · Shifty · Very strong gusts", "results after Random: %s"
		% rs.today_text())
	host.weather_settings["weather_mode"] = "local"
	t.ok(rs.today_text() == "", "results after Local: no Today line")
	host.weather_settings["weather_mode"] = "custom"
	t.ok(rs.today_text() == "", "results after Custom: no Today line")
	rs.free()
	host.free()
	m.queue_free()
	await process_frame
	Settings.reset_current()


func _menu() -> MainMenu:
	var m := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	m.change_scenes = false
	m.live_backdrop = false
	root.add_child(m)
	return m


## menus.md §1, §3, §4: the first-launch screen, Continue, the version, the wordmark, the help line, the sounds.
func test_touches() -> void:
	t.begin("first launch, Continue, version, wordmark, help line, sounds")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	Settings.reset_current()
	root.size = Vector2i(1280, 800)
	var m := _menu()
	await process_frame
	await process_frame
	t.ok(m.welcome != null and not m._row.visible, "first launch: the welcome screen, the menu hidden")
	t.ok(root.gui_get_focus_owner() == m.welcome.rows["helm_mode"], "focus on Steering")
	_key("ui_right")
	await process_frame
	_key("ui_down")
	await process_frame
	_key("ui_right")
	await process_frame
	t.ok(m.welcome.rows["helm_mode"].value == PlayerControls.HelmMode.HOLD_TO_STEER
		and m.welcome.rows["quality"].value == SeaQuality.Tier.H, "keyboard: Hold to steer, High")
	m.welcome.go_button.pressed.emit()
	await process_frame
	var saved := Settings.new()
	saved.load_file(TEST_PATH)
	t.ok(saved.welcomed and saved.helm_mode == PlayerControls.HelmMode.HOLD_TO_STEER
		and saved.quality == SeaQuality.Tier.H, "Let's sail keeps the choices and saves, welcomed")
	t.ok(m.welcome == null and m._row.visible and root.gui_get_focus_owner() == m.buttons["quick"],
		"then the menu, focus on Quick race")
	t.ok(not m.buttons["continue"].visible, "no Continue before a first session")
	m.queue_free()
	await process_frame
	Settings.reset_current()
	m = _menu()
	await process_frame
	t.ok(m.welcome == null, "shown once")
	m.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	Settings.reset_current()
	m = _menu()
	await process_frame
	m.welcome.rows["quality"].set_value(SeaQuality.Tier.L)
	_key("ui_cancel")
	await process_frame
	t.ok(m.welcome == null and m.settings.welcomed and m.settings.quality == Settings.device_defaults().quality, "Esc skips: the defaults")
	# the wordmark and the version
	var mark := m.find_child("Wordmark", true, false)
	t.ok(mark is Wordmark and (mark.get_node("Title") as Label).text == "WINDMARK", "the wordmark scene")
	var wm := mark as Wordmark
	var tf := wm.title.get_theme_font("font") as FontVariation
	var gf := wm.tagline.get_theme_font("font") as FontVariation
	t.ok(tf != null and tf.base_font.resource_path.ends_with("BarlowSemiCondensed-BlackItalic.ttf")
		and tf.base_font.get_font_style_name() == "Black Italic",
		"WINDMARK in Black Italic: %s" % (tf.base_font.resource_path if tf else "none"))
	t.ok(gf != null and gf.base_font.resource_path.ends_with("BarlowSemiCondensed-ExtraBoldItalic.ttf")
		and gf.base_font.get_font_style_name() == "ExtraBold Italic",
		"tagline in ExtraBold Italic")
	# 1280 x 800 at 100 %: 73 px, so the race card keeps its two columns (menus.md §1.2)
	t.ok(wm.title_px >= roundi(0.9 * Wordmark.SIZE) and wm.title_px < Wordmark.SIZE, "WINDMARK %d px at 1280 x 800, 100 %%"
		% wm.title_px)
	wm.fit_width(10000.0)
	t.ok(wm.title_px == Wordmark.SIZE and wm.tagline.text == "REGATTA SAILING SIMULATOR", "WINDMARK at 76 px with room")
	t.ok(wm.title.get_theme_constant("outline_size") == 9 and wm.shadow_navy.position - wm.title.position
		== Vector2(3, 3) and wm.shadow_yellow.position - wm.title.position == Vector2(6, 6)
		and wm.shadow_yellow.get_index() < wm.shadow_navy.get_index() and wm.shadow_navy.get_index()
		< wm.title.get_index(), "outline 9 (2.25 px a side), shadows +3 and +6 px, yellow at the back")
	t.ok(wm.title.get_theme_color("font_color") == Color("f4f1e8") and wm.title.get_theme_color("font_outline_color")
		== Color("1a2a3a") and wm.shadow_yellow.get_theme_color("font_outline_color") == Color("ffd23f"),
		"cream fill, navy outline, yellow shadow outlined in yellow")
	var lean := (wm.bar[1].x - wm.bar[2].x) / (wm.bar[2].y - wm.bar[1].y)
	t.near(rad_to_deg(atan(lean)), 14.0, 0.01, "tagline bar slanted 14°")
	t.ok(wm.bar_shadow[0] - wm.bar[0] == Vector2(4, 4), "bar shadow +4 px")
	var wsz := wm.natural_size(Wordmark.SIZE)
	t.ok(wsz.x <= 420.0 and wsz.y <= 110.0, "lockup %s at 76 px" % wsz)
	wm.fit_width(200.0)
	t.ok(wm.natural_size(wm.title_px).x <= 200.0 and wm.title_px < Wordmark.SIZE, "fit to 200 px: WINDMARK %d px"
		% wm.title_px)
	wm.fit_width(10000.0)
	t.ok(wm.title_px == Wordmark.SIZE, "never above 76 px")
	m._fit()
	t.ok(m.version_label.text.begins_with("v" + str(ProjectSettings.get_setting("application/config/version")))
		and root.get_visible_rect().encloses(m.version_label.get_global_rect()), "version in the corner: %s"
		% m.version_label.text)
	# Continue: after a session it starts that setup again
	var asked: Array[String] = []
	m.scene_requested.connect(func(p: String) -> void: asked.append(p))
	m.open_page("quick")
	await process_frame
	m.quick.rows["fleet_size"].set_value(6.0, true)
	m.quick.rows["wind_kn"].set_value(9.0, true)
	m.quick.start_button.pressed.emit()
	m.close_page()
	t.ok(m.buttons["continue"].visible and m.continue_line.text.contains("Quick race") and
		m.continue_line.text.contains("6 boats"), "Continue after a race: %s" % m.continue_line.text)
	GameSetup.next = null
	m.buttons["continue"].pressed.emit()
	var g := GameSetup.current()
	t.ok(g.mode == "race" and g.fleet_size == 6 and absf(g.wind_kn - 9.0) < 1e-6 and g.seed == 0
		and asked.size() == 2, "Continue starts the same race again")
	m.open_page("free")
	await process_frame
	m.free_sail.start_button.pressed.emit()
	m.close_page()
	t.ok(m.continue_text().begins_with("Free sail"), "then a free sail: %s" % m.continue_text())
	m.settings.last_setup["mode"] = "race"
	m.settings.last_setup["course"] = "practice_waters/no_such_course"
	m._refresh_continue()
	t.ok(not m.buttons["continue"].visible and not m.can_continue(), "hidden when the setup cannot start")
	m.settings.last_setup["course"] = "practice_waters/example_wl"
	m._refresh_continue()
	# the sounds on the ui bus
	var snd := m.sounds
	t.ok(snd._players.values().all(func(p: AudioStreamPlayer) -> bool: return p.bus == "ui" and p.stream != null),
		"three sounds, on the ui bus")
	snd.played.clear()
	m.buttons["quick"].grab_focus()
	await process_frame
	_key("ui_down")
	await process_frame
	_key("ui_accept")
	await process_frame
	_key("ui_cancel")
	await process_frame
	t.ok(snd.played.has("focus") and snd.played.has("accept") and snd.played.has("back"),
		"focus, accept and back: %s" % [snd.played])
	# the help line: every row of every section has its line, and it follows the focus
	m.close_page()
	m.open_page("settings")
	await process_frame
	var sp := m.settings_panel
	var missing := []
	for sec in SettingsPanel.SECTIONS:
		sp.show_section(sec)
		for k in sp.rows:
			if (sp.rows[k] as MenuRow).help == "":
				missing.append(k)
	t.ok(missing.is_empty(), "every settings row has a help line (missing: %s)" % [missing])
	sp.show_section("graphics")
	await process_frame
	sp.rows["vsync"].grab_focus()
	await process_frame
	await process_frame
	t.ok(sp.help_label.text == SettingsPanel.HELP["vsync"] and sp.help_label.is_visible_in_tree(),
		"help line follows the focus: %s" % sp.help_label.text)
	sp.show_section("controls")
	await process_frame
	sp.binding_rows["let_fly"].grab_focus()
	await process_frame
	await process_frame
	t.ok(sp.help_label.text.begins_with("Enter or A"), "a binding's help: %s" % sp.help_label.text)
	sp.tabs["audio"].grab_focus()
	await process_frame
	await process_frame
	t.ok(sp.help_label.text == SettingsPanel.HELP["tab"], "a tab's help")
	sp.close()
	m.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
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
