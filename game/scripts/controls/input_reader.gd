class_name InputReader
extends Node
## Reads Godot's Input through the input map into a RawInput once per rendered frame (controls.md §1).
## Mouse drag, wheel and the trackpad gestures are collected from events between frames. A trackpad's two-finger
## scroll arrives as a pan gesture (on macOS never as wheel clicks) and its pinch as a magnify gesture
## (controls.md §3 Trackpad): a pan gesture keeps one axis, the larger component of its first event, until it has
## been quiet for PAN_GAP. The `boat_pick` button (left mouse, a touch arrives as it) is a click or a drag
## (controls.md §3): released within DRAG_PX of its press it is a pick at that point; moved further it drags the
## camera as the orbit button does, and picks nothing. A press a menu or panel takes (the GUI handles it first) is
## neither.

## controls.md §3: a press that moves more than this is a drag (viewport px)
const DRAG_PX := 8.0
## controls.md §3 Trackpad: a pan gesture ends after this long without an event (its glide counts as the gesture)
const PAN_GAP := 0.25

var _button_actions: Array[StringName] = []
var _drag := Vector2.ZERO
var _wheel := 0.0
var _pan := Vector2.ZERO
var _pan_axis := 0  # 0 none yet, 1 x, 2 y
var _pan_last := -1.0  # time of the last pan event, s
var _magnify := 1.0
var _gamepad := false
var _down := false
var _dragging := false
var _press_at := Vector2.ZERO
var _click := Vector2(NAN, NAN)


func _actions() -> Array[StringName]:
	if _button_actions.is_empty():
		var t := DefaultBindings.table()
		for a in t:
			if not t[a].has("axis") and a != "boat_pick":
				_button_actions.append(StringName(a))
	return _button_actions


## A pick press reaches the reader only when the GUI has not taken it.
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and e.is_action(&"boat_pick"):
		pointer_press((e as InputEventMouseButton).position)


## the boat_pick button went down at `at` (viewport px)
func pointer_press(at: Vector2) -> void:
	_down = true
	_dragging = false
	_press_at = at


## the pointer moved to `at` by `rel` (viewport px) with the pick button down: past DRAG_PX it is a camera drag
func pointer_move(at: Vector2, rel: Vector2) -> void:
	if not _down:
		return
	if _dragging:
		_drag += rel
		return
	var moved := at - _press_at
	if moved.length() > DRAG_PX:
		_dragging = true
		_drag += moved * (1.0 - DRAG_PX / moved.length())  # the motion past the threshold


## the pick button came up at `at`: a click when it did not drag
func pointer_release(at: Vector2) -> void:
	if _down and not _dragging:
		_click = at
	_down = false
	_dragging = false


## A pan gesture's delta at time `now` (s): the gesture's axis is chosen on its first event and kept until a gap
## of PAN_GAP, so a vertical scroll never jitters the orbit and a horizontal one never zooms
func pan_gesture(delta: Vector2, now: float) -> void:
	if _pan_axis == 0 or now - _pan_last > PAN_GAP:
		_pan_axis = 1 if absf(delta.x) > absf(delta.y) else 2
	_pan_last = now
	if _pan_axis == 1:
		_pan.x += delta.x
	else:
		_pan.y += delta.y


## A magnify gesture's factor (> 1 fingers apart)
func magnify_gesture(factor: float) -> void:
	if factor > 0.0:
		_magnify *= factor


func _input(e: InputEvent) -> void:
	if e is InputEventPanGesture:
		pan_gesture((e as InputEventPanGesture).delta, Time.get_ticks_msec() * 0.001)
		_gamepad = false
		return
	if e is InputEventMagnifyGesture:
		magnify_gesture((e as InputEventMagnifyGesture).factor)
		_gamepad = false
		return
	if e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if Input.is_action_pressed(&"camera_orbit_drag"):
			_drag += mm.relative
		elif _down:
			pointer_move(mm.position, mm.relative)
		_gamepad = false
	elif e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if not mb.pressed and _down and e.is_action(&"boat_pick"):
			pointer_release(mb.position)
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if e.is_action(&"camera_zoom_in"):
				_wheel += 1.0  # one notch per click, the event's own factor is not read (controls.md §4)
			elif e.is_action(&"camera_zoom_out"):
				_wheel -= 1.0
		_gamepad = false
	elif e is InputEventKey:
		_gamepad = false
	elif e is InputEventJoypadButton:
		_gamepad = true
	elif e is InputEventJoypadMotion and absf((e as InputEventJoypadMotion).axis_value) > 0.3:
		_gamepad = true


static func _raw(a: StringName) -> float:
	return Input.get_action_raw_strength(a) if InputMap.has_action(a) else 0.0


## This frame's input; drains the mouse drag, the wheel and the gestures.
func read() -> RawInput:
	var r := RawInput.new()
	for a in _actions():
		if not InputMap.has_action(a):
			continue
		if Input.is_action_pressed(a):
			r.held[a] = true
		if Input.is_action_just_pressed(a):
			r.pressed.append(a)
	r.helm_stick = _raw(&"helm_stick_right") - _raw(&"helm_stick_left")
	r.trigger_in = _raw(&"sheet_in_trigger")
	r.trigger_out = _raw(&"sheet_out_trigger")
	r.right_stick = Vector2(_raw(&"camera_look_right") - _raw(&"camera_look_left"),
		_raw(&"camera_look_down") - _raw(&"camera_look_up"))
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		r.left_stick = Vector2(Input.get_joy_axis(pads[0], JOY_AXIS_LEFT_X), Input.get_joy_axis(pads[0], JOY_AXIS_LEFT_Y))
	r.mouse_drag = _drag
	r.wheel = _wheel
	r.pan = _pan
	r.magnify = _magnify
	r.gamepad = _gamepad
	r.pointer_drag = _dragging
	if not is_nan(_click.x):
		r.pressed.append(&"boat_pick")
		r.pointer = _click
	_click = Vector2(NAN, NAN)
	_drag = Vector2.ZERO
	_wheel = 0.0
	_pan = Vector2.ZERO
	_magnify = 1.0
	return r
