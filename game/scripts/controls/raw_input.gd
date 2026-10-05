class_name RawInput
extends RefCounted
## One rendered frame of device input after the input map (controls.md §1): what InputReader fills from Godot's
## Input each frame, and what tests script directly. Buttons and keys are in `held` and `pressed`; sticks,
## triggers and the mouse have their own fields (they keep working under chat focus, controls.md §7).

## button actions held this frame: action name -> true
var held := {}
## button actions pressed this frame (rising edges), in press order
var pressed: Array[StringName] = []

## left stick X, raw [-1, 1] (the `helm` axis)
var helm_stick := 0.0
## RT (sheet in) and LT (sheet out), raw [0, 1]
var trigger_in := 0.0
var trigger_out := 0.0
## optional absolute sheet axis [-1, 1]; NAN when not bound
var sheet_axis := NAN
## right stick, raw [-1, 1] each (x right, y down as Godot reports it)
var right_stick := Vector2.ZERO
## left stick, raw (the free camera flies with it)
var left_stick := Vector2.ZERO
## mouse motion this frame while the orbit drag button is held, pixels
var mouse_drag := Vector2.ZERO
## mouse wheel notches this frame: + zoom in, - zoom out
var wheel := 0
## where the click or tap of a `boat_pick` press this frame was (viewport px); NAN when not given (controls.md §3)
var pointer := Vector2(NAN, NAN)
## the left button (or a touch) is dragging the camera this frame (controls.md §3 click or drag)
var pointer_drag := false
## a gamepad was the last device used (for the RB + LB zoom-out combo)
var gamepad := false


func is_held(action: StringName) -> bool:
	return held.get(action, false)


func was_pressed(action: StringName) -> bool:
	return pressed.has(action)


## Scripting helpers for tests.
func hold(action: StringName) -> RawInput:
	held[action] = true
	return self


func press(action: StringName) -> RawInput:
	held[action] = true
	pressed.append(action)
	return self


## A click (boat_pick) at a screen point, for tests.
func click(at: Vector2) -> RawInput:
	pressed.append(&"boat_pick")
	pointer = at
	return self


func copy() -> RawInput:
	var r := RawInput.new()
	r.held = held.duplicate()
	r.pressed = pressed.duplicate()
	r.helm_stick = helm_stick
	r.trigger_in = trigger_in
	r.trigger_out = trigger_out
	r.sheet_axis = sheet_axis
	r.right_stick = right_stick
	r.left_stick = left_stick
	r.mouse_drag = mouse_drag
	r.wheel = wheel
	r.pointer = pointer
	r.pointer_drag = pointer_drag
	r.gamepad = gamepad
	return r


## The same frame with every button and key released (chat focus, window focus lost).
func without_buttons() -> RawInput:
	var r := copy()
	r.held = {}
	r.pressed = []
	r.mouse_drag = Vector2.ZERO
	r.wheel = 0
	r.pointer = Vector2(NAN, NAN)
	r.pointer_drag = false
	return r
