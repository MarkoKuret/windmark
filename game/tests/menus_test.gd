extends SceneTree
## Menus tests (menus.md): the lists come from the data on disk, the stepped race setup and the free sail write GameSetup and
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
	await test_light_rows()
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
	var quit := MenuTheme.button("Reset section", MenuTheme.ACTION_SIZE, true)
	t.ok(quit.get_theme_color("font_color") == MenuTheme.SIGNAL and quit.text == "RESET SECTION",
		"a destructive action: red caps")
	t.ok(quit.custom_minimum_size.y >= MenuTheme.ACTION_H, "footer actions are at least %d px tall" % MenuTheme.ACTION_H)
	var item := MenuTheme.button("Quit")
	t.ok(not item.has_theme_color_override("font_color") and th.get_color("font_color", "Button") == MenuTheme.NAVY
		and item.custom_minimum_size.y >= MenuTheme.ITEM_H,
		"menu items: navy, at least %d px tall" % MenuTheme.ITEM_H)
	item.free()
	var pnl := MenuTheme.panel()
	t.ok(pnl.shadow_size == 0 and pnl.border_width_bottom == 0, "cloth panels are flat: no shadow, no edge")
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
	s.keys_toggle = true
	s.weather_helm = true
	s.vibration = 0.3
	s.camera_speed = 1.75
	s.invert_x = true
	s.invert_y = true
	s.heel_follow = 0.4
	s.reduced_motion = true
	s.assist = Hud.Assist.MINIMAL
	s.hud_density = Hud.Density.DATA
	s.ui_scale = 1.15
	s.palette = "tritanopia"
	s.quality = SeaQuality.Tier.H
	s.render_scale = 0.75
	s.aa = "fxaa"
	s.fullscreen = true
	s.vsync = false
	s.fps_limit = 90
	s.capture_preset = "portrait"
	s.master_volume = 0.5
	s.effects_volume = 0.25
	s.signals_volume = 0.75
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
		# adapter, vendor, device type, Steam Deck, class, the anti-aliasing a first start picks
		["Intel(R) UHD Graphics 620", "Intel", IG, false, I, "fxaa"],
		["Intel(R) Iris(R) Xe Graphics", "Intel", IG, false, I, "fxaa"],
		["Intel(R) HD Graphics 520", "Intel", -1, false, I, "fxaa"],
		["Mesa Intel(R) UHD Graphics 620 (KBL GT2)", "Intel", IG, false, I, "fxaa"],
		["Intel(R) Arc(TM) Graphics", "Intel", IG, false, I, "fxaa"],
		["Intel(R) Arc(TM) A770 Graphics", "Intel", DG, false, D, "smaa"],
		["Intel(R) Arc(TM) B580 Graphics", "Intel", -1, false, D, "smaa"],
		["AMD Radeon(TM) Graphics", "AMD", IG, false, I, "fxaa"],
		["AMD Radeon(TM) Vega 8 Graphics", "AMD", -1, false, I, "fxaa"],
		["AMD Radeon(TM) RX Vega 10 Graphics", "AMD", IG, false, I, "fxaa"],
		["AMD Radeon 780M", "AMD", -1, false, I, "fxaa"],
		["AMD Radeon Graphics (RADV RENOIR)", "AMD", IG, false, I, "fxaa"],
		["AMD Radeon RX 6600", "AMD", DG, false, D, "smaa"],
		["AMD Radeon RX 7600M XT", "AMD", DG, false, D, "smaa"],
		["AMD Radeon Pro 5500M", "AMD", DG, false, D, "smaa"],
		["NVIDIA GeForce RTX 3060", "NVIDIA", DG, false, D, "smaa"],
		["NVIDIA GeForce MX450", "NVIDIA", DG, false, D, "smaa"],
		["Apple M1", "Apple", IG, false, Settings.Gpu.APPLE, "smaa"],
		["Apple M5", "Apple", -1, false, Settings.Gpu.APPLE, "smaa"],
		["AMD Custom GPU 0405 (RADV VANGOGH)", "AMD", IG, false, Settings.Gpu.STEAM_DECK, "smaa"],
		["AMD Custom GPU 0932", "AMD", IG, false, Settings.Gpu.STEAM_DECK, "smaa"],
		["AMD Radeon Graphics", "AMD", IG, true, Settings.Gpu.STEAM_DECK, "smaa"],
		["llvmpipe (LLVM 15.0.7, 256 bits)", "Mesa", RenderingDevice.DEVICE_TYPE_CPU, false, I, "fxaa"],
		["Qualcomm(R) Adreno(TM) X1-85 GPU", "Qualcomm", IG, false, I, "fxaa"],
		["Some New GPU", "Unknown", IG, false, I, "fxaa"],
		["Some New GPU", "Unknown", DG, false, D, "smaa"],
		["", "", -1, false, Settings.Gpu.UNKNOWN, "smaa"],
	]
	var wrong := []
	for c in cases:
		var got := Settings.gpu_class(c[0], c[1], c[2], c[3])
		if got != c[4]:
			wrong.append("%s -> %s (want %s)" % [c[0], Settings.Gpu.keys()[got], Settings.Gpu.keys()[c[4]]])
		elif Settings.device_graphics(got)["aa"] != c[5]:
			wrong.append("%s -> %s (want %s)" % [c[0], Settings.device_graphics(got)["aa"], c[5]])
	t.ok(wrong.is_empty(), "adapter classes and anti-aliasing from %d names %s" % [cases.size(), wrong])
	var g := Settings.device_graphics(I)
	t.ok(g["quality"] == SeaQuality.Tier.L and is_equal_approx(g["render_scale"], 0.67) and g["aa"] == "fxaa",
		"integrated: tier L at 67 %, FXAA")
	g = Settings.device_graphics(Settings.Gpu.STEAM_DECK)
	t.ok(g["quality"] == SeaQuality.Tier.L and g["render_scale"] == 0.0 and g["aa"] == "smaa",
		"Steam Deck: tier L, Auto (native), SMAA")
	for k in [D, Settings.Gpu.APPLE, Settings.Gpu.UNKNOWN]:
		g = Settings.device_graphics(k)
		t.ok(g["quality"] == SeaQuality.Tier.M and g["render_scale"] == 0.0 and g["aa"] == "smaa",
			"%s: today's defaults (M, Auto, SMAA)" % Settings.Gpu.keys()[k])
	# the first start: no file, so the detected device decides; a file keeps the player's values
	var first := "user://menus_test_first_start.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(first))
	Settings.path = first
	Settings.gpu_override = I
	Settings.reset_current()
	var s := Settings.current()
	t.ok(s.quality == SeaQuality.Tier.L and is_equal_approx(s.render_scale, 0.67) and s.aa == "fxaa",
		"first start on an integrated GPU: tier L at 67 %, FXAA")
	s.quality = SeaQuality.Tier.H
	s.render_scale = 1.0
	s.aa = "smaa"
	s.save_file()
	Settings.reset_current()
	s = Settings.current()
	t.ok(s.quality == SeaQuality.Tier.H and s.render_scale == 1.0 and s.aa == "smaa",
		"a saved file keeps the player's choice")
	s.reset("graphics")
	t.ok(s.quality == SeaQuality.Tier.L and is_equal_approx(s.render_scale, 0.67) and s.aa == "fxaa",
		"Reset Graphics: the device defaults")
	# an older file without the key: SMAA, whatever the device
	var cf := ConfigFile.new()
	cf.load(first)
	cf.erase_section_key("graphics", "aa")
	cf.save(first)
	Settings.reset_current()
	t.ok(Settings.current().aa == "smaa", "a settings file from before the key keeps SMAA on an integrated GPU")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(first))
	Settings.gpu_override = Settings.Gpu.APPLE
	Settings.reset_current()
	s = Settings.current()
	t.ok(s.quality == SeaQuality.Tier.M and s.render_scale == 0.0 and s.aa == "smaa",
		"first start on Apple silicon: M, Auto, SMAA")
	Settings.gpu_override = Settings.Gpu.STEAM_DECK
	Settings.reset_current()
	s = Settings.current()
	t.ok(s.quality == SeaQuality.Tier.L and s.render_scale == 0.0 and s.aa == "smaa",
		"first start on a Steam Deck: L, Auto, SMAA")
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
	cf.set_value("controls", "vibration", 9.0)
	cf.set_value("hud", "assist", 7)
	cf.set_value("graphics", "vsync", 3)
	cf.set_value("graphics", "render_scale", 7)
	cf.set_value("graphics", "aa", "msaa")
	t.ok(not cf.has_section_key("graphics", "capture_preset") and back.capture_preset == "off",
		"the capture preset is session only: not saved, Off after a load (menus.md §3)")
	cf.set_value("graphics", "capture_preset", "portrait")
	cf.save(TEST_PATH)
	var d := Settings.new()
	d.load_file(TEST_PATH)
	t.near(d.stick_dead_zone, 0.10, 1e-9, "wrong type keeps the default")
	t.near(d.vibration, 1.0, 1e-9, "vibration clamped to 100 %")
	t.ok(d.assist == Hud.Assist.MINIMAL, "assist clamped to Minimal")
	t.ok(d.vsync == true, "vsync of the wrong type keeps the default")
	t.near(d.render_scale, 1.0, 1e-9, "render scale clamped to 100 %")
	t.ok(d.aa == "smaa", "an unknown anti-aliasing keeps SMAA")
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
	t.ok(pc.let_fly_toggle and pc.helm_fine_toggle, "controls: the held keys as toggles")
	var rig := CameraRig.new()
	s.apply_cameras(rig)
	var o := rig.options
	t.near(o.speed, 1.75, 1e-9, "cameras: speed")
	t.ok(o.invert_orbit_x and o.invert_orbit_y and o.invert_look_x and o.invert_look_y,
		"cameras: one inversion per axis on the orbit and the look")
	t.ok(o.reduced_motion and o.boost_toggle, "cameras: reduced motion, the boost as a toggle")
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
	# the player's setting (menus.md §3), the temporal upscalers over it, the command line over both
	t.ok(Settings.screen_space_aa(Viewport.SCALING_3D_MODE_FSR, "fxaa") == Viewport.SCREEN_SPACE_AA_FXAA, "setting: FXAA")
	t.ok(Settings.screen_space_aa(Viewport.SCALING_3D_MODE_FSR2, "fxaa") == Viewport.SCREEN_SPACE_AA_DISABLED,
		"no FXAA under FSR2 either")
	a.aa = "fxaa"
	a.apply_render_scale(root)
	t.ok(root.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA, "the FXAA setting on the root viewport")
	a.aa = "smaa"
	a.apply_render_scale(root)
	t.ok(root.screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA, "and SMAA again")
	Settings.aa_override = "fxaa"
	t.ok(Settings.screen_space_aa(Viewport.SCALING_3D_MODE_FSR) == Viewport.SCREEN_SPACE_AA_FXAA, "--aa=fxaa for this run")
	Settings.aa_override = "smaa"
	t.ok(Settings.screen_space_aa(Viewport.SCALING_3D_MODE_FSR, "fxaa") == Viewport.SCREEN_SPACE_AA_SMAA,
		"--aa=smaa over the FXAA setting")
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


