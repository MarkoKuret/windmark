class_name MenuSounds
extends Node
## The menus' sounds (menus.md §4) on the `ui` bus: a tick when the focus moves or a value steps (quieter on the
## repeats of a held left or right, ECHO_DB), a click on accept, a lower one on back (only when back does something:
## `back_check`). Listens to the viewport's focus changes and to the ui_* actions while `active`. `played` logs every
## sound (tests), a quiet one as "<id>:quiet".

const FILES := {
	"focus": "res://audio/default/ui/focus.ogg",
	"accept": "res://audio/default/ui/accept.ogg",
	"back": "res://audio/default/ui/back.ogg",
}
const BUS := "ui"
## a held left or right steps the value on the key's repeats (MenuRow): each step ticks this much quieter, dB
const ECHO_DB := -10.0

## false: silent (a menu that is not shown)
var active := true
## headless runs log the sounds without starting players (as GameAudio does)
var audible := DisplayServer.get_name() != "headless"
var played: Array[String] = []
## returns false when back (Esc or B) does nothing where the menu is (the main menu's card with the focus on Quit):
## no back sound then; unset, back always sounds
var back_check: Callable

var _players := {}
var _quiet_focus := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioBuses.ensure()
	for id in FILES:
		var p := AudioStreamPlayer.new()
		p.name = id.capitalize()
		p.bus = BUS
		if ResourceLoader.exists(FILES[id]):
			p.stream = load(FILES[id])
		add_child(p)
		_players[id] = p
	get_viewport().gui_focus_changed.connect(_focus_changed)


func play(id: String, db := 0.0) -> void:
	if not active:
		return
	played.append(id if db == 0.0 else id + ":quiet")
	var p: AudioStreamPlayer = _players.get(id)
	if p != null:
		p.volume_db = db
	if audible and p != null and p.stream != null:
		p.play()


## The next focus change is the menu placing the focus itself (opening a page): no tick.
func quiet_next_focus() -> void:
	_quiet_focus = 1


func _focus_changed(_c: Control) -> void:
	if _quiet_focus > 0:
		_quiet_focus -= 1
		return
	play("focus")


func _input(e: InputEvent) -> void:
	if not active:
		return
	if e.is_echo():
		# a held left or right sweeps the value (MenuRow steps on the repeats): a quiet tick per step
		if e.is_action_pressed("ui_left", true) or e.is_action_pressed("ui_right", true):
			var f := get_viewport().gui_get_focus_owner()
			if f is BindingRow or (f is MenuRow and _steps(f as MenuRow, e.is_action_pressed("ui_right", true))):
				play("focus", ECHO_DB)
		return
	if e.is_action_pressed("ui_cancel"):
		if not back_check.is_valid() or back_check.call():
			play("back")
	elif e.is_action_pressed("ui_accept"):
		play("accept")
	elif e.is_action_pressed("ui_left") or e.is_action_pressed("ui_right"):
		var f := get_viewport().gui_get_focus_owner()
		if f is MenuRow or f is BindingRow:
			play("focus")
	elif e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var f := get_viewport().gui_get_focus_owner()
		if f != null and f.get_global_rect().has_point((e as InputEventMouseButton).position):
			play("accept")


## Whether a step of the row moves its value (a range stops at its ends, menus.md §4; choices wrap).
static func _steps(r: MenuRow, right: bool) -> bool:
	if r.kind == MenuRow.Kind.INFO:
		return false
	if r.kind != MenuRow.Kind.RANGE:
		return true
	var v := float(r.value)
	return v < r.max_value - 1e-6 if right else v > r.min_value + 1e-6
