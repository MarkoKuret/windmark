class_name PauseMenu
extends CanvasLayer
## The in-race pause menu (menus.md §2, controls.md §7): Resume, Restart, Retire (a quick race until the player's race
## is over: a second press within 3 s retires her; Restart and Main menu ask the same way in that window),
## Settings, Main menu. Scene changes fade (SceneFade).
##
## Instanced as a child of the sail scene, it follows the scene's own pause: the scene's `pause_menu` key pauses
## its SimRunner (`runner.paused`), the menu opens over it and holds the boat's controls (`controls.menu_open`);
## Resume or `pause_menu` again closes it. It also applies the player's settings to the scene when it starts and
## when the settings screen closes (Settings.apply_to_scene). Without such a host, open() and close() drive it.

signal action_requested(action: String)

const MAIN_MENU := "res://scenes/menu/main_menu.tscn"
## menus.md §2: Retire (and, while the race is on, Restart and Main menu) ask again for this long
const RETIRE_CONFIRM_S := 3.0
const RETIRE_TEXT := "Retire"
const RETIRE_ASK := "Retire? Press again"
## the card's least width, px
const CARD_W := 400.0
## the items that ask, their plain text and the question (menus.md §2)
const ITEM_TEXT := {"restart": "Restart", "retire": RETIRE_TEXT, "quit": "Main menu"}
const ASK_TEXT := {"restart": "Restart? Press again", "retire": RETIRE_ASK, "quit": "Leave the race? Press again"}

## tests: false keeps restart and quit from changing scene (action_requested still fires)
var act := true
var host: Node
var is_open := false
var buttons := {}
var settings_panel: SettingsPanel
## the menu sounds (menus.md §4), heard while the menu is open
var sounds: MenuSounds

var _root: Control
var _card: PanelContainer
var _list: VBoxContainer
var _margin: MarginContainer
var _settings_card: PanelContainer
var _was_paused := false
## the item asking ("" none) and the seconds left to confirm it, 0 when not asking
var _ask_id := ""
var _ask_t := 0.0


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	host = get_parent()
	_root = Control.new()
	_root.name = "Root"
	_root.theme = MenuTheme.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := MenuBackdrop.new()
	dim.draw_scene = false
	dim.dim = 0.45
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_card = PanelContainer.new()
	_card.name = "Card"
	_card.custom_minimum_size = Vector2(CARD_W, 0)
	center.add_child(_card)
	_list = MenuTheme.list()
	_card.add_child(_list)
	_list.add_child(MenuTheme.heading("Paused"))
	_list.add_child(MenuTheme.gap())
	for e in [["resume", "Resume"], ["restart", "Restart"], ["retire", RETIRE_TEXT], ["settings", "Settings"],
			["quit", "Main menu"]]:
		var b := MenuTheme.button(e[1], MenuTheme.ITEM_SIZE, e[0] == "retire")
		b.name = e[1].replace(" ", "")
		var id: String = e[0]
		b.pressed.connect(func() -> void: _pressed(id))
		b.focus_entered.connect(func() -> void:
			if _ask_id != "" and _ask_id != id:
				_ask("", false))  # moving to another item drops the question (menus.md §2)
		_list.add_child(b)
		buttons[id] = b

	# the settings screen: a page as wide as the main menu's, centred, inside the screen margins (menus.md §4)
	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_margin)
	_settings_card = PanelContainer.new()
	_settings_card.name = "SettingsCard"
	_settings_card.visible = false
	_margin.add_child(_settings_card)
	_fit()
	get_viewport().size_changed.connect(_fit)
	settings_panel = SettingsPanel.new()
	settings_panel.esc_is_pause = true
	settings_panel.build(Settings.current())
	settings_panel.changed.connect(_setting_changed)
	settings_panel.closed.connect(_settings_closed)
	_settings_card.add_child(settings_panel)
	_root.visible = false
	sounds = MenuSounds.new()
	sounds.name = "Sounds"
	sounds.active = false
	add_child(sounds)
	_apply.call_deferred()


## The settings page's room (menus.md §4): the screen margins, and no wider than a wide page of the main menu.
func _fit() -> void:
	var s := get_viewport().get_visible_rect().size
	var pad := _settings_card.get_theme_stylebox("panel")
	var pads := pad.get_content_margin(SIDE_LEFT) + pad.get_content_margin(SIDE_RIGHT)
	var side := maxf(MenuTheme.MARGIN, floorf((s.x - MenuTheme.PAGE_MAX - pads) / 2.0))
	for name in ["margin_left", "margin_right"]:
		_margin.add_theme_constant_override(name, int(side))
	for name in ["margin_top", "margin_bottom"]:
		_margin.add_theme_constant_override(name, MenuTheme.MARGIN)


func _host_runner() -> Object:
	if host == null:
		return null
	var r: Variant = host.get("runner")
	return r if r is SimRunner else null


func _apply() -> void:
	Settings.current().apply_to_scene(host)
	if host == null or not host.is_inside_tree():
		Settings.current().apply_display(get_tree().root)


