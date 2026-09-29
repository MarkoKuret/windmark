class_name SettingsPanel
extends VBoxContainer
## The settings screen (menus.md §3): five sections of rows over a Settings object. A change is written into the
## Settings at once and announced with `changed` (the owner applies it); close() saves the file.

signal changed(key: String)
signal closed

const SECTIONS := ["controls", "cameras", "hud", "graphics", "audio"]
const TITLES := ["Controls", "Cameras", "HUD", "Graphics", "Audio"]

var settings: Settings
## inside the pause menu Esc is `pause_menu` (it resumes, menus.md §4); B still goes back
var esc_is_pause := false
var section := "controls"
var rows := {}
var tabs := {}
var _body: VBoxContainer
var _scroll: ScrollContainer
var _done: Button
var _reset: Button


func build(s: Settings) -> void:
	settings = s
	name = "Settings"
	add_theme_constant_override("separation", 10)
	add_child(MenuTheme.heading("Settings"))
	var bar := HBoxContainer.new()
	bar.name = "Sections"
	bar.add_theme_constant_override("separation", 2)
	add_child(bar)
	for i in SECTIONS.size():
		var b := MenuTheme.button(TITLES[i], MenuTheme.ROW_SIZE)
		b.name = TITLES[i]
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			var sb := (MenuTheme.theme().get_stylebox(st, "Button") as StyleBoxFlat).duplicate() as StyleBoxFlat
			sb.content_margin_left = 10
			sb.content_margin_right = 10
			b.add_theme_stylebox_override(st, sb)
		var sec: String = SECTIONS[i]
		b.pressed.connect(func() -> void: show_section(sec))
		b.focus_entered.connect(func() -> void: show_section(sec, false))
		bar.add_child(b)
		tabs[sec] = b
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	_body = VBoxContainer.new()
	_body.name = "Rows"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 2)
	_scroll.add_child(_body)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	add_child(foot)
	_reset = MenuTheme.button("Reset section", MenuTheme.ROW_SIZE)
	_reset.name = "Reset"
	_reset.pressed.connect(func() -> void:
		settings.reset(section)
		for k in rows:
			changed.emit(k)
		show_section(section, false)
		_reset.grab_focus())
	foot.add_child(_reset)
	var hint := MenuTheme.label("LB / RB: section", MenuTheme.SMALL_SIZE, MenuTheme.MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(hint)
	_done = MenuTheme.button("Done", MenuTheme.ROW_SIZE)
	_done.name = "Done"
	_done.pressed.connect(close)
	foot.add_child(_done)
	show_section("controls", false)


func first_row() -> Control:
	return tabs[section]


## Shows a section's rows; `focus`: move the focus to its first row.
func show_section(sec: String, focus := true) -> void:
	if sec == section and _body.get_child_count() > 0 and not focus:
		_tab_style()
		return
	section = sec
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	rows.clear()
	match sec:
		"controls":
			_controls()
		"cameras":
			_cameras()
		"hud":
			_hud()
		"graphics":
			_graphics()
		"audio":
			_audio()
	_tab_style()
	_scroll.scroll_vertical = 0
	if focus and _body.get_child_count() > 0:
		for c in _body.get_children():
			if c.focus_mode != Control.FOCUS_NONE:
				(c as Control).grab_focus()
				break


func _tab_style() -> void:
	for sec in tabs:
		var b: Button = tabs[sec]
		var on: bool = sec == section
		b.add_theme_color_override("font_color", MenuTheme.ACCENT if on else MenuTheme.MUTED)
		b.add_theme_color_override("font_hover_color", MenuTheme.ACCENT if on else MenuTheme.NAVY)
		b.add_theme_color_override("font_focus_color", MenuTheme.ACCENT)


func _row(r: MenuRow) -> void:
	rows[r.key] = r
	_body.add_child(r)
	r.changed.connect(func(v: Variant) -> void:
		settings.set(r.key, v)
		settings._clamp()
		changed.emit(r.key))


func _sub(text: String) -> void:
	var l := MenuTheme.label(text, MenuTheme.SMALL_SIZE, MenuTheme.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(0, 30)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_body.add_child(l)


static func pct(v: float) -> String:
	return "%d %%" % roundi(v * 100.0)


func _hold(text: String, key: String) -> void:
	_row(MenuRow.choice(text, key, [false, true], ["Hold", "Toggle"], settings.get(key)))


func _controls() -> void:
	var s := settings
	_row(MenuRow.choice("Helm keys", "helm_mode", [0, 1], ["Set and hold", "Hold to steer"], s.helm_mode))
	_row(MenuRow.range_row("Stick dead zone", "stick_dead_zone", 0.0, 0.30, 0.01, s.stick_dead_zone,
		func(v: float) -> String: return "%.2f" % v))
	_row(MenuRow.range_row("Stick curve", "stick_curve", 1.0, 3.0, 0.1, s.stick_curve,
		func(v: float) -> String: return "%.1f" % v))
	_row(MenuRow.range_row("Sheet key rate", "sheet_rate", 0.5, 2.0, 0.1, s.sheet_rate,
		func(v: float) -> String: return "× %.1f" % v))
	_row(MenuRow.toggle("Sheeting turns auto trim off", "sheet_turns_auto_trim_off", s.sheet_turns_auto_trim_off))
	_hold("Let fly", "let_fly_toggle")
	_hold("Fine helm", "helm_fine_toggle")
	_hold("Rankings", "rankings_toggle")
	_hold("Camera boost", "camera_boost_toggle")
	_row(MenuRow.range_row("Vibration", "vibration", 0.0, 1.0, 0.1, s.vibration,
		func(v: float) -> String: return "Off" if v <= 0.0 else pct(v)))
	_sub("Bindings  (changing them comes in a later update)")
	for action in DefaultBindings.table():
		var r := MenuRow.info(action_name(action), binding_text(action))
		_body.add_child(r)


func _cameras() -> void:
	var s := settings
	_row(MenuRow.range_row("Camera and look speed", "camera_speed", 0.25, 3.0, 0.25, s.camera_speed,
		func(v: float) -> String: return "× %.2f" % v))
	_row(MenuRow.toggle("Invert orbit, left and right", "invert_orbit_x", s.invert_orbit_x))
	_row(MenuRow.toggle("Invert orbit, up and down", "invert_orbit_y", s.invert_orbit_y))
	_row(MenuRow.toggle("Invert look, left and right", "invert_look_x", s.invert_look_x))
	_row(MenuRow.toggle("Invert look, up and down", "invert_look_y", s.invert_look_y))
	_row(MenuRow.range_row("Onboard heel follow", "heel_follow", 0.0, 1.0, 0.1, s.heel_follow,
		func(v: float) -> String: return "Level horizon" if v <= 0.0 else pct(v)))
	_row(MenuRow.toggle("Smooth camera switch", "smooth_switch", s.smooth_switch))
	_row(MenuRow.toggle("Reduced motion", "reduced_motion", s.reduced_motion))
	_sub("Reduced motion: no camera shake, a level horizon and a calmer chase camera.")


func _hud() -> void:
	var s := settings
	_row(MenuRow.choice("Assists", "assist", [0, 1, 2], ["Full", "Standard", "Minimal"], s.assist))
	_row(MenuRow.choice("Instruments", "hud_density", [-1, 0, 1, 2], ["Auto", "Glance", "Race", "Data"],
		s.hud_density))
	_row(MenuRow.range_row("Interface scale", "ui_scale", 0.8, 1.3, 0.05, s.ui_scale, pct))
	_row(MenuRow.choice("Colour palette", "palette", ["standard", "deuteranopia", "protanopia", "tritanopia"],
		["Standard", "Deuteranopia", "Protanopia", "Tritanopia"], s.palette))
	_row(MenuRow.toggle("Captions", "captions", s.captions))
	_sub("Online races may set a lower assist level for everyone.")


func _graphics() -> void:
	var s := settings
	_row(MenuRow.choice("Quality", "quality", [0, 1, 2], ["Low", "Medium", "High"], s.quality))
	var names := ["Auto"]
	var tree := get_tree() if is_inside_tree() else Engine.get_main_loop() as SceneTree
	if tree != null:
		var auto := s.render_scale
		s.render_scale = 0.0
		names[0] = "Auto (%s)" % pct(s.effective_render_scale(tree.root))
		s.render_scale = auto
	for v in Settings.RENDER_SCALES.slice(1):
		names.append(pct(v))
	_row(MenuRow.choice("Render scale", "render_scale", Settings.RENDER_SCALES, names, s.render_scale))
	_row(MenuRow.choice("Display", "fullscreen", [false, true], ["Windowed", "Fullscreen"], s.fullscreen))
	_row(MenuRow.toggle("Vertical sync", "vsync", s.vsync))
	_row(MenuRow.choice("Frame rate limit", "fps_limit", [0, 30, 60, 90, 120, 144],
		["Off", "30", "60", "90", "120", "144"], s.fps_limit))
	_sub("Medium suits the Steam Deck; Low suits integrated graphics. Render scale draws the 3D view at fewer pixels and sharpens it up to the screen (FSR); the HUD stays sharp.")


func _audio() -> void:
	var s := settings
	for e in [["Master", "master_volume"], ["Effects", "effects_volume"], ["Signals", "signals_volume"],
			["Voice", "voice_volume"], ["Ambience", "ambience_volume"], ["Interface", "interface_volume"]]:
		_row(MenuRow.range_row(e[0], e[1], 0.0, 1.0, 0.05, s.get(e[1]), pct))


## "camera_zoom_in" -> "Camera zoom in"
static func action_name(action: String) -> String:
	var t := action.replace("_", " ")
	return t.substr(0, 1).to_upper() + t.substr(1)


const JOY_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_BACK: "View",
	JOY_BUTTON_START: "Menu", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_DPAD_UP: "D-pad up",
	JOY_BUTTON_DPAD_DOWN: "D-pad down", JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}
const AXIS_NAMES := {
	JOY_AXIS_LEFT_X: ["Left stick left", "Left stick right"], JOY_AXIS_LEFT_Y: ["Left stick up", "Left stick down"],
	JOY_AXIS_RIGHT_X: ["Right stick left", "Right stick right"],
	JOY_AXIS_RIGHT_Y: ["Right stick up", "Right stick down"],
	JOY_AXIS_TRIGGER_LEFT: ["LT", "LT"], JOY_AXIS_TRIGGER_RIGHT: ["RT", "RT"],
}
const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "Left mouse", MOUSE_BUTTON_RIGHT: "Right mouse", MOUSE_BUTTON_MIDDLE: "Middle mouse",
	MOUSE_BUTTON_WHEEL_UP: "Wheel up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel down",
}


