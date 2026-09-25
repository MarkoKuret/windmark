class_name InputReader
extends Node
## Reads Godot's Input through the input map into a RawInput once per rendered frame (controls.md §1).
## Mouse drag and wheel are collected from events between frames.

var _button_actions: Array[StringName] = []
var _drag := Vector2.ZERO
var _wheel := 0
var _gamepad := false


func _actions() -> Array[StringName]:
	if _button_actions.is_empty():
		var t := DefaultBindings.table()
		for a in t:
			if not t[a].has("axis"):
				_button_actions.append(StringName(a))
	return _button_actions


func _input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		if Input.is_action_pressed(&"camera_orbit_drag"):
			_drag += (e as InputEventMouseMotion).relative
		_gamepad = false
	elif e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if e.is_action(&"camera_zoom_in"):
				_wheel += 1
			elif e.is_action(&"camera_zoom_out"):
				_wheel -= 1
		_gamepad = false
	elif e is InputEventKey:
		_gamepad = false
	elif e is InputEventJoypadButton:
		_gamepad = true
	elif e is InputEventJoypadMotion and absf((e as InputEventJoypadMotion).axis_value) > 0.3:
		_gamepad = true


static func _raw(a: StringName) -> float:
	return Input.get_action_raw_strength(a) if InputMap.has_action(a) else 0.0


## This frame's input; drains the mouse drag and wheel.
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
	r.gamepad = _gamepad
	_drag = Vector2.ZERO
	_wheel = 0
	return r
