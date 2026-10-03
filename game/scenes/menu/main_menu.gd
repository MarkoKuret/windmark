class_name MainMenu
extends Control
## The main menu (menus.md §1): Quick race, Free sail, Settings, Quit on the left, the chosen page on a cloth
## panel on the right. Start writes GameSetup.current() and changes to the sail scene.

signal scene_requested(path: String)

const SAIL_SCENE := "res://scenes/sail_test.tscn"

## tests: false keeps the menu from changing scene (scene_requested still fires)
var change_scenes := true
var settings: Settings
var buttons := {}
var pages := {}
var page := ""
var quick: SetupPanel
var free_sail: SetupPanel
var settings_panel: SettingsPanel

var _panel: PanelContainer
var _opener: Control


func _ready() -> void:
	theme = MenuTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	settings = Settings.current()
	settings.apply_display(get_tree().root)
	settings.apply_audio()
	var back := MenuBackdrop.new()
	back.name = "Backdrop"
	add_child(back)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	margin.add_child(row)

	# left: the name and the menu
	var left := VBoxContainer.new()
	left.name = "Left"
	left.custom_minimum_size = Vector2(280, 0)
	left.add_theme_constant_override("separation", 4)
	row.add_child(left)
	var title := MenuTheme.label("WINDMARK", MenuTheme.TITLE_SIZE, MenuTheme.NAVY)
	title.name = "Title"
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.spacing_glyph = 4
	fv.variation_embolden = 0.6
	title.add_theme_font_override("font", fv)
	left.add_child(title)
	left.add_child(MenuTheme.label("Tactical sailing races", MenuTheme.ROW_SIZE, MenuTheme.INK))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	var card := PanelContainer.new()
	card.name = "Menu"
	left.add_child(card)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	card.add_child(list)
	for e in [["quick", "Quick race"], ["free", "Free sail"], ["settings", "Settings"], ["quit", "Quit"]]:
		var b := MenuTheme.button(e[1])
		b.name = e[1].replace(" ", "")
		var id: String = e[0]
		b.pressed.connect(func() -> void: _pressed(id))
		list.add_child(b)
		buttons[id] = b
	var spacer2 := Control.new()
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer2.size_flags_stretch_ratio = 0.35
	left.add_child(spacer2)

	# right: the page
	_panel = PanelContainer.new()
	_panel.name = "Page"
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.visible = false
	row.add_child(_panel)
	quick = _setup_page(true)
	free_sail = _setup_page(false)
	settings_panel = SettingsPanel.new()
	settings_panel.build(settings)
	settings_panel.changed.connect(_setting_changed)
	settings_panel.closed.connect(close_page)
	_add_page("settings", settings_panel)
	buttons["quick"].grab_focus.call_deferred()


func _setup_page(race: bool) -> SetupPanel:
	var p := SetupPanel.new()
	p.build(race, settings.last_setup)
	p.start_pressed.connect(func() -> void: start(p))
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(p)
	_add_page("quick" if race else "free", scroll)
	return p


func _add_page(id: String, c: Control) -> void:
	c.visible = false
	pages[id] = c
	_panel.add_child(c)


func _pressed(id: String) -> void:
	if id == "quit":
		get_tree().quit()
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
	first.grab_focus.call_deferred()


func close_page() -> void:
	if page == "":
		return
	page = ""
	_panel.visible = false
	for k in pages:
		pages[k].visible = false
	if _opener != null:
		_opener.grab_focus()


func _unhandled_input(e: InputEvent) -> void:
	if page != "" and e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if page == "settings":
			settings_panel.close()
		else:
			close_page()


func _setting_changed(key: String) -> void:
	if key in ["fullscreen", "vsync", "fps_limit", "ui_scale", "render_scale", "capture_preset"]:
		settings.apply_display(get_tree().root)
	elif key.ends_with("_volume"):
		settings.apply_audio()


## Writes the session (menus.md §1), remembers the choices and asks for the sail scene.
func start(p: SetupPanel) -> void:
	if not p.can_start():
		return
	var g := GameSetup.current()
	p.write(g)
	var last := settings.last_setup.duplicate()
	last.merge(p.to_dict(), true)
	settings.last_setup = last
	settings.save_file()
	request_scene(SAIL_SCENE)


func request_scene(path: String) -> void:
	scene_requested.emit(path)
	if change_scenes:
		get_tree().change_scene_to_file(path)
