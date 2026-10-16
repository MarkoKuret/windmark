class_name MainMenu
extends Control
## The main menu (menus.md §1): Quick race, Free sail, Settings, Quit on the left, the chosen page on a cloth
## panel on the right (under them in a portrait window, the capture preset of menus.md §3). Start writes
## GameSetup.current() and changes to the sail scene (with the fade of menus.md §5). `open_on` opens a page when the
## menu starts (the results screen's Change setup: the race card with the setup it remembered).

signal scene_requested(path: String)

const SAIL_SCENE := "res://scenes/sail_test.tscn"
## the logo (menus.md §1.2): the wordmark scene
const WORDMARK_SCENE := "res://scenes/menu/wordmark.tscn"
## the space round the menu, px
const MARGIN := 40

## the page to open when the menu starts next ("quick": the race card), cleared when it has; "" none
static var open_on := ""

## tests: false keeps the menu from changing scene (scene_requested still fires)
var change_scenes := true
var settings: Settings
var buttons := {}
var pages := {}
var page := ""
var quick: SetupPanel
var free_sail: SetupPanel
var settings_panel: SettingsPanel

## the live backdrop (menus.md §4): off in tests that do not need it; `stage_scene` replaces the sail scene
## (tests: a missing path shows the fallback)
var live_backdrop := true
var stage_scene := MenuStage.SAIL_SCENE
## the live backdrop, null when it did not load (the painted backdrop is drawn then)
var stage: MenuStage
var backdrop: MenuBackdrop

## the line under Continue: what it starts
var continue_line: Label
## the first-launch screen while it shows (menus.md §1), else null
var welcome: WelcomePanel
var sounds: MenuSounds
var version_label: Label

var _panel: PanelContainer
var _opener: Control
var _left: Control
var _row: BoxContainer
var _mark: Control


func _ready() -> void:
	theme = MenuTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	settings = Settings.current()
	settings.apply_display(get_tree().root)
	settings.apply_audio()
	settings.apply_bindings()
	backdrop = MenuBackdrop.new()
	backdrop.name = "Backdrop"
	if live_backdrop:
		stage = MenuStage.new()
		stage.name = "StageDrift"
		add_child(stage)
		if stage.build(self, stage_scene):
			backdrop.draw_scene = false  # menus.md §4: the live scene; the painted one is the fallback
		else:
			stage.queue_free()
			stage = null
	backdrop.haze = true
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN)
	add_child(margin)
	var row := BoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	margin.add_child(row)
	_row = row

	# left: the name and the menu
	var left := VBoxContainer.new()
	left.name = "Left"
	left.custom_minimum_size = Vector2(280, 0)
	left.add_theme_constant_override("separation", 4)
	row.add_child(left)
	_left = left
	# the logo, top left (menus.md §1.2)
	if ResourceLoader.exists(WORDMARK_SCENE):
		var mark := (load(WORDMARK_SCENE) as PackedScene).instantiate()
		mark.name = "Wordmark"
		mark.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		left.add_child(mark)
		_mark = mark
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	var card := PanelContainer.new()
	card.name = "Menu"
	left.add_child(card)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	card.add_child(list)
	for e in [["continue", "Continue"], ["quick", "Quick race"], ["free", "Free sail"], ["settings", "Settings"],
			["quit", "Quit"]]:
		var b := MenuTheme.button(e[1], MenuTheme.ITEM_SIZE, e[0] == "quit")
		b.name = e[1].replace(" ", "")
		var id: String = e[0]
		b.pressed.connect(func() -> void: _pressed(id))
		list.add_child(b)
		buttons[id] = b
		if id == "continue":
			continue_line = MenuTheme.label("", MenuTheme.SMALL_SIZE - 1, MenuTheme.MUTED, 600)
			continue_line.name = "ContinueLine"
			var pad := MarginContainer.new()
			pad.add_theme_constant_override("margin_left", 18)
			pad.add_theme_constant_override("margin_bottom", 6)
			pad.add_child(continue_line)
			list.add_child(pad)
	_refresh_continue()
	var spacer2 := Control.new()
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer2.size_flags_stretch_ratio = 0.35
	left.add_child(spacer2)

	# right: the page
	_panel = PanelContainer.new()
	_panel.name = "Page"
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.visible = false
	row.add_child(_panel)
	_fit()
	get_viewport().size_changed.connect(_fit)
	quick = _setup_page(true)
	free_sail = _setup_page(false)
	settings_panel = SettingsPanel.new()
	settings_panel.build(settings)
	settings_panel.changed.connect(_setting_changed)
	settings_panel.closed.connect(close_page)
	_add_page("settings", settings_panel)
	# the build in the bottom-right corner (menus.md §1)
	version_label = MenuTheme.label(BuildInfo.text(), MenuTheme.SMALL_SIZE - 3, Color(1, 1, 1, 0.75), 600, 0.04)
	version_label.name = "Version"
	version_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	version_label.add_theme_constant_override("shadow_offset_y", 1)
	version_label.anchor_left = 1.0
	version_label.anchor_right = 1.0
	version_label.anchor_top = 1.0
	version_label.anchor_bottom = 1.0
	version_label.offset_left = -320.0
	version_label.offset_right = -12.0
	version_label.offset_top = -30.0
	version_label.offset_bottom = -8.0
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	version_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(version_label)
	sounds = MenuSounds.new()
	sounds.name = "Sounds"
	add_child(sounds)
	if not settings.welcomed:
		_show_welcome()
	elif open_on in ["quick", "free", "settings"]:
		var id := open_on
		open_on = ""
		open_page.call_deferred(id)
	else:
		_first_focus().grab_focus.call_deferred()