## menus.md §3 "Where each setting goes": every key of the settings file reaches its target (only settings the game
## reads are offered).
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
		"controls.keys_toggle": pc.let_fly_toggle and pc.helm_fine_toggle and hud.rankings_toggle
			and rig.options.boost_toggle,
		"controls.vibration": is_equal_approx(pc.rumble.strength, s.vibration),
		# applied at world creation (core_sim_source.gd create), not by apply_controls
		"controls.weather_helm": s.weather_helm == true,
		"cameras.camera_speed": is_equal_approx(rig.options.speed, s.camera_speed),
		"cameras.invert_x": rig.options.invert_orbit_x and rig.options.invert_look_x,
		"cameras.invert_y": rig.options.invert_orbit_y and rig.options.invert_look_y,
		"cameras.heel_follow": is_equal_approx(rig.onboard.heel_follow, s.heel_follow),
		"cameras.reduced_motion": rig.options.reduced_motion,
		"hud.assist": hud.assist == s.assist,
		"hud.hud_density": hud.density == s.hud_density and not hud.density_auto,
		"hud.ui_scale": is_equal_approx(root.content_scale_factor, s.ui_scale),
		"hud.palette": HudStyle.palette == "tritanopia" and HudStyle.STBD == HudStyle.PALETTES["tritanopia"][0]
			and HudStyle.TINTS[RaceHudValues.Tint.RED] == HudStyle.PALETTES["tritanopia"][1],
		"graphics.quality": sea.quality == s.quality,
		"graphics.render_scale": is_equal_approx(root.scaling_3d_scale, s.render_scale),
		"graphics.aa": root.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA,
		"graphics.fullscreen": DisplayServer.get_name() == "headless",  # the window mode: not in headless runs
		"graphics.vsync": DisplayServer.get_name() == "headless",
		"graphics.fps_limit": Engine.max_fps == s.fps_limit,
		"menu.last_setup": true,  # the setup pages and Continue (test_main_menu, test_touches)
		"menu.welcomed": true,  # the first-launch screen (test_touches)
		"bindings.bindings": Bindings.slots("let_fly") == s.bindings["let_fly"],
	}
	for f in Settings.BUSES:
		var ok := true
		for b in Settings.BUSES[f]:
			ok = ok and (absf(bus.call(b) - float(s.get(f))) < 1e-3 or (float(s.get(f)) <= 0.0
				and AudioServer.is_bus_mute(AudioServer.get_bus_index(b))))
		got["audio." + f] = ok
	for sec in Settings.FIELDS:
		for f in Settings.FIELDS[sec]:
			var k: String = sec + "." + f
			t.ok(got.get(k, false), "%s applied" % k)
	t.ok("voice" in Settings.BUSES["signals_volume"], "the signals volume drives the hails' voice bus too")
	# a file from an older build with the dropped keys: the others load, the dropped ones are not written again
	var old := ConfigFile.new()
	old.set_value("settings", "version", 1)
	old.set_value("hud", "captions", true)
	old.set_value("audio", "voice_volume", 0.2)
	old.set_value("controls", "stick_curve", 2.0)
	old.set_value("controls", "let_fly_toggle", true)
	old.set_value("cameras", "invert_look_y", true)
	old.set_value("cameras", "smooth_switch", true)
	old.set_value("audio", "master_volume", 0.4)
	var old_path := "user://menus_test_old.cfg"
	old.save(old_path)
	var older := Settings.new()
	t.ok(older.load_file(old_path) == OK and is_equal_approx(older.master_volume, 0.4), "an older file still loads")
	older.save_file(old_path)
	var back := ConfigFile.new()
	back.load(old_path)
	t.ok(not back.has_section_key("hud", "captions") and not back.has_section_key("audio", "voice_volume")
		and not back.has_section_key("controls", "stick_curve") and not back.has_section_key("controls", "let_fly_toggle")
		and not back.has_section_key("cameras", "invert_look_y") and not back.has_section_key("cameras", "smooth_switch"),
		"the dropped keys are not saved again")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(old_path))
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
		# the showcase boat (menus.md §4.1): the Boat step puts the chosen class on the water and the camera
		# circles it; the class swaps it, the sail number repaints it, leaving the step frees it
		root.size = Vector2i(1280, 800)
		m.open_page("quick")
		await process_frame
		await process_frame
		var st := m.stage
		var q := m.quick
		var cls0 := str(q.rows["class_id"].value)
		t.ok(st.showcase != null and st.showcase_class == cls0 and st.showcase.get_parent() == sc
			and st.showcase.model != null, "the Boat step: a showcase %s on the stage" % cls0)
		var sv := st._show_sails
		var info := st.showcase.info
		t.ok(sv != null and sv.sails.size() == info.sails.size() and sv.sails[info.main_sail].phase == SimSource.Phase.UP
			and sv.front >= 0 and sv.sails[sv.front].phase == SimSource.Phase.UP
			and sv.sails[info.main_sail].beta < 0.0 and sv.sails[sv.front].beta < 0.0,
			"the main and the headsail up, trimmed to port on starboard tack")
		var down := 0
		for i in sv.sails.size():
			if i != info.main_sail and i != sv.front:
				down += 1 if sv.sails[i].phase == SimSource.Phase.DOWN else 0
		t.ok(down == sv.sails.size() - 2, "the other sails down")
		var first := st.showcase
		for i in 20:
			await process_frame
		var at := st.showcase.global_position
		var want := Frames.enu_to_scene(MenuStage.SHOW_POS.x, MenuStage.SHOW_POS.y, 0.0)
		t.ok(Vector2(at.x, at.z).distance_to(Vector2(want.x, want.z)) < 0.01 and absf(at.y) < 3.0,
			"the boat sits at its place on the water: %s" % at)
		t.ok(absf(st._show_sails.awa - MenuStage.SHOW_AWA) < 1e-9 and MenuStage.SHOW_HEEL < 0.0, "heeled to port")
		var cp := cam.global_position
		var focus := Frames.enu_to_scene(MenuStage.SHOW_POS.x, MenuStage.SHOW_POS.y, 0.0)
		var dist := Vector2(cp.x, cp.z).distance_to(Vector2(focus.x, focus.z))
		var mast: float = MenuData.class_facts(cls0)["mast_height"]
		t.ok(absf(dist - (MenuStage.SHOW_DIST * mast + MenuStage.SHOW_DIST_ADD)) < 0.5
			and absf(cp.y - MenuStage.SHOW_HEIGHT * mast) < 0.5, "the camera circles it at %.1f m, %.1f m up" % [dist, cp.y])
		t.ok(st.frame_x > 0.0 and st.frame_x < 0.5 and st.frame_offset(cam) < 0.0,
			"the boat framed left of centre, clear of the page (frame_x %.2f)" % st.frame_x)
		var b0 := st._show_bearing
		for i in 10:
			await process_frame
		t.ok(st._show_bearing != b0, "the camera goes round")
		q.rows["class_id"].step_value(1)
		await process_frame
		var cls1 := str(q.rows["class_id"].value)
		t.ok(st.showcase != first and st.showcase_class == cls1 and (not is_instance_valid(first) or first.is_queued_for_deletion()),
			"a new class: a new showcase boat (%s), the old one freed" % cls1)
		var second := st.showcase
		var lv0 := st.showcase_livery
		q.rows["livery"].step_value(1)
		await process_frame
		t.ok(st.showcase == second and st.showcase_livery != lv0 and st.showcase_livery == str(q.rows["livery"].value),
			"a new sail number repaints the same boat: %s" % st.showcase_livery)
		q.next()
		await process_frame
		t.ok(st.showcase == null and st.showcase_class == "", "the Venue step: the showcase boat freed")
		for i in 5:
			await process_frame
		var p2 := cam.global_position
		var d2 := Vector2(p2.x, p2.z).distance_to(Vector2(st._focus.x, st._focus.z))
		t.ok(d2 > MenuStage.DIST.x * 0.8 and d2 < MenuStage.DIST.y * 1.2, "the drift is back on the fleet at %.0f m" % d2)
		m.close_page()
		await process_frame
		t.ok(st.showcase == null, "no showcase boat on the menu")
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
	t.begin("main menu: the race setup's steps and the free sail")
	Settings.reset_current()
	Settings.current().welcomed = true
	var m := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	m.change_scenes = false
	m.live_backdrop = false
	var asked: Array[String] = []
	m.scene_requested.connect(func(p: String) -> void: asked.append(p))
	root.add_child(m)
	await process_frame
	root.size = Vector2i(1280, 800)
	await process_frame
	await process_frame
	t.ok(root.gui_get_focus_owner() == m.buttons["quick"], "focus starts on Race")
	t.ok(InputMap.action_get_events("ui_accept").any(func(e: InputEvent) -> bool:
		return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_A)
		and InputMap.action_get_events("ui_cancel").any(func(e: InputEvent) -> bool:
		return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_B), "the pad's A accepts and B goes back")
	# menus.md §1: the items in order with their hints, the key line
	var names := []
	for e in MainMenu.ITEMS:
		names.append(m.buttons[e[0]].text)
	t.ok(names == ["CONTINUE", "RACE", "FREE SAIL", "SETTINGS", "QUIT"], "items: %s" % [names])
	for id in ["quick", "free", "settings"]:
		var hint := m.find_child("Hint_" + id, true, false) as Label
		t.ok(hint != null and hint.text != "" and hint.is_visible_in_tree(), "%s has its hint: %s" % [id, hint.text if hint else ""])
	t.ok(m.find_child("Hint_quit", true, false) == null, "Quit has no hint")
	t.ok((m.find_child("KeyLine", true, false) as Label).text == MainMenu.KEY_LINE, "the key line")
	var q := m.quick
	t.ok(q.steps == SetupPanel.STEPS_RACE and m.free_sail.steps == SetupPanel.STEPS_FREE, "four race steps, three free sail steps")
	t.ok(q.rows["class_id"].choices == MenuData.ids(MenuData.classes()), "race: classes from disk")
	t.ok(q.rows["venue"].choices == MenuData.ids(MenuData.venues()), "race: venues from disk")
	t.ok(q.rows["course"].choices.has("practice_waters/example_wl"), "race: the venue's courses")
	t.ok(q.rows["livery"].choices == MenuData.ids(MenuData.liveries(str(q.rows["class_id"].value)))
		and q.rows["livery"].choices.size() >= 12, "race: the class's boats (sail numbers) from disk")
	t.ok(q.rows["class_id"].is_picker and q.rows["venue"].is_picker and not q.rows["livery"].is_picker,
		"the class and the venue are pickers")
	# keyboard: Enter opens Race at the Boat step, the menu card hidden, the page narrow, the focus on the picker
	var boats: Array = []
	q.boat_changed.connect(func(c: String, l: String) -> void: boats.append([c, l]))
	_key("ui_accept")
	await process_frame
	await process_frame
	t.ok(m.page == "quick" and q.is_visible_in_tree() and q.step_id() == "boat", "Enter opens Race at the Boat step")
	t.ok(not m._card.visible, "the menu card is hidden while the page shows")
	t.ok(root.gui_get_focus_owner() == q.rows["class_id"], "focus on the class picker")
	t.ok(q.narrow_page() and absf(m.page_width() - (SetupPanel.NARROW_W + 56.0)) < 1.0,
		"the Boat step's page is narrow: %d px" % m.page_width())
	t.ok(q.class_line.text == MenuData.class_line("wm7") and q.class_line.is_visible_in_tree(), "the class's character line")
	t.ok(q._fact_values["length"].text == "7.2 m" and q._fact_values["sail_area"].text == "37 m²"
		and q._fact_values["crew"].text == "4" and q._fact_values["kite"].text == "Asymmetric 54 m²",
		"the key numbers: %s %s %s %s" % [q._fact_values["length"].text, q._fact_values["sail_area"].text,
		q._fact_values["crew"].text, q._fact_values["kite"].text])
	t.ok(not q._preview.visible and not q.rows["venue"].visible and not q.rows["fleet_size"].visible,
		"the Boat step shows no venue, course or race rows")
	var cls0 := str(q.rows["class_id"].value)
	_key("ui_right")
	await process_frame
	var cls1 := str(q.rows["class_id"].value)
	t.ok(cls1 != cls0 and cls1 == q.rows["class_id"].choices[(q.rows["class_id"].choices.find(cls0) + 1)
		% q.rows["class_id"].choices.size()], "right cycles the class: %s -> %s" % [cls0, cls1])
	t.ok(boats.size() == 1 and boats[0][0] == cls1, "the showcase boat follows: %s" % [boats])
	t.ok(q.class_line.text == MenuData.class_line(cls1) and q.rows["livery"].choices == MenuData.ids(MenuData.liveries(cls1)),
		"the character line and the sail numbers follow the class")
	_key("ui_left")
	await process_frame
	t.ok(str(q.rows["class_id"].value) == cls0, "left cycles back")
	_key("ui_down")
	await process_frame
	t.ok(root.gui_get_focus_owner() == q.rows["livery"], "down: the Sail number row")
	_key("ui_right")
	await process_frame
	t.ok(boats.size() == 3 and boats[2][1] == str(q.rows["livery"].value), "a new sail number repaints the showcase boat")
	_key("ui_down")
	await process_frame
	t.ok(root.gui_get_focus_owner() == q.next_button, "down from the last row: Next")
	_key("ui_left")
	await process_frame
	t.ok(root.gui_get_focus_owner() == q.back_button, "left from Next: Back")
	_key("ui_right")
	await process_frame
	_key("ui_accept")
	await process_frame
	await process_frame
	t.ok(q.step_id() == "venue" and root.gui_get_focus_owner() == q.rows["venue"], "Next: the Venue step, focus on the venue picker")
	t.ok(not q.narrow_page() and m.page_width() > SetupPanel.NARROW_W + 100.0, "the Venue step's page is wide: %d px" % m.page_width())
	t.ok(q._preview.visible and q.course_map.extent.has_area() and not q.course_map.land.is_empty(),
		"the venue chart: the venue's bounds and land")
	t.ok(q.venue_line.text == MenuData.venue_line("practice_waters") and q.rows["course"].visible, "the venue's line and the Course row")
	var ven0 := str(q.rows["venue"].value)
	_key("ui_right")
	await process_frame
	var ven1 := str(q.rows["venue"].value)
	t.ok(ven1 != ven0 and q.venue_line.text == MenuData.venue_line(ven1)
		and q.briefing_header.text.begins_with(MenuData.name_of(MenuData.venues(), ven1).to_upper()),
		"right cycles the venue, the line and the briefing follow: %s" % ven1)
	t.ok(q.course_map.extent == MenuData.venue_shapes(ven1)["bounds"], "the chart shows the new venue")
	_key("ui_left")
	await process_frame
	t.ok(str(q.rows["venue"].value) == ven0, "left cycles back")
	# Enter on a picker is Next (menus.md §1.1)
	_key("ui_accept")
	await process_frame
	await process_frame
	t.ok(q.step_id() == "race" and root.gui_get_focus_owner() == q.rows["fleet_size"], "Enter on the picker: the Race step, focus on Fleet")
	t.ok(not q.course_map.extent.has_area(), "the Race step's map is the course's")
	var fleet := int(q.rows["fleet_size"].value)
	_key("ui_right")
	_key("ui_right")
	await process_frame
	t.ok(int(q.rows["fleet_size"].value) == fleet + 2, "right x2: fleet %d -> %d" % [fleet, q.rows["fleet_size"].value])
	for i in 5:
		_key("ui_down")
		await process_frame
	t.ok(root.gui_get_focus_owner() == q.next_button, "down x5 (AI level, Weather, Time, Sky): Next")
	_key("ui_accept")
	await process_frame
	await process_frame
	t.ok(q.step_id() == "start" and root.gui_get_focus_owner() == q.start_button, "the Start step, focus on Start race")
	var sl := q.summary_lines()
	t.ok(sl.size() == 6 and sl[0][0] == "Boat" and sl[3][1] == "%d boats · Easy" % (fleet + 2)
		and sl[4][1] == "Local", "the summary: %s" % [sl])
	# Esc goes back one step, from the first step to the menu
	_key("ui_cancel")
	await process_frame
	await process_frame
	t.ok(q.step_id() == "race" and root.gui_get_focus_owner() == q.rows["fleet_size"], "Esc: back to the Race step")
	q.go(3)
	await process_frame
	q.rows["class_id"].set_value("wm12", true)
	t.ok(q.rows["livery"].choices == MenuData.ids(MenuData.liveries("wm12")), "the sail number list follows the class")
	q.rows["livery"].set_value("nightjar", true)
	q.rows["ai_level"].set_value("pro", true)
	q.rows["wind_kn"].set_value(15.0, true)
	q.rows["wind_from_deg"].set_value(90.0, true)
	q.start_button.grab_focus()
	await process_frame
	_key("ui_accept")
	await process_frame
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
	# Esc from the first step closes the page to the menu; the card is back
	q.go(0)
	await process_frame
	_key("ui_cancel")
	await process_frame
	t.ok(m.page == "" and m._card.visible and root.gui_get_focus_owner() == m.buttons["quick"], "Esc from the Boat step: back to the menu")
	# the gamepad: A opens Race, the D-pad cycles the class and reaches Next, A goes on, B goes back
	_pad(JOY_BUTTON_A)
	await process_frame
	await process_frame
	t.ok(m.page == "quick" and q.step_id() == "boat" and root.gui_get_focus_owner() == q.rows["class_id"],
		"A opens Race at the Boat step")
	_pad(JOY_BUTTON_DPAD_RIGHT)
	await process_frame
	t.ok(str(q.rows["class_id"].value) != "wm12", "D-pad right cycles the class: %s" % q.rows["class_id"].value)
	_pad(JOY_BUTTON_DPAD_DOWN)
	_pad(JOY_BUTTON_DPAD_DOWN)
	await process_frame
	t.ok(root.gui_get_focus_owner() == q.next_button, "D-pad down x2: Next")
	_pad(JOY_BUTTON_A)
	await process_frame
	await process_frame
	t.ok(q.step_id() == "venue", "A: the Venue step")
	_pad(JOY_BUTTON_B)
	await process_frame
	await process_frame
	t.ok(q.step_id() == "boat" and root.gui_get_focus_owner() == q.rows["class_id"], "B: back to the Boat step")
	_pad(JOY_BUTTON_B)
	await process_frame
	t.ok(m.page == "" and root.gui_get_focus_owner() == m.buttons["quick"], "B: back to the menu")
	# the step bar: a click on a step done goes back to it
	m.open_page("quick")
	await process_frame
	q.go(2)
	await process_frame
	q.step_buttons[0].pressed.emit()
	await process_frame
	t.ok(q.step_id() == "boat", "the step bar: a click on 1 Boat goes back to it")
	q.step_buttons[3].pressed.emit()
	await process_frame
	t.ok(q.step_id() == "boat", "a step ahead cannot be clicked")
	m.close_page()
	# Free sail: Boat, Venue, Set sail; the weather rows on the last step with the summary; Set sail starts
	m.buttons["free"].pressed.emit()
	await process_frame
	var f := m.free_sail
	t.ok(m.page == "free" and f.step_id() == "boat" and f.narrow_page(), "Free sail opens at the Boat step")
	f.next()
	await process_frame
	t.ok(f.step_id() == "venue" and not f.rows.has("course") and f.course_map.extent.has_area(), "Venue step: the chart, no Course row")
	f.next()
	await process_frame
	t.ok(f.step_id() == "sail" and f.rows["weather"].visible and f.summary.get_parent().visible
		and f.primary() == f.start_button and f.start_button.text == "SET SAIL", "Set sail step: weather rows, the summary, Set sail")
	f.rows["wind_kn"].set_value(8.0, true)
	f.start_button.pressed.emit()
	t.ok(g.mode == "free" and g.class_id == "wm12" and absf(g.wind_kn - 8.0) < 1e-9,
		"free sail: mode free, the remembered class, its wind")
	t.ok(asked.size() == 2 and asked[1] == MainMenu.SAIL_SCENE, "sail scene requested again")
	# settings page: a change is saved on close
	m.close_page()
	m.open_page("settings")
	await process_frame
	t.ok(not m._card.visible, "the menu card hides for the settings too")
	m.settings_panel.show_section("graphics")
	m.settings_panel.rows["fps_limit"].set_value(60, true)
	t.ok(Engine.max_fps == 60, "frame rate limit applied at once")
	m.settings_panel.close()
	saved.load_file(TEST_PATH)
	t.ok(saved.fps_limit == 60 and m.page == "" and m._card.visible, "settings saved on close, the card back")
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
	# Steam Deck and the portrait capture window: every page and every step inside 1280 x 800 and 1080 x 1920 at
	# 80 %, 100 % and 130 %: the page, Back, the primary action, the step bar; the menu card when no page shows
	for scr in [Vector2i(1280, 800), Vector2i(1080, 1920)]:
		root.size = scr
		for sc in [0.8, 1.0, 1.3]:
			m.settings.ui_scale = sc
			m.settings.apply_display(root)
			await process_frame
			await process_frame
			var vis := root.get_visible_rect().grow(1)
			t.ok(vis.encloses(m._card.get_global_rect()) and vis.encloses(m.buttons["quit"].get_global_rect()),
				"the menu card within %s at %d %%: %s" % [scr, roundi(sc * 100), m._card.get_global_rect()])
			t.ok(m.hints_shown() == (scr != Vector2i(1280, 800) or sc < 1.3),
				"the hints show when the card fits (%s at %d %%: %s)" % [scr, roundi(sc * 100), m.hints_shown()])
			for p in ["quick", "free", "settings"]:
				m.open_page(p)
				await process_frame
				await process_frame
				var sp: SetupPanel = m.quick if p == "quick" else m.free_sail if p == "free" else null
				var n_steps := sp.steps.size() if sp != null else 1
				for i in n_steps:
					if sp != null:
						sp.go(i)
						await process_frame
						await process_frame
					var need: Array = [m._panel]
					if sp != null:
						need.append_array([sp.back_button, sp.primary(), sp.step_buttons[i], sp.first_row()])
					else:
						need.append(m.settings_panel.get_child(-1))
					var inside := true
					for c in need:
						inside = inside and vis.encloses((c as Control).get_global_rect())
					if not inside:
						print("  vis %s: %s" % [vis, need.map(func(c: Control) -> Rect2: return c.get_global_rect())])
					t.ok(inside, "%s%s within %s at %d %%" % [p, " step " + sp.step_id() if sp else "", scr, roundi(sc * 100)])
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


