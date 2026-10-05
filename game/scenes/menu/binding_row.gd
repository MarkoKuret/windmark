class_name BindingRow
extends PanelContainer
## One action of the Bindings list (menus.md §3 Rebinding): its name and its slots (Key 1, Key 2 (, Key 3), Pad).
## Left and right pick the slot; Enter or A listens for the new binding (Esc or 5 s without input cancels); Delete,
## or the gamepad's X, clears the picked slot. A keyboard or mouse input goes to the picked Key slot (Key 1 when the
## Pad slot is picked), a gamepad input to the Pad slot. Conflicting slots are red.

signal rebound(action: String)

const LISTEN_S := 5.0
const SLOT_W := 104.0

var action := ""
var slot := 0
var listening := false
## slot index -> the other actions it conflicts with (refresh())
var conflicts := {}
var help := ""

var _name: Label
var _slots: Array[Label] = []
var _focused := false
var _listen_t := 0.0
var _mod_down := KEY_NONE


static func create(a: String) -> BindingRow:
	var r := BindingRow.new()
	r.action = a
	r._build()
	return r


func _build() -> void:
	name = "Bind_" + action
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 4)
	add_child(h)
	_name = MenuTheme.caps(SettingsPanel.action_name(action), MenuTheme.SMALL_SIZE, MenuTheme.INK)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(_name)
	for i in Bindings.kbm_count(action) + 1:
		var l := MenuTheme.label("", MenuTheme.SMALL_SIZE, MenuTheme.NAVY, 600)
		l.custom_minimum_size = Vector2(SLOT_W, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		h.add_child(l)
		_slots.append(l)
	focus_entered.connect(func() -> void: _focused = true; _style())
	focus_exited.connect(func() -> void:
		_focused = false
		cancel()
		_style())
	mouse_entered.connect(grab_focus)
	refresh()


func pad_slot() -> int:
	return _slots.size() - 1


## The slots' texts and conflicts from the input map (`snap`: a Bindings.snapshot() to reuse).
func refresh(snap := {}) -> void:
	if snap.is_empty():
		snap = Bindings.snapshot()
	var s: Array = snap.get(action, [])
	conflicts.clear()
	for i in _slots.size():
		var b: Array = s[i] if i < s.size() else []
		var c := Bindings.conflicts(action, i, snap)
		if not c.is_empty():
			conflicts[i] = c
		_slots[i].text = "-" if b.is_empty() else Bindings.text(b)
	_style()


func _style() -> void:
	var pad := Vector2(12, 5)
	add_theme_stylebox_override("panel", MenuTheme.focus_box(pad) if _focused
		else MenuTheme.box(Color(0, 0, 0, 0), 0, 2, pad))
	_name.add_theme_color_override("font_color", MenuTheme.SIGNAL if not conflicts.is_empty()
		else (MenuTheme.NAVY if _focused else MenuTheme.INK))
	for i in _slots.size():
		var l := _slots[i]
		var bad := conflicts.has(i)
		var picked := _focused and i == slot
		if picked and listening:
			l.text = "Press a button" if i == pad_slot() else "Press a key"
		var bg := Color(0, 0, 0, 0)
		var fg := MenuTheme.SIGNAL if bad else MenuTheme.NAVY
		if picked:
			bg = MenuTheme.SIGNAL if bad else MenuTheme.NAVY
			fg = MenuTheme.CLOTH_SOLID if bad else MenuTheme.ACCENT
		var sb := MenuTheme.box(bg, 0, 2, Vector2(4, 1))
		l.add_theme_stylebox_override("normal", sb)
		l.add_theme_color_override("font_color", fg)
	help = _help()


func _help() -> String:
	if listening:
		return "Press the new %s for %s. Esc cancels." % ["button or stick" if slot == pad_slot() else "key or mouse button",
			SettingsPanel.action_name(action)]
	var t := "Enter or A: change this binding. Delete or X: clear it. Left and right: pick the slot."
	if conflicts.has(slot):
		var names: Array = (conflicts[slot] as Array).map(func(a: String) -> String: return SettingsPanel.action_name(a))
		t = "Conflict: %s also has this binding." % ", ".join(names)
	return t


## Starts listening for the picked slot.
func listen() -> void:
	listening = true
	_listen_t = 0.0
	_mod_down = KEY_NONE
	set_process(true)
	_style()


func cancel() -> void:
	if not listening:
		return
	listening = false
	set_process(false)
	refresh()


func _process(dt: float) -> void:
	if not listening:
		set_process(false)
		return
	_listen_t += dt
	if _listen_t >= LISTEN_S:
		cancel()


## Binds `b` to the slot it belongs in (menus.md §3) and stops listening.
func bind(b: Array) -> void:
	var to := slot
	if Bindings.is_pad(b):
		to = pad_slot()
	elif to == pad_slot():
		to = 0
	Bindings.set_slot(action, to, b)
	slot = to
	listening = false
	set_process(false)
	rebound.emit(action)


func clear_slot() -> void:
	Bindings.set_slot(action, slot, [])
	rebound.emit(action)


func _input(e: InputEvent) -> void:
	if not listening:
		return
	if e is InputEventKey:
		var k := e as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		get_viewport().set_input_as_handled()
		if k.echo:
			return
		if k.pressed and code == KEY_ESCAPE:
			cancel()
			return
		var is_mod := code in [KEY_SHIFT, KEY_CTRL, KEY_ALT]
		if k.pressed and is_mod:
			_mod_down = code  # a combination may follow; alone it is bound on release
			return
		if not k.pressed:
			if is_mod and code == _mod_down:
				bind(["key", int(code), ""])
			return
		bind(Bindings.encode(k))
	elif e is InputEventMouseButton:
		get_viewport().set_input_as_handled()
		if (e as InputEventMouseButton).pressed:
			bind(Bindings.encode(e))
	elif e is InputEventJoypadButton:
		get_viewport().set_input_as_handled()
		if (e as InputEventJoypadButton).pressed:
			bind(Bindings.encode(e))
	elif e is InputEventJoypadMotion:
		if absf((e as InputEventJoypadMotion).axis_value) > 0.6:
			get_viewport().set_input_as_handled()
			bind(Bindings.encode(e))


func _gui_input(e: InputEvent) -> void:
	if listening:
		return
	if e.is_action_pressed("ui_left", true):
		slot = posmod(slot - 1, _slots.size())
		_style()
		accept_event()
	elif e.is_action_pressed("ui_right", true):
		slot = posmod(slot + 1, _slots.size())
		_style()
		accept_event()
	elif e.is_action_pressed("ui_accept"):
		listen()
		accept_event()
	elif (e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_DELETE) \
			or (e is InputEventJoypadButton and e.pressed and (e as InputEventJoypadButton).button_index == JOY_BUTTON_X):
		clear_slot()
		accept_event()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var x: float = (e as InputEventMouseButton).position.x
		for i in _slots.size():
			var r := _slots[i].get_global_rect()
			if x >= r.position.x - global_position.x and x <= r.end.x - global_position.x:
				slot = i
		listen()
		accept_event()