## Continue when it is there, else Quick race (menus.md §1).
func _first_focus() -> Control:
	return buttons["continue"] if buttons["continue"].visible else buttons["quick"]


## The first-launch screen (menus.md §1): over the backdrop, the menu hidden until it is done.
func _show_welcome() -> void:
	welcome = WelcomePanel.new()
	welcome.build(settings, get_tree().root.size)
	_row.visible = false
	var center := CenterContainer.new()
	center.name = "Welcome"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(minf(560.0, get_viewport_rect().size.x - 48.0), 0)
	card.add_child(welcome)
	center.add_child(card)
	add_child(center)
	welcome.done.connect(func(_keep: bool) -> void:
		center.queue_free()
		welcome = null
		_row.visible = true
		if stage != null:
			stage.apply_settings(settings)
		_refresh_continue()
		_first_focus().grab_focus())
	welcome.first_row().grab_focus.call_deferred()


## Continue shows when the remembered setup can start again (menus.md §1), with what it starts under it.
func _refresh_continue() -> void:
	var ok := can_continue()
	buttons["continue"].visible = ok
	continue_line.get_parent().visible = ok
	if ok:
		continue_line.text = continue_text()


## Whether the last remembered setup can start: a mode, and its class, venue (and course) still on disk.
func can_continue() -> bool:
	var last := settings.last_setup
	var mode := str(last.get("mode", ""))
	if not mode in ["race", "free"]:
		return false
	var cls := str(last.get("class_id", ""))
	var ven := str(last.get("venue", ""))
	if not MenuData.ids(MenuData.classes()).has(cls) or not MenuData.ids(MenuData.venues()).has(ven):
		return false
	return mode == "free" or MenuData.ids(MenuData.courses(ven, cls)).has(str(last.get("course", "")))


## "Quick race · Practice Waters · 10 boats" or "Free sail · Practice Waters"
func continue_text() -> String:
	var last := settings.last_setup
	var ven := MenuData.name_of(MenuData.venues(), str(last.get("venue", "")))
	if str(last.get("mode", "")) == "race":
		return "Quick race · %s · %d boats" % [ven, int(last.get("fleet_size", 10))]
	return "Free sail · %s" % ven


