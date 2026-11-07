class_name Bindings
extends RefCounted
## The player's bindings (controls.md §3, §6; menus.md §3 Rebinding) over the live InputMap: each action has
## keyboard or mouse slots (two, or as many as its defaults have) and one gamepad slot. A binding is stored as a
## small array: ["key", physical keycode, "shift,ctrl,alt"], ["mouse", button], ["button", joypad button] or
## ["axis", joypad axis, -1 or 1]. The settings file keeps only the actions that differ from the defaults.

const PAD := "pad"


## The binding of one event, [] for none.
static func encode(e: InputEvent) -> Array:
	if e is InputEventKey:
		var k := e as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		var mods := []
		if k.shift_pressed and not _is_mod(code, KEY_SHIFT):
			mods.append("shift")
		if k.ctrl_pressed and not _is_mod(code, KEY_CTRL):
			mods.append("ctrl")
		if k.alt_pressed and not _is_mod(code, KEY_ALT):
			mods.append("alt")
		return ["key", int(code), ",".join(mods)]
	if e is InputEventMouseButton:
		return ["mouse", int((e as InputEventMouseButton).button_index)]
	if e is InputEventJoypadButton:
		return ["button", int((e as InputEventJoypadButton).button_index)]
	if e is InputEventJoypadMotion:
		var m := e as InputEventJoypadMotion
		return ["axis", int(m.axis), -1 if m.axis_value < 0.0 else 1]
	return []


static func _is_mod(code: int, mod: Key) -> bool:
	return code == mod


## The event of a binding, null for [] or a malformed one.
static func decode(b: Array) -> InputEvent:
	if b.size() < 2:
		return null
	match str(b[0]):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(b[1]) as Key
			var mods := str(b[2]) if b.size() > 2 else ""
			k.shift_pressed = mods.contains("shift")
			k.ctrl_pressed = mods.contains("ctrl")
			k.alt_pressed = mods.contains("alt")
			k.device = -1
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(b[1]) as MouseButton
			m.device = -1
			return m
		"button":
			var j := InputEventJoypadButton.new()
			j.button_index = int(b[1]) as JoyButton
			j.device = -1
			return j
		"axis":
			if b.size() < 3:
				return null
			var a := InputEventJoypadMotion.new()
			a.axis = int(b[1]) as JoyAxis
			a.axis_value = -1.0 if int(b[2]) < 0 else 1.0
			a.device = -1
			return a
	return null


static func is_pad(b: Array) -> bool:
	return not b.is_empty() and str(b[0]) in ["button", "axis"]


## Keyboard or mouse slots of an action: two, or as many as its defaults have.
static func kbm_count(action: String) -> int:
	if not _kbm.has(action):
		var d: Dictionary = DefaultBindings.table().get(action, {})
		_kbm[action] = maxi(2, d.get("keys", []).size() + d.get("mouse", []).size())
	return _kbm[action]


static var _kbm := {}


## An action's slots from a list of events: [kbm 1, kbm 2 (, kbm 3), pad], each a binding or [].
static func slots_of(action: String, events: Array) -> Array:
	var kbm := []
	var pad := []
	var n := kbm_count(action)
	for e in events:
		var b := encode(e)
		if b.is_empty():
			continue
		if is_pad(b):
			if pad.is_empty():
				pad = b
		elif kbm.size() < n:
			kbm.append(b)
	while kbm.size() < n:
		kbm.append([])
	return kbm + [pad]


## The slots in the live input map.
static func slots(action: String) -> Array:
	return slots_of(action, InputMap.action_get_events(action) if InputMap.has_action(action) else [])


static var _defaults := {}
static var _actions: Array = []


## The actions of controls.md §3 in table order.
static func actions() -> Array:
	if _actions.is_empty():
		_actions = DefaultBindings.table().keys()
	return _actions


static func default_slots(action: String) -> Array:
	if not _defaults.has(action):
		_defaults[action] = slots_of(action, DefaultBindings.events(DefaultBindings.table().get(action, {})))
	return (_defaults[action] as Array).duplicate(true)


## Every action's live slots, action -> slots (one read of the input map for the conflict checks).
static func snapshot() -> Dictionary:
	var out := {}
	for a in actions():
		out[a] = slots(a)
	return out


## Puts an action's slots into the live input map.
static func set_slots(action: String, s: Array) -> void:
	if not InputMap.has_action(action):
		var t := DefaultBindings.table()
		InputMap.add_action(action, DefaultBindings.deadzone(t.get(action, {})))
	InputMap.action_erase_events(action)
	for b in s:
		var e := decode(b)
		if e != null:
			InputMap.action_add_event(action, e)


