class_name DefaultBindings
extends RefCounted
## The default bindings of controls.md §3 as data: the one source for the [input] section of project.godot
## (written by write_input_map.gd) and for the rebinding reset. Keys are bound by physical position.
##
## Entry: action -> {"keys": [[physical keycode, modifiers], ...], "mouse": [button, ...],
## "joy": joypad button or -1, "axis": [joypad axis, direction] or []}. Modifiers: "shift", "ctrl", "alt".
##
## Actions of controls.md §2 that are an axis or a device pair get suffixes here: `helm` is
## helm_stick_left/right (left stick X), the sheet triggers are sheet_in_trigger/sheet_out_trigger (RT/LT),
## `camera_orbit` is camera_orbit_left/right/up/down (keys), camera_look_left/right/up/down (right stick) and
## camera_orbit_drag (right mouse button). Gamepad combos and context rules (RB + LB zoom out, LB boost in the
## free camera, RB/LB/R3 spectating when not racing) are resolved in InputReader, PlayerControls and the Hud
## (View tap or hold), not in the map. `hail` and `protest` are online only (controls.md §2): keys, no pad button,
## not listed in the settings until online play exists (Bindings.online_play). Steam Deck: the default Steam Input template presents the
## gamepad bindings below; its Deck-only items (L4 helm_fine, right trackpad orbit, Steam + R1 screenshot) are
## template entries (game/README.md).

const AXIS_DEADZONE := 0.02  # our own dead zones and curves do the rest (controls.md §4, §5)
const BUTTON_DEADZONE := 0.5


static func _k(code: Key, mods: String = "") -> Array:
	return [code, mods]


