class_name WelcomePanel
extends VBoxContainer
## The first-launch screen (menus.md §1): two choices before the menu, Steering (the helm key mode, the controls
## preset) and Quality, then Let's sail (keeps them) or Skip (keeps the defaults; Esc or B too). Either sets
## `welcomed` and saves, so it shows once.

signal done(keep: bool)

var settings: Settings
var rows := {}
var go_button: Button
var skip_button: Button


func build(s: Settings, _screen: Vector2i) -> void:
	settings = s
	name = "WelcomePanel"
	add_theme_constant_override("separation", 4)
	add_child(MenuTheme.heading("Welcome aboard"))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	add_child(gap)
	var steer := MenuRow.choice("Steering", "helm_mode", [0, 1], ["Set and hold", "Hold to steer"], s.helm_mode)
	steer.help = "Set and hold: a tap moves the helm and it stays. Hold to steer: it comes back when you let go."
	_add(steer)
	_add(MenuRow.choice("Quality", "quality", [0, 1, 2], ["Low", "Medium", "High"], s.quality))
	var help := MenuTheme.label(steer.help, MenuTheme.SMALL_SIZE, MenuTheme.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(0, 40)
	add_child(help)
	rows["quality"].help = "The detail of the sea, the sky and the shadows. Preselected for this computer's graphics."
	for k in rows:
		var r: MenuRow = rows[k]
		r.focus_entered.connect(func() -> void: help.text = r.help)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 8)
	add_child(gap2)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	add_child(foot)
	go_button = MenuTheme.button("Let's sail", MenuTheme.ACTION_SIZE)
	go_button.name = "Go"
	MenuTheme.set_primary(go_button)
	go_button.pressed.connect(func() -> void: finish(true))
	foot.add_child(go_button)
	skip_button = MenuTheme.button("Skip", MenuTheme.ACTION_SIZE)
	skip_button.name = "Skip"
	skip_button.pressed.connect(func() -> void: finish(false))
	foot.add_child(skip_button)


func _add(r: MenuRow) -> void:
	rows[r.key] = r
	add_child(r)


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