## The bindings of an action in the live input map, keys and mouse first, then the gamepad.
static func binding_text(action: String) -> String:
	if not InputMap.has_action(action):
		return "Not bound"
	var keys: Array[String] = []
	var pad: Array[String] = []
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k := e as InputEventKey
			var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			var shown := code
			if k.physical_keycode != KEY_NONE and DisplayServer.get_name() != "headless":
				shown = DisplayServer.keyboard_get_keycode_from_physical(code)  # the local key label
			var t := OS.get_keycode_string(shown if shown != KEY_NONE else code)
			if k.ctrl_pressed:
				t = "Ctrl + " + t
			if k.alt_pressed:
				t = "Alt + " + t
			if k.shift_pressed:
				t = "Shift + " + t
			keys.append(t)
		elif e is InputEventMouseButton:
			keys.append(MOUSE_NAMES.get((e as InputEventMouseButton).button_index, "Mouse"))
		elif e is InputEventJoypadButton:
			pad.append(JOY_NAMES.get((e as InputEventJoypadButton).button_index, "Pad"))
		elif e is InputEventJoypadMotion:
			var m := e as InputEventJoypadMotion
			var names: Array = AXIS_NAMES.get(m.axis, ["Stick", "Stick"])
			pad.append(names[0] if m.axis_value < 0 else names[1])
	var all := keys + pad
	return "Not bound" if all.is_empty() else "  ·  ".join(all)


func _input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var dir := 0
	if e is InputEventJoypadButton and e.pressed:
		var b := (e as InputEventJoypadButton).button_index
		dir = -1 if b == JOY_BUTTON_LEFT_SHOULDER else (1 if b == JOY_BUTTON_RIGHT_SHOULDER else 0)
	elif e is InputEventKey and e.pressed and not e.echo:
		var k := (e as InputEventKey).keycode
		dir = -1 if k == KEY_PAGEUP else (1 if k == KEY_PAGEDOWN else 0)
	if dir != 0:
		var i := posmod(SECTIONS.find(section) + dir, SECTIONS.size())
		show_section(SECTIONS[i])
		get_viewport().set_input_as_handled()


func _unhandled_input(e: InputEvent) -> void:
	if is_visible_in_tree() and e.is_action_pressed("ui_cancel") and not (esc_is_pause and e.is_action("pause_menu")):
		get_viewport().set_input_as_handled()
		close()


## Saves the settings and hands back.
func close() -> void:
	settings.save_file()
	closed.emit()