func _process(dt: float) -> void:
	if _ask_t > 0.0:
		_ask_t -= dt
		if _ask_t <= 0.0:
			_ask("", false)
	var r := _host_runner()
	if r == null:
		return
	var paused: bool = r.paused
	if paused != _was_paused:
		_was_paused = paused
		if paused and not is_open:
			open()
		elif not paused and is_open:
			close()


## Opens the menu (and pauses the host's simulation).
func open() -> void:
	is_open = true
	sounds.active = true
	sounds.quiet_next_focus()
	_root.visible = true
	_card.visible = true
	_settings_card.visible = false
	var r := _host_runner()
	if r != null:
		r.paused = true
		_was_paused = true
	_hold_controls(true)
	_host_label(false)
	_ask("", false)
	buttons["retire"].visible = can_retire()
	buttons["resume"].grab_focus.call_deferred()


## Retire shows in a quick race until the player's race is over (menus.md §2).
func can_retire() -> bool:
	return host != null and host.has_method("can_retire") and bool(host.call("can_retire"))


## `id` asks (its text becomes the question for RETIRE_CONFIRM_S), or nobody asks with `on` false.
func _ask(id: String, on: bool) -> void:
	_ask_id = id if on else ""
	_ask_t = RETIRE_CONFIRM_S if on else 0.0
	for k in ITEM_TEXT:
		buttons[k].text = String(ASK_TEXT[k] if on and k == id else ITEM_TEXT[k]).to_upper()


## The confirm step (menus.md §2): false on the first press (the item asks), true on the second within the time.
func _confirmed(id: String) -> bool:
	if _ask_id == id and _ask_t > 0.0:
		_ask("", false)
		return true
	_ask(id, true)
	return false


## Restart's seed (menus.md §2): the one the running session was made with, so the reload is the same race again
## (Race again on the results screen is the one that draws a new day); 0 without a host that has one.
func restart_seed() -> int:
	var s: Variant = host.get("world_seed") if host != null else null
	return int(s) if s is int else 0


## Restart and Main menu ask first while the player's race is on, the window of Retire (menus.md §2).
func _asks_first() -> bool:
	return can_retire()


## Closes the menu and resumes the host.
## The pause key while the settings show (menus.md §2): back to the card, the menu stays open. True when taken.
func back_from_settings() -> bool:
	if not is_open or not _settings_card.visible:
		return false
	settings_panel.close()
	return true


func close() -> void:
	if _settings_card.visible:
		settings_panel.close()
	is_open = false
	sounds.active = false
	_root.visible = false
	var r := _host_runner()
	if r != null:
		r.paused = false
		_was_paused = false
	_hold_controls(false)
	_host_label(false)


func _hold_controls(on: bool) -> void:
	var pc: Variant = host.get("controls") if host != null else null
	if pc is PlayerControls:
		pc.menu_open = on


## The sail scene's own "Paused" line sits where the menu does: hidden while the menu is there.
func _host_label(on: bool) -> void:
	var l := host.get_node_or_null("HudLayer/Paused") if host != null else null
	if l is CanvasItem:
		l.visible = on


func _pressed(id: String) -> void:
	match id:
		"resume":
			close()
		"settings":
			_card.visible = false
			_settings_card.visible = true
			settings_panel.show_section(settings_panel.section, true)
		"restart":
			if _asks_first() and not _confirmed(id):
				return
			close()
			action_requested.emit(id)
			if act:
				if get_tree().current_scene != null:
					GameSetup.restart_seed = restart_seed()
					SceneFade.reload(get_tree())
				elif host != null and host.has_method("reset_boat"):
					host.reset_boat()
		"retire":
			if not _confirmed(id):
				return
			action_requested.emit(id)
			if host != null and host.has_method("retire"):
				host.call("retire")
			close()
		"quit":
			if _asks_first() and not _confirmed(id):
				return
			close()
			action_requested.emit(id)
			if act:
				MainMenu.open_on = ""
				SceneFade.change(get_tree(), MAIN_MENU)


## A setting applies at once, as on the main menu (menus.md §2, §3): the display on the window, the rest (volumes,
## quality, controls, cameras, HUD) on the running scene.
func _setting_changed(key: String) -> void:
	if key in ["fullscreen", "vsync", "fps_limit", "ui_scale", "render_scale", "aa", "capture_preset"]:
		Settings.current().apply_display(get_tree().root, key in ["fullscreen", "capture_preset"])
	else:
		Settings.current().apply_live(host, key)


func _settings_closed() -> void:
	Settings.current().apply_to_scene(host)
	if is_open:
		_settings_card.visible = false
		_card.visible = true
		buttons["settings"].grab_focus.call_deferred()


func _unhandled_input(e: InputEvent) -> void:
	if not is_open:
		return
	if _host_runner() == null and e.is_action_pressed("pause_menu"):
		get_viewport().set_input_as_handled()
		if not back_from_settings():
			close()
	elif _card.visible and e.is_action_pressed("ui_cancel") and not e.is_action("pause_menu"):
		get_viewport().set_input_as_handled()
		close()
