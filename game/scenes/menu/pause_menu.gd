class_name PauseMenu
extends CanvasLayer
## The in-race pause menu (menus.md §2, controls.md §7): Resume, Restart, Settings, Quit to menu.
##
## Instanced as a child of the sail scene, it follows the scene's own pause: the scene's `pause_menu` key pauses
## its SimRunner (`runner.paused`), the menu opens over it and holds the boat's controls (`controls.menu_open`);
## Resume or `pause_menu` again closes it. It also applies the player's settings to the scene when it starts and
## when the settings screen closes (Settings.apply_to_scene). Without such a host, open() and close() drive it.

signal action_requested(action: String)

const MAIN_MENU := "res://scenes/menu/main_menu.tscn"

## tests: false keeps restart and quit from changing scene (action_requested still fires)
var act := true
var host: Node
var is_open := false
var buttons := {}
var settings_panel: SettingsPanel

var _root: Control
var _card: PanelContainer
var _list: VBoxContainer
var _settings_card: PanelContainer
var _was_paused := false


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
	_card.custom_minimum_size = Vector2(340, 0)
	center.add_child(_card)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_card.add_child(_list)
	_list.add_child(MenuTheme.heading("Paused"))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	_list.add_child(gap)
	for e in [["resume", "Resume"], ["restart", "Restart"], ["settings", "Settings"], ["quit", "Quit to menu"]]:
		var b := MenuTheme.button(e[1])
		b.name = e[1].replace(" ", "")
		var id: String = e[0]
		b.pressed.connect(func() -> void: _pressed(id))
		_list.add_child(b)
		buttons[id] = b

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 120)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	_root.add_child(margin)
	_settings_card = PanelContainer.new()
	_settings_card.name = "SettingsCard"
	_settings_card.visible = false
	margin.add_child(_settings_card)
	settings_panel = SettingsPanel.new()
	settings_panel.esc_is_pause = true
	settings_panel.build(Settings.current())
	settings_panel.changed.connect(_setting_changed)
	settings_panel.closed.connect(_settings_closed)
	_settings_card.add_child(settings_panel)
	_root.visible = false
	_apply.call_deferred()


func _host_runner() -> Object:
	if host == null:
		return null
	var r: Variant = host.get("runner")
	return r if r is SimRunner else null


func _apply() -> void:
	Settings.current().apply_to_scene(host)
	if host == null or not host.is_inside_tree():
		Settings.current().apply_display(get_tree().root)


func _process(_dt: float) -> void:
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
	_root.visible = true
	_card.visible = true
	_settings_card.visible = false
	var r := _host_runner()
	if r != null:
		r.paused = true
		_was_paused = true
	_hold_controls(true)
	_host_label(false)
	buttons["resume"].grab_focus.call_deferred()


## Closes the menu and resumes the host.
func close() -> void:
	if _settings_card.visible:
		settings_panel.close()
	is_open = false
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
			close()
			action_requested.emit(id)
			if act:
				if get_tree().current_scene != null:
					get_tree().reload_current_scene()
				elif host != null and host.has_method("reset_boat"):
					host.reset_boat()
		"quit":
			close()
			action_requested.emit(id)
			if act:
				get_tree().change_scene_to_file(MAIN_MENU)


func _setting_changed(key: String) -> void:
	if key in ["fullscreen", "vsync", "fps_limit", "ui_scale", "render_scale", "capture_preset"]:
		Settings.current().apply_display(get_tree().root)


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
		close()
	elif _card.visible and e.is_action_pressed("ui_cancel") and not e.is_action("pause_menu"):
		get_viewport().set_input_as_handled()
		close()