## A gamepad button press and release.
func _pad(button: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	root.push_input(e)
	var r := InputEventJoypadButton.new()
	r.button_index = button
	r.pressed = false
	root.push_input(r)


## menus.md §1.1, §1.1.1: the course map from the course file, the venue chart with the land, the keys on the Race
## step, the layout of every step at the Deck's size and in portrait.
func test_race_card() -> void:
	t.begin("race setup: the race card, the chart and the layout")
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
	# the venue chart (menus.md §1.1.1): the venue's bounds and land, a scale bar, the marks at their place
	var shapes := MenuData.venue_shapes("practice_waters")
	t.ok(shapes["bounds"] == Rect2(-2000, -2000, 4000, 5400) and shapes["land"].size() == 1,
		"Practice Waters: bounds %s, %d land polygon" % [shapes["bounds"], shapes["land"].size()])
	for v in MenuData.ids(MenuData.venues()):
		var sh := MenuData.venue_shapes(v)
		t.ok(sh["bounds"].has_area(), "%s has bounds for the chart" % v)
	var cm := CourseMap.new()
	cm.size = Vector2(400, 400)
	cm.show_course(c, 0.0, 12.0, true, shapes["land"], shapes["bounds"])
	var k := cm.scale_px()
	t.near(k * 5400.0, 400.0 - 16.0, 0.5, "the chart fits the venue's taller side: %.4f px per m" % k)
	t.ok(cm.scale_length(k) == 1000.0 and CourseMap.scale_text(1000.0) == "1 km", "scale bar 1 km on a 400 px chart")
	t.ok(cm.land_px().size() == 1 and cm.land_px()[0].size() == 12, "the island in px")
	var fit := cm._fit()
	var w_px: Vector2 = fit.call(p["w"])
	t.ok(w_px.x > 180.0 and w_px.x < 220.0 and w_px.y > 200.0, "the windward mark on the chart where the racing is: %s" % w_px)
	cm.show_course(c, 0.0, 12.0, true, shapes["land"], Rect2())
	t.ok(cm.scale_length(cm.scale_px()) == 0.0 and not cm.extent.has_area(), "the course map has no scale bar")
	cm.free()
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
	q.go(2)
	await process_frame
	t.ok(q.course_map != null and q.course_map.points.has("w"), "the course map shows the chosen course")
	q.rows["weather"].set_value("custom", true)
	q.rows["wind_from_deg"].set_value(90.0, true)
	q.rows["wind_kn"].set_value(18.0, true)
	t.ok(absf(q.course_map.wind_from_deg - 90.0) < 1e-6 and absf(q.course_map.wind_kn - 18.0) < 1e-6
		and q.course_map.points["w"].x > 600.0, "the map follows the wind rows")
	q.rows["fleet_size"].set_value(12.0, true)
	q.rows["ai_level"].set_value("pro", true)
	t.ok(q.course_map.caption == "2 laps, 6 legs", "course caption: %s" % q.course_map.caption)
	# keyboard: down from the last row is Next, up from Next the last row (Sky, after the weather rows)
	t.ok(q.last_row() == q.rows["light_conditions"], "Custom: the last row is Sky")
	q.rows["light_conditions"].grab_focus()
	await process_frame
	_key("ui_down")
	await process_frame
	t.ok(root.gui_get_focus_owner() == q.next_button, "down from the last row: Next")
	_key("ui_up")
	await process_frame
	t.ok(root.gui_get_focus_owner() == q.rows["light_conditions"], "up from Next: the last row")
	q.rows["weather"].set_value("local", true)
	t.ok(q.last_row() == q.rows["light_conditions"] and not q.rows["wind_kn"].visible, "Local: the Custom rows hidden")
	q.rows["weather"].grab_focus()
	await process_frame
	_key("ui_down")
	await process_frame
	t.ok(root.gui_get_focus_owner() == q.rows["light_time"], "Local: down from Weather is Time")
	_key("ui_down")
	await process_frame
	_key("ui_down")
	await process_frame
	t.ok(root.gui_get_focus_owner() == q.next_button, "Local: down from Sky is Next")
	_key("ui_up")
	await process_frame
	t.ok(root.gui_get_focus_owner() == q.rows["light_conditions"], "Local: up from Next is Sky")
	q.rows["fleet_size"].grab_focus()
	await process_frame
	_key("ui_up")
	await process_frame
	t.ok(root.gui_get_focus_owner() == q.rows["fleet_size"], "up from the first row stays")
	# no course for the boat: Next stops on the Venue step with the reason, Start is disabled
	q.go(1)
	q.rows["course"].set_choices([], [])
	q.rows["course"].set_value("", false)
	q.start_button.disabled = true
	q.next_button.disabled = true
	q._note.text = "This venue has no course for this boat yet."
	t.ok(not q.can_start() and q.next_button.disabled and q._note.text.begins_with("This venue has no course"),
		"no course: Next and Start blocked with the reason")
	q._refresh_courses()
	t.ok(q.can_start() and not q.next_button.disabled and q._note.text == "", "a course again: unblocked")
	# the layout of every step: the right column beside the rows when there is room, under them when not; the
	# primary action always on screen; the chart and the briefing on screen on the wide steps
	for c2 in [[Vector2i(1280, 800), 0.8], [Vector2i(1280, 800), 1.0], [Vector2i(1280, 800), 1.3],
			[Vector2i(1080, 1920), 0.8], [Vector2i(1080, 1920), 1.0], [Vector2i(1080, 1920), 1.3]]:
		root.size = c2[0]
		m.settings.ui_scale = c2[1]
		m.settings.apply_display(root)
		for i in q.steps.size():
			q.go(i)
			await process_frame
			await process_frame
			var vis := root.get_visible_rect().grow(1)
			var wide: bool = q.size.x >= SetupPanel.TWO_COLUMNS_MIN
			print("  %s %s at %d %%: page %d px, %s" % [q.step_id(), c2[0], roundi(c2[1] * 100), q.size.x,
				"two columns" if wide else "one column"])
			t.ok(q.body.vertical != wide, "%s %s at %d %%: %s (page %d px)" % [q.step_id(), c2[0], roundi(c2[1] * 100),
				"preview beside the rows" if wide else "preview under the rows", q.size.x])
			t.ok(vis.encloses(q.primary().get_global_rect()) and vis.encloses(q.back_button.get_global_rect()),
				"%s: Back and the primary action on screen" % q.step_id())
			if q.step_id() == "boat":
				t.ok(q.narrow_page() and not q._preview.visible, "the Boat step: no preview column")
				t.ok(vis.encloses(q.facts.get_global_rect()) and vis.encloses(q.rows["livery"].get_global_rect()),
					"the key numbers and the Sail number on screen")
			elif c2[0] == Vector2i(1280, 800) and c2[1] <= 1.0:
				t.ok(wide, "the logo leaves the %s step two columns at %d %%" % [q.step_id(), roundi(c2[1] * 100)])
			if wide and q.step_id() != "boat":
				t.ok(vis.encloses(q.course_map.get_global_rect()), "the map on screen")
				t.ok(vis.encloses(q.briefing.get_global_rect()), "the briefing on screen")
			# the last row and the primary action reachable by the keyboard at this size
			if q.last_row() != null:
				q.last_row().grab_focus()
				await process_frame
				_key("ui_down")
				await process_frame
				t.ok(root.gui_get_focus_owner() == q.primary(), "down to the primary action")
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
	q.go(2)  # the Race step holds the weather rows (menus.md §1.1)
	q.rows["venue"].set_value("practice_waters", true)
	t.ok(q.rows["weather"].choices == ["local", "random", "custom"] and q.rows["weather"].value == "local",
		"Weather row: Local, Random, Custom; Local by default")
	t.ok(q.rows["weather"].names == ["Local", "Random", "Custom"], "mode names: %s" % [q.rows["weather"].names])
	for k in SetupPanel.CUSTOM_ROWS:
		t.ok(not q.rows[k].visible, "Local: %s hidden" % k)
	t.ok(q.briefing_header.visible and q.briefing_header.text == "PRACTICE WATERS · Practice",
		"Local: the header %s" % q.briefing_header.text)
	t.ok(q.briefing_grid.get_child_count() == 14, "Local: seven lines with Light and the Tip (%d cells)"
		% q.briefing_grid.get_child_count())
	t.ok(q.briefing_text().contains("Light\t14:30, fair\nTip\t"), "Local: the Light line before the Tip")
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
		+ "Gusts\tModerate: to +25 %, frequent\nCurrent\tNone\nSea\tChop\nLight\t14:30, fair", "no conditions: %s" % ob.replace("\n", " / "))
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
			t.ok(vis.encloses(q.primary().get_global_rect()), "%s at %d %%: Next on screen" % [mode, roundi(sc * 100)])
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