static func table() -> Dictionary:
	var t := {}
	# boat
	t["helm_left"] = {"keys": [_k(KEY_LEFT), _k(KEY_A)]}
	t["helm_right"] = {"keys": [_k(KEY_RIGHT), _k(KEY_D)]}
	t["helm_stick_left"] = {"axis": [JOY_AXIS_LEFT_X, -1]}
	t["helm_stick_right"] = {"axis": [JOY_AXIS_LEFT_X, 1]}
	t["helm_centre"] = {"keys": [_k(KEY_DOWN)], "joy": JOY_BUTTON_LEFT_STICK}
	t["helm_fine"] = {"keys": [_k(KEY_SHIFT)], "joy": JOY_BUTTON_LEFT_SHOULDER}
	t["sheet_in"] = {"keys": [_k(KEY_W)]}
	t["sheet_out"] = {"keys": [_k(KEY_S)]}
	t["sheet_in_trigger"] = {"axis": [JOY_AXIS_TRIGGER_RIGHT, 1]}
	t["sheet_out_trigger"] = {"axis": [JOY_AXIS_TRIGGER_LEFT, 1]}
	t["let_fly"] = {"keys": [_k(KEY_SPACE)], "joy": JOY_BUTTON_A}
	t["auto_trim"] = {"keys": [_k(KEY_T)], "joy": JOY_BUTTON_DPAD_DOWN}
	var digits := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
	for i in 9:
		t["sail_%d" % (i + 1)] = {"keys": [_k(digits[i])]}
	t["sail_prev"] = {"joy": JOY_BUTTON_DPAD_LEFT}
	t["sail_next"] = {"joy": JOY_BUTTON_DPAD_RIGHT}
	t["sail_set"] = {"joy": JOY_BUTTON_X}
	t["drop_front"] = {"keys": [_k(KEY_0)], "joy": JOY_BUTTON_B}
	t["hail"] = {"keys": [_k(KEY_H)]}
	t["protest"] = {"keys": [_k(KEY_P)]}
	# cameras
	t["camera_next"] = {"keys": [_k(KEY_C)], "joy": JOY_BUTTON_Y}
	t["camera_chase"] = {"keys": [_k(KEY_F5)]}
	t["camera_onboard"] = {"keys": [_k(KEY_F6)]}
	t["camera_aerial"] = {"keys": [_k(KEY_F7)]}
	t["camera_free"] = {"keys": [_k(KEY_F8)]}
	t["camera_orbit_left"] = {"keys": [_k(KEY_KP_4), _k(KEY_J)]}
	t["camera_orbit_right"] = {"keys": [_k(KEY_KP_6), _k(KEY_L)]}
	t["camera_orbit_up"] = {"keys": [_k(KEY_KP_8), _k(KEY_I)]}
	t["camera_orbit_down"] = {"keys": [_k(KEY_KP_2), _k(KEY_K)]}
	t["camera_orbit_drag"] = {"mouse": [MOUSE_BUTTON_RIGHT]}
	t["camera_look_left"] = {"axis": [JOY_AXIS_RIGHT_X, -1]}
	t["camera_look_right"] = {"axis": [JOY_AXIS_RIGHT_X, 1]}
	t["camera_look_up"] = {"axis": [JOY_AXIS_RIGHT_Y, -1]}
	t["camera_look_down"] = {"axis": [JOY_AXIS_RIGHT_Y, 1]}
	t["camera_zoom_in"] = {"keys": [_k(KEY_KP_9), _k(KEY_O)], "mouse": [MOUSE_BUTTON_WHEEL_UP],
		"joy": JOY_BUTTON_RIGHT_SHOULDER}
	t["camera_zoom_out"] = {"keys": [_k(KEY_KP_7), _k(KEY_U)], "mouse": [MOUSE_BUTTON_WHEEL_DOWN]}
	t["camera_fov"] = {"keys": [_k(KEY_ALT)]}
	t["camera_recentre"] = {"keys": [_k(KEY_KP_5), _k(KEY_R)], "joy": JOY_BUTTON_RIGHT_STICK}
	var fkeys := [KEY_F1, KEY_F2, KEY_F3, KEY_F4]
	for i in 4:
		t["camera_preset_%d" % (i + 1)] = {"keys": [_k(fkeys[i])]}
		t["camera_preset_%d" % (i + 5)] = {"keys": [_k(fkeys[i], "shift")]}
	t["camera_preset_store"] = {"keys": [_k(KEY_CTRL)]}
	t["camera_boost"] = {"keys": [_k(KEY_SHIFT)], "joy": JOY_BUTTON_LEFT_SHOULDER}
	t["camera_clip"] = {"keys": [_k(KEY_X)]}
	# HUD and race
	t["rankings"] = {"keys": [_k(KEY_TAB)]}
	# gamepad View: a tap is hud_density, a hold the ranking list (resolved in the Hud, controls.md §3)
	t["rankings_pad"] = {"joy": JOY_BUTTON_BACK}
	t["hud_density"] = {"keys": [_k(KEY_G)]}
	t["map"] = {"keys": [_k(KEY_M)], "joy": JOY_BUTTON_DPAD_UP}
	t["radar_zoom_in"] = {"keys": [_k(KEY_EQUAL)]}
	t["radar_zoom_out"] = {"keys": [_k(KEY_MINUS)]}
	t["radar_orientation"] = {"keys": [_k(KEY_Z)]}
	t["hud_hide"] = {"keys": [_k(KEY_F10)]}
	t["world_tags"] = {"keys": [_k(KEY_SLASH)]}
	t["boat_names"] = {"keys": [_k(KEY_N)]}
	t["boat_select"] = {"keys": [_k(KEY_B)]}
	t["boat_pick"] = {"mouse": [MOUSE_BUTTON_LEFT]}
	t["spectate_next"] = {"keys": [_k(KEY_BRACKETRIGHT)], "joy": JOY_BUTTON_RIGHT_SHOULDER}
	t["spectate_prev"] = {"keys": [_k(KEY_BRACKETLEFT)], "joy": JOY_BUTTON_LEFT_SHOULDER}
	t["spectate_leader"] = {"keys": [_k(KEY_HOME)], "joy": JOY_BUTTON_RIGHT_STICK}
	t["chat"] = {"keys": [_k(KEY_ENTER)]}
	t["pause_menu"] = {"keys": [_k(KEY_ESCAPE)], "joy": JOY_BUTTON_START}
	# capture (controls.md §7): clean pause and slow motion, offline only
	t["capture_pause"] = {"keys": [_k(KEY_PERIOD)]}
	t["capture_slow"] = {"keys": [_k(KEY_COMMA)]}
	t["screenshot"] = {"keys": [_k(KEY_F12)]}
	t["reset_boat"] = {"keys": [_k(KEY_BACKSPACE)]}
	return t


## The InputEvents of one entry.
static func events(entry: Dictionary) -> Array[InputEvent]:
	var ev: Array[InputEvent] = []
	for k in entry.get("keys", []):
		var e := InputEventKey.new()
		e.physical_keycode = k[0]
		var mods: String = k[1]
		e.shift_pressed = mods.contains("shift")
		e.ctrl_pressed = mods.contains("ctrl")
		e.alt_pressed = mods.contains("alt")
		e.device = -1
		ev.append(e)
	for b in entry.get("mouse", []):
		var m := InputEventMouseButton.new()
		m.button_index = b
		m.device = -1
		ev.append(m)
	if entry.get("joy", -1) >= 0:
		var j := InputEventJoypadButton.new()
		j.button_index = entry["joy"]
		j.device = -1
		ev.append(j)
	var ax: Array = entry.get("axis", [])
	if not ax.is_empty():
		var a := InputEventJoypadMotion.new()
		a.axis = ax[0]
		a.axis_value = float(ax[1])
		a.device = -1
		ev.append(a)
	return ev


static func deadzone(entry: Dictionary) -> float:
	return AXIS_DEADZONE if entry.has("axis") else BUTTON_DEADZONE


## Replaces the live InputMap with the defaults (rebinding reset; tests).
static func apply_to_input_map() -> void:
	var t := table()
	for action in t:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action, deadzone(t[action]))
		for e in events(t[action]):
			InputMap.action_add_event(action, e)