## Starts the last remembered setup again with a new seed (menus.md §1).
func continue_last() -> void:
	if not can_continue():
		return
	var last := settings.last_setup
	var g := GameSetup.current()
	var d := GameSetup.new()
	g.mode = str(last["mode"])
	g.class_id = str(last["class_id"])
	g.venue = str(last["venue"])
	g.livery = str(last.get("livery", d.livery)) if last.get("livery") != null else ""
	g.course = str(last.get("course", d.course))
	g.fleet_size = int(last.get("fleet_size", d.fleet_size))
	g.ai_level = str(last.get("ai_level", d.ai_level))
	g.wind_kn = float(last.get("wind_kn", d.wind_kn))
	g.wind_from_deg = float(last.get("wind_from_deg", d.wind_from_deg))
	g.shift = str(last.get("shift", d.shift))
	g.gusts = str(last.get("gusts", d.gusts))
	# the weather mode the venue still offers (a venue without conditions: Custom only, menus.md §1)
	var modes := VenueWeather.modes(MenuData.venue_info(g.venue))
	g.weather = str(last.get("weather", d.weather))
	if not modes.has(g.weather):
		g.weather = modes[0]
	var light := SetupPanel.light_from(last, g.venue, g.weather)
	g.light_time = light["light_time"]
	g.light_conditions = light["light_conditions"]
	g.seed = 0
	request_scene(SAIL_SCENE)


## Menu beside the page, or above it in a portrait window (too narrow for both side by side); the logo scaled
## down when the window is narrower than it and the margins (menus.md §1.2).
func _fit() -> void:
	var s := get_viewport_rect().size
	_row.vertical = s.y > s.x
	var mark := _mark as Wordmark
	if mark == null:
		return
	var room := s.x - 2 * MARGIN
	if not _row.vertical:
		# beside the page: leave the race card its two columns (§1.1) when that costs the logo at most 10 %
		var pad := _panel.get_theme_stylebox("panel")
		var beside := room - _row.get_theme_constant("separation") - SetupPanel.TWO_COLUMNS_MIN \
			- pad.get_content_margin(SIDE_LEFT) - pad.get_content_margin(SIDE_RIGHT)
		if beside >= mark.natural_size(roundi(0.9 * Wordmark.SIZE)).x:
			room = minf(room, beside)
	mark.fit_width(room)


func _setup_page(race: bool) -> SetupPanel:
	var p := SetupPanel.new()
	p.build(race, settings.last_setup)
	p.start_pressed.connect(func() -> void: start(p))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_page("quick" if race else "free", p)
	return p


func _add_page(id: String, c: Control) -> void:
	c.visible = false
	pages[id] = c
	_panel.add_child(c)


func _pressed(id: String) -> void:
	if id == "quit":
		get_tree().quit()
		return
	if id == "continue":
		continue_last()
		return
	open_page(id)


func open_page(id: String) -> void:
	_opener = buttons.get(id)
	page = id
	_panel.visible = true
	for k in pages:
		pages[k].visible = k == id
	if id != "settings":
		(quick if id == "quick" else free_sail).load_from(settings.last_setup)
	var first: Control = (quick if id == "quick" else free_sail if id == "free" else settings_panel).first_row()
	if sounds != null:
		sounds.quiet_next_focus()
	first.grab_focus.call_deferred()


func close_page() -> void:
	if page == "":
		return
	page = ""
	_panel.visible = false
	for k in pages:
		pages[k].visible = false
	if _opener != null:
		if sounds != null:
			sounds.quiet_next_focus()
		_opener.grab_focus()


func _unhandled_input(e: InputEvent) -> void:
	if welcome != null:
		return
	if page != "" and e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if page == "settings":
			settings_panel.close()
		else:
			close_page()


func _setting_changed(key: String) -> void:
	if key in ["fullscreen", "vsync", "fps_limit", "ui_scale", "render_scale", "capture_preset"]:
		settings.apply_display(get_tree().root, key in ["fullscreen", "capture_preset"])
	elif key.ends_with("_volume"):
		settings.apply_audio()
	if stage != null and key in ["quality", "reduced_motion"]:
		stage.apply_settings(settings)
	elif stage != null and key in ["fullscreen", "vsync", "fps_limit", "ui_scale", "render_scale", "capture_preset"]:
		stage.apply_frame_cap(settings)  # menus.md §4: apply_display put the player's limit back


## Writes the session (menus.md §1), remembers the choices and asks for the sail scene.
func start(p: SetupPanel) -> void:
	if not p.can_start():
		return
	var g := GameSetup.current()
	p.write(g)
	var last := settings.last_setup.duplicate()
	last.merge(p.to_dict(), true)
	last["mode"] = p.mode
	settings.last_setup = last
	settings.save_file()
	_refresh_continue()
	request_scene(SAIL_SCENE)


func request_scene(path: String) -> void:
	scene_requested.emit(path)
	if change_scenes:
		SceneFade.change(get_tree(), path)