## One slot of an action: `b` a binding or [] to clear. Returns the new slots.
static func set_slot(action: String, slot: int, b: Array) -> Array:
	var s := slots(action)
	if slot >= 0 and slot < s.size():
		s[slot] = b
	set_slots(action, s)
	return s


## The defaults (controls.md §3), then the player's (`over`: action -> slots).
static func apply(over: Dictionary) -> void:
	DefaultBindings.apply_to_input_map()
	for a in over:
		if actions().has(a) and over[a] is Array:
			set_slots(a, over[a])


## The actions whose live slots differ from the defaults, action -> slots (what the settings file keeps).
static func overrides() -> Dictionary:
	var out := {}
	for a in actions():
		var s := slots(a)
		if s != default_slots(a):
			out[a] = s
	return out


## Whether the defaults give actions a and b a common input (a context pair of controls.md §3: not a conflict).
static func default_pair(a: String, b: String) -> bool:
	if not _defaults.has(a):
		default_slots(a)
	if not _defaults.has(b):
		default_slots(b)
	for x in _defaults[b]:
		if not (x as Array).is_empty() and (_defaults[a] as Array).has(x):
			return true
	return false


## The other actions that share slot `slot`'s binding of `action` and are not a default pair (menus.md §3).
## `snap`: a snapshot() to read instead of the input map.
static func conflicts(action: String, slot: int, snap := {}) -> Array:
	if snap.is_empty():
		snap = snapshot()
	var s: Array = snap.get(action, [])
	if slot < 0 or slot >= s.size() or (s[slot] as Array).is_empty():
		return []
	var out := []
	for o in actions():
		if o != action and (snap[o] as Array).has(s[slot]) and not default_pair(action, o):
			out.append(o)
	return out


## Every conflicting pair in the live map, [[action, other], ...] (each pair once).
static func all_conflicts() -> Array:
	var out := []
	var snap := snapshot()
	var t := actions()
	for i in t.size():
		var si: Array = snap[t[i]]
		for j in range(i + 1, t.size()):
			var sj: Array = snap[t[j]]
			for b in si:
				if not (b as Array).is_empty() and sj.has(b) and not default_pair(t[i], t[j]):
					out.append([t[i], t[j]])
					break
	return out


const JOY_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_BACK: "View",
	JOY_BUTTON_START: "Menu", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_DPAD_UP: "D-pad up",
	JOY_BUTTON_DPAD_DOWN: "D-pad down", JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}
const AXIS_NAMES := {
	JOY_AXIS_LEFT_X: ["Left stick left", "Left stick right"], JOY_AXIS_LEFT_Y: ["Left stick up", "Left stick down"],
	JOY_AXIS_RIGHT_X: ["Right stick left", "Right stick right"],
	JOY_AXIS_RIGHT_Y: ["Right stick up", "Right stick down"],
	JOY_AXIS_TRIGGER_LEFT: ["LT", "LT"], JOY_AXIS_TRIGGER_RIGHT: ["RT", "RT"],
}
const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "Left mouse", MOUSE_BUTTON_RIGHT: "Right mouse", MOUSE_BUTTON_MIDDLE: "Middle mouse",
	MOUSE_BUTTON_WHEEL_UP: "Wheel up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel down",
}


## A binding as the player reads it: the local key label, "Shift + F1", "Wheel up", "LB", "Left stick left".
static func text(b: Array) -> String:
	if b.is_empty():
		return ""
	match str(b[0]):
		"key":
			var code := int(b[1]) as Key
			var shown := code
			if DisplayServer.get_name() != "headless":
				shown = DisplayServer.keyboard_get_keycode_from_physical(code)  # the local key label
			var t := OS.get_keycode_string(shown if shown != KEY_NONE else code)
			var mods := str(b[2]) if b.size() > 2 else ""
			if mods.contains("ctrl"):
				t = "Ctrl + " + t
			if mods.contains("alt"):
				t = "Alt + " + t
			if mods.contains("shift"):
				t = "Shift + " + t
			return t
		"mouse":
			return MOUSE_NAMES.get(int(b[1]), "Mouse %d" % int(b[1]))
		"button":
			return JOY_NAMES.get(int(b[1]), "Pad %d" % int(b[1]))
		"axis":
			var names: Array = AXIS_NAMES.get(int(b[1]), ["Stick", "Stick"])
			return names[0] if int(b[2]) < 0 else names[1]
	return ""
