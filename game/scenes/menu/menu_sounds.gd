class_name MenuSounds
extends Node
## The menus' sounds (menus.md §4) on the `ui` bus: a tick when the focus moves or a value steps, a click on
## accept, a lower one on back. Listens to the viewport's focus changes and to the ui_* actions while `active`.
## `played` logs every sound (tests).

const FILES := {
	"focus": "res://audio/default/ui/focus.ogg",
	"accept": "res://audio/default/ui/accept.ogg",
	"back": "res://audio/default/ui/back.ogg",
}
const BUS := "ui"

## false: silent (a menu that is not shown)
var active := true
## headless runs log the sounds without starting players (as GameAudio does)
var audible := DisplayServer.get_name() != "headless"
var played: Array[String] = []

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


func play(id: String) -> void:
	if not active:
		return
	played.append(id)
	var p: AudioStreamPlayer = _players.get(id)
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
	if not active or e.is_echo():
		return
	if e.is_action_pressed("ui_cancel"):
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
