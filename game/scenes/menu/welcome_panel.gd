class_name WelcomePanel
extends VBoxContainer
## The first-launch screen (menus.md §1): two choices before the menu, Steering (the helm key mode, the controls
## preset) and Quality, then Skip (keeps the defaults; Esc or B too) or Let's sail (keeps them, the primary action,
## on the right as on every footer). Either sets `welcomed` and saves, so it shows once.

signal done(keep: bool)

var settings: Settings
var rows := {}
var go_button: Button
var skip_button: Button


func build(s: Settings, _screen: Vector2i) -> void:
	settings = s
	name = "WelcomePanel"
	add_theme_constant_override("separation", MenuTheme.LIST_GAP)
	add_child(MenuTheme.heading("Welcome aboard"))
	add_child(MenuTheme.gap())
	var list := MenuTheme.list()
	list.name = "Rows"
	add_child(list)
	var steer := MenuRow.choice("Steering", "helm_mode", [0, 1], ["Set and hold", "Hold to steer"], s.helm_mode)
	steer.help = SettingsPanel.HELP["helm_mode"]
	_add(list, steer)
	_add(list, MenuRow.choice("Quality", "quality", [0, 1, 2], ["Low", "Medium", "High"], s.quality))
	rows["quality"].help = "The detail of the sea, the sky and the shadows. Preselected for this computer's graphics."
	var help := MenuTheme.help_label(steer.help)
	help.name = "Help"
	add_child(help)
	for k in rows:
		var r: MenuRow = rows[k]
		r.focus_entered.connect(func() -> void: help.text = r.help)
	add_child(MenuTheme.gap())
	skip_button = MenuTheme.button("Skip", MenuTheme.ACTION_SIZE)
	skip_button.name = "Skip"
	skip_button.pressed.connect(func() -> void: finish(false))
	go_button = MenuTheme.button("Let's sail", MenuTheme.ACTION_SIZE)
	go_button.name = "Go"
	MenuTheme.set_primary(go_button)
	go_button.pressed.connect(func() -> void: finish(true))
	add_child(MenuTheme.footer([skip_button], [go_button]))


func _add(list: Control, r: MenuRow) -> void:
	rows[r.key] = r
	list.add_child(r)


func first_row() -> Control:
	return rows["helm_mode"]


## Keeps the choices (or the defaults with `keep` false), marks the screen as shown and saves.
func finish(keep: bool) -> void:
	var d := Settings.device_defaults()
	settings.helm_mode = rows["helm_mode"].value if keep else d.helm_mode
	settings.quality = rows["quality"].value if keep else d.quality
	settings.welcomed = true
	settings.save_file()
	done.emit(keep)


func _unhandled_input(e: InputEvent) -> void:
	if is_visible_in_tree() and e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		finish(false)