## menus.md §1: the Time and Sky rows: Venue default or a pick, Surprise with Random weather, the venue's window,
## GameSetup.light_time and light_conditions, the briefing's Light line, remembered and given to Continue.
func test_light_rows() -> void:
	t.begin("quick race: Time and Sky rows")
	Settings.reset_current()
	Settings.current().welcomed = true
	var m := _menu()
	root.size = Vector2i(1280, 800)
	await process_frame
	m.open_page("quick")
	await process_frame
	await process_frame
	var q := m.quick
	q.go(2)  # the Race step holds the Time and Sky rows (menus.md §1.1)
	q.rows["venue"].set_value("practice_waters", true)
	q.rows["weather"].set_value("local", true)
	var tr: MenuRow = q.rows["light_time"]
	var sr: MenuRow = q.rows["light_conditions"]
	t.ok(tr.visible and sr.visible and tr.value == -1.0 and sr.value == "", "Time and Sky shown, Venue default")
	t.ok(tr.value_text() == "Venue default" and sr.value_text() == "Venue default", "both read Venue default")
	t.ok(tr.choices[1] == 10.0 and tr.choices[-1] == 18.5 and tr.choices.size() == 19,
		"Time: 10:00 to 18:30 in 30 min steps (%d values)" % tr.choices.size())
	t.ok(tr.names[1] == "10:00" and tr.names[-1] == "18:30", "Time names: %s .. %s" % [tr.names[1], tr.names[-1]])
	t.ok(sr.names == ["Venue default", "Clear", "Fair", "Hazy", "Overcast"], "Sky names: %s" % [sr.names])
	for n in sr.names + tr.names:
		t.ok(not str(n).contains("—"), "no em dash in %s" % n)
	q.start_button.pressed.emit()
	var g := GameSetup.current()
	t.ok(g.light_time == -1.0 and g.light_conditions == "", "Venue default: GameSetup light_time -1, conditions empty")
	m.open_page("quick")
	await process_frame
	tr.set_value(16.5, true)
	sr.set_value("overcast", true)
	t.ok(tr.value_text() == "16:30" and sr.value_text() == "Overcast", "picked 16:30, Overcast")
	t.ok(q.briefing_text().contains("Light\t16:30, overcast"), "the briefing's Light line follows the rows")
	# Random: both Surprise and fixed; the picks come back after it
	q.rows["weather"].set_value("random", true)
	t.ok(tr.value_text() == "Surprise" and sr.value_text() == "Surprise", "Random: Surprise")
	tr.step_value(1)
	t.ok(tr.value_text() == "Surprise", "Random: the row does not step")
	t.ok(not q.briefing_text().contains("Light"), "Random: no Light line")
	q.start_button.pressed.emit()
	g = GameSetup.current()
	t.ok(g.light_time == -1.0 and g.light_conditions == "", "Random: the seed decides (-1, empty)")
	t.ok(m.settings.last_setup.get("light_time") == 16.5 and m.settings.last_setup.get("light_conditions") == "overcast",
		"the picks are remembered, not Surprise")
	m.open_page("quick")
	await process_frame
	q.rows["weather"].set_value("custom", true)
	t.ok(tr.value == 16.5 and sr.value == "overcast", "leaving Random gives the picks back")
	q.start_button.pressed.emit()
	g = GameSetup.current()
	t.ok(g.light_time == 16.5 and g.light_conditions == "overcast", "GameSetup: 16.5 h, overcast")
	m.continue_last()
	t.ok(GameSetup.current().light_time == 16.5 and GameSetup.current().light_conditions == "overcast",
		"Continue keeps the light")
	m.open_page("quick")
	await process_frame
	# another venue: its window; a time it lacks falls back to Venue default
	if MenuData.ids(MenuData.venues()).has("garda"):
		tr.set_value(10.0, true)
		q.rows["venue"].set_value("garda", true)
		var w := VenueLook.load_venue("garda").race_window
		t.ok(tr.choices[1] == w.x and tr.choices[-1] == w.y, "Garda: Time over %s to %s" % [tr.names[1], tr.names[-1]])
		t.ok(tr.value == -1.0, "10:00 is outside Garda's window: Venue default")
		t.ok(sr.value == "overcast", "the Sky pick stays")
		tr.set_value(14.0, true)
		q.rows["venue"].set_value("practice_waters", true)
		t.ok(tr.value == 14.0, "back on Practice Waters 14:00 stays")
	t.ok(SetupPanel.light_from({"light_time": 3.0, "light_conditions": "foggy"}, "practice_waters", "local")
		== {"light_time": -1.0, "light_conditions": ""}, "a remembered time outside the window and unknown sky: defaults")
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
	t.ok(m.buttons["continue"].visible and m.continue_line.text.begins_with("Race ·") and
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
	# the help line: only where the name does not say it all (menus.md §3), and it follows the focus
	m.close_page()
	m.open_page("settings")
	await process_frame
	var sp := m.settings_panel
	var missing := []
	var shown := []
	for sec in SettingsPanel.SECTIONS:
		sp.show_section(sec)
		for k in sp.rows:
			shown.append(k)
			if (sp.rows[k] as MenuRow).help == "" and k in ["helm_mode", "stick_dead_zone", "keys_toggle",
					"heel_follow", "assist", "hud_density", "palette", "quality", "render_scale", "capture_preset"]:
				missing.append(k)
	t.ok(missing.is_empty(), "the rows that need it have a help line (missing: %s)" % [missing])
	t.ok(not "captions" in shown and not "voice_volume" in shown, "no captions or voice rows")
	t.ok((sp.rows["master_volume"] as MenuRow).help == "", "self-explanatory rows have no help line")
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


## a stand-in sail scene whose race is on (menus.md §2: Retire shows, Restart and Main menu ask first)
class _RaceHost extends Node:
	func can_retire() -> bool:
		return true

	func retire() -> bool:
		return true


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
	# the menu has the keys (controls.md §7): Enter on an item is not the chat, a stray capture or reset key waits
	sc.scripted_input = RawInput.new().press(&"chat").press(&"capture_pause").press(&"reset_boat").press(&"hud_hide")
	sc.step_frame(1.0 / 60.0)
	sc.scripted_input = RawInput.new()
	t.ok(not sc.controls.text_focus and not sc.capture.frozen and sc.hud.visible,
		"chat, capture and HUD keys do nothing while the menu is open")
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
	t.ok(acts == ["restart", "quit"] and not pm.is_open, "restart and main menu requested: %s" % [acts])
	# menus.md §2: while the player's race is on (the window of Retire) Restart and Main menu ask first
	acts.clear()
	var stub := _RaceHost.new()
	root.add_child(stub)
	pm.host = stub
	pm.open()
	pm.buttons["restart"].pressed.emit()
	t.ok(pm.is_open and acts.is_empty() and pm.buttons["restart"].text == "RESTART? PRESS AGAIN",
		"Restart in a race: the first press asks")
	pm.buttons["quit"].pressed.emit()
	t.ok(pm.is_open and acts.is_empty() and pm.buttons["quit"].text == "QUIT? PRESS AGAIN"
		and pm.buttons["restart"].text == "RESTART", "another item asks instead, the first question dropped")
	pm.buttons["quit"].pressed.emit()
	t.ok(acts == ["quit"] and not pm.is_open, "the second press quits")
	pm.open()
	pm.buttons["restart"].pressed.emit()
	pm._process(3.1)
	t.ok(pm.buttons["restart"].text == "RESTART", "the question expires after 3 s")
	pm.buttons["restart"].pressed.emit()
	t.ok(pm.is_open and acts == ["quit"] and pm.buttons["restart"].text == "RESTART? PRESS AGAIN", "a later press asks again")
	pm.buttons["restart"].pressed.emit()
	t.ok(acts == ["quit", "restart"] and not pm.is_open, "the second press within 3 s restarts")
	pm.host = sc
	stub.queue_free()
	sc.queue_free()
	await process_frame
